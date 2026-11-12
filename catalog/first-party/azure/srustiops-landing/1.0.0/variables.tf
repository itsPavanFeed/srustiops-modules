variable "location" {
  type = string
}
variable "name" {
  type = string
}
variable "resource_group" {
  type = string
}
variable "postgres_subnet_id" {
  type = string
}
variable "endpoints_subnet_id" {
  type = string
}
variable "postgres_dns_zone_id" {
  type = string
}
variable "blob_dns_zone_id" {
  type = string
}
variable "aks_oidc_issuer" {
  type = string
}
variable "db_sku" {
  type    = string
  default = "B_Standard_B2s"
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
variable "tags" {
  type    = map(string)
  default = {}
}
