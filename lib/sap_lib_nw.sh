
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
          local MSG1="SAP NetWeaver monitoring agent did not install correctly."
          local MSG2="Try to install it manually."
          main::errhandle_log_info "${MSG1} ${MSG2}"
        else
          main::errhandle_log_info "Finished installation SAP NetWeaver monitoring agent"
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
          local MSG1="SAP NetWeaver monitoring agent did not install correctly."
          local MSG2="Try to install it manually."
          main::errhandle_log_info "${MSG1} ${MSG2}"
        else
          main::errhandle_log_info "Finished installation SAP NetWeaver monitoring agent"
        fi
      fi
      set +e
    else
      main::errhandle_log_warning "/usr/sap not mounted, aborting agent install."
    fi
  fi
}


nw-ha::fail_for_rhel() {
  if [ "${LINUX_DISTRO}" = "RHEL" ]; then
    main::errhandle_log_error "Installation on RHEL is not yet supported. Exiting."
  fi
}

nw-ha::create_deploy_directory() {
  if [[ ! -d /root/.deploy ]]; then
    mkdir -p /root/.deploy
  fi
}

nw-ha::enable_ilb_backend_communication() {
  local rc
  local local_startup_script

  main::errhandle_log_info "Enabling load balancer back-end communication between the VMs."

  local_startup_script="startup_script.sh"
  cat << EOF > ${local_startup_script}
#! /bin/bash
# VM startup script

nic0_mac="\$(curl --silent -H "Metadata-Flavor:Google" \
--connect-timeout 5 --retry 5 --retry-max-time 60 \
http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/mac)"

nic0_ip="\$(curl --silent -H "Metadata-Flavor:Google" \
--connect-timeout 5 --retry 5 --retry-max-time 60 \
http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip)"

for nic in \$(ls /sys/class/net); do
  nic_addr=\$(cat /sys/class/net/"\${nic}"/address)
  if [ "\$nic_addr" == "\$nic0_mac" ]; then
    nic0_name="\$nic"
    break
  fi
done

[[ -n \$nic0_name ]] && [[ -n \$nic0_ip ]] \
&& logger -i "gce-startup-script: INFO adding IP configuration for ILB client" \
|| logger -i "gce-startup-script: ERROR could not determine IP or interface name"

if [ -n "\$nic0_name" ]; then
  ip rule del from all lookup local
  ip rule add pref 0 from all iif "\${nic0_name}" lookup local
  ip route add local "\${nic0_ip}" dev "\${nic0_name}" proto kernel \
    scope host src "\${nic0_ip}" table main
  ip route add local 127.0.0.0/8 dev lo proto kernel \
    scope host src 127.0.0.1 table main
  ip route add local 127.0.0.1 dev lo proto kernel \
    scope host src 127.0.0.1 table main
  ip route add broadcast 127.0.0.0 dev lo proto kernel \
    scope link src 127.0.0.1 table main
  ip route add broadcast 127.255.255.255 dev lo proto kernel \
    scope link src 127.0.0.1 table main
fi
EOF

  main::errhandle_log_info "Enabling local routing."
  echo "net.ipv4.conf.eth0.accept_local=1" >> /etc/sysctl.conf
  sysctl -p

  main::errhandle_log_info "Setting startup script with IP settings."
  ${GCLOUD} --quiet compute instances add-metadata "${HOSTNAME}" \
            --metadata-from-file=startup-script="${local_startup_script}"
  rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    main::errhandle_log_info "Startup script successfully set. Applying IP settings to running instance."
    chmod +x "${local_startup_script}"
    ./"${local_startup_script}"
    main::errhandle_log_info "IP settings applied to running instance."
  else
    main::errhandle_log_error "Error setting startup script. Aborting installation."
  fi
}


