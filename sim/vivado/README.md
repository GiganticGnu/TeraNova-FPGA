# TeraNova improvement ladder in the Vivado simulator (XSim)

Simulation-only setup (Nov 2026). Runs all five rungs **side by side in one
Vivado simulation**: same clock, same start pulse, so in the wave window you
see directly how much sooner each rung finishes. No licence needed (no synthesis).

| File | What it is |
|---|---|
| `create_ladder_project.tcl` | Creates the Vivado project `project/teranova_ladder.xpr`. In the Vivado Tcl Console: `source C:/PLD/sim/vivado/create_ladder_project.tcl`, then *Run Simulation > Run Behavioral Simulation* |
| `ladder_waves.tcl` | Builds the wave view (overview + one group per rung, markers at every *done*). Runs by itself after the simulation |
| `run_ladder_batch.bat` | Same simulation without a project: `run_ladder_batch.bat [L] [gui]` (xvhdl, xelab, xsim) |
| `batch_gui.tcl` | Used by `run_ladder_batch.bat ... gui` |
| `src/tb_ladder.vhd` | Top level: five `rung_core` instances (libraries `rung0`..`rung4`), prints the summary table |
| `src/rung_core_bram.vhd` | One rung, rungs 0-3 (copy of `sim/tb_chain_rtl.vhd` with ports and a built-in result check) |
| `src/rung_core_axi.vhd` | One rung, rung 4 (copy of `sim/tb_chain_axi.vhd`, same changes) |
| `src/axi_mem_model_v.vhd`, `src/axi_rd_mem_model_v.vhd` | Memory models with a read-back port / built-in data instead of files |
| `src/tn_pkg.vhd` | Hello data set (as in `helloworld.c`) and the exact expected result |

The design RTL is **not** copied into `src/`: the scripts take it from `C:\PLD\sim`
(same files as `ladder.json`). `project/`, `lib/` and `batch/` are generated
and can be deleted at any time.

Expected summary (identical to `sim/ladder.md`, checked with GHDL):

    L = 20 : 101186 / 27186 / 27071 / 10052 / 10073 cycles, all PASS
    L = 100: 101586 / 58576 / 27151 / 18052 / 18153 cycles, all PASS
