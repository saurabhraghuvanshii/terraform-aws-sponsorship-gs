####################################################################################
# Network security resources (Netowrk ACL and Security Groups)
####################################################################################

### Network ACLs
resource "aws_network_acl" "ci_jenkins_io_controller" {
  # Do NOT use the "default_vpc_id" module output ;)
  vpc_id     = module.vpc.vpc_id
  subnet_ids = [module.vpc.public_subnets[0]]

  ## Get started with https://docs.aws.amazon.com/vpc/latest/userguide/custom-network-acl.html

  # Allow inbound HTTP from Internet
  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }
  ingress {
    protocol        = "tcp"
    rule_no         = 105
    action          = "allow"
    ipv6_cidr_block = "::/0"
    from_port       = 80
    to_port         = 80
  }

  # Allow inbound HTTPS from Internet
  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  ingress {
    protocol        = "tcp"
    rule_no         = 115
    action          = "allow"
    ipv6_cidr_block = "::/0"
    from_port       = 443
    to_port         = 443
  }

  # Allow inbound SSH (IPv4 only) from trusted IPs only
  dynamic "ingress" {
    for_each = toset(local.ssh_admin_ips)
    content {
      protocol   = "tcp"
      rule_no    = sum([120, index(local.ssh_admin_ips, ingress.value)])
      action     = "allow"
      cidr_block = "${ingress.value}/32"
      from_port  = 22
      to_port    = 22
    }
  }

  # Ephemeral ports for incoming responses to HTTP outbound requests
  ingress {
    protocol   = "tcp"
    rule_no    = 140
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    #  A NAT gateway uses ports 1024–65535
    from_port = 1024
    to_port   = 65535
  }
  ingress {
    protocol        = "tcp"
    rule_no         = 145
    action          = "allow"
    ipv6_cidr_block = "::/0"
    #  A NAT gateway uses ports 1024–65535
    from_port = 1024
    to_port   = 65535
  }

  # Allow inbound TCP Jenkins Agent JNLP protocol from private subnets only
  dynamic "ingress" {
    for_each = toset(module.vpc.private_subnets_cidr_blocks)
    content {
      protocol   = "tcp"
      rule_no    = sum([150, index(module.vpc.private_subnets_cidr_blocks, ingress.value)])
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 50000
      to_port    = 50000
    }
  }

  # Allow outbound HTTP
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }
  egress {
    protocol        = "tcp"
    rule_no         = 105
    action          = "allow"
    ipv6_cidr_block = "::/0"
    from_port       = 80
    to_port         = 80
  }

  # Allow outbound HTTPS
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }
  egress {
    protocol        = "tcp"
    rule_no         = 115
    action          = "allow"
    ipv6_cidr_block = "::/0"
    from_port       = 443
    to_port         = 443
  }

  # Allow outbound HKP (OpenPGP KeyServer) - https://github.com/jenkins-infra/helpdesk/issues/3664
  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 11371
    to_port    = 11371
  }
  egress {
    protocol        = "tcp"
    rule_no         = 125
    action          = "allow"
    ipv6_cidr_block = "::/0"
    from_port       = 11371
    to_port         = 11371
  }

  # Ephemeral ports in response to HTTP inbound requests
  egress {
    protocol   = "tcp"
    rule_no    = 140
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 65535
  }
  egress {
    protocol        = "tcp"
    rule_no         = 145
    action          = "allow"
    ipv6_cidr_block = "::/0"
    from_port       = 32768
    to_port         = 65535
  }

  # Allow outbound Puppet (IPv4 only) to the puppetmaster
  egress {
    protocol   = "tcp"
    rule_no    = 150
    action     = "allow"
    cidr_block = "${local.external_ips["puppet.jenkins.io"]}/32"
    from_port  = 8140
    to_port    = 8140
  }

  # Allow outbound LDAP (IPv4 only) to the Jenkins LDAP
  egress {
    protocol   = "tcp"
    rule_no    = 155
    action     = "allow"
    cidr_block = "${local.external_ips["ldap.jenkins.io"]}/32"
    from_port  = 636
    to_port    = 636
  }

  # Allow SSH egress to the other (private) subnets to ensure we can launch SSH agents
  dynamic "egress" {
    for_each = toset(module.vpc.private_subnets_cidr_blocks)
    content {
      protocol   = "tcp"
      rule_no    = sum([160, index(module.vpc.private_subnets_cidr_blocks, egress.value)])
      action     = "allow"
      cidr_block = egress.value
      from_port  = 22
      to_port    = 22
    }
  }
}

resource "aws_network_acl" "ci_jenkins_io_vm_agents" {
  # No IPv6 on this one

  # Do NOT use the "default_vpc_id" module output ;)
  vpc_id     = module.vpc.vpc_id
  subnet_ids = [module.vpc.private_subnets[0]]

  ## Get started with https://docs.aws.amazon.com/vpc/latest/userguide/custom-network-acl.html

  # Ephemeral ports for incoming responses to HTTP outbound requests
  ingress {
    protocol   = "tcp"
    rule_no    = 140
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 32768
    to_port    = 65535
  }

  # Allow inbound SSH from controller only (private route)
  ingress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "${aws_instance.ci_jenkins_io.private_ip}/32"
    from_port  = 22
    to_port    = 22
  }

  # Allow outbound HTTP
  egress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow outbound HTTPS
  egress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow outbound HKP (OpenPGP KeyServer) - https://github.com/jenkins-infra/helpdesk/issues/3664
  egress {
    protocol   = "tcp"
    rule_no    = 120
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 11371
    to_port    = 11371
  }

  # Allow outbound TCP Jenkins Agent JNLP protocol to controller only
  egress {
    protocol   = "tcp"
    rule_no    = 150
    action     = "allow"
    cidr_block = "${aws_eip.ci_jenkins_io.public_ip}/32"
    from_port  = 50000
    to_port    = 50000
  }

  # Ephemeral ports in response to inbound requests
  egress {
    protocol   = "tcp"
    rule_no    = 140
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    #  A NAT gateway uses ports 1024–65535
    from_port = 1024
    to_port   = 65535
  }
}

