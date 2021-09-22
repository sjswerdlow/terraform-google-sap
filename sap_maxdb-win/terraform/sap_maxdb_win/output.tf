output "maxdb_win_instance" {
  description = "MaxDB Windows instance"
  value = google_compute_instance.maxdb_win_instance.self_link
}
