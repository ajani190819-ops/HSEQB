# ============================================================================
#  Zones.ps1 - find out which physical light is which, and fix the map
#
#  Run this when the lighting is going to the wrong places: a pattern starts
#  in the wrong spot, the light bar runs the wrong way round, or a key block
#  is grouped with the light bar instead of the keyboard.
#
#  It does three things:
#
#    Identify   lights each zone one at a time and tells you which number it
#               is, so you can write down what is actually where.
#    Map        shows the map the engine is using right now, as a picture.
#    Correct    lets you change the map and save it. The engine picks the
#               change up on its next start; nothing is overwritten upstream.
#
#  Nothing here writes to the keyboard permanently. Close it and the normal
#  lighting comes straight back.
# ============================================================================

param(
    # Skip the menu and run one action directly.
    [ValidateSet('', 'identify', 'map', 'correct', 'reset', 'chase', 'ring', 'shape')]
    [string]$Do = '',
    # Seconds each zone stays lit during Identify.
    [double]$Hold = 1.5
)

$ErrorActionPreference = 'Stop'
$Here     = Split-Path -Parent $MyInvocation.MyCommand.Path
$Engine   = Join-Path $Here 'Aura-Background.ps1'
$StateDir = Join-Path $env:LOCALAPPDATA 'KeyboardLighting'
$MapFile  = Join-Path $StateDir 'zonemap.json'
$FrameF   = Join-Path $StateDir 'frame.txt'
$LayoutF  = Join-Path $StateDir 'layout.txt'

function Line { param([string]$c='DarkGray') Write-Host ('  ' + ('-' * 64)) -ForegroundColor $c }
function Head {
    param([string]$t)
    Write-Host ''
    Write-Host "  $t" -ForegroundColor White
    Line
}
function Info { param([string]$m) Write-Host "  $m" -ForegroundColor Gray }
function Good { param([string]$m) Write-Host "  $m" -ForegroundColor Green }
function Warn { param([string]$m) Write-Host "  $m" -ForegroundColor Yellow }
function Bad  { param([string]$m) Write-Host "  $m" -ForegroundColor Red }

function Need-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ---------------------------------------------------------------- read state
function Read-Layout {
    # What the engine currently thinks the grouping is.
    $out = @{ Kbd = @(); Bar = @(); KbdPos = @(); BarPos = @(); BarRing = $false }
    if (-not (Test-Path $LayoutF)) { return $out }
    foreach ($ln in (Get-Content $LayoutF -ErrorAction SilentlyContinue)) {
        $t = "$ln".Trim()
        if     ($t -like 'kbdring=*') { }
        elseif ($t -like 'barring=*') { $out.BarRing = ($t.Substring(8).Trim() -eq '1') }
        elseif ($t -like 'kbdpos=*')  { $out.KbdPos = @($t.Substring(7) -split ',' | Where-Object { $_ } | ForEach-Object { [double]$_ }) }
        elseif ($t -like 'barpos=*')  { $out.BarPos = @($t.Substring(7) -split ',' | Where-Object { $_ } | ForEach-Object { [double]$_ }) }
        elseif ($t -like 'kbd=*')     { $out.Kbd    = @($t.Substring(4) -split ',' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
        elseif ($t -like 'bar=*')     { $out.Bar    = @($t.Substring(4) -split ',' | Where-Object { $_ } | ForEach-Object { [int]$_ }) }
    }
    return $out
}

function Read-Frame {
    # The colours the engine last sent, so we can show what is lit right now.
    if (-not (Test-Path $FrameF)) { return $null }
    try {
        $txt = [System.IO.File]::ReadAllText($FrameF)
        $semi = $txt.IndexOf(';')
        if ($semi -lt 1) { return $null }
        $n = [int]$txt.Substring(0, $semi)
        $body = $txt.Substring($semi + 1)
        if ($body.Length -lt ($n * 6)) { return $null }
        $out = @()
        for ($k = 0; $k -lt $n; $k++) {
            $o = $k * 6
            $out += ,@([Convert]::ToInt32($body.Substring($o,2),16),
                       [Convert]::ToInt32($body.Substring($o+2,2),16),
                       [Convert]::ToInt32($body.Substring($o+4,2),16))
        }
        return $out
    } catch { return $null }
}

function Read-Override {
    if (-not (Test-Path $MapFile)) { return $null }
    try { return (Get-Content $MapFile -Raw | ConvertFrom-Json) } catch { return $null }
}

# ---------------------------------------------------------------- engine call
function Invoke-Engine {
    # Run the engine once, briefly, with a fixed set of zones lit.
    param([string]$ZoneList, [string]$Colour = '#FFFFFF', [double]$Seconds = 1.5)
    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File', $Engine,
        '-Effect','zonetest','-ZoneTest', $ZoneList, '-Color', $Colour,
        '-HoldSeconds', ("{0}" -f $Seconds), '-Quiet'
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Process -Id $PID).Path
    $psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $so = $p.StandardOutput.ReadToEnd()
    $se = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Out = $so; Err = $se }
}

