output "sap_ase_win_instance_self_link" {
  description = "SAP ASE Windows self-link for instance created"
  value = google_compute_instance.sap_ase_win_instance.self_link
}
