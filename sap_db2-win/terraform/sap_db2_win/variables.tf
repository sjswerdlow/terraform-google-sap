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

variable "subnetwork" {
  type = string
  description = "The sub network to deploy the instance in."
}

variable "windows_image" {
  type = string
  description = "Windows image name."
}

variable "windows_image_project" {
  type = string
  description = "Windows image project."
}

variable "db2_sid" {
  type = string
  description = "The database instance/SID name."
  validation {
    condition = can(regex("[A-Z][0-9A-Z]{2}", var.db2_sid))
    error_message = "The SID must be 3 characters long, start with a letter, and be composed only of letters and numbers."
  }
}

variable "db2_sid_size" {
  type = number
  description = "Size in GB of D:\\ (DB2) - the root directory of the database instance."
  default = 8
  validation {
    condition = var.db2_sid_size >= 8
    error_message = "SID drive must be at least 8GB."
  }
}

variable "db2_sap_tmp_size" {
  type = number
  description = "Size in GB of T:\\ (TMP) -  which holds the database temporary table space."
  default = 8
  validation {
    condition = var.db2_sap_tmp_size >= 8
    error_message = "Temp drive must be at least 8GB."
  }
}

variable "db2_sap_data_size" {
  type = number
  description = "Size in GB of E:\\ (Data) - which holds the database data files."
  default = 30
  validation {
    condition = var.db2_sap_data_size >= 30
    error_message = "Data drive must be at least 30GB."
  }
}

variable "db2_log_size" {
  type = number
  description = "Size in GB of L:\\ (Logs) - which holds the database transaction logs."
  default = 8
  validation {
    condition = var.db2_log_size >= 8
    error_message = "Log drive must be at least 8GB."
  }
}


variable "db2_backup_size" {
  type = number
  description = "OPTIONAL - Size in GB of X:\\ (Backup) - if set to 0, the volume will not be created."
  default = 0
  validation {
    condition = var.db2_backup_size >= 0
    error_message = "Backup drive size must be positive or 0."
  }
}

variable "usr_sap_size" {
  type = number
  description = "OPTIONAL - Size in GB of the /usr/sap drive. Only required if you plan on deploying SAP NetWeaver on the same VM as the DB2 database instance. If set to 0, no disk will be created."
  default = 0
  validation {
    condition = var.usr_sap_size >= 0
    error_message = "/usr/sap size must be positive or 0."
  }
}

variable "sap_mnt_size" {
  type = number
  description = "OPTIONAL - Size in GB of the /sap/mnt drive. Only required if you plan on deploying SAP NetWeaver on the same VM as the DB2 database instance. If set to 0, no disk will be created"
  default = 0
  validation {
    condition = var.sap_mnt_size >= 0
    error_message = "/sap/mnt size must be positive or 0."
  }
}

variable "db2_sap_data_ssd" {
  type = bool
  description = "SSD toggle for the data drive. If set to true, the data disk will be SSD."
  default = true
}

variable "db2_log_ssd" {
  type = bool
  description = "SSD toggle for the log drive. If set to true, the data disk will be SSD."
  default = true
}

variable "swap_size" {
  type = number
  description = "OPTIONAL - Size in GB of the swap drive. Only required if you plan on deploying SAP NetWeaver on the same VM as the DB2 database instance. If set to 0, no disk will be created"
  default = 0
  validation {
    condition = var.swap_size >= 0
    error_message = "Swap size must be positive or 0."
  }
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

variable "use_reservation_name" {
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
  default = "BUILD.SH_URL/sap_db2-win/startup.ps1"
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
