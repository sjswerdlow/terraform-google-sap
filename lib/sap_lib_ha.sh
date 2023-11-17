
ha::check_settings() {

  # Set additional global constants
  readonly PRIMARY_NODE_IP=$(ping "${VM_METADATA[sap_primary_instance]}" -c 1 | head -1 | awk  '{ print $3 }' | sed 's/(//' | sed 's/)//')
  readonly SECONDARY_NODE_IP=$(ping "${VM_METADATA[sap_secondary_instance]}" -c 1 | head -1 | awk  '{ print $3 }' | sed 's/(//' | sed 's/)//')

  ## check required parameters are present
  if [ -z "${VM_METADATA[sap_vip]}" ] || [ -z "${VM_METADATA[sap_primary_instance]}" ] || [ -z "${PRIMARY_NODE_IP}" ] || [ -z "${VM_METADATA[sap_primary_zone]}" ] || [ -z "${VM_METADATA[sap_secondary_instance]}" ] || [ -z "${SECONDARY_NODE_IP}" ]; then
    main::errhandle_log_warning "High Availability variables were missing or incomplete. Both SAP HANA VMs will be installed and configured but HA will need to be manually setup "
    main::complete
  fi

  mkdir -p /root/.deploy
}


ha::download_scripts() {
  # RHEL packages fence_gce and thus doesn't require this download
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    main::errhandle_log_info "Downloading pacemaker-gcp"
    mkdir -p /usr/lib/ocf/resource.d/gcp
    mkdir -p /usr/lib64/stonith/plugins/external
    PACEMAKER_ALIAS_COPY /usr/lib/ocf/resource.d/gcp/alias
    PACEMAKER_ROUTE_COPY /usr/lib/ocf/resource.d/gcp/route
    PACEMAKER_STONITH_COPY /usr/lib64/stonith/plugins/external/gcpstonith
    chmod +x /usr/lib/ocf/resource.d/gcp/alias
    chmod +x /usr/lib/ocf/resource.d/gcp/route
    chmod +x /usr/lib64/stonith/plugins/external/gcpstonith
  fi
}


ha::create_hdb_user() {
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    hana_monitoring_user="slehasync"
  elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
    hana_monitoring_user="rhelhasync"
  fi

  main::errhandle_log_info "Adding user ${hana_monitoring_user} to ${VM_METADATA[sap_hana_sid]}"

  ## create .sql file
  echo "CREATE USER ${hana_monitoring_user} PASSWORD \"${VM_METADATA[sap_hana_system_password]}\";" > /root/.deploy/"${HOSTNAME}"_hdbadduser.sql
  echo "GRANT DATA ADMIN TO ${hana_monitoring_user};" >> /root/.deploy/"${HOSTNAME}"_hdbadduser.sql
  echo "ALTER USER ${hana_monitoring_user} DISABLE PASSWORD LIFETIME;" >> /root/.deploy/"${HOSTNAME}"_hdbadduser.sql

  ## run .sql file
  PATH="$PATH:/usr/sap/${VM_METADATA[sap_hana_sid]}/HDB${VM_METADATA[sap_hana_instance_number]}/exe"
  bash -c "source /usr/sap/*/home/.sapenv.sh && hdbsql -u system -p '"${VM_METADATA[sap_hana_system_password]}"' -i ${VM_METADATA[sap_hana_instance_number]} -I /root/.deploy/${HOSTNAME}_hdbadduser.sql"
}


ha::hdbuserstore() {

  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    hana_user_store_key="SLEHALOC"
  elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
    hana_user_store_key="SAPHANARH2SR"
  fi

  main::errhandle_log_info "Adding hdbuserstore entry '${hana_user_store_key}' pointing to localhost:3${VM_METADATA[sap_hana_instance_number]}15"

  #add user store
  PATH="$PATH:/usr/sap/${VM_METADATA[sap_hana_sid]}/HDB${VM_METADATA[sap_hana_instance_number]}/exe"
  bash -c "source /usr/sap/*/home/.sapenv.sh && hdbuserstore SET ${hana_user_store_key} localhost:3${VM_METADATA[sap_hana_instance_number]}15 ${hana_monitoring_user} '"${VM_METADATA[sap_hana_system_password]}"'"

  #check userstore
  bash -c "source /usr/sap/*/home/.sapenv.sh && hdbsql -U ${hana_user_store_key} -o /root/.deploy/hdbsql.out -a 'select * from dummy'"

  if  ! grep -q \"X\" /root/.deploy/hdbsql.out; then
    main::errhandle_log_warning "Unable to connect to HANA after adding hdbuserstore entry. Both SAP HANA systems have been installed and configured but the remainder of the HA setup will need to be manually performed"
    main::complete
  fi

  main::errhandle_log_info "--- hdbuserstore connection test successful"
}

ha::config_cluster(){
  main::errhandle_log_info "Configuring cluster primivatives"
}


ha::copy_hdb_ssfs_keys(){
  main::errhandle_log_info "Transfering SSFS keys from ${VM_METADATA[sap_primary_instance]}"
  rm /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/data/SSFS_"${VM_METADATA[sap_hana_sid]}".DAT
  rm /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/key/SSFS_"${VM_METADATA[sap_hana_sid]}".KEY
  scp -o StrictHostKeyChecking=no "${VM_METADATA[sap_primary_instance]}":/usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/data/SSFS_"${VM_METADATA[sap_hana_sid]}".DAT /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/data/SSFS_"${VM_METADATA[sap_hana_sid]}".DAT
  scp -o StrictHostKeyChecking=no "${VM_METADATA[sap_primary_instance]}":/usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/key/SSFS_"${VM_METADATA[sap_hana_sid]}".KEY /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/key/SSFS_"${VM_METADATA[sap_hana_sid]}".KEY
  chown "${VM_METADATA[sap_hana_sid],,}"adm:sapsys /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/data/SSFS_"${VM_METADATA[sap_hana_sid]}".DAT
  chown "${VM_METADATA[sap_hana_sid],,}"adm:sapsys /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/key/SSFS_"${VM_METADATA[sap_hana_sid]}".KEY
  chmod g+wrx,u+wrx /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/data/SSFS_"${VM_METADATA[sap_hana_sid]}".DAT
  chmod g+wrx,u+wrx  /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/global/security/rsecssfs/key/SSFS_"${VM_METADATA[sap_hana_sid]}".KEY
}


