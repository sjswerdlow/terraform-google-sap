
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
  local loc_vip
  # Default google-guest-agent configuration file
  local cfg_file=/etc/default/instance_configs.cfg

  main::errhandle_log_info "Enabling load balancer back-end communication between the VMs."

  main::errhandle_log_info "Stopping google-guest-agent for reconfiguration."
  service google-guest-agent stop
  for loc_vip in $(ip route show table local | grep "proto 66" | awk '{print $2}'); do
    ip route del table local ${loc_vip} dev eth0
  done

  if grep "IpForwarding]" ${cfg_file}; then
    sed -i 's/^ip_aliases.*/ip_aliases = true/' ${cfg_file}
    sed -i 's/^target_instance_ips.*/target_instance_ips = false/' ${cfg_file}
  else
    cat << AGT >> ${cfg_file}
[IpForwarding]
ethernet_proto_id = 66
ip_aliases = true
target_instance_ips = false
AGT
  fi

  if grep "NetworkInterfaces]" ${cfg_file}; then
    sed -i 's/^ip_forwarding.*/ip_forwarding = false/' ${cfg_file}
  else
    cat << AGT >> ${cfg_file}
[NetworkInterfaces]
ip_forwarding = false
AGT
  fi

  if service google-guest-agent restart; then
    main::errhandle_log_info "IP settings applied to to the google-guest-agent for load balancing back-end communication."
  else
    main::errhandle_log_warning "The google-guest-agent is not functioning / installed. Load balancing might not work as expected."
  fi

}


nw-ha::create_nfs_directories() {
  local rc
  local dir
  local directories

  directories="
    /mnt/nfs/sapmnt${VM_METADATA[sap_sid]}
    /mnt/nfs/usrsaptrans
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
  mkdir -p /usr/sap/"${VM_METADATA[sap_sid]}"/"${VM_METADATA[sap_ascs]}"SCS"${VM_METADATA[sap_scs_instance_number]}"
  mkdir -p /usr/sap/"${VM_METADATA[sap_sid]}"/ERS"${VM_METADATA[sap_ers_instance_number]}"

  echo "/- /etc/auto.sap" | tee -a /etc/auto.master
  echo "/sapmnt/${VM_METADATA[sap_sid]} $nfs_opts ${VM_METADATA[nfs_path]}/sapmnt${VM_METADATA[sap_sid]}" | tee -a /etc/auto.sap
  echo "/usr/sap/trans $nfs_opts ${VM_METADATA[nfs_path]}/usrsaptrans" | tee -a /etc/auto.sap

  systemctl enable autofs
  systemctl restart autofs
  automount -v

  cd /sapmnt/${VM_METADATA[sap_sid]}
  cd /usr/sap/trans
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
  if [[ ${LINUX_DISTRO} = "RHEL" ]]; then
    yum install -y pcs pacemaker
    yum install -y fence-agents-gce
    yum install -y resource-agents-gcp
    yum install -y resource-agents-sap
    yum install -y sap-cluster-connector
    yum install -y haproxy
    yum install -y socat
  fi
  main::errhandle_log_info "HA packages installed."
}


