#
# Terraform SAP ASE for Google Cloud
#
# TODO - cannot set reservation affinity
# - reservaction affinity - cannot find it in terraform google module
# this is activly being added, but is not available yet by the google provider:
# https://github.com/hashicorp/terraform-provider-google/pull/7669
# https://github.com/GoogleCloudPlatform/magic-modules/pull/4335
#
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
  ase_sap_data_type = var.ase_sap_data_ssd ? "pd-ssd" : "pd-balanced"
  ase_log_type = var.ase_log_ssd ? "pd-ssd" : "pd-balanced"
}

################################################################################
# disks
################################################################################
resource "google_compute_disk" "sap_ase_boot_disk" {
  name = "${var.instance_name}-boot"
  type = "pd-balanced"
  size = 30 # GB
  zone = var.zone
  project = var.project_id
  image = "${var.linux_image_project}/${var.linux_image}"
}

# /sybase/SID
resource "google_compute_disk" "sap_ase_sid_disk" {
  name = "${var.instance_name}-asesid"
  type = "pd-balanced"
  size = var.ase_sid_size
  zone = var.zone
  project = var.project_id
}

# /sybase/SID/saptemp
resource "google_compute_disk" "sap_ase_saptemp_disk" {
  name = "${var.instance_name}-asesaptemp"
  type = "pd-balanced"
  size = var.ase_sap_temp_size
  zone = var.zone
  project = var.project_id
}

# /sybase/SID/sapdiag
resource "google_compute_disk" "sap_ase_sapdiag_disk" {
  name = "${var.instance_name}-asesapdiag"
  type = "pd-balanced"
  size = var.ase_diag_size
  zone = var.zone
  project = var.project_id
}

# /sybase/SID/saplog_1
resource "google_compute_disk" "sap_ase_log_disk" {
  name = "${var.instance_name}-aselog"
  type = local.ase_log_type
  size = var.ase_log_size
  zone = var.zone
  project = var.project_id
}

# /sybase/SID/sapdata_1
resource "google_compute_disk" "sap_ase_sapdata_disk" {
  name = "${var.instance_name}-asesapdata"
  type = local.ase_sap_data_type
  size = var.ase_sap_data_size
  zone = var.zone
  project = var.project_id
}

# /sybasebackup
resource "google_compute_disk" "sap_ase_backup_disk" {
  name = "${var.instance_name}-asebackup"
  type = "pd-balanced"
  size = var.ase_backup_size
  zone = var.zone
  project = var.project_id
}

# OPTIONAL - /usr/sap
resource "google_compute_disk" "sap_ase_usrsap_disk" {
  count = var.usr_sap_size > 0 ? 1 : 0
  name = "${var.instance_name}-usrsap"
  type = "pd-balanced"
  size = var.usr_sap_size
  zone = var.zone
  project = var.project_id
}

# OPTIONAL - /sapmnt
resource "google_compute_disk" "sap_ase_sapmnt_disk" {
  count = var.sap_mnt_size > 0 ? 1 : 0
  name = "${var.instance_name}-sapmnt"
  type = "pd-balanced"
  size = var.sap_mnt_size
  zone = var.zone
  project = var.project_id
}

# OPTIONAL - swap disk
resource "google_compute_disk" "sap_ase_swap_disk" {
  count = var.swap_size > 0 ? 1 : 0
  name = "${var.instance_name}-swap"
  type = "pd-balanced"
  size = var.swap_size
  zone = var.zone
  project = var.project_id
}

################################################################################
# instances
################################################################################
resource "google_compute_instance" "sap_ase" {
  name = var.instance_name
  zone = var.zone
  project = var.project_id
  machine_type = var.machine_type
  min_cpu_platform = "Automatic"
  boot_disk {
    auto_delete = true
    device_name = "boot"
    source =  google_compute_disk.sap_ase_boot_disk.self_link
  }

  # /sybase/SID
  attached_disk {
    device_name = google_compute_disk.sap_ase_sid_disk.name
    source = google_compute_disk.sap_ase_sid_disk.self_link
  }
  # /sybase/SID/saptemp
  attached_disk {
    device_name = google_compute_disk.sap_ase_saptemp_disk.name
    source = google_compute_disk.sap_ase_saptemp_disk.self_link
  }
  # /sybase/SID/sapdiag
  attached_disk {
    device_name = google_compute_disk.sap_ase_sapdiag_disk.name
    source = google_compute_disk.sap_ase_sapdiag_disk.self_link
  }
  # /sybase/SID/saplog_1
  attached_disk {
    device_name = google_compute_disk.sap_ase_log_disk.name
    source = google_compute_disk.sap_ase_log_disk.self_link
  }
  # /sybase/SID/sapdata_1
  attached_disk {
    device_name = google_compute_disk.sap_ase_sapdata_disk.name
    source = google_compute_disk.sap_ase_sapdata_disk.self_link
  }
  # /sybasebackup
  attached_disk {
    device_name = google_compute_disk.sap_ase_backup_disk.name
    source = google_compute_disk.sap_ase_backup_disk.self_link
  }
  # OPTIONAL - /usr/sap
  dynamic "attached_disk" {
    for_each = var.usr_sap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_ase_usrsap_disk[0].name
      source = google_compute_disk.sap_ase_usrsap_disk[0].self_link
    }
  }
  # OPTIONAL - /sapmnt
  dynamic "attached_disk" {
    for_each = var.sap_mnt_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_ase_sapmnt_disk[0].name
      source = google_compute_disk.sap_ase_sapmnt_disk[0].self_link
    }
  }
  # OPTIONAL - swap disk
  dynamic "attached_disk" {
    for_each = var.swap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.sap_ase_swap_disk[0].name
      source = google_compute_disk.sap_ase_swap_disk[0].self_link
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
    post_deployment_script = var.post_deployment_script
    sap_deployment_debug = var.sap_deployment_debug
    sap_ase_sid = var.ase_sid
  }

  metadata_startup_script = var.primary_startup_url

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}
