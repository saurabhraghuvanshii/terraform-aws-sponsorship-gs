####################################################################################
# VPC / Network ('non security) resources
####################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.16.0"

  name = "aws-sponso-vpc"
  cidr = local.vpc_cidr

  # dual stack https://github.com/terraform-aws-modules/terraform-aws-vpc/blob/v5.13.0/examples/ipv6-dualstack/main.tf
  enable_ipv6                                   = true
  public_subnet_assign_ipv6_address_on_creation = true

  manage_default_network_acl    = false
  map_public_ip_on_launch       = true
  manage_default_route_table    = false
  manage_default_security_group = false

  # only one zone, no need for multiple availability zones
  azs = [for subnet_name, subnet_cidr in local.vpc_private_subnets : format("${local.region}%s", "b")]

  # only private subnets for security (to control allowed outbound connections)
  private_subnets = [for subnet_name, subnet_cidr in local.vpc_private_subnets : subnet_cidr]
  public_subnets  = [for subnet_name, subnet_cidr in local.vpc_public_subnets : subnet_cidr]

  public_subnet_ipv6_prefixes  = range(length(local.vpc_public_subnets))
  private_subnet_ipv6_prefixes = range(10, length(local.vpc_private_subnets) + 10)

  # One NAT gateway per subnet (default)
  # ref. https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest#one-nat-gateway-per-subnet-default
  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
}
