# =============================================================================
# create_ladder_project.tcl  --  TeraNova improvement ladder in the Vivado simulator
# Kai Janssen, Nov 2026.  Made for Vivado 2025.1.1.
#
# Creates a SIMULATION-ONLY Vivado project (no block design, no synthesis, no
# licence needed) that runs all five rungs side by side in one XSim run:
#
#   In the Vivado Tcl Console (no project open):
#       source C:/PLD/sim/vivado/create_ladder_project.tcl
#   then click  Flow Navigator > SIMULATION > Run Simulation > Run Behavioral Simulation
#
# What it does
#   * copies every rung's RTL from C:\PLD\sim into lib\rungN\ (a file can be in
#     only ONE library of a Vivado fileset, but rungs share files)
#   * adds them to sim_1, each rung in its own VHDL library rung0..rung4,
#     all files as VHDL 2008, in a fixed (manual) compile order
#   * top = tb_ladder, run time = until the end (-all), all signals logged,
#     ladder_waves.tcl is run after the simulation and builds the wave view
#
# The rung definitions are the same as in sim\ladder.json (cumulative steps).
# Re-run this script after you change a source in C:\PLD\sim: it rebuilds
# the copies and the project from scratch (project\ and lib\ are throw-away).
# =============================================================================

set here     [file normalize [file dirname [info script]]]
set sim      [file normalize [file join $here ..]]
set projname teranova_ladder
set projdir  [file join $here project]
set libdir   [file join $here lib]

puts "TeraNova ladder: Vivado [version -short], scripts in $here"
if {![string match "2025.1*" [version -short]]} {
    puts "WARNING: this script was written for Vivado 2025.1.1"
}
if {[llength [get_projects -quiet]] > 0} {
    puts "Closing the open project first"
    close_project
}

# ------------------------------------------------------------- rung file lists
# paths relative to C:\PLD\sim, in compile order (leaf units first)
set rung_files(0) {
    MatMul5x5.vhd
    MatMul5x5_IF_IN.vhd
    MatMul5x5_Accumulator.vhd
    matrix_to_ports.vhd
    matrix_partitioner_B.vhd
    hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_ROWS_COLS.vhd
    hls_rtl/RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd
    hls_rtl/RAM_INTERFACE_gmem_m_axi.vhd
    hls_rtl/RAM_INTERFACE_mac_muladd_6ns_3ns_12ns_12_4_1.vhd
    hls_rtl/RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd
    hls_rtl/RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd
    hls_rtl/RAM_INTERFACE.vhd
    vivado/src/axi_mem_model_v.vhd
    vivado/src/rung_core_bram.vhd
}
set rung_files(1) {
    MatMul5x5.vhd
    MatMul5x5_IF_IN.vhd
    MatMul5x5_Accumulator.vhd
    matrix_to_ports.vhd
    variants/matrix_partitioner_B_v5b.vhd
    hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_ROWS_COLS.vhd
    hls_rtl/RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd
    hls_rtl/RAM_INTERFACE_gmem_m_axi.vhd
    hls_rtl/RAM_INTERFACE_mac_muladd_6ns_3ns_12ns_12_4_1.vhd
    hls_rtl/RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd
    hls_rtl/RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd
    hls_rtl/RAM_INTERFACE.vhd
    vivado/src/axi_mem_model_v.vhd
    vivado/src/rung_core_bram.vhd
}
set rung_files(2) {
    MatMul5x5.vhd
    MatMul5x5_IF_IN.vhd
    MatMul5x5_Accumulator.vhd
    matrix_to_ports.vhd
    variants/matrix_partitioner_B_v5b.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_BEATS.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_REQUESTS.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_RESPONSES.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_gmem_m_axi.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE.vhd
    vivado/src/axi_mem_model_v.vhd
    vivado/src/rung_core_bram.vhd
}
set rung_files(3) {
    MatMul5x5.vhd
    MatMul5x5_IF_IN.vhd
    MatMul5x5_Accumulator.vhd
    matrix_to_ports.vhd
    variants/matrix_partitioner_B_v6.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_BEATS.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_REQUESTS.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_RESPONSES.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_gmem_m_axi.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE.vhd
    vivado/src/axi_mem_model_v.vhd
    vivado/src/rung_core_bram.vhd
}
set rung_files(4) {
    MatMul5x5.vhd
    MatMul5x5_IF_IN.vhd
    MatMul5x5_Accumulator.vhd
    matrix_to_ports.vhd
    variants/matrix_partitioner_B_v7.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_BEATS.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_REQUESTS.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_RESPONSES.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_gmem_m_axi.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd
    steps/2_writer_fix/hls_rtl/RAM_INTERFACE.vhd
    vivado/src/axi_mem_model_v.vhd
    vivado/src/axi_rd_mem_model_v.vhd
    vivado/src/rung_core_axi.vhd
}

