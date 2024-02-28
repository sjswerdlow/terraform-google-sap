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
# Version:    2.0.202402230649
# Build Hash: c745a89b214d491fa9b641e2fff78abfe9965016
#
# ------------------------------------------------------------------------

## Check to see if a custom script path was provided by the template
if [[ "${1}" ]]; then
  readonly DEPLOY_URL="${1}"
else
  readonly DEPLOY_URL="gs://core-connect-dm-templates/202402230649/dm-templates"
fi

##########################################################################
## Start constants
##########################################################################
TEMPLATE_NAME="SAP_HANA_SCALEOUT_PRIMARY"

##########################################################################
## Start includes
##########################################################################


set +e

main::set_boot_parameters() {
  main::errhandle_log_info 'Checking boot paramaters'

  ## disable selinux
  if [[ -e /etc/sysconfig/selinux ]]; then
    main::errhandle_log_info "--- Disabling SELinux"
    sed -ie 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
  fi

  if [[ -e /etc/selinux/config ]]; then
    main::errhandle_log_info "--- Disabling SELinux"
    sed -ie 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
  fi
  ## work around for LVM boot where LVM volues are not started on certain SLES/RHEL versions
  if [[ -e /etc/sysconfig/lvm ]]; then
    sed -ie 's/LVM_ACTIVATED_ON_DISCOVERED="disable"/LVM_ACTIVATED_ON_DISCOVERED="enable"/g' /etc/sysconfig/lvm
  fi

  ## Configure cstates and huge pages
  if ! grep -q cstate /etc/default/grub ; then
    main::errhandle_log_info "--- Update grub"
    cmdline=$(grep GRUB_CMDLINE_LINUX_DEFAULT /etc/default/grub | head -1 | sed 's/GRUB_CMDLINE_LINUX_DEFAULT=//g' | sed 's/\"//g')
    cp /etc/default/grub /etc/default/grub.bak
    grep -v GRUBLINE_LINUX_DEFAULT /etc/default/grub.bak >/etc/default/grub
    if [[ $LINUX_DISTRO == "RHEL" ]] && [[ $LINUX_MAJOR_VERSION -ge 8 ]] && [[ $LINUX_MINOR_VERSION -ge 4 ]]; then
      # Enable tsx explicitly - SAP note 2777782
      echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${cmdline} transparent_hugepage=never intel_idle.max_cstate=1 processor.max_cstate=1 intel_iommu=off tsx=on\"" >>/etc/default/grub
    else
      echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${cmdline} transparent_hugepage=never intel_idle.max_cstate=1 processor.max_cstate=1 intel_iommu=off\"" >>/etc/default/grub
      echo "GRUB_ENABLE_LINUX_LABEL=true" >>/etc/default/grub
      echo "GRUB_DEVICE=\"LABEL=ROOT\"" >>/etc/default/grub
    fi
    grub2-mkconfig -o /boot/grub2/grub.cfg
    echo "${HOSTNAME}" >/etc/hostname
    main::errhandle_log_info '--- Parameters updated. Rebooting'
    reboot
    exit 0
  fi
}


main::errhandle_log_info() {
  local log_entry=${1}

  echo "INFO - ${log_entry}"
  if [[ -n "${GCLOUD}" ]]; then
     timeout 10 ${GCLOUD} --quiet logging write "${HOSTNAME}" "${HOSTNAME} Deployment \"${log_entry}\"" --severity=INFO
  fi
}


main::errhandle_log_warning() {
  local log_entry=${1}

  if [[ -z "${deployment_warnings}" ]]; then
    deployment_warnings=1
  else
    deployment_warnings=$((deployment_warnings +1))
  fi

  echo "WARNING - ${log_entry}"
  if [[ -n "${GCLOUD}" ]]; then
    ${GCLOUD} --quiet logging write "${HOSTNAME}" "${HOSTNAME} Deployment \"${log_entry}\"" --severity=WARNING
  fi
}


main::errhandle_log_error() {
  local log_entry=${1}

  echo "ERROR - Deployment Exited - ${log_entry}"
  if [[ -n "${GCLOUD}" ]]; then
    ${GCLOUD}	--quiet logging write "${HOSTNAME}" "${HOSTNAME} Deployment \"${log_entry}\"" --severity=ERROR
  fi

  main::complete error
}


main::get_os_version() {
  if grep SLES /etc/os-release; then
    readonly LINUX_DISTRO="SLES"
  elif grep -q "Red Hat" /etc/os-release; then
    readonly LINUX_DISTRO="RHEL"
  else
    main::errhandle_log_warning "Unsupported Linux distribution. Only SLES and RHEL are supported."
  fi
  readonly LINUX_VERSION=$(grep VERSION_ID /etc/os-release | awk -F '\"' '{ print $2 }')
  readonly LINUX_MAJOR_VERSION=$(echo $LINUX_VERSION | awk -F '.' '{ print $1 }')
  readonly LINUX_MINOR_VERSION=$(echo $LINUX_VERSION | awk -F '.' '{ print $2 }')
}


main::config_ssh() {
  ssh-keygen -m PEM -q -N "" < /dev/zero
  sed -ie 's/PermitRootLogin no/PermitRootLogin yes/g' /etc/ssh/sshd_config
  service sshd restart
  cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
  /usr/sbin/rcgoogle-accounts-daemon restart ||  /usr/sbin/rcgoogle-guest-agent restart

  ## Allow self ssh with keys
  cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
}

main::exchange_sshpubkey_with(){
  local host=${1}
  local host_zone=${2}

  if [[ -z "${host_zone}" ]]; then
    host_zone=$(${GCLOUD} --quiet compute instances list --filter="name=('${host}')" --format "value(zone)")
  fi

  main::install_sshpubkey_to "${host}" "${host_zone}"
  main::install_sshpubkey_from "${host}"
}

main::install_sshpubkey_from(){
  local host=${1}
  local key
  local count=0
  local max_count=10
  local tmp_file="/root/${host}_id_rsa.pub"

  main::errhandle_log_info "Installing public ssh key from ${host}"

  # retrieve public key from host
  while ! scp -q -o StrictHostKeyChecking=no "${host}":/root/.ssh/id_rsa.pub "${tmp_file}"; do
    count=$((count +1))
    if [ ${count} -gt ${max_count} ]; then
      main::errhandle_log_error "Failed to retrieve ssh public key from ${host}, aborting installation."
    else
      main::errhandle_log_info "Failed to retrieve ssh public key from ${host}. Attempt ${count}/${max_count}"
      sleep 5s
    fi
  done

  # check public key doesn't already exist in authorized_keys then add it
  key=$(cat "${tmp_file}")
  if ! grep "${key}" /root/.ssh/authorized_keys; then
    echo "${key}" >> /root/.ssh/authorized_keys
  fi
  rm -f "${tmp_file}"
}

main::install_sshpubkey_to(){
  local host=${1}
  local host_zone=${2}
  local count=0
  local max_count=10

  if [[ -z "${host_zone}" ]]; then
    host_zone=$(${GCLOUD} --quiet compute instances list --filter="name=('${host}')" --format "value(zone)")
  fi

  main::errhandle_log_info "Installing ${HOSTNAME} SSH key on ${host}"
  while ! "${GCLOUD}" --quiet compute instances add-metadata "${host}" --zone "${host_zone}" --metadata "ssh-keys=root:$(cat ~/.ssh/id_rsa.pub)"; do
    count=$((count +1))
    if [ ${count} -gt ${max_count} ]; then
      main::errhandle_log_error "Failed to install ${HOSTNAME} SSH key on ${host}, aborting installation."
    else
      main::errhandle_log_info "Failed to install ${HOSTNAME} SSH key on ${host}, trying again in 5 seconds."
      sleep 5s
    fi
  done

  main::wait_for_host "${host}"
  main::errhandle_log_info "Successfully installed ${HOSTNAME} SSH key on ${host}"
}

main::install_packages() {
  main::errhandle_log_info 'Installing required operating system packages'

  ## SuSE work around to avoid a startup race condition
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    local count=0

    ## check if SuSE repos are registered
    while [[ $(find /etc/zypp/repos.d/ -maxdepth 1 | wc -l) -lt 2 ]]; do
      main::errhandle_log_info "--- SuSE repositories are not registered. Waiting 60 seconds before trying again"
      sleep 60s
      count=$((count +1))
      if [ ${count} -gt 30 ]; then
        main::errhandle_log_error "SuSE repositories didn't register within an acceptable time. If you are using BYOS, ensure you login to the system and apply the SuSE license within 30 minutes after deployment. If you are using a VM without external IP make sure you set up a NAT gateway to provide internet access."
      fi
    done
    sleep 10s

    ## check if zypper is still running
    while pgrep zypper; do
      errhandle_log_info "--- zypper is still running. Waiting 10 seconds before attempting to continue"
      sleep 10s
    done
  fi

  ## packages to install
  local sles_packages="libssh2-1 libopenssl0_9_8 libopenssl1_0_0 tuned krb5-32bit unrar SAPHanaSR SAPHanaSR-doc pacemaker numactl csh python-pip python-pyasn1-modules ndctl python-oauth2client python-oauth2client-gce python-httplib2 python3-httplib2 python3-google-api-python-client python-requests python-google-api-python-client libgcc_s1 libstdc++6 libatomic1 sapconf saptune nvme-cli socat"
  local rhel_packages="unar.x86_64 tuned-profiles-sap-hana resource-agents-sap-hana.x86_64 compat-sap-c++-6 numactl-libs.x86_64 libtool-ltdl.x86_64 nfs-utils.x86_64 pacemaker pcs lvm2.x86_64 csh autofs ndctl compat-sap-c++-9 compat-sap-c++-10 compat-sap-c++-11 libatomic unzip libsss_autofs python2-pip langpacks-en langpacks-de glibc-all-langpacks libnsl libssh2 wget lsof jq chkconfig"


  ## install packages
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    for package in ${sles_packages}; do # Bash only splits unquoted.
        local count=0;
        local max_count=2;
        while ! sudo ZYPP_LOCK_TIMEOUT=60 zypper in -y "${package}"; do
          count=$((count +1))
          sleep 1
          if [[ ${count} -gt ${max_count} ]]; then
            main::errhandle_log_warning "Failed to install ${package}, continuing installation."
            break
          fi
        done
    done
    # making sure we refresh the bash env
    . /etc/bash.bashrc
    # boto.cfg has spaces in 15sp2, getting rid of them (b/172181835)
    if [[ $(tail -n 1 /etc/boto.cfg) == "  ca_certificates_file = system" ]]; then
      sed -i 's/^[ \t]*//' /etc/boto.cfg
    fi
  elif [[ ${LINUX_DISTRO} = "RHEL" ]]; then
    for package in $rhel_packages; do
        local count=0;
        local max_count=3;
        while ! yum -y install "${package}"; do
          count=$((count +1))
          sleep 3
          if [[ ${count} -gt ${max_count} ]]; then
            main::errhandle_log_warning "Failed to install ${package}, continuing installation."
            break
          fi
        done
    done
    # check for python interpreter - RHEL 8 does not have "python"
    main::errhandle_log_info 'Checking for python interpreter'
    if [[ ! -f "/bin/python" ]] && [[ -f "/usr/bin/python2" ]]; then
      main::errhandle_log_info 'Updating alternatives for python to python2.7'
      alternatives --set python /usr/bin/python2
    fi
    # make sure latest packages are installed (https://cloud.google.com/solutions/sap/docs/sap-hana-ha-config-rhel#install_the_cluster_agents_on_both_nodes)
    main::errhandle_log_info 'Applying updates to packages on system'
    if ! yum update -y; then
      main::errhandle_log_warning 'Applying updates to packages on system failed ("yum update -y"). Logon to the VM to investigate the issue.'
    fi
    if [[ $LINUX_MAJOR_VERSION -eq 8 ]] && [[ $LINUX_MINOR_VERSION -eq 4 ]]; then
      # b/283810042
      main::errhandle_log_info 'Updating fence_gce in RHEL 8.4'
      if ! yum --releasever=8.6 update -y fence-agents-gce; then
        main::errhandle_log_warning 'Update of fence_gce failed ("yum --releasever=8.6 update fence-agents-gce;"). Logon to the VM to investigate the issue.'
      fi
    fi
  fi
  main::errhandle_log_info 'Install of required operating system packages complete'
}

