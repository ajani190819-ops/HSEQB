# =====================================================================
#  Keyboard Lighting - installer
#
#  Run this ONCE. It:
#    - downloads every script into this folder
#    - builds KeyboardLighting.exe (using the C# compiler that ships
#      with Windows, so nothing extra is needed)
#    - creates Start menu and Desktop shortcuts you can pin
#    - sets it to start automatically when you log in
#    - launches it
#
#  After this you never touch these files again. The tray icon handles
#  everything, including updating itself.
# =====================================================================

$ErrorActionPreference = 'Continue'

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Base = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting'
$TaskName = 'KeyboardLighting'

function Say($t, $c = 'Gray')  { Write-Host $t -ForegroundColor $c }
function Step($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host '   [OK]   ' -ForegroundColor Green -NoNewline; Write-Host $t }
function Bad($t)  { Write-Host '   [FAIL] ' -ForegroundColor Red   -NoNewline; Write-Host $t }

Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor Cyan
Write-Host '   KEYBOARD LIGHTING - SETUP' -ForegroundColor Cyan
Write-Host '  ===============================================================' -ForegroundColor Cyan

# ---------------------------------------------------------------- admin
$isAdmin = $false
try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    $isAdmin = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }

if (-not $isAdmin) {
    Say ''
    Say '  Asking for Administrator...' 'Yellow'
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath))
    } catch {
        Say '  Permission refused. Setup cannot continue.' 'Red'
        Read-Host '  Press Enter to close'
    }
    return
}

# ---------------------------------------------------------------- download
Step '1. Downloading the latest files'
try { [Net.ServicePointManager]::SecurityProtocol = 'Tls12' } catch { }

$files = @('Aura-Background.ps1','Lighting-Panel.ps1','Tray.ps1','Install.ps1',
           'Check.ps1','Check.bat','Update.ps1','Update.bat',
           'Lighting-Panel.bat','MyEffect.ps1','Find-Lamps.ps1','README.md','app.ico')
$got = 0
foreach ($f in $files) {
    try {
        Invoke-WebRequest "$Base/$f" -OutFile (Join-Path $Here $f) -UseBasicParsing -TimeoutSec 25
        Unblock-File (Join-Path $Here $f) -ErrorAction SilentlyContinue
        $got++
    } catch {
        Write-Host ('          could not get ' + $f) -ForegroundColor DarkGray
    }
}
if ($got -ge 3) { Ok ("$got files downloaded") } else { Bad 'download failed - check your internet connection' }

# ---------------------------------------------------------------- build exe
Step '2. Building KeyboardLighting.exe'

# A running copy holds a lock on the exe, so csc would fail with
# "cannot write to output file". Close it first.
try {
    Get-CimInstance Win32_Process -Filter "Name='KeyboardLighting.exe'" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Tray.ps1*' -or $_.CommandLine -like '*Aura-Background*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 600
} catch { }

$exePath = Join-Path $Here 'KeyboardLighting.exe'
$csc = $null
foreach ($cand in @(
    "$env:WinDir\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "$env:WinDir\Microsoft.NET\Framework\v4.0.30319\csc.exe")) {
    if (Test-Path $cand) { $csc = $cand; break }
}

if (-not $csc) {
    Bad 'no C# compiler found - will use a shortcut instead of an exe'
} else {
    $src = Join-Path $env:TEMP 'kbl_launcher.cs'
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
                "\n\nRe-run Install.ps1 to repair.",
                "Keyboard Lighting");
            return 1;
        }
        string extra = "";
        for (int i = 0; i < args.Length; i++) extra += " " + args[i];
        ProcessStartInfo psi = new ProcessStartInfo();
        psi.FileName = "powershell.exe";
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + tray + "\"" + extra;
        psi.WorkingDirectory = dir;
        // UseShellExecute=false + CreateNoWindow=true is what stops a console
        // window from ever being created. WindowStyle alone only hides one
        // that has already flashed up on screen.
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

    # /target:winexe = no console window ever appears.
    # NOTE: do not call this $args - that is a PowerShell automatic
    # variable and assigning to it behaves unpredictably.
    $cscArgs = @('/nologo','/target:winexe','/optimize+',
                 '/reference:System.Windows.Forms.dll','/reference:System.dll')
    # Give the exe a real icon so the Start menu and taskbar look right.
    $icoPath = Join-Path $Here 'app.ico'
    if (Test-Path $icoPath) { $cscArgs += ('/win32icon:"{0}"' -f $icoPath) }
    $cscArgs += ('/out:"{0}"' -f $exePath)
    $cscArgs += ('"{0}"' -f $src)
    $proc = Start-Process -FilePath $csc -ArgumentList $cscArgs -NoNewWindow -Wait -PassThru `
         -RedirectStandardOutput (Join-Path $env:TEMP 'kbl_csc_out.txt') `
         -RedirectStandardError  (Join-Path $env:TEMP 'kbl_csc_err.txt')

    $built = (Test-Path $exePath) -and $proc.ExitCode -eq 0
    if ($built) {
        $sz = (Get-Item $exePath).Length
        if ($sz -lt 2048) { $built = $false }
    }
    if ($built) {
        Ok ('KeyboardLighting.exe built ({0} bytes)' -f (Get-Item $exePath).Length)
    } else {
        if (Test-Path $exePath) { Remove-Item $exePath -Force -ErrorAction SilentlyContinue }
        Bad 'could not build the exe'
        $err = ''
        try { $err = Get-Content (Join-Path $env:TEMP 'kbl_csc_err.txt') -Raw } catch { }
        try { $err += Get-Content (Join-Path $env:TEMP 'kbl_csc_out.txt') -Raw } catch { }
        if ($err.Trim()) { Write-Host $err -ForegroundColor DarkGray }
    }
    Remove-Item $src -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- shortcuts
