variable "name" {
  description = "Name tag (none when null, as on AWS default resources)."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC it belongs to."
  type        = string
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
