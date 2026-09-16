@echo off
REM ===================================================================
REM  Keyboard Lighting - get the latest version
REM
REM  Double-click this file. It fetches the newest version of
REM  everything and then opens the control panel.
REM
REM  This is a .bat on purpose: Windows blocks .ps1 files from being
REM  run directly, but .bat files are fine, and this launches
REM  PowerShell with -ExecutionPolicy Bypass so nothing is blocked.
REM ===================================================================
title Keyboard Lighting - Update
cd /d "%~dp0"

set "BASE=https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting"

REM --- first run: the updater script may not be here yet, so fetch it ---
if not exist "%~dp0Update.ps1" (
  echo.
  echo   First run - fetching the updater...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; Invoke-WebRequest '%BASE%/Update.ps1' -OutFile '%~dp0Update.ps1' -UseBasicParsing; Unblock-File '%~dp0Update.ps1'"
)

if not exist "%~dp0Update.ps1" (
  echo.
  echo   Could not download the updater.
  echo   Check your internet connection and try again.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update.ps1"

if not exist "%~dp0Lighting-Panel.bat" (
  echo.
  echo   Update finished but the control panel is missing.
  echo.
  pause
  exit /b 1
)

echo.
echo   Opening the control panel...
timeout /t 2 /nobreak >nul
start "" "%~dp0Lighting-Panel.bat"
exit /b 0
