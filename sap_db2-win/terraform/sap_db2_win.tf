#
# Version:    2.0.202403040702
# Build Hash: 14cfd7eff165f31048fdcdad85843c67e0790bef
#
module "sap_db2_win" {
  source = "gcs::https://www.googleapis.com/storage/v1/core-connect-dm-templates/202403040702/terraform/sap_db2-win/sap_db2_win_module.zip"
  #
  # By default, this source file uses the latest release of the terraform module
  # for SAP on Google Cloud.  To fix your deployments to a specific release
  # of the module, comment out the source property above and uncomment the source property below.
  #
  # source = "gcs::https://www.googleapis.com/storage/v1/core-connect-dm-templates/202403040702/terraform/sap_db2-win/sap_db2_win_module.zip"
  #
  # Fill in the information below
  #
  ##############################################################################
  ## MANDATORY SETTINGS
  ##############################################################################
  # General settings
  project_id             = "PROJECT_ID"            # example: my-project-x
  zone                   = "ZONE"                  # example: us-east1-b
  machine_type           = "MACHINE_TYPE"          # example: n1-highmem-32
  subnetwork             = "SUBNETWORK"            # example: default
  windows_image          = "WINDOWS_IMAGE"         # example: rhel-8-4-sap-ha
  windows_image_project  = "WINDOWS_IMAGE_PROJECT" # example: rhel-sap-cloud

  instance_name          = "VM_NAME"               # example: db2-instance
  db2_sid                = "DB2_DATABASE_SID"      # example: ID0

  ##############################################################################
  ## OPTIONAL SETTINGS
  ##   - default values will be determined/calculated
  ##############################################################################
  # db2_sid_size         = DB_SID_DISK_SIZE        # default is 8, minimum is 8
  # db2_sap_temp_size    = SAP_TEMP_DISK_SIZE      # default is 8, minimum is 8
  # db2_sap_data_size    = SAP_DATA_DISK_SIZE      # default is 30, minimum is 30
  # db2_sap_data_ssd     = true_or_false           # default is true
  # db2_log_size         = LOG_DISK_SIZE           # default is 8, minimum is 8
  # db2_log_ssd          = true_or_false           # default is true
  # db2_backup_size      = BACKUP_DISK_SIZE        # default is 0, minimum is 0

  # usr_sap_size         = USR_SAP_DISK_SIZE       # default is 0, minimum is 0
  # sap_mnt_size         = SAP_MNT_DISK_SIZE       # default is 0, minimum is 0
  # swap_size            = SWAP_SIZE               # default is 0, minimum is 0
  # network_tags         = [ "TAG_NAME" ]          # default is an empty list
  # public_ip            = true_or_false           # default is true
  # service_account      = ""                      # default is an empty string
  # sap_deployment_debug = true_or_false           # default is false
  # reservation_name     = ""                      # default is an empty string
}
