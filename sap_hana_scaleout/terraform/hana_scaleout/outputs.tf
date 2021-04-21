output "instances_self_links" {
  description = "List of self-links for the compute instances created"
  value = google_compute_instance.hana_scaleout_instances.*.self_link
}
