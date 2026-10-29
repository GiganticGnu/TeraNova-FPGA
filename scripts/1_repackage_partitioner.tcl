# -----------------------------------------------------------------------------
# 1_repackage_partitioner.tcl
# Re-packages matrix_partitioner_B from the newest VHDL (recovered from the
# project's ipshared folder) with core revision 4, so Vivado offers a real
# upgrade instead of the downgrade to the old Rev. 1 from the zip.
# Run in the Vivado Tcl console with S7_integration.xpr open:
#   source C:/PLD/scripts/1_repackage_partitioner.tcl
# -----------------------------------------------------------------------------
set comp C:/PLD/ip_repo/matrix_partitioner_B/component.xml
if {![file exists $comp]} { error "Not found: $comp" }

ipx::open_core $comp
set core [ipx::current_core]
puts "Old core revision: [get_property core_revision $core]"
set_property core_revision 4 $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
ipx::unload_core $comp
puts "matrix_partitioner_B re-packaged as revision 4"

update_ip_catalog -rebuild -scan_changes
