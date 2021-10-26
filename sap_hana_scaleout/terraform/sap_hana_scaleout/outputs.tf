output "hana_scaleout_primary_self_link" {
  description = "List of self-links for the hana scaleout primary instance created"
  value = google_compute_instance.hana_scaleout_primary.self_link
}
output "hana_scaleout_workers_self_links" {
  description = "List of self-links for the hana scaleout workers created"
  value = google_compute_instance.hana_scaleout_workers.*.self_link
}
output "hana_scaleout_standbys_self_links" {
  description = "List of self-links for the hana scaleout standbys created"
  value = google_compute_instance.hana_scaleout_standbys.*.self_link
}
