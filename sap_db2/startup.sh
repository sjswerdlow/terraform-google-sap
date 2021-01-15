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
# Build Date:   BUILD.SH_DATE
# Build Hash:   BUILD.HASH
# ------------------------------------------------------------------------

## Check to see if a custom script path was provided by the template
if [[ "${1}" ]]; then
  readonly DEPLOY_URL="${1}"
else
  readonly DEPLOY_URL="BUILD.SH_URL"
fi

##########################################################################
## Start includes
##########################################################################
SAP_LIB_MAIN_SH
SAP_LIB_DB2_SH
SAP_LIB_NW_SH
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

## Prepare for DB2
db2::fix_services
db2::create_filesystems

if [[ -n "${VM_METADATA[other_host]}" ]]; then
  main::install_ssh_key "${VM_METADATA[other_host]}"
fi

## Prepare for NetWeaver
nw::install_agent
nw::create_filesystems

## Clean up
main::complete