nw-ha::pacemaker_create_cluster_primary() {
  main::errhandle_log_info "Creating cluster on primary node."

  main::errhandle_log_info "Initializing cluster."
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    ha-cluster-init --name "${VM_METADATA[pacemaker_cluster_name]}" --yes --interface eth0 csync2
    ha-cluster-init --name "${VM_METADATA[pacemaker_cluster_name]}" --yes --interface eth0 corosync
    main::errhandle_log_info "Configuring Corosync ..."
    sed -i 's/token:.*/token: 20000/g' /etc/corosync/corosync.conf
    sed -i '/consensus:/d' /etc/corosync/corosync.conf
    sed -i 's/join:.*/join: 60/g' /etc/corosync/corosync.conf
    sed -i 's/max_messages:.*/max_messages: 20/g' /etc/corosync/corosync.conf
    sed -i 's/token_retransmits_before_loss_const:.*/token_retransmits_before_loss_const: 10/g' /etc/corosync/corosync.conf
    main::errhandle_log_info "Creating the cluster"
    ha-cluster-init --name ${VM_METADATA[pacemaker_cluster_name]} --yes cluster
  fi
  if [[ ${LINUX_DISTRO} = "RHEL" ]]; then
    local hacluster_pass
    # Generate one-shot password for initial setup
    main::errhandle_log_info "Setting up the hacluster user and starting pcsd"
    hacluster_pass=$(cat /dev/urandom | tr -dc '[:alnum:]' | fold -w ${1:-10} | head -n 1)
    echo "hacluster:${hacluster_pass}" | chpasswd
    ssh -o StrictHostKeyChecking=no ${VM_METADATA[sap_secondary_instance]} << EOF
echo hacluster:"${hacluster_pass}" | chpasswd
EOF
    firewall-cmd --permanent --add-service=high-availability
    firewall-cmd --reload
    systemctl start pcsd.service
    systemctl enable pcsd.service
    nw-ha::setup_haproxy

    echo "ready" > /root/.deploy/."${HOSTNAME}".ready

    local count=0
    local max_attempts=30
    local sleep_time=20
    local finished=1

    main::errhandle_log_info "Registering the hosts for the cluster"
    while ! [ ${finished} -eq 0 ]; do
      if [[ $LINUX_MAJOR_VERSION -ge 8 ]]; then
        if pcs host auth ${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]} -u hacluster -p ${hacluster_pass}; then
          main::errhandle_log_info "Hosts registered for the cluster."
          finished=0
        fi
      fi
      if [[ $LINUX_MAJOR_VERSION -le 7 ]]; then
        if pcs cluster auth ${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]} -u hacluster -p ${hacluster_pass}; then
          main::errhandle_log_info "Hosts registered for the cluster."
          finished=0
        fi
      fi
      count=$((count +1))
      main::errhandle_log_info "pcsd.service not yet started on secondary - retrying in ${sleep_time} seconds (attempt number ${count} of max ${max_attempts})"
      sleep ${sleep_time}s
      if [ ${count} -gt ${max_attempts} ]; then
        main::errhandle_log_error "pcsd.service not started on secondary. Stopping deployment. Check logs on secondary."
      fi
    done

    main::errhandle_log_info "Creating the cluster"
    if [[ $LINUX_MAJOR_VERSION -ge 8 ]]; then
      pcs cluster setup "${VM_METADATA[pacemaker_cluster_name]}" \
        ${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]} \
        totem token=20000 join=60 token_retransmits_before_loss_const=10 max_messages=20
    fi
    if [[ $LINUX_MAJOR_VERSION -le 7 ]]; then
      pcs cluster setup --name "${VM_METADATA[pacemaker_cluster_name]}" \
        ${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]} \
        --token 20000 --join 60
      local cfg_out="/etc/corosync/corosync.conf"
      grep "max_messages:" ${cfg_out} \
        && sed -i 's/max_messages:.*/max_messages: 20/g' ${cfg_out} \
        || sed -i '/token:/a\    max_messages: 20' ${cfg_out}
      grep "token_retransmits_before_loss_const:" ${cfg_out} \
        && sed -i 's/token_retransmits_before_loss_const:.*/token_retransmits_before_loss_const: 10/g' ${cfg_out} \
        || sed -i '/token:/a\    token_retransmits_before_loss_const: 10' ${cfg_out}
    fi
    if [[ ! -f /etc/corosync/corosync.conf ]]; then
      main::errhandle_log_error "/etc/corosync/corosync.conf does not exist. Cluster setup incomplete."
    fi
    if [[ $LINUX_MAJOR_VERSION -ge 8 ]]; then
      sed -i 's/transport:.*/transport: knet/g' /etc/corosync/corosync.conf
    fi
    pcs cluster sync
    pcs cluster enable --all
    pcs cluster start --all
  fi
  main::errhandle_log_info "Setting general cluster properties."
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    crm configure property stonith-timeout="300s"
    crm configure property stonith-enabled="true"
    crm configure rsc_defaults resource-stickiness="1"
    crm configure rsc_defaults migration-threshold="3"
    crm configure op_defaults timeout="600"
  fi
  if [[ ${LINUX_DISTRO} = "RHEL" ]]; then
    if [[ $LINUX_MAJOR_VERSION -ge 8 ]]; then
      pcs resource defaults update resource-stickiness="1"
      pcs resource defaults update migration-threshold="3"
    fi
    if [[ $LINUX_MAJOR_VERSION -le 7 ]]; then
      pcs resource defaults resource-stickiness="1"
      pcs resource defaults migration-threshold="3"
    fi
  fi
  main::errhandle_log_info "Enable and start Pacemaker service"
  systemctl enable pacemaker
  systemctl start pacemaker

  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    echo "ready" > /root/.deploy/."${HOSTNAME}".ready
  fi

  main::errhandle_log_info "Cluster on primary node created."
}


