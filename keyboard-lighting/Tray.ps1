# =====================================================================
#  Keyboard Lighting - tray application
#
#  This is the one thing that runs. It:
#    - lives in the system tray
#    - starts the lighting engine
#    - opens the control panel on demand
#    - updates itself in the background
#    - writes a log you can open from the menu
#
#  Launched by KeyboardLighting.exe. You should not need to run it
#  directly.
# =====================================================================

param(
    [switch]$NoUpdate,      # skip the update check (used by the updater itself)
    [switch]$Silent         # no balloon tips on start
)

$ErrorActionPreference = 'Continue'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- paths
$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Engine   = Join-Path $Here 'Aura-Background.ps1'
$Panel    = Join-Path $Here 'Lighting-Panel.ps1'
$CfgDir   = Join-Path $env:LOCALAPPDATA 'KeyboardLighting'
$CfgFile  = Join-Path $CfgDir 'panel.json'
$LiveFile = Join-Path $CfgDir 'live.txt'
$LogFile  = Join-Path $CfgDir 'log.txt'
$TaskName = 'KeyboardLighting'
$Base     = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting'

if (-not (Test-Path $CfgDir)) { New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null }

# ---------------------------------------------------------------- logging
function Log($msg, $level = 'INFO') {
    $line = '{0}  {1,-5}  {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $level, $msg
    try {
        Add-Content -Path $LogFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        # keep the log from growing without bound
        $fi = Get-Item $LogFile -ErrorAction SilentlyContinue
        if ($fi -and $fi.Length -gt 262144) {
            $keep = Get-Content $LogFile -Tail 400 -ErrorAction SilentlyContinue
            Set-Content -Path $LogFile -Value $keep -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch { }
}

Log '---------------- tray starting ----------------'
Log ("folder: {0}" -f $Here)

# ---------------------------------------------------------------- one only
# Clicking the pinned icon while it is already running must not start a
# second tray and a second engine fighting over the keyboard.
$script:Mutex = New-Object System.Threading.Mutex($false, 'Global\KeyboardLightingTray')
$gotMutex = $false
try { $gotMutex = $script:Mutex.WaitOne(0, $false) } catch { $gotMutex = $true }
if (-not $gotMutex) {
    Log 'another tray is already running - opening its panel instead'
    # Be useful rather than silent: bring up the control panel.
    if (Test-Path $Panel) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"{0}"' -f $Panel))
    }
    return
}

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

# ---------------------------------------------------------------- config
$script:Cfg = [pscustomobject]@{
    Effect     = 'Scrolling gradient'
    Swatches   = @('#FF0000','#FF7F00','#FFFF00','#00FF00','#0000FF','#8B00FF')
    Speed      = 10
    Brightness = 100
    Mirror     = $false
    Reverse    = $false
    Equalise   = $true
    Loop       = $true
}
function Load-Cfg {
    if (-not (Test-Path $CfgFile)) { return }
    try {
        $o = Get-Content $CfgFile -Raw | ConvertFrom-Json
        foreach ($p in 'Effect','Swatches','Speed','Brightness','Mirror','Reverse','Equalise','Loop') {
            if ($null -ne $o.$p) { $script:Cfg.$p = $o.$p }
        }
        Log 'config loaded'
    } catch { Log ("config load failed: {0}" -f $_.Exception.Message) 'WARN' }
}
Load-Cfg

$EffectMap = @{
    'Scrolling gradient' = 'gradient'; 'Rainbow' = 'rainbow'; 'Wave' = 'wave'
    'Comet' = 'comet'; 'Scanner' = 'scanner'; 'Breathing' = 'breathe'
    'Pulse' = 'pulse'; 'Fire' = 'fire'; 'Solid colour' = 'static'
}

# ---------------------------------------------------------------- engine
$script:Engine = $null

function Stop-Engine {
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*Aura-Background*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
    $script:Engine = $null
}

function Start-Engine {
    Stop-Engine
    Start-Sleep -Milliseconds 200
    if (-not (Test-Path $Engine)) { Log 'engine script missing' 'ERROR'; return $false }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $eff = $EffectMap[[string]$script:Cfg.Effect]
    if (-not $eff) { $eff = 'gradient' }
    $spd = ([double]$script:Cfg.Speed / 10.0).ToString('0.##', $inv)
    $brt = ([double]$script:Cfg.Brightness / 100.0).ToString('0.##', $inv)

    $a = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden'
        '-File', ('"{0}"' -f $Engine)
        '-Effect', $eff
        '-Speed', $spd
        '-Brightness', $brt
        '-Fps','60'
        '-Quiet'
    )
    $sw = @($script:Cfg.Swatches)
    if ($sw.Count -gt 0) {
        $a += '-Colors'; $a += ('"{0}"' -f ($sw -join ','))
        $a += '-Color';  $a += ('"{0}"' -f $sw[0])
        if ($sw.Count -gt 1) { $a += '-Color2'; $a += ('"{0}"' -f $sw[1]) }
    }
    if ($script:Cfg.Mirror)  { $a += '-Mirror' }
    if ($script:Cfg.Reverse) { $a += '-Reverse' }
    $eqv = 'off'; if ($script:Cfg.Equalise) { $eqv = 'on' }
    $a += '-Equalise'; $a += $eqv
    $lay = 'across'; if ($script:Cfg.Loop) { $lay = 'loop' }
    $a += '-Layout'; $a += $lay

    try {
        $script:Engine = Start-Process -FilePath 'powershell.exe' -ArgumentList $a `
                         -WindowStyle Hidden -PassThru
        Start-Sleep -Milliseconds 900
        if ($script:Engine.HasExited) {
            Log ("engine exited immediately (effect={0})" -f $eff) 'ERROR'
            $script:Engine = $null
            return $false
        }
        Log ("engine started: effect={0} speed={1} bright={2} layout={3}" -f $eff,$spd,$brt,$lay)
        return $true
    } catch {
        Log ("engine start failed: {0}" -f $_.Exception.Message) 'ERROR'
        return $false
    }
}

function Test-EngineAlive {
    if (-not $script:Engine) { return $false }
    try { return (-not $script:Engine.HasExited) } catch { return $false }
}

# ---------------------------------------------------------------- update
function Invoke-SelfUpdate {
    $files = @('Aura-Background.ps1','Lighting-Panel.ps1','Tray.ps1',
               'Check.ps1','Check.bat','Update.ps1','Update.bat',
               'Lighting-Panel.bat','MyEffect.ps1','Find-Lamps.ps1')
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
            $act = New-ScheduledTaskAction -Execute $exe -WorkingDirectory $Here
        } else {
            $act = New-ScheduledTaskAction -Execute 'powershell.exe' `
                   -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Silent' -f $PSCommandPath) `
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

# ---------------------------------------------------------------- tray icon
function New-TrayIcon {
    # Draw a small keyboard-ish glyph so we do not depend on an .ico file.
    $bmp = New-Object System.Drawing.Bitmap 32,32
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)
    $body = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235,240,250))
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

