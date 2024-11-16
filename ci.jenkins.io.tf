####################################################################################
# ci.jenkins.io resources
####################################################################################

### Network resources
resource "aws_eip" "ci_jenkins_io" {
  domain = "vpc"
}

resource "aws_eip_association" "ci_jenkins_io" {
  instance_id   = aws_instance.ci_jenkins_io.id
  allocation_id = aws_eip.ci_jenkins_io.id
}

### Compute Resources
resource "aws_key_pair" "ci_jenkins_io" {
  key_name = "ci-jenkins-io"
  # Private key 'id_jenkins-infra-team' encrypted in our SOPS vault
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDKvZ23dkvhjSU0Gxl5+mKcBOwmR7gqJDYeA1/Xzl3otV4CtC5te5Vx7YnNEFDXD6BsNkFaliXa34yE37WMdWl+exIURBMhBLmOPxEP/cWA5ZbXP//78ejZsxawBpBJy27uQhdcR0zVoMJc8Q9ShYl5YT/Tq1UcPq2wTNFvnrBJL1FrpGT+6l46BTHI+Wpso8BK64LsfX3hKnJEGuHSM0GAcYQSpXAeGS9zObKyZpk3of/Qw/2sVilIOAgNODbwqyWgEBTjMUln71Mjlt1hsEkv3K/VdvpFNF8VNq5k94VX6Rvg5FQBRL5IrlkuNwGWcBbl8Ydqk4wrD3b/PrtuLBEUsqbNhLnlEvFcjak+u2kzCov73csN/oylR0Tkr2y9x2HfZgDJVtvKjkkc4QERo7AqlTuy1whGfDYsioeabVLjZ9ahPjakv9qwcBrEEF+pAya7Q3AgNFVSdPgLDEwEO8GUHaxAjtyXXv9+yPdoDGmG3Pfn3KqM6UZjHCxne3Dr5ZE="
}

resource "aws_instance" "ci_jenkins_io" {
  ami           = "ami-0700ac71a4832f3b3" # Ubuntu 22.04 - arm64 - 2024-11-15 (no need to update it unless if recreating the VM)
  instance_type = "m8g.xlarge"            # 4vcpu 16Go https://aws.amazon.com/fr/ec2/instance-types/

  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  vpc_security_group_ids = [
    aws_security_group.restricted_in_ssh.id,
    aws_security_group.unrestricted_in_http.id,
    aws_security_group.unrestricted_out_http.id,
    aws_security_group.allow_out_puppet_jenkins_io.id,
    aws_security_group.ci_jenkins_io_controller.id,
  ]

  key_name = aws_key_pair.ci_jenkins_io.key_name

  disable_api_termination = true # Protect ourselves from accidental deletion

  user_data = templatefile("${path.root}/.shared-tools/terraform/cloudinit.tftpl", { hostname = local.ci_jenkins_io_fqdn, admin_username = "ubuntu" })

  root_block_device {
    delete_on_termination = false # Even if we terminate the machine
    encrypted             = true
    volume_type           = "gp3"
    volume_size           = 300

    tags = local.common_tags

  }

  ebs_optimized = true

  metadata_options {
    # EC2 recommends setting IMDSv2 to required - https://aws.amazon.com/blogs/security/get-the-full-benefits-of-imdsv2-and-disable-imdsv1-across-your-aws-infrastructure/
    http_tokens = "required"
  }

  tags = merge(
    local.common_tags,
    { "Name" = "ci-jenkins-io" }
  )
}

### DNS Zone delegated from Azure DNS (jenkins-infra/azure-net)
# `updatecli` maintains sync between the 2 repositories using the infra reports (see outputs.tf)
resource "aws_route53_zone" "aws_ci_jenkins_io" {
  name = local.ci_jenkins_io_fqdn

  tags = local.common_tags
}

resource "aws_route53_record" "a_aws_ci_jenkins_io" {
  zone_id = aws_route53_zone.aws_ci_jenkins_io.zone_id
  name    = local.ci_jenkins_io_fqdn
  type    = "A"
  ttl     = 60
  records = [aws_eip.ci_jenkins_io.public_ip]
}

resource "aws_route53_record" "aaaa_aws_ci_jenkins_io" {
  zone_id = aws_route53_zone.aws_ci_jenkins_io.zone_id
  name    = local.ci_jenkins_io_fqdn
  type    = "AAAA"
  ttl     = 60
  records = aws_instance.ci_jenkins_io.ipv6_addresses
}
