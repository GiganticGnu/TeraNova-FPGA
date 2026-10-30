# -----------------------------------------------------------------------------
# 6_burst_datapath.tcl
# Ladder step 4_burst_datapath (simulated 30 Oct 2026): A, B and C live in the
# PS DDR. The partitioner (v7) reads A and B itself in bursts, RAM_INTERFACE
# writes C there, both through ONE high-performance port of the PS (S_AXI_HP0).
# The CPU no longer writes 10 000 BRAM words, and reads C from cached PS DDR.
#
# What this script changes in accu_to_DDR.bd (and nothing else):
#   removes  Part0..3 (BRAMs), axi_bram_ctrl_0..3, smartconnect_0,
#            mult_gen_0/1, ReadEnable, WriteEnable, matrix_partitioner_B_0
#   adds     partitioner_v7_0  (RTL module reference, C:/PLD/hdl/partitioner_v7.vhd)
#            A_BASE / B_BASE   constants 0x8_0000_0000 / 0x8_0000_5000
#            axi_smc_hp0       SmartConnect: partitioner (read) + RAM_INTERFACE (write) -> HP0
#            ila_zero          constant 0 for the ILA probes that watched the BRAMs
#   changes  PS: S_AXI_HP0_FPD on, 128 bit, clocked by the same 100 MHz PL clock
#            DDR_BASEADDRESS 0x4_0000_0000 (PL DDR4) -> 0x8_0000_A000 (C in PS DDR)
#            axi_smc: 2 -> 1 slave port (only the CPU path to the PL DDR4 is left)
#            axi_smc_1: 2 -> 1 master port (only the GPIO is left)
#   keeps    the clock (ddr4_0/addn_ui_clkout1, 100 MHz) and the resets, the
#            DDR4 MIG, GPIO, toggle2pulse, interrupt, Cezars_pin_paradise,
#            RAM_INTERFACE (writer-fix version), the top-level ports.
#            The clock is deliberately NOT changed, so this rung only measures
#            the data-path change.
#
# Needs no licence. Run ONLY on git branch "burst-datapath", in the Vivado
# 2025.1.1 Tcl console with S7_integration.xpr open:
#   source C:/PLD/scripts/6_burst_datapath.tcl
# -----------------------------------------------------------------------------
set root   C:/PLD
set hdl    $root/hdl/partitioner_v7.vhd
set branch_needed burst-datapath

# PS DDR buffers (must match the application, helloworld_burst.c)
set A_ADDR 0x800000000
set B_ADDR 0x800005000
set C_ADDR 0x80000A000

# --- safety: only Vivado 2025.1.1 (2025.1 locks every IP of this project) ---
set vivado_dir ""
catch {set vivado_dir $::env(XILINX_VIVADO)}
if {![string match "*2025.1.1*" $vivado_dir]} {
    error "This is not Vivado 2025.1.1 (running from '$vivado_dir'). Close it without saving and start C:/Xilinx/2025.1.1/Vivado/bin/vivado.bat. Nothing was changed."
}
puts "Vivado: $vivado_dir (ok)"

# --- safety: never change Baseline 1 or an earlier rung ---------------------
if {[catch {exec git -C $root rev-parse --abbrev-ref HEAD} branch]} {
    puts "WARNING: could not ask git for the current branch ($branch)."
    puts "         Make sure you are on branch $branch_needed before continuing."
} elseif {$branch ne $branch_needed} {
    error "You are on git branch '$branch'. Switch to $branch_needed first. Nothing was changed."
} else {
    puts "Git branch: $branch (ok)"
}
if {![file exists $hdl]} { error "Not found: $hdl. Nothing was changed." }

# --- 1. the v7 source as a design source (for the module reference) ---------
if {[llength [get_files -quiet $hdl]] == 0} {
    add_files -norecurse -fileset sources_1 $hdl
}
# plain VHDL: Vivado does not allow a VHDL-2008 file as the top of a module
# reference (the file is VHDL-93 compatible, checked with GHDL --std=93c)
set_property file_type {VHDL} [get_files $hdl]
update_compile_order -fileset sources_1
puts "Added $hdl to the design sources"

open_bd_design [get_files accu_to_DDR.bd]

# must already be in the design (sanity check that this is the right BD)
foreach c {zynq_ultra_ps_e_0 ddr4_0 rst_ps8_0_99M toggle2pulse_0 Cezars_pin_paradise
           RAM_INTERFACE_0 DDR_BASEADDRESS axi_smc axi_smc_1 axi_gpio_0 system_ila_0
           matrix_partitioner_B_0} {
    if {[llength [get_bd_cells -quiet /$c]] == 0} {
        error "Block design cell $c not found - is this the partitioner-v6 design? Nothing was changed."
    }
}

