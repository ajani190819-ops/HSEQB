# PowerShell Script to download PaperMC, Geyser, Floodgate, and ViaVersion
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$serverDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginsDir = Join-Path $serverDir "plugins"

if (-not (Test-Path $pluginsDir)) {
    New-Item -ItemType Directory -Path $pluginsDir | Out-Null
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Minecraft Bedrock + Java Cross-Play Downloader (PowerShell)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. Fetch PaperMC
Write-Host "`n[*] Finding latest PaperMC build..." -ForegroundColor Yellow
$paperJarPath = Join-Path $serverDir "server.jar"
try {
    $paperApi = "https://api.papermc.io/v2/projects/paper"
    $proj = Invoke-RestMethod -Uri $paperApi -UseBasicParsing
    $latestVer = $proj.versions[-1]
    
    $verUrl = "$paperApi/versions/$latestVer"
    $verData = Invoke-RestMethod -Uri $verUrl -UseBasicParsing
    $latestBuild = $verData.builds[-1]
    
    $jarName = "paper-$latestVer-$latestBuild.jar"
    $downloadUrl = "$paperApi/versions/$latestVer/builds/$latestBuild/downloads/$jarName"
    
    Write-Host "[+] Downloading PaperMC $latestVer (Build #$latestBuild)..." -ForegroundColor Green
    Invoke-WebRequest -Uri $downloadUrl -OutFile $paperJarPath -UseBasicParsing
} catch {
    Write-Host "[!] Could not fetch PaperMC from API, using fallback URL..." -ForegroundColor Red
    $fallbackUrl = "https://api.papermc.io/v2/projects/paper/versions/1.21.4/builds/147/downloads/paper-1.21.4-147.jar"
    Invoke-WebRequest -Uri $fallbackUrl -OutFile $paperJarPath -UseBasicParsing
}

# 2. Fetch Geyser
Write-Host "`n[*] Downloading Geyser-Spigot (Bedrock protocol support)..." -ForegroundColor Yellow
$geyserPath = Join-Path $pluginsDir "Geyser-Spigot.jar"
$geyserUrl = "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
Invoke-WebRequest -Uri $geyserUrl -OutFile $geyserPath -UseBasicParsing
Write-Host "[+] Geyser-Spigot downloaded successfully!" -ForegroundColor Green

# 3. Fetch Floodgate
Write-Host "`n[*] Downloading Floodgate-Spigot (Bedrock Xbox authentication)..." -ForegroundColor Yellow
$floodgatePath = Join-Path $pluginsDir "floodgate-spigot.jar"
$floodgateUrl = "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
Invoke-WebRequest -Uri $floodgateUrl -OutFile $floodgatePath -UseBasicParsing
Write-Host "[+] Floodgate-Spigot downloaded successfully!" -ForegroundColor Green

# 4. Fetch ViaVersion
Write-Host "`n[*] Downloading ViaVersion (Cross-version compatibility)..." -ForegroundColor Yellow
$viaversionPath = Join-Path $pluginsDir "ViaVersion.jar"
$viaversionUrl = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.2.1/PAPER/ViaVersion-5.2.1.jar"
try {
    Invoke-WebRequest -Uri $viaversionUrl -OutFile $viaversionPath -UseBasicParsing
    Write-Host "[+] ViaVersion downloaded successfully!" -ForegroundColor Green
} catch {
    Write-Host "[!] ViaVersion download skipped or failed (optional plugin)." -ForegroundColor Gray
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  All files downloaded! Double-click 'start.bat' to launch your server!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