function Stop-Running {
    # The engine holds the device exclusively, so it has to stand down first.
    $found = $false
    foreach ($p in (Get-Process powershell,pwsh -ErrorAction SilentlyContinue)) {
        try {
            $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).CommandLine
            if ($cl -and $cl -match 'Aura-Background') { $found = $true }
        } catch { }
    }
    return $found
}

# ---------------------------------------------------------------- drawing
function Show-Map {
    param($lay, $ov)
    Head 'The map the engine is using'

    if ($lay.Kbd.Count -eq 0 -and $lay.Bar.Count -eq 0) {
        Warn 'No map yet. Start the lighting once, then come back.'
        return
    }

    Info ("Keyboard : {0} zones -> {1}" -f $lay.Kbd.Count, ($lay.Kbd -join ', '))
    Info ("Light bar: {0} zones -> {1}" -f $lay.Bar.Count, ($lay.Bar -join ', '))
    if ($lay.BarRing) { Info 'Light bar is treated as a ring (it wraps around).' }
    else              { Info 'Light bar is treated as a straight line.' }

    if ($ov) { Warn 'A correction of your own is in force (see Reset to undo).' }

    # Picture: position of every zone, left to right, as the engine sees it.
    Write-Host ''
    Info 'Where the engine thinks each zone sits, left to right:'
    foreach ($grp in @(@{N='Keyboard';I=$lay.Kbd;P=$lay.KbdPos},
                       @{N='Light bar';I=$lay.Bar;P=$lay.BarPos})) {
        if ($grp.I.Count -eq 0) { continue }
        $w = 56
        $row = New-Object char[] $w
        for ($k = 0; $k -lt $w; $k++) { $row[$k] = '.' }
        for ($k = 0; $k -lt $grp.I.Count; $k++) {
            $p = if ($k -lt $grp.P.Count) { $grp.P[$k] } else { if ($grp.I.Count -gt 1) { $k / ($grp.I.Count - 1) } else { 0 } }
            $x = [int][Math]::Round($p * ($w - 1))
            if ($x -lt 0) { $x = 0 }; if ($x -ge $w) { $x = $w - 1 }
            $ch = "$($grp.I[$k])"
            $row[$x] = $ch[$ch.Length - 1]
        }
        Write-Host ("  {0,-10} [{1}]" -f $grp.N, (-join $row)) -ForegroundColor Cyan
    }
    Write-Host ''
    Info 'Each character is the last digit of that zone number.'
    Info 'Dots are empty space - real gaps between the lights.'

    $fr = Read-Frame
    if ($fr) {
        Write-Host ''
        Info 'Colour being sent to each zone right now:'
        for ($i = 0; $i -lt $fr.Count; $i++) {
            $c = $fr[$i]
            $tag = if ($lay.Bar -contains $i) { 'bar' } elseif ($lay.Kbd -contains $i) { 'kbd' } else { '   ' }
            $lit = if (($c[0] + $c[1] + $c[2]) -gt 24) { 'ON ' } else { 'off' }
            Write-Host ("    zone {0,2}  {1}  {2}  #{3:X2}{4:X2}{5:X2}" -f $i, $tag, $lit, $c[0], $c[1], $c[2])
        }
    }
}

