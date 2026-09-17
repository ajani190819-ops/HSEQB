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
# Logs sit in a "logs" folder next to the program itself, so they are
# where everything else is instead of buried under AppData. The panel and
# the engine write separate files - they are separate processes, and one
# interleaved file made both harder to follow.
#
# The program folder is wherever Setup.bat was run from, which is normally
# Downloads or the Desktop and writable. If it is not - someone put it in
# Program Files, or on a read-only share - fall back to AppData rather
# than silently losing the log.
$LogDir = Join-Path $Here 'logs'
try {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction Stop | Out-Null }
    $probe = Join-Path $LogDir '.writetest'
    Set-Content -Path $probe -Value 'x' -ErrorAction Stop
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
    $LogDir = Join-Path $CfgDir 'logs'
    try { if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null } } catch { }
}
$LogFile   = Join-Path $LogDir 'panel.log'
# Earlier versions logged to AppData. Bring an existing log across rather
# than leaving an orphan that looks current but never updates again.
try {
    foreach ($oldLog in @((Join-Path $CfgDir 'log.txt'), (Join-Path (Join-Path $CfgDir 'logs') 'panel.log'))) {
        if ((Test-Path $oldLog) -and -not (Test-Path $LogFile)) {
            Move-Item -Path $oldLog -Destination $LogFile -Force -ErrorAction SilentlyContinue
        }
    }
} catch { }
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
# Set before anything can call Start-Engine.
$script:EngineErr = ''

$Effects = [ordered]@{
    'Scrolling gradient'   = 'gradient'
    'Rainbow'              = 'rainbow'
    'Wave'                 = 'wave'
    'Comet'                = 'comet'
    'Scanner'              = 'scanner'
    'Breathing'            = 'breathe'
    'Pulse'                = 'pulse'
    'Fire'                 = 'fire'
    'Solid colour'         = 'static'
    'Colour cycle'         = 'cycle'
    'Strobe'               = 'strobe'
    'Starry night'         = 'stars'
    'Ripple'               = 'ripple'
    'Aurora'               = 'aurora'
    'Music - spectrum'     = 'spectrum'
    'Music - level meter'  = 'vumeter'
    'Music - beat flash'   = 'beat'
    'Music - bass pulse'   = 'pulsebass'
    'Screen mirror'        = 'ambient'
    'Battery meter'        = 'battery'
    'CPU meter'            = 'cpu'
    'Clock'                = 'clock'
}

# Effects that choose their own colours, so the swatches do not apply.
$NoPalette  = @('rainbow','cycle','ambient','battery','cpu','clock','fire')
$NeedAudio  = @('spectrum','vumeter','beat','pulsebass')
$NeedScreen = @('ambient')

# ---- two independently controlled groups ----------------------------
function New-GroupCfg {
    param([string]$Effect, $Swatches, [bool]$Loop)
    return [pscustomobject]@{
        On         = $true
        Effect     = $Effect
        Speed      = 10
        Brightness = 100
        Mirror     = $false
        Reverse    = $false
        Equalise   = $true
        Loop       = $Loop
        Swatches   = [string[]]@($Swatches)
    }
}

$script:Cfg = [pscustomobject]@{
    Brightness = 100          # master; this is what the Fn keys drive
    Overlay    = $true
    Link       = $false       # copy keyboard changes onto the bar
    OnExit     = 'off'        # what the keyboard does once this app closes
    Smooth     = $true        # off = allow temporal dither (see the engine)
    Kbd = New-GroupCfg 'Scrolling gradient' @('#FF0000','#FF7F00','#FFFF00','#00FF00','#0000FF','#8B00FF') $false
    Bar = New-GroupCfg 'Rainbow'            @('#00B4FF','#FF0066')                                         $true
}

$script:Tab = 'Kbd'
function Cur { if ($script:Tab -eq 'Bar') { return $script:Cfg.Bar } return $script:Cfg.Kbd }

function Load-Cfg {
    if (-not (Test-Path $CfgFile)) { return }
    try {
        $o = Get-Content $CfgFile -Raw | ConvertFrom-Json
        foreach ($p in 'Brightness','Overlay','Link','OnExit','Smooth') {
            if ($null -ne $o.$p) { $script:Cfg.$p = $o.$p }
        }
        # Files written before the split had one flat set of values; load
        # them into the keyboard group so nothing is lost.
        if ($null -eq $o.Kbd -and $null -ne $o.Effect) {
            $g = $script:Cfg.Kbd
            foreach ($p in 'Effect','Speed','Mirror','Reverse','Equalise','Loop') {
                if ($null -ne $o.$p) { $g.$p = $o.$p }
            }
            if ($o.Swatches) { $g.Swatches = [string[]]@($o.Swatches) }
            Log 'settings migrated from the old single-zone format'
            return
        }
        foreach ($nm in 'Kbd','Bar') {
            $src = $o.$nm
            if (-not $src) { continue }
            $g = $script:Cfg.$nm
            foreach ($p in 'On','Effect','Speed','Brightness','Mirror','Reverse','Equalise','Loop') {
                if ($null -ne $src.$p) { $g.$p = $src.$p }
            }
            if ($src.Swatches) { $g.Swatches = [string[]]@($src.Swatches) }
        }
        Log 'settings loaded'
    } catch { Log ("settings load failed: {0}" -f $_.Exception.Message) 'WARN' }
}

Load-Cfg

function Save-Cfg {
    try {
        $script:Cfg | ConvertTo-Json -Depth 6 | Set-Content -Path $CfgFile -Encoding UTF8 -ErrorAction Stop
    } catch { Log ("settings save failed: {0}" -f $_.Exception.Message) 'WARN' }
}

function Get-EffectToken {
    param($g)
    if (-not $g) { $g = Cur }
    $t = $Effects[[string]$g.Effect]
    if (-not $t) { $t = 'gradient' }
    return $t
}

function New-ThemeBlock {
    param($g)
    return [pscustomobject]@{
        On         = [bool]$g.On
        Effect     = (Get-EffectToken $g)
        Colors     = ($g.Swatches -join ',')
        Speed      = [double]$g.Speed / 10.0
        Brightness = [double]$g.Brightness / 100.0
        Mirror     = [bool]$g.Mirror
        Reverse    = [bool]$g.Reverse
        Equalise   = [bool]$g.Equalise
        Loop       = [bool]$g.Loop
    }
}

