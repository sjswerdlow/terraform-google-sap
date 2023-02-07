#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
module "sap_maxdb_win" {
  source = "TERRAFORM_PREFIXTERRAFORM_URL_LATEST/terraform/sap_maxdb-win/sap_maxdb_win_module.zip"
  #
  # By default, this source file uses the latest release of the terraform module
  # for SAP on Google Cloud.  To fix your deployments to a specific release
  # of the module, comment out the source property above and uncomment the source property below.
  #
  # source = "TERRAFORM_PREFIXTERRAFORM_URL/terraform/sap_maxdb-win/sap_maxdb_win_module.zip"
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
  windows_image          = "WINDOWS_IMAGE"         # example: windows-server-2019-dc
  windows_image_project  = "WINDOWS_IMAGE_PROJECT" # example: windows-cloud

  instance_name          = "VM_NAME"               # example: my-vm-name

  ##############################################################################
  ## OPTIONAL SETTINGS
  ##   - default values will be determined/calculated
  ##############################################################################
  # maxdb_root_size      = ROOT_DISK_SIZE         # default is 8, minimum is 8
  # maxdb_data_size      = DATA_DISK_SIZE         # default is 30, minimum is 30
  # maxdb_data_ssd       = true_or_false          # default is true
  # maxdb_log_size       = LOG_DISK_SIZE          # default is 8, minimum is 8
  # maxdb_log_ssd        = true_or_false          # default is true
  # maxdb_backup_size    = BACKUP_DISK_SIZE       # default is 8, minimum is 8

  # usr_sap_size         = USR_SAP_DISK_SIZE       # default is 0, minimum is 0
  # swap_size            = SWAP_SIZE               # default is 0, minimum is 0
  # network_tags         = [ "TAG_NAME" ]          # default is an empty list
  # public_ip            = true_or_false           # default is true
  # service_account      = ""                      # default is an empty string
  # sap_deployment_debug = true_or_false           # default is false
  # reservation_name     = ""                      # default is an empty string
}
