# First-party module: exactly one subnet. Routing (route tables and their
# associations) is managed by its own resources, never implicitly here.
resource "aws_subnet" "this" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.cidr_block
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = var.map_public_ip_on_launch
  tags                    = var.name == null ? var.tags : merge({ Name = var.name }, var.tags)
}
