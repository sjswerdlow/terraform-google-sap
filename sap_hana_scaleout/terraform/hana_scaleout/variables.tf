
variable "project_id" {
  type = string
  description = "Project id where the instances will be created"
}
variable "zone" {
  type = string
  description = "Zone where the instances will be created"
}
variable "instance_name" {
  type = string
  description = "Naming prefix for the instances created"
}
variable "machine_type" {
  type = string
  description = "Machine type for the instances"
}
variable "subnetwork" {
  type = string
  default = "default"
  description = "Subnetwork for the instance"
}
variable "linux_image" {
  type = string
  description = "Linux image name"
}
variable "linux_image_project" {
  type = string
  description = "Linux image project"
}
variable "sap_hana_deployment_bucket" {
  type = string
  description = "Google Cloud Storage bucket that contains the HANA media"
}
variable "sap_hana_sid" {
  type = string
  description = "SAP HANA SID"
}
variable "sap_hana_instance_number" {
  type = string
  default = "00"
  description = "SAP HANA instance number"
}
variable "sap_hana_sidadm_password" {
  type = string
  default = "changeme"
  sensitive = true
  description = "SAP HANA sidadm user password - be sure to change this after deployment"
}
variable "sap_hana_system_password" {
  type = string
  default = "changeme"
  sensitive = true
  description = "SAP HANA system user password - be sure to change this after deployment"
}
variable "sap_hana_worker_nodes" {
  type = number
  default = 1
  description = <<-EOT
  Number of worker nodes to create
  This is in addition to the primary node
  EOT
}
variable "sap_hana_standby_nodes" {
  type = number
  default = 1
  description = "Number of standby nodes to create"
}
variable "sap_hana_shared_nfs" {
  type = string
  description = "Google Filestore share for /hana/shared"
}
variable "sap_hana_backup_nfs" {
  type = string
  description = "Google Filestore share for /hanabackup"
}
#
# Optional Settings
#
variable "sap_hana_double_volume_size" {
  type = bool
  default = false
  description = "Doubles the PD volume size calculated"
}
variable "public_ip" {
  type = bool
  default = false
  description = "Create an ephemeral public ip for the instances"
}
variable "service_account" {
  type = string
  default = ""
  description = <<-EOT
  Service account that will be used as the service account on the created instance.
  Leave this blank to use the project default service account
  EOT
}
variable "network_tags" {
  type = list(string)
  default = []
  description = "Network tags to apply to this instance"
}
variable "sap_hana_sidadm_uid" {
  type = number
  default = 900
  description = "SAP HANA sidadm uid"
}
variable "sap_hana_sapsys_gid" {
  type = number
  default = 79
  description = "SAP HANA sidadm gid"
}
variable "use_reservation_name" {
  type = string
  default = ""
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
}
variable "sap_deployment_debug" {
  type = bool
  default = false
  description = "Debug mode. Do not enable debug mode unless you are asked by support to turn it on."
}
#
# DO NOT MODIFY unless you know what you are doing
#
variable "primary_startup_url" {
  type = string
  default = "curl -s BUILD.SH_URL/sap_hana_scaleout/startup.sh | bash -s BUILD.SH_URL"
  description = "DO NOT USE"
}
variable "secondary_startup_url" {
  type = string
  default = "curl -s BUILD.SH_URL/sap_hana_scaleout/startup_secondary.sh | bash -s BUILD.SH_URL"
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
