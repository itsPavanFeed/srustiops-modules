variable "location" {
  type = string
}
variable "name" {
  type = string
}
variable "resource_group" {
  type = string
}
variable "subnet_id" {
  type = string
}
variable "kubernetes_version" {
  type    = string
  default = null
}
variable "vm_size" {
  type    = string
  default = "Standard_D4s_v5"
}
variable "nodes_min" {
  type    = number
  default = 1
}
variable "nodes_max" {
  type    = number
  default = 3
}
variable "api_authorized_cidrs" {
  type        = list(string)
  description = "Who may reach the API server (the provisioner's runners need it to install the chart); empty means anyone"
  default     = []
}
variable "tags" {
  type    = map(string)
  default = {}
}
