variable "project_id" {
  type = string
  description = "Project id where the instances will be created."
}

variable "zone" {
  type = string
  description = "Zone where the instances will be created."
}

variable "machine_type" {
  type = string
  description = "Machine type for the instances."
}

variable "subnetwork" {
  type = string
  description = "The sub network to deploy the instance in."
}

variable "windows_image" {
  type = string
  description = "Windows image name to use."
}

variable "windows_image_project" {
  type = string
  description = "The project which the Windows image belongs to."
}

variable "instance_name" {
  type = string
  description = "Hostname of the GCE instance."
  validation {
    condition = can(regex("^[a-z0-9\\-]+$", var.instance_name))
    error_message = "The instance_name must consist of lowercase letters (a-z), numbers, and hyphens."
  }
}

variable "swap_size" {
  type = number
  description = "Size in GB of P:\\ (Pagefile)"
  default = 0
  validation {
    condition = var.swap_size >= 0
    error_message = "Size of swap must be 0 or larger."
  }
}

variable "network_tags" {
  type = list(string)
  description = "OPTIONAL - Network tags can be associated to your instance on deployment. This can be used for firewalling or routing purposes."
  default = []
}

variable "public_ip" {
  type = bool
  description = "OPTIONAL - Defines whether a public IP address should be added to your VM. By default this is set to Yes. Note that if you set this to No without appropriate network nat and tags in place, there will be no route to the internet and thus the installation will fail."
  default = true
}

variable "service_account" {
  type = string
  description = "OPTIONAL - Ability to define a custom service account instead of using the default project service account."
  default = ""
}

variable "sap_deployment_debug" {
  type = bool
  description = "OPTIONAL - If this value is set to true, the deployment will generates verbose deployment logs. Only turn this setting on if a Google support engineer asks you to enable debugging."
  default = false
}

variable "reservation_name" {
  type = string
  description = <<-EOT
  Use a reservation specified by RESERVATION_NAME.
  By default ANY_RESERVATION is used when this variable is empty.
  In order for a reservation to be used it must be created with the
  "Select specific reservation" selected (specificReservationRequired set to true)
  Be sure to create your reservation with the correct Min CPU Platform for the
  following instance types:
  n1-highmem-32 : Intel Broadwell
  n1-highmem-64 : Intel Broadwell
  n1-highmem-96 : Intel Skylake
  n1-megamem-96 : Intel Skylake
  All other instance types can have automatic Min CPU Platform"
  EOT
  default = ""
}

variable "post_deployment_script" {
  type = string
  description = "OPTIONAL - gs:// or https:// location of a script to execute on the created VM's post deployment."
  default = ""
}

#
# DO NOT MODIFY unless you know what you are doing
#
variable "primary_startup_url" {
  type = string
  description = "Startup script to be executed when the VM boots, should not be overridden."
  default = "https://storage.googleapis.com/BUILD.SH_URL/sap_ase-win/startup.ps1"
}

variable "can_ip_forward" {
  type = bool
  description = "Whether sending and receiving of packets with non-matching source or destination IPs is allowed."
  default = true
}
