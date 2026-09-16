@echo off
REM ===================================================================
REM  Keyboard Lighting - control panel launcher
REM
REM  Just double-click this file.
REM
REM  If you want the "start automatically at log in" tick box to work,
REM  right-click this file and choose "Run as administrator" instead.
REM ===================================================================

cd /d "%~dp0"

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