function Write-Theme {
    $o = [pscustomobject]@{
        Brightness = [double]$script:Cfg.Brightness / 100.0
        Smooth     = [bool]$script:Cfg.Smooth
        Kbd        = (New-ThemeBlock $script:Cfg.Kbd)
        Bar        = (New-ThemeBlock $script:Cfg.Bar)
    }
    try { $o | ConvertTo-Json -Depth 5 | Set-Content -Path $ThemeFile -Encoding UTF8 -ErrorAction SilentlyContinue } catch { }
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
    # $Graceful is for quitting: wait for the engine to put the lighting
    # where the user wants it. A restart does not need it - the new engine
    # repaints immediately - and waiting there would make every settings
    # change feel sluggish.
    param([switch]$Graceful)

    # Ask first, kill second.
    #
    # Stop-Process -Force skips the engine's cleanup entirely, which is why
    # quitting used to leave the last frame frozen on the keyboard. Drop a
    # stop file instead and give it a moment to put the lighting where the
    # user wants it and release the device properly. Force is the fallback
    # for an engine that is wedged.
    $procs = @()
    try {
        $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                   Where-Object { $_.CommandLine -like '*Aura-Background*' })
    } catch { }

    if ($Graceful -and $procs.Count -gt 0) {
        try {
            if (-not (Test-Path $CfgDir)) { New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null }
            Set-Content -Path (Join-Path $CfgDir 'stop.flag') -Value '1' -Encoding ASCII -ErrorAction SilentlyContinue
        } catch { }

        # The engine checks the flag once per loop, so this is quick.
        $deadline = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 100
            $alive = @()
            try {
                $alive = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
                           Where-Object { $_.CommandLine -like '*Aura-Background*' })
            } catch { }
            if ($alive.Count -eq 0) { break }
        }
    }

    # Anything still running did not stop on its own.
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*Aura-Background*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
    try { Remove-Item (Join-Path $CfgDir 'stop.flag') -Force -ErrorAction SilentlyContinue } catch { }
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
    $k  = $script:Cfg.Kbd
    $bg = $script:Cfg.Bar
    $mB = [double]$script:Cfg.Brightness / 100.0

    $kEff = Get-EffectToken $k
    $bEff = Get-EffectToken $bg
    $kSpd = ([double]$k.Speed  / 10.0).ToString('0.##', $inv)
    $bSpd = ([double]$bg.Speed / 10.0).ToString('0.##', $inv)
    $kBrt = ([double]$k.Brightness  / 100.0).ToString('0.###', $inv)
    $bBrt = ([double]$bg.Brightness / 100.0).ToString('0.###', $inv)
    $mStr = $mB.ToString('0.###', $inv)
    $kLay = 'across'; if ($k.Loop)  { $kLay = 'loop' }
    $bLay = 'across'; if ($bg.Loop) { $bLay = 'loop' }
    $kEq  = 'off';    if ($k.Equalise)  { $kEq = 'on' }
    $bEq  = 'off';    if ($bg.Equalise) { $bEq = 'on' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "')
    [void]$sb.Append($Engine)
    [void]$sb.Append('" -Effect ');     [void]$sb.Append($kEff)
    [void]$sb.Append(' -Speed ');       [void]$sb.Append($kSpd)
    [void]$sb.Append(' -Brightness ');  [void]$sb.Append($kBrt)
    [void]$sb.Append(' -Master ');      [void]$sb.Append($mStr)
    # 60, not higher. Two synchronous feature reports per frame on an
    # EC-backed keyboard cost milliseconds; pushing the rate up just makes
    # frames land unevenly. The engine measures this and backs off further
    # if it still cannot hold cadence.
    [void]$sb.Append(' -Fps 60 -Quiet')
    $oe = "$($script:Cfg.OnExit)"
    if ($oe -ne 'off' -and $oe -ne 'white' -and $oe -ne 'firmware') { $oe = 'off' }
    [void]$sb.Append(' -OnExit '); [void]$sb.Append($oe)
    if ($k.Swatches.Count -gt 0) {
        [void]$sb.Append(' -Colors "'); [void]$sb.Append(($k.Swatches -join ',')); [void]$sb.Append('"')
        [void]$sb.Append(' -Color "');  [void]$sb.Append($k.Swatches[0]); [void]$sb.Append('"')
        if ($k.Swatches.Count -gt 1) {
            [void]$sb.Append(' -Color2 "'); [void]$sb.Append($k.Swatches[1]); [void]$sb.Append('"')
        }
    }
    if ($k.Mirror)  { [void]$sb.Append(' -Mirror') }
    if ($k.Reverse) { [void]$sb.Append(' -Reverse') }
    [void]$sb.Append(' -Equalise '); [void]$sb.Append($kEq)
    [void]$sb.Append(' -Layout ');   [void]$sb.Append($kLay)
    if (-not $k.On) { [void]$sb.Append(' -KbdOff') }

    # ---- light bar ----
    [void]$sb.Append(' -BarEffect ');     [void]$sb.Append($bEff)
    [void]$sb.Append(' -BarSpeed ');      [void]$sb.Append($bSpd)
    [void]$sb.Append(' -BarBrightness '); [void]$sb.Append($bBrt)
    if ($bg.Swatches.Count -gt 0) {
        [void]$sb.Append(' -BarColors "'); [void]$sb.Append(($bg.Swatches -join ',')); [void]$sb.Append('"')
    }
    if ($bg.Mirror)  { [void]$sb.Append(' -BarMirror') }
    if ($bg.Reverse) { [void]$sb.Append(' -BarReverse') }
    [void]$sb.Append(' -BarEqualise '); [void]$sb.Append($bEq)
    [void]$sb.Append(' -BarLayout ');   [void]$sb.Append($bLay)
    if (-not $bg.On) { [void]$sb.Append(' -BarOff') }
    if ($script:Cfg.Overlay) { [void]$sb.Append(' -OverlayOn') }

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
            $code = -1
            try { $code = $script:EngineP.ExitCode } catch { }
            Log ("engine exited immediately, code {0} (kbd={1} bar={2})" -f $code,$kEff,$bEff) 'ERROR'
            $script:EngineP = $null
            # Exit code 2 is the engine telling us it could not compile.
            # That is a broken download, not a transient failure, so say so
            # rather than leaving a dark keyboard and a vague status line.
            if ($code -eq 2) { $script:EngineErr = 'The lighting engine is damaged. Run Setup.bat to repair it.' }
            else             { $script:EngineErr = '' }
            return $false
        }
        $script:EngineErr = ''
        Log ("engine started: kbd={0}/{1} bar={2}/{3} master={4}%" -f $kEff,$kLay,$bEff,$bLay,$script:Cfg.Brightness)
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
    $files = @('Aura-Background.ps1', 'Tray.ps1', 'ui_controls.cs.txt', 'app.ico', 'Setup.ps1', 'Setup.bat', 'Zones.ps1', 'Zones.bat', 'MyEffect.ps1', 'README.md')
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
# Setup pre-builds this into Ui.dll so the window can open without waiting
# for a compiler. Falling back to compiling the .txt keeps a missing or
# stale DLL from being fatal.
$uiFile = Join-Path $Here 'ui_controls.cs.txt'
$uiDll   = Join-Path $Here 'Ui.dll'
$script:CustomUi = $false
if (Test-Path $uiDll) {
    try {
        $srcF = Get-Item $uiFile -ErrorAction SilentlyContinue
        $dllF = Get-Item $uiDll
        if (-not $srcF -or $dllF.LastWriteTime -ge $srcF.LastWriteTime) {
            Add-Type -Path $uiDll -ErrorAction Stop
            $script:CustomUi = $true
            Log 'custom UI loaded from Ui.dll'
        }
    } catch {
        Log ("Ui.dll would not load, compiling instead: {0}" -f $_.Exception.Message) 'WARN'
    }
}
if (-not $script:CustomUi -and (Test-Path $uiFile)) {
    try {
        Add-Type -TypeDefinition (Get-Content $uiFile -Raw) `
                 -ReferencedAssemblies 'System.Windows.Forms','System.Drawing','System' `
                 -ErrorAction Stop
        $script:CustomUi = $true
        Log 'custom UI compiled from source'
    } catch {
        Log ("custom UI failed to compile: {0}" -f $_.Exception.Message) 'ERROR'
    }
} elseif (-not $script:CustomUi) {
    Log 'ui_controls.cs.txt missing' 'WARN'
}
if (-not $script:CustomUi) {
    [System.Windows.Forms.MessageBox]::Show(
        "The interface files are missing or damaged.`n`nRun Setup.bat to repair.",
        'Keyboard Lighting','OK','Error') | Out-Null
    return
}