# create the new partitioner FIRST: if Vivado cannot make it, stop before
# anything has been removed (the block design is then still unchanged)
if {[llength [get_bd_cells -quiet /partitioner_v7_0]] == 0} {
    if {[catch {create_bd_cell -type module -reference partitioner_v7 partitioner_v7_0} msg]} {
        error "Could not create partitioner_v7_0 ($msg). The block design was NOT changed: close it without saving."
    }
}
puts "Created partitioner_v7_0 (module reference to $hdl)"
set ifs [get_bd_intf_pins -quiet partitioner_v7_0/m_axi_rd]
if {$ifs eq ""} {
    error "partitioner_v7_0 has no AXI interface m_axi_rd. The block design was NOT changed except for this new cell: close it without saving."
}
puts "partitioner_v7_0/m_axi_rd recognised as [get_property VLNV $ifs] ([get_property MODE $ifs])"

# remember the GPIO address so it stays the same
set ps_data  [get_bd_addr_spaces zynq_ultra_ps_e_0/Data]
set gpio_seg [get_bd_addr_segs -quiet -of_objects $ps_data -filter {NAME =~ *axi_gpio_0*}]
set gpio_off ""; set gpio_rng ""
if {$gpio_seg ne ""} {
    set gpio_off [get_property OFFSET $gpio_seg]
    set gpio_rng [get_property RANGE  $gpio_seg]
    puts "GPIO is at $gpio_off (range $gpio_rng)"
}

# the clock / reset nets everything in the PL already uses
set clk_pin   [get_bd_pins ddr4_0/addn_ui_clkout1]
set rst_pin   [get_bd_pins rst_ps8_0_99M/peripheral_reset]
set rstn_pin  [get_bd_pins rst_ps8_0_99M/peripheral_aresetn]

# --- 2. remove the BRAM data path --------------------------------------------
set gone {matrix_partitioner_B_0 Part0 Part1 Part2 Part3
          axi_bram_ctrl_0 axi_bram_ctrl_1 axi_bram_ctrl_2 axi_bram_ctrl_3
          smartconnect_0 mult_gen_0 mult_gen_1 ReadEnable WriteEnable}
foreach c $gone {
    set cell [get_bd_cells -quiet /$c]
    if {$cell ne ""} { delete_bd_objs $cell; puts "removed $c" }
}
# nets left without a driver (they only connected removed cells)
foreach n [get_bd_nets -quiet] {
    if {[llength [get_bd_pins -quiet -of_objects $n]] + [llength [get_bd_ports -quiet -of_objects $n]] <= 1} {
        delete_bd_objs $n
    }
}

# axi_smc_1 only feeds the GPIO now: one master port
set ic [get_bd_intf_nets -quiet -of_objects [get_bd_intf_pins axi_gpio_0/S_AXI]]
if {$ic ne ""} { delete_bd_objs $ic }
set_property CONFIG.NUM_MI 1 [get_bd_cells axi_smc_1]
connect_bd_intf_net [get_bd_intf_pins axi_smc_1/M00_AXI] [get_bd_intf_pins axi_gpio_0/S_AXI]

# RAM_INTERFACE leaves the PL DDR4 path; axi_smc keeps only the CPU (HPM0)
set ram_if [get_bd_intf_pins RAM_INTERFACE_0/m_axi_gmem]
set ic [get_bd_intf_nets -quiet -of_objects $ram_if]
if {$ic ne ""} { delete_bd_objs $ic }
set_property CONFIG.NUM_SI 1 [get_bd_cells axi_smc]

# --- 3. PS: high-performance slave port HP0, 128 bit -------------------------
set_property -dict [list CONFIG.PSU__USE__S_AXI_GP2 {1} CONFIG.PSU__SAXIGP2__DATA_WIDTH {128}] \
    [get_bd_cells zynq_ultra_ps_e_0]
connect_bd_net $clk_pin [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk]
puts "PS: S_AXI_HP0_FPD enabled (128 bit, 100 MHz PL clock)"

# --- 4. the new partitioner (cell created at the start) ---------------------------
connect_bd_net $clk_pin [get_bd_pins partitioner_v7_0/clk]
connect_bd_net $rst_pin [get_bd_pins partitioner_v7_0/rst]
connect_bd_net [get_bd_pins toggle2pulse_0/pulse]           [get_bd_pins partitioner_v7_0/start]
connect_bd_net [get_bd_pins Cezars_pin_paradise/A_in]       [get_bd_pins partitioner_v7_0/data_out_A]
connect_bd_net [get_bd_pins Cezars_pin_paradise/B_in]       [get_bd_pins partitioner_v7_0/data_out_B]
connect_bd_net [get_bd_pins Cezars_pin_paradise/valid]      [get_bd_pins partitioner_v7_0/valid]
connect_bd_net [get_bd_pins Cezars_pin_paradise/ready]      [get_bd_pins partitioner_v7_0/ready]

