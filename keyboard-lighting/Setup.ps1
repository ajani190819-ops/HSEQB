# =====================================================================
#  Keyboard Lighting - Setup
#
#  THE ONLY FILE YOU EVER RUN. It replaces Install, Update and Check.
#
#  Run it any time. It works out what is needed and does it:
#    - downloads the latest version of everything
#    - builds KeyboardLighting.exe
#    - creates the Start menu and Desktop shortcuts
#    - sets it to start when you log in
#    - makes G-Helper leave the keyboard colours alone
#    - tests that it actually works, and tells you what is wrong if not
#
#  First run installs. Every run after that updates and repairs.
# =====================================================================

param(
    [switch]$NoElevate,     # internal: do not try to elevate again
    [switch]$TestOnly       # skip installing, just run the checks
)

$ErrorActionPreference = 'Continue'

$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Base     = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting'
$TaskName = 'KeyboardLighting'
$ExePath  = Join-Path $Here 'KeyboardLighting.exe'
$TrayPs   = Join-Path $Here 'Tray.ps1'
$Engine   = Join-Path $Here 'Aura-Background.ps1'

$Files = @('Aura-Background.ps1', 'Tray.ps1', 'ui_controls.cs.txt', 'app.ico', 'Setup.ps1', 'Setup.bat', 'Zones.ps1', 'Zones.bat', 'MyEffect.ps1', 'README.md')

# --------------------------------------------------------------- output
$script:Report   = New-Object System.Collections.ArrayList
$script:Problems = New-Object System.Collections.ArrayList

function Log($t)  { [void]$script:Report.Add($t) }
function Line($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c; Log $t }
function Step($t) {
    Write-Host ''
    Write-Host "  $t" -ForegroundColor Cyan
    Write-Host ('  ' + ('-' * 62)) -ForegroundColor DarkGray
    Log ''
    Log "  $t"
    Log ('  ' + ('-' * 62))
}
function Ok($t)   { Write-Host '   [OK]   ' -ForegroundColor Green  -NoNewline; Write-Host $t; Log "   [OK]   $t" }
function Bad($t)  { Write-Host '   [FAIL] ' -ForegroundColor Red    -NoNewline; Write-Host $t; Log "   [FAIL] $t" }
function Warn($t) { Write-Host '   [WARN] ' -ForegroundColor Yellow -NoNewline; Write-Host $t; Log "   [WARN] $t" }
function Info($t) { Write-Host '          ' -NoNewline; Write-Host $t -ForegroundColor Gray; Log "          $t" }
function Need($t) { [void]$script:Problems.Add($t) }

Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor Cyan
Write-Host '   KEYBOARD LIGHTING - SETUP  (v16)' -ForegroundColor Cyan
Write-Host '  ===============================================================' -ForegroundColor Cyan
Log '  ==============================================================='
Log '   KEYBOARD LIGHTING - SETUP  (v16)'
Log '  ==============================================================='
Log ("   {0}" -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    Log ("   Windows {0} (build {1})" -f $os.Caption, $os.BuildNumber)
    Log ("   PowerShell {0}" -f $PSVersionTable.PSVersion.ToString())
    Log ("   Folder {0}" -f $Here)
} catch { }

# --------------------------------------------------------------- admin
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    $isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

if (-not $isAdmin -and -not $NoElevate) {
    Write-Host ''
    Write-Host '  Asking for Administrator...' -ForegroundColor Yellow
    try {
        $a = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
        if ($TestOnly) { $a += '-TestOnly' }
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $a
    } catch {
        Write-Host '  Permission refused. Setup cannot continue.' -ForegroundColor Red
        Read-Host '  Press Enter to close'
    }
    return
}

Step '1. Administrator rights'
if ($isAdmin) {
    Ok 'Running as Administrator.'
} else {
    Bad 'NOT running as Administrator.'
    Info 'Windows will refuse direct access to the keyboard.'
    Need 'Right-click Setup.bat and choose "Run as administrator".'
}

