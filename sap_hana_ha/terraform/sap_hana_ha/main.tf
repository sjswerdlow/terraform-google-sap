/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#
# Terraform SAP HANA HA for Google Cloud
#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#

################################################################################
# Local variables
################################################################################
locals {
  mem_size_map = {
    "n1-highmem-32"   = 208
    "n1-highmem-64"   = 416
    "n1-highmem-96"   = 624
    "n1-megamem-96"   = 1433
    "n2-highmem-32"   = 256
    "n2-highmem-48"   = 384
    "n2-highmem-64"   = 512
    "n2-highmem-80"   = 640
    "n2-highmem-96"   = 768
    "n2-highmem-128"  = 864
    "n1-ultramem-40"  = 961
    "n1-ultramem-80"  = 1922
    "n1-ultramem-160" = 3844
    "m1-megamem-96"   = 1433
    "m1-ultramem-40"  = 961
    "m1-ultramem-80"  = 1922
    "m1-ultramem-160" = 3844
    "m2-ultramem-208" = 5888
    "m2-megamem-416"  = 5888
    "m2-hypermem-416" = 8832
    "m2-ultramem-416" = 11744
    "m3-megamem-64"   = 976
    "m3-megamem-128"  = 1952
    "m3-ultramem-32"  = 976
    "m3-ultramem-64"  = 1952
    "m3-ultramem-128" = 3904
  }
  cpu_platform_map = {
    "n1-highmem-32"   = "Intel Broadwell"
    "n1-highmem-64"   = "Intel Broadwell"
    "n1-highmem-96"   = "Intel Skylake"
    "n1-megamem-96"   = "Intel Skylake"
    "n2-highmem-32"   = "Automatic"
    "n2-highmem-48"   = "Automatic"
    "n2-highmem-64"   = "Automatic"
    "n2-highmem-80"   = "Automatic"
    "n2-highmem-96"   = "Automatic"
    "n2-highmem-128"  = "Automatic"
    "n1-ultramem-40"  = "Automatic"
    "n1-ultramem-80"  = "Automatic"
    "n1-ultramem-160" = "Automatic"
    "m1-megamem-96"   = "Intel Skylake"
    "m1-ultramem-40"  = "Automatic"
    "m1-ultramem-80"  = "Automatic"
    "m1-ultramem-160" = "Automatic"
    "m2-ultramem-208" = "Automatic"
    "m2-megamem-416"  = "Automatic"
    "m2-hypermem-416" = "Automatic"
    "m2-ultramem-416" = "Automatic"
    "m3-megamem-64"   = "Automatic"
    "m3-megamem-128"  = "Automatic"
    "m3-ultramem-32"  = "Automatic"
    "m3-ultramem-64"  = "Automatic"
    "m3-ultramem-128" = "Automatic"
  }

  # Minimum disk sizes are used to ensure throughput. Extreme disks don't need this.
  # All 'over provisioned' capacity is to go onto the data disk.
  min_total_disk_map = {
    "pd-ssd" = 550
    "pd-balanced" = 943
    "pd-extreme" = 0
    "hyperdisk-extreme" = 0
  }
  min_total_disk = local.min_total_disk_map[var.disk_type]

  mem_size             = lookup(local.mem_size_map, var.machine_type, 320)
  hana_log_size    = ceil(min(512, max(64, local.mem_size / 2)))
  hana_data_size_min   = ceil(local.mem_size * 12 / 10)
  hana_shared_size = min(1024, local.mem_size)
  hana_usrsap_size = 32

  default_boot_size = 30

  hana_data_size = max(local.hana_data_size_min, local.min_total_disk - local.hana_usrsap_size - local.hana_log_size - local.hana_shared_size )

  all_network_tag_items = concat(var.network_tags, ["sap-${local.healthcheck_name}-port"])
  network_tags          = local.all_network_tag_items


  # ensure the combined disk meets minimum size/performance ;
  pd_size = ceil(max(local.min_total_disk, local.hana_log_size + local.hana_data_size_min + local.hana_shared_size + local.hana_usrsap_size + 1))

  temp_shared_disk_type = contains(["hyperdisk-extreme", "pd-extreme"], var.disk_type) ? "pd-balanced" : var.disk_type
  temp_usrsap_disk_type = contains(["hyperdisk-extreme", "pd-extreme"], var.disk_type) ? "pd-balanced" : var.disk_type

  final_data_disk_type = var.data_disk_type_override == "" ? var.disk_type : var.data_disk_type_override
  final_log_disk_type = var.log_disk_type_override == "" ? var.disk_type : var.log_disk_type_override
  final_shared_disk_type = var.shared_disk_type_override == "" ? local.temp_shared_disk_type : var.shared_disk_type_override
  final_usrsap_disk_type = var.usrsap_disk_type_override == "" ? local.temp_usrsap_disk_type : var.usrsap_disk_type_override


  unified_pd_size = var.unified_disk_size_override == null ? local.pd_size : var.unified_disk_size_override
  data_pd_size = var.data_disk_size_override == null ? local.hana_data_size : var.data_disk_size_override
  log_pd_size = var.log_disk_size_override == null ? local.hana_log_size : var.log_disk_size_override
  shared_pd_size = var.shared_disk_size_override == null ? local.hana_shared_size : var.shared_disk_size_override
  usrsap_pd_size = var.usrsap_disk_size_override == null ? local.hana_usrsap_size : var.usrsap_disk_size_override
  backup_pd_size = var.sap_hana_backup_size > 0 ? var.sap_hana_backup_size : 2 * local.mem_size


  hdx_iops_map = {
    "data" = max(10000, local.data_pd_size*2)
    "log" = max(10000, local.log_pd_size*2)
    "shared" = null
    "usrsap" = null
    "unified" = max(10000, local.data_pd_size*2) + max(10000, local.log_pd_size*2)
    "worker" = max(10000, local.data_pd_size*2) + max(10000, local.log_pd_size*2)
  }
  null_iops_map = {
    "data" = null
    "log" = null
    "shared" = null
    "usrsap" = null
    "unified" = null
    "worker" = null
  }
  iops_map = {
    "pd-ssd" = local.null_iops_map
    "pd-balanced" = local.null_iops_map
    "pd-extreme" = local.hdx_iops_map
    "hyperdisk-extreme" = local.hdx_iops_map
  }

  final_data_iops = var.data_disk_iops_override == null ? local.iops_map[local.final_data_disk_type]["data"] : var.data_disk_iops_override
  final_log_iops = var.log_disk_iops_override == null ? local.iops_map[local.final_log_disk_type]["log"] : var.log_disk_iops_override
  final_shared_iops = var.shared_disk_iops_override == null ? local.iops_map[local.final_shared_disk_type]["shared"] : var.shared_disk_iops_override
  final_usrsap_iops = var.usrsap_disk_iops_override == null ? local.iops_map[local.final_usrsap_disk_type]["usrsap"] : var.usrsap_disk_iops_override
  final_unified_iops = var.unified_disk_iops_override == null ? local.iops_map[var.disk_type]["unified"] : var.unified_disk_iops_override

  sap_vip_solution = "ILB"
  sap_hc_port      = 60000 + var.sap_hana_instance_number

  # Note that you can not have default values refernce another variable value
  primary_instance_group_name   = var.primary_instance_group_name != "" ? var.primary_instance_group_name : "ig-${var.primary_instance_name}"
  secondary_instance_group_name = var.secondary_instance_group_name != "" ? var.secondary_instance_group_name : "ig-${var.secondary_instance_name}"
  loadbalancer_name_prefix      = var.loadbalancer_name != "" ? var.loadbalancer_name : "lb-${lower(var.sap_hana_sid)}"
  loadbalancer_name             = "${local.loadbalancer_name_prefix}-ilb"
  loadbalancer_address_name     = "${local.loadbalancer_name_prefix}-address"
  loadbalancer_address          = var.sap_vip
  healthcheck_name              = "${local.loadbalancer_name_prefix}-hc"
  forwardingrule_name           = "${local.loadbalancer_name_prefix}-fwr"

  split_network  = split("/", var.network)
  is_vpc_network = length(local.split_network) > 1

  # Network: with Shared VPC option with ILB
  processed_network = local.is_vpc_network ? (
    "https://www.googleapis.com/compute/v1/projects/${local.split_network[0]}/global/networks/${local.split_network[1]}"
    ) : (
    "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/networks/${var.network}"
  )

  # network config variables
  zone_split       = split("-", var.primary_zone)
  region           = "${local.zone_split[0]}-${local.zone_split[1]}"
  subnetwork_split = split("/", var.subnetwork)

  subnetwork_uri = length(local.subnetwork_split) > 1 ? (
    "https://www.googleapis.com/compute/v1/projects/${local.subnetwork_split[0]}/regions/${local.region}/subnetworks/${local.subnetwork_split[1]}") : (
  "https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${local.region}/subnetworks/${var.subnetwork}")

  os_full_name = "${var.linux_image_project}/${var.linux_image}"

  # WLM Information
  wlm_labels = var.is_work_load_management_deployment ? (
    { goog-workload = var.wlm_deployment_name
      sap-ha        = "sap-ha"
      sap-nw        = "sap-nw"
      sap-hana      = "sap-hana"
    }) : ({}
  )

  wlm_metadata = var.is_work_load_management_deployment ? (
    {
      goog-wl-sap-product = "sap-hana-ha-v1"
      goog-wl-sap-sid     = var.sap_hana_sid
      goog-wl-os          = local.os_full_name

  }) : {}

  primary_startup_url   = var.sap_deployment_debug ? replace(var.primary_startup_url, "bash -s", "bash -x -s") : var.primary_startup_url
  secondary_startup_url = var.sap_deployment_debug ? replace(var.secondary_startup_url, "bash -s", "bash -x -s") : var.secondary_startup_url
}

