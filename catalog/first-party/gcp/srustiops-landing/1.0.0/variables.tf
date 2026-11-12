variable "project" {
  type = string
}
variable "region" {
  type = string
}
variable "name" {
  type = string
}
variable "network_id" {
  type        = string
  description = "The VPC (self link or id) Cloud SQL gets its private IP in"
}
variable "private_services" {
  type        = string
  description = "The network's private services connection; Cloud SQL waits for it"
}
variable "db_tier" {
  type    = string
  default = "db-custom-1-3840"
}
variable "db_high_availability" {
  type    = bool
  default = false
}
variable "namespace" {
  type    = string
  default = "srustiops"
}
variable "release" {
  type    = string
  default = "srustiops"
}
variable "labels" {
  type    = map(string)
  default = {}
}
