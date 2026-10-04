@echo off
setlocal enabledelayedexpansion
title Minecraft Cross-Play Server Installer

cd /d "%~dp0"

echo ======================================================================
echo    Minecraft Bedrock + Java Cross-Play Server 1-Click Installer
echo ======================================================================
echo.

:: 1. Check for Java
echo [*] Checking Java installation...
java -version >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [!] WARNING: Java 21+ was not found in your system PATH!
    echo     Please install Java JDK from: https://adoptium.net/temurin/releases/?version=21
    echo.
) else (
    echo [+] Java is installed.
)

:: 2. Ensure directories exist
if not exist "plugins" mkdir "plugins"
if not exist "plugins\Geyser-Spigot" mkdir "plugins\Geyser-Spigot"
if not exist "plugins\floodgate" mkdir "plugins\floodgate"
if not exist "plugins\ViaVersion" mkdir "plugins\ViaVersion"
if not exist "config" mkdir "config"

:: 3. Download Server Core (Stable 1.21.4), Geyser, Floodgate, ViaVersion
echo.
echo [*] Downloading Minecraft 1.21.4 Stable Server Engine and Crossplay Plugins...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
  "$ua = @{ 'User-Agent' = 'Minecraft-Crossplay-Setup/1.0 (server@laptop)' }; " ^
  "Write-Host '[1/4] Downloading stable Minecraft 1.21.4 server engine (server.jar)...' -ForegroundColor Cyan; " ^
  "Invoke-WebRequest -Uri 'https://api.purpurmc.org/v2/purpur/1.21.4/latest/download' -OutFile 'server.jar' -Headers $ua -UseBasicParsing; " ^
  "Write-Host '[+] Stable 1.21.4 server core downloaded!' -ForegroundColor Green; " ^
  "Write-Host '[2/4] Downloading Geyser-Spigot (Bedrock protocol support)...' -ForegroundColor Cyan; " ^
  "Invoke-WebRequest -Uri 'https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot' -OutFile 'plugins/Geyser-Spigot.jar' -Headers $ua -UseBasicParsing; " ^
  "Write-Host '[+] Geyser-Spigot downloaded successfully!' -ForegroundColor Green; " ^
  "Write-Host '[3/4] Downloading Floodgate-Spigot (Bedrock Xbox authentication)...' -ForegroundColor Cyan; " ^
  "Invoke-WebRequest -Uri 'https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot' -OutFile 'plugins/floodgate-spigot.jar' -Headers $ua -UseBasicParsing; " ^
  "Write-Host '[+] Floodgate-Spigot downloaded successfully!' -ForegroundColor Green; " ^
  "Write-Host '[4/4] Downloading ViaVersion (Multi-version support)...' -ForegroundColor Cyan; " ^
  "try { Invoke-WebRequest -Uri 'https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.2.1/PAPER/ViaVersion-5.2.1.jar' -OutFile 'plugins/ViaVersion.jar' -Headers $ua -UseBasicParsing; Write-Host '[+] ViaVersion downloaded!' -ForegroundColor Green; } catch { Write-Host '    ViaVersion optional download skipped.' -ForegroundColor Gray; }; " ^
  "Write-Host 'All downloads finished successfully!' -ForegroundColor Green;"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [!] Download encountered an error. Please check your internet connection.
    pause
    exit /b 1
)

:: 4. Auto-generate eula.txt if missing
if not exist "eula.txt" (
    echo eula=true> "eula.txt"
    echo [+] Created eula.txt (eula=true)
)

:: 5. Auto-generate start.bat if missing
if not exist "start.bat" (
(
echo @echo off
echo cd /d "%%~dp0"
echo title Minecraft Bedrock + Java Server
echo echo Starting Minecraft Crossplay Server...
echo java -Xms2G -Xmx4G -XX:+UseG1GC -jar server.jar --nogui
echo pause
) > "start.bat"
    echo [+] Created start.bat
)

:: 6. Auto-generate server.properties if missing
if not exist "server.properties" (
(
echo server-port=25565
echo gamemode=survival
echo difficulty=normal
echo pvp=true
echo max-players=20
echo view-distance=8
echo simulation-distance=5
echo online-mode=true
echo enforce-secure-profile=false
echo motd=\u00a7aCrossplay Server \u00a77\u00bb \u00a7bJava \u00a77+ \u00a7eBedrock
) > "server.properties"
    echo [+] Created server.properties
)

echo.
echo ======================================================================
echo  SETUP COMPLETE!
echo.
echo  To start your Minecraft server:
echo    Double-click start.bat in this folder!
echo ======================================================================
echo.
pause
