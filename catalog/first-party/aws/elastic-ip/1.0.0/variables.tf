variable "name" {
  description = "Name tag (none when null, as on AWS default resources)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags."
  type        = map(string)
  default     = {}
}
