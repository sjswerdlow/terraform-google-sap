
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


hdb::config_hdx_parameters() {
  if [[ "${VM_METADATA[sap_hana_data_disk_type]}" = "hyperdisk-extreme" ]]; then

    main::errhandle_log_info 'Setting HANA Parameters for hyperdisk-extreme disks'
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
  if [[ ! "${VM_METADATA[sap_hana_scaleout_nodes]}" = "0" \
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
  if [ ! "${VM_METADATA[sap_hana_scaleout_nodes]}" = "0" ]; then
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
