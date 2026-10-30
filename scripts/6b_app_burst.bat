@echo off
rem ---------------------------------------------------------------------------
rem 6b_app_burst.bat
rem Ladder step 4_burst_datapath: puts the burst-data-path application into the
rem Vitis app (S7_integration_vit\interrupt_rerun_test\src):
rem   1. app\burst_datapath\helloworld_burst.c  ->  src\helloworld.c
rem   2. deletes src\bram_write.c and src\bram_write.h (there are no BRAMs any
rem      more; the new BSP has no BRAM driver, so they would not compile)
rem   3. removes "bram_write.c" from src\UserConfig.cmake
rem Run ONLY on git branch burst-datapath (double-click, or from cmd).
rem ---------------------------------------------------------------------------
cd /d C:\PLD
for /f %%b in ('git rev-parse --abbrev-ref HEAD') do set BR=%%b
if not "%BR%"=="burst-datapath" (
  echo You are on git branch "%BR%". Switch to burst-datapath first. Nothing was changed.
  pause
  exit /b 1
)
set SRC=S7_integration_vit\interrupt_rerun_test\src
if not exist app\burst_datapath\helloworld_burst.c (
  echo Not found: app\burst_datapath\helloworld_burst.c. Nothing was changed.
  pause
  exit /b 1
)
copy /y app\burst_datapath\helloworld_burst.c %SRC%\helloworld.c >nul
if exist %SRC%\bram_write.c del %SRC%\bram_write.c
if exist %SRC%\bram_write.h del %SRC%\bram_write.h
powershell -NoProfile -Command "$f='%SRC%\UserConfig.cmake'; (Get-Content $f) | Where-Object { $_ -notmatch '\"bram_write\.c\"' } | Set-Content $f"
echo.
echo Done on branch %BR%:
echo   %SRC%\helloworld.c      = burst-data-path application
echo   bram_write.c / .h       deleted
echo   UserConfig.cmake        no longer lists bram_write.c
echo.
git status --short
pause