#######################################
# Finds and returns (via 'echo') first device in $by_id_dir that contains
# $searchstring. Works with SCSI (/dev/sdX) and NVME (/dev/nvmeX) devices.
#
# Input: searchstring
# Output: device name
#
# Examples for NVME and SCSI:
#     main::get_device_by_id backup
#       /dev/nvme0n3     (NVME)
#       /dev/sdc         (SCSI)
#######################################
main::get_device_by_id() {

  local searchstring=${1}
  local by_id_dir="/dev/disk/by-id"
  local device_name=""
  local nvme_script='/usr/lib/udev/google_nvme_id'

  device_name=$(readlink -f ${by_id_dir}/$(ls ${by_id_dir} | grep google | grep -m 1 "${searchstring}"))
  if [ ${device_name} != ${by_id_dir} ]; then
    echo ${device_name}
    return
  fi

  # TODO(franklegler): Remove workaround once b/249894430 is resolved
  # On M3 with SLES devices are not yet listed by their name (b/249894430)
  # Workaround: Run script to create symlinks ()
  if [[ -b /dev/nvme0n1 ]] && [[ -f ${nvme_script} ]]; then
    udevadm control --reload-rules && udevadm trigger # b/249894430#comment11
    for i in $(ls /dev/nvme0n*); do                   # b/249894430#comment13
        $nvme_script -d $i -s
    done
    device_name=$(readlink -f ${by_id_dir}/$(ls ${by_id_dir} | grep google | grep -m 1 "${searchstring}"))
    if [ ${device_name} != ${by_id_dir} ]; then
      echo ${device_name}
      return
    fi
  fi
  # End workaround

  main::errhandle_log_error "No device containing '${searchstring}' found."
}


main::create_vg() {
  local device=${1}
  local volume_group=${2}

  if [[ -b "$device" ]]; then
    main::errhandle_log_info "--- Creating physical volume group ${device}"
    pvcreate "${device}"
    main::errhandle_log_info "--- Creating volume group ${volume_group} on ${device}"
    vgcreate "${volume_group}" "${device}"
    /sbin/vgchange -ay
  else
      main::errhandle_log_error "Unable to access ${device}"
  fi
}


main::create_filesystem() {
  local mount_point=${1}
  local device=${2}
  local filesystem=$3
  local is_optional_file_system=${4}

  if [[ -h /dev/disk/by-id/google-"${HOSTNAME}"-"${device}" ]]; then
    main::errhandle_log_info "--- ${mount_point}"
    pvcreate /dev/disk/by-id/google-"${HOSTNAME}"-"${device}"
    vgcreate vg_"${device}" /dev/disk/by-id/google-"${HOSTNAME}"-"${device}"
    lvcreate -l 100%FREE -n vol vg_"${device}"
    main::format_mount "${mount_point}" /dev/vg_"${device}"/vol "${filesystem}"
    if [[ "${mount_point}" != "swap" ]]; then
      main::check_mount "${mount_point}"
    fi
  elif [[ ${is_optional_file_system:-"notOptional"} == "optional" ]]; then
    main::errhandle_log_warning "Unable to create optional file system ${filesystem}."
  else
    main::errhandle_log_error "Unable to access ${device}"
  fi

}


main::check_mount() {
  local mount_point=${1}
  local on_error=${2}

  ## check /etc/mtab to see if the filesystem is mounted
  if ! grep -q "${mount_point}" /etc/mtab; then
    case "${on_error}" in
      error)
        main::errhandle_log_error "Unable to mount ${mount_point}"
        ;;

      info)
        main::errhandle_log_info "Unable to mount ${mount_point}"
        ;;

      warning)
        main::errhandle_log_warning "Unable to mount ${mount_point}"
        ;;

      *)
        main::errhandle_log_error "Unable to mount ${mount_point}"
    esac
  fi

}

main::format_mount() {
  local mount_point=${1}
  local device=${2}
  local filesystem=${3}
  local options=${4}

  if [[ -b "$device" ]]; then
    if [[ "${filesystem}" = "swap" ]]; then
      echo "${device} none ${filesystem} defaults,nofail 0 0" >>/etc/fstab
      mkswap "${device}"
      swapon "${device}"
    else
      main::errhandle_log_info "--- Creating ${mount_point}"
      mkfs -t "${filesystem}" "${device}"
      mkdir -p "${mount_point}"
      if [[ ! "${options}" = "tmp" ]]; then
        echo "${device} ${mount_point} ${filesystem} defaults,nofail,logbsize=256k 0 2" >>/etc/fstab
        mount -a
      else
        mount -t "${filesystem}" "${device}" "${mount_point}"
      fi
      main::check_mount "${mount_point}"
    fi
  else
    main::errhandle_log_error "Unable to access ${device}"
  fi
}


