# =====================================================================
#  Keyboard Lighting - diagnostic
#
#  Runs every stage of the lighting engine one at a time and reports
#  exactly which one fails. Nothing is hidden, nothing is quiet.
#
#  Run it with Check.bat (which asks for Administrator).
# =====================================================================

$ErrorActionPreference = 'Continue'

function Head($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ('  ' + ('-' * 62)) -ForegroundColor DarkGray }
function Pass($t) { Write-Host '   [PASS] ' -ForegroundColor Green -NoNewline; Write-Host $t }
function Fail($t) { Write-Host '   [FAIL] ' -ForegroundColor Red   -NoNewline; Write-Host $t }
function Warn($t) { Write-Host '   [WARN] ' -ForegroundColor Yellow -NoNewline; Write-Host $t }
function Info($t) { Write-Host '          ' -NoNewline; Write-Host $t -ForegroundColor Gray }

$problems = New-Object System.Collections.ArrayList

Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor Cyan
Write-Host '   KEYBOARD LIGHTING - DIAGNOSTIC' -ForegroundColor Cyan
Write-Host '  ===============================================================' -ForegroundColor Cyan

# ---------------------------------------------------------------- 1. admin
Head '1. Administrator rights'
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    $isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
if ($isAdmin) { Pass 'Running as Administrator.' }
else {
    Fail 'NOT running as Administrator.'
    Info 'Direct keyboard access will be refused.'
    [void]$problems.Add('Run Check.bat by right-clicking it and choosing "Run as administrator".')
}

# ---------------------------------------------------------------- 2. dynamic lighting
Head '2. Windows Dynamic Lighting'
$dlOn = $null
try {
    $k = 'HKCU:\Software\Microsoft\Lighting'
    if (Test-Path $k) {
        $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($null -ne $p.AmbientLightingEnabled) { $dlOn = [bool]$p.AmbientLightingEnabled }
        if ($null -ne $p.ControlledByForegroundApp) { Info ("ControlledByForegroundApp = {0}" -f $p.ControlledByForegroundApp) }
    }
} catch { }
if ($dlOn -eq $true) {
    Fail 'Dynamic Lighting appears to be ON. It holds the keyboard exclusively.'
    [void]$problems.Add('Turn OFF Settings > Personalization > Dynamic Lighting.')
} elseif ($dlOn -eq $false) {
    Pass 'Dynamic Lighting is off.'
} else {
    Warn 'Could not read the Dynamic Lighting setting (this is not fatal).'
    Info 'Check manually: Settings > Personalization > Dynamic Lighting = Off'
}

# ---------------------------------------------------------------- 3. other software
Head '3. Competing lighting software'
$bad = @('ArmouryCrate','ArmouryCrate.UserSessionHelper','ArmouryQtService',
         'LightingService','AsusSystemAnalysis','AsusOptimization',
         'GHelper','OpenRGB','SignalRgb','iCUE','msi-center')
$found = @()
foreach ($b in $bad) {
    $p = Get-Process -Name $b -ErrorAction SilentlyContinue
    if ($p) { $found += $b }
}
if ($found.Count -eq 0) { Pass 'No competing lighting software running.' }
else {
    Warn ('Running: ' + ($found -join ', '))
    Info 'These can take exclusive control of the keyboard.'
    [void]$problems.Add('Close: ' + ($found -join ', '))
}

# ---------------------------------------------------------------- 4. device present
Head '4. Keyboard device'
$dev = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
       Where-Object { $_.DeviceID -like '*VID_0B05&PID_19B6*' }
if ($dev) {
    foreach ($d in $dev) { Pass ("Found: {0}" -f $d.Name); Info $d.DeviceID }
} else {
    Fail 'Keyboard HID device VID_0B05 PID_19B6 not found at all.'
    [void]$problems.Add('The keyboard HID device is missing from Device Manager.')
}

# ---------------------------------------------------------------- 5. engine
Head '5. Lighting engine'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$engine = Join-Path $here 'Aura-Background.ps1'
if (-not (Test-Path $engine)) {
    Fail "Aura-Background.ps1 is missing from $here"
    [void]$problems.Add('Run Update.bat to download the missing files.')
} else {
    Pass 'Aura-Background.ps1 found.'
    Info 'Running it for 4 seconds with all messages shown...'
    Write-Host ''
    Write-Host '  ---------------- engine output ----------------' -ForegroundColor DarkGray

    $log = Join-Path $env:TEMP 'kbl_engine_check.txt'
    if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }

    $p = Start-Process -FilePath 'powershell.exe' -PassThru -NoNewWindow `
         -RedirectStandardOutput $log `
         -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',
                         ('"{0}"' -f $engine),'-Effect','static','-Color','#FF0000')

    $exited = $p.WaitForExit(4000)
    if (-not $exited) {
        Start-Sleep -Milliseconds 500
        try { $p.Kill() } catch { }
    }
    Start-Sleep -Milliseconds 300

    $out = ''
    if (Test-Path $log) { $out = (Get-Content $log -Raw) }
    if ($out) { Write-Host $out } else { Write-Host '  (no output)' -ForegroundColor DarkGray }
    Write-Host '  -----------------------------------------------' -ForegroundColor DarkGray

    if ($out -match 'No LampArray HID interface found') {
        Fail 'The engine cannot see a LampArray interface.'
        [void]$problems.Add('LampArray interface not found - the keyboard may be claimed by another process.')
    } elseif ($out -match 'Cannot open device') {
        Fail 'The engine found the keyboard but could not open it.'
        [void]$problems.Add('Device open refused - needs Administrator, or another app holds it.')
    } elseif ($out -match 'Could not resolve the multi-update') {
        Fail 'Report layout could not be resolved.'
        [void]$problems.Add('Send me the output of Find-Lamps.ps1.')
    } elseif ($out -match 'Solid colour applied') {
        Pass 'The engine reported success.'
        Write-Host ''
        Write-Host '   >>> Did the keyboard just flash RED? <<<' -ForegroundColor Yellow
    } elseif ($out -match 'zones,') {
        Pass 'The engine started and talked to the keyboard.'
    } else {
        Warn 'The engine produced no recognisable result.'
        [void]$problems.Add('Engine gave no output - copy the engine output section above.')
    }
}

# ---------------------------------------------------------------- summary
Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor Cyan
Write-Host '   SUMMARY' -ForegroundColor Cyan
Write-Host '  ===============================================================' -ForegroundColor Cyan
Write-Host ''
if ($problems.Count -eq 0) {
    Write-Host '   No problems detected.' -ForegroundColor Green
    Write-Host '   If the keyboard still does not light up, copy everything' -ForegroundColor Gray
    Write-Host '   above and send it to me.' -ForegroundColor Gray
} else {
    Write-Host '   Fix these, in order:' -ForegroundColor Yellow
    Write-Host ''
    $i = 1
    foreach ($x in $problems) { Write-Host ("    {0}. {1}" -f $i, $x) -ForegroundColor White; $i++ }
}
Write-Host ''
Write-Host '  Copy this whole window and send it to me.' -ForegroundColor Cyan
Write-Host ''
Read-Host '  Press Enter to close'
