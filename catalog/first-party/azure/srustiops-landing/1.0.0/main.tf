# What a SrustiOps workspace keeps in its own Azure subscription: the state
# storage account (no shared keys, private endpoint), PostgreSQL flexible
# server in its delegated subnet, a Key Vault holding the database password,
# and the Workload ID identities of the tenant plane and runners (federated
# with the AKS OIDC issuer). These hold the workspace's data: they are
# protected from destroy, and the provisioner never destroys this stack.

data "azurerm_client_config" "this" {}

locals {
  tags = merge({ "managed-by" = "srustiops-landing", "srustiops-workspace" = var.name }, var.tags)
  # Storage account and vault names: 3-24 lowercase letters and digits, globally unique.
  short = substr(replace(var.name, "-", ""), 0, 14)
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# ---- state ----

resource "azurerm_storage_account" "state" {
  name                              = "${local.short}${random_string.suffix.result}"
  resource_group_name               = var.resource_group
  location                          = var.location
  account_tier                      = "Standard"
  account_replication_type          = "ZRS"
  min_tls_version                   = "TLS1_2"
  shared_access_key_enabled         = false
  allow_nested_items_to_be_public   = false
  public_network_access_enabled     = false
  infrastructure_encryption_enabled = true
  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
  tags = local.tags
  lifecycle {
    prevent_destroy = true
  }
}

# Made through the management plane (storage_account_id), so the runner
# needs no network path to the account itself.
resource "azurerm_storage_container" "state" {
  name                  = "srustiops"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_private_endpoint" "blob" {
  name                = "${var.name}-blob"
  resource_group_name = var.resource_group
  location            = var.location
  subnet_id           = var.endpoints_subnet_id
  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.state.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }
  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [var.blob_dns_zone_id]
  }
  tags = local.tags
}

# ---- PostgreSQL ----

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "azurerm_postgresql_flexible_server" "db" {
  name                          = "${var.name}-${random_string.suffix.result}"
  resource_group_name           = var.resource_group
  location                      = var.location
  version                       = "16"
  sku_name                      = var.db_sku
  storage_mb                    = 32768
  auto_grow_enabled             = true
  backup_retention_days         = 14
  geo_redundant_backup_enabled  = false
  delegated_subnet_id           = var.postgres_subnet_id
  private_dns_zone_id           = var.postgres_dns_zone_id
  public_network_access_enabled = false
  administrator_login           = "srustiops"
  administrator_password        = random_password.db.result
  dynamic "high_availability" {
    for_each = var.db_high_availability ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }
  tags = local.tags
  lifecycle {
    prevent_destroy = true
    ignore_changes  = [zone, high_availability[0].standby_availability_zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "srustiops" {
  name      = "srustiops"
  server_id = azurerm_postgresql_flexible_server.db.id
  charset   = "UTF8"
  collation = "en_US.utf8"
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_postgresql_flexible_server_configuration" "tls" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.db.id
  value     = "on"
}

# ---- the database password, for the install step ----

resource "azurerm_key_vault" "this" {
  name                       = "${local.short}${random_string.suffix.result}kv"
  resource_group_name        = var.resource_group
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.this.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = 30
  tags                       = local.tags
}

# The provisioner (this run's identity) writes and later reads the secret.
resource "azurerm_role_assignment" "provisioner_secrets" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.this.object_id
}

resource "azurerm_key_vault_secret" "db" {
  name         = "database-password"
  value        = random_password.db.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.provisioner_secrets]
}

# ---- Workload ID ----

resource "azurerm_user_assigned_identity" "this" {
  for_each            = toset(["tenant", "runner"])
  name                = "${var.name}-${each.key}"
  resource_group_name = var.resource_group
  location            = var.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "this" {
  for_each                  = azurerm_user_assigned_identity.this
  name                      = "aks"
  user_assigned_identity_id = each.value.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.aks_oidc_issuer
  subject                   = "system:serviceaccount:${var.namespace}:${var.release}-${each.key}"
}

resource "azurerm_role_assignment" "tenant_blob" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.this["tenant"].principal_id
}
