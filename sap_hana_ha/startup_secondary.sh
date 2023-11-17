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
#
# Version:    BUILD.VERSION
# Build Hash: BUILD.HASH
#
# ------------------------------------------------------------------------

## Check to see if a custom script path was provided by the template
if [[ "${1}" ]]; then
  readonly DEPLOY_URL="${1}"
else
  readonly DEPLOY_URL="BUILD.SH_URL"
fi

##########################################################################
## Start constants
##########################################################################
TEMPLATE_NAME="SAP_HANA_HA_SECONDARY"

##########################################################################
## Start includes
##########################################################################

SAP_LIB_MAIN_SH
SAP_LIB_HDB_SH
SAP_LIB_HA_SH
SAP_LIB_METRICS
SAP_LIB_HDBFR

##########################################################################
## End includes
##########################################################################

## Base GCP and OS Configuration
main::get_os_version
main::install_gsdk /usr/local
main::set_boot_parameters
main::install_packages
main::config_ssh
main::get_settings
main::create_static_ip

## Prepare for SAP HANA
hdb::check_settings
hdb::set_kernel_parameters
hdb::calculate_volume_sizes
hdb::create_shared_volume
hdb::create_sap_data_log_volumes
hdb::create_backup_volume

## Install monitoring agents
main::install_monitoring_agent

## Install SAP HANA
hdb::config_nfs
hdb::create_install_cfg
hdb::download_media
hdb::extract_media
hdb::install
hdb::upgrade
hdb::config_backup
hdb::config_hyperdisk_parameters
if [[ "${VM_METADATA[enable_fast_restart]}" = "true" ]]; then
  hdb_fr::setup_fast_restart "${VM_METADATA[sap_hana_sid]}" "${VM_METADATA[sap_hana_system_password]}"
  hdb::stop
  hdb::start
fi
hdb::install_scaleout_nodes

## Setup HA
ha::check_settings
ha::host_file_entries
ha::download_scripts
ha::pacemaker_scaleout_package_installation
ha::create_hdb_user
ha::hdbuserstore
hdb::backup pre_ha_config
hdb::stop
main::wait_for_metadata "${VM_METADATA[sap_primary_instance]}" status ready-for-ha-secondary
ha::copy_hdb_ssfs_keys
ha::config_hsr
ha::enable_hdb_hadr_provider_hook
hdb::start_nowait
ha::setup_haproxy  # RHEL only
ha::join_pacemaker_cluster "${VM_METADATA[sap_primary_instance]}"

## Post deployment & installation cleanup
main::complete
