@echo off
REM ---------------------------------------------------------------------------
REM Builds the RAM_INTERFACE HLS IP and installs it in C:\PLD\ip_repo\RAM_INTERFACE
REM Run from a normal Command Prompt: C:\PLD\hls\RAM_INTERFACE\build_ip.bat
REM ---------------------------------------------------------------------------
setlocal
call C:\Xilinx\2025.1.1\Vitis\settings64.bat || goto :fail
cd /d %~dp0

echo === 1/3 C simulation ===
call vitis-run --mode hls --csim --config hls_config.cfg --work_dir work || goto :fail

echo === 2/3 Synthesis ===
call v++ -c --mode hls --config hls_config.cfg --work_dir work || goto :fail

echo === 3/3 Package IP ===
call vitis-run --mode hls --package --config hls_config.cfg --work_dir work || goto :fail

echo === Installing into C:\PLD\ip_repo\RAM_INTERFACE ===
if exist C:\PLD\ip_repo\RAM_INTERFACE_old rmdir /s /q C:\PLD\ip_repo\RAM_INTERFACE_old
if exist C:\PLD\ip_repo\RAM_INTERFACE move C:\PLD\ip_repo\RAM_INTERFACE C:\PLD\ip_repo\RAM_INTERFACE_old >nul
powershell -NoProfile -Command "Expand-Archive -Force 'RAM_INTERFACE_ip.zip' 'C:\PLD\ip_repo\RAM_INTERFACE'" || goto :fail
if not exist C:\PLD\ip_repo\RAM_INTERFACE\component.xml (
  echo component.xml not at the top of the zip - check C:\PLD\ip_repo\RAM_INTERFACE
  goto :fail
)
REM keep the old IP out of the repository so Vivado does not see two versions
if exist C:\PLD\ip_repo\RAM_INTERFACE_old (
  if not exist C:\PLD\backup mkdir C:\PLD\backup
  if exist C:\PLD\backup\RAM_INTERFACE_old rmdir /s /q C:\PLD\backup\RAM_INTERFACE_old
  move C:\PLD\ip_repo\RAM_INTERFACE_old C:\PLD\backup\RAM_INTERFACE_old >nul
)
echo.
echo DONE. Synthesis report: work\hls\syn\report\RAM_INTERFACE_csynth.rpt
exit /b 0

:fail
echo.
echo *** FAILED - see the messages above ***
exit /b 1
