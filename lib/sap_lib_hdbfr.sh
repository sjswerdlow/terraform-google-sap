#!/bin/bash

################################################################################
#                 Configure SAP HANA Fast Restart Option
#
# Based on HANA documentation (as of HANA 2 SPS4)
#      SAP HANA Administration Guide for SAP HANA Platform
#      -> Persistent Data Storage in the SAP HANA Database
#      -> SAP HANA Fast Restart Option
#
# CAUTION:
# The script sets up or changes HANA's fast restart configuration. This
# includes changes to directories /hana/tmpf* and /etc/fstab and HANA's
# configuration.
# Use at your own risk and test the script throuroughly in a non-production
# environment before running it in production environments.
#
# COMMENTS:
#   - Script needs to run with root privileges.
#   - Script can be run standalone or included in Google's deployment scripts
#   - During initial setup and repeat run after machine scale up (more NUMA
#     nodes: HANA needs to be up during execution of script
#   - During repeated run after machine scale down (fewer NUMA nodes): HANA
#     needs to be down and the HANA configuration has to be updated manually to
#     finalize the setup
#
# INPUTS:
#   - HANA System ID
#   - HANA credentials for SYSTEM user of tenantDB (password or secret mgr.)
#
################################################################################
STANDALONE=false
HANA_SID=""
HANA_PWD=""
HANA_NO=""