# --------------------------------------------------------------- download
if (-not $TestOnly) {
    Step '2. Getting the latest files'
    try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12' } catch { }

    $new = 0; $same = 0; $miss = @()
    foreach ($f in $Files) {
        $dest = Join-Path $Here $f
        $tmp  = Join-Path $env:TEMP ('kbl_' + $f)
        try {
            Invoke-WebRequest "$Base/$f" -OutFile $tmp -UseBasicParsing -TimeoutSec 25
            $nh = (Get-FileHash $tmp -Algorithm SHA256).Hash
            $oh = ''
            if (Test-Path $dest) { $oh = (Get-FileHash $dest -Algorithm SHA256).Hash }
            if ($nh -ne $oh) {
                Copy-Item $tmp $dest -Force
                Unblock-File $dest -ErrorAction SilentlyContinue
                Info ("updated    {0}" -f $f)
                $new++
            } else {
                $same++
            }
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        } catch {
            if (Test-Path $dest) {
                Info ("could not check {0} - keeping the copy you have" -f $f)
            } else {
                Bad ("could not download {0}" -f $f)
                $miss += $f
            }
        }
    }
    if ($miss.Count -gt 0) {
        Need 'Some files could not be downloaded. Check your internet and run Setup.bat again.'
    } elseif ($new -eq 0) {
        Ok ("Already up to date ({0} files)." -f $same)
    } else {
        Ok ("{0} file(s) updated, {1} unchanged." -f $new, $same)
    }
} else {
    Step '2. Getting the latest files'
    Info 'skipped (test only)'
}

# the app cannot start without these
foreach ($need in 'Tray.ps1','ui_controls.cs.txt','Aura-Background.ps1') {
    if (-not (Test-Path (Join-Path $Here $need))) {
        Bad ("{0} is missing" -f $need)
        Need ("{0} is missing - run Setup.bat again with a working internet connection." -f $need)
    }
}

# --------------------------------------------------------------- stop running copies
if (-not $TestOnly) {
    Step '3. Closing any running copy'
    try {
        Get-CimInstance Win32_Process -Filter "Name='KeyboardLighting.exe'" -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like '*Tray.ps1*' -or $_.CommandLine -like '*Aura-Background*' } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 700
        Ok 'Closed.'
    } catch { Ok 'Nothing was running.' }
}

