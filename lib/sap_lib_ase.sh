
ase::create_filesystems() {
  main::errhandle_log_info "Creating file systems for SAP ASE"
  main::create_filesystem /sybase/"${VM_METADATA[sap_ase_sid]}" asesid xfs
  main::create_filesystem /sybase/"${VM_METADATA[sap_ase_sid]}"/sapdata_1 asesapdata xfs
  main::create_filesystem /sybase/"${VM_METADATA[sap_ase_sid]}"/loglog_1 aselog xfs
  main::create_filesystem /sybase/"${VM_METADATA[sap_ase_sid]}"/saptemp asesaptemp xfs
  main::create_filesystem /sybase/"${VM_METADATA[sap_ase_sid]}"/sapdiag asesapdiag xfs
  main::create_filesystem /sybasebackup asebackup xfs
}



