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
TEMPLATE_NAME="SAP_HANA_HA_PRIMARY"

##########################################################################
## Start includes
##########################################################################

SAP_LIB_MAIN_SH
SAP_LIB_HDB_SH
SAP_LIB_HA_SH
SAP_LIB_METRICS

##########################################################################
## End includes
##########################################################################

## Base main:: and OS Configuration
main::get_os_version
main::install_gsdk /usr/local
main::set_boot_parameters
main::install_packages
main::config_ssh
main::get_settings
main::send_start_metrics
## Scale-Out Specific
if [ ! "${VM_METADATA[sap_hana_scaleout_nodes]}" = "0" -a  ! ${LINUX_DISTRO} = "SLES" ]; then
  main::errhandle_log_error "HANA HA Scaleout deployment is currently only supported on SLES operating systems."
fi
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
hdb::config_hdx_parameters
hdb::install_scaleout_nodes

## Base HA Setup
ha::check_settings
ha::host_file_entries
ha::download_scripts
ha::pacemaker_scaleout_package_installation
ha::create_hdb_user
ha::hdbuserstore
hdb::backup pre_ha_config
main::exchange_sshpubkey_with "${VM_METADATA[sap_secondary_instance]}" "${VM_METADATA[sap_secondary_zone]}"
ha::enable_hsr
ha::setup_haproxy  # RHEL only
ha::config_pacemaker_primary

## Scale-Out Specific
if [[ -n "${VM_METADATA[majority_maker_instance_name]}" ]]; then
  main::exchange_sshpubkey_with "${VM_METADATA[majority_maker_instance_name]}" "${VM_METADATA[majority_maker_instance_zone]}"
  ha::check_node "${VM_METADATA[sap_secondary_instance]}"
  main::set_metadata status ready-for-scaleout-nodes
fi

## Additional HA setup
ha::check_cluster
ha::check_hdb_replication
ha::pacemaker_maintenance true
ha::pacemaker_add_stonith
ha::pacemaker_add_vip
ha::pacemaker_config_bootstrap_hdb
ha::pacemaker_add_hana
ha::pacemaker_maintenance false

## Allow Pacemaker to reconcile replication status before enabling hook
ha::check_hdb_replication
ha::pacemaker_maintenance true
ha::enable_hdb_hadr_provider_hook
ha::pacemaker_maintenance false

## Post deployment & installation cleanup
main::complete
