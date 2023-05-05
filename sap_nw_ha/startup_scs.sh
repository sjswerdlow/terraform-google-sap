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
TEMPLATE_NAME="NW_HA_SCS"


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
main::config_ssh
main::get_settings
main::send_start_metrics
main::create_static_ip

## Prepare for NetWeaver
nw::create_filesystems
main::install_monitoring_agent

## Setup HA
nw-ha::create_deploy_directory
ha::install_secondary_sshkeys
nw-ha::create_nfs_directories
nw-ha::configure_shared_file_system
nw-ha::enable_ilb_backend_communication
nw-ha::update_etc_hosts
nw-ha::install_ha_packages
nw-ha::pacemaker_create_cluster_primary
ha::wait_for_secondary "nw_ha"
ha::pacemaker_maintenance true
nw-ha::create_fencing_resources
nw-ha::create_file_system_resources
nw-ha::create_health_check_resources
nw-ha::create_vip_resources
ha::pacemaker_maintenance false

## Post deployment & installation cleanup
main::complete