$icon = New-Object System.Windows.Forms.NotifyIcon
$icon.Icon = New-TrayIcon
$icon.Text = 'Keyboard Lighting'
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

$miPanel = Add-Item 'Open control panel' {
    if (-not (Test-Path $Panel)) {
        [System.Windows.Forms.MessageBox]::Show('Lighting-Panel.ps1 is missing. Use "Check for updates".',
            'Keyboard Lighting','OK','Warning') | Out-Null
        return
    }
    Log 'opening control panel'
    # The panel owns the engine while it is open, so stand down first.
    Stop-Engine
    Start-Process -FilePath 'powershell.exe' -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"{0}"' -f $Panel)
    ) -Wait
    Load-Cfg
    [void](Start-Engine)
    Update-Status
}

Add-Sep
$miRestart = Add-Item 'Restart lighting' {
    Log 'manual restart'
    Load-Cfg
    [void](Start-Engine)
    Update-Status
}
$miOff = Add-Item 'Turn lighting off' {
    Log 'lighting turned off from menu'
    Stop-Engine
    if (Test-Path $Engine) {
        Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -Wait -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $Engine),'-Effect','off','-Quiet'
        ) | Out-Null
    }
    Update-Status
}

Add-Sep
$miAuto = Add-Item 'Start when I log in' {
    $want = -not $miAuto.Checked
    if (Set-Autostart $want) {
        $miAuto.Checked = $want
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not change the startup setting.`n`nThis needs Administrator.",
            'Keyboard Lighting','OK','Warning') | Out-Null
    }
}
$miAuto.Checked = Test-Autostart

