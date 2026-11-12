variable "project" {
  type = string
}
variable "region" {
  type = string
}
variable "name" {
  type = string
}
variable "cidr" {
  type        = string
  description = "A /16: nodes get the first /20, services the second, pods the upper /17"
  default     = "10.52.0.0/16"
}
variable "labels" {
  type    = map(string)
  default = {}
}