################################################################################
# VIPs
################################################################################

resource "google_compute_address" "sap_hana_ha_vm_ip" {
  count        = 2
  name         = count.index == 0 ? "${var.primary_instance_name}-ip" : "${var.secondary_instance_name}-ip"
  subnetwork   = local.subnetwork_uri
  address_type = "INTERNAL"
  region       = local.region
  project      = var.project_id
  address      = count.index == 0 ? var.primary_static_ip : var.secondary_static_ip
}


################################################################################
# Primary Instance
################################################################################
################################################################################
# disks
################################################################################
resource "google_compute_disk" "sap_hana_ha_primary_boot_disk" {
  name    = "${var.primary_instance_name}-boot"
  type    = "pd-balanced"
  zone    = var.primary_zone
  size    = local.default_boot_size
  project = var.project_id
  image   = local.os_full_name

  lifecycle {
    # Ignores newer versions of the OS image. Removing this lifecycle
    # and re-applying will cause the current disk to be deleted.
    # All existing data will be lost.
    ignore_changes = [image]
  }
}
resource "google_compute_disk" "sap_hana_ha_primary_unified_disks" {
  count   = var.use_single_shared_data_log_disk ?  1 : 0
  name    = "${var.primary_instance_name}-hana"
  type    = var.disk_type
  zone    = var.primary_zone
  size    = local.unified_pd_size
  project = var.project_id
  provisioned_iops = local.final_unified_iops

}