nw-ha::create_nfs_directories() {
  local rc
  local dir
  local directories

  directories="
    /mnt/nfs/sapmnt${VM_METADATA[sap_sid]}
    /mnt/nfs/usrsaptrans
    /mnt/nfs/usrsap${VM_METADATA[sap_sid]}SYS
    /mnt/nfs/usrsap${VM_METADATA[sap_sid]}${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}
    /mnt/nfs/usrsap${VM_METADATA[sap_sid]}"ERS"${VM_METADATA[sap_ers_instance_number]}"

  main::errhandle_log_info "Creating shared NFS directories at '${VM_METADATA[nfs_path]}'."
  mkdir /mnt/nfs
  mount -t nfs "${VM_METADATA[nfs_path]}" /mnt/nfs
  rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    main::errhandle_log_error "Error mounting '${VM_METADATA[nfs_path]}'. Exiting."
  fi

  for dir in ${directories}; do
    if [[ ! -d ${dir} ]]; then
      mkdir "${dir}"
      rc=$?
      if [[ "${rc}" -ne 0 ]]; then
        main::errhandle_log_error "Cannot create directory in '${dir}'. Check permissions or if directory already exists. Exiting."
      else
        main::errhandle_log_info "Directory /mnt/nfs/sapmnt"${dir}" created."
      fi
    else
      main::errhandle_log_warning "Directory /mnt/nfs/sapmnt"${dir}" already existed."
    fi
  done

  umount /mnt/nfs
  rm -rf /mnt/nfs
  main::errhandle_log_info "Shared directories created."
}


nw-ha::configure_shared_file_system() {
  local nfs_opts
  nfs_opts="-rw,relatime,vers=3,hard,proto=tcp,timeo=600,retrans=2,mountvers=3,mountport=2050,mountproto=tcp"

  main::errhandle_log_info "Configuring shared file system."
  mkdir -p /sapmnt/"${VM_METADATA[sap_sid]}"
  mkdir -p /usr/sap/trans
  mkdir -p /usr/sap/"${VM_METADATA[sap_sid]}"/SYS
  mkdir -p /usr/sap/"${VM_METADATA[sap_sid]}"/"${VM_METADATA[sap_ascs]}"SCS"${VM_METADATA[sap_scs_instance_number]}"
  mkdir -p /usr/sap/"${VM_METADATA[sap_sid]}"/ERS"${VM_METADATA[sap_ers_instance_number]}"

  echo "/- /etc/auto.sap" | tee -a /etc/auto.master
  echo "/sapmnt/${VM_METADATA[sap_sid]} $nfs_opts ${VM_METADATA[nfs_path]}/sapmnt${VM_METADATA[sap_sid]}" | tee -a /etc/auto.sap
  echo "/usr/sap/trans $nfs_opts ${VM_METADATA[nfs_path]}/usrsaptrans" | tee -a /etc/auto.sap
  echo "/usr/sap/${VM_METADATA[sap_sid]}/SYS $nfs_opts ${VM_METADATA[nfs_path]}/usrsap${VM_METADATA[sap_sid]}SYS" | tee -a /etc/auto.sap

  systemctl enable autofs
  systemctl restart autofs
  automount -v

  cd /sapmnt/${VM_METADATA[sap_sid]}
  cd /usr/sap/trans
  cd /usr/sap/${VM_METADATA[sap_sid]}/SYS
  main::errhandle_log_info "Shared file system configured."
}


nw-ha::update_etc_hosts() {
  local primary_node_ip
  local secondary_node_ip

  main::errhandle_log_info "Updating /etc/hosts."

  primary_node_ip=$(ping "${VM_METADATA[sap_primary_instance]}" -c 1 | head -1 | awk  '{ print $3 }' | sed 's/(//' | sed 's/)//')
  secondary_node_ip=$(ping "${VM_METADATA[sap_secondary_instance]}" -c 1 | head -1 | awk  '{ print $3 }' | sed 's/(//' | sed 's/)//')

  echo "$primary_node_ip ${VM_METADATA[sap_primary_instance]}.$(hostname -d) ${VM_METADATA[sap_primary_instance]}" | tee -a /etc/hosts
  echo "$secondary_node_ip ${VM_METADATA[sap_secondary_instance]}.$(hostname -d) ${VM_METADATA[sap_secondary_instance]}" | tee -a /etc/hosts
  echo "${VM_METADATA[scs_vip_address]} ${VM_METADATA[scs_vip_name]}.$(hostname -d) ${VM_METADATA[scs_vip_name]}" | tee -a /etc/hosts
  echo "${VM_METADATA[ers_vip_address]} ${VM_METADATA[ers_vip_name]}.$(hostname -d) ${VM_METADATA[ers_vip_name]}" | tee -a /etc/hosts

  main::errhandle_log_info "/etc/hosts updated."
}