# Without this the whole window is bitmap-stretched on a high-DPI laptop
# and every edge looks soft. Must happen before any window exists.
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
# touched before then: WinForms scales at handle-creation time.
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode       = 'Dpi'
$form.ClientSize          = New-Object System.Drawing.Size(478, 700)

$bar = New-Object KbLight.TitleBar $form
$bar.Text = 'Keyboard Lighting'
$bar.Font = $fontBd
try { $bar.Logo = $AppIcon.ToBitmap() } catch { }
$form.Controls.Add($bar)

$body = New-Object System.Windows.Forms.Panel
$body.Dock       = 'Fill'
$body.BackColor  = $Bg
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

$M  = 20
$CW = 438
$IW = 406
$y  = 12

# ================================================================ hero + live preview
$cardTop = New-Object KbLight.Card
$cardTop.Location = New-Object System.Drawing.Point($M, $y)
$cardTop.Size     = New-Object System.Drawing.Size($CW, 106)
$body.Controls.Add($cardTop)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text      = 'ROG Strix G16'
$lblTitle.Location  = New-Object System.Drawing.Point(16, 8)
$lblTitle.Size      = New-Object System.Drawing.Size(280, 26)
$lblTitle.ForeColor = $Txt
$lblTitle.Font      = $fontH1
$lblTitle.BackColor = [System.Drawing.Color]::Transparent
$cardTop.Controls.Add($lblTitle)

$dot = New-Object System.Windows.Forms.Label
$dot.Text      = [char]0x25CF
$dot.Location  = New-Object System.Drawing.Point(16, 36)
$dot.Size      = New-Object System.Drawing.Size(14, 16)
$dot.Font      = $fontSm
$dot.ForeColor = $T::Good
$dot.BackColor = [System.Drawing.Color]::Transparent
$cardTop.Controls.Add($dot)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text      = 'Starting'
$lblStatus.Location  = New-Object System.Drawing.Point(32, 36)
$lblStatus.Size      = New-Object System.Drawing.Size(390, 16)
$lblStatus.ForeColor = $Mut
$lblStatus.Font      = $fontSm
$lblStatus.BackColor = [System.Drawing.Color]::Transparent
$cardTop.Controls.Add($lblStatus)

# Live preview of both groups: 4 keyboard cells then 12 light-bar cells.
$pbPreview = New-Object KbLight.Preview
$pbPreview.Location = New-Object System.Drawing.Point(16, 56)
$pbPreview.Size     = New-Object System.Drawing.Size($IW, 40)
$pbPreview.Split    = 4          # 4 keyboard cells, then the 12 light-bar cells
$cardTop.Controls.Add($pbPreview)

$y += 106 + 14

# ================================================================ master brightness
$cardMaster = New-Object KbLight.Card
$cardMaster.Location = New-Object System.Drawing.Point($M, $y)
$cardMaster.Size     = New-Object System.Drawing.Size($CW, 68)
$body.Controls.Add($cardMaster)

$lblMB = New-Object System.Windows.Forms.Label
$lblMB.Text      = 'MASTER BRIGHTNESS'
$lblMB.Location  = New-Object System.Drawing.Point(16, 12)
$lblMB.Size      = New-Object System.Drawing.Size(240, 16)
$lblMB.ForeColor = $Mut
$lblMB.Font      = $fontLb
$lblMB.BackColor = [System.Drawing.Color]::Transparent
$cardMaster.Controls.Add($lblMB)

$valMB = New-Object System.Windows.Forms.Label
$valMB.Text      = '100%'
$valMB.Location  = New-Object System.Drawing.Point(($CW - 86), 12)
$valMB.Size      = New-Object System.Drawing.Size(70, 16)
$valMB.ForeColor = $T::Accent
$valMB.Font      = $fontVal
$valMB.TextAlign = 'TopRight'
$valMB.BackColor = [System.Drawing.Color]::Transparent
$cardMaster.Controls.Add($valMB)

$trkMaster = New-Object KbLight.Slider
$trkMaster.Location = New-Object System.Drawing.Point(16, 32)
$trkMaster.Size     = New-Object System.Drawing.Size($IW, 28)
$trkMaster.Minimum  = 5
$trkMaster.Maximum  = 100
$trkMaster.Value    = 100
$cardMaster.Controls.Add($trkMaster)

$y += 68 + 16

# ================================================================ which part am I editing
$tabs = New-Object KbLight.Tabs
$tabs.Location = New-Object System.Drawing.Point($M, $y)
$tabs.Size     = New-Object System.Drawing.Size($CW, 36)
$tabs.Font     = $fontBd
[void]$tabs.Items.Add('Keyboard')
[void]$tabs.Items.Add('Light bar')
$body.Controls.Add($tabs)
$y += 36 + 8