function Do-Identify {
    param($lay, [double]$hold)
    Head 'Identify - light one zone at a time'

    if (Stop-Running) {
        Warn 'The lighting is running and is holding the keyboard.'
        Warn 'Right-click the tray icon and choose Exit, then run this again.'
        return
    }
    if (-not (Need-Admin)) {
        Bad 'This needs to run as administrator to talk to the keyboard.'
        return
    }

    $count = 16
    if ($lay.Kbd.Count + $lay.Bar.Count -gt 0) { $count = $lay.Kbd.Count + $lay.Bar.Count }

    Info "Each zone lights WHITE on its own for $hold seconds."
    Info 'Write down where each number actually is on the laptop.'
    Info 'Press Ctrl+C at any time to stop.'
    Write-Host ''
    Start-Sleep -Milliseconds 700

    for ($z = 0; $z -lt $count; $z++) {
        $where = if ($lay.Bar -contains $z) { 'engine says: LIGHT BAR' }
                 elseif ($lay.Kbd -contains $z) { 'engine says: KEYBOARD' }
                 else { 'engine says: unknown' }
        Write-Host ("  zone {0,2}  <- lit now    {1}" -f $z, $where) -ForegroundColor Cyan
        $r = Invoke-Engine -ZoneList "$z" -Colour '#FFFFFF' -Seconds $hold
        if ($r.Code -ne 0) {
            Bad "  Could not drive the keyboard (exit $($r.Code))."
            # Show what the engine actually said - the first line of an
            # error is rarely the useful one, so print the lot.
            foreach ($stream in @($r.Err, $r.Out)) {
                if (-not $stream) { continue }
                foreach ($l in ($stream -split "`r?`n")) {
                    if ($l.Trim()) { Bad ("    " + $l.Trim()) }
                }
            }
            Write-Host ''
            Info 'If it says the engine is out of date, run Setup.bat first.'
            return
        }
    }
    Write-Host ''
    Good 'Done. If any number lit in the wrong place, use Correct.'
}

function Do-Correct {
    param($lay)
    Head 'Correct the map'

    Info 'Type the zone numbers for each group, separated by commas.'
    Info ''
    Info 'Keyboard: left to right.'
    Info 'Light bar: the order a light would travel if it went all the'
    Info 'way round the bar and back to the start. Do not repeat the'
    Info 'first number at the end - it joins up on its own.'
    Info ''
    Info 'Example for a bar that goes up one side and back the other:'
    Info '  4,5,7,9,11,13,15,14,12,10,8,6'
    Info ''
    Info 'Press Enter on its own to keep what is there now.'
    Write-Host ''

    Info ("Keyboard now : " + ($lay.Kbd -join ', '))
    $k = Read-Host '  Keyboard zones'
    Info ("Light bar now: " + ($lay.Bar -join ', '))
    $b = Read-Host '  Light bar zones'

    $kbd = if ($k.Trim()) { @($k -split ',' | Where-Object { $_.Trim() } | ForEach-Object { [int]$_.Trim() }) } else { @($lay.Kbd) }
    $bar = if ($b.Trim()) { @($b -split ',' | Where-Object { $_.Trim() } | ForEach-Object { [int]$_.Trim() }) } else { @($lay.Bar) }

    # Listing the first zone again at the end is a natural way to show a
    # loop, but it would double that lamp. Drop it and say so.
    if ($bar.Count -gt 1 -and $bar[0] -eq $bar[-1]) {
        Info ("Removed the repeated {0} at the end - the ring closes by itself." -f $bar[0])
        $bar = @($bar[0..($bar.Count - 2)])
    }

    # Sanity checks, so a typo cannot leave zones dark or doubled.
    $all = @($kbd) + @($bar)
    $dupes = $all | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name }
    if ($dupes) {
        Bad ('Zone(s) listed more than once: ' + ($dupes -join ', ') + '. Nothing saved.')
        return
    }
    $total = $lay.Kbd.Count + $lay.Bar.Count
    if ($total -gt 0) {
        $missing = @(0..($total - 1) | Where-Object { $all -notcontains $_ })
        if ($missing.Count -gt 0) {
            Warn ('Not listed, so they will stay dark: ' + ($missing -join ', '))
            $ok = Read-Host '  Continue anyway? (y/N)'
            if ($ok -ne 'y') { Info 'Nothing saved.'; return }
        }
    }

    $ring = Read-Host '  Does the light bar wrap all the way around? (y/n, Enter = keep)'
    $isRing = $lay.BarRing
    if ($ring -eq 'y') { $isRing = $true } elseif ($ring -eq 'n') { $isRing = $false }

    $obj = [ordered]@{
        Kbd     = @($kbd)
        Bar     = @($bar)
        BarRing = [bool]$isRing
        Note    = 'Written by Zones.ps1. Delete this file to go back to automatic detection.'
    }
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force -Path $StateDir | Out-Null }
    $obj | ConvertTo-Json -Depth 5 | Set-Content -Path $MapFile -Encoding UTF8
    Write-Host ''
    Good "Saved to $MapFile"
    Info 'Restart the lighting for it to take effect:'
    Info '  right-click the tray icon, Exit, then open it again.'
}

