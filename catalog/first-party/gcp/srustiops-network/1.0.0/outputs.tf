output "network" {
  value = google_compute_network.this.name
}
output "network_id" {
  value = google_compute_network.this.id
}
output "subnetwork" {
  value = google_compute_subnetwork.nodes.name
}
output "subnet_cidr" {
  value = google_compute_subnetwork.nodes.ip_cidr_range
}
output "pods_range" {
  value = "pods"
}
output "services_range" {
  value = "services"
}
output "private_services" {
  description = "Set once Cloud SQL can use private IPs in this network"
  value       = google_service_networking_connection.this.id
}