$chkOn = New-Object KbLight.Toggle
$chkOn.Text     = 'This part is on'
$chkOn.Location = New-Object System.Drawing.Point(($M + 4), $y)
$chkOn.Size     = New-Object System.Drawing.Size(200, 26)
$chkOn.Font     = $fontSm
$body.Controls.Add($chkOn)

$chkLink = New-Object KbLight.Toggle
$chkLink.Text     = 'Match both'
$chkLink.Location = New-Object System.Drawing.Point(($M + 232), $y)
$chkLink.Size     = New-Object System.Drawing.Size(206, 26)
$chkLink.Font     = $fontSm
$body.Controls.Add($chkLink)
$y += 26 + 12

# ================================================================ pattern
New-Head 'PATTERN' $M $y 200 | Out-Null
$y += 20
$cboEffect = New-Object KbLight.Picker
$cboEffect.Location = New-Object System.Drawing.Point($M, $y)
$cboEffect.Size     = New-Object System.Drawing.Size($CW, 40)
$cboEffect.Font     = $fontBd
foreach ($k in $Effects.Keys) { [void]$cboEffect.Items.Add($k) }
$cboEffect.SetQuiet(0)
$body.Controls.Add($cboEffect)
$y += 40 + 3

$lblEffInfo = New-Object System.Windows.Forms.Label
$lblEffInfo.Text      = ''
$lblEffInfo.Location  = New-Object System.Drawing.Point(($M + 2), $y)
$lblEffInfo.Size      = New-Object System.Drawing.Size($CW, 15)
$lblEffInfo.ForeColor = [System.Drawing.Color]::FromArgb(96,102,122)
$lblEffInfo.Font      = $fontSm
$lblEffInfo.BackColor = [System.Drawing.Color]::Transparent
$body.Controls.Add($lblEffInfo)
$y += 15 + 9

# ================================================================ colours
New-Head 'COLOURS' $M $y 200 | Out-Null
$lblColHint = New-Object System.Windows.Forms.Label
$lblColHint.Text      = 'click to change'
$lblColHint.Location  = New-Object System.Drawing.Point(($M + 90), $y)
$lblColHint.Size      = New-Object System.Drawing.Size(240, 16)
$lblColHint.ForeColor = [System.Drawing.Color]::FromArgb(96,102,122)
$lblColHint.Font      = $fontSm
$lblColHint.BackColor = [System.Drawing.Color]::Transparent
$body.Controls.Add($lblColHint)
$y += 20

$pnlCol = New-Object System.Windows.Forms.Panel
$pnlCol.Location  = New-Object System.Drawing.Point($M, $y)
$pnlCol.Size      = New-Object System.Drawing.Size($CW, 44)
$pnlCol.BackColor = [System.Drawing.Color]::Transparent
$body.Controls.Add($pnlCol)
$y += 44 + 12

# ================================================================ speed + zone brightness
$cardSl = New-Object KbLight.Card
$cardSl.Location = New-Object System.Drawing.Point($M, $y)
$cardSl.Size     = New-Object System.Drawing.Size($CW, 112)
$body.Controls.Add($cardSl)

$lblSpeed = New-Object System.Windows.Forms.Label
$lblSpeed.Text      = 'SPEED'
$lblSpeed.Location  = New-Object System.Drawing.Point(16, 10)
$lblSpeed.Size      = New-Object System.Drawing.Size(200, 16)
$lblSpeed.ForeColor = $Mut
$lblSpeed.Font      = $fontLb
$lblSpeed.BackColor = [System.Drawing.Color]::Transparent
$cardSl.Controls.Add($lblSpeed)

$valSpeed = New-Object System.Windows.Forms.Label
$valSpeed.Text      = '1.0x'
$valSpeed.Location  = New-Object System.Drawing.Point(($CW - 86), 10)
$valSpeed.Size      = New-Object System.Drawing.Size(70, 16)
$valSpeed.ForeColor = $T::Accent
$valSpeed.Font      = $fontVal
$valSpeed.TextAlign = 'TopRight'
$valSpeed.BackColor = [System.Drawing.Color]::Transparent
$cardSl.Controls.Add($valSpeed)

$trkSpeed = New-Object KbLight.Slider
$trkSpeed.Location = New-Object System.Drawing.Point(16, 28)
$trkSpeed.Size     = New-Object System.Drawing.Size($IW, 28)
$trkSpeed.Minimum  = 1
$trkSpeed.Maximum  = 50
$trkSpeed.Value    = 10
$cardSl.Controls.Add($trkSpeed)

$lblBright = New-Object System.Windows.Forms.Label
$lblBright.Text      = 'BRIGHTNESS FOR THIS PART'
$lblBright.Location  = New-Object System.Drawing.Point(16, 62)
$lblBright.Size      = New-Object System.Drawing.Size(240, 16)
$lblBright.ForeColor = $Mut
$lblBright.Font      = $fontLb
$lblBright.BackColor = [System.Drawing.Color]::Transparent
$cardSl.Controls.Add($lblBright)

$valBright = New-Object System.Windows.Forms.Label
$valBright.Text      = '100%'
$valBright.Location  = New-Object System.Drawing.Point(($CW - 86), 62)
$valBright.Size      = New-Object System.Drawing.Size(70, 16)
$valBright.ForeColor = $T::Accent
$valBright.Font      = $fontVal
$valBright.TextAlign = 'TopRight'
$valBright.BackColor = [System.Drawing.Color]::Transparent
$cardSl.Controls.Add($valBright)

$trkBright = New-Object KbLight.Slider
$trkBright.Location = New-Object System.Drawing.Point(16, 80)
$trkBright.Size     = New-Object System.Drawing.Size($IW, 28)
$trkBright.Minimum  = 5
$trkBright.Maximum  = 100
$trkBright.Value    = 100
$cardSl.Controls.Add($trkBright)

$y += 112 + 14

# ================================================================ options for this part
$cardOp = New-Object KbLight.Card
$cardOp.Location = New-Object System.Drawing.Point($M, $y)
$cardOp.Size     = New-Object System.Drawing.Size($CW, 78)
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
$colL = 16
$colR = 224
$colW = 198
$chkLoop    = New-Toggle 'Wrap around'     $colL 12 $colW
$chkEq      = New-Toggle 'Even brightness' $colR 12 $colW
$chkMirror  = New-Toggle 'Mirror'          $colL 44 $colW
$chkReverse = New-Toggle 'Reverse'         $colR 44 $colW

