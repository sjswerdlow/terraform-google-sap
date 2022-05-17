#
# Terraform SAP DB2 for Google Cloud
#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
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
resource "google_compute_disk" "sap_db2_boot_disk" {
  name = "${var.instance_name}-boot"
  type = "pd-balanced"
  zone = var.zone
  size = 30 # GB
  project = var.project_id
  image = "${var.linux_image_project}/${var.linux_image}"
}

resource "google_compute_disk" "sap_db2_sid_disk" {
  name = "${var.instance_name}-db2-sid"
  type = "pd-balanced"
  zone = var.zone
  size = var.db2_sid_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_sap_temp_disk" {
  name = "${var.instance_name}-db2-sap-temp"
  type = "pd-balanced"
  zone = var.zone
  size = var.db2_sap_temp_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_log_disk" {
  name = "${var.instance_name}-db2-log"
  type = var.db2_log_ssd ? "pd-ssd" : "pd-balanced"
  zone = var.zone
  size = var.db2_log_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_sap_data_disk" {
  name = "${var.instance_name}-db2-sap-data"
  type = var.db2_sap_data_ssd ? "pd-ssd" : "pd-balanced"
  zone = var.zone
  size = var.db2_sap_data_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_backup_disk" {
  count = var.db2_backup_size > 0 ? 1 : 0
  name = "${var.instance_name}-db2-backup"
  type = "pd-balanced"
  zone = var.zone
  size = var.db2_backup_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_dump_disk" {
  name = "${var.instance_name}-db2-dump"
  type = "pd-balanced"
  zone = var.zone
  size = var.db2_dump_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_home_disk" {
  name = "${var.instance_name}-db2-home"
  type = "pd-balanced"
  zone = var.zone
  size = var.db2_home_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_usr_sap_disk" {
  count = var.usr_sap_size > 0 ? 1 : 0
  name = "${var.instance_name}-db2-usr-sap"
  type = "pd-balanced"
  zone = var.zone
  size = var.usr_sap_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_swap_disk" {
  count = var.swap_size > 0 ? 1 : 0
  name = "${var.instance_name}-db2-swap"
  type = "pd-balanced"
  zone = var.zone
  size = var.swap_size
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_sap_mnt_disk" {
  count = var.sap_mnt_size > 0 ? 1 : 0
  name = "${var.instance_name}-db2-sap-mnt"
  type = "pd-balanced"
  size = var.sap_mnt_size
  zone = var.zone
  project = var.project_id
}

################################################################################
# instances
################################################################################
resource "google_compute_instance" "sap_db2_instance" {
  name = var.instance_name
  machine_type = var.machine_type
  zone = var.zone
  project = var.project_id
  min_cpu_platform = "Automatic"

  boot_disk {
    auto_delete = true
    device_name = "boot"
    source = google_compute_disk.sap_db2_boot_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_sid_disk.name
    source = google_compute_disk.sap_db2_sid_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_sap_temp_disk.name
    source = google_compute_disk.sap_db2_sap_temp_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_log_disk.name
    source = google_compute_disk.sap_db2_log_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_sap_data_disk.name
    source = google_compute_disk.sap_db2_sap_data_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_home_disk.name
    source = google_compute_disk.sap_db2_home_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_dump_disk.name
    source = google_compute_disk.sap_db2_dump_disk.self_link
  }

  dynamic "attached_disk" {
    for_each = var.db2_backup_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_db2_backup_disk[0].name
      source = google_compute_disk.sap_db2_backup_disk[0].self_link
    }
  }

  dynamic "attached_disk" {
    for_each = var.usr_sap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_db2_usr_sap_disk[0].name
      source = google_compute_disk.sap_db2_usr_sap_disk[0].self_link
    }
  }

  dynamic "attached_disk" {
    for_each = var.swap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_db2_swap_disk[0].name
      source = google_compute_disk.sap_db2_swap_disk[0].self_link
    }
  }

  dynamic "attached_disk" {
    for_each = var.sap_mnt_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_db2_sap_mnt_disk[0].name
      source = google_compute_disk.sap_db2_sap_mnt_disk[0].self_link
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
    startup-script = var.primary_startup_url
    post_deployment_script = var.post_deployment_script
    sap_deployment_debug = var.sap_deployment_debug
    sap_db2_sid = var.db2_sid
    template-type = "TERRAFORM"
  }

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}