# Split data/log/sap disks
resource "google_compute_disk" "sap_hana_ha_primary_data_disks" {
  count   = var.use_single_shared_data_log_disk ? 0 : 1
  name    = format("${var.primary_instance_name}-data")
  type    = local.final_data_disk_type
  zone    = var.primary_zone
  size    = local.data_pd_size
  project = var.project_id
  provisioned_iops = local.final_data_iops
}
resource "google_compute_disk" "sap_hana_ha_primary_log_disks" {
  count   = var.use_single_shared_data_log_disk ? 0 : 1
  name    = format("${var.primary_instance_name}-log")
  type    = local.final_log_disk_type
  zone    = var.primary_zone
  size    = local.log_pd_size
  project = var.project_id
  provisioned_iops = local.final_log_iops
}
resource "google_compute_disk" "sap_hana_ha_primary_shared_disks" {
  count   = var.use_single_shared_data_log_disk ? 0 : 1
  name    = format("${var.primary_instance_name}-shared")
  type    = local.final_shared_disk_type
  zone    = var.primary_zone
  size    = local.shared_pd_size
  project = var.project_id
  provisioned_iops = local.final_shared_iops
}
resource "google_compute_disk" "sap_hana_ha_primary_usrsap_disks" {
  count   = var.use_single_shared_data_log_disk ? 0 : 1
  name    = format("${var.primary_instance_name}-usrsap")
  type    = local.final_usrsap_disk_type
  zone    = var.primary_zone
  size    = local.usrsap_pd_size
  project = var.project_id
  provisioned_iops = local.final_usrsap_iops
}
resource "google_compute_disk" "sap_hana_ha_primary_backup_disks" {
  count = var.include_backup_disk ? 1 : 0
  name    = "${var.primary_instance_name}-backup"
  type    = "pd-standard"
  zone    = var.primary_zone
  size    = local.backup_pd_size
  project = var.project_id
}

