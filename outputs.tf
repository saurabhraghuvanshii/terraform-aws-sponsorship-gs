resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "aws.ci.jenkins.io" = {
      "name_servers" = aws_route53_zone.aws_ci_jenkins_io.name_servers,
      "outbound_ips" = {
        "agents" = module.vpc.nat_public_ips,
      },
    },
  })
  filename = "${path.module}/jenkins-infra-data-reports/aws-sponsorship.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}
