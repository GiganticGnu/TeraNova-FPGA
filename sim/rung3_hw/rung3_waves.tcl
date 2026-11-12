# =============================================================================
# rung3_waves.tcl  --  wave view for tb_rung3_hw (Vivado simulator)
# Kai Janssen, Nov 2026, Vivado 2025.1.1
#
# Runs by itself from run_rung3_hw.bat ... gui, or by hand in the Tcl Console
# while a tb_rung3_hw simulation is open:  source C:/PLD/sim/rung3_hw/rung3_waves.tcl
#
# Top row "stage" shows, as text, which part of the system is busy:
#   CPU_LOAD_BRAM, CPU_CLEAR_C, START_GPIO, PL_ONCHIP_COPY, PL_MULT_ACC,
#   PL_DRAIN_WRITES, IRQ_LATENCY, CPU_READ_C, CPU_CHECK
# Markers are placed at every stage boundary of run 1.
# =============================================================================

proc r3_add {grp path {radix ""} {name ""}} {
    set cmd [list add_wave -into $grp]
    if {$radix ne ""} { lappend cmd -radix $radix }
    if {$name  ne ""} { lappend cmd -name  $name }
    lappend cmd $path
    if {[catch $cmd msg]} { puts "rung3_waves: skipped $path ($msg)" }
}

if {[catch {create_wave_config "Rung 3 on the board model"} msg]} {
    puts "rung3_waves: using the current wave configuration ($msg)"
}
set cfg [current_wave_config]
set t /tb_rung3_hw

set g [add_wave_group "Overview - which stage is running"]
r3_add $g $t/stage "" "stage"
r3_add $g $t/gpio_start "" "start GPIO (toggle)"
r3_add $g $t/pulse "" "start pulse (toggle2pulse)"
r3_add $g $t/done "" "done (RAM_INTERFACE -> IRQ, GPIO2)"
r3_add $g $t/irq_count unsigned "interrupts"

# ------------------------------------------------------------------ values
# A, B, C as decimal numbers. Expected (helloworld data):
#   A(i,j) = 50*i + j + 1   B(i,j) = 50*i + j + 2   C(0,0) = 2 085 050
set g [add_wave_group "VALUES - A, B, C (decimal)"]
r3_add $g $t/addrA12      unsigned "BRAM element index (k = 50*row + col)"
r3_add $g $t/bram_A_value unsigned "A(k) read from BRAM"
r3_add $g $t/bram_B_value unsigned "B(k) read from BRAM"
r3_add $g $t/A  unsigned "A block -> multiplier (25 elements, expand)"
r3_add $g $t/Bm unsigned "B block -> multiplier (25 elements, expand)"
r3_add $g $t/M  unsigned "A x B product of one block pair (expand)"
r3_add $g $t/C  unsigned "C block from the accumulator (expand)"
r3_add $g $t/awaddr hex  "C write address (0x4_0000_0000 + 8*index)"
r3_add $g $t/wdata unsigned "C value written to DDR4"
r3_add $g $t/rd_addr unsigned "CPU read-back: C index"
r3_add $g $t/rd_data unsigned "CPU read-back: C value"

set g [add_wave_group "1 BRAM -> partitioner"]
r3_add $g $t/part/state "" "partitioner state"
r3_add $g $t/addrA12 unsigned "BRAM word address A"
r3_add $g $t/addrb_A hex "BRAM byte address A (x4)"
r3_add $g $t/doutb hex "BRAM data (0=A hi,1=A lo,2=B lo,3=B hi)"
r3_add $g $t/err_bram unsigned "CHECK wrong BRAM reads"

set g [add_wave_group "2-4 partitioner -> multiplier -> accumulator"]
r3_add $g $t/part/i_blk unsigned
r3_add $g $t/part/j_blk unsigned
r3_add $g $t/part/p_blk unsigned
r3_add $g $t/p_valid "" "pair valid"
r3_add $g $t/p_ready "" "multiplier free"
r3_add $g $t/m_valid "" "product valid"
r3_add $g $t/c_valid "" "C block valid"
r3_add $g $t/c_ready "" "writer takes C block"
r3_add $g $t/pairs unsigned "pairs done"
r3_add $g $t/blks unsigned "C blocks done"
r3_add $g $t/err_part unsigned "CHECK wrong partitioner elements"
r3_add $g $t/err_mul unsigned "CHECK wrong products"
r3_add $g $t/err_acc unsigned "CHECK wrong C blocks"

set g [add_wave_group "5-7 writer - AXI to DDR4"]
r3_add $g $t/awvalid
r3_add $g $t/awready
r3_add $g $t/awaddr hex
r3_add $g $t/awlen unsigned
r3_add $g $t/wvalid
r3_add $g $t/wdata hex
r3_add $g $t/wlast
r3_add $g $t/bvalid
r3_add $g $t/bresp
r3_add $g $t/outstanding unsigned "bursts in flight"
r3_add $g $t/err_awaddr unsigned "CHECK wrong addresses"
r3_add $g $t/err_wdata unsigned "CHECK wrong data"
r3_add $g $t/err_bresp unsigned "CHECK error responses"

# markers at the stage boundaries of run 1 (values in ns)
foreach {sig label} {mk_load0 "CPU load" mk_gpio "GPIO start" mk_pulse "PL start"
                     mk_pair0 "first pair" mk_pairN "last pair" mk_done "done"
                     mk_isr "ISR" mk_rb0 "read-back" mk_rb1 "check"} {
    if {[catch {
        set v [get_value -radix unsigned $t/$sig]
        if {$v > 0} { add_wave_marker -into $cfg -name $label $v ns }
    } msg]} { puts "rung3_waves: no marker $label ($msg)" }
}
catch {save_wave_config [file join [file dirname [info script]] rung3.wcfg]}
puts "rung3_waves: ready - Zoom Fit shows both runs; zoom in between 'PL start' and 'done' for the PL part"
