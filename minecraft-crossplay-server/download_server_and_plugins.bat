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
    echo [!] WARNING: Java 21 was not found in your system PATH!
    echo     Minecraft 1.20.5+ requires Java 21 JDK.
    echo     Download it from: https://adoptium.net/temurin/releases/?version=21
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

:: 3. Download PaperMC, Geyser, Floodgate, ViaVersion using embedded PowerShell
echo.
echo [*] Downloading PaperMC server and plugins...
echo     (This may take a moment depending on your internet connection)
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
  "Write-Host '[1/4] Fetching latest PaperMC server build...' -ForegroundColor Cyan; " ^
  "try { " ^
  "  $api = 'https://api.papermc.io/v2/projects/paper'; " ^
  "  $proj = Invoke-RestMethod -Uri $api -UseBasicParsing; " ^
  "  $latestVer = $proj.versions[-1]; " ^
  "  $verData = Invoke-RestMethod -Uri ('{0}/versions/{1}' -f $api, $latestVer) -UseBasicParsing; " ^
  "  $latestBuild = $verData.builds[-1]; " ^
  "  $jarName = ('paper-{0}-{1}.jar' -f $latestVer, $latestBuild); " ^
  "  $url = ('{0}/versions/{1}/builds/{2}/downloads/{3}' -f $api, $latestVer, $latestBuild, $jarName); " ^
  "  Write-Host ('    Downloading Paper {0} (Build #{1})...' -f $latestVer, $latestBuild) -ForegroundColor Gray; " ^
  "  Invoke-WebRequest -Uri $url -OutFile 'server.jar' -UseBasicParsing; " ^
  "} catch { " ^
  "  Write-Host '    API lookup failed, downloading Paper 1.21.4 direct...' -ForegroundColor Yellow; " ^
  "  Invoke-WebRequest -Uri 'https://api.papermc.io/v2/projects/paper/versions/1.21.4/builds/147/downloads/paper-1.21.4-147.jar' -OutFile 'server.jar' -UseBasicParsing; " ^
  "}; " ^
  "Write-Host '[2/4] Downloading Geyser-Spigot (Bedrock protocol support)...' -ForegroundColor Cyan; " ^
  "Invoke-WebRequest -Uri 'https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot' -OutFile 'plugins/Geyser-Spigot.jar' -UseBasicParsing; " ^
  "Write-Host '[3/4] Downloading Floodgate-Spigot (Bedrock Xbox authentication)...' -ForegroundColor Cyan; " ^
  "Invoke-WebRequest -Uri 'https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot' -OutFile 'plugins/floodgate-spigot.jar' -UseBasicParsing; " ^
  "Write-Host '[4/4] Downloading ViaVersion (Multi-version support)...' -ForegroundColor Cyan; " ^
  "try { Invoke-WebRequest -Uri 'https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.2.1/PAPER/ViaVersion-5.2.1.jar' -OutFile 'plugins/ViaVersion.jar' -UseBasicParsing; } catch { Write-Host '    ViaVersion optional download skipped.' -ForegroundColor Gray; }; " ^
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
echo setlocal
echo title Minecraft Bedrock + Java Cross-Play Server
echo set RAM=4G
echo echo Starting Minecraft Server with %%RAM%% RAM...
echo echo Java Port: 25565 ^| Bedrock Port: 19132
echo :loop
echo java -Xms%%RAM%% -Xmx%%RAM%% -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -jar server.jar --nogui
echo echo Server stopped. Press any key to restart or Ctrl+C to exit.
echo pause
echo goto loop
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

:: 7. Auto-generate Geyser config if missing
if not exist "plugins\Geyser-Spigot\config.yml" (
(
echo bedrock:
echo   address: 0.0.0.0
echo   port: 19132
echo   motd1: "Crossplay Server"
echo   motd2: "Java + Bedrock Supported!"
echo remote:
echo   address: 127.0.0.1
echo   port: 25565
echo   auth-type: floodgate
echo show-cooldown: title
echo show-coordinates: true
echo passthrough-motd: true
) > "plugins\Geyser-Spigot\config.yml"
    echo [+] Created plugins\Geyser-Spigot\config.yml
)

:: 8. Auto-generate Floodgate config if missing
if not exist "plugins\floodgate\config.yml" (
(
echo username-prefix: "."
echo replace-spaces: true
echo key: key.pem
) > "plugins\floodgate\config.yml"
    echo [+] Created plugins\floodgate\config.yml
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
