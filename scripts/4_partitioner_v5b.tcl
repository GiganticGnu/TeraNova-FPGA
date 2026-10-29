# -----------------------------------------------------------------------------
# 4_partitioner_v5b.tcl
# Puts the pipelined partitioner (v5b, simulated 29 Oct 2026) into the design:
#   1. copies sim/variants/matrix_partitioner_B_v5b.vhd over the IP source
#   2. re-packages matrix_partitioner_B as core revision 5
#   3. upgrades the IP in the block design (ports unchanged -> no rewiring),
#      validates and saves
# Needs no licence. Run ONLY on the git branch "partitioner-v5b", in the
# Vivado Tcl console with S7_integration.xpr open:
#   source C:/PLD/scripts/4_partitioner_v5b.tcl
# -----------------------------------------------------------------------------
set root C:/PLD
set src  $root/sim/variants/matrix_partitioner_B_v5b.vhd
set dst  $root/ip_repo/matrix_partitioner_B/matrix_partitioner_B.vhd
set comp $root/ip_repo/matrix_partitioner_B/component.xml

# --- safety: never change the Baseline 1 version on main ----------------------
if {[catch {exec git -C $root rev-parse --abbrev-ref HEAD} branch]} {
    puts "WARNING: could not ask git for the current branch ($branch)."
    puts "         Make sure you are on branch partitioner-v5b before continuing."
} elseif {$branch ne "partitioner-v5b"} {
    error "You are on git branch '$branch'. Switch to partitioner-v5b first (git switch partitioner-v5b). Nothing was changed."
} else {
    puts "Git branch: $branch (ok)"
}

foreach f [list $src $dst $comp] {
    if {![file exists $f]} { error "Not found: $f. Nothing was changed." }
}

# --- 1. new VHDL into the IP repository ---------------------------------------
file copy -force $src $dst
puts "Copied v5b source to $dst"

# --- 2. re-package as core revision 5 -----------------------------------------
ipx::open_core $comp
set core [ipx::current_core]
puts "Old core revision: [get_property core_revision $core]"
set_property core_revision 5 $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
ipx::unload_core $comp
puts "matrix_partitioner_B re-packaged as revision 5"
update_ip_catalog -rebuild -scan_changes

# --- 3. upgrade it in the block design ----------------------------------------
open_bd_design [get_files accu_to_DDR.bd]
set ip [get_ips accu_to_DDR_matrix_partitioner_B_0_0]
if {$ip eq ""} { error "IP accu_to_DDR_matrix_partitioner_B_0_0 not found in the block design." }
report_ip_status -name ip_status_before_v5b
upgrade_ip $ip -log ip_upgrade_v5b.log
validate_bd_design
save_bd_design
report_ip_status -name ip_status_after_v5b
puts "Done. matrix_partitioner_B_0 should now show revision 5 and be up to date."
puts "Do NOT run Generate Output Products or synthesis here (needs the licence)."
