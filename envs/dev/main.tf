# EKS Cluster

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "opsfleet-eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "karpenter.sh/discovery"                    = var.cluster_name
  }
}

data "aws_availability_zones" "available" {}

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
      most_recent              = false
      addon_version            = var.vpc_cni_addon_version
      before_compute           = true
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
      instance_types = ["t3.medium","m5.large"]

      min_size     = 2
      max_size     = 10
      desired_size = 2
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  create_node_iam_role = false
  node_iam_role_arn    = module.eks.eks_managed_node_groups["karpenter"].iam_role_arn

  # Since the node group role will already have an access entry
  create_access_entry = false

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "karpenter-node-instance-profile"
  role = module.karpenter.node_iam_role_name
}

# arm64 and x86 node classes and provisioners
resource "kubectl_manifest" "arm_node_class" {
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1beta1
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
apiVersion: karpenter.k8s.aws/v1beta1
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
apiVersion: karpenter.sh/v1beta1
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
apiVersion: karpenter.sh/v1beta1
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
