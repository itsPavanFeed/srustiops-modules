variable "project" {
  type = string
}
variable "region" {
  type = string
}
variable "name" {
  type = string
}
variable "network" {
  type = string
}
variable "subnetwork" {
  type = string
}
variable "pods_range" {
  type = string
}
variable "services_range" {
  type = string
}
variable "master_cidr" {
  type    = string
  default = "172.16.0.0/28"
}
variable "master_authorized_cidrs" {
  type        = list(string)
  description = "Who may reach the control plane besides Google (the provisioner's runners need it to install the chart)"
  default     = ["0.0.0.0/0"]
}
variable "kubernetes_version" {
  type    = string
  default = ""
}
variable "release_channel" {
  type    = string
  default = "REGULAR"
}
variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}
variable "nodes_min" {
  type    = number
  default = 1
}
variable "nodes_max" {
  type    = number
  default = 3
}
variable "labels" {
  type    = map(string)
  default = {}
}
