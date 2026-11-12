@echo off
rem ============================================================================
rem  run_ladder_batch.bat  --  TeraNova ladder in XSim without a Vivado project
rem  Kai Janssen, Nov 2026, Vivado 2025.1.1
rem
rem    run_ladder_batch.bat              L = 20, text summary only
rem    run_ladder_batch.bat 100          L = 100 (stress latency)
rem    run_ladder_batch.bat 20 gui       also open the XSim GUI with the wave view
rem
rem  Uses the three Vivado simulator steps directly: xvhdl (compile),
rem  xelab (elaborate = build the snapshot), xsim (simulate).
rem  Everything it makes goes into the folder "batch" next to this file.
rem ============================================================================
setlocal
set LAT=%~1
if "%LAT%"=="" set LAT=20
set MODE=%~2
set SETTINGS=C:\Xilinx\2025.1.1\Vivado\settings64.bat

where xvhdl >nul 2>nul
if errorlevel 1 if exist "%SETTINGS%" call "%SETTINGS%"
where xvhdl >nul 2>nul
if errorlevel 1 (
  echo Cannot find xvhdl. Open this from a "Vivado 2025.1.1 Tcl Shell" or edit SETTINGS in this file.
  exit /b 1
)

set S=%~dp0..
set B=%~dp0batch
if not exist "%B%" mkdir "%B%"
cd /d "%B%"

echo === 1/3 compile (xvhdl) ===
call xvhdl -2008 -relax -work tn_common "%S%\vivado\src\tn_pkg.vhd" -log xvhdl_tn_common.log
if errorlevel 1 goto fail
call xvhdl -2008 -relax -work rung0 -log xvhdl_rung0.log ^
    "%S%\MatMul5x5.vhd" ^
    "%S%\MatMul5x5_IF_IN.vhd" ^
    "%S%\MatMul5x5_Accumulator.vhd" ^
    "%S%\matrix_to_ports.vhd" ^
    "%S%\matrix_partitioner_B.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_ROWS_COLS.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_gmem_m_axi.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_mac_muladd_6ns_3ns_12ns_12_4_1.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE.vhd" ^
    "%S%\vivado\src\axi_mem_model_v.vhd" ^
    "%S%\vivado\src\rung_core_bram.vhd"
if errorlevel 1 goto fail
call xvhdl -2008 -relax -work rung1 -log xvhdl_rung1.log ^
    "%S%\MatMul5x5.vhd" ^
    "%S%\MatMul5x5_IF_IN.vhd" ^
    "%S%\MatMul5x5_Accumulator.vhd" ^
    "%S%\matrix_to_ports.vhd" ^
    "%S%\variants\matrix_partitioner_B_v5b.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_ROWS_COLS.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_gmem_m_axi.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_mac_muladd_6ns_3ns_12ns_12_4_1.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd" ^
    "%S%\hls_rtl\RAM_INTERFACE.vhd" ^
    "%S%\vivado\src\axi_mem_model_v.vhd" ^
    "%S%\vivado\src\rung_core_bram.vhd"
if errorlevel 1 goto fail
call xvhdl -2008 -relax -work rung2 -log xvhdl_rung2.log ^
    "%S%\MatMul5x5.vhd" ^
    "%S%\MatMul5x5_IF_IN.vhd" ^
    "%S%\MatMul5x5_Accumulator.vhd" ^
    "%S%\matrix_to_ports.vhd" ^
    "%S%\variants\matrix_partitioner_B_v5b.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_BEATS.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_REQUESTS.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_RESPONSES.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_gmem_m_axi.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE.vhd" ^
    "%S%\vivado\src\axi_mem_model_v.vhd" ^
    "%S%\vivado\src\rung_core_bram.vhd"
if errorlevel 1 goto fail
call xvhdl -2008 -relax -work rung3 -log xvhdl_rung3.log ^
    "%S%\MatMul5x5.vhd" ^
    "%S%\MatMul5x5_IF_IN.vhd" ^
    "%S%\MatMul5x5_Accumulator.vhd" ^
    "%S%\matrix_to_ports.vhd" ^
    "%S%\variants\matrix_partitioner_B_v6.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_BEATS.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_REQUESTS.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_RESPONSES.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_gmem_m_axi.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE.vhd" ^
    "%S%\vivado\src\axi_mem_model_v.vhd" ^
    "%S%\vivado\src\rung_core_bram.vhd"
if errorlevel 1 goto fail
call xvhdl -2008 -relax -work rung4 -log xvhdl_rung4.log ^
    "%S%\MatMul5x5.vhd" ^
    "%S%\MatMul5x5_IF_IN.vhd" ^
    "%S%\MatMul5x5_Accumulator.vhd" ^
    "%S%\matrix_to_ports.vhd" ^
    "%S%\variants\matrix_partitioner_B_v7.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_BEATS.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_REQUESTS.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_RAM_INTERFACE_Pipeline_RESPONSES.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_gmem_m_axi.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd" ^
    "%S%\steps\2_writer_fix\hls_rtl\RAM_INTERFACE.vhd" ^
    "%S%\vivado\src\axi_mem_model_v.vhd" ^
    "%S%\vivado\src\axi_rd_mem_model_v.vhd" ^
    "%S%\vivado\src\rung_core_axi.vhd"
if errorlevel 1 goto fail
call xvhdl -2008 -relax -work xil_defaultlib "%S%\vivado\src\tb_ladder.vhd" -log xvhdl_top.log
if errorlevel 1 goto fail

echo === 2/3 elaborate (xelab) ===
call xelab -debug typical -relax -generic_top "LAT=%LAT%" -s ladder_L%LAT% xil_defaultlib.tb_ladder -log xelab_L%LAT%.log
if errorlevel 1 goto fail

echo === 3/3 simulate (xsim) ===
if /i "%MODE%"=="gui" (
  call xsim ladder_L%LAT% -gui -tclbatch "%~dp0batch_gui.tcl" -wdb ladder_L%LAT%.wdb -log xsim_L%LAT%.log
) else (
  call xsim ladder_L%LAT% -R -log xsim_L%LAT%.log
)
if errorlevel 1 goto fail
echo.
echo Done. Logs are in %B%
exit /b 0

:fail
echo.
echo *** FAILED - see the .log files in %B% ***
exit /b 1
