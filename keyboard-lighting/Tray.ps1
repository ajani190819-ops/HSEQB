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
    $files = @('Aura-Background.ps1','Tray.ps1','ui_controls.cs.txt','app.ico','Install.ps1','Install.bat','Check.ps1','Check.bat','Update.ps1','Update.bat','MyEffect.ps1','README.md')
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

# ---------------------------------------------------------------- custom controls
# The stock WinForms TrackBar/CheckBox/ComboBox are what make a PowerShell
# window look like a PowerShell window. These are drawn from scratch
# instead: rounded cards, pill sliders, iOS-style toggles, a custom title
# bar. Compiled on the fly by the same .NET that is already running.
$uiFile = Join-Path $Here 'ui_controls.cs.txt'
$script:CustomUi = $false
if (Test-Path $uiFile) {
    try {
        Add-Type -TypeDefinition (Get-Content $uiFile -Raw) `
                 -ReferencedAssemblies 'System.Windows.Forms','System.Drawing','System' `
                 -ErrorAction Stop
        $script:CustomUi = $true
        Log 'custom UI loaded'
    } catch {
        Log ("custom UI failed to compile: {0}" -f $_.Exception.Message) 'ERROR'
    }
} else {
    Log 'ui_controls.cs.txt missing' 'WARN'
}
if (-not $script:CustomUi) {
    [System.Windows.Forms.MessageBox]::Show(
        "The interface files are missing or damaged.`n`nRun Install.bat again to repair.",
        'Keyboard Lighting','OK','Error') | Out-Null
    return
}

# ---------------------------------------------------------------- DPI
# Without this the whole window is bitmap-stretched on a high-DPI laptop
# and every edge looks soft. Must be called before any window exists.
try { [KbLight.Dpi]::Enable() } catch { }

# ---------------------------------------------------------------- icon
function New-AppIcon {
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
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$AppIcon = New-AppIcon

# ---------------------------------------------------------------- window
$T   = [KbLight.Theme]
$Bg  = $T::Bg
$Mut = $T::Muted
$Txt = $T::Text

$fontH1 = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$fontLb = New-Object System.Drawing.Font('Segoe UI', 8.25, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Point)
$fontBd = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$fontSm = New-Object System.Drawing.Font('Segoe UI', 8.75, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)
$fontVal= New-Object System.Drawing.Font('Segoe UI Semibold', 9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Point)

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Keyboard Lighting'
$form.FormBorderStyle = 'None'
$form.StartPosition   = 'CenterScreen'
$form.BackColor       = $Bg
$form.ForeColor       = $Txt
$form.Font            = $fontBd
$form.Icon            = $AppIcon
$form.ShowInTaskbar   = $true
$form.KeyPreview      = $true
# Must be set before any control is added, and the handle must NOT be
# touched before then: WinForms scales at handle-creation time, so forcing
# the handle early would leave every later control unscaled.
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode       = 'Dpi'
$form.ClientSize          = New-Object System.Drawing.Size(478, 700)

# ---- title bar ----
$bar = New-Object KbLight.TitleBar $form
$bar.Text = 'Keyboard Lighting'
$bar.Font = $fontBd
try { $bar.Logo = $AppIcon.ToBitmap() } catch { }
$form.Controls.Add($bar)

# ---- scrollable body ----
$body = New-Object System.Windows.Forms.Panel
$body.Dock      = 'Fill'
$body.BackColor = $Bg
$body.AutoScroll = $true
$form.Controls.Add($body)
$body.BringToFront()

function New-Head($text, $x, $y, $w) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = New-Object System.Drawing.Point($x, $y)
    $l.Size      = New-Object System.Drawing.Size($w, 18)
    $l.ForeColor = $Mut
    $l.Font      = $fontLb
    $l.BackColor = [System.Drawing.Color]::Transparent
    $body.Controls.Add($l)
    return $l
}

$M  = 20          # outer margin
$CW = 438         # card width
$IW = 406         # inner width

$y = 12

# ================================================================ hero
$cardTop = New-Object KbLight.Card
$cardTop.Location = New-Object System.Drawing.Point($M, $y)
$cardTop.Size     = New-Object System.Drawing.Size($CW, 66)
$body.Controls.Add($cardTop)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = 'ROG Strix G16'
$lblTitle.Location  = New-Object System.Drawing.Point(16, 12)
$lblTitle.Size      = New-Object System.Drawing.Size(280, 26)
$lblTitle.ForeColor = $Txt
$lblTitle.Font      = $fontH1
$lblTitle.BackColor = [System.Drawing.Color]::Transparent
$cardTop.Controls.Add($lblTitle)

