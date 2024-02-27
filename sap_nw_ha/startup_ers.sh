#!/bin/bash
# ------------------------------------------------------------------------
# Copyright 2021 Google Inc.
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
TEMPLATE_NAME="NW_HA_ERS"

##########################################################################
## Start includes
##########################################################################

SAP_LIB_MAIN_SH
SAP_LIB_HA_SH
SAP_LIB_NW_SH
SAP_LIB_METRICS

##########################################################################
## End includes
##########################################################################

## Base configuration
main::get_os_version
main::install_gsdk /usr/local
main::set_boot_parameters
main::install_packages
main::get_settings

## Add local host entries
ha::host_file_entries
nw-ha::update_etc_hosts

## Base configuration - continued
main::config_ssh
main::send_start_metrics
main::create_static_ip

## Prepare for NetWeaver
nw::create_filesystems
main::install_monitoring_agent

## Setup HA
nw-ha::create_deploy_directory
nw-ha::configure_shared_file_system
nw-ha::enable_ilb_backend_communication
nw-ha::install_ha_packages
main::wait_for_metadata "${VM_METADATA[sap_primary_instance]}" status ready-for-secondary-join
nw-ha::pacemaker_join_secondary
main::set_metadata status ready-for-ha-config
main::wait_for_metadata "${VM_METADATA[sap_primary_instance]}" status cluster-setup-complete

## Post deployment & installation cleanup
main::complete


