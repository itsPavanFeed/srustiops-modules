# What a SrustiOps workspace keeps in its own GCP project: a Cloud KMS key,
# the state bucket (CMEK), Cloud SQL for PostgreSQL on a private IP (its
# password in Secret Manager), and the Workload Identity service accounts of
# the tenant plane and runners. These hold the workspace's data: they are
# protected from destroy, and the provisioner never destroys this stack.

data "google_project" "this" {
  project_id = var.project
}

locals {
  labels = merge({ "managed-by" = "srustiops-landing", "srustiops-workspace" = var.name }, var.labels)
  pool   = "${var.project}.svc.id.goog"
}

resource "google_kms_key_ring" "this" {
  project  = var.project
  name     = var.name
  location = var.region
}

resource "google_kms_crypto_key" "this" {
  name            = "${var.name}-data"
  key_ring        = google_kms_key_ring.this.id
  rotation_period = "7776000s" # 90 days
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_kms_crypto_key_iam_member" "gcs" {
  crypto_key_id = google_kms_crypto_key.this.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.this.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_storage_bucket" "state" {
  project                     = var.project
  name                        = "${var.name}-state-${data.google_project.this.number}"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning {
    enabled = true
  }
  encryption {
    default_kms_key_name = google_kms_crypto_key.this.id
  }
  lifecycle_rule {
    condition {
      num_newer_versions = 10
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
  labels     = local.labels
  depends_on = [google_kms_crypto_key_iam_member.gcs]
  lifecycle {
    prevent_destroy = true
  }
}

# ---- PostgreSQL ----

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "google_sql_database_instance" "db" {
  project             = var.project
  name                = var.name
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = true
  settings {
    tier              = var.db_tier
    edition           = "ENTERPRISE"
    availability_type = var.db_high_availability ? "REGIONAL" : "ZONAL"
    disk_autoresize   = true
    user_labels       = local.labels
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }
    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 14
      }
    }
    database_flags {
      name  = "log_connections"
      value = "on"
    }
  }
  # The private services connection must exist before a private IP can be used.
  depends_on = [terraform_data.private_services]
  lifecycle {
    prevent_destroy = true
  }
}

resource "terraform_data" "private_services" {
  input = var.private_services
}

resource "google_sql_database" "srustiops" {
  project  = var.project
  name     = "srustiops"
  instance = google_sql_database_instance.db.name
}

resource "google_sql_user" "srustiops" {
  project  = var.project
  name     = "srustiops"
  instance = google_sql_database_instance.db.name
  password = random_password.db.result
}

resource "google_secret_manager_secret" "db" {
  project   = var.project
  secret_id = "${var.name}-db-password"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
  labels = local.labels
}

resource "google_secret_manager_secret_version" "db" {
  secret      = google_secret_manager_secret.db.id
  secret_data = random_password.db.result
}

# ---- Workload Identity ----

resource "google_service_account" "this" {
  for_each     = toset(["tenant", "runner"])
  project      = var.project
  account_id   = "${substr(var.name, 0, 22)}-${each.key}"
  display_name = "SrustiOps ${each.key} (${var.name})"
}

resource "google_service_account_iam_member" "workload_identity" {
  for_each           = google_service_account.this
  service_account_id = each.value.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${local.pool}[${var.namespace}/${var.release}-${each.key}]"
}

resource "google_storage_bucket_iam_member" "tenant" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectUser"
  member = google_service_account.this["tenant"].member
}

resource "google_storage_bucket_iam_member" "tenant_bucket_read" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.legacyBucketReader" # the plane checks the bucket exists at start
  member = google_service_account.this["tenant"].member
}

resource "google_kms_crypto_key_iam_member" "tenant" {
  crypto_key_id = google_kms_crypto_key.this.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = google_service_account.this["tenant"].member
}

resource "google_project_iam_member" "tenant_sql" {
  project = var.project
  role    = "roles/cloudsql.client"
  member  = google_service_account.this["tenant"].member
}
