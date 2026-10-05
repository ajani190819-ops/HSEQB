@echo off
setlocal
title Minecraft World Inspector

cd /d "%~dp0"

echo ======================================================================
echo  Scanning for Minecraft World and Player Data...
echo ======================================================================
echo.

python check_world.py "%~dp0"
if %ERRORLEVEL% NEQ 0 (
    python3 check_world.py "%~dp0"
)

echo.
pause
