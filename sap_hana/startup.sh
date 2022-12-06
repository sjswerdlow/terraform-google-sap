#!/bin/bash
# ------------------------------------------------------------------------
# Copyright 2018 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Description:  Google Cloud Platform - SAP Deployment Functions
# Version:   BUILD.VERSION
# Build Hash:   BUILD.HASH
# ------------------------------------------------------------------------

## Check to see if a custom script path was provieded by the template
if [[ "${1}" ]]; then
  readonly DEPLOY_URL="${1}"
else
  readonly DEPLOY_URL="BUILD.SH_URL"
fi

##########################################################################
## Start constants
##########################################################################
TEMPLATE_NAME="SAP_HANA_PRIMARY"

##########################################################################
## Start includes
##########################################################################

SAP_LIB_MAIN_SH
SAP_LIB_HDB_SH
SAP_LIB_HDBSO_SH
SAP_LIB_METRICS

##########################################################################
## End includes
##########################################################################

### Base GCP and OS Configuration
main::get_os_version
main::install_gsdk /usr/local
main::set_boot_parameters
main::install_packages
main::config_ssh
main::get_settings
main::send_start_metrics
main::create_static_ip

##prepare for SAP HANA
hdb::check_settings
hdb::set_kernel_parameters
hdbso::mount_nfs_vols "nonha"
hdb::calculate_volume_sizes
hdb::create_shared_volume
hdb::create_sap_data_log_volumes
hdb::create_backup_volume

## Install monitoring agent
main::install_monitoring_agent

## scaleout config
hdb::install_worker_sshkeys
hdb::config_nfs

## Install SAP HANA
hdb::create_install_cfg
hdb::download_media
hdb::extract_media
hdb::install
hdb::upgrade
hdb::config_backup
hdb::install_scaleout_nodes

## Post deployment & installation cleanup
main::complete
