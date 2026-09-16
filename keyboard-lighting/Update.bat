@echo off
REM ===================================================================
REM  Keyboard Lighting - get the latest version
REM
REM  Double-click this file. It fetches the newest version of
REM  everything and then opens the control panel.
REM
REM  It always re-downloads the updater itself FIRST, so that newly
REM  added files are never missed.
REM ===================================================================
title Keyboard Lighting - Update
cd /d "%~dp0"

set "BASE=https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting"

echo.
echo   Refreshing the updater...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; try { Invoke-WebRequest '%BASE%/Update.ps1' -OutFile '%~dp0Update.ps1' -UseBasicParsing -TimeoutSec 25; Unblock-File '%~dp0Update.ps1' } catch { Write-Host '  Could not reach GitHub.' -ForegroundColor Red }"

if not exist "%~dp0Update.ps1" (
  echo.
  echo   Could not download the updater.
  echo   Check your internet connection and try again.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update.ps1"

echo.
echo   ==============================================================
echo    Files are up to date.
echo   ==============================================================
echo.
echo    Next: double-click  Check.bat   to run the diagnostic,
echo          or            Lighting-Panel.bat   for the control panel.
echo.
pause
exit /b 0
