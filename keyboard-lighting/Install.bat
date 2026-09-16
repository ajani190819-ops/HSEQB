@echo off
REM ===================================================================
REM  Keyboard Lighting - INSTALL  (this is the only file you need)
REM
REM  Double-click it, click "Yes" on the permission prompt, and wait.
REM
REM  It downloads everything, builds KeyboardLighting.exe, puts it in
REM  your Start menu, sets it to run at log in, and starts it.
REM  After this the lighting lives in the system tray, near the clock.
REM ===================================================================
title Keyboard Lighting - Install
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel%==0 goto run

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:run
set "BASE=https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting"

echo.
echo   Getting the installer...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; try{ Invoke-WebRequest '%BASE%/Install.ps1' -OutFile (Join-Path '%~dp0' 'Install.ps1') -UseBasicParsing -TimeoutSec 25; Unblock-File (Join-Path '%~dp0' 'Install.ps1') } catch { Write-Host ('   ' + $_.Exception.Message) -ForegroundColor Yellow }"

if not exist "%~dp0Install.ps1" (
  echo.
  echo   Could not download the installer.
  echo   Check your internet connection and run this again.
  echo.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
exit /b 0
