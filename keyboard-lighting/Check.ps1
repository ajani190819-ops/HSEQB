# =====================================================================
#  Keyboard Lighting - diagnostic
#
#  Runs every stage of the lighting engine one at a time and reports
#  exactly which one fails. Nothing is hidden, nothing is quiet.
#
#  When it finishes it saves a report to your Desktop, opens it in
#  Notepad, and copies it to the clipboard so you can just paste it.
#
#  Run it with Check.bat (which asks for Administrator).
# =====================================================================

$ErrorActionPreference = 'Continue'

$script:Report = New-Object System.Collections.ArrayList

function Log($t)  { [void]$script:Report.Add($t) }
function Line($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c; Log $t }
function Head($t) {
    Write-Host ''
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 62)) -ForegroundColor DarkGray
    Log ''
    Log "  $t"
    Log ('  ' + ('-' * 62))
}
function Pass($t) { Write-Host '   [PASS] ' -ForegroundColor Green  -NoNewline; Write-Host $t; Log "   [PASS] $t" }
function Fail($t) { Write-Host '   [FAIL] ' -ForegroundColor Red    -NoNewline; Write-Host $t; Log "   [FAIL] $t" }
function Warn($t) { Write-Host '   [WARN] ' -ForegroundColor Yellow -NoNewline; Write-Host $t; Log "   [WARN] $t" }
function Info($t) { Write-Host '          ' -NoNewline; Write-Host $t -ForegroundColor Gray; Log "          $t" }

$problems = New-Object System.Collections.ArrayList

Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor Cyan
Write-Host '   KEYBOARD LIGHTING - DIAGNOSTIC  (check v11)' -ForegroundColor Cyan
Write-Host '  ===============================================================' -ForegroundColor Cyan
Log '  ==============================================================='
Log '   KEYBOARD LIGHTING - DIAGNOSTIC  (check v11)'
Log '  ==============================================================='
Log ("   {0}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    Log ("   Windows {0} (build {1})" -f $os.Caption, $os.BuildNumber)
    Log ("   PowerShell {0}" -f $PSVersionTable.PSVersion.ToString())
} catch { }

$here = Split-Path -Parent $MyInvocation.MyCommand.Path

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
    [void]$problems.Add('Right-click Check.bat and choose "Run as administrator".')
}

# ---------------------------------------------------------------- 2. files
Head '2. Script files'
$want = @('Aura-Background.ps1','Lighting-Panel.ps1','Lighting-Panel.bat','Tray.ps1','Install.ps1','Install.bat',
          'Update.bat','Update.ps1','Check.bat','Check.ps1')
foreach ($f in $want) {
    $p = Join-Path $here $f
    if (Test-Path $p) {
        $i = Get-Item $p
        Info ("{0,-22} {1,7} bytes   {2}" -f $f, $i.Length, $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))
    } else {
        Fail ("{0} is MISSING" -f $f)
        [void]$problems.Add("Run Update.bat - $f is missing.")
    }
}

# ---------------------------------------------------------------- 3. dynamic lighting
Head '3. Windows Dynamic Lighting'
$dlOn = $null
try {
    $k = 'HKCU:\Software\Microsoft\Lighting'
    if (Test-Path $k) {
        $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
        if ($null -ne $p.AmbientLightingEnabled)    { $dlOn = [bool]$p.AmbientLightingEnabled }
        if ($null -ne $p.ControlledByForegroundApp) { Info ("ControlledByForegroundApp = {0}" -f $p.ControlledByForegroundApp) }
    }
} catch { }
if ($dlOn -eq $true) {
    Fail 'Dynamic Lighting appears to be ON. It holds the keyboard exclusively.'
    [void]$problems.Add('Turn OFF Settings > Personalization > Dynamic Lighting.')
} elseif ($dlOn -eq $false) {
    Pass 'Dynamic Lighting is off.'
} else {
    Warn 'Could not read the Dynamic Lighting setting (not fatal).'
    Info 'Check manually: Settings > Personalization > Dynamic Lighting = Off'
}

# ---------------------------------------------------------------- 4. other software
Head '4. Competing lighting software'
$bad = @('ArmouryCrate','ArmouryCrate.UserSessionHelper','ArmouryQtService',
         'LightingService','AsusSystemAnalysis','AsusOptimization',
         'GHelper','OpenRGB','SignalRgb','iCUE','msi-center')
$found = @()
foreach ($b in $bad) {
    if (Get-Process -Name $b -ErrorAction SilentlyContinue) { $found += $b }
}
if ($found.Count -eq 0) { Pass 'No competing lighting software running.' }
else {
    Warn ('Running: ' + ($found -join ', '))
    Info 'These can take exclusive control of the keyboard.'
    [void]$problems.Add('Close: ' + ($found -join ', '))
}

# ---------------------------------------------------------------- 5. device
Head '5. Keyboard device'
$dev = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
       Where-Object { $_.DeviceID -like '*VID_0B05&PID_19B6*' }
if ($dev) {
    Pass ("{0} interfaces found for VID_0B05 PID_19B6" -f @($dev).Count)
    foreach ($d in $dev) { Info $d.DeviceID }
} else {
    Fail 'Keyboard HID device VID_0B05 PID_19B6 not found at all.'
    [void]$problems.Add('The keyboard HID device is missing from Device Manager.')
}

