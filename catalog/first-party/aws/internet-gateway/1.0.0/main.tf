# First-party module: exactly one internet gateway, attached to a VPC.
resource "aws_internet_gateway" "this" {
  vpc_id = var.vpc_id
  tags   = var.name == null ? var.tags : merge({ Name = var.name }, var.tags)
}
