#requires -Version 5.1
<#
  LIGHTING PANEL  (legacy)

  The control panel is now built into the main application, so this file
  just starts that instead. It is kept so older shortcuts keep working.
#>

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $Here 'KeyboardLighting.exe'
$tray = Join-Path $Here 'Tray.ps1'

if (Test-Path $exe) {
    Start-Process -FilePath $exe -WorkingDirectory $Here
    return
}

if (Test-Path $tray) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = 'powershell.exe'
    $psi.Arguments       = ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $tray)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.WorkingDirectory = $Here
    [void][System.Diagnostics.Process]::Start($psi)
    return
}

Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.MessageBox]::Show(
    "Keyboard Lighting is not installed in this folder.`n`nRun Install.bat to set it up.",
    'Keyboard Lighting','OK','Warning') | Out-Null
