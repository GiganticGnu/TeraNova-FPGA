# -----------------------------------------------------------------------------
# 2_update_block_design.tcl
# - upgrades matrix_partitioner_B to the re-packaged revision 4
# - replaces RAM_INTERFACE_0 with the rebuilt HLS IP (new ap_fifo handshake)
#   and wires it up:
#     dout    (Cezars_pin_paradise)  -> data_dout
#     C_valid (Cezars_pin_paradise)  -> data_empty_n
#     C_ready (Cezars_pin_paradise) <-  data_read
# Run after build_ip.bat and 1_repackage_partitioner.tcl:
#   source C:/PLD/scripts/2_update_block_design.tcl
# -----------------------------------------------------------------------------
update_ip_catalog -rebuild -scan_changes
open_bd_design [get_files accu_to_DDR.bd]

# --- matrix_partitioner_B: same ports, newer revision -----------------------
upgrade_ip [get_ips accu_to_DDR_matrix_partitioner_B_0_0] -log ip_upgrade.log

# --- RAM_INTERFACE: ports changed, so recreate the cell ---------------------
delete_bd_objs [get_bd_cells RAM_INTERFACE_0]
create_bd_cell -type ip -vlnv xilinx.com:hls:RAM_INTERFACE:1.0 RAM_INTERFACE_0

connect_bd_net [get_bd_pins ddr4_0/addn_ui_clkout1]                [get_bd_pins RAM_INTERFACE_0/ap_clk]
connect_bd_net [get_bd_pins rst_ps8_0_99M/peripheral_aresetn]      [get_bd_pins RAM_INTERFACE_0/ap_rst_n]
connect_bd_net [get_bd_pins DDR_BASEADDRESS/dout]                  [get_bd_pins RAM_INTERFACE_0/DDR]
connect_bd_net [get_bd_pins Cezars_pin_paradise/dout]              [get_bd_pins RAM_INTERFACE_0/data_dout]
connect_bd_net [get_bd_pins Cezars_pin_paradise/C_valid]           [get_bd_pins RAM_INTERFACE_0/data_empty_n]
connect_bd_net [get_bd_pins RAM_INTERFACE_0/data_read]             [get_bd_pins Cezars_pin_paradise/C_ready]
connect_bd_net [get_bd_pins RAM_INTERFACE_0/done]                  [get_bd_pins axi_gpio_0/gpio2_io_i]
connect_bd_intf_net [get_bd_intf_pins RAM_INTERFACE_0/m_axi_gmem]  [get_bd_intf_pins axi_smc/S01_AXI]

# 'done' also drives the interrupt and the ILA probe; make sure they share the net
foreach p {zynq_ultra_ps_e_0/pl_ps_irq0 Cezars_pin_paradise/probe31} {
    if {[llength [get_bd_nets -quiet -of_objects [get_bd_pins $p]]] == 0} {
        connect_bd_net [get_bd_pins RAM_INTERFACE_0/done] [get_bd_pins $p]
    }
}

# --- address map: result memory = PL DDR4 at 0x4_0000_0000 ------------------
assign_bd_address -target_address_space [get_bd_addr_spaces RAM_INTERFACE_0/Data_m_axi_gmem] \
    [get_bd_addr_segs ddr4_0/C0_DDR4_MEMORY_MAP/C0_DDR4_ADDRESS_BLOCK] -force
set seg [get_bd_addr_segs RAM_INTERFACE_0/Data_m_axi_gmem/*]
set_property offset 0x400000000 $seg
set_property range 512M $seg

validate_bd_design
save_bd_design
report_ip_status -name ip_status_after_update
puts "Block design updated. Check the IP Status tab: everything should be up to date."
