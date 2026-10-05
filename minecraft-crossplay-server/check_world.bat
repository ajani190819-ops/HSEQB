@echo off
setlocal
title Minecraft World & Playerdata Inspector

cd /d "%~dp0"

echo ======================================================================
echo  Inspecting World & Playerdata...
echo ======================================================================
echo.

python check_world.py "%~dp0world"
if %ERRORLEVEL% NEQ 0 (
    python3 check_world.py "%~dp0world"
)

echo.
pause
