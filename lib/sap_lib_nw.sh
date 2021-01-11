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
# ------------------------------------------------------------------------

nw::create_filesystems() {
  if [[ -h /dev/disk/by-id/google-"${HOSTNAME}"-usrsap ]]; then
    main::errhandle_log_info "Creating filesytems for NetWeaver"
    main::create_filesystem /usr/sap usrsap xfs
  fi

  if [[ -h /dev/disk/by-id/google-"${HOSTNAME}"-sapmnt ]]; then
    main::create_filesystem /sapmnt sapmnt xfs
  fi    

  if [[ -h /dev/disk/by-id/google-"${HOSTNAME}"-swap ]]; then
    main::create_filesystem swap swap swap
  fi

}

nw::install_agent() {
  if grep -q "/usr/sap" /etc/mtab; then
    main::errhandle_log_info "Installing SAP NetWeaver monitoring agent"
    if curl -s -f https://storage.googleapis.com/sap-netweaver-on-gcp/setupagent_linux.sh -O;
    then
      if timeout 300 bash setupagent_linux.sh;  then
        main::errhandle_log_info "SAP NetWeaver monitoring agent installed"
      else
        local MSG1="SAP NetWeaver monitoring agent did not install correctly."
        local MSG2="Try to install it manually."
        main::errhandle_log_info "${MSG1} ${MSG2}"
      fi
      set +e
    else
      main::errhandle_log_info "Could not download agent installation script."
    fi
  else
    main::errhandle_log_info "/usr/sap not mounted, aborting agent install."
  fi
}
