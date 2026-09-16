@echo off
REM ===================================================================
REM  Keyboard Lighting - diagnostic
REM
REM  Double-click this. Click "Yes" on the permission prompt.
REM
REM  It re-downloads the diagnostic AND the lighting engine first,
REM  so it always tests the current code.
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
echo   Downloading the latest files...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; $b='%BASE%'; $d='%~dp0'; $n=0; foreach($f in 'Check.ps1','Aura-Background.ps1','Tray.ps1','ui_controls.cs.txt','app.ico','Update.ps1','Update.bat','Install.ps1','Install.bat'){ try{ Invoke-WebRequest \"$b/$f\" -OutFile (Join-Path $d $f) -UseBasicParsing -TimeoutSec 25; Unblock-File (Join-Path $d $f); $n++ } catch { Write-Host ('   could not download ' + $f) -ForegroundColor Yellow } }; Write-Host ('   got ' + $n + ' of 9 files') -ForegroundColor Gray"

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