set rung_desc(0) "baseline (restored design)"
set rung_desc(1) "partitioner v5b, pipelined fetch"
set rung_desc(2) "writer fix, overlapped write responses"
set rung_desc(3) "partitioner v6, on-chip copy + 10x reuse"
set rung_desc(4) "burst data path, PL reads A/B from PS DDR"

# check that every source exists before touching anything
set missing {}
foreach r {0 1 2 3 4} {
    foreach f $rung_files($r) {
        if {![file exists [file join $sim $f]]} { lappend missing $f }
    }
}
foreach f {vivado/src/tn_pkg.vhd vivado/src/tb_ladder.vhd vivado/ladder_waves.tcl} {
    if {![file exists [file join $sim $f]]} { lappend missing $f }
}
if {[llength $missing] > 0} {
    error "Missing source files (relative to $sim): [lsort -unique $missing]"
}

# ------------------------------------------------------------- fresh project
file delete -force $projdir $libdir
create_project $projname $projdir
set_property target_language VHDL [current_project]
catch {set_property simulator_language VHDL [current_project]}
# Manual compile order: files compile in the order they are added below.
# (Automatic ordering gets confused by five entities with the same name.)
set_property source_mgmt_mode DisplayOnly [current_project]

set fs [get_filesets sim_1]

proc add_lib_files {fs lib files} {
    set objs [add_files -fileset $fs -norecurse $files]
    set_property library   $lib       [get_files -of_objects $fs $files]
    set_property file_type {VHDL 2008} [get_files -of_objects $fs $files]
    return $objs
}

# shared package (test data, expected result)
add_lib_files $fs tn_common [list [file join $sim vivado/src/tn_pkg.vhd]]

# one library per rung, with private copies of its files
foreach r {0 1 2 3 4} {
    set dst [file join $libdir rung$r]
    file mkdir $dst
    set copies {}
    foreach f $rung_files($r) {
        set c [file join $dst [file tail $f]]
        file copy -force [file join $sim $f] $c
        lappend copies $c
    }
    add_lib_files $fs rung$r $copies
    puts [format "  rung %d  %-45s %2d files -> library rung%d" $r $rung_desc($r) [llength $copies] $r]
}

# the top level that runs all five rungs side by side
add_lib_files $fs xil_defaultlib [list [file join $sim vivado/src/tb_ladder.vhd]]

# ------------------------------------------------------------- simulation settings
set_property top tb_ladder $fs
catch {set_property top_lib xil_defaultlib $fs}
set_property generic {LAT=20} $fs
set_property -name {xsim.simulate.runtime}         -value {-all} -objects $fs
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects $fs
set_property -name {xsim.simulate.tcl.post} -value [file join $here ladder_waves.tcl] -objects $fs

puts ""
puts "Project created: [file join $projdir $projname.xpr]"
puts "Next: Flow Navigator > SIMULATION > Run Simulation > Run Behavioral Simulation"
puts "      (compiles 5 rungs, runs about 1.1 ms of simulated time; the summary"
puts "       table appears in the Tcl Console, the wave view opens by itself)"
puts "Stress latency: set_property generic {LAT=100} \[get_filesets sim_1\]  then Run Simulation again"
