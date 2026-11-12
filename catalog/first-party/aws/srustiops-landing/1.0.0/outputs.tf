output "tenant_role_arn" {
  value = aws_iam_role.this["tenant"].arn
}
output "runner_role_arn" {
  value = aws_iam_role.this[local.irsa ? "runner" : "tenant"].arn
}
output "instance_profile" {
  description = "For a VM install; empty on EKS."
  value       = local.irsa ? "" : aws_iam_instance_profile.this[0].name
}
output "bucket" {
  value = aws_s3_bucket.bucket.id
}
output "kms_key_arn" {
  value = aws_kms_key.this.arn
}
output "database_endpoint" {
  value = aws_db_instance.db.endpoint
}
output "database_password_secret_arn" {
  description = "RDS-managed password; the install reads it at runtime"
  value       = aws_db_instance.db.master_user_secret[0].secret_arn
}