ha::enable_hsr() {
  main::errhandle_log_info "Enabling HANA System Replication support "
  runuser -l "${VM_METADATA[sap_hana_sid],,}adm" -c "hdbnsutil -sr_enable --name=${HOSTNAME}"
}


ha::config_hsr() {
  main::errhandle_log_info "Configuring SAP HANA system replication primary -> secondary"

  for (( i = 0; i < 5; i++ )); do
    runuser -l "${VM_METADATA[sap_hana_sid],,}adm" -c "hdbnsutil -sr_register --remoteHost=${VM_METADATA[sap_primary_instance]} --remoteInstance=${VM_METADATA[sap_hana_instance_number]} --replicationMode=syncmem --operationMode=logreplay --name=${VM_METADATA[sap_secondary_instance]}"
    if ! [[ $? -eq 0 ]]; then
      main::errhandle_log_info "Enabling system repication failed. Attempt ${i}/5"
      sleep 60
    else
      break
    fi
  done
}


ha::check_hdb_replication(){
  main::errhandle_log_info "Checking SAP HANA replication status"
  # check status
  bash -c "source /usr/sap/*/home/.sapenv.sh && /usr/sap/${VM_METADATA[sap_hana_sid]}/HDB${VM_METADATA[sap_hana_instance_number]}/exe/hdbsql -o /root/.deploy/hdbsql.out -a -U ${hana_user_store_key} 'select distinct REPLICATION_STATUS from SYS.M_SERVICE_REPLICATION'"

  local count=0

  while ! grep -q \"ACTIVE\" /root/.deploy/hdbsql.out; do
    count=$((count +1)) # b/183019459
    main::errhandle_log_info "--- Replication is still in progressing. Waiting 60 seconds then trying again"
    bash -c "source /usr/sap/*/home/.sapenv.sh && /usr/sap/${VM_METADATA[sap_hana_sid]}/HDB${VM_METADATA[sap_hana_instance_number]}/exe/hdbsql -o /root/.deploy/hdbsql.out -a -U ${hana_user_store_key} 'select distinct REPLICATION_STATUS from SYS.M_SERVICE_REPLICATION'"
    sleep 60s
    if [ ${count} -gt 20 ]; then
      main::errhandle_log_error "SAP HANA System Replication didn't complete. Please check network connectivity and firewall rules"
    fi
  done
  main::errhandle_log_info "--- Replication in sync. Continuing with HA configuration"
}


ha::check_cluster(){
  main::errhandle_log_info "Checking cluster status"
  local count=0
  local max_attempts=20
  local sleep_time=60
  local finished=1

  while ! [ ${finished} -eq 0 ]; do
    ## Check cluster to ensure node is online
    if [ "${LINUX_DISTRO}" = "SLES" ]; then
      if crm status | grep -q offline; then
        finished=1
      else
        crm status simple
        finished=$?
      fi
    elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
      if pcs status | grep -q offline; then
        finished=1
      else
        pcs status
        finished=$?
      fi
    fi

    ## If cluster isn't healthy, wait and try again
    if ! [ ${finished} -eq 0 ]; then
      count=$((count +1))
      main::errhandle_log_info "--- Cluster is not yet healthy. Waiting ${sleep_time} seconds then trying again (attempt ${count}/${max_attempts})"
      sleep ${sleep_time}s
      if [ ${count} -gt ${max_attempts} ]; then
        main::errhandle_log_error "Not all pacemaker cluster nodes have come online. Please check network connectivity and firewall rules"
      fi
    fi
  done
  main::errhandle_log_info "--- All cluster nodes are online and healthy."
}

ha::check_node() {
  local node=${1}

  local count=0
  local max_attempts=25
  local sleep_time=60
  local finished=1

  main::errhandle_log_info "Checking cluster status of node ${node}"

  while ! [[ ${finished} -eq 0 ]]; do
    ## Check cluster to ensure node is online
    if [ "${LINUX_DISTRO}" = "SLES" ]; then
      crm status --group-by-node | grep online | grep -q "${node}"
    elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
      pcs status --full | grep Online | grep -q "${node}"
    fi
    finished=$?
    ## If node isn't online, wait and try again
    if ! [[ ${finished} -eq 0 ]]; then
      count=$((count +1))
      main::errhandle_log_info "--- Cluster node ${node} is not yet online. Waiting ${sleep_time} seconds then trying again (attempt ${count}/${max_attempts})"
      sleep ${sleep_time}s
      if [ ${count} -gt ${max_attempts} ]; then
        main::errhandle_log_error "Cluster node ${node} failed to come online. Please check network connectivity and firewall rules"
      fi
    fi
  done
  main::errhandle_log_info "---  Cluster node ${node} is online and healthy."
}

