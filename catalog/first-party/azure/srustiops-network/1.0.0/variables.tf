variable "location" {
  type = string
}
variable "name" {
  type = string
}
variable "cidr" {
  type        = string
  description = "A /16: AKS nodes and pods get the first /18; PostgreSQL and private endpoints a /24 each after it"
  default     = "10.62.0.0/16"
}
variable "tags" {
  type    = map(string)
  default = {}
}