$y += 78 + 14

# ================================================================ whole-app options
$chkSmooth = New-Object KbLight.Toggle
$chkSmooth.Text     = 'Smooth colour (turn off if colours look banded)'
$chkSmooth.Location = New-Object System.Drawing.Point(($M + 4), $y)
$chkSmooth.Size     = New-Object System.Drawing.Size($CW, 26)
$chkSmooth.Font     = $fontBd
$body.Controls.Add($chkSmooth)
$y += 26 + 4

$chkOverlay = New-Object KbLight.Toggle
$chkOverlay.Text     = 'Flash the battery level when the charger changes'
$chkOverlay.Location = New-Object System.Drawing.Point(($M + 4), $y)
$chkOverlay.Size     = New-Object System.Drawing.Size($CW, 26)
$chkOverlay.Font     = $fontBd
$body.Controls.Add($chkOverlay)
$y += 26 + 4

$chkAuto = New-Object KbLight.Toggle
$chkAuto.Text     = 'Start when I log in'
$chkAuto.Location = New-Object System.Drawing.Point(($M + 4), $y)
$chkAuto.Size     = New-Object System.Drawing.Size($CW, 26)
$chkAuto.Font     = $fontBd
$body.Controls.Add($chkAuto)
$y += 26 + 14

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
$y += 40 + 10

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text      = 'Every change takes effect straight away.'
$lblHint.Location  = New-Object System.Drawing.Point($M, $y)
$lblHint.Size      = New-Object System.Drawing.Size($CW, 16)
$lblHint.ForeColor = [System.Drawing.Color]::FromArgb(96,102,122)
$lblHint.Font      = $fontSm
$lblHint.TextAlign = 'TopCenter'
$lblHint.BackColor = [System.Drawing.Color]::Transparent
$body.Controls.Add($lblHint)
$y += 16 + 12

# Size to the content, but never taller than the screen will hold. The
# body scrolls if a small display cannot fit it.
$wantH = $bar.Height + $y
$maxH  = 900
try {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
    $maxH = [int]($wa * 0.92)
} catch { }
if ($wantH -gt $maxH) { $wantH = $maxH }
$form.ClientSize = New-Object System.Drawing.Size(478, $wantH)

# ---------------------------------------------------------------- live preview
# The preview used to re-implement each effect in PowerShell, which only
# ever matched reality for the simple gradients - fire, comet, the audio
# modes and the meters were all guesses. The engine now publishes the
# actual bytes it sends to the keyboard, so the preview just reads those.
$script:FrameFile  = Join-Path $CfgDir 'frame.txt'
$script:LayoutFile = Join-Path $CfgDir 'layout.txt'
$script:FrameStamp = -1
$script:FrameCols  = $null
$script:FrameAge   = 0
# Lamp indices in PHYSICAL left-to-right order, published by the engine.
# Device index order is not visual order: the light bar wraps around the
# chassis, so drawing 4..15 in index order would scramble it.
$script:MapKbd     = @(0,1,2,3)
$script:MapBar     = @(4,5,6,7,8,9,10,11,12,13,14,15)
# Real 0..1 position of each lamp within its group. The light bar's lamps
# are clustered with wide gaps, so even spacing would misplace them.
$script:PosKbd     = $null
$script:PosBar     = $null
# True when the group is a closed ring (light bar around the chassis).
$script:RingKbd    = $false
$script:RingBar    = $false
$script:LayStamp   = -1

function Read-Layout {
    try {
        $fi = Get-Item $script:LayoutFile -ErrorAction Stop
        if ($fi.LastWriteTimeUtc.Ticks -eq $script:LayStamp) { return }
        $script:LayStamp = $fi.LastWriteTimeUtc.Ticks
        foreach ($ln in (Get-Content $script:LayoutFile -ErrorAction Stop)) {
            $t = $ln.Trim()
            if ($t -like 'kbdring=*') {
                $script:RingKbd = ($t.Substring(8).Trim() -eq '1')
            } elseif ($t -like 'barring=*') {
                $script:RingBar = ($t.Substring(8).Trim() -eq '1')
            } elseif ($t -like 'kbdpos=*') {
                $v = @($t.Substring(7) -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { [double]$_ })
                if ($v.Count -gt 0) { $script:PosKbd = [double[]]$v } else { $script:PosKbd = $null }
            } elseif ($t -like 'barpos=*') {
                $v = @($t.Substring(7) -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { [double]$_ })
                if ($v.Count -gt 0) { $script:PosBar = [double[]]$v } else { $script:PosBar = $null }
            } elseif ($t -like 'kbd=*') {
                $v = @($t.Substring(4) -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
                if ($v.Count -gt 0) { $script:MapKbd = $v }
            } elseif ($t -like 'bar=*') {
                $v = @($t.Substring(4) -split ',' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ })
                if ($v.Count -gt 0) { $script:MapBar = $v }
            }
        }
    } catch { }
}