function Invoke-Chase {
    param([string]$which = 'bar', [double]$hold = 0.45)
    $args = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File', $Engine,
        '-ChaseTest','-ChaseWhich', $which,
        '-Color','#FFFFFF','-HoldSeconds', ("{0}" -f $hold)
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Process -Id $PID).Path
    $psi.Arguments = ($args | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    while (-not $p.HasExited) {
        $ln = $p.StandardOutput.ReadLine()
        if ($null -eq $ln) { break }
        if ($ln.Trim()) { Write-Host $ln -ForegroundColor Gray }
    }
    $p.WaitForExit()
    $rest = $p.StandardOutput.ReadToEnd()
    foreach ($l in ($rest -split "`r?`n")) { if ($l.Trim()) { Write-Host $l -ForegroundColor Gray } }
    $err = $p.StandardError.ReadToEnd()
    if ($p.ExitCode -ne 0) {
        Bad ("  Engine exited with $($p.ExitCode).")
        foreach ($l in ($err -split "`r?`n")) { if ($l.Trim()) { Bad ("    " + $l.Trim()) } }
    }
    return ($p.ExitCode -eq 0)
}

function Do-Chase {
    Head 'Watch the path - does it trace the circle?'
    if (Stop-Running) {
        Warn 'The lighting is running and is holding the keyboard.'
        Warn 'Right-click the tray icon, choose Exit, then run this again.'
        return
    }
    if (-not (Need-Admin)) { Bad 'This needs to run as administrator.'; return }
    Info 'One light walks the light bar in the order the app believes.'
    Info 'Watch it. If it jumps about instead of going round smoothly,'
    Info 'the order is wrong - use option 6 to fix it by watching.'
    Write-Host ''
    [void](Invoke-Chase 'bar' 0.45)
}

