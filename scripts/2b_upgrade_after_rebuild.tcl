# -----------------------------------------------------------------------------
# 2b_upgrade_after_rebuild.tcl
# Use this instead of 2_update_block_design.tcl when the block design has
# ALREADY been rewired for the new RAM_INTERFACE (data_dout / data_empty_n /
# data_read) and only the IP was rebuilt (build_ip.bat) afterwards.
# The ports are unchanged, so a normal upgrade keeps all connections.
#   source C:/PLD/scripts/2b_upgrade_after_rebuild.tcl
# -----------------------------------------------------------------------------
update_ip_catalog -rebuild -scan_changes
open_bd_design [get_files accu_to_DDR.bd]

report_ip_status -name ip_status_before_upgrade

upgrade_ip [get_ips {accu_to_DDR_RAM_INTERFACE_0_1 accu_to_DDR_matrix_partitioner_B_0_0}] -log ip_upgrade.log

validate_bd_design
save_bd_design
report_ip_status -name ip_status_after_upgrade
puts "Done. Check the IP Status tab: RAM_INTERFACE_0 should no longer be locked."
