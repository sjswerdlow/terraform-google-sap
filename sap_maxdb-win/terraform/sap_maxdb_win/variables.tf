variable "machine_type" {
  type = string
  description = "Machine type for the instances."
}

variable "project_id" {
  type = string
  description = "Project id where the instances will be created."
}

variable "zone" {
  type = string
  description = "Zone where the instances will be created."
}

variable "instance_name" {
  type = string
  description = "Naming prefix for the instances created."
}

variable "network" {
  type = string
  description = "Network for the instances."
}

variable "subnetwork" {
  type = string
  description = "The sub network to deploy the instance in."
}

variable "windows_image" {
  type = string
  description = "Windows image name to use. amily/windows-cloud to use the latest Google supplied Windows images."
}

variable "windows_image_project" {
  type = string
  description = "The project which the Windows image belongs to."
}

variable "maxdb_root_size" {
  type = number
  description = "Size in GB of D:\\ (MaxDB) - the  diretory of the database instance."
  default = 8
  validation {
    condition     = var.maxdb_root_size >= 8
    error_message = "Root drive must be at least 8 GB."
  }
}

variable "maxdb_data_size" {
  type = number
  description = "Size in GB of E:\\ (Data) - Which holds the database data files."
  default = 30
  validation {
    condition     = var.maxdb_data_size >= 30
    error_message = "Data drive must be at least 30 GB."
  }
}

variable "maxdb_log_size" {
  type = number
  description = "Size of L:\\ (Logs) - Which holds the database transaction logs."
  default = 8
  validation {
    condition     = var.maxdb_log_size >= 8
    error_message = "Log drive must be at least 8 GB."
  }
}

variable "maxdb_backup_size" {
  type = number
  description = "Size in GB of X:\\ (Backup)."
  default = 10
}

variable "maxdb_data_ssd" {
  type = bool
  description = "SSD toggle for the data drive. If set to true, the data disk will be SSD."
  default = true
}

variable "maxdb_log_ssd" {
  type = bool
  description = "SSD toggle for the log drive. If set to true, the log disk will be SSD."
  default = true
}

variable "usr_sap_size" {
  type = number
  description = "OPTIONAL - Only required if you plan on deploying SAP NetWeaver on the same VM as the ase database instance. If set to 0, no disk will be created."
  default = 0
}

variable "swap_size" {
  type = number
  description = "OPTIONAL - Only required if you plan on deploying SAP NetWeaver on the same VM as the ase database instance. If set to 0, no disk will be created."
  default = 0
}

variable "network_tags" {
  type = list(string)
  default = []
  description = "Network tags to apply to the instances."
}

variable "sap_deployment_debug" {
  type = bool
  default = false
  description = "Debug log level for deployment."
}

variable "public_ip" {
  type = bool
  description = "OPTIONAL - Defines whether a public IP address should be added to your VM. By default this is set to Yes. Note that if you set this to No without appropriate network nat and tags in place, there will be no route to the internet and thus the installation will fail."
  default = true
}

variable "reservation_name" {
  type = string
  description = "OPTIONAL - Ability to use a specified reservation."
  default = ""
}

variable "service_account" {
  type = string
  description = "OPTIONAL - Ability to define a custom service account instead of using the default project service account"
  default = ""
}

#
# DO NOT MODIFY unless you know what you are doing
#
variable "primary_startup_url" {
  type = string
  default = "https://storage.googleapis.com/BUILD.SH_URL/sap_ase-win/startup.ps1"
  description = "DO NOT USE"
}
