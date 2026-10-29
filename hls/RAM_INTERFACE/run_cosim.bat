@echo off
REM C/RTL co-simulation of RAM_INTERFACE (test build with ap_ctrl_hs).
REM Does not touch work\ or the installed IP. Output: cosim_log.txt
setlocal
call C:\Xilinx\2025.1.1\Vitis\settings64.bat || goto :fail
cd /d %~dp0
echo === 1/2 Synthesis (cosim build) ===
call v++ -c --mode hls --config hls_config_cosim.cfg --work_dir work_cosim || goto :fail
echo === 2/2 C/RTL co-simulation ===
call vitis-run --mode hls --cosim --config hls_config_cosim.cfg --work_dir work_cosim || goto :fail
echo.
echo DONE.
exit /b 0
:fail
echo.
echo *** FAILED - see the messages above ***
exit /b 1
