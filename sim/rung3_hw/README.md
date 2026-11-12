# Rung 3 on the board model: where does C go wrong, and how long does each stage take?

Kai Janssen, 10 Nov 2026. Simulation only, so no licence is needed (Vivado XSim 2025.1.1, also GHDL).

## Why
On the ZCU102, Badr ran rung 3 (branch `partitioner-v6`) and measured **123 µs** with -O0. But all 2500 values of C read back as **0**.
The ladder testbench (`sim/vivado`) had not caught this, so it is worth knowing what that testbench simplifies:
it gives RAM_INTERFACE `DDR = 0`, decodes only `awaddr(31 downto 3) mod 2500`, runs only one start, and leaves out the block-design glue.

`tb_rung3_hw` follows the board instead:

| Taken from the real build (branch partitioner-v6) | Modelled |
|---|---|
| RTL of every IP exactly as packaged in `ip_repo` (partitioner v6, MatMul5x5_PAR_IF, Accumulator NUM_ACC=10, matrix_to_ports, RAM_INTERFACE writer fix) | PS side: CPU access times, interrupt latency (generics) |
| BD wiring: `mult_gen` x4 on the BRAM addresses, Part0/1 = A hi/lo, Part3/2 = B hi/lo, ilconcat (C0 = LSB), `DDR_BASEADDRESS = 0x4_0000_0000` | SmartConnect + DDR4: full 64-bit address decode (512 MB segment, DECERR outside), write-response latency `LAT` |
| BRAM settings from the .xci (8192 x 32, BRAM-controller byte addressing, read latency 1) | |
| `toggle2pulse` (pulse_width 105), done to the GIC on a rising edge, 2 back-to-back runs as in `helloworld.c` | |

A golden model checks the data at every stage, in this order:
**BRAM → partitioner → multiplier → accumulator → AXI address → AXI data → AXI response → C read back**.
The first stage that shows errors is where things go wrong. Before each run, C is filled with `0xDEADBEEFDEADBEEF`, so the report can tell "never written" apart from "written as 0".

## Result 1: the design itself is correct
`results/rung3_real_design.log`: both runs pass 2500/2500, with 0 errors at every stage. This includes the real `0x4_0000_0000` address and the 4 KB burst splits that the HLS m_axi adapter makes (AXI rule).

What the simulation predicts for each possible cause (what-if runs, `results/whatif_*.log`):

| Cause | First wrong stage | C after the run | PL time |
|---|---|---|---|
| none (real design) | – | correct | 120.5 µs at LAT 40 |
| PL reads empty BRAMs (CPU writes did not reach the BRAMs the PL reads) | 1 BRAM → partitioner | **written as 0** | unchanged |
| writer address not in DDR4 (`DDR` input wrong / other bitstream) | 7 BRESP = DECERR | **never written** (stays at whatever the CPU put there) | probably shorter (a DECERR comes back in a few cycles, ~86 µs); the model keeps LAT |
| BRAM read latency 2 | 1 (shifted by one element) | wrong, but **not 0** | unchanged |

The application clears C to **0** before each run. That makes "written as 0" and "never written" look exactly the same on the board (`whatif_app_fill_0_brams_empty.log`).

**Timing as a clue:** the PL time depends almost linearly on the DDR4 write-response latency (panel c of the figure). Badr's 123 µs (including the interrupt) matches about 40 cycles of real DDR4 latency. That points to writes that reached the DDR4, i.e. **zeros were written**, so the PL saw A and B as 0. It argues against writes that went nowhere. This is an inference, not a proof. The board checks below settle it.

## Board checks, in order (each is quick)
1. **Make sure the app and bitstream match.** Use rung-3 hardware (`partitioner-v6`) with the rung-3 `helloworld.c` from that branch. Check that `_ide/bitstream/*.bit` has the date of the build. The `C:\PLD` Vitis app is currently the **rung-4** version, which reads A/B from PS DDR and writes C to `0x8_0000_A000`. Mixing rung 3 and rung 4 gives exactly "all zeros".
2. **In `run_once()`, fill C with `0xDEADBEEFDEADBEEF` instead of 0.** If C is still DEADBEEF afterwards, the writes did not land. If it is 0, the PL computed with A = B = 0.
3. **If it is 0:** use the system ILA that is already in the design (probes 2-5 = BRAM `doutb`, 7/8 = BRAM addresses). Trigger on the start pulse (probe 1). During the first 2500 cycles, the A/B values should count up 1, 2, 3, ...

## Result 2: time per stage (`results/rung3_stage_timing.png`)
One run at LAT = 40 cycles. The CPU parts are an estimate (150 ns per BRAM write, 300 ns per DDR4 read) until the `CSV,probe` values from the board are filled in.

| Stage | Time | Source |
|---|---:|---|
| CPU writes A, B into the BRAMs (10 000 x 32 bit) | 1500 µs | model |
| Start: GPIO → toggle2pulse → partitioner | 0.18 µs | model + RTL |
| PL: on-chip copy of A, B (2500 elements) | 25.1 µs | RTL |
| PL: multiply + accumulate (1000 block pairs) | 94.2 µs | RTL |
| PL: last product → last C block → last write response → done | 1.3 µs | RTL |
| **PL total (start → done)** | **120.5 µs** | RTL |
| Interrupt latency | 1 µs | model |
| CPU reads C back (2500 x 64 bit) | 750 µs | model |

Inside the PL (12 056 cycles): the multiplier is busy for 8 422 cycles. For 3 853 cycles the accumulator has a finished C block waiting for the writer, because RAM_INTERFACE collects the 5 write responses of **every** block before it accepts the next one.
That is why the PL time grows by 100 x LAT: 86 µs at LAT 5, 101 at 20, 121 at 40, 181 at 100.
The next improvement for the PL is therefore the writer: do not wait for responses per block, only count them at the end (expected about 86 µs, whatever the latency).
End to end, the CPU's single BRAM writes and DDR4 reads dominate. Rung 4 (burst data path) targets exactly that.

## How to run
* **Vivado GUI (easiest):** in the Tcl Console on the start page: `source C:/PLD/sim/rung3_hw/create_rung3_project.tcl`. This creates the project, runs the simulation and opens the wave view.
* Vivado without the GUI: in a "Vivado 2025.1.1 Tcl Shell" (not the Tcl Console inside Vivado), run `C:\PLD\sim\rung3_hw\run_rung3_hw.bat` (report in `batch\xsim_L40.log`).
  `run_rung3_hw.bat 40 gui` opens the wave view. The top row `stage` shows by name which stage is running, and there are markers at every stage boundary.
  The group **VALUES** shows A, B and C as decimal numbers: what comes out of the BRAMs, the 5x5 blocks into the multiplier, every C block, every C value written to DDR4 and every value the CPU reads back (expected: A(i,j) = 50i+j+1, B(i,j) = 50i+j+2, C(0,0) = 2 085 050).
  `run_rung3_hw.bat whatif` runs the three what-if cases.
* Generics: `LAT`, `N_RUNS`, `T_BRAM_WR_NS`, `T_DDR_RD_NS`, `T_GPIO_NS`, `T_IRQ_NS` (put the measured probe values here), `DDR_BASE_HI`, `CPU_LOADS_BRAM`, `BRAM_LAT`, `FILL_POISON`.
* Figure: `python make_stage_figure.py batch\xsim_L40.log results\latency_sweep.csv`
* Design RTL comes from `C:\PLD\sim` (`variants\matrix_partitioner_B_v6.vhd`, `steps\2_writer_fix\hls_rtl`). These files are identical to `ip_repo` on branch partitioner-v6, so the folder works from any branch.
