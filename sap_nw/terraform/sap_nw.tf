#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#

module "sap_nw" {

  source = "TERRAFORM_PREFIXTERRAFORM_URL_LATEST/dm-templates/sap_nw/sap_nw_module.zip"

  # Fill in the information below
  #
  ##############################################################################
  ## MANDATORY SETTINGS
  ##############################################################################
  # General settings

  project_id                 = "PROJECT_ID"           # example: my-project-x
  machine_type               = "MACHINE_TYPE"         # example: n1-highmem-32
  subnetwork                 = "SUBNETWORK"           # example: default
  linux_image                = "LINUX_IMAGE"          # example: sles-15-sp2-sap
  linux_image_project        = "LINUX_IMAGE_PROJECT"  # example: suse-sap-cloud
  zone                       = "PRIMARY_ZONE"         # example: us-central1-b
  instance_name              = "INSTANCE_NAME"        # example: instance-test1
  }


  ##############################################################################
  ## OPTIONAL SETTINGS
  ##   - default values will be determined/calculated
  ##############################################################################


  # usrsap_size                = 8
  # sapmnt_size                = 8
  # swap_size                  = 8
  # public_ip                  = false
  # service_account            = ""
  # network_tags               = []
  # sap_deployment_debug       = false
  # post_deployment_script     = ""
  # primary_startup_url        = "curl -s BUILD.TERRA_SH_URL/sap_nw/startup.sh | bash -x -s BUILD.TERRA_SH_URL"
  # reservation_name           = ""
  # can_ip_forward             = true


