# -----------------------------------------------------------------------------
# install_partitioner.tcl  (generic; used by 5_partitioner_v6.tcl and later partitioner steps)
# Puts a simulated partitioner variant into the design:
#   1. copies sim/variants/matrix_partitioner_B_<variant>.vhd over the IP source
#   2. re-packages matrix_partitioner_B with the given core revision
#   3. upgrades the IP in the block design (ports unchanged -> no rewiring),
#      validates and saves
# Needs no licence. The caller sets three variables first, e.g.
#   set pv_variant v6 ; set pv_revision 6 ; set pv_branch partitioner-v6
#   source C:/PLD/scripts/install_partitioner.tcl
# -----------------------------------------------------------------------------
foreach v {pv_variant pv_revision pv_branch} {
    if {![info exists $v]} { error "Set $v before sourcing install_partitioner.tcl. Nothing was changed." }
}
set root C:/PLD
set src  $root/sim/variants/matrix_partitioner_B_${pv_variant}.vhd
set dst  $root/ip_repo/matrix_partitioner_B/matrix_partitioner_B.vhd
set comp $root/ip_repo/matrix_partitioner_B/component.xml

# --- safety: only Vivado 2025.1.1 (2025.1 locks every IP of this project) ---
set vivado_dir ""
catch {set vivado_dir $::env(XILINX_VIVADO)}
if {![string match "*2025.1.1*" $vivado_dir]} {
    error "This is not Vivado 2025.1.1 (running from '$vivado_dir'). Close it without saving and start C:/Xilinx/2025.1.1/Vivado/bin/vivado.bat. Nothing was changed."
}
puts "Vivado: $vivado_dir (ok)"

# --- safety: never change the Baseline 1 version on main ----------------------
if {[catch {exec git -C $root rev-parse --abbrev-ref HEAD} branch]} {
    puts "WARNING: could not ask git for the current branch ($branch)."
    puts "         Make sure you are on branch $pv_branch before continuing."
} elseif {$branch ne $pv_branch} {
    error "You are on git branch '$branch'. Switch to $pv_branch first. Nothing was changed."
} else {
    puts "Git branch: $branch (ok)"
}

foreach f [list $src $dst $comp] {
    if {![file exists $f]} { error "Not found: $f. Nothing was changed." }
}

# --- 1. new VHDL into the IP repository ---------------------------------------
file copy -force $src $dst
puts "Copied $pv_variant source to $dst"

# --- 2. re-package as core revision 5 -----------------------------------------
ipx::open_core $comp
set core [ipx::current_core]
puts "Old core revision: [get_property core_revision $core]"
set_property core_revision $pv_revision $core
ipx::update_checksums $core
ipx::check_integrity $core
ipx::save_core $core
ipx::unload_core $comp
puts "matrix_partitioner_B re-packaged as revision $pv_revision"
update_ip_catalog -rebuild -scan_changes

# --- 3. upgrade it in the block design ----------------------------------------
open_bd_design [get_files accu_to_DDR.bd]
set ip [get_ips accu_to_DDR_matrix_partitioner_B_0_0]
if {$ip eq ""} { error "IP accu_to_DDR_matrix_partitioner_B_0_0 not found in the block design." }
report_ip_status -name ip_status_before_$pv_variant
upgrade_ip $ip -log ip_upgrade_$pv_variant.log
validate_bd_design
save_bd_design
report_ip_status -name ip_status_after_$pv_variant
puts "Done. matrix_partitioner_B_0 should now show revision $pv_revision and be up to date."
puts "Do NOT run Generate Output Products or synthesis here (needs the licence)."