$miUpdate = Add-Item 'Check for updates' {
    $icon.Text = 'Keyboard Lighting - updating...'
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
        if ($r -eq 'Yes') {
            Log 'restarting after update'
            $exe = Join-Path $Here 'KeyboardLighting.exe'
            if (Test-Path $exe) { Start-Process -FilePath $exe }
            else {
                Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                    '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
                    '-File',('"{0}"' -f $PSCommandPath),'-NoUpdate','-Silent')
            }
            $script:Quitting = $true
            $icon.Visible = $false
            [System.Windows.Forms.Application]::Exit()
        }
    }
}

$miLog = Add-Item 'Open log' {
    if (-not (Test-Path $LogFile)) { Set-Content -Path $LogFile -Value 'no entries yet' -Encoding UTF8 }
    Start-Process notepad.exe $LogFile
}
$miFolder = Add-Item 'Open folder' { Start-Process explorer.exe $Here }

Add-Sep
$miExit = Add-Item 'Exit' {
    Log 'exit from menu'
    $script:Quitting = $true
    Stop-Engine
    $icon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
}

$icon.ContextMenuStrip = $menu
$icon.Add_MouseDoubleClick({ $miPanel.PerformClick() })

function Update-Status {
    if (Test-EngineAlive) {
        $miStatus.Text = ('Running - {0}' -f $script:Cfg.Effect)
        $icon.Text = ('Keyboard Lighting - {0}' -f $script:Cfg.Effect)
    } else {
        $miStatus.Text = 'Not running'
        $icon.Text = 'Keyboard Lighting - stopped'
    }
}

# ---------------------------------------------------------------- startup
if (-not $IsAdmin) {
    Log 'not elevated - HID access will fail' 'WARN'
    $icon.BalloonTipTitle = 'Keyboard Lighting'
    $icon.BalloonTipText  = 'Not running as Administrator, so the keyboard cannot be controlled. Right-click the tray icon and use "Start when I log in" to fix this permanently.'
    $icon.ShowBalloonTip(6000)
}

if (-not $NoUpdate) {
    # Background update check; never blocks startup.
    $null = Start-Job -ScriptBlock {
        param($b, $h)
        try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12' } catch { }
        foreach ($f in 'Aura-Background.ps1','Lighting-Panel.ps1','Tray.ps1','Check.ps1','Check.bat','Update.ps1','Update.bat') {
            try {
                $tmp = Join-Path $env:TEMP ('kblbg_' + $f)
                Invoke-WebRequest "$b/$f" -OutFile $tmp -UseBasicParsing -TimeoutSec 20
                $dest = Join-Path $h $f
                $new = (Get-FileHash $tmp -Algorithm SHA256).Hash
                $old = ''
                if (Test-Path $dest) { $old = (Get-FileHash $dest -Algorithm SHA256).Hash }
                if ($new -ne $old) { Copy-Item $tmp $dest -Force }
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            } catch { }
        }
    } -ArgumentList $Base, $Here
}

[void](Start-Engine)
Update-Status

if (-not $Silent) {
    $icon.BalloonTipTitle = 'Keyboard Lighting'
    $icon.BalloonTipText  = 'Running in the tray. Double-click for the control panel.'
    $icon.ShowBalloonTip(3000)
}

# Watchdog: if the engine dies, say so rather than pretending.
$watch = New-Object System.Windows.Forms.Timer
$watch.Interval = 4000
$watch.Add_Tick({
    if (-not (Test-EngineAlive)) {
        if ($miStatus.Text -ne 'Not running') { Log 'engine is no longer running' 'WARN' }
    }
    Update-Status
})
$watch.Start()

$script:Quitting = $false
[System.Windows.Forms.Application]::Run()

if (-not $script:Quitting) { Stop-Engine }
$icon.Visible = $false
try { $script:Mutex.ReleaseMutex(); $script:Mutex.Dispose() } catch { }
Log 'tray exited'