# buffer addresses
set ca [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 A_BASE]
set_property -dict [list CONFIG.CONST_WIDTH {64} CONFIG.CONST_VAL $A_ADDR] $ca
set cb [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 B_BASE]
set_property -dict [list CONFIG.CONST_WIDTH {64} CONFIG.CONST_VAL $B_ADDR] $cb
connect_bd_net [get_bd_pins A_BASE/dout] [get_bd_pins partitioner_v7_0/a_base]
connect_bd_net [get_bd_pins B_BASE/dout] [get_bd_pins partitioner_v7_0/b_base]
set_property CONFIG.CONST_VAL $C_ADDR [get_bd_cells DDR_BASEADDRESS]

# --- 5. both masters -> SmartConnect -> HP0 ---------------------------------
set smc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc_hp0]
set_property -dict [list CONFIG.NUM_SI {2} CONFIG.NUM_MI {1} CONFIG.NUM_CLKS {1}] $smc
connect_bd_net $clk_pin  [get_bd_pins axi_smc_hp0/aclk]
connect_bd_net $rstn_pin [get_bd_pins axi_smc_hp0/aresetn]
connect_bd_intf_net [get_bd_intf_pins partitioner_v7_0/m_axi_rd] [get_bd_intf_pins axi_smc_hp0/S00_AXI]
connect_bd_intf_net $ram_if                                      [get_bd_intf_pins axi_smc_hp0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc_hp0/M00_AXI] [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# --- 6. ILA probes that watched the BRAMs: tie to 0 --------------------------
set z [create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 ila_zero]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $z
set ila [get_bd_cells system_ila_0]
foreach p {2 3 4 5 7 8} {
    catch {set_property CONFIG.C_PROBE${p}_WIDTH {1} $ila}
    set pin [get_bd_pins system_ila_0/probe$p]
    if {[llength [get_bd_nets -quiet -of_objects $pin]] == 0} {
        connect_bd_net [get_bd_pins ila_zero/dout] $pin
    }
}
# probe0 reset, 1 start, 6 ready, 9/10 data_out_A/B, 11 valid still watch the same signals

# --- 7. addresses --------------------------------------------------------------
# both masters see only the PS DDR above 32 GB ... 34 GB (DDR_HIGH, where A/B/C are)
foreach m {partitioner_v7_0 RAM_INTERFACE_0} {
    set as [get_bd_addr_spaces -of_objects [get_bd_cells $m]]
    foreach s [get_bd_addr_segs -quiet -of_objects $as] { delete_bd_objs $s }
    set hi [get_bd_addr_segs -quiet zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_HIGH]
    if {$hi ne ""} {
        assign_bd_address -target_address_space $as $hi
    } else {
        puts "NOTE: segment HP0_DDR_HIGH not found by name, assigning all HP0 segments"
        assign_bd_address -target_address_space $as
    }
    foreach s [get_bd_addr_segs -quiet -of_objects $as] {
        puts "$m sees [get_property NAME $s] at [get_property OFFSET $s] (range [get_property RANGE $s])"
    }
}
# the GPIO keeps its old address
if {$gpio_off ne "" && [llength [get_bd_addr_segs -quiet -of_objects $ps_data -filter {NAME =~ *axi_gpio_0*}]] == 0} {
    assign_bd_address -offset $gpio_off -range $gpio_rng -target_address_space $ps_data \
        [get_bd_addr_segs axi_gpio_0/S_AXI/Reg]
}
set gpio_now [get_property OFFSET [get_bd_addr_segs -of_objects $ps_data -filter {NAME =~ *axi_gpio_0*}]]
puts "GPIO is at $gpio_now (was $gpio_off)"
# any other segment that lost its address
assign_bd_address

# --- 8. check and save ----------------------------------------------------------
regenerate_bd_layout
validate_bd_design
save_bd_design
report_ip_status -name ip_status_burst_datapath
puts ""
puts "Done. Burst data path is in the block design:"
puts "  A at $A_ADDR, B at $B_ADDR, C at $C_ADDR (PS DDR, through S_AXI_HP0_FPD)"
puts "Look at the Messages tab: validate_bd_design must show no errors / critical warnings."
puts "Do NOT run Generate Output Products or synthesis here (needs the licence)."
