output "db2_instance" {
  description = "DB2 instance"
  value = google_compute_instance.db2_instance.self_link
}
