@echo off
REM ===================================================================
REM  Keyboard Lighting - diagnostic
REM
REM  Double-click this. It checks every stage and tells you exactly
REM  what is wrong. Click "Yes" on the permission prompt.
REM
REM  It re-downloads its own script first, so it is always current.
REM ===================================================================
title Keyboard Lighting - Diagnostic
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel%==0 goto run

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:run
set "BASE=https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting"

echo.
echo   Fetching the latest diagnostic...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; try { Invoke-WebRequest '%BASE%/Check.ps1' -OutFile '%~dp0Check.ps1' -UseBasicParsing -TimeoutSec 25; Unblock-File '%~dp0Check.ps1' } catch { Write-Host '  (could not refresh - using local copy)' -ForegroundColor Yellow }"

if not exist "%~dp0Check.ps1" (
  echo.
  echo   Check.ps1 is missing and could not be downloaded.
  echo   Check your internet connection.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Check.ps1"
exit /b 0
