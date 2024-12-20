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

# TODO track with updatecli
provider "cloudinit" {
  # Required by the EKS module
}

# TODO track with updatecli
provider "null" {
  # Required by the EKS module
}

# TODO track with updatecli
provider "time" {
  # Required by the EKS module
}

# TODO track with updatecli
provider "tls" {
  # Required by the EKS module
}

# TODO track with updatecli
provider "kubernetes" {
  alias = "cijenkinsio-agents-2"

  host                   = module.cijenkinsio_agents_2.cluster_endpoint
  cluster_ca_certificate = base64decode(module.cijenkinsio_agents_2.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cijenkinsio-agents-2.token
}

# TODO track with updatecli
provider "helm" {
  alias = "cijenkinsio-agents-2"

  kubernetes {
    host                   = module.cijenkinsio_agents_2.cluster_endpoint
    token                  = data.aws_eks_cluster_auth.cijenkinsio-agents-2.token
    cluster_ca_certificate = base64decode(module.cijenkinsio_agents_2.cluster_certificate_authority_data)
  }
}
