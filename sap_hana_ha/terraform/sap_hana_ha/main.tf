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
    "n2-highmem-48"   = 386
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
    "m2-ultramem-208" = 5916
    "m2-megamem-416"  = 5916
    "m2-ultramem-416" = 11832
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
    "m2-ultramem-416" = "Automatic"
  }
  mem_size = lookup(local.mem_size_map, var.machine_type, 640)
  hana_log_size_min = min(512, max(64, local.mem_size / 2))
  hana_data_size_min = local.mem_size * 12 / 10
  hana_shared_size_min = min(1024, local.mem_size)

  default_boot_size = 30

  # doubles log and data size if sap_hana_double_volume_size == true; sap_hana_double_volume_size should work but is not used because of readiblity
  hana_log_size = local.hana_log_size_min * (var.sap_hana_double_volume_size == true ? 2 : 1)
  hana_data_size = local.hana_data_size_min * (var.sap_hana_double_volume_size == true ? 2 : 1)

  all_network_tag_items = concat(var.network_tags, ["sap-${local.healthcheck_name}-port"])
  network_tags = var.use_ilb_vip ? local.all_network_tag_items : var.network_tags

  pdhdd_size = var.sap_hana_backup_size > 0 ? var.sap_hana_backup_size : 2 * local.mem_size

  # determine default log/data/shared sizes
  hana_shared_size = min(1024, local.mem_size + 0)

  # ensure pd-ssd meets minimum size/performance
  pdssd_size = ceil(max(834, local.hana_log_size + local.hana_data_size + local.hana_shared_size + 32 + 1))

  sap_vip_solution = var.use_ilb_vip ? "ILB" : ""
  sap_hc_port = var.use_ilb_vip ? (60000 + var.sap_hana_instance_number) : 0

  # Note that you can not have default values refernce another variable value
  primary_instance_group_name = var.primary_instance_group_name != "" ? var.primary_instance_group_name : "ig-${var.primary_instance_name}"
  secondary_instance_group_name = var.secondary_instance_group_name != "" ? var.secondary_instance_group_name : "ig-${var.secondary_instance_name}"
  loadbalancer_name = "${var.loadbalancer_name != "" ? var.loadbalancer_name : "lb-${lower(var.sap_hana_sid)}"}-ilb"
  loadbalancer_address_name = "lb-${lower(var.sap_hana_sid)}-address"
  loadbalancer_address = var.sap_vip
  healthcheck_name = "${var.loadbalancer_name != "" ? var.loadbalancer_name : "lb-${lower(var.sap_hana_sid)}"}-hc"
  forwardingrule_name = "${var.loadbalancer_name != "" ? var.loadbalancer_name : "lb-${lower(var.sap_hana_sid)}"}-fwr"

  split_network = split(var.network, ",")
  is_vpc_network = length(local.split_network) > 1
  is_basic_network = !local.is_vpc_network && length(var.network) > 1

  # Network: with Shared VPC option with ILB
  is_subnetwork_split = local.is_vpc_network
  possible_network = local.is_vpc_network ? (
    "https://www.googleapis.com/compute/v1/projects/${local.split_network[0]}/global/networks/${local.split_network[1]}"
    ) : (
    "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/networks/${var.network}"
  )
  processed_network = local.is_basic_network ? (
    "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/networks/default"
    ) : local.possible_network

  # network config variables
  zone_split = split("-", var.primary_zone)
  region = "${local.zone_split[0]}-${local.zone_split[1]}"
  subnetwork_split = split("/", var.subnetwork)
}

################################################################################
# Primary Instance
################################################################################
################################################################################
# disks
################################################################################
resource "google_compute_disk" "sap_hana_ha_primary_boot_disk" {
  name = "${var.primary_instance_name}-boot"
  type = "pd-standard"
  zone = var.primary_zone
  size = local.default_boot_size
  project = var.project_id
  image = "${var.linux_image_project}/${var.linux_image}"
}
resource "google_compute_disk" "sap_hana_ha_primary_pdssd_disk" {
  name = "${var.primary_instance_name}-pdssd"
  type = "pd-ssd"
  zone = var.primary_zone
  size = local.pdssd_size
  project = var.project_id
}
resource "google_compute_disk" "sap_hana_ha_primary_backup_disk" {
  name = "${var.primary_instance_name}-backup"
  type = "pd-standard"
  zone = var.primary_zone
  size = local.pdhdd_size
  project = var.project_id
}