nw-ha::pacemaker_join_secondary() {
  main::errhandle_log_info "Joining secondary VM to the cluster."
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
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
  fi

  if [[ ${LINUX_DISTRO} = "RHEL" ]]; then
    # RHEL secondary would be triggered from primary
    # validate that cluster is online
    firewall-cmd --permanent --add-service=high-availability
    firewall-cmd --reload
    systemctl start pcsd.service
    systemctl enable pcsd.service
    pcs cluster sync
    systemctl restart corosync
    nw-ha::setup_haproxy
  fi

  echo "ready" > /root/.deploy/."${HOSTNAME}".ready

  main::errhandle_log_info "Enable and start Pacemaker."
  systemctl enable pacemaker
  #Retry startup in case there's still initialization
  local retrycount=5
  while [[ retrycount -gt 0 ]]; do
    if systemctl start pacemaker; then
      main::errhandle_log_info "Pacemaker started on secondary."
      break
    else
      let retrycount-=1
      if [[ retrycount -gt 0 ]]; then
        main::errhandle_log_warning "Pacemaker could not be started on secondary yet. Retrying."
        sleep 30
      else
        main::errhandle_log_error "Pacemaker could not be started on secondary. Aborting."
        # Error routine will handle exit
      fi
    fi
  done
  main::errhandle_log_info "Secondary VM joined the cluster."
}


nw-ha::create_fencing_resources() {
  local pri_suffix
  local sec_suffix

  main::errhandle_log_info "Adding fencing resources."

  pri_suffix="${VM_METADATA[sap_sid]}-${VM_METADATA[sap_primary_instance]}"
  sec_suffix="${VM_METADATA[sap_sid]}-${VM_METADATA[sap_secondary_instance]}"

  if [ "${LINUX_DISTRO}" = "SLES" ]; then
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
  elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
    pcs stonith create "fence-${pri_suffix}" fence_gce \
        port="${VM_METADATA[sap_primary_instance]}" \
        zone="${VM_METADATA[sap_primary_zone]}" project="${VM_PROJECT}" \
        pcmk_reboot_timeout=300 pcmk_monitor_retries=4 pcmk_delay_max=30 \
        op monitor interval="300s" timeout="120s" \
        op start interval="0" timeout="60s"
    pcs stonith create "fence-${sec_suffix}" fence_gce \
        port="${VM_METADATA[sap_secondary_instance]}" \
        zone="${VM_METADATA[sap_secondary_zone]}" project="${VM_PROJECT}" \
        pcmk_reboot_timeout=300 pcmk_monitor_retries=4 \
        op monitor interval="300s" timeout="120s" \
        op start interval="0" timeout="60s"
    pcs constraint location "fence-${pri_suffix}" avoids "${VM_METADATA[sap_primary_instance]}"
    pcs constraint location "fence-${sec_suffix}" avoids "${VM_METADATA[sap_secondary_instance]}"
  fi

  main::errhandle_log_info "Fencing resources added."
}


nw-ha::create_file_system_resources() {
  main::errhandle_log_info "Adding file system resources."
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
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
  elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
    pcs resource create \
      file-system-"${VM_METADATA[sap_sid]}-${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
      Filesystem \
      device="${VM_METADATA[nfs_path]}/usrsap${VM_METADATA[sap_sid]}${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
      directory="/usr/sap/${VM_METADATA[sap_sid]}/${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
      fstype="nfs" \
      op start timeout=60s interval=0 \
      op stop timeout=60s interval=0 \
      op monitor interval=20s timeout=40s
    pcs resource create \
      file-system-"${VM_METADATA[sap_sid]}-ERS${VM_METADATA[sap_ers_instance_number]}" \
      Filesystem \
      device="${VM_METADATA[nfs_path]}/usrsap${VM_METADATA[sap_sid]}ERS${VM_METADATA[sap_ers_instance_number]}" \
      directory="/usr/sap/${VM_METADATA[sap_sid]}/ERS${VM_METADATA[sap_ers_instance_number]}" \
      fstype="nfs" \
      op start timeout=60s interval=0 \
      op stop timeout=60s interval=0 \
      op monitor interval=20s timeout=40s
  fi
  main::errhandle_log_info "File system resources added."
}