ha::config_corosync(){
  main::errhandle_log_info "--- Creating /etc/corosync/corosync.conf"
  cat <<EOF > /etc/corosync/corosync.conf
    totem {
      version: 2
      secauth: off
      crypto_hash: sha1
      crypto_cipher: aes256
      cluster_name: hacluster
      clear_node_high_bit: yes
      token: 20000
      token_retransmits_before_loss_const: 10
      join: 60
      max_messages: 20
      transport: udpu
      interface {
        ringnumber: 0
        bindnetaddr: "${PRIMARY_NODE_IP}"
        mcastport: 5405
        ttl: 1
      }
    }
    logging {
      fileline: off
      to_stderr: no
      to_logfile: no
      logfile: /var/log/cluster/corosync.log
      to_syslog: yes
      debug: off
      timestamp: on
      logger_subsys {
        subsys: QUORUM
        debug: off
      }
    }
    quorum {
      provider: corosync_votequorum
      expected_votes: 2
      two_node: 1
    }
    nodelist {
      node {
        ring0_addr: ${VM_METADATA[sap_primary_instance]}
        nodeid: 1
      }
      node {
        ring0_addr: ${VM_METADATA[sap_secondary_instance]}
        nodeid: 2
      }
EOF

  ## SAP HANA Scale-Out Specific
  if [[ -n "${VM_METADATA[majority_maker_instance_name]}" ]]; then
    {
      local node_count=3
      echo "      node {"
      echo "        ring0_addr: ${VM_METADATA[majority_maker_instance_name]}"
      echo "        nodeid: ${node_count}"
      echo "       }"
      node_count=$((node_count+1))

      for worker in $(seq 1 "${VM_METADATA[sap_hana_scaleout_nodes]}"); do
        echo "      node {"
        echo "        ring0_addr: ${VM_METADATA[sap_primary_instance]}w${worker}"
        echo "        nodeid: ${node_count}"
        echo "       }"
        node_count=$((node_count+1))
        echo "      node {"
        echo "        ring0_addr: ${VM_METADATA[sap_secondary_instance]}w${worker}"
        echo "        nodeid: ${node_count}"
        echo "       }"
        node_count=$((node_count+1))
      done
    } >> /etc/corosync/corosync.conf
    # disable two node cluster when in scale-out config
    sed -i 's/two_node: 1//g' /etc/corosync/corosync.conf
    sed -i 's/expected_votes: 2//g' /etc/corosync/corosync.conf
  fi

  ## Close out file
  cat <<EOF >> /etc/corosync/corosync.conf
    }
EOF
}


ha::pacemaker_maintenance() {
  local mode="${1}"

  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    main::errhandle_log_info "Setting cluster maintenance mode to ${mode}"
    crm configure property maintenance-mode="${mode}"
    crm resource cleanup
  fi

  if [ "${LINUX_DISTRO}" = "RHEL" ]; then
    main::errhandle_log_info "Setting cluster maintenance mode to ${mode}"
    pcs property set maintenance-mode="${mode}"
    pcs resource cleanup
  fi
}


ha::host_file_entries(){
  local ip

  main::errhandle_log_info "Updating /etc/hosts."

  # Add primary node entry
  ip=$(main::get_ip "${VM_METADATA[sap_primary_instance]}")
  if ! grep -q "${ip}" /etc/hosts; then
    echo  "${ip}" "${VM_METADATA[sap_primary_instance]}" >> /etc/hosts
  fi

  # Add secondary node entry
  ip=$(main::get_ip "${VM_METADATA[sap_secondary_instance]}")
  if ! grep -q "${ip}"  /etc/hosts; then
    echo  "${ip}" "${VM_METADATA[sap_secondary_instance]}" >> /etc/hosts
  fi

  # Scale-Out Specific Entries
  if [[ "${VM_METADATA[sap_hana_scaleout_nodes]}" -gt 0 ]]; then
    # Add majority maker entry
    main::errhandle_log_info "Adding scale-out node configuration to /etc/hosts"
    ip=$(main::get_ip "${VM_METADATA[majority_maker_instance_name]}")
    echo "${ip} ${VM_METADATA[majority_maker_instance_name]}" >> /etc/hosts
    # Add  worker node entries
    for worker in $(seq 1 "${VM_METADATA[sap_hana_scaleout_nodes]}"); do
      ip=$(main::get_ip "${VM_METADATA[sap_primary_instance]}w${worker}")
      echo "${ip} ${VM_METADATA[sap_primary_instance]}w${worker}" >> /etc/hosts
      ip=$(main::get_ip "${VM_METADATA[sap_secondary_instance]}w${worker}")
      echo "${ip} ${VM_METADATA[sap_secondary_instance]}w${worker}" >> /etc/hosts
    done
  fi
}

ha::pacemaker_startup_delay(){
  main::errhandle_log_info "--- Adding pacemaker startup delay"
  mkdir -p /etc/systemd/system/corosync.service.d/
  echo -e '[Service]\nExecStartPre=/bin/sleep 60' | tee -a /etc/systemd/system/corosync.service.d/override.conf
}

ha::config_pacemaker_primary() {
  main::errhandle_log_info "Creating cluster on primary node"

  main::errhandle_log_info "--- Creating corosync-keygen"
  corosync-keygen

  # SuSE specific
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    main::errhandle_log_info "--- Starting csync2"

    # initiate cluster and create configuration file
    script -q -c 'ha-cluster-init -y csync2' > /dev/null 2>&1 &
    ha::config_corosync

    # enable and start pacemaker services
    main::errhandle_log_info "--- Starting cluster services"
    sleep 5s
    systemctl enable pacemaker
    systemctl start pacemaker
    main::set_metadata status ready-for-ha-secondary
  fi

  # Redhat Specific
  if [ "${LINUX_DISTRO}" = "RHEL" ]; then
    main::errhandle_log_info "--- Setting hacluster password"
    echo linux | passwd --stdin hacluster
    main::errhandle_log_info "--- Configure firewall to allow high-availability traffic"
    firewall-cmd --permanent --add-service=high-availability
    firewall-cmd --reload
    main::errhandle_log_info "--- Starting cluster services & enabling on startup"
    systemctl start pcsd.service
    systemctl enable pcsd.service
    main::set_metadata status ready-for-ha-secondary

    main::errhandle_log_info "--- Creating the cluster"

    local count=0
    local max_attempts=30
    local sleep_time=20
    local finished=1
    local pcs_auth_command="pcs REPLACEME auth ${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]} -u hacluster -p linux"

    while ! [ ${finished} -eq 0 ]; do
      if [ "${LINUX_MAJOR_VERSION}" = "7" ]; then
        ${pcs_auth_command/REPLACEME/cluster}
        finished=$?
      else
        ${pcs_auth_command/REPLACEME/host}
        finished=$?
      fi
      if [ ${finished} -eq 0 ]; then
        if [ "${LINUX_MAJOR_VERSION}" = "7" ]; then
          pcs cluster setup --name hacluster ${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]} --token 20000 --join 60
          main::errhandle_log_info "--- Configuring Corosync"
          sed -i 's/join: 60/join: 60\n    token_retransmits_before_loss_const: 10\n    max_messages: 20/g' /etc/corosync/corosync.conf
        else
          pcs cluster setup hacluster ${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]} totem token=20000 join=60 token_retransmits_before_loss_const=10 max_messages=20
        fi
      else
        count=$((count +1))
        main::errhandle_log_info "--- pcsd.service not yet started on secondary - retrying in ${sleep_time} seconds (attempt number ${count} of max ${max_attempts})"
        sleep ${sleep_time}s
        if [ ${count} -gt ${max_attempts} ]; then
          main::errhandle_log_error "--- pcsd.service not started on secondary. Stopping deployment. Check logs on secondary."
        fi
      fi
    done
    pcs cluster sync
    pcs cluster enable --all
    pcs cluster start --all
  fi
  ha::pacemaker_startup_delay
}


