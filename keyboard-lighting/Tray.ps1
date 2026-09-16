# =====================================================================
#  Keyboard Lighting
#
#  The whole application. One process:
#    - the window you see
#    - the tray icon next to the clock
#    - the settings, saved and restored
#    - the background updater
#
#  The only separate process is the lighting engine itself, which is
#  started with CreateNoWindow so no console ever appears. Settings
#  changes are sent to it live through a small state file, so nothing
#  is torn down and restarted while you are adjusting things.
#
#  Launched by KeyboardLighting.exe.
# =====================================================================

param(
    [switch]$NoUpdate,      # skip the update check
    [switch]$Silent,        # start in the tray without showing the window
    [switch]$NoElevate      # internal: do not try to elevate again
)

$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- paths
$Here      = Split-Path -Parent $MyInvocation.MyCommand.Path
$Engine    = Join-Path $Here 'Aura-Background.ps1'
$CfgDir    = Join-Path $env:LOCALAPPDATA 'KeyboardLighting'
$CfgFile   = Join-Path $CfgDir 'panel.json'
$LiveFile  = Join-Path $CfgDir 'live.txt'
$ThemeFile = Join-Path $CfgDir 'theme.json'
$LogFile   = Join-Path $CfgDir 'log.txt'
$TaskName  = 'KeyboardLighting'
$Base      = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting'

if (-not (Test-Path $CfgDir)) { New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null }

# ---------------------------------------------------------------- logging
function Log($msg, $level = 'INFO') {
    $line = '{0}  {1,-5}  {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $level, $msg
    try {
        Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        $fi = Get-Item $LogFile -ErrorAction SilentlyContinue
        if ($fi -and $fi.Length -gt 262144) {
            $keep = Get-Content $LogFile -Tail 400 -ErrorAction SilentlyContinue
            Set-Content -Path $LogFile -Value $keep -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch { }
}

Log '---------------- starting ----------------'

# ---------------------------------------------------------------- single instance
# Autostart runs this elevated; clicking the Start-menu icon starts a
# normal-privilege copy. Windows blocks the lower one from signalling a
# kernel object owned by the higher one, so the handshake goes through
# files in the user's own AppData instead - readable and writable from
# both, and checked BEFORE any elevation prompt.
$LockFile = Join-Path $CfgDir 'running.lock'
$ShowFile = Join-Path $CfgDir 'show.flag'

function Test-AlreadyRunning {
    if (-not (Test-Path $LockFile)) { return $false }
    try {
        $age = (Get-Date) - (Get-Item $LockFile).LastWriteTime
        # The live instance refreshes this every 2s. Anything older than
        # 15s is a leftover from a crash or a hard power-off.
        return ($age.TotalSeconds -lt 15)
    } catch { return $false }
}

if (Test-AlreadyRunning) {
    Log 'already running - asking that copy to show its window'
    try { Set-Content -Path $ShowFile -Value ([DateTime]::UtcNow.Ticks) -Encoding ASCII -ErrorAction SilentlyContinue } catch { }
    return
}

function Update-Heartbeat {
    try { Set-Content -Path $LockFile -Value $PID -Encoding ASCII -ErrorAction SilentlyContinue } catch { }
}
Update-Heartbeat

# ---------------------------------------------------------------- admin
function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}
$IsAdmin = Test-IsAdmin
Log ("administrator: {0}" -f $IsAdmin)

# Direct keyboard access needs Administrator. The scheduled task already
# runs elevated, so this only ever prompts on a manual launch.
if (-not $IsAdmin -and -not $NoElevate) {
    Log 'not elevated - relaunching'
    try {
        $relArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
                     '-File', ('"{0}"' -f $PSCommandPath), '-NoElevate')
        if ($Silent)   { $relArgs += '-Silent' }
        if ($NoUpdate) { $relArgs += '-NoUpdate' }
        try { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue } catch { }
        Start-Process -FilePath 'powershell.exe' -ArgumentList $relArgs -Verb RunAs | Out-Null
        return
    } catch {
        Log 'elevation refused - continuing without it' 'WARN'
        Update-Heartbeat
    }
}

# ---------------------------------------------------------------- config
$Effects = [ordered]@{
    'Scrolling gradient' = 'gradient'
    'Rainbow'            = 'rainbow'
    'Wave'               = 'wave'
    'Comet'              = 'comet'
    'Scanner'            = 'scanner'
    'Breathing'          = 'breathe'
    'Pulse'              = 'pulse'
    'Fire'               = 'fire'
    'Solid colour'       = 'static'
}

$script:Swatches = @('#FF0000','#FF7F00','#FFFF00','#00FF00','#0000FF','#8B00FF')
$script:Cfg = [pscustomobject]@{
    Effect     = 'Scrolling gradient'
    Speed      = 10
    Brightness = 100
    Mirror     = $false
    Reverse    = $false
    Equalise   = $true
    Loop       = $true
}
$script:Suppress  = $true    # no live updates until the window has loaded
$script:Quitting  = $false
$script:WantOff   = $false
$script:EngineP   = $null
$script:PalGain   = @()
$script:phase     = 0.0

