output "sap_db2_instance" {
  description = "DB2 instance"
  value = google_compute_instance.sap_db2_instance.self_link
}
