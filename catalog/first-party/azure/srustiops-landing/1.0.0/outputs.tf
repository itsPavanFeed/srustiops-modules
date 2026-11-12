output "tenant_client_id" {
  value = azurerm_user_assigned_identity.this["tenant"].client_id
}
output "runner_client_id" {
  value = azurerm_user_assigned_identity.this["runner"].client_id
}
output "storage_account" {
  value = azurerm_storage_account.state.name
}
output "database_host" {
  value = azurerm_postgresql_flexible_server.db.fqdn
}
output "key_vault_id" {
  value = azurerm_key_vault.this.id
}
