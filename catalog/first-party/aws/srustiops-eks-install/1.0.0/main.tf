# The SrustiOps services on an EKS cluster: the tenant Helm chart with a fresh
# install token, so bootstrap runs in the cluster and every key is made
# there. The database URL is built from the RDS-managed secret into a
# Kubernetes Secret. Removing the workspace destroys only this release; the
# chart keeps its keys and the landing module keeps the data.

data "aws_region" "current" {}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  name = var.cluster_name
}

data "aws_secretsmanager_secret_version" "db" {
  secret_id = var.database_password_secret_arn
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

locals {
  db = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)
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
    "database-url" = "postgres://${local.db.username}:${urlencode(local.db.password)}@${var.database_endpoint}/srustiops?sslmode=require"
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
    link                      = merge({ gatewayURL = var.gateway_url }, var.gateway_ca != "" ? { serverCASecret = "srustiops-gateway-ca" } : {})
    serviceAccountAnnotations = { "eks.amazonaws.com/role-arn" = var.tenant_role_arn }
    runner                    = { serviceAccountAnnotations = { "eks.amazonaws.com/role-arn" = var.runner_role_arn } }
    bucket                    = { url = "s3://${var.bucket}?region=${data.aws_region.current.region}", credentials = "workload" }
    replicas                  = var.replicas
  })]
  set_sensitive = [{ name = "install.token", value = var.install_token }]
  depends_on    = [kubernetes_secret_v1.db, kubernetes_secret_v1.gateway_ca]
  lifecycle {
    # A later install token must not reinstall a running tenant.
    ignore_changes = [set_sensitive]
  }
}
