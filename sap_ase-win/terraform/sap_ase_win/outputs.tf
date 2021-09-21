output "ase_win_instance" {
  description = "ASE Windows instance"
  value = google_compute_instance.ase_win_instance.self_link
}
