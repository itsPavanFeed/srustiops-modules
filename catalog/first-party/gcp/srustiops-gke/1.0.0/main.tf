# A regional GKE cluster for a workspace: private nodes, a public control
# plane limited to master_authorized_cidrs, Workload Identity, Shielded
# nodes, and one autoscaling node pool with its own minimal service account.

resource "google_service_account" "nodes" {
  project      = var.project
  account_id   = "${substr(var.name, 0, 23)}-nodes"
  display_name = "GKE nodes of ${var.name}"
}

resource "google_project_iam_member" "nodes" {
  for_each = toset(["roles/logging.logWriter", "roles/monitoring.metricWriter", "roles/monitoring.viewer", "roles/artifactregistry.reader", "roles/stackdriver.resourceMetadata.writer"])
  project  = var.project
  role     = each.key
  member   = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  project                  = var.project
  name                     = var.name
  location                 = var.region
  network                  = var.network
  subnetwork               = var.subnetwork
  networking_mode          = "VPC_NATIVE"
  remove_default_node_pool = true
  initial_node_count       = 1
  min_master_version       = var.kubernetes_version != "" ? var.kubernetes_version : null
  deletion_protection      = false
  resource_labels          = var.labels
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range
    services_secondary_range_name = var.services_range
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block = cidr_blocks.value
      }
    }
  }
  release_channel {
    channel = var.release_channel
  }
  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }
  enable_shielded_nodes = true
  datapath_provider     = "ADVANCED_DATAPATH" # Dataplane V2: network policies are enforced
  addons_config {
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }
  node_config {
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  lifecycle {
    ignore_changes = [node_config, initial_node_count]
  }
}

resource "google_container_node_pool" "this" {
  project  = var.project
  name     = "srustiops"
  location = var.region
  cluster  = google_container_cluster.this.name
  autoscaling {
    total_min_node_count = var.nodes_min
    total_max_node_count = var.nodes_max
  }
  initial_node_count = 1
  management {
    auto_repair  = true
    auto_upgrade = true
  }
  node_config {
    machine_type    = var.machine_type
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = var.labels
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    shielded_instance_config {
      enable_secure_boot = true
    }
  }
  lifecycle {
    ignore_changes = [initial_node_count]
  }
}
