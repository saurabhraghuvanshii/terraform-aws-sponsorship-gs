locals {
  cluster_name   = "aws-sponso"
  aws_account_id = "326712726440"
  region         = "us-east-2"
  our_az         = format("${local.region}%s", "b")
  common_tags = {
    "scope"      = "terraform-managed"
    "repository" = "jenkins-infra/terraform-aws-sponsorship"
  }
}
