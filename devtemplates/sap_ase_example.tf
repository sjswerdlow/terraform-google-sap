module "sap_ase" {
  source = "./sap_ase"

  instance_name       = "example-test-ase"
  machine_type        = "e2-standard-8"
  project_id          = "core-connect-dev"
  zone                = "us-central1-a"
  subnetwork          = "default"
  linux_image         = "sles-15-sp2-sap"
  linux_image_project = "suse-sap-cloud"
  ase_sid             = "AS1"
  ase_sid_size        = 10
  ase_diag_size       = 10
  ase_sap_temp_size   = 10
  ase_sap_data_size   = 10
  ase_log_size        = 10
  ase_backup_size     = 10
  ase_sap_data_ssd    = false
  ase_log_ssd         = false
  usr_sap_size        = 10
  sap_mnt_size        = 10
  swap_size           = 10
  public_ip           = true

  # Optional advanced options
  # network_tags           = "TAG"
  # public_ip              = true_or_false
  # service_account        = "CUSTOM_SERVICE_ACCOUNT"
  # sap_deployment_debug   = true_or_false
  # reservation_name       = "RESERVATION_NAME"
  # can_ip_forward         = true_or_false

  # Developer options
  # post_deployment_script = "SCRIPT_URL"
}
