@echo off
setlocal enabledelayedexpansion
title Minecraft Server File Downloader

echo ======================================================================
echo    Minecraft Bedrock + Java Cross-Play Server Downloader
echo ======================================================================
echo.

:: Check for Java
java -version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [!] WARNING: Java was not detected on your system PATH!
    echo     Minecraft 1.20.5+ requires Java 21 JDK.
    echo     Download it from: https://adoptium.net/temurin/releases/?version=21
    echo.
) else (
    echo [+] Java is installed.
)

:: Try using Python first if available
python --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [+] Python found. Running Python downloader...
    python download_server_and_plugins.py
    goto end
)

python3 --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [+] Python3 found. Running Python downloader...
    python3 download_server_and_plugins.py
    goto end
)

:: Fallback to PowerShell
echo [*] Python not detected, falling back to native PowerShell downloader...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0download_server_and_plugins.ps1"

:end
echo.
echo ======================================================================
echo Download process finished. Press any key to exit.
echo To start your server, double-click start.bat
echo ======================================================================
pause
