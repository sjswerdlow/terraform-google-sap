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
  region      = regex("[a-z]*-[a-z1-9]*", var.zone)
  shared_vpc  = split("/", var.subnetwork)
}

################################################################################
# disks
################################################################################
resource "google_compute_disk" "sap_db2_boot_disk" {
  name = "${var.instance_name}-boot"
  type = "pd-balanced"
  size = 30 # GB
  zone = var.zone
  project = var.project_id
  image = "${var.linux_image_project}/${var.linux_image}"
}

resource "google_compute_disk" "sap_db2_sid_disk" {
  name = "${var.instance_name}-db2sid"
  type = "pd-standard"
  size = var.db2_sid_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_dump_disk" {
  name = "${var.instance_name}-db2-dump"
  type = "pd-standard"
  size = var.db2_dump_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_home_disk" {
  name = "${var.instance_name}-db2-home"
  type = "pd-standard"
  size = var.db2_home_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_sap_tmp_disk" {
  name = "${var.instance_name}-db2-sap-tmp"
  type = "pd-standard"
  size = var.db2_sap_tmp_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_log_disk" {
  name = "${var.instance_name}-db2-log"
  type = var.db2_log_ssd ? "pd-ssd" : "pd-standard"
  size = var.db2_log_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_sap_data_disk" {
  name = "${var.instance_name}-db2-sap-data"
  type = var.db2_sap_data_ssd ? "pd-ssd" : "pd-standard"
  size = var.db2_sap_data_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_backup_disk" {
  count = var.db2_backup_size > 0 ? 1 : 0
  name = "${var.instance_name}-db2-backup"
  type = "pd-standard"
  size = var.db2_backup_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_usr_sap_disk" {
  count = var.usr_sap_size > 0 ? 1 : 0
  name = "${var.instance_name}-db2-usr-sap"
  type = "pd-standard"
  size = var.usr_sap_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_sap_mnt_disk" {
  count = var.usr_sap_size > 0 ? 1 : 0
  name = "${var.instance_name}-db2-sap-mnt"
  type = "pd-standard"
  size = var.sap_mnt_size
  zone = var.zone
  project = var.project_id
}

resource "google_compute_disk" "sap_db2_swap_disk" {
  count = var.swap_size > 0 ? 1 : 0
  name = "${var.instance_name}-db2-swap"
  type = "pd-standard"
  size = var.sap_mnt_size
  zone = var.zone
  project = var.project_id
}

################################################################################
# instances
################################################################################
resource "google_compute_instance" "sap_db2" {
  name = var.instance_name
  zone = var.zone
  project = var.project_id
  machine_type = var.machine_type
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
    device_name = google_compute_disk.sap_db2_home_disk.name
    source = google_compute_disk.sap_db2_home_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_dump_disk.name
    source = google_compute_disk.sap_db2_dump_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_sap_tmp_disk.name
    source = google_compute_disk.sap_db2_sap_tmp_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_sap_data_disk.name
    source = google_compute_disk.sap_db2_sap_data_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_db2_log_disk.name
    source = google_compute_disk.sap_db2_log_disk.self_link
  }

  dynamic "attached_disk" {
    for_each = var.db2_backup_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_db2_backup_disk.name
      source = google_compute_disk.sap_db2_backup_disk.self_link
    }
  }

  dynamic "attached_disk" {
    for_each = var.usr_sap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_db2_usr_sap_disk.name
      source = google_compute_disk.sap_db2_usr_sap_disk.self_link
    }
  }

  dynamic "attached_disk" {
    for_each = var.sap_mnt_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_db2_sap_mnt_disk.name
      source = google_compute_disk.sap_db2_sap_mnt_disk.self_link
    }
  }

  dynamic "attached_disk" {
    for_each = var.swap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_db2_swap_disk.name
      source = google_compute_disk.sap_db2_swapdisk.self_link
    }
  }
  can_ip_forward = true
  network_interface {
    subnetwork = length(local.shared_vpc) > 1 ? (
      "projects/${local.shared_vpc[0]}/regions/${local.region}/subnetworks/${local.shared_vpc[1]}") : (
      "projects/${var.project_id}/regions/${local.region}/subnetworks/${var.subnetwork}")
    # we only include access_config if public_ip is true, an empty access_config
    # will create an ephemeral public ip
    dynamic "access_config" {
      for_each = var.public_ip ? [1] : []
      content {
      }
    }
  }
  tags = flatten(var.network_tags)
  service_account {
    # An empty string service account will default to the projects default compute engine service account
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
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

  metadata = {
    startup-script = var.primary_startup_url
    post_deployment_script = var.post_deployment_script

    sap_ibm_db2_sid = var.db2_sid

    sap_deployment_debug = var.sap_deployment_debug
  }
}
