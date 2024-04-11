
module "hana_scaleout" {
  source               = "gcs::https://www.googleapis.com/storage/v1/core-connect-dm-templates/DATE_TIME_STAMP/dm-templates/sap_hana_scaleout/sap_hana_scaleout_module.zip"
  instance_name        = "hana-scaleout"
  machine_type         = "n1-standard-8"
  sap_deployment_debug = true
  # machine_type = "n1-highmem-32"
  project_id = "core-connect-dev"
  zone       = "us-central1-a"
  subnetwork = "default"
  # RHEL
  # linuxImage: rhel-7-7-sap-ha
  # linuxImage: rhel-8-1-sap-ha
  # linuxImageProject: rhel-sap-cloud
  # SLES
  # linuxImage: sles-12-sp2-sap
  # linuxImage: sles-12-sp3-sap
  # linuxImage: sles-12-sp4-sap
  # linuxImage: sles-12-sp5-sap
  # linuxImage: sles-15-sap
  # linuxImage: sles-15-sp1-sap
  # linuxImageProject: suse-sap-cloud
  linux_image                = "sles-15-sp2-sap"
  linux_image_project        = "suse-sap-cloud"
  sap_hana_deployment_bucket = "core-connect-dev-saphana/hana-47"
  sap_hana_sid               = "SH1"
  sap_hana_instance_number   = "00"
  sap_hana_sidadm_password   = "Google123"
  sap_hana_system_password   = "Google123"
  sap_hana_worker_nodes      = 2
  sap_hana_standby_nodes     = 1
  sap_hana_shared_nfs        = "10.6.120.90:/hanashared"
  sap_hana_backup_nfs        = "10.150.221.242:/hanabackup"
  public_ip                  = true
  #
  # Dev scripts at DATE_TIME_STAMP, use when developing changes to the bash scripts
  #
  primary_startup_url   = <<-EOT
if [[ ! -f "/bin/gcloud" ]] && [[ ! -d "/usr/local/google-cloud-sdk" ]]; then
  bash <(curl -s https://dl.google.com/dl/cloudsdk/channels/rapid/install_google_cloud_sdk.bash) --disable-prompts --install-dir=/usr/local >/dev/null;
  export PATH=/usr/local/google-cloud-sdk/bin/:$PATH;
fi;
if [[ -e "/usr/bin/python" ]]; then
  export CLOUDSDK_PYTHON=/usr/bin/python;
fi;
gsutil cat gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates/sap_hana_ha_ilb/startup.sh | bash -s gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates
  EOT
  secondary_startup_url = <<-EOT
if [[ ! -f "/bin/gcloud" ]] && [[ ! -d "/usr/local/google-cloud-sdk" ]]; then
  bash <(curl -s https://dl.google.com/dl/cloudsdk/channels/rapid/install_google_cloud_sdk.bash) --disable-prompts --install-dir=/usr/local >/dev/null;
  export PATH=/usr/local/google-cloud-sdk/bin/:$PATH;
fi;
if [[ -e "/usr/bin/python" ]]; then
  export CLOUDSDK_PYTHON=/usr/bin/python;
fi;
gsutil cat gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates/sap_hana_ha_ilb/startup_secondary.sh | bash -s gs://core-connect-dm-templates/DATE_TIME_STAMP/dm-templates
  EOT
  #
  # Latest public scripts
  #
  # primary_startup_url = "curl -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates/sap_hana_scaleout/startup.sh | bash -x -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates"
  # secondary_startup_url = "curl -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates/sap_hana_scaleout/startup_secondary.sh | bash -x -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates"
}

