@echo off
REM ===================================================================
REM  Keyboard Lighting - get the latest version
REM
REM  Double-click this file. It downloads the newest version
REM  and then opens the control panel.
REM ===================================================================
title Keyboard Lighting - Update
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update.ps1"

echo.
echo   Opening the control panel...
timeout /t 2 /nobreak >nul
start "" "%~dp0Lighting-Panel.bat"
exit /b 0
