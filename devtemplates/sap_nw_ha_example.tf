module "sap_nw_ha" {
  source = "./sap_nw_ha"
  ##############################################################################
  ## MANDATORY SETTINGS
  ##############################################################################
  # General settings
  project_id                 = "sap-certification-env"
  machine_type               = "n2-standard-8"
  subnetwork                 = "sapcertificationnetwork"
  #linux_image                = "sles-15-sp2-sap"
  linux_image                = "sles-12-sp5-sap"
  linux_image_project        = "suse-sap-cloud"

  sap_primary_instance       = "fl-tf-nw1"
  sap_primary_zone           = "us-central1-b"

  sap_secondary_instance     = "fl-tf-nw2"
  sap_secondary_zone         = "us-central1-c"

  nfs_path                   = "10.132.59.122:/fl_tf_nw_hdd"

  sap_sid                    = "FL1"

  ##############################################################################
  ## OPTIONAL SETTINGS
  ##   - can be omitted - default values will be determined/calculated
  ##############################################################################
  hc_firewall_name           = ""
  hc_network_tag             = []

  scs_inst_group_name        = ""
  scs_hc_name                = ""
  scs_hc_port                = ""
  scs_vip_name               = ""
  scs_vip_address            = "10.128.0.162"
  scs_backend_svc_name       = ""
  scs_forw_rule_name         = ""

  ers_inst_group_name        = ""
  ers_hc_name                = ""
  ers_hc_port                = ""
  ers_vip_name               = ""
  ers_vip_address            = "10.128.0.213"
  ers_backend_svc_name       = ""
  ers_forw_rule_name         = ""

  usrsap_size                = 8
  sapmnt_size                = 8
  swap_size                  = 8

  sap_scs_instance_number    = ""
  sap_ers_instance_number    = ""
  sap_nw_abap                = true

  pacemaker_cluster_name     = ""

  public_ip                  = true
  service_account            = ""
  network_tags               = []
  sap_deployment_debug       = true
  install_monitoring_agent   = true
  post_deployment_script     = ""

  #
  # Dev scripts at DATE_TIME_STAMP, use when developing changes to the bash scripts
  #
  primary_startup_url = <<-EOT
if grep SLES /etc/os-release; then
  readonly LINUX_DISTRO="SLES";
elif grep -q "Red Hat" /etc/os-release; then
  readonly LINUX_DISTRO="RHEL";
else
  main::errhandle_log_warning "Unsupported Linux distribution. Only SLES and RHEL are supported.";
fi;
readonly LINUX_VERSION=$(grep VERSION_ID /etc/os-release | awk -F '\"' '{ print $2 }');
readonly LINUX_MAJOR_VERSION=$(echo $LINUX_VERSION | awk -F '.' '{ print $1 }');

if [[ $LINUX_DISTRO = "SLES" && $LINUX_MAJOR_VERSION = "12" ]]; then
 export CLOUDSDK_PYTHON=/usr/bin/python
fi;

if [[ ! -f "/bin/gcloud" ]] && [[ ! -d "/usr/local/google-cloud-sdk" ]]; then
  bash <(curl -s https://dl.google.com/dl/cloudsdk/channels/rapid/install_google_cloud_sdk.bash) --disable-prompts --install-dir=/usr/local >/dev/null;
fi;

if [[ $LINUX_DISTRO = "SLES" ]]; then
  update-alternatives --install /usr/bin/gsutil gsutil /usr/local/google-cloud-sdk/bin/gsutil 1 --force;
  update-alternatives --install /usr/bin/gcloud gcloud /usr/local/google-cloud-sdk/bin/gcloud 1 --force;
  if [[ $LINUX_MAJOR_VERSION = "12" ]]; then
    export CLOUDSDK_PYTHON=/usr/bin/python;
    echo "export CLOUDSDK_PYTHON=/usr/bin/python" | tee -a /etc/profile;
    echo "export CLOUDSDK_PYTHON=/usr/bin/python" | tee -a /etc/environment;
  fi;
fi;

gsutil cat gs://core-connect-dm-templates/202106011728/dm-templates/sap_nw_ha/startup_scs.sh | bash -s gs://core-connect-dm-templates/202106011728/dm-templates
  EOT
  secondary_startup_url = <<-EOT
if grep SLES /etc/os-release; then
  readonly LINUX_DISTRO="SLES";
elif grep -q "Red Hat" /etc/os-release; then
  readonly LINUX_DISTRO="RHEL";
else
  main::errhandle_log_warning "Unsupported Linux distribution. Only SLES and RHEL are supported.";
fi;
readonly LINUX_VERSION=$(grep VERSION_ID /etc/os-release | awk -F '\"' '{ print $2 }');
readonly LINUX_MAJOR_VERSION=$(echo $LINUX_VERSION | awk -F '.' '{ print $1 }');

if [[ $LINUX_DISTRO = "SLES" && $LINUX_MAJOR_VERSION = "12" ]]; then
 export CLOUDSDK_PYTHON=/usr/bin/python
fi;

if [[ ! -f "/bin/gcloud" ]] && [[ ! -d "/usr/local/google-cloud-sdk" ]]; then
  bash <(curl -s https://dl.google.com/dl/cloudsdk/channels/rapid/install_google_cloud_sdk.bash) --disable-prompts --install-dir=/usr/local >/dev/null;
fi;

if [[ $LINUX_DISTRO = "SLES" ]]; then
  update-alternatives --install /usr/bin/gsutil gsutil /usr/local/google-cloud-sdk/bin/gsutil 1 --force;
  update-alternatives --install /usr/bin/gcloud gcloud /usr/local/google-cloud-sdk/bin/gcloud 1 --force;
  if [[ $LINUX_MAJOR_VERSION = "12" ]]; then
    export CLOUDSDK_PYTHON=/usr/bin/python;
    echo "export CLOUDSDK_PYTHON=/usr/bin/python" | tee -a /etc/profile;
    echo "export CLOUDSDK_PYTHON=/usr/bin/python" | tee -a /etc/environment;
  fi;
fi;

gsutil cat gs://core-connect-dm-templates/202106011728/dm-templates/sap_nw_ha/startup_ers.sh | bash -s gs://core-connect-dm-templates/202106011728/dm-templates
  EOT
  #
  # Latest public scripts
  #
  # primary_startup_url = "curl -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates/sap_hana_scaleout/startup.sh | bash -x -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates"
  # secondary_startup_url = "curl -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates/sap_hana_scaleout/startup_secondary.sh | bash -x -s https://storage.googleapis.com/cloudsapdeploy/deploymentmanager/latest/dm-templates"

}