ha::join_pacemaker_cluster() {
  local cluster_name=${1}

  local i

  main::errhandle_log_info "Joining ${HOSTNAME} to cluster ${cluster_name}"

  # SuSE Specific
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    # enable and start pacemaker services
    main::errhandle_log_info "--- Starting cluster services"

    for (( i = 0; i < 5; i++ )); do
      bash -c "ha-cluster-join -y -c ${cluster_name} csync2"
      systemctl enable pacemaker
      systemctl start pacemaker
      if [ $? -eq 0 ]; then
        break
      fi
      sleep 60
    done

    systemctl enable hawk
    systemctl start hawk
  fi

  # Redhat Specific
  if [ "${LINUX_DISTRO}" = "RHEL" ]; then
    main::errhandle_log_info "--- Setting hacluster password"
    echo linux | passwd --stdin hacluster
    main::errhandle_log_info "--- Configure firewall to allow high-availability traffic"
    firewall-cmd --permanent --add-service=high-availability
    firewall-cmd --reload
    main::errhandle_log_info "--- Starting cluster services & enabling on startup"
    systemctl start pcsd.service
    systemctl enable pcsd.service
  fi

  # Check cluster is complete then run complete (SSH bug within function)
  ha::check_node "${cluster_name}"
  ha::pacemaker_startup_delay
  main::complete
}

ha::pacemaker_scaleout_package_installation(){
  local count=0
  local max_count=10
  local package

  if [[ "${VM_METADATA[sap_hana_scaleout_nodes]}" -gt 0 && "${LINUX_DISTRO}" = "SLES" ]]; then
    local remove_packages="SAPHanaSR SAPHanaSR-doc yast2-sap-ha"
    local install_packages="SAPHanaSR-ScaleOut SAPHanaSR-ScaleOut-doc"

    # wait for zypper to finish running
    while pgrep zypper; do
      errhandle_log_info "--- zypper is still running. Waiting 10 seconds before attempting to continue"
      sleep 10s
    done

    # remove scale-up packages
    for package in ${remove_packages}; do
      sudo ZYPP_LOCK_TIMEOUT=60 zypper remove -y "${package}"
    done

    # install scale-out packages
    for package in ${install_packages}; do
      while ! sudo ZYPP_LOCK_TIMEOUT=60 zypper in -y "${package}"; do
        count=$((count +1))
        sleep 1
        if [[ ${count} -gt ${max_count} ]]; then
          main::errhandle_log_warning "Failed to install ${package}, continuing installation."
          break
        fi
      done
    done
  fi
}

