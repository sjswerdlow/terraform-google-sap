#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
module "sap_ase" {
  source = "TERRAFORM_PREFIXTERRAFORM_URL_LATEST/terraform/sap_ase/sap_ase_module.zip"
  #
  # By default, this source file uses the latest release of the terraform module
  # for SAP on Google Cloud.  To fix your deployments to a specific release
  # of the module, comment out the source property above and uncomment the source property below.
  #
  # source = "TERRAFORM_PREFIXTERRAFORM_URL/terraform/sap_ase/sap_ase_module.zip"
  #
  # Fill in the information below
  #
  instance_name          = "VM_NAME"
  machine_type           = "MACHINE_TYPE"
  project_id             = "PROJECT_ID"
  zone                   = "ZONE"
  subnetwork             = "SUBNETWORK"
  linux_image            = "IMAGE_FAMILY"
  linux_image_project    = "IMAGE_PROJECT"
  ase_sid                = "ASE_DATABASE_SID"
  ase_sid_size           = DBSID_DISK_SIZE     # in GB, default is 8
  ase_diag_size          = DIAG_DISK_SIZE      # in GB, default is 8
  ase_sap_temp_size      = SAPTEMP_DISK_SIZE   # in GB, default is 8
  ase_sap_data_size      = SAPDATA_DISK_SIZE   # in GB, default is 30
  ase_log_size           = LOGDIR_DISK_SIZE    # in GB, default is 8
  ase_backup_size        = BACKUP_DISK_SIZE    # in GB, default is 0 and will not be created
  ase_sap_data_ssd       = true_or_false       # default is true
  ase_log_ssd            = true_or_false       # default is true
  usr_sap_size           = USRSAP_DISK_SIZE    # in GB, default is 0 and will not be created
  sap_mnt_size           = SAPMNT_DISK_SIZE    # in GB, default is 0 and will not be created
  swap_size              = SWAP_SIZE           # in GB, default is 0 and will not be created

  # Optional advanced options
  # network_tags           = "TAG"
  # public_ip              = true_or_false            # default is true
  # service_account        = "CUSTOM_SERVICE_ACCOUNT"
  # sap_deployment_debug   = true_or_false            # default is false
  # use_reservation_name   = "RESERVATION_NAME"

  # Developer options - do not modify unless instructed to
  # primary_startup_url    = "SCRIPT_URL"
  # post_deployment_script = "SCRIPT_URL"
}
