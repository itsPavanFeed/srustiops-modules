output "tenant_service_account" {
  value = google_service_account.this["tenant"].email
}
output "runner_service_account" {
  value = google_service_account.this["runner"].email
}
output "bucket" {
  value = google_storage_bucket.state.name
}
output "kms_key" {
  value = google_kms_crypto_key.this.id
}
output "database_ip" {
  value = google_sql_database_instance.db.private_ip_address
}
output "database_password_secret" {
  value = google_secret_manager_secret.db.id
}