ha::pacemaker_add_stonith() {
  main::errhandle_log_info "Cluster: Adding STONITH devices"

  # SuSE specific
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    crm configure primitive STONITH-"${VM_METADATA[sap_primary_instance]}" stonith:external/gcpstonith \
        op monitor interval="300s" timeout="120s" \
        op start interval="0" timeout="60s" \
        params instance_name="${VM_METADATA[sap_primary_instance]}" gcloud_path="${GCLOUD}" logging="yes" \
        pcmk_reboot_timeout=300 pcmk_monitor_retries=4 pcmk_delay_max=30
    crm configure primitive STONITH-"${VM_METADATA[sap_secondary_instance]}" stonith:external/gcpstonith \
        op monitor interval="300s" timeout="120s" \
        op start interval="0" timeout="60s" \
        params instance_name="${VM_METADATA[sap_secondary_instance]}" gcloud_path="${GCLOUD}" logging="yes" \
        pcmk_reboot_timeout=300 pcmk_monitor_retries=4
    crm configure location LOC_STONITH_"${VM_METADATA[sap_primary_instance]}" STONITH-"${VM_METADATA[sap_primary_instance]}" -inf: "${VM_METADATA[sap_primary_instance]}"
    crm configure location LOC_STONITH_"${VM_METADATA[sap_secondary_instance]}" STONITH-"${VM_METADATA[sap_secondary_instance]}" -inf: "${VM_METADATA[sap_secondary_instance]}"
    # Scale-out worker & majority mm node
    if [[ "${VM_METADATA[sap_hana_scaleout_nodes]}" -gt 0 ]]; then
      # mm
      crm configure primitive STONITH-"${VM_METADATA[majority_maker_instance_name]}w${worker}" stonith:external/gcpstonith \
        op monitor interval="300s" timeout="120s" \
        op start interval="0" timeout="60s" \
        params instance_name="${VM_METADATA[majority_maker_instance_name]}w${worker}" gcloud_path="${GCLOUD}" logging="yes" \
        pcmk_reboot_timeout=300 pcmk_monitor_retries=4 pcmk_delay_max=30
      crm configure location LOC_STONITH_"${VM_METADATA[majority_maker_instance_name]}" STONITH-"${VM_METADATA[majority_maker_instance_name]}" -inf: "${VM_METADATA[majority_maker_instance_name]}"
      for worker in $(seq 1 "${VM_METADATA[sap_hana_scaleout_nodes]}"); do
        # primary workers
        crm configure primitive STONITH-"${VM_METADATA[sap_primary_instance]}w${worker}" stonith:external/gcpstonith \
          op monitor interval="300s" timeout="120s" \
          op start interval="0" timeout="60s" \
          params instance_name="${VM_METADATA[sap_primary_instance]}w${worker}" gcloud_path="${GCLOUD}" logging="yes" \
          pcmk_reboot_timeout=300 pcmk_monitor_retries=4 pcmk_delay_max=30
        crm configure location LOC_STONITH_"${VM_METADATA[sap_primary_instance]}w${worker}" STONITH-"${VM_METADATA[sap_primary_instance]}w${worker}" -inf: "${VM_METADATA[sap_primary_instance]}w${worker}"
        # secondary workers
        crm configure primitive STONITH-"${VM_METADATA[sap_secondary_instance]}w${worker}" stonith:external/gcpstonith \
          op monitor interval="300s" timeout="120s" \
          op start interval="0" timeout="60s" \
          params instance_name="${VM_METADATA[sap_secondary_instance]}w${worker}" gcloud_path="${GCLOUD}" logging="yes" \
          pcmk_reboot_timeout=300 pcmk_monitor_retries=4
        crm configure location LOC_STONITH_"${VM_METADATA[sap_secondary_instance]}w${worker}" STONITH-"${VM_METADATA[sap_secondary_instance]}w${worker}" -inf: "${VM_METADATA[sap_secondary_instance]}w${worker}"
      done
    fi
  fi

  # Redhat specific
  if [ "${LINUX_DISTRO}" = "RHEL" ]; then
    pcs stonith create STONITH-"${VM_METADATA[sap_primary_instance]}" fence_gce \
        port="${VM_METADATA[sap_primary_instance]}" zone="${VM_METADATA[sap_primary_zone]}" project="${VM_PROJECT}" \
        pcmk_reboot_timeout=300 pcmk_monitor_retries=4 pcmk_delay_max=30 \
        op monitor interval="300s" timeout="120s" \
        op start interval="0" timeout="60s"
    pcs stonith create STONITH-"${VM_METADATA[sap_secondary_instance]}" fence_gce \
        port="${VM_METADATA[sap_secondary_instance]}" zone="${VM_METADATA[sap_secondary_zone]}" project="${VM_PROJECT}" \
        pcmk_reboot_timeout=300 pcmk_monitor_retries=4 \
        op monitor interval="300s" timeout="120s" \
        op start interval="0" timeout="60s"
    pcs constraint location STONITH-"${VM_METADATA[sap_primary_instance]}" avoids "${VM_METADATA[sap_primary_instance]}"
    pcs constraint location STONITH-"${VM_METADATA[sap_secondary_instance]}" avoids "${VM_METADATA[sap_secondary_instance]}"
  fi
}


ha::pacemaker_add_vip() {
  main::errhandle_log_info "Cluster: Adding virtual IP"
  main::errhandle_log_info "ILB settings" "${VM_METADATA[sap_vip_solution]}" "${VM_METADATA[sap_hc_port]}"
  if [ "${VM_METADATA[sap_vip_solution]}" = "ILB" ]; then
    main::errhandle_log_info "Using an ILB for the VIP"
    if [ "${LINUX_DISTRO}" = "SLES" ]; then
      crm configure primitive rsc_vip_hc-primary anything params binfile="/usr/bin/socat" cmdline_options="-U TCP-LISTEN:"${VM_METADATA[sap_hc_port]}",backlog=10,fork,reuseaddr /dev/null" op monitor timeout=20s interval=10s op_params depth=0
      crm configure primitive rsc_vip_int-primary IPaddr2 params ip="${VM_METADATA[sap_vip]}" cidr_netmask=32 nic="eth0" op monitor interval=3600s timeout=60s
      if [[ "${VM_METADATA[sap_hana_scaleout_nodes]}" = "0" ]]; then
        crm configure group g-primary rsc_vip_int-primary rsc_vip_hc-primary
      else
        crm configure group g-primary rsc_vip_int-primary rsc_vip_hc-primary meta resource-stickiness=0
      fi
    elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
      pcs resource create rsc_vip_${VM_METADATA[sap_hana_sid]}_${VM_METADATA[sap_hana_instance_number]} \
        IPaddr2 ip="${VM_METADATA[sap_vip]}" nic=eth0 cidr_netmask=32 op monitor interval=3600s timeout=60s
      pcs resource create rsc_healthcheck_${VM_METADATA[sap_hana_sid]} service:haproxy op monitor interval=10s timeout=20s
      pcs resource move rsc_healthcheck_${VM_METADATA[sap_hana_sid]} ${VM_METADATA[sap_primary_instance]}
      pcs resource clear rsc_healthcheck_${VM_METADATA[sap_hana_sid]}
      pcs resource group add g-primary rsc_healthcheck_${VM_METADATA[sap_hana_sid]} rsc_vip_${VM_METADATA[sap_hana_sid]}_${VM_METADATA[sap_hana_instance_number]}
    fi
  else
    if ! ping -c 1 -W 1 "${VM_METADATA[sap_vip]}"; then
      if [ "${LINUX_DISTRO}" = "SLES" ]; then
        crm configure primitive rsc_vip_int-primary IPaddr2 params ip="${VM_METADATA[sap_vip]}" cidr_netmask=32 nic="eth0" op monitor interval=3600s timeout=60s
        if [[ -n "${VM_METADATA[sap_vip_secondary_range]}" ]]; then
          crm configure primitive rsc_vip_gcp-primary ocf:gcp:alias op monitor interval="60s" timeout="60s" op start interval="0" timeout="600s" op stop interval="0" timeout="180s" params alias_ip="${VM_METADATA[sap_vip]}/32" hostlist="${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]}" gcloud_path="${GCLOUD}" alias_range_name="${VM_METADATA[sap_vip_secondary_range]}" logging="yes" meta priority=10
        else
          crm configure primitive rsc_vip_gcp-primary ocf:gcp:alias op monitor interval="60s" timeout="60s" op start interval="0" timeout="600s" op stop interval="0" timeout="180s" params alias_ip="${VM_METADATA[sap_vip]}/32" hostlist="${VM_METADATA[sap_primary_instance]} ${VM_METADATA[sap_secondary_instance]}" gcloud_path="${GCLOUD}" logging="yes" meta priority=10
        fi
        crm configure group g-primary rsc_vip_int-primary rsc_vip_gcp-primary
      fi
    else
      main::errhandle_log_warning "VIP is already associated with another VM. The cluster setup will continue but the floating/virtual IP address will not be added"
    fi
  fi
}


