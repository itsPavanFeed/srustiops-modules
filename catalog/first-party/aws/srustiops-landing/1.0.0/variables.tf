variable "name" {
  description = "Prefix for every resource, e.g. srustiops-acme."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.name))
    error_message = "name must be lowercase letters, digits and dashes (3-31)."
  }
}
variable "vpc_id" {
  description = "VPC the tenant runs in."
  type        = string
}
variable "vpc_cidr" {
  description = "CIDR of that VPC: endpoints and the database accept traffic from it only."
  type        = string
}
variable "private_subnet_ids" {
  description = "Private subnets for the endpoints and the database (at least two zones)."
  type        = list(string)
}
variable "eks_oidc_provider_arn" {
  description = "ARN of the EKS cluster's IAM OIDC provider (IRSA). Empty: the tenant runs on a VM and gets an instance profile."
  type        = string
  default     = ""
}
variable "eks_oidc_issuer" {
  description = "The cluster's OIDC issuer without https://. Required with eks_oidc_provider_arn."
  type        = string
  default     = ""
}
variable "namespace" {
  description = "Namespace the tenant chart is installed in."
  type        = string
  default     = "srustiops"
}
variable "release" {
  description = "Helm release name of the tenant chart."
  type        = string
  default     = "srustiops"
}
variable "deploy_role_arns" {
  description = "Roles in the accounts this tenant manages that runners may assume."
  type        = list(string)
  default     = []
}
variable "interface_endpoints" {
  description = "AWS services reached through VPC interface endpoints."
  type        = list(string)
  # IAM is global and has no regional endpoint; it is reached through STS-issued credentials over the NAT or a proxy.
  default = ["sts", "kms", "secretsmanager", "ec2", "cloudcontrolapi", "logs", "rds", "ssm", "ssmmessages", "ec2messages"]
}
variable "bucket_admin_arns" {
  description = "Roles that may use the state bucket from outside the VPC, besides the role that deploys this module (e.g. your account's administrator role)."
  type        = list(string)
  default     = []
}
variable "image_repositories" {
  description = "Create ECR repositories for the images (air-gapped installs)."
  type        = bool
  default     = false
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "db_multi_az" {
  description = "A standby in a second zone (standard and HA sizes)."
  type        = bool
  default     = true
}
variable "tags" {
  type    = map(string)
  default = {}
}
