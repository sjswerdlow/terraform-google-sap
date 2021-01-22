
hdbso::calculate_volume_sizes() {

  if [[ ! "${VM_METADATA[sap_hana_original_role]}" = "standby" ]]; then
    main::errhandle_log_info "Calculating disk volume sizes"

    hana_log_size=$((VM_MEMSIZE/2))

    if [[ ${hana_log_size} -gt 512 ]]; then
      hana_log_size=512
    fi

    hana_data_size=$(((VM_MEMSIZE*15)/10))

    ## if there is enough space (i.e, multi_sid enabled or if 208GB instances) then double the volume sizes
    hana_pdssd_size=$(($(lsblk --nodeps --bytes --noheadings --output SIZE /dev/sdb)/1024/1024/1024))
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

    ## create volume group
    main::create_vg /dev/sdb vg_hana

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
  fi

  ## create base SID directory to avoid hdblcm failing on worker/standby nodes
  mkdir -p /hana/data/"${VM_METADATA[sap_hana_sid]}" /hana/log/"${VM_METADATA[sap_hana_sid]}"
}


hdbso::mount_nfs_vols() {
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
}


hdbso::gcestorageclient_install() {
  ## install python module requirements for gceStorageClient
  pip install --upgrade pyasn1-modules

  main::errhandle_log_info "Installing gceStorageClient"
  if [[ ${LINUX_DISTRO} = "SLES" ]]; then
    zypper addrepo --gpgcheck-allow-unsigned-package --refresh https://packages.cloud.google.com/yum/repos/google-sapgcestorageclient-sles$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"' | cut -f1 -d.)-\$basearchGCE_STORAGE_REPO_SUFFIX google-sapgcestorageclientGCE_STORAGE_REPO_SUFFIX
    zypper --no-gpg-checks install -y google-sapgcestorageclient
  else
    # RHEL
    RHEL_VERSION=`rpm -q --queryformat '%{VERSION}' redhat-release-server | cut -f1 -d. | cut -c1-1`
    if [[ "${RHEL_VERSION}" == "p" ]]; then
      RHEL_VERSION=`rpm -q --queryformat '%{VERSION}' redhat-release | cut -f1 -d. | cut -c1-1`
    fi
    tee /etc/yum.repos.d/google-sapgcestorageclientGCE_STORAGE_REPO_SUFFIX.repo << EOM
[google-sapgcestorageclientGCE_STORAGE_REPO_SUFFIX]
name=Google SAP GCE Storage Client
baseurl=https://packages.cloud.google.com/yum/repos/google-sapgcestorageclient-el${RHEL_VERSION}-\$basearchGCE_STORAGE_REPO_SUFFIX
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
basepath_shared = no

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
    echo "partition_${worker}_*__pd = ${HOSTNAME}-mnt${partno_concat}" >> /hana/shared/gceStorageClient/global.ini
  done

  ## Add bottom section to global.ini
  cat <<EOF >> /hana/shared/gceStorageClient/global.ini
partition_*_data__dev = /dev/vg_hana/data
partition_*_log__dev = /dev/vg_hana/log
partition_*_data__mountOptions = -t xfs -o logbsize=256k
partition_*_log__mountOptions = -t xfs -o nobarrier,logbsize=256k
partition_*_*__fencing = disabled

[trace]
ha_gcestorageclient = info
EOF
}


hdbso::update_sudoers() {
  main::errhandle_log_info "Updating /etc/sudoers"
  echo "${VM_METADATA[sap_hana_sid],,}adm ALL=NOPASSWD: /sbin/multipath,/sbin/multipathd,/etc/init.d/multipathd,/usr/bin/sg_persist,/bin/mount,/bin/umount,/bin/kill,/usr/bin/lsof,/usr/bin/systemctl,/usr/sbin/lsof,/usr/sbin/xfs_repair,/usr/bin/mkdir,/sbin/vgscan,/sbin/pvscan,/sbin/lvscan,/sbin/vgchange,/sbin/lvdisplay,/usr/bin/gcloud" >>/etc/sudoers
  echo "" >> /etc/sudoers
}