ha::pacemaker_config_bootstrap_hdb() {
  main::errhandle_log_info "Cluster: Configuring bootstrap for SAP HANA"

  # SuSE Specific
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    crm configure property stonith-timeout="300s"
    crm configure property stonith-enabled="true"
    crm configure rsc_defaults resource-stickiness="1000"
    crm configure rsc_defaults migration-threshold="5000"
    crm configure op_defaults timeout="600"
    # enable concurrent fencing if scale-out environment
    if [[ "${VM_METADATA[sap_hana_scaleout_nodes]}" -gt 0 ]]; then
      crm configure property concurrent-fencing=true
    fi
  fi

  # RHEL Specific
  if [ "${LINUX_DISTRO}" = "RHEL" ]; then
    main::errhandle_log_info "--- Setting cluster defaults"
    # as per documentation
    pcs resource defaults resource-stickiness=1000
    pcs resource defaults migration-threshold=5000
    pcs property set stonith-enabled="true"
    # increase from default 60
    pcs property set stonith-timeout="300s"
    # increase from default 20
    pcs resource op defaults timeout="600s"
  fi
}


ha::pacemaker_config_bootstrap_nfs() {
  main::errhandle_log_info "Cluster: Configuring bootstrap for NFS"
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    crm configure property no-quorum-policy="ignore"
    crm configure property startup-fencing="true"
    crm configure property stonith-timeout="300s"
    crm configure property stonith-enabled="true"
    crm configure rsc_defaults resource-stickiness="100"
    crm configure rsc_defaults migration-threshold="5000"
    crm configure op_defaults timeout="600"
  elif [ "${LINUX_DISTRO}" = "RHEL" ]; then
    pcs property set no-quorum-policy="ignore"
    pcs property set startup-fencing="true"
    pcs property set stonith-timeout="300s"
    pcs property set stonith-enabled="true"
    pcs resource defaults default-resource-stickness=1000
    pcs resource defaults default-migration-threshold=5000
    pcs resource op defaults timeout=600s
  fi
}


ha::pacemaker_add_hana() {
  main::errhandle_log_info "Cluster: Creating HANA resources (SAPHanaTopology, SAPHana)"

  # SuSE Specific
  if [ "${LINUX_DISTRO}" = "SLES" ]; then
    cat <<EOF > /root/.deploy/cluster.tmp
    primitive rsc_SAPHanaTopology_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} ocf:suse:SAPHanaTopology \
        operations \$id="rsc_sap2_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]}-operations" \
        op monitor interval="10" timeout="600" \
        op start interval="0" timeout="600" \
        op stop interval="0" timeout="300" \
        params SID="${VM_METADATA[sap_hana_sid]}" InstanceNumber="${VM_METADATA[sap_hana_instance_number]}"

    clone cln_SAPHanaTopology_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} rsc_SAPHanaTopology_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} \
        meta clone-node-max="1" target-role="Started" interleave="true"
EOF

    crm configure load update /root/.deploy/cluster.tmp

    if [[ -n "${VM_METADATA[majority_maker_instance_name]}" ]]; then
      cat <<EOF > /root/.deploy/cluster.tmp
      primitive rsc_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} ocf:suse:SAPHanaController \
        op start interval="0" timeout="3600" \
        op stop interval="0" timeout="3600" \
        op promote interval="0" timeout="3600" \
        op demote interval="0" timeout="3600" \
        op monitor interval="60" role="Master" timeout="700" \
        op monitor interval="61" role="Slave" timeout="700" \
        params SID="${VM_METADATA[sap_hana_sid]}" InstanceNumber="${VM_METADATA[sap_hana_instance_number]}" PREFER_SITE_TAKEOVER="true" \
        DUPLICATE_PRIMARY_TIMEOUT="7200" AUTOMATED_REGISTER="true"

      ms msl_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} rsc_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} \
        meta clone-node-max="1" master-max="1" interleave="true" \
        target-role="Started" interleave="true"

      colocation col_saphana_ip_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} 4000: g-primary:Started \
        msl_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]}:Master
      order ord_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} Optional: cln_SAPHanaTopology_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} \
        msl_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]}
EOF

      crm configure load update /root/.deploy/cluster.tmp
      crm configure location SAPHanaTop_not_on_mm "cln_SAPHanaTopology_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]}" -inf: "${VM_METADATA[majority_maker_instance_name]}"
      crm configure location SAPHanaCon_not_on_mm  "msl_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]}" -inf: "${VM_METADATA[majority_maker_instance_name]}"
    else
      cat <<EOF > /root/.deploy/cluster.tmp
      primitive rsc_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} ocf:suse:SAPHana \
        operations \$id="rsc_sap_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]}-operations" \
        op start interval="0" timeout="3600" \
        op stop interval="0" timeout="3600" \
        op promote interval="0" timeout="3600" \
        op demote interval="0" timeout="3600" \
        op monitor interval="60" role="Master" timeout="700" \
        op monitor interval="61" role="Slave" timeout="700" \
        params SID="${VM_METADATA[sap_hana_sid]}" InstanceNumber="${VM_METADATA[sap_hana_instance_number]}" PREFER_SITE_TAKEOVER="true" \
        DUPLICATE_PRIMARY_TIMEOUT="7200" AUTOMATED_REGISTER="true"

      ms msl_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} rsc_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} \
        meta notify="true" clone-max="2" clone-node-max="1" \
        target-role="Started" interleave="true"

      colocation col_saphana_ip_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} 4000: g-primary:Started \
        msl_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]}:Master
      order ord_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} Optional: cln_SAPHanaTopology_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]} \
        msl_SAPHana_${VM_METADATA[sap_hana_sid]}_HDB${VM_METADATA[sap_hana_instance_number]}
