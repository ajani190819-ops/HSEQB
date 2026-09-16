@echo off
REM ===================================================================
REM  Keyboard Lighting - control panel launcher
REM
REM  Just double-click this file.
REM
REM  Direct keyboard access needs Administrator, so this asks Windows
REM  for permission automatically. Click "Yes" on the prompt.
REM ===================================================================
cd /d "%~dp0"

REM --- already elevated? then just run ---
net session >nul 2>&1
if %errorlevel%==0 goto run

REM --- not elevated: re-launch this same file as administrator ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Lighting-Panel.ps1"

if errorlevel 1 (
  echo.
  echo The panel closed with an error.
  echo.
  echo Run this to see the full message:
  echo   powershell -ExecutionPolicy Bypass -File "%~dp0Lighting-Panel.ps1"
  echo.
  pause
)
exit /b 0
