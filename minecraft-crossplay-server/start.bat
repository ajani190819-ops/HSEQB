@echo off
setlocal enabledelayedexpansion
title Minecraft Bedrock + Java Cross-Play Server

cd /d "%~dp0"

echo ======================================================================
echo  Starting Minecraft Server...
echo  Java Port: 25565 -- Bedrock Port: 19132
echo ======================================================================
echo.

if not exist "server.jar" (
    echo [!] ERROR: server.jar was not found in:
    echo     %~dp0
    echo     Please make sure you downloaded server.jar into this folder.
    echo.
    pause
    exit /b 1
)

java -Xms2G -Xmx4G -XX:+UseG1GC -jar server.jar --nogui

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ======================================================================
    echo [!] Server stopped with exit code %ERRORLEVEL%.
    echo ======================================================================
)

echo.
echo Server window closed. Press any key to exit.
pause