################################################################################
# instance
################################################################################
resource "google_compute_instance" "sap_hana_ha_primary_instance" {
  name         = var.primary_instance_name
  machine_type = var.machine_type
  zone         = var.primary_zone
  project      = var.project_id

  min_cpu_platform = lookup(local.cpu_platform_map, var.machine_type, "Automatic")

  boot_disk {
    auto_delete = true
    device_name = "boot"
    source      = google_compute_disk.sap_hana_ha_primary_boot_disk.self_link
  }

  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [1] : []
    content {
      device_name = google_compute_disk.sap_hana_ha_primary_unified_disks[0].name
      source      = google_compute_disk.sap_hana_ha_primary_unified_disks[0].self_link
    }
  }
  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [] : [1]
    content {
      device_name = google_compute_disk.sap_hana_ha_primary_data_disks[0].name
      source      = google_compute_disk.sap_hana_ha_primary_data_disks[0].self_link
    }
  }
  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [] : [1]
    content {
      device_name = google_compute_disk.sap_hana_ha_primary_log_disks[0].name
      source      = google_compute_disk.sap_hana_ha_primary_log_disks[0].self_link
    }
  }
  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [] : [1]
    content {
      device_name = google_compute_disk.sap_hana_ha_primary_shared_disks[0].name
      source      = google_compute_disk.sap_hana_ha_primary_shared_disks[0].self_link
    }
  }
  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [] : [1]
    content {
      device_name = google_compute_disk.sap_hana_ha_primary_usrsap_disks[0].name
      source      = google_compute_disk.sap_hana_ha_primary_usrsap_disks[0].self_link
    }
  }

  dynamic attached_disk {
    for_each = var.include_backup_disk ? [1] : []
    content {
      device_name = google_compute_disk.sap_hana_ha_primary_backup_disks[0].name
      source      = google_compute_disk.sap_hana_ha_primary_backup_disks[0].self_link
    }
  }
  can_ip_forward = var.can_ip_forward

  network_interface {
    subnetwork = local.subnetwork_uri
    network_ip = google_compute_address.sap_hana_ha_vm_ip.0.address

    nic_type = var.nic_type == "" ? null : var.nic_type
    # we only include access_config if public_ip is true, an empty access_config
    # will create an ephemeral public ip
    dynamic "access_config" {
      for_each = var.public_ip ? [1] : []
      content {
      }
    }
  }

  tags = local.network_tags

  service_account {
    # The default empty service account string will use the projects default compute engine service account
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  dynamic "reservation_affinity" {
    for_each = length(var.primary_reservation_name) > 1 ? [1] : []
    content {
      type = "SPECIFIC_RESERVATION"
      specific_reservation {
        key    = "compute.googleapis.com/reservation-name"
        values = [var.primary_reservation_name]
      }
    }
  }

  labels = local.wlm_labels

  metadata = merge(
    {
      startup-script                  = local.primary_startup_url
      post_deployment_script          = var.post_deployment_script
      sap_deployment_debug            = var.sap_deployment_debug
      sap_hana_deployment_bucket      = var.sap_hana_deployment_bucket
      sap_hana_sid                    = var.sap_hana_sid
      sap_hana_instance_number        = var.sap_hana_instance_number
      sap_hana_sidadm_password        = var.sap_hana_sidadm_password
      sap_hana_sidadm_password_secret = var.sap_hana_sidadm_password_secret
      # wording on system_password may be inconsitent with DM
      sap_hana_system_password        = var.sap_hana_system_password
      sap_hana_system_password_secret = var.sap_hana_system_password_secret
      sap_hana_sidadm_uid             = var.sap_hana_sidadm_uid
      sap_hana_sapsys_gid             = var.sap_hana_sapsys_gid
      sap_vip                         = var.sap_vip
      sap_vip_solution                = local.sap_vip_solution
      sap_hc_port                     = local.sap_hc_port
      sap_primary_instance            = var.primary_instance_name
      sap_secondary_instance          = var.secondary_instance_name
      sap_primary_zone                = var.primary_zone
      sap_secondary_zone              = var.secondary_zone
      use_single_shared_data_log_disk = var.use_single_shared_data_log_disk
      sap_hana_backup_disk            = var.include_backup_disk
      sap_hana_shared_disk            = !var.use_single_shared_data_log_disk
      template-type                   = "TERRAFORM"
    },
    local.wlm_metadata
  )

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}