hdbso::install_scaleout_nodes() {

  main::errhandle_log_info "Preparing to install additional SAP HANA nodes"

  local worker
  local count=0

  for worker in $(seq 1 "${VM_METADATA[sap_hana_scaleout_nodes]}"); do
    while [[ $(ssh -o StrictHostKeyChecking=no "${HOSTNAME}"w"${worker}" "echo 1") != [1] ]]; do
			count=$((count +1))
      main::errhandle_log_info "--- ${HOSTNAME}w${worker} is not accessible via SSH - sleeping for 10 seconds and trying again"
      sleep 10
      if [ ${count} -gt 60 ]; then
        main::errhandle_log_error "Unable to add additional HANA hosts. Couldn't connect to additional ${HOSTNAME}w${worker} via SSH"
      fi
    done
  done

  ## get passwords from install file
  local hana_xml="<?xml version=\"1.0\" encoding=\"UTF-8\"?><Passwords>"
  hana_xml+="<password><![CDATA[$(grep password /root/.deploy/"${HOSTNAME}"_hana_install.cfg | grep -v sapadm | grep -v system | cut -d"=" -f2 | head -1)]]></password>"
  hana_xml+="<sapadm_password><![CDATA[$(grep sapadm_password /root/.deploy/"${HOSTNAME}"_hana_install.cfg | cut -d"=" -f2)]]></sapadm_password>"
  hana_xml+="<system_user_password><![CDATA[$(grep system_user_password /root/.deploy/"${HOSTNAME}"_hana_install.cfg | cut -d"=" -f2 | head -1)]]></system_user_password></Passwords>"

  cd /hana/shared/"${VM_METADATA[sap_hana_sid]}"/hdblcm || main::errhandle_log_error "Unable to access HANA Lifecycle Manager. Additional HANA nodes will not be installed"

  ## Install Worker Nodes
  if [[ ! "${VM_METADATA[sap_hana_worker_nodes]}" = "0" ]]; then
    main::errhandle_log_info "Installing ${VM_METADATA[sap_hana_worker_nodes]} worker nodes"
    ## ssh into each worker node and start SAP HANA
    for worker in $(seq 1 "${VM_METADATA[sap_hana_worker_nodes]}"); do
      main::errhandle_log_info "--- ${HOSTNAME}w${worker}"
      echo "${hana_xml}" | ./hdblcm --action=add_hosts --addhosts="${HOSTNAME}"w"${worker}" --root_user=root --listen_interface=global --read_password_from_stdin=xml -b
    done
  fi

  if [[ ! ${VM_METADATA[sap_hana_standby_nodes]} = "0" ]]; then
    main::errhandle_log_info "Installing ${VM_METADATA[sap_hana_standby_nodes]} standby nodes"
    for worker in $(seq $((VM_METADATA[sap_hana_worker_nodes]+1)) "${VM_METADATA[sap_hana_scaleout_nodes]}"); do
      main::errhandle_log_info "--- ${HOSTNAME}w${worker}"
      echo "${hana_xml}" | ./hdblcm --action=add_hosts --addhosts="${HOSTNAME}"w"${worker}":role=standby --root_user=root --listen_interface=global --read_password_from_stdin=xml -b
    done
  fi

  # Ensure HANA is set to autostart
  sed -i -e 's/Autostart=0/Autostart=1/g' /usr/sap/"${VM_METADATA[sap_hana_sid]}"/SYS/profile/*

  ## restart SAP HANA
  hdbso::restart

  ## configure masters
  main::errhandle_log_info "Updating SAP HANA configured roles"
  echo "call SYS.UPDATE_LANDSCAPE_CONFIGURATION('deploy','{\"HOSTS\":{\"${HOSTNAME}w1\":{\"WORKER_CONFIG_GROUPS\":\"default\",\"FAILOVER_CONFIG_GROUP\":\"default\",\"INDEXSERVER_CONFIG_ROLE\":\"WORKER\",\"NAMESERVER_CONFIG_ROLE\":\"MASTER 2\"},\"${HOSTNAME}w$((VM_METADATA[sap_hana_worker_nodes]+1))\":{\"WORKER_CONFIG_GROUPS\":\"default\",\"FAILOVER_CONFIG_GROUP\":\"default\",\"INDEXSERVER_CONFIG_ROLE\":\"STANDBY\",\"NAMESERVER_CONFIG_ROLE\":\"MASTER 3\"}}}')" > /root/.deploy/hdbconfig.sql
  bash -c "source /usr/sap/*/home/.sapenv.sh && hdbsql -d SYSTEMDB -u SYSTEM -p ${VM_METADATA[sap_hana_system_password]} -i ${VM_METADATA[sap_hana_instance_number]} -I /root/.deploy/hdbconfig.sql -O /dev/null"
  bash -c "source /usr/sap/*/home/.sapenv.sh && hdbsql -u SYSTEM -p ${VM_METADATA[sap_hana_system_password]} -i ${VM_METADATA[sap_hana_instance_number]} -I /root/.deploy/hdbconfig.sql -O /dev/null"

  ## enable fencing
  hdb::set_parameters global.ini storage partition_*_*__fencing enabled

  main::complete
}

hdbso::restart() {
  main::errhandle_log_info "Restarting SAP HANA"
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function StopSystem HDB
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function WaitforStopped 400 2 HDB
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function StartSystem HDB
  /usr/sap/hostctrl/exe/sapcontrol -nr "${VM_METADATA[sap_hana_instance_number]}" -function WaitforStarted 400 2 HDB
}
