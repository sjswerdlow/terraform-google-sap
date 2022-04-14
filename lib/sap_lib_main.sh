
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

  # Send metrics
  metrics::send_metric -s "ERROR"  -e "1"

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
}


main::install_ssh_key(){
  local host=${1}
  local host_zone

  host_zone=$(${GCLOUD} compute instances list --filter="name=('${host}')" --format "value(zone)")
  main::errhandle_log_info "Installing ${HOSTNAME} SSH key on ${host}"

  local count=0
  local max_count=10

  while ! ${GCLOUD} --quiet compute instances add-metadata "${host}" --metadata "ssh-keys=root:$(cat ~/.ssh/id_rsa.pub)" --zone "${host_zone}"; do
    count=$((count +1))
    if [ ${count} -gt ${max_count} ]; then
      main::errhandle_log_error "Failed to install ${HOSTNAME} SSH key on ${host}, aborting installation."
    else
      main::errhandle_log_info "Failed to install ${HOSTNAME} SSH key on ${host}, trying again in 5 seconds."
      sleep 5s
    fi
  done
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
      errhandle_log_info "--- zypper is still running. Waiting 10 seconds before continuing"
      sleep 10s
    done
  fi

  ## packages to install
  local sles_packages="libssh2-1 libopenssl0_9_8 libopenssl1_0_0 joe tuned krb5-32bit unrar SAPHanaSR SAPHanaSR-doc pacemaker numactl csh python-pip python-pyasn1-modules ndctl python-oauth2client python-oauth2client-gce python-httplib2 python3-httplib2 python3-google-api-python-client python-requests python-google-api-python-client libgcc_s1 libstdc++6 libatomic1 sapconf saptune"
  local rhel_packages="unar.x86_64 tuned-profiles-sap-hana tuned-profiles-sap-hana-2.7.1-3.el7_3.3 joe resource-agents-sap-hana.x86_64 compat-sap-c++-6 numactl-libs.x86_64 libtool-ltdl.x86_64 nfs-utils.x86_64 pacemaker pcs lvm2.x86_64 compat-sap-c++-5.x86_64 csh autofs ndctl compat-sap-c++-9 compat-sap-c++-10 libatomic unzip libsss_autofs python2-pip langpacks-en langpacks-de glibc-all-langpacks libnsl libssh2 wget lsof jq"

  ## install packages
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    for package in ${sles_packages}; do # Bash only splits unquoted.
        local count=0;
        local max_count=3;
        while ! sudo ZYPP_LOCK_TIMEOUT=60 zypper in -y "${package}"; do
          count=$((count +1))
          sleep 3
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
        local max_count=10;
        while ! yum -y install "${package}"; do
          count=$((count +1))
          sleep 5
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
      main::errhandle_log_error 'Applying updates to packages on system failed ("yum update -y"). Logon to the VM to investigate the issue.'
    fi
  fi
  main::errhandle_log_info 'Install of required operating system packages complete'
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
    main::errhandle_log_warn "Unable to create optional file system ${filesystem}."
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
        main::errhandle_log_warn "Unable to mount ${mount_point}"
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


    if [[ ${uses_secret_password} == "true" ]] && [[ "${key}" = *"password"* ]]; then
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
    main::errhandle_log_info "Startup script has previously been run. Aborting execution."
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
    # b/188946979
    if [[ "${LINUX_DISTRO}" = "SLES" && "${LINUX_MAJOR_VERSION}" = "12" ]]; then
      export CLOUDSDK_PYTHON=/usr/bin/python
    fi
    bash <(curl -s https://dl.google.com/dl/cloudsdk/channels/rapid/install_google_cloud_sdk.bash) --disable-prompts --install-dir="${install_location}" >/dev/null
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

  ## set default python version for Cloud SDK in SLES, move from 3.4 to 2.7
  # b/188946979 - only applicable to SLES12
  if [[ ${LINUX_DISTRO} = "SLES" && "${LINUX_MAJOR_VERSION}" = "12" ]]; then
    update-alternatives --install /usr/bin/gsutil gsutil /usr/local/google-cloud-sdk/bin/gsutil 1 --force
    update-alternatives --install /usr/bin/gcloud gcloud /usr/local/google-cloud-sdk/bin/gcloud 1 --force
    export CLOUDSDK_PYTHON=/usr/bin/python
    # b/189944327 - to avoid gcloud/gsutil fails when using Python3.4 on SLES12
    if ! grep -q CLOUDSDK_PYTHON /etc/profile; then
      echo "export CLOUDSDK_PYTHON=/usr/bin/python" | tee -a /etc/profile
    fi
    if ! grep -q CLOUDSDK_PYTHON /etc/environment; then
      echo "export CLOUDSDK_PYTHON=/usr/bin/python" | tee -a /etc/environment
    fi
  fi

  ## run an instances list to ensure the software is up to date
  ${GCLOUD} --quiet beta compute instances list >/dev/null
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


main::get_metadata() {
  local key=${1}

  local value

  if [[ ${key} = *"169.254.169.254/computeMetadata"* ]]; then
      value=$(curl --fail -sH'Metadata-Flavor: Google' "${key}")
  else
    value=$(curl --fail -sH'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/attributes/"${key}")
  fi
  echo "${value}"
}


main::complete() {
  local on_error=${1}

  if [[ -z "${on_error}" ]]; then
    main::errhandle_log_info "INSTANCE DEPLOYMENT COMPLETE"

    local count=0
    local max_count=10

    while ! ${GCLOUD} --quiet compute instances add-metadata "${HOSTNAME}" --metadata "status=completed" --zone "${CLOUDSDK_COMPUTE_ZONE}"; do
      count=$((count +1))
      if [ ${count} -gt ${max_count} ]; then
        main::errhandle_log_info "Failed to update script complete status, continuing."
        continue
      else
        main::errhandle_log_info "Failed to update script complete status, trying again in 5 seconds."
        sleep 5s
      fi
    done
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

  if [[ -z "${deployment_warnings}" ]]; then
    main::errhandle_log_info "--- Finished"
  else
    main::errhandle_log_warning "--- Finished (${deployment_warnings} warnings)"
  fi

  ## exit sending right error code
  if [[ -z "${on_error}" ]]; then
      exit 0
    else
    exit 1
  fi
}

main::send_start_metrics() {
  metrics::send_metric -s "STARTED"
  metrics::send_metric -s "TEMPLATEID"
}

main::install_ops_agent() {
  if [[ ! "${VM_METADATA[install_cloud_ops_agent]}" == "false" ]]; then
    main::errhandle_log_info "Installing Google Ops Agent"
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    sudo bash add-google-cloud-ops-agent-repo.sh --also-install
  fi
}

main::install_monitoring_agent() {
  if [[ ! "${VM_METADATA[install_monitoring_agent]}" == "false" ]]; then
    if grep -q "/usr/sap" /etc/mtab; then
      main::errhandle_log_info "Installing SAP NetWeaver monitoring agent"
      if [ "${LINUX_DISTRO}" = "SLES" ]; then
        main::errhandle_log_info "Installing agent for SLES"
        # SLES
        zypper addrepo --gpgcheck-allow-unsigned-package --refresh https://packages.cloud.google.com/yum/repos/google-sapnetweavermonitoring-agent-sles$(grep "VERSION_ID=" /etc/os-release | cut -d = -f 2 | tr -d '"' | cut -d . -f 1)-\$basearch google-sapnetweavermonitoring-agent
        rpm --import https://packages.cloud.google.com/yum/doc/yum-key.gpg
        zypper --no-gpg-checks --gpg-auto-import-keys ref -f
        if timeout 300 zypper -n --no-gpg-checks install "google-sapnetweavermonitoring-agent"; then
          main::errhandle_log_info "Finished installation SAP NetWeaver monitoring agent"
        else
          local MSG1="SAP NetWeaver monitoring agent did not install correctly."
          local MSG2="Try to install it manually."
          main::errhandle_log_info "${MSG1} ${MSG2}"
        fi
      elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
        # RHEL
        main::errhandle_log_info "Installing agent for RHEL"
        tee /etc/yum.repos.d/google-sapnetweavermonitoring-agent.repo << EOM
[google-sapnetweavermonitoring-agent]
name=Google SAP Netweaver Monitoring Agent
baseurl=https://packages.cloud.google.com/yum/repos/google-sapnetweavermonitoring-agent-el$(cat /etc/redhat-release | cut -d . -f 1 | tr -d -c 0-9)-\$basearch
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
      https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOM
        if timeout 300 yum install -y "google-sapnetweavermonitoring-agent"; then
          main::errhandle_log_info "Finished installation SAP NetWeaver monitoring agent"
        else
          local MSG1="SAP NetWeaver monitoring agent did not install correctly."
          local MSG2="Try to install it manually."
          main::errhandle_log_info "${MSG1} ${MSG2}"
        fi
      fi
      set +e
    else
      main::errhandle_log_warning "/usr/sap not mounted, aborting agent install."
    fi
  fi
}