$dot = New-Object System.Windows.Forms.Label
$dot.Text      = [char]0x25CF
$dot.Location  = New-Object System.Drawing.Point(16, 42)
$dot.Size      = New-Object System.Drawing.Size(14, 18)
$dot.Font      = $fontSm
$dot.ForeColor = $T::Good
$dot.BackColor = [System.Drawing.Color]::Transparent
$cardTop.Controls.Add($dot)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = 'Starting'
$lblStatus.Location  = New-Object System.Drawing.Point(32, 42)
$lblStatus.Size      = New-Object System.Drawing.Size(390, 18)
$lblStatus.ForeColor = $Mut
$lblStatus.Font      = $fontSm
$lblStatus.BackColor = [System.Drawing.Color]::Transparent
$cardTop.Controls.Add($lblStatus)

$y += 66 + 12

# ================================================================ pattern
New-Head 'PATTERN' $M $y 200 | Out-Null
$y += 22
$cboEffect = New-Object KbLight.Picker
$cboEffect.Location = New-Object System.Drawing.Point($M, $y)
$cboEffect.Size     = New-Object System.Drawing.Size($CW, 40)
$cboEffect.Font     = $fontBd
foreach ($k in $Effects.Keys) { [void]$cboEffect.Items.Add($k) }
$cboEffect.SetQuiet(0)
$body.Controls.Add($cboEffect)
$y += 40 + 14

# ================================================================ colours
New-Head 'COLOURS' $M $y 200 | Out-Null
$lblColHint = New-Object System.Windows.Forms.Label
$lblColHint.Text      = 'click to change'
$lblColHint.Location  = New-Object System.Drawing.Point(($M + 90), $y)
$lblColHint.Size      = New-Object System.Drawing.Size(200, 18)
$lblColHint.ForeColor = [System.Drawing.Color]::FromArgb(96,102,122)
$lblColHint.Font      = $fontSm
$lblColHint.BackColor = [System.Drawing.Color]::Transparent
$body.Controls.Add($lblColHint)
$y += 22

$pnlCol = New-Object System.Windows.Forms.Panel
$pnlCol.Location  = New-Object System.Drawing.Point($M, $y)
$pnlCol.Size      = New-Object System.Drawing.Size($CW, 46)
$pnlCol.BackColor = [System.Drawing.Color]::Transparent
$body.Controls.Add($pnlCol)
$y += 46 + 14

# ================================================================ preview
New-Head 'PREVIEW' $M $y 200 | Out-Null
$y += 22
$pbPreview = New-Object KbLight.Preview
$pbPreview.Location = New-Object System.Drawing.Point($M, $y)
$pbPreview.Size     = New-Object System.Drawing.Size($CW, 44)
$body.Controls.Add($pbPreview)
$y += 44 + 16

# ================================================================ sliders
$cardSl = New-Object KbLight.Card
$cardSl.Location = New-Object System.Drawing.Point($M, $y)
$cardSl.Size     = New-Object System.Drawing.Size($CW, 132)
$body.Controls.Add($cardSl)

$lblSpeed = New-Object System.Windows.Forms.Label
$lblSpeed.Text      = 'SPEED'
$lblSpeed.Location  = New-Object System.Drawing.Point(16, 14)
$lblSpeed.Size      = New-Object System.Drawing.Size(200, 18)
$lblSpeed.ForeColor = $Mut
$lblSpeed.Font      = $fontLb
$lblSpeed.BackColor = [System.Drawing.Color]::Transparent
$cardSl.Controls.Add($lblSpeed)

$valSpeed = New-Object System.Windows.Forms.Label
$valSpeed.Text      = '1.0x'
$valSpeed.Location  = New-Object System.Drawing.Point(($CW - 86), 14)
$valSpeed.Size      = New-Object System.Drawing.Size(70, 18)
$valSpeed.ForeColor = $T::Accent
$valSpeed.Font      = $fontVal
$valSpeed.TextAlign = 'TopRight'
$valSpeed.BackColor = [System.Drawing.Color]::Transparent
$cardSl.Controls.Add($valSpeed)

