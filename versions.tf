
terraform {
  required_version = ">= 1.10, <1.11"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    local = {
      source = "hashicorp/local"
    }
    # TODO track with updatecli
    # Required by the EKS module
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
    # TODO track with updatecli
    # Required by the EKS module
    null = {
      source = "hashicorp/null"
    }
    # TODO track with updatecli
    # Required by the EKS module
    time = {
      source = "hashicorp/time"
    }
    # TODO track with updatecli
    # Required by the EKS module
    tls = {
      source = "hashicorp/tls"
    }
    # TODO track with updatecli
    # Required by the EKS module
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    # TODO track with updatecli
    # Required by the EKS module
    helm = {
      source = "hashicorp/helm"
    }
  }
}
