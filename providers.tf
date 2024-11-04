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

provider "kubernetes" {
  alias                  = "cik8s"
  host                   = module.cik8s.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cik8s.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cik8s.token
}
