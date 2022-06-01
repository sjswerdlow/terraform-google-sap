
db2::fix_services() {
  main::errhandle_log_info "Updating /etc/services"
  grep -v '5912/tcp\|5912/udp\|5912/stcp' /etc/services > /etc/services.new
  cp /etc/services /etc/services.bak
  mv /etc/services.new /etc/services
}


db2::create_filesystems() {
  main::errhandle_log_info "Creating file systems for IBM DB2"
  main::create_filesystem /db2/"${VM_METADATA[sap_ibm_db2_sid]}" db2sid xfs
  main::create_filesystem /db2/"${VM_METADATA[sap_ibm_db2_sid]}"/db2dump db2dump xfs
  main::create_filesystem /db2/"${VM_METADATA[sap_ibm_db2_sid]}"/sapdata db2sapdata xfs
  main::create_filesystem /db2/"${VM_METADATA[sap_ibm_db2_sid]}"/saptmp db2saptmp xfs
  main::create_filesystem /db2/"${VM_METADATA[sap_ibm_db2_sid]}"/log_dir db2log xfs
  main::create_filesystem /db2/db2"${VM_METADATA[sap_ibm_db2_sid],,}" db2home xfs
  main::create_filesystem /db2backup db2backup xfs "optional"
}
