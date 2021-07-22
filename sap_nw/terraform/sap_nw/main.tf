#
# Terraform SAP NW for Google Cloud
#
#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#


################################################################################
# Local variables
################################################################################
locals {
  shared_vpc = split("/", var.subnetwork)
  zone_split = split("-", var.zone)
  region = "${local.zone_split[0]}-${local.zone_split[1]}"

  cpu_map = {
    "n1-highmem-96": "Intel Skylake",
    "n1-megamem-96": "Intel Skylake",
  }

}


################################################################################
# disks
################################################################################

resource "google_compute_disk" "nw_boot_disk" {
  name  = "${var.instance_name}-boot"
  type  = "pd-balanced"
  zone  = var.zone
  size  = 30
  project = var.project_id
  image = "${var.linux_image_project}/${var.linux_image}"
}

# OPTIONAL - /usr/sap
resource "google_compute_disk" "nw_usrsap_disks" {
  count = var.usr_sap_size > 0 ? 1 : 0
  name  = "${var.instance_name}-usrsap"
  type  = "pd-balanced"
  zone  = var.zone
  size  = var.usr_sap_size
  project = var.project_id
}

# OPTIONAL - /sapmnt
resource "google_compute_disk" "nw_sapmnt_disks" {
  count = var.sap_mnt_size > 0 ? 1 : 0
  name  = "${var.instance_name}-sapmnt"
  type  = "pd-balanced"
  zone  = var.zone
  size  = var.sap_mnt_size
  project = var.project_id
}

# OPTIONAL - swap disk
resource "google_compute_disk" "nw_swap_disks" {
  count = var.swap_size > 0 ? 1 : 0
  name  = "${var.instance_name}-swap"
  type  = "pd-balanced"
  zone  = var.zone
  size  = var.swap_size
  project = var.project_id
}

################################################################################
# instances
################################################################################
resource "google_compute_instance" "sap_nw_instance" {
  provider = google
  name = var.instance_name
  project = var.project_id
  zone = var.zone
  machine_type = var.machine_type
  min_cpu_platform = lookup(local.cpu_map, var.machine_type, "Automatic")

  boot_disk {
    auto_delete = true
    device_name = "boot"
    source =  "projects/${var.project_id}/zones/${var.zone}/disks/${var.instance_name}-boot"
  }

  # OPTIONAL - /usr/sap
  dynamic "attached_disk" {
    for_each = var.usr_sap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.nw_usrsap_disks[0].name
      source = google_compute_disk.nw_usrsap_disks[0].self_link
    }
  }
  # OPTIONAL - /sapmnt
  dynamic "attached_disk" {
    for_each = var.sap_mnt_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.nw_sapmnt_disks[0].name
      source = google_compute_disk.nw_sapmnt_disks[0].self_link
    }
  }
  # OPTIONAL - swap disk
  dynamic "attached_disk" {
    for_each = var.swap_size > 0 ? [1] : []
    content {
      device_name = google_compute_disk.nw_swap_disks[0].name
      source = google_compute_disk.nw_swap_disks[0].self_link
    }
  }

  can_ip_forward = var.can_ip_forward
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
    sap_deployment_debug = var.sap_deployment_debug
    post_deployment_script = var.post_deployment_script
  }

  metadata_startup_script = var.primary_startup_url

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }

}

