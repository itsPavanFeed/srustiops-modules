# An AKS cluster for a workspace: Azure CNI overlay in the workspace's
# subnet, Azure network policy, the OIDC issuer and Workload ID (the tenant
# plane's Blob and Key Vault access), and one autoscaling node pool.

resource "azurerm_kubernetes_cluster" "this" {
  name                      = var.name
  location                  = var.location
  resource_group_name       = var.resource_group
  dns_prefix                = var.name
  kubernetes_version        = var.kubernetes_version
  sku_tier                  = "Standard"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"
  tags                      = merge({ "managed-by" = "srustiops" }, var.tags)
  default_node_pool {
    name                 = "srustiops"
    vm_size              = var.vm_size
    vnet_subnet_id       = var.subnet_id
    auto_scaling_enabled = true
    min_count            = var.nodes_min
    max_count            = var.nodes_max
    os_disk_type         = "Managed"
    upgrade_settings {
      max_surge = "33%"
    }
  }
  identity {
    type = "SystemAssigned"
  }
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "172.20.0.0/16"
    dns_service_ip      = "172.20.0.10"
  }
  dynamic "api_server_access_profile" {
    for_each = length(var.api_authorized_cidrs) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_authorized_cidrs
    }
  }
  lifecycle {
    ignore_changes = [default_node_pool[0].node_count, kubernetes_version]
  }
}

# The cluster manages load balancers and routes in its subnet.
resource "azurerm_role_assignment" "network" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
}
