# batch_gui.tcl -- used by run_ladder_batch.bat ... gui
# log everything, run to the end, then build the ladder wave view
log_wave -r /
run -all
source [file join [file dirname [info script]] ladder_waves.tcl]