Step '3. Creating shortcuts you can pin'

$target = $exePath
$usePs  = -not (Test-Path $exePath)
$trayPs = Join-Path $Here 'Tray.ps1'

function New-Shortcut($path) {
    try {
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($path)
        if ($usePs) {
            $lnk.TargetPath = 'powershell.exe'
            $lnk.Arguments  = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $trayPs)
        } else {
            $lnk.TargetPath = $target
        }
        $lnk.WorkingDirectory = $Here
        $lnk.Description = 'Keyboard Lighting'
        $ico = Join-Path $Here 'app.ico'
        if (Test-Path $ico) { $lnk.IconLocation = $ico }
        elseif (-not $usePs) { $lnk.IconLocation = $target }
        else { $lnk.IconLocation = "$env:WinDir\System32\shell32.dll,176" }
        $lnk.Save()
        return $true
    } catch { return $false }
}

$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Keyboard Lighting.lnk'
$desktop   = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Keyboard Lighting.lnk'
if (New-Shortcut $startMenu) { Ok 'Start menu shortcut created' } else { Bad 'Start menu shortcut failed' }
if (New-Shortcut $desktop)   { Ok 'Desktop shortcut created' }    else { Bad 'Desktop shortcut failed' }

# ---------------------------------------------------------------- autostart
Step '4. Starting automatically when you log in'
try {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    if (Test-Path $exePath) {
        $act = New-ScheduledTaskAction -Execute $exePath -Argument '-Silent' -WorkingDirectory $Here
    } else {
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' `
               -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Silent' -f $trayPs) `
               -WorkingDirectory $Here
    }
    $trg  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $prin = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
    $set  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
            -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg `
        -Principal $prin -Settings $set -Description 'Keyboard lighting' -Force | Out-Null
    Ok 'will start at log in, with no permission prompt'
} catch {
    Bad ('autostart failed: ' + $_.Exception.Message)
}

# ---------------------------------------------------------------- launch
Step '5. Starting it'
try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*Tray.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} catch { }

if (Test-Path $exePath) { Start-Process -FilePath $exePath -WorkingDirectory $Here }
else {
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Here -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"{0}"' -f $trayPs))
}
Ok 'running - look for the keyboard icon in your system tray'

Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor Green
Write-Host '   DONE' -ForegroundColor Green
Write-Host '  ===============================================================' -ForegroundColor Green
Write-Host ''
Write-Host '   The tray icon (bottom-right, may be under the ^ arrow) does'
Write-Host '   everything from now on:'
Write-Host ''
Write-Host '     double-click       open the control panel'
Write-Host '     right-click        menu: updates, log, turn off, exit'
Write-Host ''
Write-Host '   To pin it: find "Keyboard Lighting" in the Start menu,'
Write-Host '   right-click it, choose Pin to Start or Pin to taskbar.'
Write-Host ''
Write-Host '   It updates itself in the background. You should not need'
Write-Host '   to run this installer again.'
Write-Host ''
Read-Host '  Press Enter to close'