################################################################################
# instance
################################################################################
resource "google_compute_instance" "sap_hana_ha_primary_instance" {
  name = var.primary_instance_name
  machine_type = var.machine_type
  zone = var.primary_zone
  project = var.project_id

  min_cpu_platform = lookup(local.cpu_platform_map, var.machine_type, "Automatic")

  boot_disk {
    auto_delete = true
    device_name = "boot"
    source = google_compute_disk.sap_hana_ha_primary_boot_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_hana_ha_primary_pdssd_disk.name
    source = google_compute_disk.sap_hana_ha_primary_pdssd_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_hana_ha_primary_backup_disk.name
    source = google_compute_disk.sap_hana_ha_primary_backup_disk.self_link
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

  tags = local.network_tags

  service_account {
    # The default empty service account string will use the projects default compute engine service account
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
    sap_hana_deployment_bucket = var.sap_hana_deployment_bucket
    sap_hana_sid = var.sap_hana_sid
    sap_hana_instance_number = var.sap_hana_instance_number
    sap_hana_sidadm_password = var.sap_hana_sidadm_password
    # wording on system_password may be inconsitent with DM
    sap_hana_system_password = var.sap_hana_system_password
    sap_hana_sidadm_uid = var.sap_hana_sidadm_uid
    sap_hana_sapsys_gid = var.sap_hana_sapsys_gid
    sap_vip = var.sap_vip
    sap_vip_solution = local.sap_vip_solution
    sap_hc_port = local.sap_hc_port
    sap_vip_secondary_range = var.sap_vip_secondary_range
    sap_primary_instance = var.primary_instance_name
    sap_secondary_instance = var.secondary_instance_name
    sap_primary_zone = var.primary_zone
    sap_secondary_zone = var.secondary_zone
    template-type = "TERRAFORM"
  }

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
  name = "${var.secondary_instance_name}-boot"
  type = "pd-standard"
  zone = var.secondary_zone
  size = local.default_boot_size
  project = var.project_id
  image = "${var.linux_image_project}/${var.linux_image}"
}
resource "google_compute_disk" "sap_hana_ha_secondary_pdssd_disk" {
  name = "${var.secondary_instance_name}-pdssd"
  type = "pd-ssd"
  zone = var.secondary_zone
  size = local.pdssd_size
  project = var.project_id
}
resource "google_compute_disk" "sap_hana_ha_secondary_backup_disk" {
  name = "${var.secondary_instance_name}-backup"
  type = "pd-standard"
  zone = var.secondary_zone
  size = local.pdhdd_size
  project = var.project_id
}

################################################################################
# instance
################################################################################
resource "google_compute_instance" "sap_hana_ha_secondary_instance" {
  name = var.secondary_instance_name
  machine_type = var.machine_type
  zone = var.secondary_zone
  project = var.project_id

  min_cpu_platform = lookup(local.cpu_platform_map, var.machine_type, "Automatic")

  boot_disk {
    auto_delete = true
    device_name = "boot"
    source = google_compute_disk.sap_hana_ha_secondary_boot_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_hana_ha_secondary_pdssd_disk.name
    source = google_compute_disk.sap_hana_ha_secondary_pdssd_disk.self_link
  }

  attached_disk {
    device_name = google_compute_disk.sap_hana_ha_secondary_backup_disk.name
    source = google_compute_disk.sap_hana_ha_secondary_backup_disk.self_link
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

  tags = local.network_tags

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
    startup-script = var.secondary_startup_url
    post_deployment_script = var.post_deployment_script
    sap_deployment_debug = var.sap_deployment_debug
    sap_hana_deployment_bucket = var.sap_hana_deployment_bucket
    sap_hana_sid = var.sap_hana_sid
    sap_hana_instance_number = var.sap_hana_instance_number
    sap_hana_sidadm_password = var.sap_hana_sidadm_password
    # wording on system_password may be inconsitent with DM
    sap_hana_system_password = var.sap_hana_system_password
    sap_hana_sidadm_uid = var.sap_hana_sidadm_uid
    sap_hana_sapsys_gid = var.sap_hana_sapsys_gid
    sap_vip = var.sap_vip
    sap_vip_solution = local.sap_vip_solution
    sap_hc_port = local.sap_hc_port
    sap_vip_secondary_range = var.sap_vip_secondary_range
    sap_primary_instance = var.primary_instance_name
    sap_secondary_instance = var.secondary_instance_name
    sap_primary_zone = var.primary_zone
    sap_secondary_zone = var.secondary_zone
    template-type = "TERRAFORM"
  }

  lifecycle {
    # Ignore changes in the instance metadata, since it is modified by the SAP startup script.
    ignore_changes = [metadata]
  }
}


################################################################################
# Optional ILB for VIP
################################################################################
resource "google_compute_instance_group" "sap_hana_ha_primary_instance_group" {
  count = var.use_ilb_vip ? 1 : 0
  name = local.primary_instance_group_name
  zone = var.primary_zone
  instances = [google_compute_instance.sap_hana_ha_primary_instance.id]
  project = var.project_id
}

resource "google_compute_instance_group" "sap_hana_ha_secondary_instance_group" {
  count = var.use_ilb_vip ? 1 : 0
  name = local.secondary_instance_group_name
  zone = var.secondary_zone
  instances = [google_compute_instance.sap_hana_ha_secondary_instance.id]
  project = var.project_id
}

resource "google_compute_region_backend_service" "sap_hana_ha_loadbalancer" {
  count = var.use_ilb_vip ? 1 : 0
  name = local.loadbalancer_name
  region = local.region
  project = var.project_id
  network = local.processed_network
  health_checks = [google_compute_health_check.sap_hana_ha_loadbalancer_hc[0].self_link]

  backend {
      group = google_compute_instance_group.sap_hana_ha_primary_instance_group[0].self_link
  }

  backend {
      group = google_compute_instance_group.sap_hana_ha_secondary_instance_group[0].self_link
  }

  protocol = "TCP"
  load_balancing_scheme = "INTERNAL"
  failover_policy {
    failover_ratio = 1
    drop_traffic_if_unhealthy = true
    disable_connection_drain_on_failover = true
  }
}

resource "google_compute_health_check" "sap_hana_ha_loadbalancer_hc" {
  count = var.use_ilb_vip ? 1 : 0
  name = local.healthcheck_name
  project = var.project_id
  tcp_health_check {
    port = local.sap_hc_port
  }
  check_interval_sec = 10
  healthy_threshold = 2
  timeout_sec = 10
  unhealthy_threshold = 2
}

resource "google_compute_address" "sap_hana_ha_loadbalancer_address" {
  count = var.use_ilb_vip ? 1 : 0
  name = local.loadbalancer_address_name
  project = var.project_id
  address_type = "INTERNAL"
  subnetwork = var.subnetwork
  region = local.region
  address = local.loadbalancer_address
}

resource "google_compute_forwarding_rule" "sap_hana_ha_forwarding_rule" {
  count = var.use_ilb_vip ? 1 : 0
  name = local.forwardingrule_name
  project = var.project_id
  all_ports = true
  network = local.processed_network
  subnetwork = var.subnetwork
  region = local.region
  backend_service = google_compute_region_backend_service.sap_hana_ha_loadbalancer[0].id
  load_balancing_scheme = "INTERNAL"
  ip_address = google_compute_address.sap_hana_ha_loadbalancer_address[0].address
}

resource "google_compute_firewall" "sap_hana_ha_vpc_firewall" {
  count = local.is_shared_vpc ? 1 : 0
  name = "${local.healthcheck_name}-allow-firewall-rule"
  project = var.project_id
  network = local.processed_network
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags = ["sap-${local.healthcheck_name}-port"]
  allow {
      protocol = "tcp"
      ports = ["${local.sap_hc_port}"]
  }
}