main::get_settings() {
  main::errhandle_log_info "Fetching GCE Instance Settings"

  ## set current zone as the default zone
  readonly CLOUDSDK_COMPUTE_ZONE=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/zone" | cut -d'/' -f4)
  export CLOUDSDK_COMPUTE_ZONE
  main::errhandle_log_info "--- Instance determined to be running in ${CLOUDSDK_COMPUTE_ZONE}. Setting this as the default zone"

  readonly VM_REGION=${CLOUDSDK_COMPUTE_ZONE::-2}

  ## get instance type & details
  readonly VM_INSTTYPE=$(main::get_metadata http://169.254.169.254/computeMetadata/v1/instance/machine-type | cut -d'/' -f4)
  main::errhandle_log_info "--- Instance type determined to be ${VM_INSTTYPE}"

  readonly VM_CPUPLAT=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/cpu-platform")
  main::errhandle_log_info "--- Instance is determined to be part on CPU Platform ${VM_CPUPLAT}"

  readonly VM_CPUCOUNT=$(grep -c processor /proc/cpuinfo)
  main::errhandle_log_info "--- Instance determined to have ${VM_CPUCOUNT} cores"

  readonly VM_MEMSIZE=$(free -g | grep Mem | awk '{ print $2 }')
  main::errhandle_log_info "--- Instance determined to have ${VM_MEMSIZE}GB of memory"

  readonly VM_PROJECT=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/project/project-id")
  main::errhandle_log_info "--- VM is in project ${VM_PROJECT}"

  ## get network settings
  readonly VM_NETWORK=$(main::get_metadata http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/network | cut -d'/' -f4)
  main::errhandle_log_info "--- Instance is determined to be part of network ${VM_NETWORK}"

  readonly VM_NETWORK_FULL=$(gcloud compute instances describe "${HOSTNAME}" | grep "subnetwork:" | head -1 | grep -o 'projects.*')

  readonly VM_SUBNET=$(grep -o 'subnetworks.*' <<< "${VM_NETWORK_FULL}" | cut -f2- -d"/")
  main::errhandle_log_info "--- Instance is determined to be part of subnetwork ${VM_SUBNET}"

  readonly VM_NETWORK_PROJECT=$(cut -d'/' -f2 <<< "${VM_NETWORK_FULL}")
  main::errhandle_log_info "--- Networking is hosted in project ${VM_NETWORK_PROJECT}"

  readonly VM_IP=$(main::get_metadata http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip)
  main::errhandle_log_info "--- Instance IP is determined to be ${VM_IP}"

  # fetch all custom metadata associated with the instance
  main::errhandle_log_info "Fetching GCE Instance Metadata"
  local value
  local key
  declare -g -A VM_METADATA
  local uses_secret_password
  uses_secret_password="false"

  for key in $(curl --fail -sH'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/attributes/ | grep -v ssh-keys); do
    value=$(main::get_metadata "${key}")

    if [[ "${key}" = *"password"* ]]; then
      main::errhandle_log_info "${key} determined to be *********"
    else
      main::errhandle_log_info "${key} determined to be '${value}'"
    fi


    if [[ ${uses_secret_password} == "true" ]] && [[ "${key}" = *"password" ]]; then
      continue;
    fi

    if [[ "${key}" = *"password_secret"* ]]; then
      if [[ -z ${value} ]]; then
        continue;
      fi
      uses_secret_password="true"
      pass_key=${key::-7} # strips off _secret
      secret_ret=$(${GCLOUD} secrets versions access latest --secret="${value}")
      VM_METADATA[$pass_key]="${secret_ret}"
    else
      VM_METADATA[$key]="${value}"
    fi

  done

  # remove startup script
  if [[ -n "${VM_METADATA[startup-script]}" ]]; then
    main::remove_metadata startup-script
  fi

  # remove metrics info
  if [[ -n "${VM_METADATA[template-type]}" ]]; then
    main::remove_metadata template-type
  else
    VM_METADATA[template-type]="UNKNOWN"
  fi

  ## if the startup script has previously completed, abort execution.
  if [[ -n "${VM_METADATA[status]}" ]]; then
    main::errhandle_log_info "Startup script has previously been run. Taking no further action."
    exit 0
  fi
}


main::create_static_ip() {
  ## attempt to reserve the current IP address as static
  if [[ "$VM_NETWORK_PROJECT" == "${VM_PROJECT}" ]]; then
    main::errhandle_log_info "Creating static IP address ${VM_IP} in subnetwork ${VM_SUBNET}"
    ${GCLOUD} --quiet compute --project "${VM_NETWORK_PROJECT}" addresses create "${HOSTNAME}" --addresses "${VM_IP}" --region "${VM_REGION}" --subnet "${VM_SUBNET}"
  else
    main::errhandle_log_info "Creating static IP address ${VM_IP} in shared VPC ${VM_NETWORK_PROJECT}"
    ${GCLOUD} --quiet compute --project "${VM_PROJECT}" addresses create "${HOSTNAME}" --addresses "${VM_IP}" --region "${VM_REGION}" --subnet "${VM_NETWORK_FULL}"
  fi
}


main::remove_metadata() {
  local key=${1}

  ${GCLOUD} --quiet compute instances remove-metadata "${HOSTNAME}" --keys "${key}"
}


main::install_gsdk() {
  local install_location=${1}
  local rc

  if [[ -e /usr/bin/gsutil ]]; then
    # if SDK is installed, link to the standard location for backwards compatibility
    if [[ ! -d /usr/local/google-cloud-sdk/bin ]]; then
      mkdir -p /usr/local/google-cloud-sdk/bin
    fi
    if [[ ! -e /usr/local/google-cloud-sdk/bin/gsutil ]]; then
      ln -s /usr/bin/gsutil /usr/local/google-cloud-sdk/bin/gsutil
    fi
    if [[ ! -e /usr/local/google-cloud-sdk/bin/gcloud ]]; then
      ln -s /usr/bin/gcloud /usr/local/google-cloud-sdk/bin/gcloud
    fi
  elif [[ ! -d "${install_location}/google-cloud-sdk" ]]; then
    # commenting out this block since we are using the bundled python to install
    # b/189154450 - on SLES 12 use Python 3.6 w/ gcloud (default 3.4 is no longer supported by gcloud)
    # if [[ "${LINUX_DISTRO}" = "SLES" && "${LINUX_MAJOR_VERSION}" = "12" ]]; then
    #   zypper install -y python36
    #   export CLOUDSDK_PYTHON=/usr/bin/python3.6
    #   if ! grep -q CLOUDSDK_PYTHON /etc/profile; then
    #     echo "export CLOUDSDK_PYTHON=/usr/bin/python3.6" | tee -a /etc/profile
    #   fi
    #   if ! grep -q CLOUDSDK_PYTHON /etc/environment; then
    #     echo "export CLOUDSDK_PYTHON=/usr/bin/python3.6" | tee -a /etc/environment
    #   fi
    # fi
    curl -o /tmp/google-cloud-sdk.tar.gz https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-453.0.0-linux-x86_64.tar.gz
    tar -xzf /tmp/google-cloud-sdk.tar.gz -C ${install_location}
    bash ${install_location}/google-cloud-sdk/install.sh --quiet 1> /var/log/google-cloud-sdk-install.log 2>&1
    rc=$?
    if [[ "${rc}" -eq 0 ]]; then
      main::errhandle_log_info "Installed Google SDK in ${install_location}"
    else
      main::errhandle_log_error "Google SDK not correctly installed. Aborting installation."
    fi

    if [[ ${LINUX_DISTRO} = "SLES" ]]; then
      update-alternatives --install /usr/bin/gsutil gsutil /usr/local/google-cloud-sdk/bin/gsutil 1 --force
      update-alternatives --install /usr/bin/gcloud gcloud /usr/local/google-cloud-sdk/bin/gcloud 1 --force
    fi
  fi

  readonly GCLOUD="/usr/bin/gcloud"
  readonly GSUTIL="/usr/bin/gsutil"

  ## run an instances list to ensure the software is up to date
  ${GCLOUD} --quiet beta compute instances list --limit=1 >/dev/null
}


main::check_default() {
  local default=${1}
  local current=${2}

  if [[ -z ${current} ]]; then
    echo "${default}"
  else
    echo "${current}"
  fi
}

main::get_host_zone(){
  local host=${1}
  local i
  local host_zone

  ## Check host was passed
  if [[ -z "${host}" ]]; then
     main::errhandle_log_error "Unable to retreive zone as host was not supplied."
  fi

  # Retreive host zone, retrying if the API call fails
  for (( i = 0; i < 5; i++ )); do
    host_zone=$("${GCLOUD}" --quiet compute instances list --filter="name=(""${host}"")" --format "value(zone)")
    if [[ $? -eq 0 ]]; then
      echo "${host_zone}"
      return
    fi
    sleep 10
  done

  main::errhandle_log_error "Unable to get zone for host ${host}.."
}

main::get_ip() {
  local host="${1}"

  local host_zone
  local ip
  local count=0
  local max_count=10

  ## Check host was passed
  if [[ -z "${host}" ]]; then
     main::errhandle_log_error "Unable to retreive IP address as host was not supplied."
  fi

  ## Get zone of host
  host_zone=$(main::get_host_zone "${host}")

  for (( i = 0; i < 5; i++ )); do
    ip=$("${GCLOUD}" --quiet compute instances describe "${host}" --format="value(networkInterfaces[0].networkIP)" --zone="${host_zone}")
    if [[ $? -eq 0 ]]; then
      echo "${ip}"
      return
    fi
    sleep 10
  done

  main::errhandle_log_error "Unable to get IP for host ${host}.."
}

main::get_metadata() {
  local key=${1}

  local value

  if [[ ${key} = *"169.254.169.254/computeMetadata"* ]]; then
      value=$(curl --fail -sH'Metadata-Flavor: Google' "${key}")
  else
    value=$(curl --fail -sH'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/attributes/"${key}")
  fi

  ## Return value
  echo "${value}"
}

main::set_metadata() {
  local key="${1}"
  local value="${2}"

  local count=0
  local max_count=2

  while ! ${GCLOUD} --quiet compute instances add-metadata "${HOSTNAME}" --metadata "${key}=${value}" --zone "${CLOUDSDK_COMPUTE_ZONE}"; do
    count=$((count +1))
    if [ ${count} -gt ${max_count} ]; then
      main::errhandle_log_error "Failed to update metadata key=${key}, value=${value}, continuing."
    else
      main::errhandle_log_info "Failed to update metadata key=${key}, value=${value}, trying again in 5 seconds. [Attempt ${count}/${max_count}"
      sleep 30s
    fi
  done
  main::errhandle_log_info "Set metadata ${key}=${value} for ${HOSTNAME}."
  sleep 10 # match with main::wait_for_metadata()
}

main::wait_for_host() {
  local host="${1}"
  local count=0

  ## Check host was passed
  if [[ -z "${host}" ]]; then
     main::errhandle_log_error "Unable to check host is available as host was not supplied."
  fi

  ## Wait until host is contactable via sftp
  while ! sftp -o StrictHostKeyChecking=no "${host}":/proc/uptime /dev/null >/dev/null; do
    count=$((count +1))
    main::errhandle_log_info "--- ${host} is not accessible via SSH - sleeping for 10 seconds and trying again"
    sleep 10
    if [ $count -gt 60 ]; then
      main::errhandle_log_error "${host} not available after waiting 600 seconds"
    fi
  done
}

main::wait_for_metadata() {
  local host="${1}"
  local key="${2}"
  local value="${3}"

  local count=0
  local max_count=360
  local set_value
  local host_zone

  host_zone=$(main::get_host_zone "${host}")

  while [[ ! "${set_value}" == "${value}" ]]; do
    count=$((count +1))
    main::errhandle_log_info "Waiting for '${key}' to be set to '${value}' on '${host}' before continuing. Attempt ${count}/${max_count}"
    set_value=$(${GCLOUD} --quiet compute instances describe ${host} --format="value[](metadata.items.${key})" --zone=${host_zone})

    main::errhandle_log_info "Retrieved '${set_value}' for '${key}' from '${host}'. Attempt ${count}/${max_count}"
    ## error out if the metadata is set to a complete/error code
    if [[ "${set_value}" == "completed" ]] || [[ "${set_value}" == "completed_with_warnings" ]] || [[ "${set_value}" == "failed_or_error" ]]; then
      main::errhandle_log_error "Host ${host} completed its deployment before '${key}' was set to '${value}'"
    fi

    ## error out if max number of retries hit
    if [ ${count} -gt ${max_count} ]; then
      main::errhandle_log_error "'${key}' wasn't set to '${value}' on '${host}' within an acceptable time."
    fi

    sleep 10
  done

  main::errhandle_log_info "'${key}' is set to '${value}' on '${host}'. Continuing"
}

main::complete() {
  local on_error=${1}

  # we only want to run gcloud commands if it's defined
  if [[ -n "${GCLOUD}" ]]; then
    ## update instance metadata with status
    if [[ -n "${on_error}" ]]; then
      main::set_metadata "status" "failed_or_error"
      metrics::send_metric -s "ERROR"  -e "1" > /dev/null 2>&1
    elif [[ -n "${deployment_warnings}" ]]; then
      main::errhandle_log_info "INSTANCE DEPLOYMENT COMPLETE"
      main::set_metadata "status" "completed_with_warnings"
      metrics::send_metric -s "ERROR"  -e "2" > /dev/null 2>&1
    else
      main::errhandle_log_info "INSTANCE DEPLOYMENT COMPLETE"
      main::set_metadata "status" "completed"
      metrics::send_metric -s "CONFIGURED" > /dev/null 2>&1
    fi

    ## prepare advanced logs
    if [[ "${VM_METADATA[sap_deployment_debug]}" = "True" ]]; then
      mkdir -p /root/.deploy
      main::errhandle_log_info "--- Debug mode is turned on. Preparing additional logs"
      env > /root/.deploy/"${HOSTNAME}"_debug_env.log
      grep startup /var/log/messages > /root/.deploy/"${HOSTNAME}"_debug_startup_script_output.log
      tar -czvf /root/.deploy/"${HOSTNAME}"_deployment_debug.tar.gz -C /root/.deploy/ .
      main::errhandle_log_info "--- Debug logs stored in /root/.deploy/"
      ## Upload logs to GCS bucket & display complete message
      if [ -n "${VM_METADATA[sap_hana_deployment_bucket]}" ]; then
        main::errhandle_log_info "--- Uploading logs to Google Cloud Storage bucket"
        ${GSUTIL} -q cp /root/.deploy/"${HOSTNAME}"_deployment_debug.tar.gz  gs://"${VM_METADATA[sap_hana_deployment_bucket]}"/logs/
      fi
    fi
  fi

  # only run post deployment script if this is not an error
  if [[ -z "${on_error}" ]]; then
    ## Run custom post deployment script
    if [[ -n "${VM_METADATA[post_deployment_script]}" ]]; then
        main::errhandle_log_info "--- Running custom post deployment script - ${VM_METADATA[post_deployment_script]}"
      if [[ "${VM_METADATA[post_deployment_script]:0:8}" = "https://" ]] || [[ "${VM_METADATA[post_deployment_script]:0:7}" = "http://" ]]; then
        source /dev/stdin <<< "$(curl -s "${VM_METADATA[post_deployment_script]}")"
      elif [[ "${VM_METADATA[post_deployment_script]:0:5}" = "gs://" ]]; then
        source /dev/stdin <<< "$("${GSUTIL}" cat "${VM_METADATA[post_deployment_script]}")"
      else
        main::errhandle_log_warning "--- Unknown post deployment script. URL must begin with https:// http:// or gs://"
      fi
    fi
  fi

  if [[ -z "${deployment_warnings}" ]]; then
    main::errhandle_log_info "--- Finished"
  else
    main::errhandle_log_warning "--- Finished (${deployment_warnings} warnings)"
  fi

  ## exit sending right error code
  if [[ -n "${on_error}" ]]; then
    exit 1
  else
    exit 0
  fi
}

main::send_start_metrics() {
  metrics::send_metric -s "STARTED" > /dev/null 2>&1
  metrics::send_metric -s "TEMPLATEID" > /dev/null 2>&1
}

main::install_ops_agent() {
  if [[ ! "${VM_METADATA[install_cloud_ops_agent]}" == "false" ]]; then
    main::errhandle_log_info "Installing Google Ops Agent"
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    sudo bash add-google-cloud-ops-agent-repo.sh --also-install
  fi
}

main::install_monitoring_agent() {
  local msg1
  local msg2

  main::errhandle_log_info "Installing Agent for SAP"

  if [[ "${LINUX_DISTRO}" = "SLES" ]] && [[ -e /usr/lib/systemd/system/google-cloud-sap-agent.service ]]; then
      # remove the existing agent so we install the latest from the google repo
      zypper remove -y google-cloud-sap-agent
  fi

  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    main::errhandle_log_info "Installing agent for SLES"
    # SLES
    zypper addrepo --refresh https://packages.cloud.google.com/yum/repos/google-cloud-sap-agent-sles$(grep "VERSION_ID=" /etc/os-release | cut -d = -f 2 | tr -d '"' | cut -d . -f 1)-\$basearch google-cloud-sap-agent
    zypper mr --priority 90 google-cloud-sap-agent

    if timeout 300 zypper --gpg-auto-import-keys install -y "google-cloud-sap-agent"; then
      main::errhandle_log_info "Finished installation Agent for SAP"
    else
      local msg1="Agent for SAP did not install correctly."
      local msg2="Try to install it manually."
      main::errhandle_log_info "${msg1} ${msg2}"
    fi
  elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
    # RHEL
    main::errhandle_log_info "Installing agent for RHEL"

  tee /etc/yum.repos.d/google-cloud-sap-agent.repo << EOM
[google-cloud-sap-agent]
name=Google Cloud Agent for SAP
baseurl=https://packages.cloud.google.com/yum/repos/google-cloud-sap-agent-el$(cat /etc/redhat-release | cut -d . -f 1 | tr -d -c 0-9)-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM

    if timeout 300 yum install -y "google-cloud-sap-agent"; then
      main::errhandle_log_info "Finished installation Agent for SAP"
    else
      local msg1="Agent for SAP did not install correctly."
      local msg2="Try to install it manually."
      main::errhandle_log_info "${msg1} ${msg2}"
    fi
  fi
  set +e
}

hdb::calculate_volume_sizes() {
  if [[ "${VM_METADATA[use_single_shared_data_log_disk]}" = "false" ]]; then
    main::errhandle_log_info "No disk volume size calculation needed, using multiple disks used for /usr/sap, shared, data, log."
    return 0
  fi

  main::errhandle_log_info "Calculating disk volume sizes"

  hana_log_size=$((VM_MEMSIZE/2))

  if [[ ${hana_log_size} -gt 512 ]]; then
    hana_log_size=512
  fi

  hana_data_size=$(((VM_MEMSIZE*12)/10))

  # check if node is a standby or not
  if [[ "${VM_METADATA[hana_node_type]}" = "secondary" ]]; then
    hana_shared_size=0
  else
    # determine hana shared size based on memory size
    hana_shared_size=${VM_MEMSIZE}

    if [[ ${hana_shared_size} -gt 1024 ]]; then
        hana_shared_size=1024
    fi

    # increase shared size if there are more than 3 nodes
    if [[ ${VM_METADATA[sap_hana_scaleout_nodes]} -gt 3 ]]; then
      hana_shared_size_multi=$(/usr/bin/python -c "print (int(round(${VM_METADATA[sap_hana_scaleout_nodes]} /4 + 0.5)))")
      hana_shared_size=$((hana_shared_size * hana_shared_size_multi))
    fi
  fi

  ## if there is enough space (i.e, multi_sid enabled or if 208GB instances) then double the volume sizes
  hana_pdssd_size=$(($(lsblk --nodeps --bytes --noheadings --output SIZE $DEVICE_SINGLE_PD)/1024/1024/1024))
  hana_pdssd_size_x2=$(((hana_data_size+hana_log_size)*2 +hana_shared_size))

  if [[ ${hana_pdssd_size} -gt ${hana_pdssd_size_x2} ]]; then
    main::errhandle_log_info "--- Determined double volume sizes are required"
    main::errhandle_log_info "--- Determined minimum data volume requirement to be $((hana_data_size*2))"
    hana_log_size=$((hana_log_size*2))
  else
    main::errhandle_log_info "--- Determined minimum data volume requirement to be ${hana_data_size}"
    main::errhandle_log_info "--- Determined log volume requirement to be ${hana_log_size}"
    main::errhandle_log_info "--- Determined shared volume requirement to be ${hana_shared_size}"
  fi
}

hdb::create_sap_data_log_volumes() {
  main::errhandle_log_info "Building /usr/sap, /hana/data & /hana/log"

  if [[ "${VM_METADATA[use_single_shared_data_log_disk]}" = "true" ]]; then
    ## create volume group
    main::create_vg $DEVICE_SINGLE_PD vg_hana

    ## create logical volumes
    main::errhandle_log_info '--- Creating logical volumes'
    lvcreate -L 32G -n sap vg_hana
    lvcreate -L ${hana_log_size}G -n log vg_hana
    lvcreate -l 100%FREE -n data vg_hana

    ## format file systems
    main::format_mount /usr/sap /dev/vg_hana/sap xfs
    main::format_mount /hana/data /dev/vg_hana/data xfs
    main::format_mount /hana/log /dev/vg_hana/log xfs
  else
    main::create_vg $DEVICE_DATA vg_hana_data
    lvcreate -l 100%FREE -n data vg_hana_data
    main::format_mount /hana/data /dev/vg_hana_data/data xfs

    main::create_vg $DEVICE_LOG vg_hana_log
    lvcreate -l 100%FREE -n log vg_hana_log
    main::format_mount /hana/log /dev/vg_hana_log/log xfs

    main::create_vg $DEVICE_USRSAP vg_hana_usrsap
    lvcreate -l 100%FREE -n usrsap vg_hana_usrsap
    main::format_mount /usr/sap /dev/vg_hana_usrsap/usrsap xfs
  fi

  ## create base folders
  mkdir -p /hana/data/"${VM_METADATA[sap_hana_sid]}" /hana/log/"${VM_METADATA[sap_hana_sid]}"
  chmod 777 /hana/data/"${VM_METADATA[sap_hana_sid]}" /hana/log/"${VM_METADATA[sap_hana_sid]}"

  ## add 2GB swap file as per Note 1999997, point 21. Non-critical, warning on failure
  main::errhandle_log_info "Attempting to add swap space"
  if (( $(free -k | grep -i swap | awk '{print $2}') > 2097152 )); then
    main::errhandle_log_warning "Swap space larger than recommended 2GiB. Please review."
  elif (( $(free -k | grep -i swap | awk '{print $2}') > 0 )); then
    main::errhandle_log_info "Non-zero swap already exists. Skipping."
  else
    if dd if=/dev/zero of=/swapfile bs=1048576 count=2048; then
      chmod 0600 /swapfile
      mkswap /swapfile
      echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
      systemctl daemon-reload
      swapon /swapfile
    fi
    if (( $(free -k | grep -i swap | awk '{print $2}') > 0 )); then
      main::errhandle_log_info "Swap space added."
    else
      main::errhandle_log_warning "Swap space not added. Post-processing needed."
    fi
  fi
}


hdb::create_shared_volume() {
  if [[ -n ${VM_METADATA[sap_hana_shared_nfs]} ]]; then
    main::errhandle_log_info "NFS endpoint specified for /hana/shared. Skipping block device."
    return 0
  fi

  main::errhandle_log_info "Building /hana/shared"
  if [[ "${VM_METADATA[use_single_shared_data_log_disk]}" = "true" ]]; then
    main::create_vg $DEVICE_SINGLE_PD vg_hana
    lvcreate -L ${hana_shared_size}G -n shared vg_hana
    main::format_mount /hana/shared /dev/vg_hana/shared xfs
  else
    main::create_vg $DEVICE_SHARED vg_hana_shared
    lvcreate -l 100%FREE -n shared vg_hana_shared
    main::format_mount /hana/shared /dev/vg_hana_shared/shared xfs
  fi
}


hdb::create_backup_volume() {
  if [[ -n ${VM_METADATA[sap_hana_backup_nfs]} ]]; then
    main::errhandle_log_info "NFS endpoint specified for /hanabackup. Skipping block device."
    return 0
  fi

  if [[ -n $DEVICE_BACKUP ]]; then
    main::errhandle_log_info "Building /hanabackup"

    ## create volume group
    main::create_vg $DEVICE_BACKUP vg_hanabackup

    main::errhandle_log_info "--- Creating logical volume"
    lvcreate -l 100%FREE -n backup vg_hanabackup

    ## create filesystems
    main::format_mount /hanabackup /dev/vg_hanabackup/backup xfs
  fi
}


hdb::set_kernel_parameters(){
  main::errhandle_log_info "Setting kernel paramaters"

  # b/190863339 - pagecache_limit_mb only relevant to SLES 12
  if [[ "${LINUX_DISTRO}" = "SLES" && "${LINUX_MAJOR_VERSION}" = "12" ]]; then
    echo "vm.pagecache_limit_mb = 0" >> /etc/sysctl.conf
  fi
  {
    echo "net.ipv4.tcp_slow_start_after_idle=0"
    echo "kernel.numa_balancing = 0"
    echo "net.ipv4.tcp_slow_start_after_idle=0"
    echo "net.core.somaxconn = 4096"
    echo "net.ipv4.tcp_tw_reuse = 1"
    echo "net.ipv4.tcp_tw_recycle = 1"
    echo "net.ipv4.tcp_timestamps = 1"
    echo "net.ipv4.tcp_syn_retries = 8"
    echo "net.ipv4.tcp_wmem = 4096 16384 4194304"
    echo "net.ipv4.tcp_limit_output_bytes = 1048576"
  } >> /etc/sysctl.conf

  sysctl -p

  main::errhandle_log_info "Preparing tuned/saptune"

  if [[ "${LINUX_DISTRO}" = "SLES" ]]; then
    saptune solution apply HANA
    saptune daemon start
  else
    mkdir -p /etc/tuned/sap-hana/
    cp /usr/lib/tuned/sap-hana/tuned.conf /etc/tuned/sap-hana/
    systemctl start tuned
    systemctl enable tuned
    tuned-adm profile sap-hana
  fi
}


hdb::download_media() {
  main::errhandle_log_info "Downloading HANA media from ${VM_METADATA[sap_hana_deployment_bucket]}"
  mkdir -p /hana/shared/media

  # Check for sap_hana_deployment_bucket being empty in hdb::create_install_cfg()

  # Check you have access to the bucket
  if ! ${GSUTIL} ls gs://"${VM_METADATA[sap_hana_deployment_bucket]}"/; then
    main::errhandle_log_error "SAP HANA media bucket '${VM_METADATA[sap_hana_deployment_bucket]}' cannot be accessed. The deployment has finished and is ready for SAP HANA, but SAP HANA will need to be downloaded and installed manually."
  fi

  # Set the media number, so we know
  VM_METADATA[sap_hana_media_number]="$(${GSUTIL} ls gs://${VM_METADATA[sap_hana_deployment_bucket]} | grep _part1.exe | awk -F"/" '{print $NF}' | sed 's/_part1.exe//')"

  # If SP4 or above, get the media number from the .ZIP
  if [[ -z ${VM_METADATA[sap_hana_media_number]} ]]; then
    VM_METADATA[sap_hana_media_number]="$(${GSUTIL} ls gs://${VM_METADATA[sap_hana_deployment_bucket]}/51* | grep -i .ZIP | awk -F"/" '{print $NF}' | sed 's/.ZIP//I')"
  fi

  # b/169984954 fail here already so user understands easier what is wrong
  if [[ -z ${VM_METADATA[sap_hana_media_number]} ]]; then
    main::errhandle_log_error "HANA Media not found in bucket. Expected format gs://${VM_METADATA[sap_hana_deployment_bucket]}/51*.[zip|ZIP]. The deployment has finished and is ready for SAP HANA, but SAP HANA will need to be downloaded and installed manually."
  fi

  ## download unrar from GCS. Fix for RHEL missing unrar and SAP packaging change which stoppped unar working.
  if [[ ${DEPLOY_URL} = gs* ]]; then
    ${GSUTIL} -q cp "${DEPLOY_URL}"/third_party/unrar/unrar /root/.deploy/unrar
  else
    curl "${DEPLOY_URL}"/third_party/unrar/unrar -o /root/.deploy/unrar
  fi
  chmod a=wrx /root/.deploy/unrar

  ## download SAP HANA media
  main::errhandle_log_info "gsutil cp of gs://${VM_METADATA[sap_hana_deployment_bucket]} to /hana/shared/media/ in progress..."
  # b/259315464 - no parallelism on SLES12
  local parallel="-m"
  if [[ ${LINUX_DISTRO} = "SLES" && "${LINUX_MAJOR_VERSION}" = "12" ]]; then
    parallel=""
  fi
  if ! ${GSUTIL} -q -o "GSUtil:state_dir=/root/.deploy" ${parallel} cp gs://"${VM_METADATA[sap_hana_deployment_bucket]}"/* /hana/shared/media/; then
    main::errhandle_log_error "HANA Media Download Failed. The deployment has finished and is ready for SAP HANA, but SAP HANA will need to be downloaded and installed manually."
  fi
  main::errhandle_log_info "gsutil cp of HANA media complete."
}


hdb::create_install_cfg() {

  ## output settings to log
  main::errhandle_log_info "Creating HANA installation configuration file /root/.deploy/${HOSTNAME}_hana_install.cfg"

  errored=""

  ## check parameters
  if [ -z "${VM_METADATA[sap_hana_deployment_bucket]}" ]; then
    main::errhandle_log_warning "SAP HANA deployment bucket is missing or incorrect in the accelerator template."
    errored="true"
  fi
  if [ -z "${VM_METADATA[sap_hana_system_password]}" ]; then
    main::errhandle_log_warning "SAP HANA system password or password secret was missing or incomplete in the accelerator template."
    errored="true"
  fi
  if [ -z "${VM_METADATA[sap_hana_sidadm_password]}" ]; then
    main::errhandle_log_warning "SAP HANA sidadm password or password secret was missing or incomplete in the accelerator template."
    errored="true"
  fi
  if [ -z "${VM_METADATA[sap_hana_sid]}" ]; then
    main::errhandle_log_warning "SAP HANA sid was missing or incomplete in the accelerator template."
    errored="true"
  fi
  if [ -z "${VM_METADATA[sap_hana_sidadm_uid]}" ]; then
    main::errhandle_log_warning "SAP HANA sidadm uid was missing or incomplete in the accelerator template."
    errored="true"
  fi
  if [ -n "${errored}" ]; then
    main::errhandle_log_error "Due to missing parameters, the deployment has finished and ready for SAP HANA, but SAP HANA will need to be installed manually."
  fi

  mkdir -p /root/.deploy

  ## create hana_install.cfg file
  {
    echo "[General]"  >/root/.deploy/"${HOSTNAME}"_hana_install.cfg
    echo "components=client,server"
    echo "[Server]"
    echo "sid=${VM_METADATA[sap_hana_sid]}"
    echo "number=${VM_METADATA[sap_hana_instance_number]}"
    echo "userid=${VM_METADATA[sap_hana_sidadm_uid]}"
    echo "groupid=${VM_METADATA[sap_hana_sapsys_gid]}"
    echo "apply_system_size_dependent_parameters=off"
  } >>/root/.deploy/"${HOSTNAME}"_hana_install.cfg

  ## If HA configured, disable autostart
  if [ -n "${VM_METADATA[sap_vip]}" ]; then
    echo "autostart=n" >>/root/.deploy/"${HOSTNAME}"_hana_install.cfg
  else
    echo "autostart=y" >>/root/.deploy/"${HOSTNAME}"_hana_install.cfg
  fi

  ## If scale-out then add the GCE Storage Connector
  if [ -n "${VM_METADATA[sap_hana_standby_nodes]}" ]; then
    echo "storage_cfg=/hana/shared/gceStorageClient" >>/root/.deploy/"${HOSTNAME}"_hana_install.cfg
  fi

}

hdb::build_pw_xml() {
  if [ -n "${VM_METADATA[sap_hana_system_password]}" ] || [ -n "${VM_METADATA[sap_hana_sidadm_password]}" ]; then
    ## set password for stdin use with hdblcm --read_password_from_stdin=xml
    ## single quotes required for ! as special character
    local hana_xml='<?xml version="1.0" encoding="UTF-8"?><Passwords>'
    hana_xml+='<password><![CDATA['
    hana_xml+=${VM_METADATA[sap_hana_sidadm_password]}
    hana_xml+=']]></password><sapadm_password><![CDATA['
    hana_xml+=${VM_METADATA[sap_hana_sidadm_password]}
    hana_xml+=']]></sapadm_password><system_user_password><![CDATA['
    hana_xml+=${VM_METADATA[sap_hana_system_password]}
    hana_xml+=']]></system_user_password></Passwords>'
    echo ${hana_xml}
  else
    main::errhandle_log_error "Required passwords could not be retrieved. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required."
  fi
}

hdb::extract_media() {
  local media_file

  main::errhandle_log_info "Extracting SAP HANA media"
  cd /hana/shared/media/ || main::errhandle_log_error "Unable to access /hana/shared/media. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required."

  media_file=$(find /hana/shared/media  -maxdepth 1 -type f -iname "${VM_METADATA[sap_hana_media_number]}*.ZIP")
  if [[ -n ${media_file} ]]; then
    mkdir -p /hana/shared/media/"${VM_METADATA[sap_hana_media_number]}"/
    unzip -o "${media_file}" -d /hana/shared/media/"${VM_METADATA[sap_hana_media_number]}"/
    mv "${media_file}" /hana/shared/media/"${VM_METADATA[sap_hana_media_number]}"/
  elif [[ -n $(find /hana/shared/media -maxdepth 1 -iname "${VM_METADATA[sap_hana_media_number]}*part1.exe") ]]; then
    ## Workaround requried due to unar not working with SAP HANA 2.0 SP3. TODO - Remove once no longer required
    if [[ -f /root/.deploy/unrar ]]; then
      if ! /root/.deploy/unrar -o+ x "${VM_METADATA[sap_hana_media_number]}*part1.exe" >/dev/null; then
        main::errhandle_log_error "HANA media extraction failed. Please ensure the correct media is uploaded to your GCS bucket"
      fi
    elif [ "${LINUX_DISTRO}" = "SLES" ]; then
      if ! unrar -o+ x "*part1.exe" >/dev/null; then
        main::errhandle_log_error "HANA media extraction failed. Please ensure the correct media is uploaded to your GCS bucket"
      fi
    elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
      local file
      for file in *.exe; do
        if ! unar -f "${file}" >/dev/null; then
          main::errhandle_log_error "HANA media extraction failed. Please ensure the correct media is uploaded to your GCS bucket"
        fi
      done
    fi
  else
    main::errhandle_log_error "Unable to find SAP HANA media. Please ensure the media is uploaded to your GCS bucket in the correct format"
  fi
}


hdb::install() {
  main::errhandle_log_info 'Installing SAP HANA'
  if [[ ! "$(grep -c "${VM_METADATA[sap_hana_sid],,}"adm /etc/passwd)" == "0" ]]; then
    main::errhandle_log_warning "--- User ${VM_METADATA[sap_hana_sid],,}adm already exists on the system. This may prevent SAP HANA from installing correctly. If this occurs, ensure that you are using a clean image and that ${VM_METADATA[sap_hana_sid],,}adm doesn't exist in the project ssh-keys metadata"
  fi

  if ! echo $(hdb::build_pw_xml) | /hana/shared/media/"${VM_METADATA[sap_hana_media_number]}"/DATA_UNITS/HDB_LCM_LINUX_X86_64/hdblcm --configfile=/root/.deploy/"${HOSTNAME}"_hana_install.cfg --read_password_from_stdin=xml -b; then
    main::errhandle_log_error "HANA Installation Failed. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required"
  fi

  # workaround for backup/log directory missing bug in HANA 2.0 SP4 Rev40
  mkdir -p /usr/sap/"${VM_METADATA[sap_hana_sid]}"/HDB"${VM_METADATA[sap_hana_instance_number]}"/backup/log
  mkdir -p /usr/sap/"${VM_METADATA[sap_hana_sid]}"/HDB"${VM_METADATA[sap_hana_instance_number]}"/backup/data
  mkdir -p /usr/sap/"${VM_METADATA[sap_hana_sid]}"/HDB"${VM_METADATA[sap_hana_instance_number]}"/backup/sec
}


hdb::upgrade(){
  if [ "$(ls /hana/shared/media/IMDB_SERVER*.SAR)" ]; then
    main::errhandle_log_info "An SAP HANA update was found in GCS. Performing the upgrade:"
    main::errhandle_log_info "--- Extracting HANA upgrade media"
    cd /hana/shared/media || main::errhandle_log_error "Unable to access /hana/shared/media. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required."
    /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/exe/hdb/SAPCAR -xvf "IMDB_SERVER*.SAR"
    cd SAP_HANA_DATABASE || main::errhandle_log_error "Unable to access /hana/shared/media. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required."
    main::errhandle_log_info "--- Upgrading Database"
    # remove component specification from install batch config. hdblcm will auto-detect components from patch file location.
    sed -i '/^components=/d' /root/.deploy/"${HOSTNAME}"_hana_install.cfg || main::errhandle_log_warning "Unable to update batch install configuration file. Upgrade may fail."
    if ! echo $(hdb::build_pw_xml) | ./hdblcm --configfile=/root/.deploy/"${HOSTNAME}"_hana_install.cfg --action=update --ignore=check_signature_file --update_execution_mode=optimized --read_password_from_stdin=xml --batch; then
        main::errhandle_log_warning "SAP HANA Database revision upgrade failed to install."
    fi
  fi
}


hdb::install_afl() {
  if [[ "$(${GSUTIL} ls gs://"${VM_METADATA[sap_hana_deployment_bucket]}"/IMDB_AFL*)" ]]; then
    main::errhandle_log_info "SAP AFL was found in GCS. Installing SAP AFL addon"
    main::errhandle_log_info "--- Downloading AFL media"
    ${GSUTIL} -q cp gs://"${VM_METADATA[sap_hana_deployment_bucket]}"/IMDB_AFL*.SAR /hana/shared/media/
    main::errhandle_log_info "--- Extracting AFL media"
    cd /hana/shared/media || main::errhandle_log_warning "AFL failed to install"
    /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/exe/hdb/SAPCAR -xvf "IMDB_AFL*.SAR"
    cd SAP_HANA_AFL || main::errhandle_log_warning "AFL failed to install"
    main::errhandle_log_info "--- Installing AFL"
    ./hdbinst --sid="${VM_METADATA[sap_hana_sid]}"
  fi
}


hdb::set_parameters() {
  local inifile=${1}
  local section=${2}
  local setting=${3}
  local value=${4}
  local tenant=${5}
  main::errhandle_log_info "--- Setting database parameters for ${section}:${setting}"
  # if tenant specified, run it on that tenant. Else do it in SYSTEMDB. If that fails (HANA 2.0 SP0 <) then run it without specifying a tenant
  if [[ -n ${tenant} ]]; then
    bash -c "source /usr/sap/${VM_METADATA[sap_hana_sid]}/home/.sapenv.sh && hdbsql -d ${tenant} -u SYSTEM -p '"${VM_METADATA[sap_hana_system_password]}"' -i ${VM_METADATA[sap_hana_instance_number]} \"ALTER SYSTEM ALTER CONFIGURATION ('$inifile', 'SYSTEM') SET ('$section','$setting') = '$value' with reconfigure\""
  else
    if ! bash -c "source /usr/sap/${VM_METADATA[sap_hana_sid]}/home/.sapenv.sh && hdbsql -d SYSTEMDB -u SYSTEM -p '"${VM_METADATA[sap_hana_system_password]}"' -i ${VM_METADATA[sap_hana_instance_number]} \"ALTER SYSTEM ALTER CONFIGURATION ('$inifile', 'SYSTEM') SET ('$section','$setting') = '$value' with reconfigure\""; then
      bash -c "source /usr/sap/${VM_METADATA[sap_hana_sid]}/home/.sapenv.sh && hdbsql -u SYSTEM -p '"${VM_METADATA[sap_hana_system_password]}"' -i ${VM_METADATA[sap_hana_instance_number]} \"ALTER SYSTEM ALTER CONFIGURATION ('$inifile', 'SYSTEM') SET ('$section','$setting') = '$value' with reconfigure\""
    fi
  fi
}


hdb::config_backup() {
  if [[ "${VM_METADATA[sap_hana_backup_disk]}" = "true" \
      || -n ${VM_METADATA[sap_hana_backup_nfs]} ]]; then

    main::errhandle_log_info 'Configuring backup locations to /hanabackup'
    mkdir -p /hanabackup/data/"${VM_METADATA[sap_hana_sid]}" /hanabackup/log/"${VM_METADATA[sap_hana_sid]}"
    chown -R root:sapsys /hanabackup
    chmod -R g=wrx /hanabackup
    hdb::set_parameters global.ini persistence basepath_databackup /hanabackup/data/"${VM_METADATA[sap_hana_sid]}"
    hdb::set_parameters global.ini persistence basepath_logbackup /hanabackup/log/"${VM_METADATA[sap_hana_sid]}"
    hdb::set_parameters global.ini persistence basepath_catalogbackup /hanabackup/log/"${VM_METADATA[sap_hana_sid]}"
  elif [[ -n "${VM_METADATA[sap_primary_instance]}" ]]; then
    main::errhandle_log_warning 'WARNING: No backup disk provisioned. Configuring "/hana/shared" as backup location for initial backup in HA deployment. Make sure to change backup configuration after deployment.'

    mkdir -p /hana/shared/backup/data/"${VM_METADATA[sap_hana_sid]}" /hana/shared/backup/log/"${VM_METADATA[sap_hana_sid]}"
    chown -R root:sapsys /hana/shared/backup
    chmod -R g=wrx /hana/shared/backup
    hdb::set_parameters global.ini persistence basepath_databackup /hana/shared/backup/data/"${VM_METADATA[sap_hana_sid]}"
    hdb::set_parameters global.ini persistence basepath_logbackup /hana/shared/backup/log/"${VM_METADATA[sap_hana_sid]}"
    hdb::set_parameters global.ini persistence basepath_catalogbackup /hana/shared/backup/log/"${VM_METADATA[sap_hana_sid]}"
  else
    main::errhandle_log_warning 'WARNING: No backup disk provisioned. Skipping configuration of backup locations.'
  fi
}


hdb::config_hyperdisk_parameters() {
  if [[ "${VM_METADATA[sap_hana_data_disk_type]}" = "hyperdisk-extreme" ]] || [[ "${VM_METADATA[sap_hana_data_disk_type]}" = "hyperdisk-balanced" ]]; then

    main::errhandle_log_info 'Setting HANA Parameters for hyperdisks'
    hdb::set_parameters global.ini fileio num_completion_queues 12
    hdb::set_parameters global.ini fileio num_submit_queues 12
    hdb::set_parameters indexserver.ini parallel tables_preloaded_in_parallel 32
    hdb::set_parameters indexserver.ini global load_table_numa_aware true
  fi
}


hdb::check_settings() {
  main::errhandle_log_info "Checking settings for HANA deployment"

  ## Set defaults if required
  VM_METADATA[sap_hana_sidadm_uid]=$(main::check_default 900 "${VM_METADATA[sap_hana_sidadm_uid]}")
  VM_METADATA[sap_hana_sapsys_gid]=$(main::check_default 79 "${VM_METADATA[sap_hana_sapsys_gid]}")

  ## fix instance number to be two digits
  local tmp_instance_number
  if [[ -n "${VM_METADATA[sap_hana_instance_number]}" ]]; then
    if [[ ${VM_METADATA[sap_hana_instance_number]} -lt 10 ]]; then
     tmp_instance_number="0${VM_METADATA[sap_hana_instance_number]}"
     VM_METADATA[sap_hana_instance_number]=${tmp_instance_number}
    fi
  fi

  ## figure out the master node hostname
  if [[ ${VM_METADATA[startup-script]} = *"secondary"* ]]; then
     hana_master_node="$(hostname | rev | cut -d"w" -f2-999 | rev)"
  else
     hana_master_node=${HOSTNAME}
  fi

  ## Remove passwords from metadata
  main::remove_metadata sap_hana_system_password
  main::remove_metadata sap_hana_sidadm_password

  ## Detect devices for attached disks
  ##   - Names of disks correspond to what is defined on TF side
  ##      - universal (1 disk) PD has '<VM-name>-hana'   in name
  ##      - /hana/data PD         has '<VM-name>-data'   in name
  ##      - /hana/log PD          has '<VM-name>-log'    in name
  ##      - /hana/shared PD       has '<VM-name>-shared' in name
  ##      - /usr/sap PD           has '<VM-name>-usrsap' in name
  ##      - /hanabackup PD        has '<VM-name>-backup' in name
  # Worker nodes in sap_hana and sap_hana_scaleout use different naming
  # convention.
  #       - VMs are named <Primary-VM-name>w1 to <Primary-VM-name>w16
  #       - Disks are named <Primary-VM-name>-<meaning>-00XX (XX = 01 to 16)
  main::errhandle_log_info "Determining device names for HANA deployment"

  local vm_name=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/name")

  # Adopting VM name used in disks for worker nodes (sap_hana and sap_hana_scaleout tf templates)
  if [[ -n "${VM_METADATA[sap_hana_original_role]}" && "${VM_METADATA[sap_hana_original_role]}" = "worker" || "${VM_METADATA[sap_hana_scaleout_nodes]}" -gt 0 ]]; then
    # If majority maker is present (sap_hana_ha in scale-out mode) then do not change the vm name
    if [[ -z "${VM_METADATA[majority_maker_instance_name]}" ]]; then
      vm_name=$(echo "${vm_name}" | awk '{split($0,a,"w[0-9]"); print a[1]}')
    fi
  fi

  local name_single_pd="${vm_name}".*-hana
  local name_data="${vm_name}"-data
  local name_log="${vm_name}"-log
  local name_usrsap="${vm_name}"-usrsap
  local name_shared="${vm_name}"-shared
  local name_backup="${vm_name}"-backup

  if [[ -n "${VM_METADATA[sap_hana_original_role]}" && \
        ! "${VM_METADATA[sap_hana_original_role]}" = "standby" ]]; then

    # Scale-out scenario (sap_hana_scaleout) - non-standby nodes
    #   - we have either a single disk or 2 disks (hana, log)
    if [[ "${VM_METADATA[use_single_data_log_disk]}" = "true" ]]; then
      readonly DEVICE_SINGLE_PD=$(main::get_device_by_id "${name_single_pd}")
      main::errhandle_log_info "DEVICE_SINGLE_PD is ${DEVICE_SINGLE_PD}"
    else
      readonly DEVICE_DATA=$(main::get_device_by_id "${name_data}")
      main::errhandle_log_info "DEVICE_DATA is ${DEVICE_DATA}"
      readonly DEVICE_LOG=$(main::get_device_by_id "${name_log}")
      main::errhandle_log_info "DEVICE_LOG is ${DEVICE_LOG}"
    fi
  elif [[ -n "${VM_METADATA[sap_hana_original_role]}" && \
          "${VM_METADATA[sap_hana_original_role]}" = "standby" ]]; then

    # Scale-out scenario (sap_hana_scaleout) - standby nodes
    #   - we have no additional disks
    main::errhandle_log_info "Standby node, no devices to be detected."
  else
    # non-Scale-out scenarios (sap_hana, sap_hana_ha)
    #   - we have either a single disk or 3 disks (hana, log, usrsap)
    #     or 4 disks (hana, log, usrsap, shared)
    if [[ "${VM_METADATA[use_single_shared_data_log_disk]}" = "true" ]]; then
      readonly DEVICE_SINGLE_PD=$(main::get_device_by_id "${name_single_pd}")
      main::errhandle_log_info "DEVICE_SINGLE_PD is ${DEVICE_SINGLE_PD}"
    else
      readonly DEVICE_DATA=$(main::get_device_by_id "${name_data}")
      main::errhandle_log_info "DEVICE_DATA is ${DEVICE_DATA}"
      readonly DEVICE_LOG=$(main::get_device_by_id "${name_log}")
      main::errhandle_log_info "DEVICE_LOG is ${DEVICE_LOG}"
      readonly DEVICE_USRSAP=$(main::get_device_by_id "${name_usrsap}")
      main::errhandle_log_info "DEVICE_USRSAP is ${DEVICE_USRSAP}"

      if [[ "${VM_METADATA[sap_hana_shared_disk]}" = "true" ]]; then
        readonly DEVICE_SHARED=$(main::get_device_by_id "${name_shared}")
        main::errhandle_log_info "DEVICE_SHARED is ${DEVICE_SHARED}"
      fi
    fi
  fi

  if [[ "${VM_METADATA[sap_hana_backup_disk]}" = "true" ]]; then
    readonly DEVICE_BACKUP=$(main::get_device_by_id "${name_backup}")
    main::errhandle_log_info "DEVICE_BACKUP is ${DEVICE_BACKUP}"
  fi
}


hdb::config_nfs() {
  if [[ "${VM_METADATA[sap_hana_scaleout_nodes]}" -gt 0 \
        && -z ${VM_METADATA[sap_hana_shared_nfs]} ]]; then

    main::errhandle_log_info "Configuring NFS for scale-out"

    ## turn off NFS4 support
    sed -ie 's/NFS4_SUPPORT="yes"/NFS4_SUPPORT="no"/g' /etc/sysconfig/nfs || \
    sed -ie 's/vers4=y/vers4=n/g' /etc/nfs.conf
    # Addition for RHEL 8 where old config is removed
    # It is recommended not to mix the two

    main::errhandle_log_info "--- Starting NFS server"
    if [ "${LINUX_DISTRO}" = "SLES" ]; then
      systemctl start nfsserver
    elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
      systemctl start nfs || systemctl start nfs-server
    fi

    ## Check NFS has started - Fix for bug which occasionally causes a delay in the NFS start-up
    while [ "$(pgrep -c nfs)" -le 3 ]; do
      main::errhandle_log_info "--- NFS server not running. Waiting 10 seconds then trying again"
      sleep 10s
      if [ "${LINUX_DISTRO}" = "SLES" ]; then
        systemctl start nfsserver
      elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
        systemctl start nfs  || systemctl start nfs-server
      fi
    done

    ## Enable & start NFS service
    main::errhandle_log_info "--- Enabling NFS server at boot up"
    if [ "${LINUX_DISTRO}" = "SLES" ]; then
      systemctl enable nfsserver
    elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
      systemctl enable nfs  || systemctl enable nfs-server
    fi

    ## Adding file system to NFS exports file systems
    local worker
    for worker in $(seq 1 "${VM_METADATA[sap_hana_scaleout_nodes]}"); do
      echo "/hana/shared ${HOSTNAME}w${worker}(rw,no_root_squash,sync,no_subtree_check)" >>/etc/exports
      ## Backup volume is only created if the deployment was configured to include a backup disk
      if [[ "${VM_METADATA[sap_hana_backup_disk]}" = "true" ]]; then
        echo "/hanabackup ${HOSTNAME}w${worker}(rw,no_root_squash,sync,no_subtree_check)" >>/etc/exports
      fi
    done

    ## manually exporting file systems
    exportfs -rav
  fi
}


hdb::install_scaleout_nodes() {
  if [[ "${VM_METADATA[sap_hana_scaleout_nodes]}" -gt 0 ]]; then
    local worker

    main::errhandle_log_info "Installing ${VM_METADATA[sap_hana_scaleout_nodes]} additional worker nodes"
    cd /hana/shared/"${VM_METADATA[sap_hana_sid]}"/hdblcm || main::errhandle_log_error "Unable to access hdblcm. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required."

    ## Set basepath
    hdb::set_parameters global.ini persistence basepath_shared no

    for worker in $(seq 1 "${VM_METADATA[sap_hana_scaleout_nodes]}"); do
      main::exchange_sshpubkey_with "${HOSTNAME}w${worker}" "${CLOUDSDK_COMPUTE_ZONE}"
      main::errhandle_log_info "--- Adding node ${HOSTNAME}w${worker}"
      if ! echo $(hdb::build_pw_xml) | ./hdblcm --action=add_hosts --addhosts="${HOSTNAME}"w"${worker}" --root_user=root --listen_interface=global --read_password_from_stdin=xml -b; then
        main::errhandle_log_error "Unable to access hdblcm. The server deployment is complete but SAP HANA is not deployed. Manual SAP HANA installation will be required."
      fi
    done
  fi
}


hdb::mount_nfs() {
  if [[ -z ${VM_METADATA[sap_hana_shared_nfs]} ]]; then
    main::errhandle_log_info 'Mounting NFS volumes /hana/shared & /hanabackup'
    echo "$(hostname | rev | cut -d"w" -f2-999 | rev):/hana/shared /hana/shared nfs  nfsvers=3,rsize=32768,wsize=32768,hard,intr,timeo=18,retrans=200 0 0" >>/etc/fstab
    echo "$(hostname | rev | cut -d"w" -f2-999 | rev):/hanabackup /hanabackup nfs  nfsvers=3,rsize=32768,wsize=32768,hard,intr,timeo=18,retrans=200 0 0" >>/etc/fstab

    mkdir -p /hana/shared /hanabackup

    ## mount file systems
    mount -a
  fi
  ## check /hana/shared is mounted before continuing
  local count=0
  while ! grep -q '/hana/shared' /etc/mtab ; do
    count=$((count +1))
    main::errhandle_log_info "--- /hana/shared is not mounted. Waiting 10 seconds and trying again. [Attempt ${count}/100]"
    sleep 10s
    mount -a
    if [ ${count} -gt 100 ]; then
      main::errhandle_log_error "/hana/shared is not mounted - Unable to continue"
    fi
  done
  main::errhandle_log_info "--- /hana/shared successfully mounted."
}


hdb::backup() {
  local backup_name=${1}

  main::errhandle_log_info "Creating HANA backup ${backup_name}"
  PATH="$PATH:/usr/sap/${VM_METADATA[sap_hana_sid]}/HDB${VM_METADATA[sap_hana_instance_number]}/exe"

  ## Call bash with source script to avoid RHEL library errors
  bash -c "source /usr/sap/${VM_METADATA[sap_hana_sid]}/home/.sapenv.sh && hdbsql -u system -p '"${VM_METADATA[sap_hana_system_password]}"' -i ${VM_METADATA[sap_hana_instance_number]} \"BACKUP DATA USING FILE ('${backup_name}')\""
  bash -c "source /usr/sap/${VM_METADATA[sap_hana_sid]}/home/.sapenv.sh && hdbsql -u system -p '"${VM_METADATA[sap_hana_system_password]}"' -d SYSTEMDB -i ${VM_METADATA[sap_hana_instance_number]} \"BACKUP DATA for SYSTEMDB USING FILE ('${backup_name}_SYSTEMDB')\""
}


hdb::stop() {
  main::errhandle_log_info "Stopping SAP HANA"
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function StopSystem HDB
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function WaitforStopped 400 2 HDB
}


hdb::stop_nowait(){
  /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr "${VM_METADATA[sap_hana_instance_number]}" -function Stop
}


hdb::restart_nowait(){
  /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr "${VM_METADATA[sap_hana_instance_number]}" -function RestartInstance
}


hdb::start() {
  main::errhandle_log_info "Starting SAP HANA"
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function StartSystem HDB
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function WaitforStarted 400 2
}


hdb::start_nowait(){
  /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/exe/hdb/sapcontrol -prot NI_HTTP -nr "${VM_METADATA[sap_hana_instance_number]}" -function Start
}


hdb::install_backint() {
  main::errhandle_log_info "Installing SAP HANA Backint for Google Cloud Storage"
  su - "${VM_METADATA[sap_hana_sid],,}"adm -c "curl https://storage.googleapis.com/cloudsapdeploy/backint-gcs/install.sh | bash"
}

hdb::config_backint() {
  local backup_bucket="${1}"

  ## if bucket isn't specified as an argument, use the bucket defined in the VM metadata
  if [[ ${backup_bucket} ]]; then
    main::errhandle_log_info "--- Setting HANA backup bucket to ${backup_bucket}"
  elif [[ -n ${VM_METADATA[sap_hana_backup_bucket]} ]]; then
      backup_bucket=${VM_METADATA[sap_hana_backup_bucket]}
  else
      main::errhandle_log_warning "--- Unknown backup bucket specified. Backup using BackInt is unlikely to work without reviewing and correcting parameters"
  fi

  ## check if bucket is accessible
  if ! ${GSUTIL} -q ls gs://"${VM_METADATA[sap_hana_backup_bucket]}"; then
    main::errhandle_log_warning "--- Backup bucket doesn't exist or permission is denied."
  fi

  ## update configuration file with settings
  sed -i --follow-symlinks "s/<GCS Bucket Name>/${backup_bucket}/" /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/hdb/opt/hdbconfig/parameters.txt

  if ! grep -q DISABLE_COMPRESSION /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/hdb/opt/hdbconfig/parameters.txt; then
    echo "\\#DISABLE_COMPRESSION" >> /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/hdb/opt/hdbconfig/parameters.txt
  fi

  if ! grep -q CHUNK_SIZE_MB /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/hdb/opt/hdbconfig/parameters.txt; then
    echo "\\#CHUNK_SIZE_MB 1024" >> /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/hdb/opt/hdbconfig/parameters.txt
  fi

  ## Set SAP HANA parameters
  main::errhandle_log_info "--- Configuring SAP HANA to use BackInt"
  hdb::set_parameters global.ini backup data_backup_parameter_file /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/hdb/opt/hdbconfig/parameters.txt
  hdb::set_parameters global.ini backup log_backup_parameter_file /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/hdb/opt/hdbconfig/parameters.txt
  hdb::set_parameters global.ini backup catalog_backup_parameter_file /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/hdb/opt/hdbconfig/parameters.txt
  hdb::set_parameters global.ini backup log_backup_using_backint true
  hdb::set_parameters global.ini backup catalog_backup_using_backint true

  ## Calculate number of channels based on instanec size + Configure in SAP HANA
  local backup_channels
  backup_channels=$(((VM_MEMSIZE / 128) + (VM_MEMSIZE % 128 > 0)))
  if [[ ${backup_channels} -ge 16 ]]; then
    backup_channels=16
  fi

  hdb::set_parameters global.ini backup parallel_data_backup_backint_channels "${backup_channels}"

  ## Set catalog location
  hdb::set_parameters global.ini persistence 'basepath_catalogbackup' /hanabackup/log/"${VM_METADATA[sap_hana_sid]}"
}

hdbso::calculate_volume_sizes() {

  if [[ "${VM_METADATA[use_single_shared_data_log_disk]}" = "false" ]]; then
    main::errhandle_log_info "No disk volume size calculation needed, using multiple disks used for /usr/sap, shared, data, log."
    return 0
  fi

  if [[ ! "${VM_METADATA[sap_hana_original_role]}" = "standby" ]]; then
    main::errhandle_log_info "Calculating disk volume sizes"

    hana_log_size=$((VM_MEMSIZE/2))

    if [[ ${hana_log_size} -gt 512 ]]; then
      hana_log_size=512
    fi

    hana_data_size=$(((VM_MEMSIZE*12)/10))

    ## if there is enough space (i.e, multi_sid enabled or if 208GB instances) then double the volume sizes
    hana_pdssd_size=$(($(lsblk --nodeps --bytes --noheadings --output SIZE $DEVICE_SINGLE_PD)/1024/1024/1024))
    hana_pdssd_size_x2=$(((hana_data_size+hana_log_size)*2))

    if [[ ${hana_pdssd_size} -gt ${hana_pdssd_size_x2} ]]; then
      main::errhandle_log_info "--- Determined double volume sizes are required"
      main::errhandle_log_info "--- Determined minimum data volume requirement to be $((hana_data_size*2))"
      hana_log_size=$((hana_log_size*2))
    else
      main::errhandle_log_info "--- Determined minimum data volume requirement to be ${hana_data_size}"
      main::errhandle_log_info "--- Determined log volume requirement to be ${hana_log_size}"
    fi
  fi
}


hdbso::create_data_log_volumes() {

  ## if not a standby node
  if [[ ! "${VM_METADATA[sap_hana_original_role]}" = "standby" ]]; then
    main::errhandle_log_info 'Building /hana/data & /hana/log'

    if [[ "${VM_METADATA[use_single_data_log_disk]}" = "true" ]]; then
      ## create volume group
      main::create_vg $DEVICE_SINGLE_PD vg_hana

      ## create logical volumes
      main::errhandle_log_info '--- Creating logical volumes'
      lvcreate -L "${hana_log_size}"G -n log vg_hana
      lvcreate -l 100%FREE -n data vg_hana

      ## format file systems
      main::format_mount /hana/data /dev/vg_hana/data xfs tmp
      main::format_mount /hana/log /dev/vg_hana/log xfs tmp

      ## create sid folder inside of mounted file system
      mkdir -p /hana/data/"${VM_METADATA[sap_hana_sid]}" /hana/log/"${VM_METADATA[sap_hana_sid]}"

      ## Update permissions then unmount - mounts are now under the control of gceStorageClient
      main::errhandle_log_info '--- Unmounting and deactivating file systems'
      chown -R "${VM_METADATA[sap_hana_sidadm_uid]}":"${VM_METADATA[sap_hana_sapsys_gid]}" /hana/log /hana/data
      chmod -R 750 /hana/data /hana/log
      /usr/bin/sync
      /usr/bin/umount /hana/log
      /usr/bin/umount /hana/data

      ## disable volume group
      /sbin/vgchange -a n vg_hana
    else
      main::create_vg $DEVICE_DATA vg_hana_data
      lvcreate -l 100%FREE -n data vg_hana_data
      main::format_mount /hana/data /dev/vg_hana_data/data xfs tmp

      main::create_vg $DEVICE_LOG vg_hana_log
      lvcreate -l 100%FREE -n log vg_hana_log
      main::format_mount /hana/log /dev/vg_hana_log/log xfs tmp

      ## create sid folder inside of mounted file system
      mkdir -p /hana/data/"${VM_METADATA[sap_hana_sid]}" /hana/log/"${VM_METADATA[sap_hana_sid]}"

      ## Update permissions then unmount - mounts are now under the control of gceStorageClient
      main::errhandle_log_info '--- Unmounting and deactivating file systems'
      chown -R "${VM_METADATA[sap_hana_sidadm_uid]}":"${VM_METADATA[sap_hana_sapsys_gid]}" /hana/log /hana/data
      chmod -R 750 /hana/data /hana/log
      /usr/bin/sync
      /usr/bin/umount /hana/log
      /usr/bin/umount /hana/data

      ## disable volume group
      /sbin/vgchange -a n vg_hana_data
      /sbin/vgchange -a n vg_hana_log
    fi
  fi

  ## create base SID directory to avoid hdblcm failing on worker/standby nodes
  mkdir -p /hana/data/"${VM_METADATA[sap_hana_sid]}" /hana/log/"${VM_METADATA[sap_hana_sid]}"

  ## add 2GB swap file as per Note 1999997, point 21. Non-critical, warning on failure
  main::errhandle_log_info "Attempting to add swap space"
  if (( $(free -k | grep -i swap | awk '{print $2}') > 2097152 )); then
    main::errhandle_log_warning "Swap space larger than recommended 2GiB. Please review."
  elif (( $(free -k | grep -i swap | awk '{print $2}') > 0 )); then
    main::errhandle_log_info "Non-zero swap already exists. Skipping."
  else
    if dd if=/dev/zero of=/swapfile bs=1048576 count=2048; then
      chmod 0600 /swapfile
      mkswap /swapfile
      echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
      systemctl daemon-reload
      swapon /swapfile
    fi
    if (( $(free -k | grep -i swap | awk '{print $2}') > 0 )); then
      main::errhandle_log_info "Swap space added."
    else
      main::errhandle_log_warning "Swap space not added. Post-processing needed."
    fi
  fi
}


hdbso::mount_nfs_vols() {
  local scenario="${1}"

  if [[ "${scenario}" == "nonha" ]]; then
    if [[ -z ${VM_METADATA[sap_hana_shared_nfs]} ]]; then
      main::errhandle_log_info "No NFS endpoint specified for /hana/shared"
      return 0
    fi
    if [[ -z ${VM_METADATA[sap_hana_backup_nfs]} ]]; then
      main::errhandle_log_info "No NFS endpoint specified for /hanabackup"
      return 0
    fi
    if [[ ${VM_METADATA[sap_hana_scaleout_nodes]} -lt 1 ]]; then
      main::errhandle_log_warning "No scale-out nodes specified"
    fi
  fi

  main::errhandle_log_info "Mounting NFS volumes /hana/shared & /hanabackup"

  local nfs_version
  nfs_version=$(timeout -k 10 2 rpcinfo "${VM_METADATA[sap_hana_shared_nfs]%:*}" | grep -w nfs | awk '{ print $2 }' | sort -r | head -1)

  main::errhandle_log_info "--- Creating automount for /hana/shared to ${VM_METADATA[sap_hana_shared_nfs]}"
  main::errhandle_log_info "--- Creating automount for /hanabackup to ${VM_METADATA[sap_hana_backup_nfs]}"

  echo "/- /etc/auto.hana" >> /etc/auto.master

  if [[ "${nfs_version}" = "3" ]]; then
    echo "/hana/shared -rsize=1048576,wsize=1048576,hard,intr,timeo=18,retrans=200 ${VM_METADATA[sap_hana_shared_nfs]}" > /etc/auto.hana
    echo "/hanabackup -rsize=1048576,wsize=1048576,hard,intr,timeo=18,retrans=200 ${VM_METADATA[sap_hana_backup_nfs]}" >> /etc/auto.hana
  else
    ## Default to version 4 - as rpcinfo can timeout if UDP ports are not open
    echo "/hana/shared -fstype=nfs4 -rsize=1048576,wsize=1048576,hard,intr,timeo=18,retrans=200 ${VM_METADATA[sap_hana_shared_nfs]}" > /etc/auto.hana
    echo "/hanabackup -fstype=nfs4 -rsize=1048576,wsize=1048576,hard,intr,timeo=18,retrans=200 ${VM_METADATA[sap_hana_backup_nfs]}" >> /etc/auto.hana
  fi

  ## Enable autofs and start on boot
  systemctl enable autofs
  /sbin/service autofs restart

  ## list directories to force mount
  ls /hana/shared
  ls /hanabackup

  ## check mounts have worked
  main::check_mount /hana/shared
  main::check_mount /hanabackup warning

  ## set permissions correctly. Workaround for some NFS servers
  chmod 775 /hana/shared

  ## Check for existing sid in shared
  if [[ -d "/hana/shared/${VM_METADATA[sap_hana_sid]}" ]]; then
    # no need to add an exit - the errhandle_log_error stops the installation
    main::errhandle_log_error "HANA SID exists in shared volume: /hana/shared/${VM_METADATA[sap_hana_sid]}, cannot continue with installation"
  fi

  ## Check for existing data in /hana/shared
  if [[ "$(ls -A /hana/shared)" ]]; then
    # we just log an warning, this can be okay
    main::errhandle_log_warning "HANA Shared volume (/hana/shared) is not empty"
  fi
}


hdbso::gcestorageclient_install() {
  ## install python module requirements for gceStorageClient
  pip install --upgrade pyasn1-modules

  main::errhandle_log_info "Installing gceStorageClient"
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    zypper addrepo --gpgcheck-allow-unsigned-package --refresh https://packages.cloud.google.com/yum/repos/google-sapgcestorageclient-sles$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"' | cut -f1 -d.)-\$basearch google-sapgcestorageclient
    zypper --no-gpg-checks install -y google-sapgcestorageclient
  else
    # RHEL
    RHEL_VERSION=`rpm -q --queryformat '%{VERSION}' redhat-release-server | cut -f1 -d. | cut -c1-1`
    if [[ "${RHEL_VERSION}" == "p" ]]; then
      RHEL_VERSION=`rpm -q --queryformat '%{VERSION}' redhat-release | cut -f1 -d. | cut -c1-1`
    fi
    tee /etc/yum.repos.d/google-sapgcestorageclient.repo << EOM
[google-sapgcestorageclient]
name=Google SAP GCE Storage Client
baseurl=https://packages.cloud.google.com/yum/repos/google-sapgcestorageclient-el${RHEL_VERSION}-\$basearch
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
EOM
    # RHEL 8 does not like repo gpg check on when
    # installing from the startup script
    yum --nogpgcheck -y install google-sapgcestorageclient
  fi
  mkdir -p /hana/shared/gceStorageClient
  cp /usr/sap/google-sapgcestorageclient/gceStorageClient.py /hana/shared/gceStorageClient/
  if [[ ! -f /hana/shared/gceStorageClient/gceStorageClient.py ]]; then
    main::errhandle_log_error "Unable to install gceStorageClient"
  fi
}


hdbso::gcestorageclient_gcloud_config() {
  # Configuring gcloud to work under target SAP HANA sidadm account
  mkdir -p /usr/sap/"${VM_METADATA[sap_hana_sid]}"/home/.config/gcloud/
  chown -R "${VM_METADATA[sap_hana_sidadm_uid]}":"${VM_METADATA[sap_hana_sapsys_gid]}" /usr/sap/"${VM_METADATA[sap_hana_sid]}"/home/.config/gcloud/
}


hdbso::create_global_ini(){
  main::errhandle_log_info "Creating /hana/shared/gceStorageClient/global.ini"

  ## Add top section to global.ini
  cat <<EOF > /hana/shared/gceStorageClient/global.ini
[persistence]
basepath_datavolumes = /hana/data/${VM_METADATA[sap_hana_sid]}
basepath_logvolumes = /hana/log/${VM_METADATA[sap_hana_sid]}
use_mountpoints = yes
basepath_shared = yes

[storage]
ha_provider = gceStorageClient
ha_provider_path = /hana/shared/gceStorageClient
EOF

  ## Add each storage partition
  local partno
  local worker

  for worker in $(seq 1 $((VM_METADATA[sap_hana_worker_nodes]+1))); do
    partno="0000${worker}"
    partno_concat="${partno: -5}"
    if [[ "${VM_METADATA[use_single_data_log_disk]}" = "true" ]]; then
      echo "partition_${worker}_*__pd = ${HOSTNAME}-hana${partno_concat}" >> /hana/shared/gceStorageClient/global.ini
    else
      echo "partition_${worker}_data__pd = ${HOSTNAME}-data${partno_concat}" >> /hana/shared/gceStorageClient/global.ini
      echo "partition_${worker}_log__pd = ${HOSTNAME}-log${partno_concat}" >> /hana/shared/gceStorageClient/global.ini
    fi
  done

  ## Add bottom section to global.ini
  if [[ "${VM_METADATA[use_single_data_log_disk]}" = "true" ]]; then
    cat <<EOF >> /hana/shared/gceStorageClient/global.ini
partition_*_data__dev = /dev/vg_hana/data
partition_*_log__dev = /dev/vg_hana/log
partition_*_data__mountOptions = -t xfs -o logbsize=256k
partition_*_log__mountOptions = -t xfs -o logbsize=256k
partition_*_*__fencing = disabled

[trace]
ha_gcestorageclient = info
EOF
  else
    cat <<EOF >> /hana/shared/gceStorageClient/global.ini
partition_*_data__dev = /dev/vg_hana_data/data
partition_*_log__dev = /dev/vg_hana_log/log
partition_*_data__mountOptions = -t xfs -o logbsize=256k
partition_*_log__mountOptions = -t xfs -o logbsize=256k
partition_*_*__fencing = disabled

[trace]
ha_gcestorageclient = info
EOF
  fi
}


hdbso::update_sudoers() {
  main::errhandle_log_info "Updating /etc/sudoers"
  echo "${VM_METADATA[sap_hana_sid],,}adm ALL=NOPASSWD: /sbin/multipath,/sbin/multipathd,/etc/init.d/multipathd,/usr/bin/sg_persist,/bin/mount,/bin/umount,/bin/kill,/usr/bin/lsof,/usr/bin/systemctl,/usr/sbin/lsof,/usr/sbin/xfs_repair,/sbin/xfs_repair,/usr/bin/mkdir,/sbin/vgscan,/sbin/pvscan,/sbin/lvscan,/sbin/vgchange,/sbin/lvdisplay,/usr/bin/gcloud,/sbin/dmsetup" >>/etc/sudoers
  echo "" >> /etc/sudoers
}


hdbso::install_scaleout_nodes() {
  local worker

  main::errhandle_log_info "Preparing to install additional SAP HANA nodes"
  cd /hana/shared/"${VM_METADATA[sap_hana_sid]}"/hdblcm || main::errhandle_log_error "Unable to access HANA Lifecycle Manager. Additional HANA nodes will not be installed"

  ## Install Worker Nodes
  if [[ ! "${VM_METADATA[sap_hana_worker_nodes]}" = "0" ]]; then
    main::errhandle_log_info "Installing ${VM_METADATA[sap_hana_worker_nodes]} worker nodes"
    ## ssh into each worker node and start SAP HANA
    for worker in $(seq 1 "${VM_METADATA[sap_hana_worker_nodes]}"); do
      main::errhandle_log_info "--- ${HOSTNAME}w${worker}"
      main::exchange_sshpubkey_with "${HOSTNAME}w${worker}" "${CLOUDSDK_COMPUTE_ZONE}"
      echo $(hdb::build_pw_xml) | ./hdblcm --action=add_hosts --addhosts="${HOSTNAME}"w"${worker}" --root_user=root --listen_interface=global --read_password_from_stdin=xml -b
    done
  fi

  if [[ ! ${VM_METADATA[sap_hana_standby_nodes]} = "0" ]]; then
    main::errhandle_log_info "Installing ${VM_METADATA[sap_hana_standby_nodes]} standby nodes"
    for worker in $(seq $((VM_METADATA[sap_hana_worker_nodes]+1)) "${VM_METADATA[sap_hana_scaleout_nodes]}"); do
      main::errhandle_log_info "--- ${HOSTNAME}w${worker}"
      main::exchange_sshpubkey_with "${HOSTNAME}w${worker}" "${CLOUDSDK_COMPUTE_ZONE}"
      echo $(hdb::build_pw_xml) | ./hdblcm --action=add_hosts --addhosts="${HOSTNAME}"w"${worker}":role=standby --root_user=root --listen_interface=global --read_password_from_stdin=xml -b
    done
  fi

  # Ensure HANA is set to autostart
  sed -i -e 's/Autostart=0/Autostart=1/g' /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/profile/*

  ## restart SAP HANA
  hdbso::restart

  ## configure masters
  main::errhandle_log_info "Updating SAP HANA configured roles"
  echo "call SYS.UPDATE_LANDSCAPE_CONFIGURATION('deploy','{\"HOSTS\":{\"${HOSTNAME}w1\":{\"WORKER_CONFIG_GROUPS\":\"default\",\"FAILOVER_CONFIG_GROUP\":\"default\",\"INDEXSERVER_CONFIG_ROLE\":\"WORKER\",\"NAMESERVER_CONFIG_ROLE\":\"MASTER 2\"},\"${HOSTNAME}w$((VM_METADATA[sap_hana_worker_nodes]+1))\":{\"WORKER_CONFIG_GROUPS\":\"default\",\"FAILOVER_CONFIG_GROUP\":\"default\",\"INDEXSERVER_CONFIG_ROLE\":\"STANDBY\",\"NAMESERVER_CONFIG_ROLE\":\"MASTER 3\"}}}')" > /root/.deploy/hdbconfig.sql
  bash -c "source /usr/sap/*/home/.sapenv.sh && hdbsql -d SYSTEMDB -u SYSTEM -p '"${VM_METADATA[sap_hana_system_password]}"' -i ${VM_METADATA[sap_hana_instance_number]} -I /root/.deploy/hdbconfig.sql -O /dev/null"
  bash -c "source /usr/sap/*/home/.sapenv.sh && hdbsql -u SYSTEM -p '"${VM_METADATA[sap_hana_system_password]}"' -i ${VM_METADATA[sap_hana_instance_number]} -I /root/.deploy/hdbconfig.sql -O /dev/null"

  ## enable fencing
  hdb::set_parameters global.ini storage partition_*_*__fencing enabled
}

hdbso::restart() {
  main::errhandle_log_info "Restarting SAP HANA"
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function StopSystem HDB
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function WaitforStopped 400 2 HDB

  # reset basepath_shared = no (b/179021501)
  sed -i -e 's/basepath_shared = yes/basepath_shared = no/g' /hana/shared/gceStorageClient/global.ini

  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function StartSystem HDB
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function WaitforStarted 400 2 HDB
}
#!/bin/bash

# send_metrics should generally be called from a sub-shell. It should never exit the main process.
metrics::send_metric() {(  #Exits will only exit the sub-shell.
    local SKIP_LOG_DENY_LIST=("510599941441" "1038306394601" "714149369409" "161716815775" "607888266690" "863817768072" "450711760461" "600915385160" "114837167255" "39979408140" "155261204042" "922508251869" "208472317671" "824757391322" "977154783768" "148036532291" "425380551487" "811811474621" "975534532604" "475132212764" "201338458013" "269972924358" "400774613146" "977154783768" "425380551487" "783555621715" "182593831895" "1042063780714" "1001412328766" "148036532291" "135217527788" "444363138560" "116074023633" "545763614633" "528626677366" "871521991065" "271532348354" "706203752296" "742377328177" "756002114100" "599169460194" "880648352583" "973107100758" "783641913733" "355955620782" "653441306135" "703965468432" "381292615623", "605897091243")

    local NUMERIC_VM_PROJECT=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/project/numeric-project-id")
    local VM_IMAGE_FULL=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/image")
    local VM_ZONE=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/zone" | cut -d / -f 4 )
    local VM_NAME=$(main::get_metadata "http://169.254.169.254/computeMetadata/v1/instance/name")
    local METADATA_URL="https://compute.googleapis.com/compute/v1/projects/${VM_PROJECT}/zones/${VM_ZONE}/instances/${VM_NAME}"

    while getopts 's:n:v:e:u:c:p:' argv; do
        case "${argv}" in
        s) status="${OPTARG}";;
        e) error_id="${OPTARG}";;
        u) updated_version="${OPTARG}";;
        c) action_id="${OPTARG}";;
        esac
    done

    if [[ -z "${VM_METADATA[template-type]}" ]]; then
        VM_METADATA[template-type]="UNKNOWN"
    fi
    if [[ -z "${TEMPLATE_NAME}" ]]; then
        TEMPLATE_NAME="UNSET"
    fi

    metrics::validate "${status}" "Missing required status (-s) argument."
    # We don't want to log our own test runs:
    if [[ " ${SKIP_LOG_DENY_LIST[*]} " == *" ${NUMERIC_VM_PROJECT} "* ]]; then
        echo "Not logging metrics this is an internal project."
        exit 0
    fi
    if [[ $VM_IMAGE_FULL =~ ^projects/(centos-cloud|cos-cloud|debian-cloud|fedora-coreos-cloud|rhel-cloud|rhel-sap-cloud|suse-cloud|suse-sap-cloud|ubuntu-os-cloud|ubuntu-os-pro-cloud|windows-cloud|windows-sql-cloud)/global/images/.+$ ]]; then
        VM_IMAGE=$(echo "${VM_IMAGE_FULL}" | cut -d / -f 5)
    else
        VM_IMAGE="unknown"
    fi

    # If IDs are not numeric, we blank them out
    digit_re='^[0-9]+$'
    if ! [[ $error_id =~ $digit_re ]] ; then
        error_id=0
    fi
    if ! [[ $action_id =~ $digit_re ]] ; then
        action_id=0
    fi

    local template_id="${VM_METADATA[template-type]}-${TEMPLATE_NAME}"
    case $status in
    RUNNING|STARTED|STOPPED|CONFIGURED|MISCONFIGURED|INSTALLED|UNINSTALLED)
        user_agent="sap-core-eng/accelerator-template/2.0.202402230649/${VM_IMAGE}/${status}"
        ;;
    ERROR)
        metrics::validate "${error_id}" "'ERROR' statuses require the error message (-e) argument."
        user_agent="sap-core-eng/accelerator-template/2.0.202402230649/${VM_IMAGE}/${status}/${error_id}-${template_id}"
        ;;
    UPDATED)
        metrics::validate "${updated_version}" "'UPDATED' statuses require the updated version (-u) argument."
        user_agent="sap-core-eng/accelerator-template/2.0.202402230649/${VM_IMAGE}/${status}/${updated_version}"
        ;;
    ACTION)
        metrics::validate "${action_id}" "'ACTION' statuses require the action id (-c) argument."
        user_agent="sap-core-eng/accelerator-template/2.0.202402230649/${VM_IMAGE}/${status}/${action_id}"
        ;;
    TEMPLATEID)
        user_agent="sap-core-eng/accelerator-template/2.0.202402230649/${VM_IMAGE}/ACTION/${template_id}"
        ;;
    *)
        echo "Error, valid status must be provided."
        exit 0
    esac

    local curlToken=$(metrics::get_token)
    curl --fail -H "Authorization: Bearer ${curlToken}" -A "${user_agent}" "${METADATA_URL}"
)}


