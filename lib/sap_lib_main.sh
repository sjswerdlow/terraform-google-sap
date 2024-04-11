
set +e

main::set_boot_parameters() {

  main::errhandle_log_info 'Checking boot parameters'

  ## disable selinux
  if [[ -e /etc/sysconfig/selinux ]]; then
    main::errhandle_log_info "--- Disabling SELinux"
    sed -ie 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
  fi

  if [[ -e /etc/selinux/config ]]; then
    main::errhandle_log_info "--- Disabling SELinux"
    sed -ie 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
  fi
  ## work around for LVM boot where LVM volumes are not started on certain SLES/RHEL versions
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

main::wait_for_mount() {
  local mount_name=${1}
  local only_warn=${2}

  local failed_to_mount="false"

  local count=0
  while ! grep -q "${mount_name}" /etc/mtab ; do
    count=$((count +1))
    main::errhandle_log_info "--- ${mount_name} is not mounted. Waiting 10 seconds and trying again. [Attempt ${count}/100]"
    sleep 10s
    mount -a
    if [ ${count} -gt 100 ] && [ -z ${only_warn} ]; then
      main::errhandle_log_error "${mount_name} is not mounted - Unable to continue"
    elif [ ${count} -gt 100 ]; then
      failed_to_mount="true"
      break
    fi
  done

  if [[ "${failed_to_mount}" == "true" ]]; then
    main::errhandle_log_warning "--- ${mount_name} failed to mount."
  else
    main::errhandle_log_info "--- ${mount_name} successfully mounted."
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
     main::errhandle_log_error "Unable to retrieve zone as host was not supplied."
  fi

  # Retrieve host zone, retrying if the API call fails
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
