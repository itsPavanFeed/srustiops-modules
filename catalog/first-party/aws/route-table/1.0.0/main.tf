# First-party module: exactly one route table. Routes are not declared here, so the routes it already has stay as they are.
resource "aws_route_table" "this" {
  vpc_id = var.vpc_id
  tags   = var.name == null ? var.tags : merge({ Name = var.name }, var.tags)
}
