@echo off
REM Double-click this to program the FX600 and run Coral NPU. No typing needed.
setlocal enabledelayedexpansion
set "KIT=%~dp0"
set "VIV="
for /d %%V in ("C:\Xilinx\Vivado\*") do set "VIV=%%V"
if not defined VIV for /d %%V in ("D:\Xilinx\Vivado\*") do set "VIV=%%V"
if not defined VIV (
  echo Could not find Vivado under C:\Xilinx\Vivado or D:\Xilinx\Vivado
  echo Edit this file and set VIV to your Vivado directory.
  pause
  exit /b 1
)
echo Using Vivado at !VIV!
"!VIV!\bin\vivado.bat" -mode batch -nolog -nojournal -source "%KIT%do_all.tcl" > "%KIT%coralnpu_run.log" 2>&1
echo.
echo ================= OUTPUT =================
type "%KIT%coralnpu_run.log"
echo ==========================================
echo Saved to %KIT%coralnpu_run.log
pause
