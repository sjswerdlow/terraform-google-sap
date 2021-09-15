#Variables.tf
#
variable "instance_name" {
  type = string
  description = "Hostname of the GCE instance"
  validation {
    condition = can(regex("^[a-z0-9\\-]+$", var.instance_name))
    error_message = "The instance_name must consist of lowercase letters (a-z), numbers, and hyphens."
  }
}
variable "zone" {
  type = string
  description = "Zone where the instances will be created"
}
variable "subnetwork" {
  type = string
  description = "The sub network to deploy the instance in"
}
variable "linux_image" {
  type = string
  description = "Linux image name to use. family/sles-12-sp2-sap or family/sles-12-sp2-sap will use the latest SLES 12 SP2 or SP3 image"
}
variable "linux_image_project" {
  type = string
  description = "The project which the Linux image belongs to"
}
variable "project_id" {
  type = string
  description = "Project id where the instances will be created"
}
variable "machine_type" {
  type = string
  description = "Machine type for the instances"
}
#
# Optional Settings
#
variable "sap_hana_deployment_bucket" {
  type = string
  default = ""
  description = "The GCS bucket containing the SAP HANA media. If this is not defined, the GCE instance will be provisioned without SAP HANA installed."
}
variable "sap_hana_sid" {
  type = string
  default = ""
  description = "The SAP HANA SID. If this is not defined, the GCE instance will be provisioned without SAP HANA installed. SID must adere to SAP standard (Three letters or numbers and start with a letter)"
  validation {
    condition = (length(var.sap_hana_sid) == 3) && (length(regexall("[A-Z][0-9A-Z][0-9A-Z]",var.sap_hana_sid)) == 1)
    error_message = "The sap_hana_sid must be 3 characters long and start with a letter and all letters must be capatilized."
  }
}
variable "sap_hana_double_volume_size" {
  type = bool
  default = false
  description = "If this is set to Yes or True, the GCE instance will be provisioned with double the amount of disk space to support multiple SAP instances."
}
variable "sap_hana_instance_number" {
  type = number
  default = 0
  description = "The SAP instance number. If this is not defined, the GCE instance will be provisioned without SAP HANA installed."
  validation {
    condition = (var.sap_hana_instance_number >= 0) && (var.sap_hana_instance_number < 100)
    error_message = "The sap_hana_instance_number must be 2 digit long."
  }
}
variable "sap_hana_sid_adm_password" {
  type = string
  default = ""
  description = "The linux sidadm login password. If this is not defined, the GCE instance will be provisioned without SAP HANA installed. Minimum requirement is 8 characters."
  validation {
    condition = length(var.sap_hana_sid_adm_password) >= 8 && ((length(regexall("[0-9]", var.sap_hana_sid_adm_password)) > 0)) && ((length(regexall("[a-z]", var.sap_hana_sid_adm_password)) > 0)) && ((length(regexall("[A-Z]", var.sap_hana_sid_adm_password)) > 0))
    error_message = "The sap_hana_sid_adm_password must have at least 8 characters. Must contain at least one capitalized letter, one lowercase letter, and one number."
  }
}
variable "sap_hana_system_adm_password" {
  type = string
  default = ""
  description = "The SAP HANA SYSTEM password. If this is not defined, the GCE instance will be provisioned without SAP HANA installed. Minimum requirement is 8 characters with at least 1 number."
  validation {
    condition = length(var.sap_hana_system_adm_password) >= 8 && ((length(regexall("[0-9]", var.sap_hana_system_adm_password)) > 0)) && ((length(regexall("[a-z]", var.sap_hana_system_adm_password)) > 0)) && ((length(regexall("[A-Z]", var.sap_hana_system_adm_password)) > 0))
    error_message = "Sap_hana_system_adm_password must have at least 8 characters. Must contain at least one capitalized letter, one lowercase letter, and one number."
  }
}
variable "sap_hana_scaleout_nodes" {
  type = number
  default = 0
  description = "Number of additional nodes to add. E.g - if you wish for a 4 node cluster you would specify 3 here."
}
variable "sap_hana_backup_size" {
  type = number
  default = 0
  description = "Size in GB of the /hanabackup volume. If this is not set or set to zero, the GCE instance will be provisioned with a hana backup volume of 2 times the total memory."
}
variable "sap_hana_sidadm_uid" {
 type = number
 default = 900
 description = "The Linux UID of the <SID>adm user. By default this is set to 900 to avoid conflicting with other OS users."
}
variable "sap_hana_sapsys_gid" {
  type = number
  default = 79
  description = "The Linux GID of the SAPSYS group. By default this is set to 79"
}
variable "network_tag" {
  type = string
  default = ""
  description = "A network tag can be associated to your instance on deployment. This can be used for firewalling or routing purposes."
}
variable "public_ip" {
  type = bool
  default = true
  description = "Defines whether a public IP address should be added to your VM. By default this is set to Yes. Note that if you set this to No without appropriate network nat and tags in place, there will be no route to the internet and thus the installation will fail."
}
variable "sap_deployment_debug" {
  type = bool
  default = false
  description = "If this value is set to anything, the deployment will generates verbose deployment logs. Only turn this setting on if a Google support engineer asks you to enable debugging."
}
variable "service_account" {
  type = string
  default = ""
  description = "Ability to define a custom service account instead of using the default project service account"
}
variable "use_reservation_name" {
  type = string
  default = ""
  description = "Ability to use a specified reservation"
}
#
# DO NOT MODIFY unless you know what you are doing
#
variable "primary_startup_url" {
  type = string
  default = "curl -s BUILD.SH_URL/sap_hana/startup.sh | bash -s BUILD.SH_URL"
  description = "DO NOT USE"
}
variable "secondary_startup_url" {
  type = string
  default = "curl -s BUILD.SH_URL/sap_hana/startup_secondary.sh | bash -s BUILD.SH_URL"
  description = "DO NOT USE"
}
variable "post_deployment_script" {
  type = string
  default = ""
  description = <<-EOT
  Specifies the location of a script to run after the deployment is complete.
  The script should be hosted on a web server or in a GCS bucket. The URL should
  begin with http:// https:// or gs://. Note that this script will be executed
  on all VM's that the template creates. If you only want to run it on the master
  instance you will need to add a check at the top of your script.
  EOT
}
