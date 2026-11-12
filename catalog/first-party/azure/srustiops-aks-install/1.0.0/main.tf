# The SrustiOps services on an AKS cluster: the tenant Helm chart with a
# fresh install token, so bootstrap runs in the cluster and every key is
# made there. The database URL is built from the password in Key Vault into
# a Kubernetes Secret; Blob Storage is used through Workload ID. Removing
# the workspace destroys only this release; the landing keeps the data.

data "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = var.resource_group
}

data "azurerm_key_vault_secret" "db" {
  name         = "database-password"
  key_vault_id = var.key_vault_id
}

locals {
  kube = data.azurerm_kubernetes_cluster.this.kube_admin_config_raw != "" ? data.azurerm_kubernetes_cluster.this.kube_admin_config[0] : data.azurerm_kubernetes_cluster.this.kube_config[0]
}

provider "kubernetes" {
  host                   = local.kube.host
  cluster_ca_certificate = base64decode(local.kube.cluster_ca_certificate)
  client_certificate     = base64decode(local.kube.client_certificate)
  client_key             = base64decode(local.kube.client_key)
}

provider "helm" {
  kubernetes = {
    host                   = local.kube.host
    cluster_ca_certificate = base64decode(local.kube.cluster_ca_certificate)
    client_certificate     = base64decode(local.kube.client_certificate)
    client_key             = base64decode(local.kube.client_key)
  }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name   = var.namespace
    labels = { "srustiops-tenant" = var.tenant, "pod-security.kubernetes.io/enforce" = "restricted" }
  }
}

resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = "srustiops-tenant"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  data = {
    "database-url" = "postgres://srustiops:${urlencode(data.azurerm_key_vault_secret.db.value)}@${var.database_host}/srustiops?sslmode=require"
  }
}

resource "kubernetes_secret_v1" "gateway_ca" {
  count = var.gateway_ca != "" ? 1 : 0
  metadata {
    name      = "srustiops-gateway-ca"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
  data = { "ca.crt" = var.gateway_ca }
}

resource "helm_release" "this" {
  name       = var.release
  namespace  = kubernetes_namespace_v1.this.metadata[0].name
  repository = var.chart_repository
  chart      = "srustiops-tenant"
  version    = var.chart_version
  wait       = true
  timeout    = 900
  values = [yamlencode({
    tenant       = var.tenant
    connectivity = "tunnel"
    image = {
      server = "${var.image_repo}/srustiops-server"
      runner = "${var.image_repo}/srustiops-runner"
      tag    = var.image_tag
    }
    central                   = { url = var.central_url }
    link                      = merge({ gatewayURL = var.gateway_url, storageClass = "managed-csi" }, var.gateway_ca != "" ? { serverCASecret = "srustiops-gateway-ca" } : {})
    podLabels                 = { "azure.workload.identity/use" = "true" }
    serviceAccountAnnotations = { "azure.workload.identity/client-id" = var.tenant_client_id }
    runner = {
      podLabels                 = { "azure.workload.identity/use" = "true" }
      serviceAccountAnnotations = { "azure.workload.identity/client-id" = var.runner_client_id }
    }
    bucket   = { url = "azblob://${var.storage_account}/srustiops", credentials = "workload" }
    replicas = var.replicas
  })]
  set_sensitive = [{ name = "install.token", value = var.install_token }]
  depends_on    = [kubernetes_secret_v1.db, kubernetes_secret_v1.gateway_ca]
  lifecycle {
    # A later install token must not reinstall a running tenant.
    ignore_changes = [set_sensitive]
  }
}
