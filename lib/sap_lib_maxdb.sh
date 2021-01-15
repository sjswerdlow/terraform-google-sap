
maxdb::create_filesystems() {
  main::errhandle_log_info "Creating filesytems for MaxDB"
  main::create_filesystem /sapdb/"${VM_METADATA[sap_maxdb_sid]}" maxdbroot xfs
  main::create_filesystem /sapdb/"${VM_METADATA[sap_maxdb_sid]}"/sapdata maxdbdata xfs
  main::create_filesystem /sapdb/"${VM_METADATA[sap_maxdb_sid]}"/saplog maxdblog xfs
  main::create_filesystem /maxdbbackup maxdbbackup xfs
}
