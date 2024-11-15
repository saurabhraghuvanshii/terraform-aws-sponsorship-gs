####################################################################################
# ci.jenkins.io resources
####################################################################################

### DNS Zone delegated from Azure DNS (jenkins-infra/azure-net)
# `updatecli` maintains sync between the 2 repositories using the infra reports (see outputs.tf)
resource "aws_route53_zone" "aws_ci_jenkins_io" {
  name = "aws.ci.jenkins.io"

  tags = local.common_tags
}
