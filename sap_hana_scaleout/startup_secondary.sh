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
#########################################################################
## Start constants
##########################################################################
TEMPLATE_NAME="SAP_HANA_SCALEOUT_SECONDARY"

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
main::create_static_ip

## Install monitoring agent
main::install_monitoring_agent

## prepare for SAP HANA
hdb::check_settings
hdb::set_kernel_parameters
hdbso::mount_nfs_vols
hdbso::calculate_volume_sizes
hdbso::create_data_log_volumes
hdbso::update_sudoers
hdbso::gcestorageclient_gcloud_config

## Post deployment & installation cleanup
main::complete
