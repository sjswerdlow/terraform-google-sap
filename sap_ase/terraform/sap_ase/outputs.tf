output "sap_ase_self_link" {
  description = "SAP ASE self-link for instance created"
  value = google_compute_instance.sap_ase.self_link
}