function Read-Frame {
    # Returns $true when a usable frame was read.
    try {
        $fi = Get-Item $script:FrameFile -ErrorAction Stop
        $st = $fi.LastWriteTimeUtc.Ticks
        if ($st -eq $script:FrameStamp) { return $false }
        $script:FrameStamp = $st

        $txt = [System.IO.File]::ReadAllText($script:FrameFile)
        if (-not $txt) { return $false }
        $semi = $txt.IndexOf(';')
        if ($semi -lt 1) { return $false }
        $n = 0
        if (-not [int]::TryParse($txt.Substring(0, $semi), [ref]$n)) { return $false }
        if ($n -lt 1 -or $n -gt 512) { return $false }
        $body = $txt.Substring($semi + 1)
        # A torn read is possible: the engine rewrites this file 20x a
        # second. Short body means we caught it mid-write - skip this one
        # rather than draw nonsense.
        if ($body.Length -lt ($n * 6)) { return $false }

        $raw = New-Object 'System.Drawing.Color[]' $n
        for ($k = 0; $k -lt $n; $k++) {
            $o = $k * 6
            $r = [Convert]::ToInt32($body.Substring($o,     2), 16)
            $g = [Convert]::ToInt32($body.Substring($o + 2, 2), 16)
            $b = [Convert]::ToInt32($body.Substring($o + 4, 2), 16)
            $raw[$k] = [System.Drawing.Color]::FromArgb($r, $g, $b)
        }

        # Re-order into physical order: keyboard first, then the bar.
        Read-Layout
        # Only draw lamps this frame actually reported. Anything else used
        # to be painted pure black, which invented holes in the pattern
        # that the keyboard was never showing.
        $kIdx = @(); $kPos = @()
        for ($k = 0; $k -lt $script:MapKbd.Count; $k++) {
            $ix = $script:MapKbd[$k]
            if ($ix -ge 0 -and $ix -lt $n) {
                $kIdx += $ix
                if ($script:PosKbd -and $k -lt $script:PosKbd.Count) { $kPos += $script:PosKbd[$k] }
            }
        }
        $bIdx = @(); $bPos = @()
        for ($k = 0; $k -lt $script:MapBar.Count; $k++) {
            $ix = $script:MapBar[$k]
            if ($ix -ge 0 -and $ix -lt $n) {
                $bIdx += $ix
                if ($script:PosBar -and $k -lt $script:PosBar.Count) { $bPos += $script:PosBar[$k] }
            }
        }
        if ($kIdx.Count + $bIdx.Count -eq 0) { return $false }

        $seq  = @($kIdx) + @($bIdx)
        $cols = New-Object 'System.Drawing.Color[]' $seq.Count
        for ($k = 0; $k -lt $seq.Count; $k++) { $cols[$k] = $raw[$seq[$k]] }

        $pbPreview.Split     = $kIdx.Count
        $pbPreview.LeftRing  = $script:RingKbd
        $pbPreview.RightRing = $script:RingBar
        if ($kPos.Count -eq $kIdx.Count -and $kIdx.Count -gt 0) {
            $pbPreview.PosLeft = [double[]]$kPos
        } else { $pbPreview.PosLeft = $null }
        if ($bPos.Count -eq $bIdx.Count -and $bIdx.Count -gt 0) {
            $pbPreview.PosRight = [double[]]$bPos
        } else { $pbPreview.PosRight = $null }
        $script:FrameCols = $cols
        $script:FrameAge  = 0
        return $true
    } catch {
        return $false
    }
}

# Fallback for when the engine is not running: show the first colour of
# each group, dimmed, so the preview is obviously inert rather than lying.
function Get-IdleColours {
    Read-Layout
    $nk = $script:MapKbd.Count
    $nb = $script:MapBar.Count
    $out = New-Object 'System.Drawing.Color[]' ($nk + $nb)
    for ($i = 0; $i -lt ($nk + $nb); $i++) {
        $g = $script:Cfg.Kbd
        if ($i -ge $nk) { $g = $script:Cfg.Bar }
        $c = [System.Drawing.Color]::FromArgb(24, 25, 32)
        if ($g.On -and $g.Swatches.Count -gt 0) {
            try {
                $h = [System.Drawing.ColorTranslator]::FromHtml($g.Swatches[0])
                $c = [System.Drawing.Color]::FromArgb(
                        [int]($h.R * 0.22), [int]($h.G * 0.22), [int]($h.B * 0.22))
            } catch { }
        }
        $out[$i] = $c
    }
    $pbPreview.Split    = $nk
    $pbPreview.PosLeft  = $script:PosKbd
    $pbPreview.PosRight = $script:PosBar
    return $out
}

function Update-Preview {
    if (Read-Frame) {
        $pbPreview.Colors = $script:FrameCols
        $pbPreview.Live   = $true
        $pbPreview.Invalidate()
        return
    }
    # No new frame. Keep showing the last one for a moment - a static
    # effect legitimately produces no change - then fall back to idle.
    $script:FrameAge++
    if ($script:FrameCols -ne $null -and $script:FrameAge -lt 60) {
        $pbPreview.Live = $true
        return
    }
    $script:FrameCols = $null
    $pbPreview.Colors = Get-IdleColours
    $pbPreview.Live   = $false
    $pbPreview.Invalidate()
}

# ---------------------------------------------------------------- swatches
function Redraw-Swatches {
    $g = Cur
    $pnlCol.Controls.Clear()
    $x = 0
    for ($i = 0; $i -lt $g.Swatches.Count; $i++) {
        $sw = New-Object KbLight.Swatch
        $sw.Location = New-Object System.Drawing.Point($x, 0)
        $sw.Size     = New-Object System.Drawing.Size(44, 44)
        try { $sw.Value = [System.Drawing.ColorTranslator]::FromHtml($g.Swatches[$i]) }
        catch { $sw.Value = [System.Drawing.Color]::Gray }
        $sw.Tag = $i
        $sw.Add_Click({
            $idx = $this.Tag
            $gg  = Cur
            $dlg = New-Object System.Windows.Forms.ColorDialog
            $dlg.FullOpen = $true
            try { $dlg.Color = [System.Drawing.ColorTranslator]::FromHtml($gg.Swatches[$idx]) } catch { }
            if ($dlg.ShowDialog() -eq 'OK') {
                $arr = @($gg.Swatches)
                $arr[$idx] = '#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B
                $gg.Swatches = [string[]]$arr
                Sync-Link
                Redraw-Swatches
                Update-Preview
                Request-Apply
            }
        })
        $pnlCol.Controls.Add($sw)
        $x += 50
    }
    if ($g.Swatches.Count -lt 8) {
        $add = New-Object KbLight.MiniBtn
        $add.Glyph    = '+'
        $add.Location = New-Object System.Drawing.Point($x, 0)
        $add.Size     = New-Object System.Drawing.Size(30, 44)
        $add.Add_Click({
            $gg = Cur
            $gg.Swatches = [string[]]@(@($gg.Swatches) + '#FFFFFF')
            Sync-Link
            Redraw-Swatches
            Update-Preview
            Request-Apply
        })
        $pnlCol.Controls.Add($add)
        $x += 36
    }
    if ($g.Swatches.Count -gt 2) {
        $rem = New-Object KbLight.MiniBtn
        $rem.Glyph    = '-'
        $rem.Location = New-Object System.Drawing.Point($x, 0)
        $rem.Size     = New-Object System.Drawing.Size(30, 44)
        $rem.Add_Click({
            $gg = Cur
            if ($gg.Swatches.Count -gt 2) {
                $arr = @($gg.Swatches)
                $gg.Swatches = [string[]]@($arr[0..($arr.Count-2)])
                Sync-Link
                Redraw-Swatches
                Update-Preview
                Request-Apply
            }
        })
        $pnlCol.Controls.Add($rem)
    }
    # colours do not apply to every pattern
    $tok = Get-EffectToken $g
    $usesPal = -not ($NoPalette -contains $tok)
    foreach ($c in $pnlCol.Controls) { $c.Enabled = $usesPal }
}

