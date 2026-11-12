# The SrustiOps services on a GKE cluster: the tenant Helm chart with a fresh
# install token, so bootstrap runs in the cluster and every key is made
# there. The database URL is built from the password in Secret Manager into
# a Kubernetes Secret; the bucket and KMS are used through Workload Identity.
# Removing the workspace destroys only this release; the landing keeps the data.

data "google_client_config" "this" {}

data "google_container_cluster" "this" {
  project  = var.project
  name     = var.cluster_name
  location = var.location
}

data "google_secret_manager_secret_version" "db" {
  secret = var.database_password_secret
}

locals {
  host = "https://${data.google_container_cluster.this.endpoint}"
  ca   = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
}

provider "kubernetes" {
  host                   = local.host
  cluster_ca_certificate = local.ca
  token                  = data.google_client_config.this.access_token
}

provider "helm" {
  kubernetes = {
    host                   = local.host
    cluster_ca_certificate = local.ca
    token                  = data.google_client_config.this.access_token
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
    "database-url" = "postgres://srustiops:${urlencode(data.google_secret_manager_secret_version.db.secret_data)}@${var.database_ip}/srustiops?sslmode=require"
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
    link                      = merge({ gatewayURL = var.gateway_url, storageClass = "standard-rwo" }, var.gateway_ca != "" ? { serverCASecret = "srustiops-gateway-ca" } : {})
    serviceAccountAnnotations = { "iam.gke.io/gcp-service-account" = var.tenant_service_account }
    runner                    = { serviceAccountAnnotations = { "iam.gke.io/gcp-service-account" = var.runner_service_account } }
    bucket                    = { url = "gs://${var.bucket}", credentials = "workload" }
    replicas                  = var.replicas
  })]
  set_sensitive = [{ name = "install.token", value = var.install_token }]
  depends_on    = [kubernetes_secret_v1.db, kubernetes_secret_v1.gateway_ca]
  lifecycle {
    # A later install token must not reinstall a running tenant.
    ignore_changes = [set_sensitive]
  }
}
