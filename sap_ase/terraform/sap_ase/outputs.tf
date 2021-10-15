output "sap_ase_instance_self_link" {
  description = "SAP ASE self-link for instance created"
  value = google_compute_instance.sap_ase_instance.self_link
}