# When "same settings for both" is on, copy the edited group onto the other.
function Sync-Link {
    if (-not $script:Cfg.Link) { return }
    $src = Cur
    $dst = $script:Cfg.Bar
    if ($script:Tab -eq 'Bar') { $dst = $script:Cfg.Kbd }
    foreach ($p in 'Effect','Speed','Brightness','Mirror','Reverse','Equalise','On') {
        $dst.$p = $src.$p
    }
    $dst.Swatches = [string[]]@($src.Swatches)
}

# ---------------------------------------------------------------- live apply
function Update-EffectInfo {
    $g = Cur
    $tok = Get-EffectToken $g
    $msg = ''
    if ($NeedAudio -contains $tok) {
        $msg = 'Listens to whatever is playing through your speakers.'
    } elseif ($NeedScreen -contains $tok) {
        $msg = 'Copies the colours on your screen.'
    } elseif ($tok -eq 'battery') {
        $msg = 'Fills up with your battery level. Green full, red empty.'
    } elseif ($tok -eq 'cpu') {
        $msg = 'Fills up with how hard the computer is working.'
    } elseif ($tok -eq 'clock') {
        $msg = 'Colour follows the time of day.'
    } elseif ($NoPalette -contains $tok) {
        $msg = 'This pattern picks its own colours.'
    }
    $lblEffInfo.Text = $msg
    $usesPal = -not ($NoPalette -contains $tok)
    if ($usesPal) { $lblColHint.Text = 'click to change' }
    else          { $lblColHint.Text = 'not used by this pattern' }
}

# Push every control's value into the group the tab is showing.
function Sync-CfgFromUi {
    $g = Cur
    $g.Effect     = [string]$cboEffect.SelectedItem
    $g.Speed      = [int]$trkSpeed.Value
    $g.Brightness = [int]$trkBright.Value
    $g.Mirror     = [bool]$chkMirror.Checked
    $g.Reverse    = [bool]$chkReverse.Checked
    $g.Equalise   = [bool]$chkEq.Checked
    $g.Loop       = [bool]$chkLoop.Checked
    $g.On         = [bool]$chkOn.Checked
    $script:Cfg.Brightness = [int]$trkMaster.Value
    Sync-Link
}