# --------------------------------------------------------------- build exe
if (-not $TestOnly) {
    Step '4. Building KeyboardLighting.exe'
    $csc = $null
    foreach ($cand in @(
        "$env:WinDir\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
        "$env:WinDir\Microsoft.NET\Framework\v4.0.30319\csc.exe")) {
        if (Test-Path $cand) { $csc = $cand; break }
    }
    if (-not $csc) {
        Warn 'No C# compiler found - a shortcut will be used instead.'
    } else {
        $src  = Join-Path $env:TEMP 'kbl_launcher.cs'
        $code = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

class Launcher {
    [STAThread]
    static int Main(string[] args) {
        string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string tray = Path.Combine(dir, "Tray.ps1");
        if (!File.Exists(tray)) {
            System.Windows.Forms.MessageBox.Show(
                "Tray.ps1 is missing from:\n" + dir +
                "\n\nRun Setup.bat to repair.",
                "Keyboard Lighting");
            return 1;
        }
        string extra = "";
        for (int i = 0; i < args.Length; i++) extra += " " + args[i];
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + tray + "\"" + extra;
        psi.WorkingDirectory = dir;
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WindowStyle = ProcessWindowStyle.Hidden;
        try { Process.Start(psi); }
        catch (Exception ex) {
            System.Windows.Forms.MessageBox.Show("Could not start:\n" + ex.Message, "Keyboard Lighting");
            return 2;
        }
        return 0;
    }
}
'@
        Set-Content -Path $src -Value $code -Encoding UTF8
        $cscArgs = @('/nologo','/target:winexe','/optimize+',
                     '/reference:System.Windows.Forms.dll','/reference:System.dll')
        $ico = Join-Path $Here 'app.ico'
        if (Test-Path $ico) { $cscArgs += ('/win32icon:"{0}"' -f $ico) }
        $cscArgs += ('/out:"{0}"' -f $ExePath)
        $cscArgs += ('"{0}"' -f $src)
        $p = Start-Process -FilePath $csc -ArgumentList $cscArgs -NoNewWindow -Wait -PassThru `
             -RedirectStandardOutput (Join-Path $env:TEMP 'kbl_csc_out.txt') `
             -RedirectStandardError  (Join-Path $env:TEMP 'kbl_csc_err.txt')
        $built = (Test-Path $ExePath) -and ($p.ExitCode -eq 0)
        if ($built -and (Get-Item $ExePath).Length -lt 2048) { $built = $false }
        if ($built) {
            Ok ('Built ({0} bytes).' -f (Get-Item $ExePath).Length)
        } else {
            if (Test-Path $ExePath) { Remove-Item $ExePath -Force -ErrorAction SilentlyContinue }
            Warn 'Could not build the exe - a shortcut will be used instead.'
            $e = ''
            try { $e  = Get-Content (Join-Path $env:TEMP 'kbl_csc_err.txt') -Raw } catch { }
            try { $e += Get-Content (Join-Path $env:TEMP 'kbl_csc_out.txt') -Raw } catch { }
            if ($e.Trim()) { Info $e.Trim() }
        }
        Remove-Item $src -Force -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------------------------- shortcuts + autostart
if (-not $TestOnly) {
    Step '5. Shortcuts and starting at log in'
    $usePs = -not (Test-Path $ExePath)

    function New-Shortcut($path) {
        try {
            $sh  = New-Object -ComObject WScript.Shell
            $lnk = $sh.CreateShortcut($path)
            if ($usePs) {
                $lnk.TargetPath = 'powershell.exe'
                $lnk.Arguments  = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $TrayPs)
            } else {
                $lnk.TargetPath = $ExePath
            }
            $lnk.WorkingDirectory = $Here
            $lnk.Description = 'Keyboard Lighting'
            $ico = Join-Path $Here 'app.ico'
            if (Test-Path $ico)   { $lnk.IconLocation = $ico }
            elseif (-not $usePs)  { $lnk.IconLocation = $ExePath }
            else                  { $lnk.IconLocation = "$env:WinDir\System32\shell32.dll,176" }
            $lnk.Save()
            return $true
        } catch { return $false }
    }

    $sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Keyboard Lighting.lnk'
    $dt = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Keyboard Lighting.lnk'
    if (New-Shortcut $sm) { Ok 'Start menu shortcut ready.' } else { Warn 'Start menu shortcut failed.' }
    if (New-Shortcut $dt) { Ok 'Desktop shortcut ready.' }    else { Warn 'Desktop shortcut failed.' }

    try {
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        }
        if (Test-Path $ExePath) {
            $act = New-ScheduledTaskAction -Execute $ExePath -Argument '-Silent' -WorkingDirectory $Here
        } else {
            $act = New-ScheduledTaskAction -Execute 'powershell.exe' `
                   -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Silent' -f $TrayPs) `
                   -WorkingDirectory $Here
        }
        $trg  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
        $prin = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
        $set  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
        Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg `
            -Principal $prin -Settings $set -Description 'Keyboard lighting' -Force | Out-Null
        Ok 'Will start at log in, with no permission prompt.'
    } catch {
        Warn ('Autostart could not be set: ' + $_.Exception.Message)
    }
}

# --------------------------------------------------------------- G-Helper
# G-Helper is welcome to stay. It only has to stop pushing its own colours
# at the keyboard. "skip_aura" tells it not to apply a lighting mode on
# startup, which is the one thing that fights us. Fan curves, performance
# modes, the Fn brightness keys and everything else keep working.
Step '6. G-Helper'
$ghCfg     = Join-Path $env:APPDATA 'GHelper\config.json'
$ghRunning = [bool](Get-Process -Name 'GHelper' -ErrorAction SilentlyContinue)
$ghPath    = $null
try {
    $pp = Get-Process -Name 'GHelper' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pp) { $ghPath = $pp.Path }
} catch { }

if (-not (Test-Path $ghCfg) -and -not $ghRunning) {
    Info 'G-Helper is not installed. Nothing to do.'
} else {
    if ($ghRunning) { Info 'G-Helper is running - that is fine, it can stay.' }
    $skip = $null
    $cfg  = $null
    try {
        if (Test-Path $ghCfg) {
            $raw = Get-Content $ghCfg -Raw -ErrorAction Stop
            if ($raw.Trim()) { $cfg = $raw | ConvertFrom-Json -ErrorAction Stop }
        }
        if ($cfg -and $null -ne $cfg.skip_aura) { $skip = [int]$cfg.skip_aura }
    } catch {
        Warn 'G-Helper config.json could not be read.'
    }

    if ($skip -eq 1) {
        Ok 'G-Helper is already set to leave the keyboard colours alone.'
    } elseif ($TestOnly) {
        Warn 'G-Helper will re-apply its own colours on startup.'
        Need 'Run Setup.bat (not test mode) to set G-Helper to leave the colours alone.'
    } else {
        try {
            if (-not $cfg) { $cfg = New-Object PSObject }
            if ($null -ne $cfg.skip_aura) { $cfg.skip_aura = 1 }
            else { Add-Member -InputObject $cfg -MemberType NoteProperty -Name 'skip_aura' -Value 1 -Force }

            $dir = Split-Path -Parent $ghCfg
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            if (Test-Path $ghCfg) { Copy-Item $ghCfg ($ghCfg + '.bak') -Force -ErrorAction SilentlyContinue }
            ($cfg | ConvertTo-Json -Depth 10) | Set-Content -Path $ghCfg -Encoding UTF8 -ErrorAction Stop
            Ok 'G-Helper set to leave the keyboard colours to us (skip_aura).'
            Info 'Everything else in G-Helper is untouched.'

            # G-Helper only reads this at startup, and it rewrites the file
            # when it exits, so it has to be restarted for this to hold.
            if ($ghRunning -and $ghPath) {
                Info 'Restarting G-Helper so the change takes effect...'
                try {
                    Get-Process -Name 'GHelper' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 900
                    # re-write: G-Helper saves its config on exit and would
                    # otherwise put the old value straight back
                    ($cfg | ConvertTo-Json -Depth 10) | Set-Content -Path $ghCfg -Encoding UTF8 -ErrorAction SilentlyContinue
                    Start-Process -FilePath $ghPath -WorkingDirectory (Split-Path -Parent $ghPath)
                    Ok 'G-Helper restarted.'
                } catch {
                    Warn 'Could not restart G-Helper - close and reopen it yourself.'
                }
            } elseif ($ghRunning) {
                Warn 'Close and reopen G-Helper for this to take effect.'
            }
        } catch {
            Warn ('Could not update G-Helper config: ' + $_.Exception.Message)
            Info 'Not fatal - our engine repaints 60 times a second and wins anyway.'
        }
    }
}

# --------------------------------------------------------------- checks
Step '7. Windows Dynamic Lighting'
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
    Bad 'Dynamic Lighting is ON. It takes the keyboard exclusively.'
    Need 'Turn OFF Settings > Personalization > Dynamic Lighting.'
} elseif ($dlOn -eq $false) {
    Ok 'Dynamic Lighting is off.'
} else {
    Warn 'Could not read the Dynamic Lighting setting (not fatal).'
    Info 'Check manually: Settings > Personalization > Dynamic Lighting = Off'
}

Step '8. Other lighting software'
$bad = @('ArmouryCrate','ArmouryCrate.UserSessionHelper','ArmouryQtService',
         'LightingService','AsusSystemAnalysis','AsusOptimization',
         'OpenRGB','SignalRgb','iCUE','msi-center')
$found = @()
foreach ($b in $bad) {
    if (Get-Process -Name $b -ErrorAction SilentlyContinue) { $found += $b }
}
if ($found.Count -eq 0) {
    Ok 'Nothing else is competing for the keyboard.'
} else {
    Warn ('Running: ' + ($found -join ', '))
    Info 'These take exclusive control and will fight the lighting.'
    Need ('Close these: ' + ($found -join ', '))
}

Step '9. The keyboard'
$dev = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
       Where-Object { $_.DeviceID -like '*VID_0B05&PID_19B6*' }
if ($dev) {
    Ok ("Found ({0} interfaces)." -f @($dev).Count)
} else {
    Bad 'Keyboard HID device VID_0B05 PID_19B6 not found.'
    Need 'The keyboard is missing from Device Manager - reboot and try again.'
}
# full list goes in the report file, not on screen
foreach ($d in $dev) { Log ('          ' + $d.DeviceID) }

Step '10. Testing the lighting engine'
if (-not (Test-Path $Engine)) {
    Bad 'Aura-Background.ps1 is missing.'
    Need 'Run Setup.bat again to download it.'
} else {
    Info 'Flashing the keyboard red for a moment...'
    $outLog = Join-Path $env:TEMP 'kbl_engine_out.txt'
    $errLog = Join-Path $env:TEMP 'kbl_engine_err.txt'
    foreach ($f in @($outLog,$errLog)) { if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue } }

    $proc = Start-Process -FilePath 'powershell.exe' -PassThru -NoNewWindow `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',
                            ('"{0}"' -f $Engine),'-Effect','static','-Color','#FF0000')
    if (-not $proc.WaitForExit(9000)) {
        Start-Sleep -Milliseconds 500
        try { $proc.Kill() } catch { }
    }
    Start-Sleep -Milliseconds 400
    $code = -1
    try { $code = $proc.ExitCode } catch { }

    $out = ''; $err = ''
    if (Test-Path $outLog) { $out = (Get-Content $outLog -Raw) }
    if (Test-Path $errLog) { $err = (Get-Content $errLog -Raw) }
    $all = "$out`n$err"

    Log ''
    Log '  ---------------- engine output ----------------'
    if ($out) { Log $out } else { Log '  (no output)' }
    if ($err -and $err.Trim()) {
        Log '  ---------------- errors ----------------'
        Log $err
    }
    Log '  -----------------------------------------------'

    if ($code -eq 2 -or $all -match 'could not be compiled') {
        Bad 'The lighting engine failed to compile.'
        $m = ''
        if ($all -match '(?m)^(.*error CS\d+.*)$') { $m = $Matches[1] }
        elseif ($all -match "(?m)^(.*contains a definition.*)$") { $m = $Matches[1] }
        if ($m) { Info $m.Trim() }
        Need 'The engine is damaged or out of date. Run Setup.bat again; if it repeats, send this report.'
        Write-Host ''
        Write-Host $all -ForegroundColor Red
    } elseif ($all -match 'No LampArray HID interface found') {
        Bad 'Cannot see the keyboard lighting interface.'
        Need 'Another program is holding the keyboard. Close it and run Setup.bat again.'
    } elseif ($all -match 'Cannot open device') {
        Bad 'Found the keyboard but could not open it.'
        Need 'Needs Administrator, or another app is holding the device.'
    } elseif ($all -match 'Solid colour applied' -or $all -match 'zones,') {
        Ok 'The engine talked to the keyboard successfully.'
        Write-Host ''
        Write-Host '   >>> Did the keyboard flash RED just now? <<<' -ForegroundColor Yellow
        Log '   >>> Did the keyboard flash RED just now? <<<'
    } else {
        Warn 'The engine gave no recognisable result.'
        Need 'Engine produced no usable output - send this report.'
        if ($all.Trim()) { Write-Host $all -ForegroundColor DarkGray }
    }
}