function Do-BuildRing {
    Head 'Build the circle by watching'
    if (Stop-Running) {
        Warn 'The lighting is running and is holding the keyboard.'
        Warn 'Right-click the tray icon, choose Exit, then run this again.'
        return
    }
    if (-not (Need-Admin)) { Bad 'This needs to run as administrator.'; return }

    $lay = Read-Layout
    $pool = @($lay.Bar)
    if ($pool.Count -eq 0) { Warn 'No light bar zones known yet. Start the lighting once first.'; return }

    Info 'Each zone will light on its own. After each one, say whether it'
    Info 'is the NEXT light going round the circle from the last one.'
    Info ''
    Info 'Start anywhere. Go one direction and keep going the same way.'
    Info 'Type y for yes, n for no, or q to give up. Enter on its own = n.'
    Write-Host ''

    $ring = @()
    $left = @($pool)
    while ($left.Count -gt 0) {
        $progress = $false
        foreach ($z in @($left)) {
            if ($ring.Count -eq 0) {
                Write-Host ("  Lighting zone {0} - is this a good place to START? " -f $z) -ForegroundColor Cyan -NoNewline
            } else {
                Write-Host ("  Lighting zone {0} - is it next after {1}? " -f $z, $ring[-1]) -ForegroundColor Cyan -NoNewline
            }
            $r = Invoke-Engine -ZoneList "$z" -Colour '#FFFFFF' -Seconds 1.2
            if ($r.Code -ne 0) {
                Write-Host ''
                Bad "  Could not drive the keyboard (exit $($r.Code))."
                foreach ($l in (($r.Err + "`n" + $r.Out) -split "`r?`n")) { if ($l.Trim()) { Bad ("    " + $l.Trim()) } }
                return
            }
            $a = Read-Host
            if ($a -eq 'q') { Info 'Stopped. Nothing saved.'; return }
            if ($a -eq 'y') {
                $ring += $z
                $left = @($left | Where-Object { $_ -ne $z })
                $progress = $true
                Good ("    added {0}   ring so far: {1}" -f $z, ($ring -join ','))
                break
            }
        }
        if (-not $progress) {
            Write-Host ''
            Warn 'None of the remaining zones was accepted.'
            Info ("Remaining: " + ($left -join ', '))
            $f = Read-Host '  Add them in this order anyway? (y/N)'
            if ($f -eq 'y') { $ring += $left; $left = @() } else { break }
        }
    }

    if ($ring.Count -lt 2) { Warn 'Not enough zones chosen. Nothing saved.'; return }

    Write-Host ''
    Good ("Circle: " + ($ring -join ','))
    Info 'Saving this as the travel path for the light bar.'
    $obj = [ordered]@{
        Kbd     = @($lay.Kbd)
        Bar     = @($ring)
        BarRing = $true
        Note    = 'Written by Zones.ps1. Delete this file to go back to automatic detection.'
    }
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force -Path $StateDir | Out-Null }
    $obj | ConvertTo-Json -Depth 5 | Set-Content -Path $MapFile -Encoding UTF8
    Good "Saved to $MapFile"
    Write-Host ''
    Info 'Restart the lighting (tray icon, Exit, then open it again),'
    Info 'then come back and use option 5 to watch the path.'
}

function Get-RingShape {
    # Common ways a two-sided light bar is wired. The firmware's own
    # coordinates are often wrong, so offering the handful of real-world
    # shapes is faster and more reliable than asking about every lamp.
    param($zones)
    $z = @($zones | Sort-Object)
    if ($z.Count -lt 2) { return @{} }
    $lo = $z[0]
    $odd  = @($z | Where-Object { ($_ - $lo) % 2 -eq 1 })
    $even = @($z | Where-Object { ($_ - $lo) % 2 -eq 0 })
    $evenBack = @($even | Sort-Object -Descending)
    $oddBack  = @($odd  | Sort-Object -Descending)
    $half = [int][Math]::Floor($z.Count / 2)
    return [ordered]@{
        'Up one side, back the other (most common)' = @($odd + $evenBack)
        'The other way round'                       = @($even + $oddBack)
        'Straight round in number order'            = @($z)
        'First half out, second half back'          = @($z[0..($half-1)] + @($z[$half..($z.Count-1)] | Sort-Object -Descending))
    }
}

