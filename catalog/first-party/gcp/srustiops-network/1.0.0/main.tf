# The network a GKE workspace runs in: a VPC with one regional subnet (and
# secondary ranges for pods and services), Cloud NAT for private nodes,
# Private Google Access, and the private services range Cloud SQL uses.
# The APIs the workspace needs are enabled here (and left enabled).

locals {
  services = ["compute.googleapis.com", "container.googleapis.com", "sqladmin.googleapis.com", "servicenetworking.googleapis.com",
  "secretmanager.googleapis.com", "iamcredentials.googleapis.com", "cloudkms.googleapis.com", "storage.googleapis.com"]
}

resource "google_project_service" "this" {
  for_each           = toset(local.services)
  project            = var.project
  service            = each.key
  disable_on_destroy = false
}

resource "google_compute_network" "this" {
  project                 = var.project
  name                    = var.name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  depends_on              = [google_project_service.this]
}

resource "google_compute_subnetwork" "nodes" {
  project                  = var.project
  name                     = "${var.name}-nodes"
  region                   = var.region
  network                  = google_compute_network.this.id
  ip_cidr_range            = cidrsubnet(var.cidr, 4, 0)
  private_ip_google_access = true
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = cidrsubnet(var.cidr, 1, 1)
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = cidrsubnet(var.cidr, 4, 1)
  }
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.2
  }
}

resource "google_compute_router" "this" {
  project = var.project
  name    = var.name
  region  = var.region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  project                            = var.project
  name                               = var.name
  router                             = google_compute_router.this.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private services access: Cloud SQL gets a private IP in this range.
resource "google_compute_global_address" "services" {
  project       = var.project
  name          = "${var.name}-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.this.id
}

resource "google_service_networking_connection" "this" {
  network                 = google_compute_network.this.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.services.name]
}
