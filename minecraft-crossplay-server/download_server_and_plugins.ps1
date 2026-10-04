# PowerShell Script to download Minecraft server core, Geyser, Floodgate, and ViaVersion
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$serverDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pluginsDir = Join-Path $serverDir "plugins"
$ua = @{ "User-Agent" = "Minecraft-Crossplay-Setup/1.0 (server@laptop)" }

if (-not (Test-Path $pluginsDir)) {
    New-Item -ItemType Directory -Path $pluginsDir | Out-Null
}

Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "  Minecraft Bedrock + Java Cross-Play Downloader (PowerShell)" -ForegroundColor Cyan
Write-Host "======================================================================" -ForegroundColor Cyan

# 1. Fetch Server Core (Purpur / Paper Fill v3)
Write-Host "`n[*] Finding latest Minecraft server engine..." -ForegroundColor Yellow
$serverJarPath = Join-Path $serverDir "server.jar"
$serverDownloaded = $false

try {
    $purpurMeta = Invoke-RestMethod -Uri "https://api.purpurmc.org/v2/purpur" -Headers $ua -UseBasicParsing
    $latestVer = $purpurMeta.versions[-1]
    $downloadUrl = "https://api.purpurmc.org/v2/purpur/$latestVer/latest/download"
    Write-Host "[+] Downloading server core ($latestVer)..." -ForegroundColor Green
    Invoke-WebRequest -Uri $downloadUrl -OutFile $serverJarPath -Headers $ua -UseBasicParsing
    $serverDownloaded = $true
} catch {
    Write-Host "[!] Purpur lookup skipped, trying Paper Fill v3..." -ForegroundColor Yellow
}

if (-not $serverDownloaded) {
    try {
        $paperMeta = Invoke-RestMethod -Uri "https://fill.papermc.io/v3/projects/paper" -Headers $ua -UseBasicParsing
        $latestVer = if ($paperMeta.versions -is [System.Collections.IDictionary]) { ($paperMeta.versions.Values | Select-Object -First 1)[0] } else { $paperMeta.versions[-1] }
        if (-not $latestVer) { $latestVer = "1.21.4" }
        $builds = Invoke-RestMethod -Uri "https://fill.papermc.io/v3/projects/paper/versions/$latestVer/builds" -Headers $ua -UseBasicParsing
        $latestBuild = $builds[-1]
        $url = $latestBuild.downloads.'server:default'.url
        if (-not $url) { $url = $latestBuild.downloads.server.url }
        Write-Host "[+] Downloading Paper $latestVer..." -ForegroundColor Green
        Invoke-WebRequest -Uri $url -OutFile $serverJarPath -Headers $ua -UseBasicParsing
        $serverDownloaded = $true
    } catch {
        Write-Host "[!] Downloading fallback 1.21.4 server core..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri "https://api.purpurmc.org/v2/purpur/1.21.4/latest/download" -OutFile $serverJarPath -Headers $ua -UseBasicParsing
    }
}

# 2. Fetch Geyser
Write-Host "`n[*] Downloading Geyser-Spigot (Bedrock protocol support)..." -ForegroundColor Yellow
$geyserPath = Join-Path $pluginsDir "Geyser-Spigot.jar"
$geyserUrl = "https://download.geysermc.org/v2/projects/geyser/versions/latest/builds/latest/downloads/spigot"
Invoke-WebRequest -Uri $geyserUrl -OutFile $geyserPath -Headers $ua -UseBasicParsing
Write-Host "[+] Geyser-Spigot downloaded successfully!" -ForegroundColor Green

# 3. Fetch Floodgate
Write-Host "`n[*] Downloading Floodgate-Spigot (Bedrock Xbox authentication)..." -ForegroundColor Yellow
$floodgatePath = Join-Path $pluginsDir "floodgate-spigot.jar"
$floodgateUrl = "https://download.geysermc.org/v2/projects/floodgate/versions/latest/builds/latest/downloads/spigot"
Invoke-WebRequest -Uri $floodgateUrl -OutFile $floodgatePath -Headers $ua -UseBasicParsing
Write-Host "[+] Floodgate-Spigot downloaded successfully!" -ForegroundColor Green

# 4. Fetch ViaVersion
Write-Host "`n[*] Downloading ViaVersion (Cross-version compatibility)..." -ForegroundColor Yellow
$viaversionPath = Join-Path $pluginsDir "ViaVersion.jar"
$viaversionUrl = "https://hangarcdn.papermc.io/plugins/ViaVersion/ViaVersion/versions/5.2.1/PAPER/ViaVersion-5.2.1.jar"
try {
    Invoke-WebRequest -Uri $viaversionUrl -OutFile $viaversionPath -Headers $ua -UseBasicParsing
    Write-Host "[+] ViaVersion downloaded successfully!" -ForegroundColor Green
} catch {
    Write-Host "[!] ViaVersion download skipped or failed (optional plugin)." -ForegroundColor Gray
}

Write-Host "`n======================================================================" -ForegroundColor Cyan
Write-Host "  All files downloaded! Double-click 'start.bat' to launch your server!" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Cyan
