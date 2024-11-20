resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = trimspace(element(split("#", compact(split("\n", file("./ec2_agents_authorized_keys")))[0]), 0))
  tags       = local.common_tags
}
