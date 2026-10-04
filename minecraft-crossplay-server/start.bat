@echo off
setlocal enabledelayedexpansion
title FLOOR 5 WORLDWIDE - Minecraft Cross-Play Server

cd /d "%~dp0"

echo ======================================================================
echo  Starting [FLOOR 5 WORLDWIDE] Minecraft Crossplay Server (8GB RAM)...
echo  Java Port: 25565 -- Bedrock Port: 19132
echo ======================================================================
echo.

if not exist "server.jar" (
    echo [!] ERROR: server.jar was not found in:
    echo     %~dp0
    echo.
    pause
    exit /b 1
)

:: Optimized G1GC JVM flags for 50 players & 16 chunk view distance
java -Xms8G -Xmx8G ^
  -XX:+UseG1GC ^
  -XX:+ParallelRefProcEnabled ^
  -XX:MaxGCPauseMillis=200 ^
  -XX:+UnlockExperimentalVMOptions ^
  -XX:+DisableExplicitGC ^
  -XX:+AlwaysPreTouch ^
  -XX:G1NewSizePercent=30 ^
  -XX:G1MaxNewSizePercent=40 ^
  -XX:G1ReservePercent=20 ^
  -XX:G1HeapWastePercent=5 ^
  -XX:G1MixedGCCountTarget=4 ^
  -XX:InitiatingHeapOccupancyPercent=15 ^
  -XX:G1MixedGCLiveThresholdPercent=90 ^
  -XX:G1RSetUpdatingPauseTimePercent=5 ^
  -XX:SurvivorRatio=32 ^
  -XX:+PerfDisableSharedMem ^
  -XX:MaxTenuringThreshold=1 ^
  -jar server.jar --nogui

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ======================================================================
    echo [!] Server stopped with exit code %ERRORLEVEL%.
    echo ======================================================================
)

echo.
echo Server window closed. Press any key to exit.
pause
