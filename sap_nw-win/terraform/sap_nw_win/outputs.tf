output "sap_nw_win_self_link" {
  description = "SAP NW Windows self-link for instance created"
  value       = google_compute_instance.sap_nw_win_instance.self_link
}
