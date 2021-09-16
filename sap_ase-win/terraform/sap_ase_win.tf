module "sap_ase_win" {
  source = "TERRAFORM_PREFIXTERRAFORM_URL_LATEST/terraform/sap_ase_win/sap_ase_win_module.zip"
  #
  # By default, this source file uses the latest release of the terraform module
  # for SAP on Google Cloud.  To fix your deployments to a specific release
  # of the module, comment out the source property above and uncomment the source property below.
  #
  # source = "TERRAFORM_PREFIXTERRAFORM_URL/terraform/sap_ase_win/sap_ase_win_module.zip"
  #
  # Fill in the information below
  #
  ##############################################################################
  ## MANDATORY SETTINGS
  ##############################################################################
  # General settings
  machine_type          = "MACHINE_TYPE"          # example: n1-highmem-32
  project_id            = "PROJECT_ID"            # example: my-project-x
  zone                  = "ZONE"                  # example: us-central1-b
  instance_name         = "INSTANCE_NAME"         # example: ase-win-example
  subnetwork            = "SUBNETWORK"            # example: default-subnet1
  windows_image         = "WINDOWS_IMAGE"         # example: windows-server-2019-dc
  windows_image_project = "WINDOWS_IMAGE_PROJECT" # example: windows-cloud

  ##############################################################################
  ## OPTIONAL SETTINGS
  ##   - default values will be determined/calculated
  ##############################################################################
  # ase_sid_size          = DB_SID_DISK_SIZE_IN_GB   # default is 8, minimum is 8
  # ase_sap_temp_size     = SAP_TEMP_DISK_SIZE_IN_GB # default is 8, minimum is 8
  # ase_sap_data_size     = SAP_DATA_DISK_SIZE_IN_GB # default is 30, minimum is 30
  # ase_sap_data_ssd      = [true|false]             # default is true
  # ase_log_size          = LOG_DIR_DISK_SIZE_IN_GB  # default is 8, minimum is 8
  # ase_log_ssd           = [true|false]             # default is true
  # ase_backup_size       = BACKUP_DISK_SIZE_IN_GB   # default is 10
  # usr_sap_size          = USR_SAP_DISK_SIZE_IN_GB  # default is 0
  # swap_size             = SWAP_SIZE_IN_GB          # default is 0
  #
  # --- Advanced Options ---
  # The following advanced options are not usually needed. To use an advanced option, remove
  # the comment indicator, #, before the parameter name and specify an appropriate value.
  #
  # network_tag: [TAG]
  #    Adds a network tag to your instance. This is useful if you do routing or define
  #    firewall rules by tags. By default, no tags are added to your VM.
  #
  # public_ip: [true | false]
  #    Defines whether a public IP address should be added to your VM. By default this is
  #    set to true. Note that if you set this to false without appropriate network nat and
  #    tags in place, there will be no route to the internet and thus the installation could
  #    fail.
  #
  # use_reservation_name: [RESERVATION_NAME]
  #    Use a reservation specified by RESERVATION_NAME.  By default ANY reservation is used.
  #    In order for a reservation to be used it must be created with the
  #    "Select specific reservation" selected (specificReservationRequired set to true)
  #
  # service_account: [CUSTOM_SERVICE_ACCOUNT]
  #    By default, the VM's will be deployed using the default project service account. If
  #    you wish, you can create your own service account with locked down permissions and
  #    specify the name of the account here. Note that an incorrectly defined service
  #    account will prevent a successful deployment. Example of a correctly specified
  #    custom service account: myserviceuser@myproject.iam.gserviceaccount.com
}
