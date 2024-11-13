locals {
  cluster_name   = "aws-sponso"
  aws_account_id = "326712726440"
  region         = "us-east-2"
  our_az         = format("${local.region}%s", "b")
  ## Tracked bu updatecli from the following source: https://reports.jenkins.io/jenkins-infra-data-reports/azure-net.json
  ## Note: we use strings with space separator to manage type changes in updatecli's HCL parser
  # permanent agent of update_center2
  outbound_ips_trusted_ci_jenkins_io = "104.209.128.236 172.177.128.34 172.210.175.108 172.210.170.228"
  # Infra.ci / Release CI controllers
  outbound_ips_privatek8s_jenkins_io = "20.65.63.127"
  # Terraform management and Docker-packaging build
  outbound_ips_infracijenkinsioagents1_jenkins_io = "20.122.14.108 20.186.70.154"
  # Connections routed through the VPN
  outbound_ips_private_vpn_jenkins_io = "172.176.126.194"

  outbound_ips = {
    "trusted.ci.jenkins.io"              = split(" ", local.outbound_ips_trusted_ci_jenkins_io)
    "privatek8s.jenkins.io"              = split(" ", local.outbound_ips_privatek8s_jenkins_io)
    "infracijenkinsioagents1.jenkins.io" = split(" ", local.outbound_ips_infracijenkinsioagents1_jenkins_io)
    "private.vpn.jenkins.io"             = split(" ", local.outbound_ips_private_vpn_jenkins_io)
  }

  common_tags = {
    "scope"      = "terraform-managed"
    "repository" = "jenkins-infra/terraform-aws-sponsorship"
  }
}
