#
# Terraform SAP HANA Scaleout for Google Cloud
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

provider "google" {
  project = var.project_id
  zone = var.zone
}

################################################################################
# Local variables
################################################################################
locals {
  mem_map = {
    "n1-highmem-32": 208,
    "n1-highmem-64": 416,
    "n1-highmem-96": 624,
    "n1-megamem-96": 1433,
    "n1-ultramem-40": 961,
    "n1-ultramem-80": 1922,
    "n1-ultramem-160": 3844,
    "m1-megamem-96": 1433,
    "m1-ultramem-40": 961,
    "m1-ultramem-80": 1922,
    "m1-ultramem-160": 3844,
    "m2-ultramem-208": 5916,
    "m2-megamem-416": 5916,
    "m2-ultramem-416": 11832,
  }
  cpu_map = {
    "n1-highmem-32": "Intel Broadwell",
    "n1-highmem-64": "Intel Broadwell",
    "n1-highmem-96": "Intel Skylake",
    "n1-megamem-96": "Intel Skylake",
    "m1-megamem-96": "Intel Skylake",
  }
  mem_size = lookup(local.mem_map, var.machine_type, 256)
  hana_log_size_min = min(512, max(64, local.mem_size / 2))
  hana_data_size_min = local.mem_size * 12 / 10
  # we double the log and data sizes if sap_hana_double_volume_size is true and mem_size != 208
  hana_log_size = var.sap_hana_double_volume_size == true && local.mem_size != 208 ? local.hana_log_size_min * 2 : local.hana_log_size_min
  hana_data_size = var.sap_hana_double_volume_size == true && local.mem_size != 208 ? local.hana_data_size_min * 2 : local.hana_data_size_min
  pdssd_size = max(834, local.hana_log_size + local.hana_data_size + 1)
  zone_split = split("-", var.zone)
  shared_vpc = split("/", var.subnetwork)
  region = "${local.zone_split[0]}-${local.zone_split[1]}"
}

################################################################################
# disks
################################################################################
resource "google_compute_disk" "hana_scaleout_pd_disks" {
  # Need a pd disk for primary, worker nodes
  count = var.sap_hana_worker_nodes + 1
  name  = format("${var.instance_name}-mnt%05d", count.index + 1)
  type  = "pd-ssd"
  size = local.pdssd_size
}

resource "google_compute_disk" "hana_scaleout_boot_disks" {
  # Need a disk for primary, worker nodes, standby nodes
  count = var.sap_hana_worker_nodes + var.sap_hana_standby_nodes + 1
  name  = count.index == 0 ? "${var.instance_name}-boot" : "${var.instance_name}w${count.index}-boot"
  type  = "pd-standard"
  size = 45
  image = "${var.linux_image_project}/${var.linux_image}"
}

################################################################################
# instances
################################################################################
resource "google_compute_instance" "hana_scaleout_primary" {
  # We will have a primary, worker nodes, and standby nodes
  name = var.instance_name
  machine_type = var.machine_type
  min_cpu_platform = lookup(local.cpu_map, var.machine_type, "Automatic")
  boot_disk {
    auto_delete = true
    device_name = "boot"
    source =  "projects/${var.project_id}/zones/${var.zone}/disks/${var.instance_name}-boot"
  }
  attached_disk {
    # we only attach the PDs to the primary and workers
    device_name = google_compute_disk.hana_scaleout_pd_disks[0].name
    source = google_compute_disk.hana_scaleout_pd_disks[0].self_link
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
  tags = var.network_tags
  service_account {
    # An empty string service account will default to the projects default compute engine service account
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/devstorage.read_write"
    ]
  }

  metadata = {
    sap_hana_deployment_bucket = var.sap_hana_deployment_bucket
    sap_deployment_debug = var.sap_deployment_debug
    post_deployment_script = var.post_deployment_script
    sap_hana_original_role = "master"
    sap_hana_sid = var.sap_hana_sid
    sap_hana_instance_number = var.sap_hana_instance_number
    sap_hana_sidadm_password = var.sap_hana_sidadm_password
    sap_hana_system_password = var.sap_hana_system_password
    sap_hana_sidadm_uid = var.sap_hana_sidadm_uid
    sap_hana_shared_nfs = var.sap_hana_shared_nfs
    sap_hana_backup_nfs = var.sap_hana_backup_nfs
    sap_hana_scaleout_nodes = var.sap_hana_worker_nodes + var.sap_hana_standby_nodes
    sap_hana_worker_nodes = var.sap_hana_worker_nodes
    sap_hana_standby_nodes = var.sap_hana_standby_nodes
  }

  metadata_startup_script = var.primary_startup_url

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}

