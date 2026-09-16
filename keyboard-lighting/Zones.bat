@echo off
REM Zone checker - work out which light is which, and correct it.
setlocal
set BASE=https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo   Asking for administrator access...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo   Getting the latest zone checker...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol='Tls12'; try{ Invoke-WebRequest '%BASE%/Zones.ps1' -OutFile (Join-Path '%~dp0' 'Zones.ps1') -UseBasicParsing -TimeoutSec 25; Unblock-File (Join-Path '%~dp0' 'Zones.ps1') } catch { Write-Host ('   ' + $_.Exception.Message) -ForegroundColor Yellow }"

if not exist "%~dp0Zones.ps1" (
  echo   Could not download Zones.ps1 and no local copy was found.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Zones.ps1"
pause
