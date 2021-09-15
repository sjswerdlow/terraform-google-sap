
#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
module "hana_scaleout" {
  source = "TERRAFORM_PREFIXTERRAFORM_URL_LATEST/terraform/sap_hana_scaleout/sap_hana_scaleout_module.zip"
  #
  # By default, this source file uses the latest release of the terraform module
  # for SAP on Google Cloud.  To fix your deployments to a specific release
  # of the module, comment out the source property above and uncomment the source property below.
  #
  # source = "TERRAFORM_PREFIXTERRAFORM_URL/terraform/sap_hana_scaleout/sap_hana_scaleout_module.zip"
  #
  # Fill in the information below
  #
  instance_name              = "VM_NAME"              # example: hana-scaleout
  machine_type               = "MACHINE_TYPE"         # example: n1-highmem-32
  project_id                 = "PROJECT_ID"           # example: customer-project-x
  zone                       = "ZONE"                 # example: us-central1-a
  subnetwork                 = "SUBNETWORK"           # example: default
  linux_image                = "LINUX_IMAGE"          # example: sles-15-sp2-sap
  linux_image_project        = "LINUX_IMAGE_PROJECT"  # example: suse-sap-cloud
  sap_hana_deployment_bucket = "GCS_BUCKET"           # example: customer-bucket/hana-install-media
  sap_hana_sid               = "HANA_SID"             # example: SH1
  sap_hana_instance_number   = "HANA_INSTANCE_NUM"    # example: 00
  sap_hana_sidadm_password   = "SIDADM_PASS"          # example: Google123
  sap_hana_system_password   = "SYSTE$M_PASS"         # example: Google123
  sap_hana_worker_nodes      = WORKER_NODES_NUM       # example: 2
  sap_hana_standby_nodes     = STANDBY_NODES_NUM      # example: 1
  sap_hana_shared_nfs        = "HANA_SHARED_NFS"      # example: 10.1.1.1:/hanashared
  sap_hana_backup_nfs        = "HANA_BACKUP_NFS"      # example: 10.1.1.1:/hanabackup
  public_ip                  = TRUE_OR_FALSE          # example: true

  # Add additional variable docs / examples
  # Optional advanced options
  # sap_hana_double_volume_size   = TRUE_OR_FALSE            # default is false
  # service_account               = "CUSTOM_SERVICE_ACCOUNT"
  # network_tags                  = "TAG"
  # sap_hana_sidadm_uid           = "SIDADM_UID"             # default is 900
  # sap_hana_sapsys_gid           = "SAPSYS_GID"             # default is 79
  # sap_deployment_debug          = TRUE_OR_FALSE            # default is false
  # use_reservation_name          = "RESERVATION_NAME"
}