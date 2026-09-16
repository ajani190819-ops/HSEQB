# =====================================================================
#  Keyboard Lighting - updater
#
#  Downloads the latest version of every script into this folder.
#  You normally never run this directly - use Update.bat, or the
#  "Check for updates" link at the bottom of the control panel.
# =====================================================================

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Base = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting'

$Files = @(
    'Aura-Background.ps1',
    'Lighting-Panel.ps1',
    'Lighting-Panel.bat','Tray.ps1','Install.ps1','Install.bat',
    'Update.bat',
    'Update.ps1',
    'Check.bat',
    'Check.ps1',
    'MyEffect.ps1',
    'Find-Lamps.ps1',
    'Install-Autostart.ps1',
    'README.md'
)

Write-Host ''
Write-Host '  Keyboard Lighting - checking for updates' -ForegroundColor Cyan
Write-Host ''

try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12' } catch { }

$updated = 0
$same    = 0
$failed  = @()

foreach ($f in $Files) {
    $dest = Join-Path $Here $f
    $tmp  = Join-Path $env:TEMP ('kbl_' + $f)
    try {
        Invoke-WebRequest "$Base/$f" -OutFile $tmp -UseBasicParsing -TimeoutSec 25

        $newHash = (Get-FileHash $tmp -Algorithm SHA256).Hash
        $oldHash = ''
        if (Test-Path $dest) { $oldHash = (Get-FileHash $dest -Algorithm SHA256).Hash }

        if ($newHash -ne $oldHash) {
            Copy-Item $tmp $dest -Force
            Unblock-File $dest -ErrorAction SilentlyContinue
            Write-Host ('   updated    ' + $f) -ForegroundColor Green
            $updated++
        } else {
            Write-Host ('   unchanged  ' + $f) -ForegroundColor DarkGray
            $same++
        }
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Host ('   FAILED     ' + $f) -ForegroundColor Red
        $failed += $f
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ('  Could not download ' + $failed.Count + ' file(s).') -ForegroundColor Yellow
    Write-Host '  Check your internet connection and run this again.' -ForegroundColor Yellow
} elseif ($updated -gt 0) {
    Write-Host ('  Done. ' + $updated + ' file(s) updated.') -ForegroundColor Green
} else {
    Write-Host '  Already up to date.' -ForegroundColor Green
}
Write-Host ''
