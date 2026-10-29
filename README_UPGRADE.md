# Restoring the two locked IPs and making PS <-> PL robust

Goal: get the block design unlocked (so it can be validated, rebuilt and changed),
with source code we own, and an application that runs reliably end to end.

## What is in this package

| Path (under `C:\PLD`) | What it is |
|---|---|
| `hls\RAM_INTERFACE\` | **Rewritten** HLS source of `RAM_INTERFACE` + C testbench + `hls_config.cfg` + `build_ip.bat` |
| `ip_repo\matrix_partitioner_B\matrix_partitioner_B.vhd` | **Newest** partitioner VHDL, recovered from `S7_integration.gen\...\ipshared\8053` |
| `scripts\1_repackage_partitioner.tcl` | Re-packages the partitioner as revision 4 |
| `scripts\2_update_block_design.tcl` | Upgrades the partitioner, replaces and rewires `RAM_INTERFACE_0`, validates |
| `scripts\3_build_and_export.tcl` | Bitstream + exports `S7_integration\interrupt_rerun.xsa` |
| `sim\` | GHDL testbench of the complete PL data path (partitioner -> multiplier -> accumulator -> writer) |
| `S7_integration_vit\interrupt_rerun_test\src\helloworld.c` | Updated application (timing per phase, timeouts, 2 runs) |

## Why option B (rebuild from source)

* We own editable source for both IPs instead of opaque generated HDL.
* The improvement plan replaces/extends `RAM_INTERFACE` anyway (burst writes to PS DDR),
  so we need a clean HLS source to start from.
* The old handshake (`ap_none` valid/ready on a free-running block) was not a real
  protocol and could capture a block twice or miss one. The new version uses an
  `ap_fifo` stream input, which is exactly the valid/ready protocol the accumulator
  already speaks (`C_valid` -> `data_empty_n`, `C_ready` <- `data_read`).
* `matrix_partitioner_B` is plain VHDL: the newest source was still in the project,
  so it only needs re-packaging (ports are identical to the old Rev. 1).

## Verified before handing over (without the board)

* **HLS C simulation** of the new `RAM_INTERFACE` (2 complete matrices back to back,
  full 64-bit values): all 2 x 2500 words land at the right address, `done` behaves
  as intended. Result: PASS.
* **RTL simulation (GHDL)** of the whole PL path with the newest partitioner and the
  previous group's multiplier/accumulator, with a model of the new writer handshake:
  * test data from `helloworld.c`: PASS (all 2500 results correct)
  * random full-range 64-bit data: PASS (signed multiplier + unsigned accumulator
    give the correct result modulo 2^64)
  * slow writer (back-pressure, 1500 cycles per block): PASS, no lost or duplicate blocks
  * measured PL run time: **101 008 cycles** (1.01 ms at 100 MHz)

Not verified yet (needs Vitis HLS / Vivado / the board): HLS synthesis, the block
design update, timing closure, and the run on the ZCU102.

## Steps

1. **Close Vivado and Vitis.**
2. **Build the HLS IP** - double-click `C:\PLD\hls\RAM_INTERFACE\build_ip.bat`
   (or run it from a Command Prompt). It runs C simulation, synthesis and packaging,
   then installs the IP into `C:\PLD\ip_repo\RAM_INTERFACE` (the old one is moved to
   `C:\PLD\backup\RAM_INTERFACE_old`). It must end with `DONE`.
3. **Open Vivado 2025.1.1** -> `C:\PLD\S7_integration\S7_integration.xpr`, then in the Tcl console:
   ```
   source C:/PLD/scripts/1_repackage_partitioner.tcl
   source C:/PLD/scripts/2_update_block_design.tcl
   ```
   Check: IP Status shows everything up to date, validation has no errors.
   Open the block design and look at `RAM_INTERFACE_0`: `data_dout`, `data_empty_n`,
   `data_read`, `done`, `DDR`, `m_axi_gmem`, `ap_clk`, `ap_rst_n` must all be connected.
4. **Build and export** (long):
   ```
   source C:/PLD/scripts/3_build_and_export.tcl
   ```
   It prints the worst negative slack; it must be >= 0.
5. **Vitis**: open workspace `C:\PLD\S7_integration_vit`.
   * Platform `interrupt_rerun_plat` -> Settings (`vitis-comp.json`) -> update / switch the
     hardware specification to `C:\PLD\S7_integration\interrupt_rerun.xsa` -> Build.
   * Application `interrupt_rerun_test` -> Build.
   * Check that `interrupt_rerun_test\_ide\bitstream\interrupt_rerun.bit` has today's date.
     If not, copy `interrupt_rerun_plat\export\interrupt_rerun_plat\hw\interrupt_rerun.bit` over it.
6. **On the board** (JTAG + UART 115200): Run. Expected output ends with
   `ALL RUNS PASSED` and prints, per run: BRAM load time, PL compute time
   (~1 ms expected), read-back time; plus the CPU-only reference time.

## If something goes wrong

* `build_ip.bat` fails on `vitis-run`/`v++`: open the Vitis IDE instead, create an HLS
  component from `hls_config.cfg`, run C Simulation -> C Synthesis -> Package, and
  extract the packaged zip into `C:\PLD\ip_repo\RAM_INTERFACE`.
* Script 2 stops on a `connect_bd_net` line: the message names the pin; send it to me.
* No interrupt on the board: the program times out after 1 s, reads `done` via GPIO 2
  and tells you whether the PL finished. That separates a PL problem from an
  interrupt problem.
* Everything is backed up: old IP in `C:\PLD\backup\`, old XSA in
  `C:\PLD\backup\interrupt_rerun_before_upgrade.xsa`, previous application versions in
  `C:\PLD\S7_integration_vit\backup\`.
