#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
module "sap_hana_ha" {
  source = "TERRAFORM_PREFIXTERRAFORM_URL_LATEST/dm-templates/sap_hana_ha/sap_hana_ha_module.zip"
  #
  # By default, this source file uses the latest release of the terraform module
  # for SAP on Google Cloud.  To fix your deployments to a specific release
  # of the module, comment out the source property above and uncomment the source property below.
  #
  # source = "TERRAFORM_PREFIXTERRAFORM_URL/dm-templates/sap_hana_ha/sap_hana_ha_module.zip"
  #
  # Fill in the information below
  #
  ##############################################################################
  ## MANDATORY SETTINGS
  ##############################################################################
  # General settings

  primary_instance_name     = "PRIMARY_NAME"      # example: hana_ha_primary
  secondary_instance_name   = "SECONDARY_NAME"    # example: hana_ha_secondary
  project_id                = "PROJECT_ID"        # example: customer-project-x
  machine_type              = "MACHINE_TYPE"      # example: n1-highmem-32
  primary_zone              = "PRIMARY_ZONE"      # example: us-east1-b
  secondary_zone            = "SECONDARY_ZONE"    # example: us-east1-b
  linux_image               = "LINUX_IMAGE"       # example: sles-15-sp2-sap
  linux_image_project       = "IMAGE_PROJECT"     # example: suse-sap-cloud
  subnetwork                = "default"           # example: default

  ##############################################################################
  ## OPTIONAL SETTINGS
  ##   - default values will be determined/calculated
  ##############################################################################

  # sap_vip_secondary_range       = VIP_SECONDARY_RANGE      # default is ""
  # sap_hana_deployment_bucket    = GCS_BUCKET               # default is ""
  # sap_hana_sid                  = SID                      # default is ""
  # sap_hana_instance_number      = INSTANCE_NUMBER          # default is 10
  # sap_hana_sidadm_password      = SIDADM_PASSWORD          # default is ""
  # sap_hana_system_password      = SYSTEM_PASSWORD          # default is ""
  # sap_vip                       = IP_ADDRESS               # default is ""
  # sap_hana_backup_size          = HANA_BACKUP_SIZE_IN_GB   # default is 0
  # sap_hana_sidadm_uid           = SIDADMIN_UID             # default is 900
  # sap_hana_sapsys_gid           = SAPSYS_GID               # default is 79

  # network_tags                  = NETWORK_TAGS             # default is []
  # public_ip                     = true_or_false            # default is false
  # sap_hana_double_volume_size   = true_or_false            # default is false
  # sap_deployment_debug          = true_or_false            # default is false
  # post_deployment_script        = POST_DEPLOYMENT_SCRIPT   # default is ""
  # service_account               = SERVICE_ACCOUNT          # default is ""
  # use_ilb_vip                   = true_or_false            # default is true
  # primary_instance_group_name   = GROUP_NAME               # default is ""
  # secondary_instance_group_name = GROUP_NAME               # default is ""
  # network                       = NETWORK                  # default is ""
  # loadbalancer_name             = LB_NAME                  # default is ""
  # use_reservation_name          = RESERVATION_NAME         # default is ""

}
