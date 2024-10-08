locals {
  cluster_name   = "aws-sponso"
  aws_account_id = "326712726440"
  region         = "us-east-1a"
  common_tags = {
    "scope"      = "terraform-managed"
    "repository" = "jenkins-infra/terraform-aws-sponsorship"
  }
}
