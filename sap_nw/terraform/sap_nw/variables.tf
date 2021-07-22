variable "instance_name" {
  type = string
  description = "Hostname of the GCE instance"
  validation {
    condition = length(var.instance_name) <= 13
    error_message = "Length of instance name must be less than 14 characters."
  }
}

variable "zone" {
  description = "Zone to create the resources in."
  type = string
}

variable "subnetwork" {
  type = string
  description = "The sub network to deploy the instance in."
}

variable "linux_image" {
  type = string
  description = "Linux image name to use e.g family/sles-12-sp3-sap will use the latest SLES 12 SP3 image - https://cloud.google.com/compute/docs/images#image_families"
}

variable "linux_image_project" {
  type = string
  description = "The project which the Linux image belongs to."
}

variable "usr_sap_size" {
  type = number
  description = "Size of /usr/sap disk"
  default = 0
  validation {
    condition = var.usr_sap_size >= 8 || var.usr_sap_size == 0
    error_message = "Size of /usr/sap must be larger than 7 GB or zero (default)."
  }
}

variable "sap_mnt_size" {
  type = number
  description = "Size of /sap/mnt disk"
  default = 0
  validation {
    condition = var.sap_mnt_size >= 8 || var.sap_mnt_size == 0
    error_message = "Size of /sapmnt must be larger than 7 GB or zero (default)."
  }
}

variable "machine_type" {
  type = string
  description = "Machine type for the instances"
}

variable "project_id" {
  type = string
  description = "Project id to create the resources in"
}

variable "swap_size" {
  type = number
  description = "Size of swap volume"
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

variable "public_IP" {
  type = bool
  description = "OPTIONAL - Defines whether a public IP address should be added to your VM. By default this is set to Yes. Note that if you set this to No without appropriate network nat and tags in place, there will be no route to the internet and thus the installation will fail."
  default = true
}

variable "sap_deployment_debug" {
  type = bool
  description = "OPTIONAL - If this value is set to anything, the deployment will generates verbose deployment logs. Only turn this setting on if a Google support engineer asks you to enable debugging."
  default = false
}

variable "post_deployment_script" {
  type = string
  description = "OPTIONAL - gs:// or https:// location of a script to execute on the created VM's post deployment"
  default = ""
}

variable "service_account" {
  type = string
  description = "OPTIONAL - Ability to define a custom service account instead of using the default project service account"
  default = ""
}

variable "primary_startup_url" {
  type = string
  default = "curl -s BUILD.TERRA_SH_URL/sap_nw/startup.sh | bash -x -s BUILD.TERRA_SH_URL"
  description = "Startup script to be executed when the VM boots, should not be overridden"
}

variable "use_reservation_name" {
  type = string
  description = "OPTIONAL - Ability to use a specified reservation"
  default = ""
}

variable "can_ip_forward" {
  type = bool
  default = true
  description = "Whether sending and receiving of packets with non-matching source or destination IPs is allowed"
}
