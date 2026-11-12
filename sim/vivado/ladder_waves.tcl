# =============================================================================
# ladder_waves.tcl  --  builds the "TeraNova ladder" wave view in the Vivado simulator
# Kai Janssen, Nov 2026, Vivado 2025.1.1
#
# Runs by itself after Run Behavioral Simulation (xsim.simulate.tcl.post),
# or by hand in the Tcl Console while a simulation of tb_ladder is open:
#     source C:/PLD/sim/vivado/ladder_waves.tcl
# All signals are logged from time 0 (log_all_signals / log_wave -r /), so the
# waves show the whole run even though they are added after it.
#
# Layout
#   Overview          start, and per rung: busy (= PL run time), done, cycle counter
#   Rung 0 .. Rung 4  the inside of each rung: partitioner state and block
#                     counters, the handshakes between the blocks, the AXI
#                     write channel (and for rung 4 the AXI read channel)
# Markers are placed where each rung raises done.
# =============================================================================

set tn_names {
    "Rung 0 - baseline"
    "Rung 1 - partitioner v5b (pipelined fetch)"
    "Rung 2 - writer fix (overlapped responses)"
    "Rung 3 - partitioner v6 (on-chip copy, reuse)"
    "Rung 4 - burst data path (AXI read)"
}

# add one signal; a missing signal gives a warning instead of stopping the script
proc tn_add {grp path {radix ""} {name ""}} {
    set cmd [list add_wave -into $grp]
    if {$radix ne ""} { lappend cmd -radix $radix }
    if {$name  ne ""} { lappend cmd -name  $name }
    lappend cmd $path
    if {[catch $cmd msg]} { puts "ladder_waves: skipped $path ($msg)" }
}

# a fresh wave window of its own
if {[catch {create_wave_config "TeraNova ladder"} msg]} {
    puts "ladder_waves: could not create a new wave configuration ($msg), using the current one"
}
set cfg [current_wave_config]

# ------------------------------------------------------------------ overview
set ov [add_wave_group "Overview - one 50x50 multiplication per rung"]
tn_add $ov /tb_ladder/rst
tn_add $ov /tb_ladder/start
for {set r 0} {$r < 5} {incr r} {
    tn_add $ov /tb_ladder/r$r/busy      "" "busy  rung $r"
}
for {set r 0} {$r < 5} {incr r} {
    tn_add $ov /tb_ladder/r$r/pl_cycles "" "cycles rung $r"
}
tn_add $ov /tb_ladder/all_checked "" "all results checked"

# ------------------------------------------------------------------ per rung
for {set r 0} {$r < 5} {incr r} {
    set u /tb_ladder/r$r
    set g [add_wave_group [lindex $tn_names $r]]

    set gp [add_wave_group -into $g "Partitioner"]
    tn_add $gp $u/part/state
    if {$r < 4} {
        tn_add $gp $u/addrA unsigned "BRAM address A"
    } else {
        tn_add $gp $u/r_arvalid "" "AXI read ARVALID"
        tn_add $gp $u/r_arready "" "AXI read ARREADY"
        tn_add $gp $u/r_araddr  hex "AXI read ARADDR"
        tn_add $gp $u/r_arlen   unsigned "AXI read ARLEN"
        tn_add $gp $u/r_rvalid  "" "AXI read RVALID"
        tn_add $gp $u/r_rlast   "" "AXI read RLAST"
    }
    tn_add $gp $u/part/i_blk
    tn_add $gp $u/part/j_blk
    tn_add $gp $u/part/p_blk

    set gh [add_wave_group -into $g "Handshakes between the blocks"]
    tn_add $gh $u/p_valid "" "pair valid  (partitioner -> multiplier)"
    tn_add $gh $u/p_ready "" "pair ready  (multiplier free)"
    tn_add $gh $u/m_valid "" "product valid (multiplier -> accumulator)"
    tn_add $gh $u/c_valid "" "block valid (accumulator -> writer)"
    tn_add $gh $u/c_ready "" "block read  (writer takes it)"
    tn_add $gh $u/blocks_written "" "output blocks written"

    set gw [add_wave_group -into $g "Writer - AXI write channel"]
    tn_add $gw $u/awvalid
    tn_add $gw $u/awready
    tn_add $gw $u/awaddr hex
    tn_add $gw $u/awlen  unsigned
    tn_add $gw $u/wvalid
    tn_add $gw $u/wready
    tn_add $gw $u/wlast
    tn_add $gw $u/bvalid
    tn_add $gw $u/bready
    tn_add $gw $u/done
}

# ------------------------------------------------------------------ markers
# t_done_ns is the time (ns) at which the rung saw done; 0 if it never finished
for {set r 0} {$r < 5} {incr r} {
    if {[catch {
        set t [get_value /tb_ladder/r$r/t_done_ns]
        if {$t > 0} { add_wave_marker -into $cfg -name "rung $r done" $t ns }
    } msg]} { puts "ladder_waves: no marker for rung $r ($msg)" }
}

# keep the layout for next time (File > Simulation Waveform > Open Configuration)
catch {save_wave_config [file join [file dirname [info script]] ladder.wcfg]}
puts "ladder_waves: wave view ready - press 'Zoom Fit' in the wave window toolbar to see the whole run"