################################################################################
# Secondary Instance
################################################################################
################################################################################
# disks
################################################################################
resource "google_compute_disk" "sap_hana_ha_secondary_boot_disk" {
  name    = "${var.secondary_instance_name}-boot"
  type    = "pd-balanced"
  zone    = var.secondary_zone
  size    = local.default_boot_size
  project = var.project_id
  image   = local.os_full_name

  lifecycle {
    # Ignores newer versions of the OS image. Removing this lifecycle
    # and re-applying will cause the current disk to be deleted.
    # All existing data will be lost.
    ignore_changes = [image]
  }
}
resource "google_compute_disk" "sap_hana_ha_secondary_unified_disks" {
  count   = var.use_single_shared_data_log_disk ? 1 : 0
  name    = "${var.secondary_instance_name}-hana"
  type    = var.disk_type
  zone    = var.secondary_zone
  size    = local.unified_pd_size
  project = var.project_id
  provisioned_iops = local.final_unified_iops
}

# Split data/log/sap disks
resource "google_compute_disk" "sap_hana_ha_secondary_data_disks" {
  count   = var.use_single_shared_data_log_disk ? 0 : 1
  name    = format("${var.secondary_instance_name}-data")
  type    = local.final_data_disk_type
  zone    = var.secondary_zone
  size    = local.data_pd_size
  project = var.project_id
  provisioned_iops = local.final_data_iops
}
resource "google_compute_disk" "sap_hana_ha_secondary_log_disks" {
  count   = var.use_single_shared_data_log_disk ? 0 : 1
  name    = format("${var.secondary_instance_name}-log")
  type    = local.final_log_disk_type
  zone    = var.secondary_zone
  size    = local.log_pd_size
  project = var.project_id
  provisioned_iops = local.final_log_iops
}
resource "google_compute_disk" "sap_hana_ha_secondary_shared_disks" {
  count   = var.use_single_shared_data_log_disk ? 0 : 1
  name    = format("${var.secondary_instance_name}-shared")
  type    = local.final_shared_disk_type
  zone    = var.secondary_zone
  size    = local.shared_pd_size
  project = var.project_id
  provisioned_iops = local.final_shared_iops
}
resource "google_compute_disk" "sap_hana_ha_secondary_usrsap_disks" {
  count   = var.use_single_shared_data_log_disk ? 0 : 1
  name    = format("${var.secondary_instance_name}-usrsap")
  type    = local.final_usrsap_disk_type
  zone    = var.secondary_zone
  size    = local.usrsap_pd_size
  project = var.project_id
  provisioned_iops = local.final_usrsap_iops
}

