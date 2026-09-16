@echo off
REM ===================================================================
REM  Keyboard Lighting - SETUP
REM
REM  THE ONLY FILE YOU RUN. Double-click it, click "Yes".
REM
REM  First time:  installs everything and starts it.
REM  Any time after: updates, repairs, and tests it.
REM
REM  If something is broken it tells you exactly what and copies a
REM  report to your clipboard.
REM ===================================================================
title Keyboard Lighting - Setup
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel%==0 goto run

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:run
set "BASE=https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting"

echo.
echo   Getting the latest setup...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; try{ Invoke-WebRequest '%BASE%/Setup.ps1' -OutFile (Join-Path '%~dp0' 'Setup.ps1') -UseBasicParsing -TimeoutSec 25; Unblock-File (Join-Path '%~dp0' 'Setup.ps1') } catch { Write-Host ('   ' + $_.Exception.Message) -ForegroundColor Yellow }"

if not exist "%~dp0Setup.ps1" (
  echo.
  echo   Could not download Setup.ps1.
  echo   Check your internet connection and run this again.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1" -NoElevate
exit /b 0