nw-ha::install_ha_packages() {
  main::errhandle_log_info "Installing HA packages."
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    zypper install -t pattern ha_sles
    zypper install -y sap-suse-cluster-connector
    zypper install -y socat
  fi
  main::errhandle_log_info "HA packages installed."
}


nw-ha::pacemaker_create_cluster_primary() {
  main::errhandle_log_info "Creating cluster on primary node."

  main::errhandle_log_info "Initializing cluster."
  ha-cluster-init --name "${VM_METADATA[pacemaker_cluster_name]}" --yes --interface eth0 csync2
  ha-cluster-init --name "${VM_METADATA[pacemaker_cluster_name]}" --yes --interface eth0 corosync
  main::errhandle_log_info "Configuring Corosync per Google recommendations."
  sed -i 's/token:.*/token: 20000/g' /etc/corosync/corosync.conf
  sed -i '/consensus:/d' /etc/corosync/corosync.conf
  sed -i 's/join:.*/join: 60/g' /etc/corosync/corosync.conf
  sed -i 's/max_messages:.*/max_messages: 20/g' /etc/corosync/corosync.conf
  sed -i 's/token_retransmits_before_loss_const:.*/token_retransmits_before_loss_const: 10/g' /etc/corosync/corosync.conf
  main::errhandle_log_info "Starting cluster."
  ha-cluster-init --name ${VM_METADATA[pacemaker_cluster_name]} --yes cluster

  main::errhandle_log_info "Setting general cluster properties."
  crm configure property stonith-timeout="300s"
  crm configure property stonith-enabled="true"
  crm configure rsc_defaults resource-stickiness="1"
  crm configure rsc_defaults migration-threshold="3"
  crm configure op_defaults timeout="600"

  main::errhandle_log_info "Enable and start Pacemaker."
  systemctl enable pacemaker
  systemctl start pacemaker

  echo "ready" > /root/.deploy/."${HOSTNAME}".ready

  main::errhandle_log_info "Cluster on primary node created."
}


nw-ha::pacemaker_join_secondary() {
  main::errhandle_log_info "Joining secondary VM to the cluster."

  # Workaround of wrapping 'ha-cluster-join' into ssh calls to own host:
  # Without it, 'ha-cluster-join' commands block commands/functions
  # executed after this function (caused by ssh calls inside 'ha-cluster-join')
  ssh -o StrictHostKeyChecking=no $(hostname) << EOF
ha-cluster-join --cluster-node "${VM_METADATA[sap_primary_instance]}" --yes --interface eth0 csync2
EOF
  ssh $(hostname) << EOF
ha-cluster-join --cluster-node "${VM_METADATA[sap_primary_instance]}" --yes ssh_merge
EOF
  ssh $(hostname) << EOF
ha-cluster-join --cluster-node "${VM_METADATA[sap_primary_instance]}" --yes cluster
EOF

  main::errhandle_log_info "Enable and start Pacemaker."
  systemctl enable pacemaker
  systemctl start pacemaker

  echo "ready" > /root/.deploy/."${HOSTNAME}".ready

  main::errhandle_log_info "Secondary VM joined the cluster."
}


