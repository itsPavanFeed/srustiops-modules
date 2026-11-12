variable "name" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "name must be lowercase letters, digits and dashes (3-31)."
  }
}
variable "tenant" {
  description = "The workspace slug."
  type        = string
}
variable "vpc_id" {
  type = string
}
variable "vpc_cidr" {
  type = string
}
variable "subnet_ids" {
  description = "Private subnets with a route out (NAT) to the gateway and the image registry; the instance goes in the first."
  type        = list(string)
}
variable "instance_profile" {
  description = "From the landing module (instance_profile output)."
  type        = string
}
variable "kms_key_arn" {
  description = "Encrypts the root volume (landing module)."
  type        = string
}
variable "database_endpoint" {
  type = string
}
variable "database_password_secret_arn" {
  type = string
}
variable "gateway_url" {
  description = "The platform's tenant link gateway."
  type        = string
}
variable "central_url" {
  description = "The platform's central URL (the assertion issuer)."
  type        = string
}
variable "gateway_ca" {
  description = "PEM of the gateway's CA; empty when it is publicly trusted."
  type        = string
  default     = ""
}
variable "install_token" {
  description = "One-time install token from the platform (works once, expires in an hour)."
  type        = string
  sensitive   = true
}
variable "image_repo" {
  type    = string
  default = "docker.io/mukkarapavankumarreddy"
}
variable "image_tag" {
  type = string
}
variable "instance_type" {
  type    = string
  default = "t3.large"
}
variable "architecture" {
  description = "x86_64 or arm64 (match the instance type)."
  type        = string
  default     = "x86_64"
}
variable "disk_gb" {
  type    = number
  default = 40
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "remove_srustiops" {
  description = "Take SrustiOps off the instance (the workspace was removed): stop and remove its services and images. The instance, its disk and the keys stay."
  type        = bool
  default     = false
}