resource "google_compute_disk" "sap_hana_ha_secondary_backup_disks" {
  count = var.include_backup_disk ? 1 : 0
  name    = "${var.secondary_instance_name}-backup"
  type    = "pd-standard"
  zone    = var.secondary_zone
  size    = local.backup_pd_size
  project = var.project_id
}

################################################################################
# instance
################################################################################
resource "google_compute_instance" "sap_hana_ha_secondary_instance" {
  name         = var.secondary_instance_name
  machine_type = var.machine_type
  zone         = var.secondary_zone
  project      = var.project_id

  min_cpu_platform = lookup(local.cpu_platform_map, var.machine_type, "Automatic")

  boot_disk {
    auto_delete = true
    device_name = "boot"
    source      = google_compute_disk.sap_hana_ha_secondary_boot_disk.self_link
  }

  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [1] : []
    content {
      device_name = google_compute_disk.sap_hana_ha_secondary_unified_disks[0].name
      source      = google_compute_disk.sap_hana_ha_secondary_unified_disks[0].self_link
    }
  }
  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [] : [1]
    content {
      device_name = google_compute_disk.sap_hana_ha_secondary_data_disks[0].name
      source      = google_compute_disk.sap_hana_ha_secondary_data_disks[0].self_link
    }
  }
  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [] : [1]
    content {
      device_name = google_compute_disk.sap_hana_ha_secondary_log_disks[0].name
      source      = google_compute_disk.sap_hana_ha_secondary_log_disks[0].self_link
    }
  }
  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [] : [1]
    content {
      device_name = google_compute_disk.sap_hana_ha_secondary_shared_disks[0].name
      source      = google_compute_disk.sap_hana_ha_secondary_shared_disks[0].self_link
    }
  }
  dynamic attached_disk {
    for_each = var.use_single_shared_data_log_disk ? [] : [1]
    content {
      device_name = google_compute_disk.sap_hana_ha_secondary_usrsap_disks[0].name
      source      = google_compute_disk.sap_hana_ha_secondary_usrsap_disks[0].self_link
    }
  }

  dynamic attached_disk {
    for_each = var.include_backup_disk ? [1] : []
    content {
      device_name = google_compute_disk.sap_hana_ha_secondary_backup_disks[0].name
      source      = google_compute_disk.sap_hana_ha_secondary_backup_disks[0].self_link
    }
  }

  can_ip_forward = var.can_ip_forward

  network_interface {
    subnetwork = local.subnetwork_uri
    network_ip = google_compute_address.sap_hana_ha_vm_ip.1.address
    nic_type = var.nic_type == "" ? null : var.nic_type
    # we only include access_config if public_ip is true, an empty access_config
    # will create an ephemeral public ip
    dynamic "access_config" {
      for_each = var.public_ip ? [1] : []
      content {
      }
    }
  }

  tags = local.network_tags

  service_account {
    # An empty string service account will default to the projects default compute engine service account
    email = var.service_account
    scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  dynamic "reservation_affinity" {
    for_each = length(var.secondary_reservation_name) > 1 ? [1] : []
    content {
      type = "SPECIFIC_RESERVATION"
      specific_reservation {
        key    = "compute.googleapis.com/reservation-name"
        values = [var.secondary_reservation_name]
      }
    }
  }

  labels = local.wlm_labels

  metadata = merge(
    {
      startup-script                  = local.secondary_startup_url
      post_deployment_script          = var.post_deployment_script
      sap_deployment_debug            = var.sap_deployment_debug
      sap_hana_deployment_bucket      = var.sap_hana_deployment_bucket
      sap_hana_sid                    = var.sap_hana_sid
      sap_hana_instance_number        = var.sap_hana_instance_number
      sap_hana_sidadm_password        = var.sap_hana_sidadm_password
      sap_hana_sidadm_password_secret = var.sap_hana_sidadm_password_secret
      # wording on system_password may be inconsitent with DM
      sap_hana_system_password        = var.sap_hana_system_password
      sap_hana_system_password_secret = var.sap_hana_system_password_secret
      sap_hana_sidadm_uid             = var.sap_hana_sidadm_uid
      sap_hana_sapsys_gid             = var.sap_hana_sapsys_gid
      sap_vip                         = var.sap_vip
      sap_vip_solution                = local.sap_vip_solution
      sap_hc_port                     = local.sap_hc_port
      sap_primary_instance            = var.primary_instance_name
      sap_secondary_instance          = var.secondary_instance_name
      sap_primary_zone                = var.primary_zone
      sap_secondary_zone              = var.secondary_zone
      use_single_shared_data_log_disk = var.use_single_shared_data_log_disk
      sap_hana_backup_disk            = var.include_backup_disk
      sap_hana_shared_disk            = !var.use_single_shared_data_log_disk
      template-type                   = "TERRAFORM"
    },
    local.wlm_metadata
  )

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}