# --------------------------------------------------------------- launch
if (-not $TestOnly -and $script:Problems.Count -eq 0) {
    Step '11. Starting it'
    try {
        if (Test-Path $ExePath) { Start-Process -FilePath $ExePath -WorkingDirectory $Here }
        else {
            Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Here -ArgumentList @(
                '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"{0}"' -f $TrayPs))
        }
        Ok 'Running - look for the keyboard icon in your system tray.'
    } catch {
        Warn ('Could not start it: ' + $_.Exception.Message)
    }
}

# --------------------------------------------------------------- summary
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

if ($script:Problems.Count -eq 0) {
    Line '   Everything is working.' 'Green'
    Line ''
    Line '   The tray icon (bottom-right, may be under the ^ arrow):'
    Line '     double-click   open the control panel'
    Line '     right-click    menu'
    Line ''
    Line '   To pin it: Start menu, right-click "Keyboard Lighting",'
    Line '   then Pin to Start or Pin to taskbar.'
} else {
    Line '   Fix these, in order:' 'Yellow'
    Line ''
    $i = 1
    foreach ($x in $script:Problems) { Line ("    {0}. {1}" -f $i, $x) 'White'; $i++ }
}

# --------------------------------------------------------------- report
# Only bother the user with a report file when something is actually wrong.
if ($script:Problems.Count -gt 0) {
    $text = ($script:Report -join "`r`n")
    $desk = [Environment]::GetFolderPath('Desktop')
    if (-not $desk -or -not (Test-Path $desk)) { $desk = $Here }
    $rp = Join-Path $desk 'Keyboard-Lighting-Report.txt'

    $saved = $false; $copied = $false
    try { Set-Content -Path $rp -Value $text -Encoding UTF8; $saved = $true } catch { }
    try { Set-Clipboard -Value $text; $copied = $true }
    catch { try { $text | clip.exe; $copied = $true } catch { } }

    Write-Host ''
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor DarkGray
    if ($copied) {
        Write-Host '   A full report is COPIED TO YOUR CLIPBOARD.' -ForegroundColor Green
        Write-Host '   Click the chat and press Ctrl+V to send it.' -ForegroundColor Green
    }
    if ($saved) {
        Write-Host ''
        Write-Host '   Also saved to your Desktop as Keyboard-Lighting-Report.txt' -ForegroundColor Gray
        try { Start-Process notepad.exe $rp } catch { }
    }
}

Write-Host ''
Read-Host '  Press Enter to close'