metrics::validate () {
    variable="$1"
    validate_message="$2"
    if [[ -z "${variable}" ]]; then
        echo "${validate_message}"
        exit 0
    fi
}

metrics::get_token() {
    if command -v jq>/dev/null; then
        TOKEN=$(curl --fail -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r '.access_token')
    elif command -v python>/dev/null; then
        TOKEN=$(curl --fail -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | python -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
    elif command -v python3>/dev/null; then
        TOKEN=$(curl --fail -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | python3 -c "import sys, json; print(json.load(sys.stdin)['access_token'])")
    else
        echo "Failed to retrieve token, metrics logging requires either Python, Python3, or jq."
        exit 0
    fi
    echo "${TOKEN}"
}

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

## Prepare for SAP HANA
hdb::check_settings
hdb::set_kernel_parameters
hdbso::mount_nfs_vols
hdbso::calculate_volume_sizes
hdbso::create_data_log_volumes
hdbso::gcestorageclient_install
hdbso::gcestorageclient_gcloud_config

## Install monitoring agent
main::install_monitoring_agent

## Install SAP HANA
hdb::create_install_cfg
hdbso::create_global_ini
hdbso::update_sudoers
hdb::download_media
hdb::extract_media
hdb::install
hdb::upgrade
hdb::config_backup
hdb::config_hyperdisk_parameters
hdbso::install_scaleout_nodes

## Post deployment & installation cleanup
main::complete
