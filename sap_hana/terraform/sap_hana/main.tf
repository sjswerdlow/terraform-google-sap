# Main.tf file for hana template
#
#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
################################################
# Local variables for memory and cpu lookups
################################################
locals {
  mem_map = {
    "n1-highmem-32" : 208,
    "n1-highmem-64" : 416,
    "n1-highmem-96" : 624,
    "n1-megamem-96": 1433,
    "n2-highmem-32" : 256,
    "n2-highmem-48" : 386,
    "n2-highmem-64" : 512,
    "n2-highmem-80" : 640,
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
    "n1-highmem-32" : "Intel Broadwell",
    "n1-highmem-64" : "Intel Broadwell",
    "n1-highmem-96" : "Intel Skylake",
    "n1-megamem-96" : "Intel Skylake",
    "m1-megamem-96" : "Intel Skylake",
  }
  mem_size = lookup(local.mem_map, var.machine_type, 640)
  hana_log_size_min = min(512, max(64, local.mem_size / 2))
  hana_data_size_min = local.mem_size * 12 / 10
  hana_shared_size_min = min(1024, local.mem_size)
  # doubles log and data size if sap_hana_double_size == true; sap_hana_double_size should work but is not used because of readiblity
  hana_log_size = local.hana_log_size_min * (var.sap_hana_double_volume_size == true ? 2 : 1)
  hana_data_size = local.hana_data_size_min * (var.sap_hana_double_volume_size == true ? 2 : 1)
  # scaleout_nodes > 0 then hana_shared_size and pdhdd is changed; assumes that sap_hana_scaleout_nodes is an interger
  hana_shared_size = local.hana_shared_size_min * (var.sap_hana_scaleout_nodes > 0 ? ceil(var.sap_hana_scaleout_nodes / 4) : 1)
  pdhdd_size_default = var.sap_hana_scaleout_nodes > 0 ? 2 * local.mem_size * (var.sap_hana_scaleout_nodes + 1) : 0
  # ensure pd-ssd meets minimum size/performance ; 32 is the min allowed memery and + 1 is there to make sure no undersizing happens
  pdssd_size = max(834, local.hana_log_size + local.hana_data_size + local.hana_shared_size + 32 + 1)
  # ensure pd-hdd for backup is smaller than the maximum pd size
  pdssd_size_worker = max(834, local.hana_log_size + local.hana_data_size + 32 + 1)
  # change PD-HDD size if a custom backup size has been set
  pdhdd_size = var.sap_hana_backup_size > 0 ? var.sap_hana_backup_size : local.pdhdd_size_default
  # network config variables
  zone_split = split("-", var.zone)
  shared_vpc = split("/", var.subnetwork)
  region = "${local.zone_split[0]}-${local.zone_split[1]}"
}

###############################################
# disks
###############################################
resource "google_compute_disk" "sap_hana_pdssd_disks" {
  count = var.sap_hana_scaleout_nodes + 1
  # TODO check if name is correct
  name = format("${var.instance_name}-pdssd%05d", count.index + 1)
  type = "pd-ssd"
  size = local.pdssd_size
  project = var.project_id
  zone = var.zone
}
resource "google_compute_disk" "sap_hana_backup_disk" {
  #TODO check if name is correct
  name = "${var.instance_name}-backup"
  type = "pd-standard"
  size = local.pdhdd_size
  project = var.project_id
  zone = var.zone
}
resource "google_compute_disk" "sap_hana_boot_disks" {
  count = var.sap_hana_scaleout_nodes + 1
  name = format("${var.instance_name}-boot%05d", count.index + 1)
  size = 30 # GB
  project = var.project_id
  zone = var.zone
}

###############################################
# instances
###############################################
resource "google_compute_instance" "sap_hana_primary" {
  provider = google
  name = var.instance_name
  project = var.project_id
  zone = var.zone
  machine_type = var.machine_type
  min_cpu_platform = lookup(local.cpu_map, var.machine_type, "Automatic")
  boot_disk {
    auto_delete = true
    device_name = "boot"
    initialize_params {
      image = "${var.linux_image_project}/${var.linux_image}"
    }
  }
  attached_disk {
    device_name = google_compute_disk.sap_hana_pdssd_disks[0].name
    source = google_compute_disk.sap_hana_pdssd_disks[0].self_link
  }
  attached_disk {
    device_name = google_compute_disk.sap_hana_backup_disk.name
    source = google_compute_disk.sap_hana_backup_disk.self_link
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

  service_account {
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  metadata = {
    sap_hana_deployment_bucket = var.sap_hana_deployment_bucket
    sap_deployment_debug = var.sap_deployment_debug
    post_deployment_script = var.post_deployment_script
    sap_hana_sid = var.sap_hana_sid
    sap_hana_instance_number = var.sap_hana_instance_number
    sap_hana_sid_adm_password = var.sap_hana_sid_adm_password
    # wording on system_adm_password may be inconsitent with DM
    sap_hana_system_password = var.sap_hana_system_adm_password
    sap_hana_sidadm_uid = var.sap_hana_sidadm_uid
    sap_hana_sapsys_gid = var.sap_hana_sapsys_gid
    sap_hana_scaleout_nodes = var.sap_hana_scaleout_nodes
  }

  metadata_startup_script = var.primary_startup_url

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}

# creates additional workers
resource "google_compute_instance" "sap_hana_workers" {
  provider = google
  count = var.sap_hana_scaleout_nodes
  name = "${var.instance_name}w${count.index + 1}"
  project = var.project_id
  zone = var.zone
  machine_type = var.machine_type
  boot_disk {
    auto_delete = true
    device_name = "boot"
    initialize_params {
      image =  "${var.linux_image_project}/${var.linux_image}"
    }
  }
  attached_disk {
    device_name = google_compute_disk.sap_hana_pdssd_disks[count.index + 1].name
    source = google_compute_disk.sap_hana_pdssd_disks[count.index + 1].self_link
  }
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

  can_ip_forward = true
  service_account {
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  metadata = {
    sap_hana_deployment_bucket = var.sap_hana_deployment_bucket
    sap_deployment_debug = var.sap_deployment_debug
    post_deployment_script = var.post_deployment_script
    sap_hana_sid = var.sap_hana_sid
    sap_hana_instance_number = var.sap_hana_instance_number
    sap_hana_scaleout_nodes = var.sap_hana_scaleout_nodes
  }
  metadata_startup_script = var.primary_startup_url

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}