$trkSpeed = New-Object KbLight.Slider
$trkSpeed.Location = New-Object System.Drawing.Point(16, 36)
$trkSpeed.Size     = New-Object System.Drawing.Size($IW, 28)
$trkSpeed.Minimum  = 1
$trkSpeed.Maximum  = 50
$trkSpeed.Value    = 10
$cardSl.Controls.Add($trkSpeed)

$lblBright = New-Object System.Windows.Forms.Label
$lblBright.Text      = 'BRIGHTNESS'
$lblBright.Location  = New-Object System.Drawing.Point(16, 74)
$lblBright.Size      = New-Object System.Drawing.Size(200, 18)
$lblBright.ForeColor = $Mut
$lblBright.Font      = $fontLb
$lblBright.BackColor = [System.Drawing.Color]::Transparent
$cardSl.Controls.Add($lblBright)

$valBright = New-Object System.Windows.Forms.Label
$valBright.Text      = '100%'
$valBright.Location  = New-Object System.Drawing.Point(($CW - 86), 74)
$valBright.Size      = New-Object System.Drawing.Size(70, 18)
$valBright.ForeColor = $T::Accent
$valBright.Font      = $fontVal
$valBright.TextAlign = 'TopRight'
$valBright.BackColor = [System.Drawing.Color]::Transparent
$cardSl.Controls.Add($valBright)

$trkBright = New-Object KbLight.Slider
$trkBright.Location = New-Object System.Drawing.Point(16, 96)
$trkBright.Size     = New-Object System.Drawing.Size($IW, 28)
$trkBright.Minimum  = 5
$trkBright.Maximum  = 100
$trkBright.Value    = 100
$cardSl.Controls.Add($trkBright)

$y += 132 + 16

# ================================================================ options
$cardOp = New-Object KbLight.Card
$cardOp.Location = New-Object System.Drawing.Point($M, $y)
$cardOp.Size     = New-Object System.Drawing.Size($CW, 120)
$body.Controls.Add($cardOp)

function New-Toggle($text, $xx, $yy, $ww) {
    $t = New-Object KbLight.Toggle
    $t.Text     = $text
    $t.Location = New-Object System.Drawing.Point($xx, $yy)
    $t.Size     = New-Object System.Drawing.Size($ww, 26)
    $t.Font     = $fontBd
    $cardOp.Controls.Add($t)
    return $t
}
# Two columns: the short labels do not need the full card width, and this
# keeps the window short enough for a laptop screen.
$colL = 16
$colR = 224
$colW = 198
$chkLoop    = New-Toggle 'Wrap light bar'      $colL  14 $colW
$chkEq       = New-Toggle 'Even brightness'    $colR  14 $colW
$chkMirror  = New-Toggle 'Mirror'              $colL  48 $colW
$chkReverse = New-Toggle 'Reverse'             $colR  48 $colW
$chkAuto    = New-Toggle 'Start when I log in' $colL  82 ($colW + 180)

$y += 120 + 16

# ================================================================ buttons
$btnOff = New-Object KbLight.FlatBtn
$btnOff.Text     = 'Turn lighting off'
$btnOff.Location = New-Object System.Drawing.Point($M, $y)
$btnOff.Size     = New-Object System.Drawing.Size(212, 40)
$btnOff.Font     = $fontBd
$body.Controls.Add($btnOff)

$btnHide = New-Object KbLight.FlatBtn
$btnHide.Text     = 'Hide to tray'
$btnHide.Primary  = $true
$btnHide.Location = New-Object System.Drawing.Point(($M + 226), $y)
$btnHide.Size     = New-Object System.Drawing.Size(212, 40)
$btnHide.Font     = $fontBd
$body.Controls.Add($btnHide)

$y += 40 + 12

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text      = 'Changes apply to the keyboard as you make them.'
$lblHint.Location  = New-Object System.Drawing.Point($M, $y)
$lblHint.Size      = New-Object System.Drawing.Size($CW, 18)
$lblHint.ForeColor = [System.Drawing.Color]::FromArgb(96,102,122)
$lblHint.Font      = $fontSm
$lblHint.TextAlign = 'TopCenter'
$lblHint.BackColor = [System.Drawing.Color]::Transparent
$body.Controls.Add($lblHint)

$y += 26
$form.ClientSize = New-Object System.Drawing.Size(478, ($bar.Height + $y))

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

