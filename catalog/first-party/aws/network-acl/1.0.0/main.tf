# First-party module: exactly one network ACL. Rules and subnet associations are not declared here, so the ones it already has stay as they are.
resource "aws_network_acl" "this" {
  vpc_id = var.vpc_id
  tags   = var.name == null ? var.tags : merge({ Name = var.name }, var.tags)
}
