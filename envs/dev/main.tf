###############################################################################
# VPC
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "opsfleet-eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
    "Environment"                               = "dev"
    "Terraform"                                 = "true"
  }

  default_security_group_tags = {
    "Environment" = "dev"
    "Terraform"   = "true"
  }
}

data "aws_availability_zones" "available" {}

###############################################################################
# EKS Cluster
###############################################################################

module "eks" {
  source                          = "terraform-aws-modules/eks/aws"
  version                         = "20.8.4"
  cluster_name                    = var.cluster_name
  cluster_version                 = "1.30"
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = false
  cluster_addons = {
    coredns = {
      most_recent   = false
      addon_version = var.core_dns_addon_version
    }
    kube-proxy = {
      most_recent   = false
      addon_version = var.kube_proxy_addon_version
    }
    vpc-cni = {
      most_recent    = false
      addon_version  = var.vpc_cni_addon_version
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent   = false
      addon_version = var.aws_ebs_csi_driver_addon_version
    }
  }

  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  enable_irsa = true

  # EKS Managed Node Group(s)
  eks_managed_node_group_defaults = {
    instance_types = ["t3.medium", "m5.large", "t4g.medium", "m6g.large"]
  }

  eks_managed_node_groups = {
    karpenter = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium", "m5.large"]

      min_size     = 2
      max_size     = 10
      desired_size = 2
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }

  cluster_security_group_tags = {
    Environment = "dev"
    Terraform   = "true"
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
    "Environment"            = "dev"
    "Terraform"              = "true"
  }
}

###############################################################################
# Karpenter
###############################################################################

module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name          = module.eks.cluster_name
  enable_v1_permissions = true

  enable_pod_identity             = true
  create_pod_identity_association = true

  create_instance_profile = true

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    AmazonEBSCSIDriverPolicy     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

###############################################################################
# Karpenter Helm
###############################################################################

resource "helm_release" "karpenter" {
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  chart               = "karpenter"
  version             = "1.0.0"
  wait                = false

  values = [
    <<-EOT
    serviceAccount:
      name: ${module.karpenter.service_account}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${module.karpenter.queue_name}
    EOT
  ]
}

###############################################################################
# Karpenter Kubectl
###############################################################################

resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            name: default
          requirements:
            - key: "karpenter.k8s.aws/instance-category"
              operator: In
              values: ["c", "m", "r"]
            - key: "karpenter.k8s.aws/instance-cpu"
              operator: In
              values: ["4", "8", "16", "32"]
            - key: "karpenter.k8s.aws/instance-hypervisor"
              operator: In
              values: ["nitro"]
            - key: "karpenter.k8s.aws/instance-generation"
              operator: Gt
              values: ["2"]
      limits:
        cpu: 1000
      disruption:
        consolidationPolicy: WhenEmpty
        consolidateAfter: 30s
  YAML

  depends_on = [
    kubectl_manifest.arm_node_class,
    kubectl_manifest.x86_node_class,

  ]
}

# arm64 and x86 node classes and provisioners
resource "kubectl_manifest" "arm_node_class" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: arm64
spec:
  amiFamily: AL2
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${var.cluster_name}
  securityGroupSelectorTerms:
    - tags:
        "aws:eks:cluster-name": ${var.cluster_name}
  instanceTypes:
    - t4g.medium
    - m6g.large
  tags:
    Name: karpenter-arm64
YAML
}

resource "kubectl_manifest" "x86_node_class" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: x86
spec:
  amiFamily: AL2
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${var.cluster_name}
  securityGroupSelectorTerms:
    - tags:
        "aws:eks:cluster-name": ${var.cluster_name}
  instanceTypes:
    - t3.medium
    - m5.large
  tags:
    Name: karpenter-x86
YAML
}

resource "kubectl_manifest" "arm_provisioner" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: Provisioner
metadata:
  name: arm64
spec:
  requirements:
    - key: kubernetes.io/arch
      operator: In
      values: [arm64]
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
  providerRef:
    name: arm64
  ttlSecondsAfterEmpty: 30
YAML
}

resource "kubectl_manifest" "x86_provisioner" {
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1
kind: Provisioner
metadata:
  name: x86
spec:
  requirements:
    - key: kubernetes.io/arch
      operator: In
      values: [amd64]
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
  providerRef:
    name: x86
  ttlSecondsAfterEmpty: 30
YAML
}