nw-ha::create_fencing_resources() {
  local pri_suffix
  local sec_suffix

  main::errhandle_log_info "Adding fencing resources."

  pri_suffix="${VM_METADATA[sap_sid]}-${VM_METADATA[sap_primary_instance]}"
  sec_suffix="${VM_METADATA[sap_sid]}-${VM_METADATA[sap_secondary_instance]}"

  crm configure primitive "fence-${pri_suffix}" stonith:fence_gce \
    op monitor interval="300s" timeout="120s" \
    op start interval="0" timeout="60s" \
    params port="${VM_METADATA[sap_primary_instance]}" \
    zone="${VM_METADATA[sap_primary_zone]}" project="${VM_PROJECT}" \
    pcmk_reboot_timeout=300 pcmk_monitor_retries=4 pcmk_delay_max=30

  crm configure location "loc-fence-${pri_suffix}" "fence-${pri_suffix}" \
                         -inf: "${VM_METADATA[sap_primary_instance]}"

  crm configure primitive "fence-${sec_suffix}" stonith:fence_gce \
    op monitor interval="300s" timeout="120s" \
    op start interval="0" timeout="60s" \
    params port="${VM_METADATA[sap_secondary_instance]}" \
    zone="${VM_METADATA[sap_secondary_zone]}" project="${VM_PROJECT}" \
    pcmk_reboot_timeout=300 pcmk_monitor_retries=4

  crm configure location "loc-fence-${sec_suffix}" "fence-${sec_suffix}" \
                         -inf: "${VM_METADATA[sap_secondary_instance]}"

  main::errhandle_log_info "Fencing resources added."
}


nw-ha::create_file_system_resources() {
  main::errhandle_log_info "Adding file system resources."

  crm configure primitive \
    "file-system-${VM_METADATA[sap_sid]}-${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
    Filesystem \
    device="${VM_METADATA[nfs_path]}/usrsap${VM_METADATA[sap_sid]}${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
    directory="/usr/sap/${VM_METADATA[sap_sid]}/${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
    fstype="nfs" \
    op start timeout=60s interval=0 \
    op stop timeout=60s interval=0 \
    op monitor interval=20s timeout=40s

  crm configure primitive \
    file-system-"${VM_METADATA[sap_sid]}-ERS${VM_METADATA[sap_ers_instance_number]}" \
    Filesystem \
    device="${VM_METADATA[nfs_path]}/usrsap${VM_METADATA[sap_sid]}ERS${VM_METADATA[sap_ers_instance_number]}" \
    directory="/usr/sap/${VM_METADATA[sap_sid]}/ERS${VM_METADATA[sap_ers_instance_number]}" \
    fstype="nfs" \
    op start timeout=60s interval=0 \
    op stop timeout=60s interval=0 \
    op monitor interval=20s timeout=40s

  main::errhandle_log_info "File system resources added."
}


nw-ha::create_health_check_resources() {
  main::errhandle_log_info "Adding health check resources."

  crm configure primitive \
    "health-check-${VM_METADATA[sap_sid]}-${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" anything \
    params binfile="/usr/bin/socat" \
    cmdline_options="-U TCP-LISTEN:${VM_METADATA[scs_hc_port]},backlog=10,fork,reuseaddr /dev/null" \
    op monitor timeout=20s interval=10s \
    op_params depth=0

  crm configure primitive "health-check-${VM_METADATA[sap_sid]}-ERS${VM_METADATA[sap_ers_instance_number]}" anything \
    params binfile="/usr/bin/socat" \
    cmdline_options="-U TCP-LISTEN:${VM_METADATA[ers_hc_port]},backlog=10,fork,reuseaddr /dev/null" \
    op monitor timeout=20s interval=10s \
    op_params depth=0

  main::errhandle_log_info "Health check resources added."
}


nw-ha::create_vip_resources() {
  main::errhandle_log_info "Adding VIP resources."

  crm configure primitive \
    "vip-${VM_METADATA[sap_sid]}-${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
    IPaddr2 \
    params ip=${VM_METADATA[scs_vip_address]} cidr_netmask=32 nic="eth0" \
    op monitor interval=3600s timeout=60s

  crm configure primitive \
    "vip-${VM_METADATA[sap_sid]}-ERS${VM_METADATA[sap_ers_instance_number]}" \
    IPaddr2 \
    params ip=${VM_METADATA[ers_vip_address]} cidr_netmask=32 nic="eth0" \
    op monitor interval=3600s timeout=60s

  main::errhandle_log_info "VIP resources added."
}