function Load-Cfg {
    if (-not (Test-Path $CfgFile)) { return }
    try {
        $o = Get-Content $CfgFile -Raw | ConvertFrom-Json
        if ($o.Swatches) { $script:Swatches = @($o.Swatches) }
        foreach ($p in 'Effect','Speed','Brightness','Mirror','Reverse','Equalise','Loop') {
            if ($null -ne $o.$p) { $script:Cfg.$p = $o.$p }
        }
        Log 'settings loaded'
    } catch { Log ("settings load failed: {0}" -f $_.Exception.Message) 'WARN' }
}
Load-Cfg

function Save-Cfg {
    $o = [pscustomobject]@{
        Effect     = $script:Cfg.Effect
        Swatches   = $script:Swatches
        Speed      = $script:Cfg.Speed
        Brightness = $script:Cfg.Brightness
        Mirror     = $script:Cfg.Mirror
        Reverse    = $script:Cfg.Reverse
        Equalise   = $script:Cfg.Equalise
        Loop       = $script:Cfg.Loop
    }
    try { $o | ConvertTo-Json -Depth 4 | Set-Content -Path $CfgFile -Encoding UTF8 } catch { }
}

# ---------------------------------------------------------------- engine
function Get-EffectToken {
    $t = $Effects[[string]$script:Cfg.Effect]
    if (-not $t) { $t = 'gradient' }
    return $t
}

