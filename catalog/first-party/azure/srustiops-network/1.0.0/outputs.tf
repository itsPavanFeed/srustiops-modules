output "resource_group" {
  value = azurerm_resource_group.this.name
}
output "vnet_id" {
  value = azurerm_virtual_network.this.id
}
output "vnet_cidr" {
  value = var.cidr
}
output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}
output "postgres_subnet_id" {
  value = azurerm_subnet.postgres.id
}
output "endpoints_subnet_id" {
  value = azurerm_subnet.endpoints.id
}
output "postgres_dns_zone_id" {
  value = azurerm_private_dns_zone.this["privatelink.postgres.database.azure.com"].id
}
output "blob_dns_zone_id" {
  value = azurerm_private_dns_zone.this["privatelink.blob.core.windows.net"].id
}
output "vault_dns_zone_id" {
  value = azurerm_private_dns_zone.this["privatelink.vaultcore.azure.net"].id
}