# ---------------------------------------------------------------- 6. engine
Head '6. Lighting engine'
$engine = Join-Path $here 'Aura-Background.ps1'
if (-not (Test-Path $engine)) {
    Fail "Aura-Background.ps1 is missing from $here"
    [void]$problems.Add('Run Update.bat to download the missing files.')
} else {
    Pass 'Aura-Background.ps1 found.'
    Info 'Running it for 5 seconds with all messages shown...'
    Write-Host ''
    Write-Host '  ---------------- engine output ----------------' -ForegroundColor DarkGray
    Log ''
    Log '  ---------------- engine output ----------------'

    $outLog = Join-Path $env:TEMP 'kbl_engine_out.txt'
    $errLog = Join-Path $env:TEMP 'kbl_engine_err.txt'
    foreach ($f in @($outLog, $errLog)) {
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }

    $proc = Start-Process -FilePath 'powershell.exe' -PassThru -NoNewWindow `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',
                            ('"{0}"' -f $engine),'-Effect','static','-Color','#FF0000')

    if (-not $proc.WaitForExit(5000)) {
        Start-Sleep -Milliseconds 500
        try { $proc.Kill() } catch { }
    }
    Start-Sleep -Milliseconds 400

    $out = ''
    $err = ''
    if (Test-Path $outLog) { $out = (Get-Content $outLog -Raw) }
    if (Test-Path $errLog) { $err = (Get-Content $errLog -Raw) }

    if ($out) { Write-Host $out; Log $out } else { Write-Host '  (no output)' -ForegroundColor DarkGray; Log '  (no output)' }

    if ($err -and $err.Trim().Length -gt 0) {
        Write-Host ''
        Write-Host '  ---------------- ERRORS ----------------' -ForegroundColor Red
        Write-Host $err -ForegroundColor Red
        Log ''
        Log '  ---------------- ERRORS ----------------'
        Log $err
    }

    Write-Host '  -----------------------------------------------' -ForegroundColor DarkGray
    Log '  -----------------------------------------------'

    $all = "$out`n$err"

    if ($err -match 'Add-Type|Cannot add type|compiler') {
        Fail 'The compiled engine failed to build.'
        [void]$problems.Add('The C# engine did not compile - the ERRORS section above has the reason.')
    } elseif ($all -match 'No LampArray HID interface found') {
        Fail 'The engine cannot see a LampArray interface.'
        [void]$problems.Add('LampArray interface not found - the keyboard may be claimed by another process.')
    } elseif ($all -match 'Cannot open device') {
        Fail 'The engine found the keyboard but could not open it.'
        [void]$problems.Add('Device open refused - needs Administrator, or another app holds it.')
    } elseif ($all -match 'Could not resolve the multi-update') {
        Fail 'Report layout could not be resolved.'
        [void]$problems.Add('Layout detail is in the engine output above - send me this report.')
    } elseif ($all -match 'Solid colour applied') {
        Pass 'The engine reported success.'
        Write-Host ''
        Write-Host '   >>> Did the keyboard just flash RED? <<<' -ForegroundColor Yellow
        Log ''
        Log '   >>> Did the keyboard just flash RED? <<<'
    } elseif ($all -match 'zones,') {
        Pass 'The engine started and talked to the keyboard.'
    } else {
        Warn 'The engine produced no recognisable result.'
        [void]$problems.Add('Engine gave no usable output - send me this report.')
    }
}

# ---------------------------------------------------------------- summary
Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor Cyan
Write-Host '   SUMMARY' -ForegroundColor Cyan
Write-Host '  ===============================================================' -ForegroundColor Cyan
Log ''
Log '  ==============================================================='
Log '   SUMMARY'
Log '  ==============================================================='
Write-Host ''
Log ''
if ($problems.Count -eq 0) {
    Line '   No problems detected.' 'Green'
} else {
    Line '   Fix these, in order:' 'Yellow'
    Line ''
    $i = 1
    foreach ($x in $problems) { Line ("    {0}. {1}" -f $i, $x) 'White'; $i++ }
}

# ---------------------------------------------------------------- deliver
$text = ($script:Report -join "`r`n")

$desktop = [Environment]::GetFolderPath('Desktop')
if (-not $desktop -or -not (Test-Path $desktop)) { $desktop = $here }
$reportPath = Join-Path $desktop 'Keyboard-Lighting-Report.txt'

$saved = $false
try { Set-Content -Path $reportPath -Value $text -Encoding UTF8; $saved = $true } catch { }

$copied = $false
try { Set-Clipboard -Value $text; $copied = $true }
catch {
    try { $text | clip.exe; $copied = $true } catch { }
}

Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor Green
Write-Host '   YOUR REPORT' -ForegroundColor Green
Write-Host '  ===============================================================' -ForegroundColor Green
Write-Host ''
if ($copied) {
    Write-Host '   It is already COPIED TO YOUR CLIPBOARD.' -ForegroundColor Green
    Write-Host '   Just click the chat and press Ctrl+V.' -ForegroundColor Green
    Write-Host ''
}
if ($saved) {
    Write-Host '   Also saved to your Desktop as:' -ForegroundColor Gray
    Write-Host '      Keyboard-Lighting-Report.txt' -ForegroundColor White
    Write-Host ''
    Write-Host '   Opening it in Notepad now...' -ForegroundColor Gray
    try { Start-Process notepad.exe $reportPath } catch { }
} else {
    Write-Host '   Could not save the file - use the clipboard copy.' -ForegroundColor Yellow
}
Write-Host ''
Read-Host '  Press Enter to close'
