variable project_id {
  type = string
  description = "Project id to create the resources in"
}
variable primary_instance_name {
  description = "Name of primary"
  type = string
}
variable   secondary_instance_name {
  description = "Name of secondary"
  type = string
}
variable   primary_zone {
  description = "Zone to create the resources in."
  type = string
}
variable   secondary_zone {
  description = "Zone to create the resources in"
  type = string
}
variable   machine_type {
  description = "Instance type to deploy for SAP HANA"
  type = string
}
variable   linux_image {
  description = "Linux image to use for deployment It is recommended to use SLES for SAP or RHEL for SAP."
  type = string
}
variable   linux_image_project {
  description = "The project which the Linux image belongs to."
  type = string
}
variable   subnetwork {
  description = "The sub network to deploy the instance in."
  type = string
}
variable   sap_vip_secondary_range {
  description = "OPTIONAL - Specifies the secondary IP range that the VM's virtual IP address will be added to."
  type = string
  default = ""
}
variable   sap_hana_deployment_bucket {
  description = "OPTIONAL - The GCS bucket containing the SAP HANA media. If this is not defined, the GCE instance will be provisioned without SAP HANA installed."
  type = string
  default = ""
}
variable   sap_hana_sid {
  description = "OPTIONAL - The SAP HANA SID. If this is not defined, the GCE instance will be provisioned without SAP HANA installed. SID must adere to SAP standard (Three letters or numbers and start with a letter)."
  type = string
  validation {
    condition     = var.sap_hana_sid == "" || length(var.sap_hana_sid) == 3 && can(regex("^([A-Z][A-Z0-9][A-Z0-9])", var.sap_hana_sid))
    error_message = "The sap_hana_sid must have a length of 3 and match the regex: '([A-Z][A-Z0-9][A-Z0-9])'."
  }
  default = ""
}
variable   sap_hana_instance_number {
  description = "OPTIONAL - The SAP instance number. If this is not defined, the GCE instance will be provisioned without SAP HANA installed."
  type = number
  validation {
    condition     = var.sap_hana_instance_number >= 0 && var.sap_hana_instance_number < 100
    error_message = "The sap_hana_instance_number must be in the range 0 to 99."
  }
  default = 0
}
variable   sap_hana_sidadm_password {
  description = "OPTIONAL - The linux sidadm login password. If this is not defined, the GCE instance will be provisioned without SAP HANA installed. Minimum requirement is 8 characters."
  type = string
  validation {
    condition     = var.sap_hana_sidadm_password == "" || length(var.sap_hana_sidadm_password) >= 8 && can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])", var.sap_hana_sidadm_password))
    error_message = "The sap_hana_sidadm_password must have a length of at least 8 and match the regex: '^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])'."
  }
  default = ""
}
variable   sap_hana_system_password {
  description = "OPTIONAL - The SAP HANA SYSTEM password. If this is not defined, the GCE instance will be provisioned without SAP HANA installed. Minimum requirement is 8 characters with at least 1 number."
  type = string
  validation {
    condition     = var.sap_hana_system_password == "" || length(var.sap_hana_system_password) >= 8 && can(regex("^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])", var.sap_hana_system_password))
    error_message = "The sap_hana_system_password must have a length of at least 8 and match the regex: '^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])'."
  }
  default = ""
}
variable   sap_vip {
  description = "OPTIONAL - The virtual IP address of the alias/route pointing towards the active SAP HANA instance. For a route based solution this IP must sit outside of any defined networks."
  type = string
  default = ""
}
variable   sap_hana_backup_size {
  description = "OPTIONAL - Size in GB of the /hanabackup volume. If this is not set or set to zero, the GCE instance will be provisioned with a hana backup volume of 2 times the total memory."
  type = number
  validation {
    condition     = var.sap_hana_backup_size >= 0 && var.sap_hana_backup_size <= 63000
    error_message = "The variable sap_hana_backup_size valid range is from 1 to 63000."
  }
  default = 0
}
variable   sap_hana_sidadm_uid {
  description = "OPTIONAL - The Linux UID of the <SID>adm user. By default this is set to 900 to avoid conflicting with other OS users."
  type = number
  validation {
    condition     = var.sap_hana_sidadm_uid >= 0 && var.sap_hana_sidadm_uid <= 60000
    error_message = "The variable sap_hana_backup_size valid range is from 0 to 60000."
  }
  default = 900
}
variable   sap_hana_sapsys_gid {
  description = "OPTIONAL - The Linux GID of the SAPSYS group. By default this is set to 79"
  type = number
  validation {
    condition     = var.sap_hana_sapsys_gid >= 0 && var.sap_hana_sapsys_gid <= 60000
    error_message = "The variable sap_hana_sapsys_gid valid range is from 0 to 60000."
  }
  default = 79
}
variable   network_tags {
  description = "OPTIONAL - Network tags can be associated to your instance on deployment. This can be used for firewalling or routing purposes"
  type = list(string)
  default = []
}
variable   public_ip {
  description = "OPTIONAL - Defines whether a public IP address should be added to your VM. By default this is set to Yes. Note that if you set this to No without appropriate network nat and tags in place, there will be no route to the internet and thus the installation will fail."
  type = bool
  default = true
}
variable   sap_hana_double_volume_size {
  description = "OPTIONAL - If this is set to true, the GCE instance will be provisioned with double the amount of disk space to support multiple SAP instances."
  type = bool
  default = false
}
variable   sap_deployment_debug {
  description = "OPTIONAL - If this value is set to true, the deployment will generates verbose deployment logs. Only turn this setting on if a Google support engineer asks you to enable debugging."
  type = bool
  default = false
}
variable   post_deployment_script {
  description = "OPTIONAL - gs:// or https:// location of a script to execute on the created VM's post deployment"
  type = string
  default = ""
}
variable   service_account {
  description = "OPTIONAL - Ability to define a custom service account instead of using the default project service account"
  type = string
  default = ""
}
variable   use_ilb_vip {
  description = "OPTIONAL - Use the Google Internal TCP Load Balancer to manage the virtual IP for the primary resource"
  type = bool
  default = true
}
variable   primary_instance_group_name {
  description = "OPTIONAL - Unmanaged instance group to be created for the primary node. If blank, will use ig-VM_NAME"
  type = string
  default = ""
}
variable   secondary_instance_group_name {
  description = "OPTIONAL - Unmanaged instance group to be created for the secondary node. If blank, will use ig-VM_NAME"
  type = string
  default = ""
}
variable   network {
  description = "OPTIONAL - Network in which the ILB resides including resources like firewall rules."
  type = string
  default = ""
}
variable   loadbalancer_name {
  description = "OPTIONAL - Name of the load balancer that will be created. If left blank with use_ilb_vip set to true, then will use lb-SID as default"
  type = string
  default = ""
}
variable   use_reservation_name {
  description = "OPTIONAL - Ability to use a specified reservation"
  type = string
  default = ""
}
