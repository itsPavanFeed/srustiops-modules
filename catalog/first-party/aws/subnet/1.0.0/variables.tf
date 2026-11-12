variable "name" {
  description = "Name tag (none when null, as on AWS default resources)."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC the subnet belongs to."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR block."
  type        = string
}

variable "availability_zone" {
  description = "Availability zone, e.g. ap-southeast-2a."
  type        = string
  default     = null
}

variable "map_public_ip_on_launch" {
  description = "Give instances launched in the subnet a public IP."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