# Work out the 16 preview colours and hand them to the control to draw.
function Update-Preview {
    $pal = @()
    foreach ($s in $script:Swatches) {
        try { $pal += ,([System.Drawing.ColorTranslator]::FromHtml($s)) }
        catch { $pal += ,([System.Drawing.Color]::Gray) }
    }
    if ($pal.Count -lt 2) { $pal += $pal[0] }
    $pc = $pal.Count
    $bright = $trkBright.Value / 100.0
    Update-PalGain $pal

    $n = 16
    $out = New-Object 'System.Drawing.Color[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $u0 = $i / [double]($n - 1)
        if ($chkLoop.Checked) { $u0 = $i / [double]$n }
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
        if ($r  -lt 0) { $r = 0 };  if ($r  -gt 255) { $r = 255 }
        if ($gg -lt 0) { $gg = 0 }; if ($gg -gt 255) { $gg = 255 }
        if ($bb -lt 0) { $bb = 0 }; if ($bb -gt 255) { $bb = 255 }
        $out[$i] = [System.Drawing.Color]::FromArgb($r, $gg, $bb)
    }
    $pbPreview.Colors = $out
    $pbPreview.Invalidate()
}

# ---------------------------------------------------------------- swatches
function Redraw-Swatches {
    $pnlCol.Controls.Clear()
    $x = 0
    for ($i = 0; $i -lt $script:Swatches.Count; $i++) {
        $sw = New-Object KbLight.Swatch
        $sw.Location = New-Object System.Drawing.Point($x, 0)
        $sw.Size     = New-Object System.Drawing.Size(44, 44)
        try { $sw.Value = [System.Drawing.ColorTranslator]::FromHtml($script:Swatches[$i]) }
        catch { $sw.Value = [System.Drawing.Color]::Gray }
        $sw.Tag = $i
        $sw.Add_Click({
            $idx = $this.Tag
            $dlg = New-Object System.Windows.Forms.ColorDialog
            $dlg.FullOpen = $true
            try { $dlg.Color = [System.Drawing.ColorTranslator]::FromHtml($script:Swatches[$idx]) } catch { }
            if ($dlg.ShowDialog() -eq 'OK') {
                $script:Swatches[$idx] = '#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B
                Redraw-Swatches
                Update-Preview
                Request-Apply
            }
        })
        $pnlCol.Controls.Add($sw)
        $x += 50
    }
    if ($script:Swatches.Count -lt 8) {
        $add = New-Object KbLight.MiniBtn
        $add.Glyph    = '+'
        $add.Location = New-Object System.Drawing.Point($x, 0)
        $add.Size     = New-Object System.Drawing.Size(30, 44)
        $add.Add_Click({
            $script:Swatches += '#FFFFFF'
            Redraw-Swatches
            Update-Preview
            Request-Apply
        })
        $pnlCol.Controls.Add($add)
        $x += 36
    }
    if ($script:Swatches.Count -gt 2) {
        $rem = New-Object KbLight.MiniBtn
        $rem.Glyph    = '-'
        $rem.Location = New-Object System.Drawing.Point($x, 0)
        $rem.Size     = New-Object System.Drawing.Size(30, 44)
        $rem.Add_Click({
            if ($script:Swatches.Count -gt 2) {
                $script:Swatches = @($script:Swatches[0..($script:Swatches.Count-2)])
                Redraw-Swatches
                Update-Preview
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
        $lblStatus.Text = 'Lighting is off'
        $dot.ForeColor  = $Mut
        $icon.Text      = 'Keyboard Lighting - off'
        $miStatus.Text  = 'Lighting is off'
        $btnOff.Text    = 'Turn lighting on'
        $btnOff.Invalidate()
        return
    }
    $btnOff.Text = 'Turn lighting off'
    $btnOff.Invalidate()
    if (Test-EngineAlive) {
        $lblStatus.Text = ('Running - {0}' -f $script:Cfg.Effect)
        $dot.ForeColor  = $T::Good
        $icon.Text      = ('Keyboard Lighting - {0}' -f $script:Cfg.Effect)
        $miStatus.Text  = ('Running - {0}' -f $script:Cfg.Effect)
    } else {
        $lblStatus.Text = 'Not running'
        $dot.ForeColor  = $T::Bad
        $icon.Text      = 'Keyboard Lighting - stopped'
        $miStatus.Text  = 'Not running'
    }
}

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

$trkBright.Add_ValueChanged({
    $valBright.Text = ('{0}%' -f $trkBright.Value)
    if ($script:Suppress) { return }
    $script:Cfg.Brightness = [int]$trkBright.Value
    Write-LiveBrightness
    Update-Preview
    Request-Apply
})
$trkSpeed.Add_ValueChanged({
    $valSpeed.Text = ('{0:0.0}x' -f ($trkSpeed.Value / 10.0))
    Request-Apply
})
$cboEffect.Add_SelectedChanged({ Request-Apply })
$chkMirror.Add_CheckedChanged({ Request-Apply })
$chkReverse.Add_CheckedChanged({ Request-Apply })
$chkLoop.Add_CheckedChanged({ Request-Apply; Update-Preview })
$chkEq.Add_CheckedChanged({ Request-Apply; Update-Preview })

$chkAuto.Add_CheckedChanged({
    if ($script:Suppress) { return }
    $want = [bool]$chkAuto.Checked
    if (Set-Autostart $want) {
        $miAuto.Checked = $want
    } else {
        $script:Suppress = $true
        $chkAuto.SetQuiet((-not $want))
        $script:Suppress = $false
        [System.Windows.Forms.MessageBox]::Show(
            "Could not change the startup setting. This needs Administrator.",
            'Keyboard Lighting','OK','Warning') | Out-Null
    }
})

$btnOff.Add_Click({
    if ($script:WantOff) { [void](Start-Engine) } else { Set-AllOff }
    Update-Status
})
$btnHide.Add_Click({ $form.Hide() })

# ---------------------------------------------------------------- tray
$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon    = $AppIcon
$icon.Text    = 'Keyboard Lighting'
$icon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.BackColor   = $T::Panel2
$menu.ForeColor   = $Txt
$menu.Font        = $fontBd
$menu.ShowImageMargin = $false
$menu.Renderer    = New-Object System.Windows.Forms.ToolStripProfessionalRenderer

function Add-Item($text, $action) {
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem
    $mi.Text = $text
    $mi.BackColor = $T::Panel2
    $mi.ForeColor = $Txt
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
$miOpen.Font = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)

Add-Sep
$miPending = Add-Item 'Restart to finish update' { Restart-App }
$miPending.Visible = $false
$miPending.Font = New-Object System.Drawing.Font('Segoe UI', 9.75, [System.Drawing.FontStyle]::Bold)

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
        $chkAuto.SetQuiet($want)
        $script:Suppress = $false
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not change the startup setting. This needs Administrator.",
            'Keyboard Lighting','OK','Warning') | Out-Null
    }
}
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
# Every $script: flag the timers and handlers rely on, declared in one
# place before anything can read it.
$script:HintShown   = $false
$script:UpdJob      = $null
$script:UpdPrompted = $false
$script:Pending     = $false
$script:WakeAt      = 0

