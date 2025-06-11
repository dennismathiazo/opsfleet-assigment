provider "aws" {
  region = var.region
}

terraform {
  required_version = ">= 1.3.2"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
    }
  }

  backend "s3" {
    bucket         = "opsfleet-eks-tf-state"
    key            = "terraform/state.tfstate"
    region         = "us-east-1"
    dynamodb_table = "opsfleet-eks-tf-state-table"
    encrypt        = true
  }
}

provider "kubernetes" {
  host                   = dependency.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode("${dependency.cluster.outputs.cluster_certificate_authority_data}")
  exec {
    api_version = "client.authentication.k8s.io/v1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
}