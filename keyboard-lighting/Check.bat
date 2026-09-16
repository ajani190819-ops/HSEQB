@echo off
REM ===================================================================
REM  Keyboard Lighting - diagnostic
REM
REM  Double-click this. It checks every stage and tells you exactly
REM  what is wrong. Click "Yes" on the permission prompt.
REM ===================================================================
title Keyboard Lighting - Diagnostic
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel%==0 goto run

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Check.ps1"
exit /b 0
