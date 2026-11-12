output "cluster_name" {
  value = google_container_cluster.this.name
}
output "location" {
  value = google_container_cluster.this.location
}
output "endpoint" {
  value = google_container_cluster.this.endpoint
}
output "workload_pool" {
  value = "${var.project}.svc.id.goog"
}
