#
# Main.tf file for ase_win template
#
#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
################################################
# Local variables for memory and cpu lookups
################################################

locals {
  region = regex("[a-z]*-[a-z1-9]*", var.zone)
  shared_vpc = split("/", var.subnetwork)
}

################################################################################
# disks
################################################################################

resource "google_compute_disk" "ase_win_boot_disk" {
  name = "${var.instance_name}-boot"
  type = "pd-balanced"
  zone = var.zone
  size = 64
  image = "${var.windows_image_project}/${var.windows_image}"
  project = var.project_id
}

resource "google_compute_disk" "ase_win_sid_disk" {
  name = "${var.instance_name}-ase-sid"
  type = "pd-standard"
  zone = var.zone
  size = var.ase_sid_size
  project = var.project_id
}

resource "google_compute_disk" "ase_win_temp_disk" {
  name = "${var.instance_name}-ase-temp"
  type = "pd-standard"
  zone = var.zone
  size = var.ase_sap_temp_size
  project = var.project_id
}

resource "google_compute_disk" "ase_win_log_disk" {
  name = "${var.instance_name}-ase-log"
  type = var.ase_log_ssd ? "pd-ssd" : "pd-standard"
  zone = var.zone
  size = var.ase_log_size
  project = var.project_id
}

resource "google_compute_disk" "ase_win_data_disk" {
  name = "${var.instance_name}-ase-data"
  type = var.ase_sap_data_ssd ? "pd-ssd" : "pd-standard"
  zone = var.zone
  size = var.ase_sap_data_size
  project = var.project_id
}

resource "google_compute_disk" "ase_win_backup_disk" {
  name = "${var.instance_name}-ase-backup"
  type = "pd-standard"
  zone = var.zone
  size = var.ase_backup_size
  project = var.project_id
}

resource "google_compute_disk" "ase_win_usr_sap_disk" {
  count = var.usr_sap_size > 0 ? 1 : 0
  name = "${var.instance_name}-ase-usr-sap"
  type = "pd-standard"
  zone = var.zone
  size = var.usr_sap_size
  project = var.project_id
}

resource "google_compute_disk" "ase_win_swap_disk" {
  count = var.swap_size > 0 ? 1 : 0
  name = "${var.instance_name}-ase-swap"
  type = "pd-standard"
  zone = var.zone
  size = var.swap_size
  project = var.project_id
}

################################################################################
# instances
################################################################################

resource "google_compute_instance" "ase_win_instance" {
  name = var.instance_name
  machine_type = var.machine_type
  zone = var.zone
  project = var.project_id
  boot_disk {
    auto_delete = true
    device_name = "boot"
    source = google_compute_disk.ase_win_boot_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.ase_win_sid_disk.name
    source = google_compute_disk.ase_win_sid_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.ase_win_temp_disk.name
    source = google_compute_disk.ase_win_temp_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.ase_win_log_disk.name
    source = google_compute_disk.ase_win_log_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.ase_win_data_disk.name
    source = google_compute_disk.ase_win_data_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.ase_win_backup_disk.name
    source = google_compute_disk.ase_win_backup_disk.self_link
  }

  dynamic "attached_disk" {
    for_each = var.usr_sap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.ase_win_usr_sap_disk[0].name
      source = google_compute_disk.ase_win_usr_sap_disk[0].self_link
    }
  }

  dynamic "attached_disk" {
    for_each = var.swap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.ase_win_swap_disk[0].name
      source = google_compute_disk.ase_win_swap_disk[0].self_link
    }
  }

  can_ip_forward = true

  service_account {
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  network_interface {
    subnetwork = length(local.shared_vpc) > 1 ? (
      "projects/${local.shared_vpc[0]}/regions/${local.region}/subnetworks${local.shared_vpc[1]}") :(
      "projects/${var.project_id}/regions/${local.region}/subnetworks/${var.subnetwork}")
    # we only include access_config if public_ip is true, an empty access_config
    # will create an ephemeral public ip
    dynamic "access_config" {
      for_each = var.public_ip ? [1] : []
      content {
      }
    }
  }

  metadata = {
    windows-startup-script-url = var.primary_startup_url
    sap_deployment_debug = var.sap_deployment_debug ? "True" : "False"
  }

  tags = flatten(var.network_tags)

  dynamic "reservation_affinity" {
    for_each = length(var.use_reservation_name) > 1 ? [1] : []
    content {
      type = "SPECIFIC_RESERVATION"
      specific_reservation {
        key = "compute.googleapis.com/reservation-name"
        values = [var.use_reservation_name]
      }
    }
  }
}