function Do-QuickRing {
    Head 'Pick the shape of your light bar'

    $lay = Read-Layout
    $pool = @($lay.Bar)
    if ($pool.Count -eq 0) { Warn 'No light bar zones known yet. Start the lighting once first.'; return }

    $shapes = Get-RingShape $pool
    Info 'Most light bars are wired one of these ways. Pick the one that'
    Info 'matches, save it, and watch the result - no need to answer for'
    Info 'every single light.'
    Write-Host ''
    $i = 1
    $keys = @()
    foreach ($k in $shapes.Keys) {
        Write-Host ("   {0}  {1}" -f $i, $k) -ForegroundColor Gray
        Write-Host ("      {0}" -f (($shapes[$k]) -join ', ')) -ForegroundColor DarkGray
        $keys += $k
        $i++
    }
    Write-Host ("   {0}  Type the order myself" -f $i) -ForegroundColor Gray
    Write-Host ("   {0}  Cancel" -f ($i+1)) -ForegroundColor Gray
    Write-Host ''
    $c = Read-Host ("  Choose 1-{0}" -f ($i+1))
    $n = 0
    if (-not [int]::TryParse($c, [ref]$n)) { Info 'Cancelled.'; return }

    $ring = $null
    if ($n -ge 1 -and $n -le $keys.Count) {
        $ring = @($shapes[$keys[$n-1]])
    } elseif ($n -eq $i) {
        $t = Read-Host '  Zone numbers in travel order, separated by commas'
        if (-not $t.Trim()) { Info 'Cancelled.'; return }
        $ring = @($t -split ',' | Where-Object { $_.Trim() } | ForEach-Object { [int]$_.Trim() })
    } else {
        Info 'Cancelled.'; return
    }

    if ($ring.Count -gt 1 -and $ring[0] -eq $ring[-1]) {
        $ring = @($ring[0..($ring.Count - 2)])
    }
    $dupe = @($ring | Group-Object | Where-Object { $_.Count -gt 1 })
    if ($dupe.Count -gt 0) {
        Bad ('Zone(s) listed twice: ' + (($dupe | ForEach-Object { $_.Name }) -join ', ') + '. Nothing saved.')
        return
    }
    $missing = @($pool | Where-Object { $ring -notcontains $_ })
    if ($missing.Count -gt 0) {
        Warn ('Not listed, so they will stay dark: ' + ($missing -join ', '))
        $ok = Read-Host '  Continue anyway? (y/N)'
        if ($ok -ne 'y') { Info 'Nothing saved.'; return }
    }

    $obj = [ordered]@{
        Kbd     = @($lay.Kbd)
        Bar     = @($ring)
        BarRing = $true
        Note    = 'Written by Zones.ps1. Delete this file to go back to automatic detection.'
    }
    if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Force -Path $StateDir | Out-Null }
    $obj | ConvertTo-Json -Depth 5 | Set-Content -Path $MapFile -Encoding UTF8
    Write-Host ''
    Good ("Saved: " + ($ring -join ', '))
    Write-Host ''
    Info 'Restart the lighting (tray icon, Exit, then open it again).'
    Info 'Then use option 5 to watch it and check it goes round smoothly.'
}

function Do-Reset {
    Head 'Reset to automatic detection'
    if (Test-Path $MapFile) {
        Remove-Item $MapFile -Force
        Good 'Your correction has been removed.'
        Info 'Restart the lighting (tray icon, Exit, then open it again).'
    } else {
        Info 'There was no correction saved - already automatic.'
    }
}

# ---------------------------------------------------------------- main
Write-Host ''
Write-Host '  ZONE CHECKER' -ForegroundColor White
Write-Host '  Work out which light is which, and correct it if it is wrong.' -ForegroundColor DarkGray

$lay = Read-Layout
$ov  = Read-Override

if ($Do) {
    switch ($Do) {
        'identify' { Do-Identify $lay $Hold }
        'map'      { Show-Map $lay $ov }
        'correct'  { Do-Correct $lay }
        'reset'    { Do-Reset }
        'chase'    { Do-Chase }
        'ring'     { Do-BuildRing }
        'shape'    { Do-QuickRing }
    }
    Write-Host ''
    return
}

while ($true) {
    Head 'What do you want to do?'
    Write-Host '   1  Show the map the engine is using' -ForegroundColor Gray
    Write-Host '   2  Identify - light each zone one at a time' -ForegroundColor Gray
    Write-Host '   3  Correct the map by hand' -ForegroundColor Gray
    Write-Host '   4  Reset back to automatic' -ForegroundColor Gray
    Write-Host '   5  Watch the path - does it trace the circle?' -ForegroundColor Gray
    Write-Host '   6  Build the circle by watching (slow but certain)' -ForegroundColor Gray
    Write-Host '   7  Pick the shape of the bar (fast - start here)' -ForegroundColor Gray
    Write-Host '   8  Quit' -ForegroundColor Gray
    Write-Host ''
    $c = Read-Host '  Choose 1-8'
    switch ($c) {
        '1' { $lay = Read-Layout; $ov = Read-Override; Show-Map $lay $ov }
        '2' { Do-Identify $lay $Hold }
        '3' { Do-Correct $lay; $lay = Read-Layout }
        '4' { Do-Reset }
        '5' { Do-Chase }
        '6' { Do-BuildRing; $lay = Read-Layout }
        '7' { Do-QuickRing; $lay = Read-Layout }
        '8' { Write-Host ''; return }
        default { Warn 'Type a number from 1 to 8.' }
    }
}