nw-ha::setup_haproxy() {
  if [ "${LINUX_DISTRO}" = "RHEL" ]; then
    main::errhandle_log_info "Configuring haproxy"
    which haproxy || main::errhandle_log_error "haproxy is not installed. Manual configuration will be needed for a healthcheck service"

    ## Set up health check target
    main::errhandle_log_info "Installing haproxy -- setting up systemd files"
    cp /usr/lib/systemd/system/haproxy.service /etc/systemd/system/haproxy@.service
    sed -i 's/HAProxy Load Balancer/HAProxy Load Balancer \%i/' /etc/systemd/system/haproxy\@.service
    sed -i 's/haproxy.cfg/haproxy-\%i.cfg/' /etc/systemd/system/haproxy\@.service
    sed -i 's/haproxy.pid/haproxy-\%i.pid/' /etc/systemd/system/haproxy\@.service

    main::errhandle_log_info "Installing haproxy -- creating configuration files"
    for type in ${VM_METADATA[sap_ascs]}SCS ERS; do
      cat <<- EOF > /etc/haproxy/haproxy-"${VM_METADATA[sap_sid]}${type}".cfg
global
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy-%i.pid
    user        haproxy
    group       haproxy
    daemon
defaults
    mode                    tcp
    log                     global
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout check           10s
    maxconn                 3000
EOF

      echo "# Listener for SAP healthcheck" >> /etc/haproxy/haproxy-"${VM_METADATA[sap_sid]}${type}".cfg
      echo "listen healthcheck" >> /etc/haproxy/haproxy-"${VM_METADATA[sap_sid]}${type}".cfg
      if [[ $type == "ERS" ]]; then
        echo "   bind *:${VM_METADATA[ers_hc_port]}" >> /etc/haproxy/haproxy-"${VM_METADATA[sap_sid]}${type}".cfg
      else
        echo "   bind *:${VM_METADATA[scs_hc_port]}" >> /etc/haproxy/haproxy-"${VM_METADATA[sap_sid]}${type}".cfg
      fi
    done
  fi
}

nw-ha::create_health_check_resources() {
  main::errhandle_log_info "Adding health check resources."
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    crm configure primitive \
      "health-check-${VM_METADATA[sap_sid]}-${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" anything \
      params binfile="/usr/bin/socat" \
      cmdline_options="-U TCP-LISTEN:${VM_METADATA[scs_hc_port]},backlog=10,fork,reuseaddr /dev/null" \
      op monitor timeout=20s interval=10s \
      op_params depth=0

    crm -F configure primitive "health-check-${VM_METADATA[sap_sid]}-ERS${VM_METADATA[sap_ers_instance_number]}" anything \
      params binfile="/usr/bin/socat" \
      cmdline_options="-U TCP-LISTEN:${VM_METADATA[ers_hc_port]},backlog=10,fork,reuseaddr /dev/null" \
      op monitor timeout=20s interval=10s \
      op_params depth=0
  elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
    pcs resource create "health-check-${VM_METADATA[sap_sid]}-${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
      service:haproxy@${VM_METADATA[sap_sid]}${VM_METADATA[sap_ascs]}SCS \
      op monitor interval=10s timeout=20s
    pcs resource create "health-check-${VM_METADATA[sap_sid]}-ERS${VM_METADATA[sap_ers_instance_number]}" \
      service:haproxy@${VM_METADATA[sap_sid]}ERS \
      op monitor interval=10s timeout=20s
  fi

  main::errhandle_log_info "Health check resources added."
}


nw-ha::create_vip_resources() {
  main::errhandle_log_info "Adding VIP resources."
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
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
  elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
    pcs resource create \
      "vip-${VM_METADATA[sap_sid]}-${VM_METADATA[sap_ascs]}SCS${VM_METADATA[sap_scs_instance_number]}" \
      IPaddr2 \
      ip=${VM_METADATA[scs_vip_address]} cidr_netmask=32 nic="eth0" \
      op monitor interval=3600s timeout=60s

    pcs resource create \
      "vip-${VM_METADATA[sap_sid]}-ERS${VM_METADATA[sap_ers_instance_number]}" \
      IPaddr2 \
      ip=${VM_METADATA[ers_vip_address]} cidr_netmask=32 nic="eth0" \
      op monitor interval=3600s timeout=60s
  fi
  main::errhandle_log_info "VIP resources added."
}
