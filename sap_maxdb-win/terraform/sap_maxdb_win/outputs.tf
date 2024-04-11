output "sap_maxdb_win_instance" {
  description = "SAP MaxDB Windows self-link for instance created"
  value       = google_compute_instance.sap_maxdb_win_instance.self_link
}
