# =============================================================================
# create_rung3_project.tcl  --  rung 3 board model in the Vivado GUI
# Kai Janssen, Nov 2026, Vivado 2025.1.1 (simulation only, no licence needed)
#
# In the Vivado Tcl Console (start page, no project open):
#     source C:/PLD/sim/rung3_hw/create_rung3_project.tcl
# It creates a simulation-only project in C:/PLD/sim/rung3_hw/project,
# starts the behavioral simulation and builds the wave view by itself
# (rung3_waves.tcl). Text report: Tcl Console / simulate.log.
#
# Change settings afterwards, then Run Simulation again, e.g.:
#     set_property generic {LAT=40 N_RUNS=2} [get_filesets sim_1]
# =============================================================================
set here [file normalize [file dirname [info script]]]
set sim  [file normalize [file join $here ..]]
set rtl  [file join $sim steps 2_writer_fix hls_rtl]
set projdir [file join $here project]

if {[llength [get_projects -quiet]] > 0} { close_project }
file delete -force $projdir
create_project rung3_hw $projdir
set_property target_language VHDL [current_project]
catch {set_property simulator_language VHDL [current_project]}
set_property source_mgmt_mode DisplayOnly [current_project]

# compile order = order below (leaf units first)
set files [list \
    [file join $sim MatMul5x5.vhd] \
    [file join $sim MatMul5x5_IF_IN.vhd] \
    [file join $sim MatMul5x5_Accumulator.vhd] \
    [file join $sim matrix_to_ports.vhd] \
    [file join $sim variants matrix_partitioner_B_v6.vhd] \
    [file join $rtl RAM_INTERFACE_RAM_INTERFACE_Pipeline_BEATS.vhd] \
    [file join $rtl RAM_INTERFACE_RAM_INTERFACE_Pipeline_REQUESTS.vhd] \
    [file join $rtl RAM_INTERFACE_RAM_INTERFACE_Pipeline_RESPONSES.vhd] \
    [file join $rtl RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd] \
    [file join $rtl RAM_INTERFACE_gmem_m_axi.vhd] \
    [file join $rtl RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd] \
    [file join $rtl RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd] \
    [file join $rtl RAM_INTERFACE.vhd] \
    [file join $here src toggle2pulse.vhd] \
    [file join $here src hw_pkg.vhd] \
    [file join $here src bram_tdp_model.vhd] \
    [file join $here src axi_ddr_model.vhd] \
    [file join $here src tb_rung3_hw.vhd] ]
foreach f $files { if {![file exists $f]} { error "Missing $f" } }

set fs [get_filesets sim_1]
add_files -fileset $fs -norecurse $files
set_property file_type {VHDL 2008} [get_files -of_objects $fs $files]
set_property top tb_rung3_hw $fs
set_property generic {LAT=40 N_RUNS=1} $fs
set_property -name {xsim.simulate.runtime}         -value {-all} -objects $fs
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects $fs
set_property -name {xsim.simulate.tcl.post} -value [file join $here rung3_waves.tcl] -objects $fs

puts "Project created. Starting the behavioral simulation (compile + run ~2.5 ms simulated time)..."
launch_simulation
