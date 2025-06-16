variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "opsfleet-eks"
}

variable "tags" {
  type = map(string)
  default = {
    Environment = "dev"
    Terraform   = "true"
  }
}

variable "kubernetes_host" {
  description = "Kubernetes API server endpoint"
  type        = string
}

variable "kubernetes_token" {
  description = "Kubernetes authentication token"
  type        = string
}

variable "kubernetes_ca_cert" {
  description = "Kubernetes cluster CA certificate (base64 encoded)"
  type        = string
}

variable "core_dns_addon_version" {
  type        = string
  description = "Version of the Core DNS addon"
  default = "v1.11.3-eksbuild.2"
}

variable "kube_proxy_addon_version" {
  type        = string
  description = "Version of the Kube Proxy addon"
  default = "v1.31.2-eksbuild.3"
}

variable "vpc_cni_addon_version" {
  type        = string
  description = "Version of the VPC CNI addon"
  default = "v1.19.0-eksbuild.1"
}

variable "aws_ebs_csi_driver_addon_version" {
  type        = string
  description = "Version of the AWS EBS CSI Driver addon"
  default = "v1.37.0-eksbuild.1"
}
