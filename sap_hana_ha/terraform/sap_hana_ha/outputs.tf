output "primary_hana_self_link" {
  description = "Primary HANA instance deployed."
  value = google_compute_instance.hana_ha_primary.self_link
}
output "secondary_hana_self_link" {
  description = "Secondary HANA instance deployed"
  value = google_compute_instance.hana_ha_secondary.self_link
}
output "loadbalander_link" {
  description = "Link to the optional load balancer"
  value = google_compute_region_backend_service.loadbalancer.*.self_link
}
output "firewall_link" {
  description = "Link to the optional fire wall"
  value = google_compute_firewall.vpc_firewall.*.self_link
}