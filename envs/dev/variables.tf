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
}

variable "kube_proxy_addon_version" {
  type        = string
  description = "Version of the Kube Proxy addon"
}

variable "vpc_cni_addon_version" {
  type        = string
  description = "Version of the VPC CNI addon"
}

variable "aws_ebs_csi_driver_addon_version" {
  type        = string
  description = "Version of the AWS EBS CSI Driver addon"
}