# First-party module: exactly one Elastic IP in a VPC.
resource "aws_eip" "this" {
  domain = "vpc"
  tags   = var.name == null ? var.tags : merge({ Name = var.name }, var.tags)
}
