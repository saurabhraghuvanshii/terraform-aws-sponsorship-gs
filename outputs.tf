resource "local_file" "jenkins_infra_data_report" {
  content = jsonencode({
    "${local.ci_jenkins_io["controller_vm_fqdn"]}" = {
      "name_servers" = aws_route53_zone.aws_ci_jenkins_io.name_servers,
      "outbound_ips" = {
        "agents" = module.vpc.nat_public_ips,
        "controller" = concat(
          aws_instance.ci_jenkins_io.ipv6_addresses, # Public IPv6(s) (usually list of one element)
          [aws_eip.ci_jenkins_io.public_ip],         # Public IPv4 of the controller
        ),
      },
      "ec2-agents" = {
        "subnet_ids" = [module.vpc.private_subnets[0]],
        "security_group_names" = [
          aws_security_group.ephemeral_vm_agents.name,
          aws_security_group.unrestricted_out_http.name,
        ]
      },
      "cijenkinsio-agents-2" = {
        "cluster_endpoint" = module.cijenkinsio_agents_2.cluster_endpoint,
        "node_groups" = {
          "applications" = {
            "labels"      = module.cijenkinsio_agents_2.eks_managed_node_groups["applications"].node_group_labels
            "tolerations" = local.cijenkinsio_agents_2["node_groups"]["applications"]["tolerations"],
          },
        }

      },
    },

  })
  filename = "${path.module}/jenkins-infra-data-reports/aws-sponsorship.json"
}
output "jenkins_infra_data_report" {
  value = local_file.jenkins_infra_data_report.content
}
