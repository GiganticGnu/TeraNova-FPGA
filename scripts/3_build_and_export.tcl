# -----------------------------------------------------------------------------
# 3_build_and_export.tcl
# Generates the bitstream and exports C:/PLD/S7_integration/interrupt_rerun.xsa
# (the file the Vitis platform points to). The old XSA is backed up first.
# Takes a long time (synthesis + implementation).
#   source C:/PLD/scripts/3_build_and_export.tcl
# -----------------------------------------------------------------------------
set proj_dir [get_property DIRECTORY [current_project]]
set xsa      $proj_dir/interrupt_rerun.xsa
file mkdir C:/PLD/backup
if {[file exists $xsa]} {
    file copy -force $xsa C:/PLD/backup/interrupt_rerun_before_upgrade.xsa
}

generate_target all [get_files accu_to_DDR.bd]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "Implementation did not finish - check the Design Runs tab."
}
set wns [get_property STATS.WNS [get_runs impl_1]]
puts "Worst negative slack: $wns ns"
if {$wns < 0} { puts "WARNING: timing is NOT met - do not trust the hardware until fixed." }

write_hw_platform -fixed -include_bit -force -file $xsa
puts "Exported $xsa - now update the hardware specification in Vitis."
