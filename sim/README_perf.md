# Performance and full-RTL simulation (added 29 Oct 2026)

New files next to the original `tb_chain` testbench. The design files are unchanged.

| File | What it is |
|---|---|
| `tb_chain_perf.vhd`, `run_perf.py` | `tb_chain` + passive monitors on every valid/ready handshake; prints `PERF key=value` lines (cycles per stage, stalls, busy time) |
| `tb_chain_rtl.vhd`, `run_rtl.py` | Data path with the **real** Vitis-HLS `RAM_INTERFACE` RTL writing through `m_axi` into `axi_mem_model.vhd`; ends when `done` rises |
| `axi_mem_model.vhd` | AXI4 write slave: 4 outstanding addresses, byte strobes, write response `B_LATENCY` cycles after `WLAST`, optional `WREADY` throttling (`W_STALL_N`); counts bursts/beats |
| `hls_rtl/` | Copy of `hls/RAM_INTERFACE/work/hls/impl/vhdl` (7 Oct). One line in `RAM_INTERFACE_gmem_m_axi.vhd` is marked `SIM PATCH`: a VHDL-2019 conditional constant rewritten as a VHDL-2008 function call (same value) so GHDL accepts it |
| `run_all.py` | Compiles everything and runs all 31 GHDL cases (~12 min), writes `results.json`, ends with `ALL PASS` |
| `make_figures.py` | Draws the two report figures from `results.json` (needs matplotlib) |

    cd /d C:\PLD\sim
    python run_all.py
    python run_perf.py hello 30      # data set (hello|random), writer-model busy cycles per block
    python run_rtl.py random 20 0    # data set, B_LATENCY, W_STALL_N

Key results (see `report/simulation_report`):
* PL run 101 008 cycles with the writer model, 101 186 cycles with the real RTL (L = 20): 1.012 ms at 100 MHz
* partitioner: one block pair every 101 cycles (25 elements x 4 states + 1); multiplier busy 5 000 cycles (4.95 %)
* real `RAM_INTERFACE`: 504 bursts of 1-5 beats; waits for the write response after every row,
  so 79 + 5L cycles per block; becomes the bottleneck for L > 186 cycles today, L > 36 once the partitioner reads 1 element/cycle

## Partitioner variants (added 29 Oct 2026, afternoon)

| File | What it is |
|---|---|
| `variants/matrix_partitioner_B_v5a.vhd` | rev. 4 with WAIT1/WAIT2 removed (2 cycles per element) |
| `variants/matrix_partitioner_B_v5b.vhd` | pipelined fetch: one address per cycle, capture 2 edges later (1 cycle per element) |
| `run_variants.py` | builds each version (rev4, v5a, v5b) in `build_<name>/` and runs the chain, perf, real-RTL, restart and latency-sweep tests; `variants_results.json` |

    python run_variants.py          # all three (~30 min on 2 cores)
    python run_variants.py v5b      # one version

Results: PL run (real RAM_INTERFACE, L = 20) 101 186 / 51 186 / 27 186 cycles (1.00x / 1.98x / 3.72x);
writer keeps up while 85 + 5L <= block interval: L <= 185 / 85 / 37 cycles. All tests PASS, incl. restart without reset.
`tb_chain_rtl.vhd` now has a generic RUNS (2 = second complete run without reset) and `axi_mem_model.vhd` a `clear` input.
