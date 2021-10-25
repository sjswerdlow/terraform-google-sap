output "sap_db2_instance_self_link" {
  description = "DB2 self-link for instance created"
  value = google_compute_instance.sap_db2_instance.self_link
}
