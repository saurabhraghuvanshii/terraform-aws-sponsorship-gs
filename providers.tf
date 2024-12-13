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

provider "kubernetes" {
  alias                  = "cijenkinsio-agents-2"
  host                   = module.cijenkinsio-agents-2.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cijenkinsio-agents-2.cluster_certificate_authority_data)
}
