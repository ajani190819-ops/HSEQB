#requires -Version 5.1
<#
  INSTALL-AUTOSTART
  Makes your keyboard lighting start by itself every time you log in.

  It copies the lighting script to a permanent folder, then creates a
  Windows scheduled task that launches it hidden at logon.

  USAGE  (run in Windows PowerShell as Administrator)

    .\Install-Autostart.ps1 -Effect rainbow
    .\Install-Autostart.ps1 -Effect wave -Color "#00B4FF" -Brightness 0.7
    .\Install-Autostart.ps1 -Effect comet -Speed 1.5

    .\Install-Autostart.ps1 -Uninstall      # remove it completely
    .\Install-Autostart.ps1 -Status         # check whether it is installed

  To change the effect later, just run this again with a different -Effect.
#>

[CmdletBinding()]
param(
    [ValidateSet('wave','rainbow','breathe','comet','pulse','scanner','fire','static')]
    [string]$Effect = 'rainbow',

    [string]$Color = '#00B4FF',
    [string]$Color2 = '#FF0066',

    [ValidateRange(0.05, 20.0)]
    [double]$Speed = 1.0,

    [ValidateRange(0.0, 1.0)]
    [double]$Brightness = 1.0,

    [ValidateRange(5, 60)]
    [int]$Fps = 30,

    [switch]$Uninstall,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

$TaskName  = 'KeyboardLighting'
$InstallTo = Join-Path $env:LOCALAPPDATA 'KeyboardLighting'
$Target    = Join-Path $InstallTo 'Aura-Background.ps1'

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " KEYBOARD LIGHTING  -  autostart installer" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------- STATUS
if ($Status) {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        Write-Host "  INSTALLED." -ForegroundColor Green
        Write-Host ("  Task state : {0}" -f $t.State)
        $act = $t.Actions[0].Arguments
        Write-Host ("  Runs       : {0}" -f $act) -ForegroundColor DarkGray
        Write-Host ("  Script at  : {0}" -f $Target) -ForegroundColor DarkGray
        $p = Get-Process powershell -ErrorAction SilentlyContinue |
             Where-Object { $_.MainWindowTitle -eq '' }
        Write-Host ("  Background PowerShell processes running: {0}" -f @($p).Count) -ForegroundColor DarkGray
    } else {
        Write-Host "  NOT INSTALLED." -ForegroundColor Yellow
    }
    Write-Host ""
    return
}

if (-not (Test-Admin)) {
    Write-Host "  This needs Administrator." -ForegroundColor Red
    Write-Host "  Close this window. Press Start, type powershell," -ForegroundColor Red
    Write-Host "  right-click Windows PowerShell, choose Run as administrator," -ForegroundColor Red
    Write-Host "  then run this again." -ForegroundColor Red
    Write-Host ""
    return
}

# ---------------------------------------------------------------- UNINSTALL
if ($Uninstall) {
    Write-Host "Removing..." -ForegroundColor Yellow

    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($t) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "  Scheduled task removed." -ForegroundColor Green
    } else {
        Write-Host "  No scheduled task found." -ForegroundColor DarkGray
    }

    Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
            if ($cl -and $cl -like '*Aura-Background*') {
                Stop-Process -Id $_.Id -Force
                Write-Host ("  Stopped running instance (PID {0})." -f $_.Id) -ForegroundColor Green
            }
        } catch { }
    }

    if (Test-Path $Target) {
        try {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Target -Effect off -Quiet
            Write-Host "  Lighting handed back to the keyboard firmware." -ForegroundColor Green
        } catch { }
    }

    if (Test-Path $InstallTo) {
        Remove-Item $InstallTo -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  Installed files deleted." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  Done. Reboot to be sure the firmware default returns." -ForegroundColor Cyan
    Write-Host ""
    return
}

# ---------------------------------------------------------------- INSTALL
$source = Join-Path $PSScriptRoot 'Aura-Background.ps1'
if (-not (Test-Path $source)) {
    Write-Host "  Cannot find Aura-Background.ps1 next to this installer." -ForegroundColor Red
    Write-Host ("  Looked in: {0}" -f $PSScriptRoot) -ForegroundColor Red
    Write-Host "  Both files must be in the same folder." -ForegroundColor Red
    Write-Host ""
    return
}

Write-Host ("[1/3] Copying to {0}" -f $InstallTo) -ForegroundColor Yellow
if (-not (Test-Path $InstallTo)) { New-Item -ItemType Directory -Path $InstallTo -Force | Out-Null }
Copy-Item $source $Target -Force
Unblock-File $Target -ErrorAction SilentlyContinue
Write-Host "  Copied." -ForegroundColor Green

Write-Host "[2/3] Stopping any instance that is already running..." -ForegroundColor Yellow
$stopped = 0
Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine
        if ($cl -and $cl -like '*Aura-Background*') { Stop-Process -Id $_.Id -Force; $stopped++ }
    } catch { }
}
Write-Host ("  Stopped {0}." -f $stopped) -ForegroundColor Green

Write-Host "[3/3] Creating the logon task..." -ForegroundColor Yellow

$argList = @(
    '-NoProfile'
    '-ExecutionPolicy Bypass'
    '-WindowStyle Hidden'
    ('-File "{0}"' -f $Target)
    ('-Effect {0}' -f $Effect)
    ('-Color "{0}"' -f $Color)
    ('-Color2 "{0}"' -f $Color2)
    ('-Speed {0}' -f $Speed)
    ('-Brightness {0}' -f $Brightness)
    ('-Fps {0}' -f $Fps)
    '-Quiet'
) -join ' '

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argList
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -StartWhenAvailable

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings `
    -Description 'Animated keyboard backlight (direct HID LampArray control)' | Out-Null

Write-Host "  Task created." -ForegroundColor Green

Write-Host ""
Write-Host "Starting it now..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 3

$t = Get-ScheduledTask -TaskName $TaskName
Write-Host ("  State: {0}" -f $t.State) -ForegroundColor Green

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " DONE" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host ("  Effect     : {0}" -f $Effect)
Write-Host ("  Brightness : {0}" -f $Brightness)
Write-Host ("  Speed      : {0}" -f $Speed)
Write-Host ""
Write-Host "  Your keyboard should be animating now, and it will" -ForegroundColor Green
Write-Host "  start by itself every time you log in." -ForegroundColor Green
Write-Host ""
Write-Host "  Change effect : re-run this with a different -Effect" -ForegroundColor DarkGray
Write-Host "  Remove it     : .\Install-Autostart.ps1 -Uninstall" -ForegroundColor DarkGray
Write-Host "  Check it      : .\Install-Autostart.ps1 -Status" -ForegroundColor DarkGray
Write-Host ""