################################################################################
# Optional ILB for VIP
################################################################################
resource "google_compute_instance_group" "sap_hana_ha_primary_instance_group" {
  name      = local.primary_instance_group_name
  zone      = var.primary_zone
  instances = [google_compute_instance.sap_hana_ha_primary_instance.id]
  project   = var.project_id
}

resource "google_compute_instance_group" "sap_hana_ha_secondary_instance_group" {
  name      = local.secondary_instance_group_name
  zone      = var.secondary_zone
  instances = [google_compute_instance.sap_hana_ha_secondary_instance.id]
  project   = var.project_id
}

resource "google_compute_region_backend_service" "sap_hana_ha_loadbalancer" {
  name          = local.loadbalancer_name
  region        = local.region
  project       = var.project_id
  network       = local.processed_network
  health_checks = [google_compute_health_check.sap_hana_ha_loadbalancer_hc.self_link]

  backend {
    group    = google_compute_instance_group.sap_hana_ha_primary_instance_group.self_link
    failover = false
  }

  backend {
    group    = google_compute_instance_group.sap_hana_ha_secondary_instance_group.self_link
    failover = true
  }

  protocol              = "TCP"
  load_balancing_scheme = "INTERNAL"
  failover_policy {
    failover_ratio                       = 1
    drop_traffic_if_unhealthy            = true
    disable_connection_drain_on_failover = true
  }
}

resource "google_compute_health_check" "sap_hana_ha_loadbalancer_hc" {
  name    = local.healthcheck_name
  project = var.project_id
  tcp_health_check {
    port = local.sap_hc_port
  }
  check_interval_sec  = 10
  healthy_threshold   = 2
  timeout_sec         = 10
  unhealthy_threshold = 2
}

resource "google_compute_address" "sap_hana_ha_loadbalancer_address" {
  name         = local.loadbalancer_address_name
  project      = var.project_id
  address_type = "INTERNAL"
  subnetwork   = local.subnetwork_uri
  region       = local.region
  address      = local.loadbalancer_address
}

resource "google_compute_forwarding_rule" "sap_hana_ha_forwarding_rule" {
  name                  = local.forwardingrule_name
  project               = var.project_id
  all_ports             = true
  network               = local.processed_network
  subnetwork            = local.subnetwork_uri
  region                = local.region
  backend_service       = google_compute_region_backend_service.sap_hana_ha_loadbalancer.id
  load_balancing_scheme = "INTERNAL"
  ip_address            = google_compute_address.sap_hana_ha_loadbalancer_address.address
}

resource "google_compute_firewall" "sap_hana_ha_vpc_firewall" {
  count         = local.is_vpc_network ? 0 : 1
  name          = "${local.healthcheck_name}-allow-firewall-rule"
  project       = var.project_id
  network       = local.processed_network
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["sap-${local.healthcheck_name}-port"]
  allow {
    protocol = "tcp"
    ports    = ["${local.sap_hc_port}"]
  }
}

