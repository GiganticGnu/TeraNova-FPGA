@echo off
rem ============================================================================
rem  run_rung3_hw.bat  --  rung 3 as it is built on the board, in XSim
rem  Kai Janssen, Nov 2026, Vivado 2025.1.1 (simulation only, no licence needed)
rem
rem    run_rung3_hw.bat                 LAT = 40 cycles, 2 runs, text report only
rem    run_rung3_hw.bat 40 gui          same, and open the wave view (stage signal,
rem                                     groups per block, markers per stage)
rem    run_rung3_hw.bat 20              other DDR4 write-response latency
rem    run_rung3_hw.bat whatif          the three what-if cases (1 run each):
rem                                     DDR input 0, BRAMs not loaded, BRAM latency 2
rem
rem  Sources: the testbench + models in .\src, the design RTL from C:\PLD\sim
rem  (identical to ip_repo on branch partitioner-v6). Output goes to .\batch
rem  The report (data check per stage + stage timing) is in batch\xsim_*.log
rem ============================================================================
setlocal
set LAT=%~1
if "%LAT%"=="" set LAT=40
set MODE=%~2
set SETTINGS=C:\Xilinx\2025.1.1\Vivado\settings64.bat

where xvhdl >nul 2>nul
if errorlevel 1 if exist "%SETTINGS%" call "%SETTINGS%"
where xvhdl >nul 2>nul
if errorlevel 1 (
  echo Cannot find xvhdl. Open this from a "Vivado 2025.1.1 Tcl Shell" or edit SETTINGS in this file.
  exit /b 1
)

set H=%~dp0
set S=%~dp0..
set R=%S%\steps\2_writer_fix\hls_rtl
set B=%~dp0batch
if not exist "%B%" mkdir "%B%"
cd /d "%B%"

echo === 1/3 compile (xvhdl) ===
call xvhdl -2008 -relax -work xil_defaultlib -log xvhdl.log ^
    "%S%\MatMul5x5.vhd" ^
    "%S%\MatMul5x5_IF_IN.vhd" ^
    "%S%\MatMul5x5_Accumulator.vhd" ^
    "%S%\matrix_to_ports.vhd" ^
    "%S%\variants\matrix_partitioner_B_v6.vhd" ^
    "%R%\RAM_INTERFACE_RAM_INTERFACE_Pipeline_BEATS.vhd" ^
    "%R%\RAM_INTERFACE_RAM_INTERFACE_Pipeline_REQUESTS.vhd" ^
    "%R%\RAM_INTERFACE_RAM_INTERFACE_Pipeline_RESPONSES.vhd" ^
    "%R%\RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd" ^
    "%R%\RAM_INTERFACE_gmem_m_axi.vhd" ^
    "%R%\RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd" ^
    "%R%\RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd" ^
    "%R%\RAM_INTERFACE.vhd" ^
    "%H%src\toggle2pulse.vhd" ^
    "%H%src\hw_pkg.vhd" ^
    "%H%src\bram_tdp_model.vhd" ^
    "%H%src\axi_ddr_model.vhd" ^
    "%H%src\tb_rung3_hw.vhd"
if errorlevel 1 goto fail

if /i "%LAT%"=="whatif" goto whatif

echo === 2/3 elaborate (xelab) ===
call xelab -debug typical -relax -generic_top "LAT=%LAT%" -s rung3_L%LAT% xil_defaultlib.tb_rung3_hw -log xelab_L%LAT%.log
if errorlevel 1 goto fail

echo === 3/3 simulate (xsim) ===
if /i "%MODE%"=="gui" (
  call xsim rung3_L%LAT% -gui -tclbatch "%H%batch_gui.tcl" -wdb rung3_L%LAT%.wdb -log xsim_L%LAT%.log
) else (
  call xsim rung3_L%LAT% -R -log xsim_L%LAT%.log
)
if errorlevel 1 goto fail
echo.
echo Done. Report: %B%\xsim_L%LAT%.log
exit /b 0

:whatif
call xelab -relax -generic_top "N_RUNS=1" -generic_top "DDR_BASE_HI=0" -s wi_ddr0 xil_defaultlib.tb_rung3_hw -log xelab_wi_ddr0.log
if errorlevel 1 goto fail
call xsim wi_ddr0 -R -log xsim_whatif_ddr_input_0.log
call xelab -relax -generic_top "N_RUNS=1" -generic_top "CPU_LOADS_BRAM=0" -s wi_nobram xil_defaultlib.tb_rung3_hw -log xelab_wi_nobram.log
if errorlevel 1 goto fail
call xsim wi_nobram -R -log xsim_whatif_brams_empty.log
call xelab -relax -generic_top "N_RUNS=1" -generic_top "BRAM_LAT=2" -s wi_lat2 xil_defaultlib.tb_rung3_hw -log xelab_wi_lat2.log
if errorlevel 1 goto fail
call xsim wi_lat2 -R -log xsim_whatif_bram_latency_2.log
echo.
echo Done. Reports: %B%\xsim_whatif_*.log
exit /b 0

:fail
echo.
echo *** FAILED - see the .log files in %B% ***
exit /b 1