hdb_fr::usage() {
  echo -e "
Usage: ${0} [options]

\e[1;4mParameters\e[0m
  -h [HANA_SID]    | HANA SID
  -p [HANA_PWD]    | HANA password for SYSTEM user in SystemDB
  -s [SECRET_MGR]  | Secret Manager secret containing SYSTEM password for SYSTEMDB

Provide either a password or a secret. The latest version of the secret will be used.

\e[1;4mExamples\e[0m
  ${0} -h 'HAN' -p 'my_sysdb_pwd'
  ${0} -h 'HDB' -s 'my-secret'"
}

hdb_fr::log_warning() {
  if [[ ${STANDALONE} = false ]]; then
    main::errhandle_log_warning "${1}"
  else
    echo "WARNING - ${1}"
  fi
}

hdb_fr::log_info() {
  if [[ ${STANDALONE} = false ]]; then
    main::errhandle_log_info "${1}"
  else
    echo "INFO - ${1}"
  fi
}

hdb_fr::hdbsql_system_db() {
  hdb_fr::log_info "Running command: ${1}"
  bash -c "source /usr/sap/${HANA_SID^^}/home/.sapenv.sh && hdbsql -n localhost:3${HANA_NO}13 -u SYSTEM -p '${HANA_PWD}' -j \"${1}\""
}

hdb_fr::cleanup_fast_restart() {
  local num_tmpfs_dirs=${1}

  hdb_fr::log_info "Unmounting and removing existing directories in /hana/tmpfs*"
  for (( i=0; i<$num_tmpfs_dirs; i++ )) do
    umount tmpfs"${HANA_SID}${i}"
    rm -rf /hana/tmpfs"${i}"
  done

  ts="$(date +%Y%m%d_%H%M%S)"
  hdb_fr::log_info "Removing /hana/tmpfs* entries from /etc/fstab. Copy is in /etc/fstab.${ts}"
  cp /etc/fstab /etc/fstab."${ts}"
  sed -ie "/^tmpfs${HANA_SID}/d" /etc/fstab
}

################################################################################
# Main function to set up HANA Fast Restart
#
# Input parameters:
#    - HANA SID      - 3-character HANA system identifier
#    - HANA Password - Password for SYSTEM user of tenantDB
################################################################################
hdb_fr::setup_fast_restart() {
  local hana_major_version
  local hana_minor_version
  local num_hana_nodes
  local num_tmpfs_dirs
  local tmpfs_dirs
  local ts

  HANA_SID="${1^^}"
  HANA_PWD="${2}"
  HANA_NO=$(ls /usr/sap/${HANA_SID^^}/ | grep HDB | grep -o -E '[0-9]+')
  numa_nodes=$(numactl -H | grep 'available:' | awk '{print $2}')
  num_tmpfs_dirs=$(ls -d /hana/tmpfs* | wc | awk '{print $1}')
  tmpfs_dirs=""
  hana_major_version=$(su - "${HANA_SID,,}"adm HDB version | grep "version:" | awk '{ print $2 }' | awk -F "." '{ print $1 }')
  hana_minor_version=$(su - "${HANA_SID,,}"adm HDB version | grep "version:" | awk '{ print $2 }' | awk -F "." '{ print $3 }' | sed 's/^0*//')

  hdb_fr::log_info "Setting up HANA Fast Restart for system '${HANA_SID}/${HANA_NO}'."
  hdb_fr::log_info "Number of NUMA nodes is ${numa_nodes}"
  hdb_fr::log_info "Number of directories /hana/tmpfs* is ${num_tmpfs_dirs}"
  hdb_fr::log_info "HANA version ${hana_major_version}.${hana_minor_version}"

  if [[ "${hana_major_version}" -eq 1 ]] || [[ "${hana_major_version}" -eq 2 && "${hana_minor_version}" -le 40 ]]; then
    hdb_fr::log_warning "Fast Restart is only supported as of HANA 2 SPS4. Exiting."
    return
  fi

  if [[ ${numa_nodes} -eq ${num_tmpfs_dirs} ]]; then
    hdb_fr::log_info "Number of directories /hana/tmpfs* is equal to number of NUMA nodes. Assuming setup exists. Not performing any changes."
    return
  fi

  if [[ ${num_tmpfs_dirs} -eq 0 ]]; then
    hdb_fr::log_info "No directories /hana/tmpfs* exist. Assuming initial setup."
  else
    hdb_fr::log_info "Number of directories /hana/tmpfs* is not equal to number of NUMA nodes. Assuming machine was resized. Changing configuration according to current number of NUMA nodes."
    hdb_fr::cleanup_fast_restart "${num_tmpfs_dirs}"
  fi

  hdb_fr::log_info "Creating ${numa_nodes} directories /hana/tmpfs* and mounting them"
  for (( i=0; i < ${numa_nodes}; i++ )) do
    mkdir -p /hana/tmpfs"${i}"/"${HANA_SID}"
    mount tmpfs"${HANA_SID}${i}" -t tmpfs -o mpol=prefer:"${i}" /hana/tmpfs"${i}"/"${HANA_SID}"
  done

  chown -R "${HANA_SID,,}"adm:sapsys /hana/tmpfs*/"${HANA_SID}"
  chmod 777 -R /hana/tmpfs*/"${HANA_SID}"

  ts="$(date +%Y%m%d_%H%M%S)"
  hdb_fr::log_info "Adding /hana/tmpfs* entries to /etc/fstab. Copy is in /etc/fstab.${ts}"
  cp /etc/fstab /etc/fstab."${ts}"
  for (( i=0; i < ${numa_nodes}; i++ )) do
    echo "tmpfs${HANA_SID}${i} /hana/tmpfs${i}/${HANA_SID} tmpfs rw,relatime,mpol=prefer:${i} 0 0" >> /etc/fstab
  done

  hdb_fr::log_info "Updating the HANA configuration."
  for dir in $(ls -d /hana/tmpfs*/*); do
    tmpfs_dirs="${tmpfs_dirs}${dir};"
  done
  hdb_fr::hdbsql_system_db "select * from dummy"
  if [[ $? != 0 ]]; then
    hdb_fr::log_warning "Failure connecting to HANA (HANA down or wrong credentials)"
    hdb_fr::log_warning "Ensure those settings are in place to finalize the setup:"
    hdb_fr::log_warning "    global.ini -> [persistence] -> basepath_persistent_memory_volumes = ${tmpfs_dirs}"
    hdb_fr::log_warning "    global.ini -> [persistent_memory] -> table_unload_action = retain"
    hdb_fr::log_warning "    indexserver.ini -> [persistent_memory] -> table_default = ON;"
  else
    hdb_fr::hdbsql_system_db "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('persistence', 'basepath_persistent_memory_volumes') = '${tmpfs_dirs}'"
    hdb_fr::hdbsql_system_db "ALTER SYSTEM ALTER CONFIGURATION ('global.ini', 'SYSTEM') SET ('persistent_memory', 'table_unload_action') = 'retain';"
    hdb_fr::hdbsql_system_db "ALTER SYSTEM ALTER CONFIGURATION ('indexserver.ini', 'SYSTEM') SET ('persistent_memory', 'table_default') = 'ON';"
  fi
}

# If the script is run standalone - get options and call setup function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  STANDALONE=true
  hdb_fr::log_info "Script is running in standalone mode"

  while getopts 'h:p:s:l' argv; do
    case "${argv}" in
    h) HANA_SID=${OPTARG} ;;
    p) HANA_PWD=${OPTARG} ;;
    s) SECRET_MANAGER_SECRET=${OPTARG} ;;
    *) hdb_fr::usage
       exit 1;;
    esac
  done

  if [[ ! -z ${SECRET_MANAGER_SECRET} ]]; then
    HANA_PWD=$(gcloud secrets versions access latest --secret="${SECRET_MANAGER_SECRET}")
  fi

  if [[ -z ${HANA_PWD} ]]; then
    hdb_fr::usage
    exit 1
  fi

  hdb_fr::setup_fast_restart "${HANA_SID}" "${HANA_PWD}"
fi