resource "google_compute_instance" "hana_scaleout_workers" {
  # We will have a primary, worker nodes, and standby nodes
  count = var.sap_hana_worker_nodes
  name = "${var.instance_name}w${count.index + 1}"
  machine_type = var.machine_type
  min_cpu_platform = lookup(local.cpu_map, var.machine_type, "Automatic")
  boot_disk {
    auto_delete = true
    device_name = "boot"
    source = "projects/${var.project_id}/zones/${var.zone}/disks/${var.instance_name}w${count.index + 1}-boot"
  }
  attached_disk {
    # we only attach the PDs to the primary and workers
    device_name = google_compute_disk.hana_scaleout_pd_disks[count.index + 1].name
    source = google_compute_disk.hana_scaleout_pd_disks[count.index + 1].self_link
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
  tags = var.network_tags
  service_account {
    # An empty string service account will default to the projects default compute engine service account
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/devstorage.read_write"
    ]
  }

  metadata = {
    sap_hana_deployment_bucket = var.sap_hana_deployment_bucket
    sap_deployment_debug = var.sap_deployment_debug
    post_deployment_script = var.post_deployment_script
    sap_hana_original_role = "worker"
    sap_hana_sid = var.sap_hana_sid
    sap_hana_instance_number = var.sap_hana_instance_number
    sap_hana_sidadm_password = var.sap_hana_sidadm_password
    sap_hana_system_password = var.sap_hana_system_password
    sap_hana_sidadm_uid = var.sap_hana_sidadm_uid
    sap_hana_shared_nfs = var.sap_hana_shared_nfs
    sap_hana_backup_nfs = var.sap_hana_backup_nfs
    sap_hana_scaleout_nodes = var.sap_hana_worker_nodes + var.sap_hana_standby_nodes
    sap_hana_worker_nodes = var.sap_hana_worker_nodes
    sap_hana_standby_nodes = var.sap_hana_standby_nodes
  }

  metadata_startup_script = var.secondary_startup_url

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }

  depends_on = [
    google_compute_instance.hana_scaleout_primary,
  ]
}

resource "google_compute_instance" "hana_scaleout_standbys" {
  # We will have a primary, worker nodes, and standby nodes
  count = var.sap_hana_standby_nodes
  name = "${var.instance_name}w${count.index + var.sap_hana_worker_nodes + 1}"
  machine_type = var.machine_type
  min_cpu_platform = lookup(local.cpu_map, var.machine_type, "Automatic")
  boot_disk {
    auto_delete = true
    device_name = "boot"
    source = "projects/${var.project_id}/zones/${var.zone}/disks/${var.instance_name}w${count.index + var.sap_hana_worker_nodes + 1}-boot"
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
  tags = var.network_tags
  service_account {
    # An empty string service account will default to the projects default compute engine service account
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/compute",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/trace.append",
      "https://www.googleapis.com/auth/devstorage.read_write"
    ]
  }

  metadata = {
    sap_hana_deployment_bucket = var.sap_hana_deployment_bucket
    sap_deployment_debug = var.sap_deployment_debug
    post_deployment_script = var.post_deployment_script
    sap_hana_original_role = "standby"
    sap_hana_sid = var.sap_hana_sid
    sap_hana_instance_number = var.sap_hana_instance_number
    sap_hana_sidadm_password = var.sap_hana_sidadm_password
    sap_hana_system_password = var.sap_hana_system_password
    sap_hana_sidadm_uid = var.sap_hana_sidadm_uid
    sap_hana_shared_nfs = var.sap_hana_shared_nfs
    sap_hana_backup_nfs = var.sap_hana_backup_nfs
    sap_hana_scaleout_nodes = var.sap_hana_worker_nodes + var.sap_hana_standby_nodes
    sap_hana_worker_nodes = var.sap_hana_worker_nodes
    sap_hana_standby_nodes = var.sap_hana_standby_nodes
  }

  metadata_startup_script = var.secondary_startup_url

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }

  depends_on = [
    google_compute_instance.hana_scaleout_primary,
  ]
}