# Send the current settings to a running engine. It picks them up within
# about a tenth of a second, so the keyboard follows the controls live
# instead of being restarted.
function Write-Theme {
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $o = [pscustomobject]@{
        Effect     = Get-EffectToken
        Colors     = ($script:Swatches -join ',')
        Speed      = [double]$script:Cfg.Speed / 10.0
        Brightness = [double]$script:Cfg.Brightness / 100.0
        Mirror     = [bool]$script:Cfg.Mirror
        Reverse    = [bool]$script:Cfg.Reverse
        Equalise   = [bool]$script:Cfg.Equalise
        Loop       = [bool]$script:Cfg.Loop
    }
    try { $o | ConvertTo-Json -Depth 4 | Set-Content -Path $ThemeFile -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
}

function Write-LiveBrightness {
    try {
        $lvl = [int]([Math]::Round([double]$script:Cfg.Brightness * 10))
        if ($lvl -lt 0) { $lvl = 0 }
        if ($lvl -gt 1000) { $lvl = 1000 }
        Set-Content -Path $LiveFile -Value $lvl -Encoding ASCII -ErrorAction SilentlyContinue
    } catch { }
}

function Stop-Engine {
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*Aura-Background*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
    $script:EngineP = $null
}

function Test-EngineAlive {
    if (-not $script:EngineP) { return $false }
    try { return (-not $script:EngineP.HasExited) } catch { return $false }
}

# Start the engine with no console window at all. -WindowStyle Hidden
# still creates a console and then hides it, which is the flash you used
# to see; CreateNoWindow never creates one.
function Start-Engine {
    Stop-Engine
    Start-Sleep -Milliseconds 200
    if (-not (Test-Path $Engine)) { Log 'engine script missing' 'ERROR'; return $false }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $eff = Get-EffectToken
    $spd = ([double]$script:Cfg.Speed / 10.0).ToString('0.##', $inv)
    $brt = ([double]$script:Cfg.Brightness / 100.0).ToString('0.##', $inv)
    $lay = 'across'
    if ($script:Cfg.Loop) { $lay = 'loop' }
    $eqv = 'off'
    if ($script:Cfg.Equalise) { $eqv = 'on' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "')
    [void]$sb.Append($Engine)
    [void]$sb.Append('" -Effect ');     [void]$sb.Append($eff)
    [void]$sb.Append(' -Speed ');       [void]$sb.Append($spd)
    [void]$sb.Append(' -Brightness ');  [void]$sb.Append($brt)
    [void]$sb.Append(' -Fps 60 -Quiet')
    if ($script:Swatches.Count -gt 0) {
        [void]$sb.Append(' -Colors "'); [void]$sb.Append(($script:Swatches -join ',')); [void]$sb.Append('"')
        [void]$sb.Append(' -Color "');  [void]$sb.Append($script:Swatches[0]); [void]$sb.Append('"')
        if ($script:Swatches.Count -gt 1) {
            [void]$sb.Append(' -Color2 "'); [void]$sb.Append($script:Swatches[1]); [void]$sb.Append('"')
        }
    }
    if ($script:Cfg.Mirror)  { [void]$sb.Append(' -Mirror') }
    if ($script:Cfg.Reverse) { [void]$sb.Append(' -Reverse') }
    [void]$sb.Append(' -Equalise '); [void]$sb.Append($eqv)
    [void]$sb.Append(' -Layout ');   [void]$sb.Append($lay)

    # Keep the live files consistent with what we are about to launch, so a
    # stale value from the last session cannot override the saved theme.
    Write-LiveBrightness
    Write-Theme

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName        = 'powershell.exe'
        $psi.Arguments       = $sb.ToString()
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        $psi.WindowStyle     = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $psi.WorkingDirectory = $Here
        $script:EngineP = [System.Diagnostics.Process]::Start($psi)
        $script:WantOff = $false
        Start-Sleep -Milliseconds 900
        if ($script:EngineP.HasExited) {
            Log ("engine exited immediately (effect={0})" -f $eff) 'ERROR'
            $script:EngineP = $null
            return $false
        }
        Log ("engine started: effect={0} speed={1} bright={2} layout={3}" -f $eff,$spd,$brt,$lay)
        return $true
    } catch {
        Log ("engine start failed: {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Set-AllOff {
    Stop-Engine
    $script:WantOff = $true
    if (-not (Test-Path $Engine)) { return }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName        = 'powershell.exe'
        $psi.Arguments       = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Effect off -Quiet' -f $Engine)
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        $p = [System.Diagnostics.Process]::Start($psi)
        [void]$p.WaitForExit(6000)
    } catch { Log ("turn off failed: {0}" -f $_.Exception.Message) 'WARN' }
    Log 'lighting turned off'
}

# ---------------------------------------------------------------- autostart
function Test-Autostart {
    try { return [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) }
    catch { return $false }
}

function Set-Autostart([bool]$on) {
    try {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        if (-not $on) { Log 'autostart removed'; return $true }

        $exe = Join-Path $Here 'KeyboardLighting.exe'
        if (Test-Path $exe) {
            $act = New-ScheduledTaskAction -Execute $exe -Argument '-Silent' -WorkingDirectory $Here
        } else {
            $act = New-ScheduledTaskAction -Execute 'powershell.exe' `
                   -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Silent -NoElevate' -f $PSCommandPath) `
                   -WorkingDirectory $Here
        }
        $trg  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $prin = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        $set  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
        Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg `
            -Principal $prin -Settings $set -Description 'Keyboard lighting' -Force | Out-Null
        Log 'autostart installed'
        return $true
    } catch {
        Log ("autostart change failed: {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

# ---------------------------------------------------------------- update
function Invoke-SelfUpdate {
    $files = @('Aura-Background.ps1','Lighting-Panel.ps1','Tray.ps1','Install.ps1','Install.bat',
               'Check.ps1','Check.bat','Update.ps1','Update.bat',
               'Lighting-Panel.bat','MyEffect.ps1','Find-Lamps.ps1','README.md','app.ico')
    $changed = @()
    try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12' } catch { }
    foreach ($f in $files) {
        $dest = Join-Path $Here $f
        $tmp  = Join-Path $env:TEMP ('kblu_' + $f)
        try {
            Invoke-WebRequest "$Base/$f" -OutFile $tmp -UseBasicParsing -TimeoutSec 20
            $new = (Get-FileHash $tmp -Algorithm SHA256).Hash
            $old = ''
            if (Test-Path $dest) { $old = (Get-FileHash $dest -Algorithm SHA256).Hash }
            if ($new -ne $old) {
                Copy-Item $tmp $dest -Force
                Unblock-File $dest -ErrorAction SilentlyContinue
                $changed += $f
            }
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        } catch { }
    }
    if ($changed.Count -gt 0) { Log ("updated: {0}" -f ($changed -join ', ')) }
    else { Log 'already up to date' }
    return $changed
}

# ---------------------------------------------------------------- icon
function New-AppIcon {
    # Prefer the real icon file so the window, taskbar and tray all match
    # the Start menu entry. Fall back to drawing one if it is missing.
    $ico = Join-Path $Here 'app.ico'
    if (Test-Path $ico) {
        try { return (New-Object System.Drawing.Icon $ico) } catch { }
    }
    $bmp = New-Object System.Drawing.Bitmap 32,32
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $body = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(238,242,252))
    $g.FillRectangle($body, 2, 9, 28, 16)
    $cols = @(
        [System.Drawing.Color]::FromArgb(255,60,60),
        [System.Drawing.Color]::FromArgb(255,170,0),
        [System.Drawing.Color]::FromArgb(70,220,110),
        [System.Drawing.Color]::FromArgb(0,170,255),
        [System.Drawing.Color]::FromArgb(160,90,255)
    )
    for ($i = 0; $i -lt 5; $i++) {
        $b = New-Object System.Drawing.SolidBrush $cols[$i]
        $g.FillRectangle($b, (4 + $i*5.4), 12, 4, 4)
        $b.Dispose()
    }
    $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(60,64,80))
    $g.FillRectangle($dark, 7, 19, 18, 3)
    $body.Dispose(); $dark.Dispose(); $g.Dispose()
    $h = $bmp.GetHicon()
    return [System.Drawing.Icon]::FromHandle($h)
}
$AppIcon = New-AppIcon

# ---------------------------------------------------------------- window
$bg    = [System.Drawing.Color]::FromArgb(24,26,34)
$card  = [System.Drawing.Color]::FromArgb(34,37,48)
$fg    = [System.Drawing.Color]::FromArgb(232,234,240)
$muted = [System.Drawing.Color]::FromArgb(140,147,167)

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Keyboard Lighting'
$form.ClientSize      = New-Object System.Drawing.Size(470, 646)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.BackColor       = $bg
$form.ForeColor       = $fg
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9.5)
$form.Icon            = $AppIcon
$form.ShowInTaskbar   = $true

function New-Label($text, $x, $y, $w, $col, $size, $bold) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = New-Object System.Drawing.Point($x, $y)
    $l.Size      = New-Object System.Drawing.Size($w, 22)
    $l.ForeColor = $col
    $style = [System.Drawing.FontStyle]::Regular
    if ($bold) { $style = [System.Drawing.FontStyle]::Bold }
    $l.Font      = New-Object System.Drawing.Font('Segoe UI', $size, $style)
    $form.Controls.Add($l)
    return $l
}

$y = 18
New-Label 'Keyboard Lighting' 24 $y 300 $fg 14 $true | Out-Null
$y += 30
$lblSub = New-Label 'ROG Strix G16  -  16 zones' 24 $y 340 $muted 8.5 $false

# ---- pattern ----
$y += 34
New-Label 'PATTERN' 24 $y 200 $muted 8 $true | Out-Null
$y += 24
$cboEffect = New-Object System.Windows.Forms.ComboBox
$cboEffect.Location      = New-Object System.Drawing.Point(24, $y)
$cboEffect.Size          = New-Object System.Drawing.Size(418, 28)
$cboEffect.DropDownStyle = 'DropDownList'
$cboEffect.BackColor     = $card
$cboEffect.ForeColor     = $fg
$cboEffect.FlatStyle     = 'Flat'
$cboEffect.Font          = New-Object System.Drawing.Font('Segoe UI', 10)
foreach ($k in $Effects.Keys) { [void]$cboEffect.Items.Add($k) }
$cboEffect.SelectedIndex = 0
$form.Controls.Add($cboEffect)

# ---- colours ----
$y += 40
New-Label 'COLOURS    (click a square to change it)' 24 $y 380 $muted 8 $true | Out-Null
$y += 24
$pnlCol = New-Object System.Windows.Forms.Panel
$pnlCol.Location  = New-Object System.Drawing.Point(24, $y)
$pnlCol.Size      = New-Object System.Drawing.Size(418, 46)
$pnlCol.BackColor = $bg
$form.Controls.Add($pnlCol)

# ---- preview ----
$y += 58
New-Label 'PREVIEW' 24 $y 200 $muted 8 $true | Out-Null
$y += 22
$pbPreview = New-Object System.Windows.Forms.PictureBox
$pbPreview.Location  = New-Object System.Drawing.Point(24, $y)
$pbPreview.Size      = New-Object System.Drawing.Size(418, 38)
$pbPreview.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($pbPreview)

# ---- speed ----
$y += 52
$lblSpeed = New-Label 'SPEED' 24 $y 200 $muted 8 $true
$y += 22
$trkSpeed = New-Object System.Windows.Forms.TrackBar
$trkSpeed.Location   = New-Object System.Drawing.Point(20, $y)
$trkSpeed.Size       = New-Object System.Drawing.Size(426, 40)
$trkSpeed.Minimum    = 1
$trkSpeed.Maximum    = 50
$trkSpeed.Value      = 10
$trkSpeed.TickFrequency = 5
$trkSpeed.BackColor  = $bg
$form.Controls.Add($trkSpeed)

# ---- brightness ----
$y += 44
$lblBright = New-Label 'BRIGHTNESS' 24 $y 250 $muted 8 $true
$y += 22
$trkBright = New-Object System.Windows.Forms.TrackBar
$trkBright.Location   = New-Object System.Drawing.Point(20, $y)
$trkBright.Size       = New-Object System.Drawing.Size(426, 40)
$trkBright.Minimum    = 5
$trkBright.Maximum    = 100
$trkBright.Value      = 100
$trkBright.TickFrequency = 10
$trkBright.BackColor  = $bg
$form.Controls.Add($trkBright)

# ---- options ----
$y += 46
New-Label 'OPTIONS' 24 $y 200 $muted 8 $true | Out-Null
$y += 24

function New-Check($text, $x, $yy, $w) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text      = $text
    $c.Location  = New-Object System.Drawing.Point($x, $yy)
    $c.Size      = New-Object System.Drawing.Size($w, 24)
    $c.ForeColor = $fg
    $c.FlatStyle = 'Flat'
    $form.Controls.Add($c)
    return $c
}

$chkMirror  = New-Check 'Mirror'              24  $y 200
$chkReverse = New-Check 'Reverse direction'  244  $y 200
$y += 26
$chkLoop    = New-Check 'Wrap around the light bar'  24 $y 220
$chkEq      = New-Check 'Even colour brightness'    244 $y 210
$y += 26
$chkAuto    = New-Check 'Start when I log in'        24 $y 220
$chkTray    = New-Check 'Close button hides to tray' 244 $y 230
$chkTray.Checked = $true
$chkTray.Enabled = $false

# ---- status + buttons ----
$y += 36
$lblStatus = New-Label '  Starting...' 24 $y 418 $muted 9.5 $false
$lblStatus.BackColor = $card
$lblStatus.Size = New-Object System.Drawing.Size(418, 28)

$y += 38
function New-Button($text, $x, $yy, $w, $accent) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $text
    $b.Location  = New-Object System.Drawing.Point($x, $yy)
    $b.Size      = New-Object System.Drawing.Size($w, 36)
    $b.FlatStyle = 'Flat'
    $b.Cursor    = 'Hand'
    $b.ForeColor = $fg
    $b.BackColor = $card
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,64,80)
    if ($accent) {
        $b.BackColor = [System.Drawing.Color]::FromArgb(0,120,190)
        $b.Font      = New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Bold)
    }
    $form.Controls.Add($b)
    return $b
}

$btnOff  = New-Button 'Turn lighting off'  24 $y 200 $false
$btnHide = New-Button 'Hide to tray'      244 $y 198 $true

$y += 44
$lblHint = New-Label 'Changes apply to the keyboard as you make them.' 24 $y 418 $muted 8.5 $false

$FormBottom = $y + 22

# ---------------------------------------------------------------- preview maths
function Lin([double]$v) {
    $c = $v / 255.0
    if ($c -le 0.04045) { return $c / 12.92 }
    return [Math]::Pow((($c + 0.055) / 1.055), 2.4)
}
function Srgb([double]$l) {
    if ($l -le 0) { return 0.0 }
    if ($l -ge 1) { return 255.0 }
    if ($l -le 0.0031308) { return 12.92 * $l * 255.0 }
    return (1.055 * [Math]::Pow($l, (1.0/2.4)) - 0.055) * 255.0
}
function Luma([double]$lr, [double]$lg, [double]$lb) {
    return 0.2126*$lr + 0.7152*$lg + 0.0722*$lb
}
function Update-PalGain($pal) {
    $n = $pal.Count
    $g = New-Object double[] $n
    for ($i=0; $i -lt $n; $i++) { $g[$i] = 1.0 }
    if ($chkEq -and $chkEq.Checked -and $n -gt 0) {
        $logSum = 0.0; $cnt = 0
        for ($i=0; $i -lt $n; $i++) {
            $L = Luma (Lin $pal[$i].R) (Lin $pal[$i].G) (Lin $pal[$i].B)
            if ($L -gt 0.0005) { $logSum += [Math]::Log($L); $cnt++ }
        }
        if ($cnt -gt 0) {
            $target = [Math]::Exp($logSum / $cnt)
            for ($i=0; $i -lt $n; $i++) {
                $lr = Lin $pal[$i].R; $lg = Lin $pal[$i].G; $lb = Lin $pal[$i].B
                $L = Luma $lr $lg $lb
                if ($L -le 0.0005) { continue }
                $gain = [Math]::Pow(($target / $L), 0.5)
                $peak = [Math]::Max($lr, [Math]::Max($lg, $lb))
                if ($peak -gt 0 -and ($gain * $peak) -gt 1.0) { $gain = 1.0 / $peak }
                if ($gain -lt 0.25) { $gain = 0.25 }
                if ($gain -gt 4.00) { $gain = 4.00 }
                $g[$i] = $gain
            }
        }
    }
    $script:PalGain = $g
}

$pbPreview.Add_Paint({
    $gr = $_.Graphics
    $w  = $pbPreview.Width
    $h  = $pbPreview.Height
    $n  = 16
    $cw = $w / [double]$n
    $pal = @()
    foreach ($s in $script:Swatches) {
        try { $pal += ,([System.Drawing.ColorTranslator]::FromHtml($s)) }
        catch { $pal += ,([System.Drawing.Color]::Gray) }
    }
    if ($pal.Count -lt 2) { $pal += $pal[0] }
    $pc = $pal.Count
    $bright = $trkBright.Value / 100.0
    Update-PalGain $pal
    for ($i = 0; $i -lt $n; $i++) {
        $u0 = $i / [double]($n - 1)
        if ($chkLoop -and $chkLoop.Checked) { $u0 = $i / [double]$n }
        $f = (($u0 + $script:phase) % 1.0) * $pc
        if ($f -lt 0) { $f += $pc }
        $a = [int][Math]::Floor($f)
        $u = $f - $a
        $b2 = ($a + 1) % $pc
        $a  = $a % $pc
        $wgt = $u * $u * (3.0 - 2.0 * $u)
        $ga = $script:PalGain[$a]; $gb = $script:PalGain[$b2]
        $lr = (Lin $pal[$a].R) * $ga; $lr = $lr + (((Lin $pal[$b2].R) * $gb) - $lr) * $wgt
        $lg = (Lin $pal[$a].G) * $ga; $lg = $lg + (((Lin $pal[$b2].G) * $gb) - $lg) * $wgt
        $lb = (Lin $pal[$a].B) * $ga; $lb = $lb + (((Lin $pal[$b2].B) * $gb) - $lb) * $wgt
        $r  = [int]((Srgb $lr) * $bright)
        $gg = [int]((Srgb $lg) * $bright)
        $bb = [int]((Srgb $lb) * $bright)
        $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($r,$gg,$bb))
        $gr.FillRectangle($br, [float]($i*$cw), 0.0, [float]($cw+1), [float]$h)
        $br.Dispose()
    }
})

# ---------------------------------------------------------------- swatches
function Redraw-Swatches {
    $pnlCol.Controls.Clear()
    $x = 0
    for ($i = 0; $i -lt $script:Swatches.Count; $i++) {
        $b = New-Object System.Windows.Forms.Button
        $b.Size      = New-Object System.Drawing.Size(42, 42)
        $b.Location  = New-Object System.Drawing.Point($x, 0)
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize  = 2
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,64,80)
        $b.Cursor    = 'Hand'
        try { $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml($script:Swatches[$i]) }
        catch { $b.BackColor = [System.Drawing.Color]::Gray }
        $b.Tag = $i
        $b.Add_Click({
            $idx = $this.Tag
            $dlg = New-Object System.Windows.Forms.ColorDialog
            $dlg.FullOpen = $true
            try { $dlg.Color = [System.Drawing.ColorTranslator]::FromHtml($script:Swatches[$idx]) } catch { }
            if ($dlg.ShowDialog() -eq 'OK') {
                $script:Swatches[$idx] = '#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B
                Redraw-Swatches
                Request-Apply
            }
        })
        $pnlCol.Controls.Add($b)
        $x += 48
    }
    if ($script:Swatches.Count -lt 8) {
        $add = New-Object System.Windows.Forms.Button
        $add.Text      = '+'
        $add.Size      = New-Object System.Drawing.Size(34, 42)
        $add.Location  = New-Object System.Drawing.Point($x, 0)
        $add.FlatStyle = 'Flat'
        $add.BackColor = $card
        $add.ForeColor = $muted
        $add.Font      = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        $add.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,64,80)
        $add.Cursor    = 'Hand'
        $add.Add_Click({
            $script:Swatches += '#FFFFFF'
            Redraw-Swatches
            Request-Apply
        })
        $pnlCol.Controls.Add($add)
        $x += 40
    }
    if ($script:Swatches.Count -gt 2) {
        $rem = New-Object System.Windows.Forms.Button
        $rem.Text      = '-'
        $rem.Size      = New-Object System.Drawing.Size(34, 42)
        $rem.Location  = New-Object System.Drawing.Point($x, 0)
        $rem.FlatStyle = 'Flat'
        $rem.BackColor = $card
        $rem.ForeColor = $muted
        $rem.Font      = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
        $rem.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,64,80)
        $rem.Cursor    = 'Hand'
        $rem.Add_Click({
            if ($script:Swatches.Count -gt 2) {
                $script:Swatches = @($script:Swatches[0..($script:Swatches.Count-2)])
                Redraw-Swatches
                Request-Apply
            }
        })
        $pnlCol.Controls.Add($rem)
    }
}

# ---------------------------------------------------------------- live apply
function Sync-CfgFromUi {
    $script:Cfg.Effect     = [string]$cboEffect.SelectedItem
    $script:Cfg.Speed      = [int]$trkSpeed.Value
    $script:Cfg.Brightness = [int]$trkBright.Value
    $script:Cfg.Mirror     = [bool]$chkMirror.Checked
    $script:Cfg.Reverse    = [bool]$chkReverse.Checked
    $script:Cfg.Equalise   = [bool]$chkEq.Checked
    $script:Cfg.Loop       = [bool]$chkLoop.Checked
}

function Update-Status {
    if ($script:WantOff) {
        $lblStatus.Text = '  Lighting is off'
        $lblStatus.ForeColor = $muted
        $icon.Text = 'Keyboard Lighting - off'
        $miStatus.Text = 'Lighting is off'
        $btnOff.Text = 'Turn lighting on'
        return
    }
    $btnOff.Text = 'Turn lighting off'
    if (Test-EngineAlive) {
        $lblStatus.Text = ('  Running - {0}' -f $script:Cfg.Effect)
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(70,200,120)
        $icon.Text = ('Keyboard Lighting - {0}' -f $script:Cfg.Effect)
        $miStatus.Text = ('Running - {0}' -f $script:Cfg.Effect)
    } else {
        $lblStatus.Text = '  Not running'
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(230,90,90)
        $icon.Text = 'Keyboard Lighting - stopped'
        $miStatus.Text = 'Not running'
    }
}

# Everything the user touches funnels through here. The settings are saved
# and handed to the running engine; nothing is restarted.
$script:ApplyTimer = New-Object System.Windows.Forms.Timer
$script:ApplyTimer.Interval = 220
$script:ApplyTimer.Add_Tick({
    $script:ApplyTimer.Stop()
    Sync-CfgFromUi
    Save-Cfg
    if ($script:WantOff) { return }
    if (Test-EngineAlive) {
        Write-Theme
        Write-LiveBrightness
    } else {
        [void](Start-Engine)
    }
    Update-Status
})

function Request-Apply {
    if ($script:Suppress) { return }
    $script:ApplyTimer.Stop()
    $script:ApplyTimer.Start()
}

# Brightness is special: it goes straight out so the slider feels attached
# to the keyboard, with no wait.
$trkBright.Add_ValueChanged({
    if ($script:Suppress) { return }
    $script:Cfg.Brightness = [int]$trkBright.Value
    Write-LiveBrightness
    $lblBright.Text = ('BRIGHTNESS    {0}%' -f $trkBright.Value)
    $pbPreview.Invalidate()
    Request-Apply
})
$trkSpeed.Add_ValueChanged({
    $lblSpeed.Text = ('SPEED    {0:0.0}x' -f ($trkSpeed.Value / 10.0))
    Request-Apply
})
$cboEffect.Add_SelectedIndexChanged({ Request-Apply })
$chkMirror.Add_CheckedChanged({ Request-Apply })
$chkReverse.Add_CheckedChanged({ Request-Apply })
$chkLoop.Add_CheckedChanged({ Request-Apply; $pbPreview.Invalidate() })
$chkEq.Add_CheckedChanged({ Request-Apply; $pbPreview.Invalidate() })

$chkAuto.Add_CheckedChanged({
    if ($script:Suppress) { return }
    $want = [bool]$chkAuto.Checked
    if (Set-Autostart $want) {
        $miAuto.Checked = $want
    } else {
        $script:Suppress = $true
        $chkAuto.Checked = -not $want
        $script:Suppress = $false
        [System.Windows.Forms.MessageBox]::Show(
            "Could not change the startup setting. This needs Administrator.",
            'Keyboard Lighting','OK','Warning') | Out-Null
    }
})

$btnOff.Add_Click({
    if ($script:WantOff) {
        [void](Start-Engine)
    } else {
        Set-AllOff
    }
    Update-Status
})
$btnHide.Add_Click({ $form.Hide() })

# ---------------------------------------------------------------- tray
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon    = $AppIcon
$icon.Text    = 'Keyboard Lighting'
$icon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
function Add-Item($text, $action) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem
    $mi.Text = $text
    if ($action) { $mi.Add_Click($action) }
    [void]$menu.Items.Add($mi)
    return $mi
}
function Add-Sep { [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }

$miStatus = Add-Item 'Starting...' $null
$miStatus.Enabled = $false
Add-Sep

function Show-Window {
    $form.Show()
    $form.WindowState = 'Normal'
    [void]$form.Activate()
    $form.BringToFront()
}

$miOpen = Add-Item 'Open Keyboard Lighting' { Show-Window }
$miOpen.Font = New-Object System.Drawing.Font($menu.Font, [System.Drawing.FontStyle]::Bold)

Add-Sep
$miRestart = Add-Item 'Restart lighting' {
    Log 'manual restart'
    [void](Start-Engine)
    Update-Status
}
$miOff = Add-Item 'Turn lighting off' {
    Set-AllOff
    Update-Status
}
Add-Sep
$miAuto = Add-Item 'Start when I log in' {
    $want = -not $miAuto.Checked
    if (Set-Autostart $want) {
        $miAuto.Checked = $want
        $script:Suppress = $true
        $chkAuto.Checked = $want
        $script:Suppress = $false
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not change the startup setting. This needs Administrator.",
            'Keyboard Lighting','OK','Warning') | Out-Null
    }
}
$miPending = Add-Item 'Restart to finish update' {
    Restart-App
}
$miPending.Visible = $false
$miPending.Font = New-Object System.Drawing.Font($menu.Font, [System.Drawing.FontStyle]::Bold)

$miUpdate = Add-Item 'Check for updates' {
    $icon.Text = 'Keyboard Lighting - checking...'
    $changed = Invoke-SelfUpdate
    $icon.Text = 'Keyboard Lighting'
    if ($changed.Count -eq 0) {
        $icon.BalloonTipTitle = 'Keyboard Lighting'
        $icon.BalloonTipText  = 'Already up to date.'
        $icon.ShowBalloonTip(3000)
    } else {
        $r = [System.Windows.Forms.MessageBox]::Show(
            ("Updated {0} file(s).`n`nRestart now to use the new version?" -f $changed.Count),
            'Update installed','YesNo','Question')
        if ($r -eq 'Yes') { Restart-App }
    }
}
Add-Sep
$miLog = Add-Item 'Open log file' {
    if (-not (Test-Path $LogFile)) { Set-Content -Path $LogFile -Value 'no entries yet' -Encoding UTF8 }
    Start-Process notepad.exe $LogFile
}
$miFolder = Add-Item 'Open program folder' { Start-Process explorer.exe $Here }
Add-Sep
$miExit = Add-Item 'Exit' {
    Log 'exit from menu'
    $script:Quitting = $true
    Stop-Engine
    $icon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
}

$icon.ContextMenuStrip = $menu
$icon.Add_MouseDoubleClick({ Show-Window })
$icon.Add_BalloonTipClicked({
    if ($script:Pending) { Restart-App } else { Show-Window }
})

function Restart-App {
    Log 'restarting'
    $script:Quitting = $true
    $exe = Join-Path $Here 'KeyboardLighting.exe'
    try {
        if (Test-Path $exe) {
            Start-Process -FilePath $exe
        } else {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName        = 'powershell.exe'
            $psi.Arguments       = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -NoUpdate -Silent -NoElevate' -f $PSCommandPath)
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow  = $true
            [void][System.Diagnostics.Process]::Start($psi)
        }
    } catch { Log ("restart failed: {0}" -f $_.Exception.Message) 'ERROR' }
    $icon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
}

# ---------------------------------------------------------------- window behaviour
# The close button puts it in the tray, like every other tray app. Exit is
# on the tray menu.
$form.Add_FormClosing({
    param($s, $e)
    if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing -and -not $script:Quitting) {
        $e.Cancel = $true
        $form.Hide()
        if (-not $script:HintShown) {
            $script:HintShown = $true
            $icon.BalloonTipTitle = 'Still running'
            $icon.BalloonTipText  = 'Keyboard Lighting is here. Double-click to open it again.'
            $icon.ShowBalloonTip(3000)
        }
    }
})
$form.Add_Resize({
    if ($form.WindowState -eq 'Minimized') { $form.Hide() }
})
$script:HintShown   = $false
$script:UpdJob      = $null
$script:UpdPrompted = $false
$script:Pending     = $false

# ---------------------------------------------------------------- load UI
$script:Suppress = $true
if ($Effects.Contains([string]$script:Cfg.Effect)) { $cboEffect.SelectedItem = [string]$script:Cfg.Effect }
$trkSpeed.Value  = [Math]::Min(50, [Math]::Max(1, [int]$script:Cfg.Speed))
$trkBright.Value = [Math]::Min(100, [Math]::Max(5, [int]$script:Cfg.Brightness))
$chkMirror.Checked  = [bool]$script:Cfg.Mirror
$chkReverse.Checked = [bool]$script:Cfg.Reverse
$chkEq.Checked      = [bool]$script:Cfg.Equalise
$chkLoop.Checked    = [bool]$script:Cfg.Loop
$chkAuto.Checked    = Test-Autostart
$miAuto.Checked     = $chkAuto.Checked
$lblSpeed.Text  = ('SPEED    {0:0.0}x' -f ($trkSpeed.Value / 10.0))
$lblBright.Text = ('BRIGHTNESS    {0}%' -f $trkBright.Value)
Redraw-Swatches

# preview animation
$anim = New-Object System.Windows.Forms.Timer
$anim.Interval = 33
$anim.Add_Tick({
    if (-not $form.Visible) { return }
    $dir = 1.0
    if ($chkReverse.Checked) { $dir = -1.0 }
    $script:phase = ($script:phase + (0.25 * ($trkSpeed.Value/10.0) * $dir) * 0.033) % 1.0
    if ($script:phase -lt 0) { $script:phase += 1.0 }
    $pbPreview.Invalidate()
})
$anim.Start()

# ---------------------------------------------------------------- start up
if (-not $IsAdmin) {
    $lblSub.Text = 'Not running as Administrator - the keyboard cannot be controlled'
    $lblSub.ForeColor = [System.Drawing.Color]::FromArgb(230,160,60)
    Log 'running without Administrator' 'WARN'
}

if (-not $NoUpdate) {
    $job = Start-Job -ScriptBlock {
        param($b, $h)
        try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12' } catch { }
        $hit = @()
        foreach ($f in 'Aura-Background.ps1','Lighting-Panel.ps1','Tray.ps1','Install.ps1','Install.bat',
                       'Check.ps1','Check.bat','Update.ps1','Update.bat','README.md','app.ico') {
            try {
                $tmp = Join-Path $env:TEMP ('kblbg_' + $f)
                Invoke-WebRequest "$b/$f" -OutFile $tmp -UseBasicParsing -TimeoutSec 20
                $dest = Join-Path $h $f
                $new = (Get-FileHash $tmp -Algorithm SHA256).Hash
                $old = ''
                if (Test-Path $dest) { $old = (Get-FileHash $dest -Algorithm SHA256).Hash }
                if ($new -ne $old) { Copy-Item $tmp $dest -Force; $hit += $f }
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            } catch { }
        }
        return $hit
    } -ArgumentList $Base, $Here
    $script:UpdJob = $job
}

# Apply the saved theme immediately, before anything is shown.
[void](Start-Engine)
$script:Suppress = $false
Update-Status

if (-not $Silent) { Show-Window }

# Watchdog + "show me" signal from a second launch.
$watch = New-Object System.Windows.Forms.Timer
$watch.Interval = 500
$script:tick = 0
$watch.Add_Tick({
    Update-Heartbeat
    if (Test-Path $ShowFile) {
        try { Remove-Item $ShowFile -Force -ErrorAction SilentlyContinue } catch { }
        Show-Window
    }
    $script:tick++
    if ($script:tick % 8 -eq 0) { Update-Status }

    # The background updater replaces files on disk but never restarts
    # anything underneath you. Once it finishes, say so plainly.
    if ($script:UpdJob -and -not $script:UpdPrompted) {
        try {
            if ($script:UpdJob.State -eq 'Completed') {
                $script:UpdPrompted = $true
                $got = @(Receive-Job $script:UpdJob -ErrorAction SilentlyContinue)
                Remove-Job $script:UpdJob -Force -ErrorAction SilentlyContinue
                $script:UpdJob = $null
                if ($got.Count -gt 0) {
                    Log ("background update fetched: {0}" -f ($got -join ', '))
                    $script:Pending = $true
                    $miPending.Visible = $true
                    $icon.BalloonTipTitle = 'Update ready'
                    $icon.BalloonTipText  = 'A new version was downloaded. Click here, or use the tray menu, to restart and apply it.'
                    $icon.ShowBalloonTip(6000)
                }
            } elseif ($script:UpdJob.State -eq 'Failed') {
                $script:UpdPrompted = $true
                Remove-Job $script:UpdJob -Force -ErrorAction SilentlyContinue
                $script:UpdJob = $null
            }
        } catch { $script:UpdPrompted = $true }
    }
})
$watch.Start()

Log 'ready'
[System.Windows.Forms.Application]::Run()

if (-not $script:Quitting) { Stop-Engine }
$icon.Visible = $false
try { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue } catch { }
Log 'exited'
