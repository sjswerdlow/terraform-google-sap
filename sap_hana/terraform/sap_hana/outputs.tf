#outputs.tf
#
output "sap_hana_primary_self_link" {
  description = "List of self-links for the sap hana primary instance created"
  value = google_compute_instance.sap_hana_primary.self_link
}
output "sap_hana_workers_self_link" {
  description = "List of self-links for the hana worker instances created"
  value = google_compute_instance.sap_hana_workers.*.self_link
}
