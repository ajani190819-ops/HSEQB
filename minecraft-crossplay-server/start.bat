@echo off
setlocal enabledelayedexpansion
title Minecraft Bedrock + Java Cross-Play Server

cd /d "%~dp0"

echo ======================================================================
echo  Minecraft Bedrock + Java Server Launcher
echo ======================================================================
echo.

:: 1. Check if server.jar exists
if not exist "server.jar" (
    echo [!] ERROR: 'server.jar' is missing from this folder:
    echo     %~dp0
    echo.
    echo     Please double-click 'download_server_and_plugins.bat' first!
    echo ======================================================================
    pause
    exit /b 1
)

:: 2. Check Java
where java >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [!] ERROR: Java is not detected in your PATH.
    echo     Please download and install Java 21 JDK from:
    echo     https://adoptium.net/temurin/releases/?version=21
    echo ======================================================================
    pause
    exit /b 1
)

echo [*] Java detected:
java -version
echo.

:: 3. Launch Server
echo ======================================================================
echo  Starting server... (Please wait a few seconds)
echo  Java Port:    25565
echo  Bedrock Port: 19132
echo ======================================================================
echo.

java -Xms2G -Xmx4G -XX:+UseG1GC -jar server.jar --nogui

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ======================================================================
    echo [!] The server stopped unexpectedly with error code %ERRORLEVEL%.
    echo     - If it says 'UnsupportedClassVersionError', you need Java 21 JDK.
    echo     - If it says 'Could not reserve enough space', edit start.bat to 2G.
    echo ======================================================================
)

echo.
echo Press any key to exit or close this window...
pause >nul
