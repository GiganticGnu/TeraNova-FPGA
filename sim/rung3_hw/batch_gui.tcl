# batch_gui.tcl -- used by run_rung3_hw.bat ... gui
# log everything, run to the end, then build the wave view
log_wave -r /
run -all
source [file join [file dirname [info script]] rung3_waves.tcl]