# Load the visible group's values into the controls.
function Load-UiFromCfg {
    $script:Suppress = $true
    $g = Cur
    $keys = @($Effects.Keys)
    $idx = 0
    for ($i = 0; $i -lt $keys.Count; $i++) {
        if ($keys[$i] -eq [string]$g.Effect) { $idx = $i }
    }
    $cboEffect.SetQuiet($idx)
    $trkSpeed.Value  = [Math]::Min(50,  [Math]::Max(1,  [int]$g.Speed))
    $trkBright.Value = [Math]::Min(100, [Math]::Max(5,  [int]$g.Brightness))
    $chkMirror.SetQuiet([bool]$g.Mirror)
    $chkReverse.SetQuiet([bool]$g.Reverse)
    $chkEq.SetQuiet([bool]$g.Equalise)
    $chkLoop.SetQuiet([bool]$g.Loop)
    $chkOn.SetQuiet([bool]$g.On)
    $valSpeed.Text  = ('{0:0.0}x' -f ($trkSpeed.Value / 10.0))
    $valBright.Text = ('{0}%' -f $trkBright.Value)
    Redraw-Swatches
    Update-EffectInfo
    $script:Suppress = $false
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
        $k = $script:Cfg.Kbd
        $b = $script:Cfg.Bar
        $parts = @()
        if ($k.On) { $parts += ('Keys: {0}' -f $k.Effect) } else { $parts += 'Keys: off' }
        if ($b.On) { $parts += ('Bar: {0}'  -f $b.Effect) } else { $parts += 'Bar: off' }
        $txt = ($parts -join '   ')
        $lblStatus.Text = $txt
        $dot.ForeColor  = $T::Good
        $icon.Text      = 'Keyboard Lighting'
        $miStatus.Text  = $txt
    } else {
        $msg = 'Not running'
        if ($script:EngineErr) { $msg = $script:EngineErr }
        $lblStatus.Text = $msg
        $dot.ForeColor  = $T::Bad
        $icon.Text      = 'Keyboard Lighting - stopped'
        $miStatus.Text  = $msg
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
        # Everything below is picked up live by the engine: effect,
        # colours, speed, brightness, flags and on/off, per group.
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

# ---- control events ----
$trkMaster.Add_ValueChanged({
    $valMB.Text = ('{0}%' -f $trkMaster.Value)
    if ($script:Suppress) { return }
    $script:Cfg.Brightness = [int]$trkMaster.Value
    Write-LiveBrightness
    Update-Preview
    Request-Apply
})
$trkBright.Add_ValueChanged({
    $valBright.Text = ('{0}%' -f $trkBright.Value)
    if ($script:Suppress) { return }
    (Cur).Brightness = [int]$trkBright.Value
    Sync-Link
    Update-Preview
    Request-Apply
})
$trkSpeed.Add_ValueChanged({
    $valSpeed.Text = ('{0:0.0}x' -f ($trkSpeed.Value / 10.0))
    if ($script:Suppress) { return }
    (Cur).Speed = [int]$trkSpeed.Value
    Sync-Link
    Request-Apply
})
$cboEffect.Add_SelectedChanged({
    if ($script:Suppress) { return }
    (Cur).Effect = [string]$cboEffect.SelectedItem
    Sync-Link
    Update-EffectInfo
    Redraw-Swatches
    Update-Preview
    Request-Apply
})
$chkMirror.Add_CheckedChanged({
    if ($script:Suppress) { return }
    (Cur).Mirror = [bool]$chkMirror.Checked
    Sync-Link; Request-Apply
})
$chkReverse.Add_CheckedChanged({
    if ($script:Suppress) { return }
    (Cur).Reverse = [bool]$chkReverse.Checked
    Sync-Link; Request-Apply
})
$chkLoop.Add_CheckedChanged({
    if ($script:Suppress) { return }
    (Cur).Loop = [bool]$chkLoop.Checked
    Sync-Link; Update-Preview; Request-Apply
})
$chkEq.Add_CheckedChanged({
    if ($script:Suppress) { return }
    (Cur).Equalise = [bool]$chkEq.Checked
    Sync-Link; Update-Preview; Request-Apply
})
$chkOn.Add_CheckedChanged({
    if ($script:Suppress) { return }
    (Cur).On = [bool]$chkOn.Checked
    Sync-Link; Update-Preview; Request-Apply
})
$chkLink.Add_CheckedChanged({
    if ($script:Suppress) { return }
    $script:Cfg.Link = [bool]$chkLink.Checked
    if ($script:Cfg.Link) {
        Sync-Link
        Update-Preview
        Request-Apply
    } else {
        Save-Cfg
    }
})
$chkSmooth.Add_CheckedChanged({
    if ($script:Suppress) { return }
    $script:Cfg.Smooth = [bool]$chkSmooth.Checked
    Save-Cfg
    # Applies live through theme.json, exactly like the colour controls.
    # Deliberately does NOT restart the engine.
    Write-Theme
})
$chkOverlay.Add_CheckedChanged({
    if ($script:Suppress) { return }
    $script:Cfg.Overlay = [bool]$chkOverlay.Checked
    Save-Cfg
    # A start-up switch, so the engine has to come back up for this one.
    if (-not $script:WantOff) { [void](Start-Engine) }
    Update-Status
})

$tabs.Add_SelectedChanged({
    if ($tabs.SelectedIndex -eq 1) { $script:Tab = 'Bar' } else { $script:Tab = 'Kbd' }
    Load-UiFromCfg
    Update-Preview
})

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
$menu.BackColor       = $T::Panel2
$menu.ForeColor       = $Txt
$menu.Font            = $fontBd
$menu.ShowImageMargin = $false
$menu.Renderer        = New-Object System.Windows.Forms.ToolStripProfessionalRenderer

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
# What the keyboard should do once this app is closed.
$miWhenClosed = New-Object System.Windows.Forms.ToolStripMenuItem
$miWhenClosed.Text = 'When closed'
$miWhenClosed.BackColor = $T::Panel2
$miWhenClosed.ForeColor = $Txt
[void]$menu.Items.Add($miWhenClosed)

$script:ExitChoices = @{}
function Add-ExitChoice {
    param([string]$key, [string]$text)
    $it = New-Object System.Windows.Forms.ToolStripMenuItem
    $it.Text = $text
    $it.BackColor = $T::Panel2
    $it.ForeColor = $Txt
    $it.Add_Click({
        $script:Cfg.OnExit = $key
        foreach ($kv in $script:ExitChoices.GetEnumerator()) {
            $kv.Value.Checked = ($kv.Key -eq $key)
        }
        Save-Cfg
        Log "on-exit set to $key"
    }.GetNewClosure())
    [void]$miWhenClosed.DropDownItems.Add($it)
    $script:ExitChoices[$key] = $it
}
Add-ExitChoice 'off'      'Turn the lighting off'
Add-ExitChoice 'white'    'Leave it plain white'
Add-ExitChoice 'firmware' 'Let the keyboard take over'

# Tick whichever one is saved.
$script:CurExit = "$($script:Cfg.OnExit)"
if (-not $script:ExitChoices.ContainsKey($script:CurExit)) { $script:CurExit = 'off' }
foreach ($kv in $script:ExitChoices.GetEnumerator()) {
    $kv.Value.Checked = ($kv.Key -eq $script:CurExit)
}

Add-Sep
# Opens the folder rather than one file: the panel and the engine log
# separately, and the engine's is the one with the lighting timings in it.
$miLog = Add-Item 'Open logs folder' {
    try {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
        if (-not (Test-Path $LogFile)) { Set-Content -Path $LogFile -Value 'no entries yet' -Encoding UTF8 }
        Start-Process explorer.exe $LogDir
    } catch { }
}
$miFolder = Add-Item 'Open program folder' { Start-Process explorer.exe $Here }
Add-Sep
$miExit = Add-Item 'Exit' {
    Log 'exit from menu'
    $script:Quitting = $true
    Stop-Engine -Graceful
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
# Safe here: the handle exists and DPI scaling has been applied.
$form.Add_Shown({ try { [KbLight.Win]::RoundCorners($form.Handle) } catch { } })

# ---------------------------------------------------------------- load UI
$script:Suppress = $true
$trkMaster.Value = [Math]::Min(100, [Math]::Max(5, [int]$script:Cfg.Brightness))
$valMB.Text      = ('{0}%' -f $trkMaster.Value)
$chkLink.SetQuiet([bool]$script:Cfg.Link)
$chkSmooth.SetQuiet([bool]$script:Cfg.Smooth)
$chkOverlay.SetQuiet([bool]$script:Cfg.Overlay)
$chkAuto.SetQuiet((Test-Autostart))
$miAuto.Checked = $chkAuto.Checked
$tabs.SetQuiet(0)
$script:Tab = 'Kbd'
$script:Suppress = $false
Load-UiFromCfg
Update-Preview

# Poll the engine's published frame. The engine writes at 20 fps; polling
# at 25 keeps the preview current without ever waiting on it. Nothing is
# simulated here - this only reads and draws.
$anim = New-Object System.Windows.Forms.Timer
$anim.Interval = 40
$anim.Add_Tick({
    if (-not $form.Visible) { return }
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
        foreach ($f in 'Aura-Background.ps1','Tray.ps1','ui_controls.cs.txt','app.ico','Setup.ps1','Setup.bat','Zones.ps1','Zones.bat','MyEffect.ps1','README.md') {
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
Update-Status

if (-not $Silent) { Show-Window }

# Register for sleep/lock so the app can repair the lighting on wake.
# No -Action scriptblock: that runs in its own scope, so a flag set inside
# it would never be visible here. Queue the events and drain them below.
$script:PowerOk = $false
try {
    Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) `
        -EventName PowerModeChanged -SourceIdentifier 'TrayPower' `
        -ErrorAction Stop | Out-Null
    Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) `
        -EventName SessionSwitch -SourceIdentifier 'TraySession' `
        -ErrorAction SilentlyContinue | Out-Null
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
        $se = Get-Event -SourceIdentifier 'TraySession' -ErrorAction SilentlyContinue
        while ($se) {
            Remove-Event -EventIdentifier $se.EventIdentifier -ErrorAction SilentlyContinue
            $woke = $true
            $se = Get-Event -SourceIdentifier 'TraySession' -ErrorAction SilentlyContinue
        }
    }
    if ($woke) {
        Log 'resume/session event'
        # Do NOT sleep here: this is the UI thread. Schedule the repair a
        # few ticks later so the USB stack has time to settle.
        if (-not $script:WantOff) { $script:WakeAt = $script:tick + 4 }
    }
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

if (-not $script:Quitting) { Stop-Engine -Graceful }
Unregister-Event -SourceIdentifier 'TrayPower' -ErrorAction SilentlyContinue
Unregister-Event -SourceIdentifier 'TraySession' -ErrorAction SilentlyContinue
$icon.Visible = $false
try { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue } catch { }
Log 'exited'
