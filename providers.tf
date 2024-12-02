provider "aws" {
  region = local.region
  # profile = var.aws_profile
  assume_role {
    role_arn = "arn:aws:iam::326712726440:role/infra-developer"
  }

  default_tags {
    tags = local.common_tags
  }
}

provider "local" {
}

provider "cloudinit" {
  # Required by the EKS module
}

provider "null" {
  # Required by the EKS module
}

provider "time" {
  # Required by the EKS module
}

provider "tls" {
  # Required by the EKS module
}
