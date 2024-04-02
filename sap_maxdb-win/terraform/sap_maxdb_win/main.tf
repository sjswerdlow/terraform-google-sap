#
# Terraform SAP MaxDB Windows for Google Cloud
#
# Version:    2.0.202403040702
# Build Hash: 14cfd7eff165f31048fdcdad85843c67e0790bef
#

################################################################################
# Local variables
################################################################################
locals {
  zone_split = split("-", var.zone)
  region = "${local.zone_split[0]}-${local.zone_split[1]}"
  subnetwork_split = split("/", var.subnetwork)
}

################################################################################
# disks
################################################################################
resource "google_compute_disk" "sap_maxdb_win_boot_disk" {
  name = "${var.instance_name}-boot"
  type = "pd-balanced"
  zone = var.zone
  size = 64 # GB
  project = var.project_id
  image = "${var.windows_image_project}/${var.windows_image}"
}

resource "google_compute_disk" "sap_maxdb_win_root_disk" {
  name = "${var.instance_name}-maxdb-root"
  type = "pd-balanced"
  zone = var.zone
  size = var.maxdb_root_size
  project = var.project_id
}

resource "google_compute_disk" "sap_maxdb_win_data_disk" {
  name = "${var.instance_name}-maxdb-data"
  type = var.maxdb_data_ssd ? "pd-ssd" : "pd-balanced"
  zone = var.zone
  size = var.maxdb_data_size
  project = var.project_id
}

resource "google_compute_disk" "sap_maxdb_win_log_disk" {
  name = "${var.instance_name}-maxdb-log"
  type = var.maxdb_log_ssd ? "pd-ssd" : "pd-balanced"
  zone = var.zone
  size = var.maxdb_log_size
  project = var.project_id
}

resource "google_compute_disk" "sap_maxdb_win_backup_disk" {
  name = "${var.instance_name}-maxdb-backup"
  type = "pd-balanced"
  zone = var.zone
  size = var.maxdb_backup_size
  project = var.project_id
}

resource "google_compute_disk" "sap_maxdb_win_usr_sap_disk" {
  count = var.usr_sap_size > 0 ? 1 : 0
  name = "${var.instance_name}-maxdb-usr-sap"
  type = "pd-balanced"
  zone = var.zone
  size = var.usr_sap_size
  project = var.project_id
}

resource "google_compute_disk" "sap_maxdb_win_swap_disk" {
  count = var.swap_size > 0 ? 1 : 0
  name = "${var.instance_name}-maxdb-swap"
  type = "pd-balanced"
  zone = var.zone
  size = var.swap_size
  project = var.project_id
}

###############################################################################
# instances
################################################################################
resource "google_compute_instance" "sap_maxdb_win_instance" {
  name = var.instance_name
  machine_type = var.machine_type
  zone = var.zone
  project = var.project_id
  min_cpu_platform = "Automatic"

  boot_disk {
    auto_delete = true
    device_name = "boot"
    source = google_compute_disk.sap_maxdb_win_boot_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_maxdb_win_root_disk.name
    source = google_compute_disk.sap_maxdb_win_root_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_maxdb_win_data_disk.name
    source = google_compute_disk.sap_maxdb_win_data_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_maxdb_win_log_disk.name
    source = google_compute_disk.sap_maxdb_win_log_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_maxdb_win_backup_disk.name
    source = google_compute_disk.sap_maxdb_win_backup_disk.self_link
  }

  dynamic "attached_disk" {
    for_each = var.usr_sap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_maxdb_win_usr_sap_disk[0].name
      source = google_compute_disk.sap_maxdb_win_usr_sap_disk[0].self_link
    }
  }

  dynamic "attached_disk" {
    for_each = var.swap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_maxdb_win_swap_disk[0].name
      source = google_compute_disk.sap_maxdb_win_swap_disk[0].self_link
    }
  }

  can_ip_forward = var.can_ip_forward

  network_interface {
    subnetwork = length(local.subnetwork_split) > 1 ? (
      "projects/${local.subnetwork_split[0]}/regions/${local.region}/subnetworks/${local.subnetwork_split[1]}") : (
      "projects/${var.project_id}/regions/${local.region}/subnetworks/${var.subnetwork}")
    # we only include access_config if public_ip is true, an empty access_config
    # will create an ephemeral public ip
    dynamic "access_config" {
      for_each = var.public_ip ? [1] : []
      content {
      }
    }
  }

  tags = var.network_tags

  service_account {
    # An empty string service account will default to the projects default compute engine service account
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  dynamic "reservation_affinity" {
    for_each = length(var.reservation_name) > 1 ? [1] : []
    content {
      type = "SPECIFIC_RESERVATION"
      specific_reservation {
        key = "compute.googleapis.com/reservation-name"
        values = [var.reservation_name]
      }
    }
  }

  metadata = {
    windows-startup-script-url = var.primary_startup_url
    post_deployment_script = var.post_deployment_script
    sap_deployment_debug = var.sap_deployment_debug
  }

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}
