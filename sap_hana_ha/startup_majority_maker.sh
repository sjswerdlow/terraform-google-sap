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
TEMPLATE_NAME="SAP_HANA_HA_MM"

##########################################################################
## Start includes
##########################################################################

SAP_LIB_MAIN_SH
SAP_LIB_HA_SH
SAP_LIB_METRICS

##########################################################################
## End includes
##########################################################################

## Base GCP and OS Configuration
main::get_os_version
main::install_gsdk /usr/local
main::install_packages
main::config_ssh
main::get_settings
main::create_static_ip

## Install monitoring agents
main::install_monitoring_agent

## Enable MM
ha::host_file_entries
ha::download_scripts
ha::pacemaker_scaleout_package_installation
main::wait_for_metadata "${VM_METADATA[sap_primary_instance]}" status ready-for-scaleout-nodes
ha::join_pacemaker_cluster "${VM_METADATA[sap_primary_instance]}"
ha::check_cluster "${VM_METADATA[sap_primary_instance]}"

## Post deployment & installation cleanup
main::complete