function Show-HideHint {
    if ($script:HintShown) { return }
    $script:HintShown = $true
    $icon.BalloonTipTitle = 'Still running'
    $icon.BalloonTipText  = 'Keyboard Lighting is here. Double-click to open it again.'
    $icon.ShowBalloonTip(3000)
}

$bar.Add_CloseClicked({ $form.Hide(); Show-HideHint })
$bar.Add_MinClicked({ $form.Hide(); Show-HideHint })

$form.Add_FormClosing({
    param($s, $e)
    if ($e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing -and -not $script:Quitting) {
        $e.Cancel = $true
        $form.Hide()
        Show-HideHint
    }
})
$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $form.Hide(); Show-HideHint }
})
# Safe here: the handle already exists and DPI scaling has been applied.
$form.Add_Shown({ try { [KbLight.Win]::RoundCorners($form.Handle) } catch { } })

# ---------------------------------------------------------------- load UI
$script:Suppress = $true
$idx = 0
$keys = @($Effects.Keys)
for ($i = 0; $i -lt $keys.Count; $i++) {
    if ($keys[$i] -eq [string]$script:Cfg.Effect) { $idx = $i }
}
$cboEffect.SetQuiet($idx)
$trkSpeed.Value  = [Math]::Min(50, [Math]::Max(1, [int]$script:Cfg.Speed))
$trkBright.Value = [Math]::Min(100, [Math]::Max(5, [int]$script:Cfg.Brightness))
$chkMirror.SetQuiet([bool]$script:Cfg.Mirror)
$chkReverse.SetQuiet([bool]$script:Cfg.Reverse)
$chkEq.SetQuiet([bool]$script:Cfg.Equalise)
$chkLoop.SetQuiet([bool]$script:Cfg.Loop)
$chkAuto.SetQuiet((Test-Autostart))
$miAuto.Checked = $chkAuto.Checked
$valSpeed.Text  = ('{0:0.0}x' -f ($trkSpeed.Value / 10.0))
$valBright.Text = ('{0}%' -f $trkBright.Value)
Redraw-Swatches
Update-Preview

