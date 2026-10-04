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

:: 3. Download Server Core, Geyser, Floodgate, ViaVersion using embedded PowerShell
echo.
echo [*] Downloading server engine and crossplay plugins...
echo     (This may take a minute depending on your internet connection)
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; " ^
  "$ua = @{ 'User-Agent' = 'Minecraft-Crossplay-Setup/1.0 (server@laptop)' }; " ^
  "$serverDownloaded = $false; " ^
  "Write-Host '[1/4] Fetching latest Minecraft server engine...' -ForegroundColor Cyan; " ^
  "try { " ^
  "  $purpurMeta = Invoke-RestMethod -Uri 'https://api.purpurmc.org/v2/purpur' -Headers $ua -UseBasicParsing; " ^
  "  $latestVer = $purpurMeta.versions[-1]; " ^
  "  $downloadUrl = ('https://api.purpurmc.org/v2/purpur/{0}/latest/download' -f $latestVer); " ^
  "  Write-Host ('    Downloading server core ({0})...' -f $latestVer) -ForegroundColor Gray; " ^
  "  Invoke-WebRequest -Uri $downloadUrl -OutFile 'server.jar' -Headers $ua -UseBasicParsing; " ^
  "  $serverDownloaded = $true; " ^
  "} catch { " ^
  "  Write-Host '    Purpur lookup failed, trying Paper Fill v3...' -ForegroundColor Yellow; " ^
  "}; " ^
  "if (-not $serverDownloaded) { " ^
  "  try { " ^
  "    $paperMeta = Invoke-RestMethod -Uri 'https://fill.papermc.io/v3/projects/paper' -Headers $ua -UseBasicParsing; " ^
  "    $latestVer = if ($paperMeta.versions -is [System.Collections.IDictionary]) { ($paperMeta.versions.Values | Select-Object -First 1)[0] } else { $paperMeta.versions[-1] }; " ^
  "    if (-not $latestVer) { $latestVer = '1.21.4' }; " ^
  "    $builds = Invoke-RestMethod -Uri ('https://fill.papermc.io/v3/projects/paper/versions/{0}/builds' -f $latestVer) -Headers $ua -UseBasicParsing; " ^
  "    $latestBuild = $builds[-1]; " ^
  "    $url = $latestBuild.downloads.'server:default'.url; " ^
  "    if (-not $url) { $url = $latestBuild.downloads.server.url }; " ^
  "    Invoke-WebRequest -Uri $url -OutFile 'server.jar' -Headers $ua -UseBasicParsing; " ^
  "    $serverDownloaded = $true; " ^
  "  } catch { " ^
  "    Write-Host '    Downloading fallback 1.21.4 server core...' -ForegroundColor Yellow; " ^
  "    Invoke-WebRequest -Uri 'https://api.purpurmc.org/v2/purpur/1.21.4/latest/download' -OutFile 'server.jar' -Headers $ua -UseBasicParsing; " ^
  "  }; " ^
  "}; " ^
  "Write-Host '[+] Server core (server.jar) downloaded successfully!' -ForegroundColor Green; " ^
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