EOF
      crm configure load update /root/.deploy/cluster.tmp
    fi
  fi

  # RHEL Specific
  if [ "${LINUX_DISTRO}" = "RHEL" ]; then
    main::errhandle_log_info "Cluster: Creating resources SAPHanaTopology"
    pcs resource create SAPHanaTopology_${VM_METADATA[sap_hana_sid]}_${VM_METADATA[sap_hana_instance_number]} SAPHanaTopology SID=${VM_METADATA[sap_hana_sid]} \
      InstanceNumber=${VM_METADATA[sap_hana_instance_number]} \
      op start timeout=600 \
      op stop timeout=300 \
      op monitor interval=10 timeout=600 \
      clone clone-max=2 clone-node-max=1 interleave=true
    main::errhandle_log_info "Cluster: Creating resources SAPHana and constraints"
    pcs_create_command="pcs resource create SAPHana_${VM_METADATA[sap_hana_sid]}_${VM_METADATA[sap_hana_instance_number]} SAPHana SID=${VM_METADATA[sap_hana_sid]}
        InstanceNumber=${VM_METADATA[sap_hana_instance_number]}
        PREFER_SITE_TAKEOVER=true DUPLICATE_PRIMARY_TIMEOUT=7200 AUTOMATED_REGISTER=true
        op start timeout=3600
        op stop timeout=3600
        op monitor interval=61 role=Slave timeout=700
        op monitor interval=59 role=Master timeout=700
        op promote timeout=3600
        op demote timeout=3600
        REPLACEME meta notify=true clone-max=2 clone-node-max=1 interleave=true"
    pcs_constraint_order="pcs constraint order SAPHanaTopology_${VM_METADATA[sap_hana_sid]}_${VM_METADATA[sap_hana_instance_number]}-clone
        then SAPHana_${VM_METADATA[sap_hana_sid]}_${VM_METADATA[sap_hana_instance_number]}-REPLACEME symmetrical=false"
    pcs_constraint_coloc="pcs constraint colocation add g-primary
        with master SAPHana_${VM_METADATA[sap_hana_sid]}_${VM_METADATA[sap_hana_instance_number]}-REPLACEME 4000"
    if [ "${LINUX_MAJOR_VERSION}" = "7" ]; then
      ${pcs_create_command/REPLACEME/master}
      ${pcs_constraint_order/REPLACEME/master}
      ${pcs_constraint_coloc/REPLACEME/master}
    else
      ${pcs_create_command/REPLACEME/promotable}
      ${pcs_constraint_order/REPLACEME/clone}
      ${pcs_constraint_coloc/REPLACEME/clone}
    fi
  fi
}