$anim = New-Object System.Windows.Forms.Timer
$anim.Interval = 40
$anim.Add_Tick({
    if (-not $form.Visible) { return }
    $dir = 1.0
    if ($chkReverse.Checked) { $dir = -1.0 }
    $script:phase = ($script:phase + (0.25 * ($trkSpeed.Value/10.0) * $dir) * 0.040) % 1.0
    if ($script:phase -lt 0) { $script:phase += 1.0 }
    Update-Preview
})
$anim.Start()

# ---------------------------------------------------------------- start up
if (-not $IsAdmin) {
    $lblStatus.Text = 'Not running as Administrator'
    $dot.ForeColor  = $T::Bad
    Log 'running without Administrator' 'WARN'
}

if (-not $NoUpdate) {
    $job = Start-Job -ScriptBlock {
        param($b, $h)
        try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12' } catch { }
        $hit = @()
        foreach ($f in 'Aura-Background.ps1','Tray.ps1','ui_controls.cs.txt','app.ico','Install.ps1','Install.bat','Check.ps1','Check.bat','Update.ps1','Update.bat','MyEffect.ps1','README.md') {
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

[void](Start-Engine)
$script:Suppress = $false
Update-Status

if (-not $Silent) { Show-Window }

# The app must also notice a resume: if the engine died outright (rather
# than just losing its handle) nothing else will bring the lighting back.
# NOTE: no -Action scriptblock. That runs in its own scope, so a
# $script: flag set inside it would never be visible here. Queue the
# events instead and drain them from the timer, which is the same pattern
# the engine uses for its hotkey watcher.
$script:PowerOk = $false
try {
    Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) `
        -EventName PowerModeChanged -SourceIdentifier 'TrayPower' `
        -ErrorAction Stop | Out-Null
    $script:PowerOk = $true
    Log 'sleep/resume watch active'
} catch {
    Log 'sleep/resume watch unavailable' 'WARN'
}

$watch = New-Object System.Windows.Forms.Timer
$watch.Interval = 500
$script:tick = 0
$watch.Add_Tick({
    Update-Heartbeat
    if (Test-Path $ShowFile) {
        try { Remove-Item $ShowFile -Force -ErrorAction SilentlyContinue } catch { }
        Show-Window
    }
    # --- came back from sleep ---
    $woke = $false
    if ($script:PowerOk) {
        $pe = Get-Event -SourceIdentifier 'TrayPower' -ErrorAction SilentlyContinue
        while ($pe) {
            $mode = ''
            try { $mode = [string]$pe.SourceEventArgs.Mode } catch { }
            Remove-Event -EventIdentifier $pe.EventIdentifier -ErrorAction SilentlyContinue
            if ($mode -eq 'Resume') { $woke = $true }
            $pe = Get-Event -SourceIdentifier 'TrayPower' -ErrorAction SilentlyContinue
        }
    }
    if ($woke) {
        Log 'resumed from sleep'
        # Do NOT sleep here - this runs on the UI thread and would freeze
        # the window. Schedule the work a few ticks later instead, giving
        # the USB stack time to re-enumerate the keyboard.
        if ($script:WantOff) {
            Log 'lighting was off before sleep - leaving it off'
        } else {
            $script:WakeAt = $script:tick + 4        # ~2 seconds
        }
    }

    # deferred post-resume repair
    if ($script:WakeAt -gt 0 -and $script:tick -ge $script:WakeAt) {
        $script:WakeAt = 0
        if (-not $script:WantOff) {
            if (Test-EngineAlive) {
                Write-Theme
                Write-LiveBrightness
                Log 'engine alive after resume - theme re-sent'
            } else {
                Log 'engine gone after resume - restarting'
                [void](Start-Engine)
            }
            Update-Status
        }
    }

    $script:tick++
    if ($script:tick % 8 -eq 0) { Update-Status }

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
                    $icon.BalloonTipText  = 'A new version was downloaded. Click here to restart and apply it.'
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
Unregister-Event -SourceIdentifier 'TrayPower' -ErrorAction SilentlyContinue
$icon.Visible = $false
try { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue } catch { }
Log 'exited'
