module "sap_hana" {
  source = "TERRAFORM_PREFIXTERRAFORM_URL_LATEST/terraform/sap_hana/sap_hana_module.zip"
  #
  # By default, this source file uses the latest release of the terraform module
  # for SAP on Google Cloud.  To fix your deployments to a specific release
  # of the module, comment out the source property above and uncomment the source property below.
  #
  # source = "TERRAFORM_PREFIXTERRAFORM_URL/terraform/sap_hana/sap_hana_module.zip"
  #
  # Fill in the information below
  #
  machine_type                 = "MACHINE_TYPE"         # example: "n1-standard-8"
  project_id                   = "PROJECT_ID"           # example: "core-connect-interns"
  instance_name                = "VM_NAME"              # example: "testing-sap-hana"
  zone                         = "ZONE"                 # example: us-central1-a
  subnetwork                   = "SUBNETWORK"           # example: default
  linux_image                  = "LINUX_IMAGE"          # example: "rhel-8-1-sap-ha"
  linux_image_project          = "LINUX_IMAGE_PROJECT"  # example: "rhel-sap-cloud"
  sap_hana_deployment_bucket   = "GCS_BUCKET"           # example: customer-bucket/hana-install-media
  sap_hana_sid                 = "SID"                  # example: "AAA"
  sap_hana_instance_number     = INSTANCE_NUMBER        # example: 12
  sap_hana_sid_adm_password    = "SID_ADM_PASSWORD"     # example: Password1
  sap_hana_system_adm_password = "SYSTEM_PASSWORD"      # example: Password1
  sap_hana_scaleout_nodes      = SCALEOUT_NODES_NUM     # example: 2
}
