#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
module "sap_db2_win" {
  source = "TERRAFORM_PREFIXTERRAFORM_URL_LATEST/terraform/sap_db2-win/sap_db2_win_module.zip"
  #
  # By default, this source file uses the latest release of the terraform module
  # for SAP on Google Cloud.  To fix your deployments to a specific release
  # of the module, comment out the source property above and uncomment the source property below.
  #
  # source = "TERRAFORM_PREFIXTERRAFORM_URL/terraform/sap_db2-win/sap_db2_win_module.zip"
  #
  # Fill in the information below
  #
  #############################################################################
  # MANDATORY SETTINGS
  #############################################################################
  # General settings
  project_id            = [PROJECT_NAME]          # example: my-project-x
  zone                  = [ZONE]                  # example: us-east1-b
  machine_type          = [MACHINE_TYPE]          # example: n1-highmem-32
  subnetwork            = [SUBNETWORK]            # example: default
  windows_image         = [WINDOWS_IMAGE]         # example: rhel-8-4-sap-ha
  windows_image_project = [WINDOWS_IMAGE_PROJECT] # example: rhel-sap-cloud

  instance_name         = [INSTANCE_NAME]         # example: db2-instance
  db2_sid               = [DB2_SID]               # example: ID0

  #############################################################################
  # OPTIONAL SETTINGS
  #   - default values will be determined/calculated
  #############################################################################
  # db2_sid_size           = SID_SIZE       # default is 8, minimum is 8
  # db2_sap_tmp_size       = TMP_SIZE       # default is 8, minimum is 8
  # db2_sap_data_size      = DATA_SIZE      # default is 30, minimum is 30
  # db2_log_size           = LOG_SIZE       # default is 8, minimum is 8
  # db2_backup_size        = BACKUP_SIZE    # default is 0, minimum is 0
  # db2_sap_data_ssd       = true_or_false  # default is true
  # db2_log_ssd            = true_or_false  # default is true

  # usr_sap_size           = USR_SAP_SIZE   # default is 0, minimum is 0
  # swap_size              = SWAP_SIZE      # default is 0, minimum is 0

  # network_tags           = []             # default is an empty list
  # public_ip              = true_or_false  # default is true
  # service_account        = ""             # default is an empty string
  # sap_deployment_debug   = true_or_false  # default is false
  # use_reservation_name   = ""             # default is an empty string
}
