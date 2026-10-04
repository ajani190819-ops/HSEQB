@echo off
setlocal
title Minecraft Bedrock + Java Cross-Play Server

:: ============================================================================
:: CONFIGURATION: RAM ALLOCATION
:: ============================================================================
:: Minimum RAM (Xms) and Maximum RAM (Xmx).
:: For an 8 GB laptop: set RAM=3G or 4G.
:: For a 16 GB laptop: set RAM=6G or 8G.
set RAM=4G

:: ============================================================================
:: CHECK PREREQUISITES
:: ============================================================================
if not exist "server.jar" (
    echo ======================================================================
    echo [!] server.jar NOT FOUND in this folder!
    echo ======================================================================
    echo It looks like you haven't downloaded the server files yet.
    echo Would you like to run the automated downloader now?
    echo.
    set /p RUN_DOWNLOAD="Download server files now? (Y/N): "
    if /i "!RUN_DOWNLOAD!"=="Y" (
        call download_server_and_plugins.bat
    ) else (
        echo Please place your server.jar here and run start.bat again.
        pause
        exit /b 1
    )
)

java -version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ======================================================================
    echo [!] ERROR: Java is not installed or not in your system PATH!
    echo ======================================================================
    echo Minecraft 1.20.5+ requires Java 21 JDK.
    echo Please install Eclipse Temurin JDK 21:
    echo https://adoptium.net/temurin/releases/?version=21
    echo ======================================================================
    pause
    exit /b 1
)

:: ============================================================================
:: LAUNCH MINECRAFT SERVER WITH AIKAR'S OPTIMIZED FLAGS
:: ============================================================================
echo ======================================================================
echo  Starting Minecraft Bedrock + Java Server with %RAM% RAM...
echo  Java Port:    25565 (TCP)
echo  Bedrock Port: 19132 (UDP)
echo ======================================================================

:server_loop
java -Xms%RAM% -Xmx%RAM% ^
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
  -Dusing.aikars.flags=https://mcflags.emc.gs ^
  -Daikars.new.flags=true ^
  -jar server.jar --nogui

echo.
echo ======================================================================
echo Server stopped.
echo ======================================================================
echo Press Ctrl+C to terminate, or press any key to restart the server...
pause >nul
goto server_loop