ha::enable_hdb_hadr_provider_hook() {
  main::errhandle_log_info "Enabling HA/DR provider hook - checking HANA version"
  HANA_MAJOR_VERSION=$(su - "${VM_METADATA[sap_hana_sid],,}"adm HDB version | grep "version:" | awk '{ print $2 }' | awk -F "." '{ print $1 }')
  HANA_MINOR_VERSION=$(expr $(su - "${VM_METADATA[sap_hana_sid],,}"adm HDB version | grep "version:" | awk '{ print $2 }' | awk -F "." '{ print $3 }') + 0)
  main::errhandle_log_info "SAP HANA version returned as ${HANA_MAJOR_VERSION}.${HANA_MINOR_VERSION}"

  ## Only enable if HANA 2.0 SP3 or higher
  if [ "${HANA_MAJOR_VERSION}" -ge 2 -a "${HANA_MINOR_VERSION}" -ge 30 ]; then
    main::errhandle_log_info "Enabling HA/DR provider hook - HANA version checked"
    hdb::stop

    ## RHEL Specific
    if [[ "${LINUX_DISTRO}" = "RHEL" ]]; then
      # Add to sudoers
      {
        echo "Cmnd_Alias SITEA_SOK = /usr/sbin/crm_attribute -n hana_${VM_METADATA[sap_hana_sid],,}_site_srHook_${VM_METADATA[sap_primary_instance]} -v SOK -t crm_config -s SAPHanaSR"
        echo "Cmnd_Alias SITEA_SFAIL = /usr/sbin/crm_attribute -n hana_${VM_METADATA[sap_hana_sid],,}_site_srHook_${VM_METADATA[sap_primary_instance]} -v SFAIL -t crm_config -s SAPHanaSR"
        echo "Cmnd_Alias SITEB_SOK = /usr/sbin/crm_attribute -n hana_${VM_METADATA[sap_hana_sid],,}_site_srHook_${VM_METADATA[sap_secondary_instance]} -v SOK -t crm_config -s SAPHanaSR"
        echo "Cmnd_Alias SITEB_SFAIL = /usr/sbin/crm_attribute -n hana_${VM_METADATA[sap_hana_sid],,}_site_srHook_${VM_METADATA[sap_secondary_instance]} -v SFAIL -t crm_config -s SAPHanaSR"
        echo "${VM_METADATA[sap_hana_sid],,}adm ALL=(ALL) NOPASSWD: SITEA_SOK, SITEA_SFAIL, SITEB_SOK, SITEB_SFAIL"
        echo "# https://access.redhat.com/solutions/6315931"
        echo "Defaults!SITEA_SOK, SITEA_SFAIL, SITEB_SOK, SITEB_SFAIL !requiretty"
      } >> /etc/sudoers.d/20-saphana

      mkdir -p /hana/shared/myHooks
      cp /usr/share/SAPHanaSR/srHook/SAPHanaSR.py /hana/shared/myHooks
      chown -R "${VM_METADATA[sap_hana_sid],,}"adm:sapsys /hana/shared/myHooks

      ## Add hook to global.ini
      {
        echo "[ha_dr_provider_SAPHanaSR]"
        echo "provider = SAPHanaSR"
        echo "path = /hana/shared/myHooks"
        echo "execution_order = 1"
        echo "[trace]"
        echo "ha_dr_saphanasr = info"
      } >> /hana/shared/"${VM_METADATA[sap_hana_sid]}"/global/hdb/custom/config/global.ini
    fi

    ## SuSE Specific
    if [[ "${LINUX_DISTRO}" = "SLES" ]]; then
      # Add to sudoers
      {
        echo "# SAPHanaSR-ScaleUp & Scale-Out entries for writing srHook cluster attribute"
        echo "${VM_METADATA[sap_hana_sid],,}adm ALL=(ALL) NOPASSWD: /usr/sbin/crm_attribute -n hana_${VM_METADATA[sap_hana_sid],,}_site_srHook_*"
        echo "${VM_METADATA[sap_hana_sid],,}adm ALL=(ALL) NOPASSWD: /usr/sbin/SAPHanaSR-hookHelper *"
        echo "${VM_METADATA[sap_hana_sid],,}adm ALL=(ALL) NOPASSWD: /usr/sbin/crm_attribute -n hana_${VM_METADATA[sap_hana_sid],,}_glob_srHook -v *"
        echo "${VM_METADATA[sap_hana_sid],,}adm ALL=(ALL) NOPASSWD: /usr/sbin/crm_attribute -n hana_${VM_METADATA[sap_hana_sid],,}_glob_mts -v *"
        echo "${VM_METADATA[sap_hana_sid],,}adm ALL=(ALL) NOPASSWD: /usr/sbin/crm_attribute -n hana_${VM_METADATA[sap_hana_sid],,}_gsh -v *"
      } >> /etc/sudoers.d/20-saphana

      if [[ "${VM_METADATA[sap_hana_scaleout_nodes]}" -gt 0 ]]; then
        # Scale-out
        if [ "${HANA_MAJOR_VERSION}" -ge 2 -a "${HANA_MINOR_VERSION}" -ge 40 ]; then
          {
            echo "[ha_dr_provider_saphanasrmultitarget]"
            echo "provider = SAPHanaSrMultiTarget"
            echo "path = /usr/share/SAPHanaSR-ScaleOut"
            echo "execution_order = 1"
            echo "[trace]"
            echo "ha_dr_saphanasrmultitarget = info"
          } >> /hana/shared/"${VM_METADATA[sap_hana_sid]}"/global/hdb/custom/config/global.ini
        else
          # fallback option for HANA 2 < SPS4
          {
            echo "[ha_dr_provider_SAPHanaSR]"
            echo "provider = SAPHanaSR"
            echo "path = /usr/share/SAPHanaSR-ScaleOut/"
            echo "execution_order = 1"
            echo "[trace]"
            echo "ha_dr_saphanasr = info"
          } >> /hana/shared/"${VM_METADATA[sap_hana_sid]}"/global/hdb/custom/config/global.ini
        fi
        # susChkSrv to speed up takeover if indexserver fails (needs HANA 2 SPS5)
        if [ "${HANA_MAJOR_VERSION}" -ge 2 -a "${HANA_MINOR_VERSION}" -ge 50 ]; then
          {
            echo "[ha_dr_provider_suschksrv]"
            echo "provider = susChkSrv"
            echo "path = /usr/share/SAPHanaSR-ScaleOut"
            echo "execution_order = 3"
            echo "action_on_lost = stop"
          } >> /hana/shared/"${VM_METADATA[sap_hana_sid]}"/global/hdb/custom/config/global.ini
        fi
      else
        # Scale-up
        {
          echo "[ha_dr_provider_SAPHanaSR]"
          echo "provider = SAPHanaSR"
          echo "path = /usr/share/SAPHanaSR"
          echo "execution_order = 1"
          echo "[trace]"
          echo "ha_dr_saphanasr = info"
        } >> /hana/shared/"${VM_METADATA[sap_hana_sid]}"/global/hdb/custom/config/global.ini

        # susChkSrv to speed up takeover if indexserver fails (needs HANA 2 SPS5)
        if [ "${HANA_MAJOR_VERSION}" -ge 2 -a "${HANA_MINOR_VERSION}" -ge 50 ]; then
          {
            echo "[ha_dr_provider_suschksrv]"
            echo "provider = susChkSrv"
            echo "path = /usr/share/SAPHanaSR"
            echo "execution_order = 3"
            echo "action_on_lost = stop"
          } >> /hana/shared/"${VM_METADATA[sap_hana_sid]}"/global/hdb/custom/config/global.ini
        fi
      fi
    fi
    hdb::start
  fi
}

ha::setup_haproxy() {
  if [ "${LINUX_DISTRO}" = "RHEL" -a "${VM_METADATA[sap_vip_solution]}" = "ILB" ]; then
    main::errhandle_log_info "Installing haproxy"
    yum install -y haproxy || main::errhandle_log_warning "- haproxy could not be installed. Manual configuration will be needed"

    main::errhandle_log_info "Configuring haproxy"
    sed -ie '/mode/s/http/tcp/' /etc/haproxy/haproxy.cfg
    sed -ie '/option/s/httplog/tcplog/' /etc/haproxy/haproxy.cfg
    sed -ie 's/option forwardfor/#option forwardfor/' /etc/haproxy/haproxy.cfg
    cat <<EOF >> /etc/haproxy/haproxy.cfg

#---------------------------------------------------------------------
# Health check listener port for SAP HANA HA cluster
#---------------------------------------------------------------------
listen healthcheck
  bind *:${VM_METADATA[sap_hc_port]}
EOF
  fi
}
