variable "project_id" {
  type = string
  description = "Project id to create the resources in"
}
variable "zone" {
  type = string
  description = "Zone to create the resources in"
}
variable "instance_name" {
  type = string
  description = "Hostname of the GCE instance"
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
variable "ase_sid" {
  type = string
  description = "The database instance/SID name"
}
variable "ase_sid_size" {
  type = number
  default = 8
  description = "Size of /sybase/[DBSID] - the root diretory of the database instance"
}
variable "ase_diag_size" {
  type = number
  default = 8
  description = "Size of /sybase/[DBSID]/sapdiag - Which holds the diagnostic tablespace for SAPTOOLS"
}
variable "ase_sap_temp_size" {
  type = number
  default = 8
  description = "Size of /sybase/[DBSID]/saptmp - Which holds the database temporary table space"
}
variable "ase_sap_data_size" {
  type = number
  default = 30
  description = "Size of /sybase/[DBSID]/sapdata - Which holds the database data files"
}
variable "ase_log_size" {
  type = number
  default = 8
  description = "Size of /sybase/[DBSID]/logdir - Which holds the database transaction logs"
}
variable "ase_backup_size" {
  type = number
  default = 0
  description = "OPTIONAL - Size of the /sybasebackup volume. If set to 0, no disk will be created"
}
variable "ase_sap_data_ssd" {
  type = bool
  default = true
  description = "SSD toggle for the data drive. If set to true, the data disk will be SSD"
}
variable "ase_log_ssd" {
  type = bool
  default = true
  description = "SSD toggle for the log drive. If set to true, the log disk will be SSD"
}
variable "usr_sap_size" {
  type = number
  default = 0
  description = "OPTIONAL - Only required if you plan on deploying SAP NetWeaver on the same VM as the ase database instance. If set to 0, no disk will be created"
}
variable "sap_mnt_size" {
  type = number
  default = 0
  description = "OPTIONAL - Only required if you plan on deploying SAP NetWeaver on the same VM as the ase database instance. If set to 0, no disk will be created"
}
variable "swap_size" {
  type = number
  default = 0
  description = "OPTIONAL - Only required if you plan on deploying SAP NetWeaver on the same VM as the ase database instance. If set to 0, no disk will be created"
}
variable "network_tags" {
  type = list(string)
  default = []
  description = "OPTIONAL - Network tags can be associated to your instance on deployment. This can be used for firewalling or routing purposes"
}
variable "public_ip" {
  type = bool
  default = true
  description = "OPTIONAL - Defines whether a public IP address should be added to your VM. By default this is set to Yes. Note that if you set this to No without appropriate network nat and tags in place, there will be no route to the internet and thus the installation will fail."
}
variable "service_account" {
  type = string
  default = ""
  description = "OPTIONAL - Ability to define a custom service account instead of using the default project service account"
}
variable "sap_deployment_debug" {
  type = bool
  default = false
  description = "OPTIONAL - If this value is set to anything, the deployment will generates verbose deployment logs. Only turn this setting on if a Google support engineer asks you to enable debugging."
}
variable "post_deployment_script" {
  type = string
  default = ""
  description = "OPTIONAL - gs:// or https:// location of a script to execute on the created VM's post deployment"
}
variable "primary_startup_url" {
  type = string
  default = "curl -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates/sap_ase/startup.sh | bash -x -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates"
  description = "Startup script to be executed when the VM boots, should not be overridden"
}
variable "use_reservation_name" {
  type = string
  default = ""
  description = "Reservation name to use when creating instances"
}
variable "can_ip_forward" {
  type = bool
  default = true
  description = "Whether sending and receiving of packets with non-matching source or destination IPs is allowed"
}
