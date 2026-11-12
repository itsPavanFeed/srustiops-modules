variable "tenant" {
  description = "The workspace slug."
  type        = string
}
variable "cluster_name" {
  type = string
}
variable "namespace" {
  type    = string
  default = "srustiops"
}
variable "release" {
  type    = string
  default = "srustiops"
}
variable "chart_repository" {
  description = "OCI registry holding the srustiops-tenant chart."
  type        = string
  default     = "oci://docker.io/mukkarapavankumarreddy/charts"
}
variable "chart_version" {
  type = string
}
variable "image_repo" {
  type    = string
  default = "docker.io/mukkarapavankumarreddy"
}
variable "image_tag" {
  type = string
}
variable "gateway_url" {
  type = string
}
variable "central_url" {
  type = string
}
variable "gateway_ca" {
  type    = string
  default = ""
}
variable "install_token" {
  type      = string
  sensitive = true
}
variable "database_endpoint" {
  type = string
}
variable "database_password_secret_arn" {
  type = string
}
variable "bucket" {
  type = string
}
variable "tenant_role_arn" {
  type = string
}
variable "runner_role_arn" {
  type = string
}
variable "replicas" {
  type    = number
  default = 2
}