### Security Groups
resource "aws_security_group" "ephemeral_vm_agents" {
  name        = "ephemeral-vm-agents"
  description = "Allow inbound SSH only from ci.jenkins.io controller"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_from_cijio_controller" {
  description       = "Allow inbound SSH from ci.jenkins.io controller"
  security_group_id = aws_security_group.ephemeral_vm_agents.id
  cidr_ipv4         = "${aws_instance.ci_jenkins_io.private_ip}/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_security_group" "restricted_in_ssh" {
  name        = "restricted-in-ssh"
  description = "Allow inbound SSH only from trusted sources (admins or VPN)"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "allow_ssh_from_admins" {
  for_each = toset(local.ssh_admin_ips)

  description       = "Allow admin (or platform) IPv4 for inbound SSH"
  security_group_id = aws_security_group.restricted_in_ssh.id
  cidr_ipv4         = "${each.value}/32"
  from_port         = 22
  ip_protocol       = "tcp"
  to_port           = 22
}

resource "aws_security_group" "unrestricted_in_http" {
  name        = "unrestricted-in-http"
  description = "Allow inbound HTTP from everywhere (public services)"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

## We WANT inbound from everywhere
#trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "allow_http_from_internet" {
  description       = "Allow HTTP from everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_in_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}
## We WANT inbound from everywhere
#trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "allow_http6_from_internet" {
  description       = "Allow HTTP (IPv6) from everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_in_http.id
  cidr_ipv6         = "::/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

## We WANT inbound from everywhere
#trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "allow_https_from_internet" {
  description       = "Allow HTTPS from everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_in_http.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}
## We WANT inbound from everywhere
#trivy:ignore:avd-aws-0107
resource "aws_vpc_security_group_ingress_rule" "allow_https6_from_internet" {
  description       = "Allow HTTS (IPv6) from everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_in_http.id
  cidr_ipv6         = "::/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_security_group" "unrestricted_out_http" {
  name        = "unrestricted-out-http"
  description = "Allow outbound HTTP to everywhere (Internet access)"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_http_to_internet" {
  description       = "Allow HTTP to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_http6_to_internet" {
  description       = "Allow HTTP (IPv6) to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv6   = "::/0"
  from_port   = 80
  ip_protocol = "tcp"
  to_port     = 80
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_https_to_internet" {
  description       = "Allow HTTPS to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_https6_to_internet" {
  description       = "Allow HTTPS (IPv6) to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv6   = "::/0"
  from_port   = 443
  ip_protocol = "tcp"
  to_port     = 443
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_hkp_to_internet" {
  description       = "Allow HKP to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 11371
  ip_protocol = "tcp"
  to_port     = 11371
}
## We WANT egress to internet (APT at least, but also outbound azcopy on some machines)
#trivy:ignore:avd-aws-0104
resource "aws_vpc_security_group_egress_rule" "allow_hkp6_to_internet" {
  description       = "Allow HKP (IPv6) to everywhere (public Internet)"
  security_group_id = aws_security_group.unrestricted_out_http.id

  cidr_ipv6   = "::/0"
  from_port   = 11371
  ip_protocol = "tcp"
  to_port     = 11371
}

resource "aws_security_group" "allow_out_puppet_jenkins_io" {
  name        = "allow-out-puppet-jenkins-io"
  description = "Allow outbound Puppet (8140) to puppet.jenkins.io"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "allow_puppet_to_puppetmaster" {
  description       = "Allow Puppet protocol to the Puppet master"
  security_group_id = aws_security_group.allow_out_puppet_jenkins_io.id

  cidr_ipv4   = "${local.external_ips["puppet.jenkins.io"]}/32"
  from_port   = 8140
  ip_protocol = "tcp"
  to_port     = 8140
}

resource "aws_security_group" "ci_jenkins_io_controller" {
  name        = "ci-jenkins-io-controller"
  description = "Allow outbound HTTP to everywhere (Internet access)"
  vpc_id      = module.vpc.vpc_id

  tags = local.common_tags
}

resource "aws_vpc_security_group_egress_rule" "allow_ssh_out_s390x_agent" {
  description       = "Allow SSH to the the external s390x permanent agent"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = "${local.external_ips["s390x.ci.jenkins.io"]}/32"
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_egress_rule" "allow_ldaps_out_ldap_jenkins_io" {
  description       = "Allow LDAPS to ldap.jenkins.io"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = "${local.external_ips["ldap.jenkins.io"]}/32"
  from_port   = 636
  ip_protocol = "tcp"
  to_port     = 636
}

resource "aws_vpc_security_group_egress_rule" "allow_ssh_out_private_subnets" {
  for_each = toset(module.vpc.private_subnets_cidr_blocks)

  description       = "Allow SSH to the private subnet ${each.key}"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = each.key
  from_port   = 22
  ip_protocol = "tcp"
  to_port     = 22
}

resource "aws_vpc_security_group_ingress_rule" "allow_jnlp_in_private_subnets" {
  for_each = toset(module.vpc.private_subnets_cidr_blocks)

  description       = "Allow inbound JNLP Jenkins Agent protocol from private subnet ${each.key}"
  security_group_id = aws_security_group.ci_jenkins_io_controller.id

  cidr_ipv4   = each.key
  from_port   = 50000
  ip_protocol = "tcp"
  to_port     = 50000
}
