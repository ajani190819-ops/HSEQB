#requires -Version 5.1
<#
  LIGHTING PANEL
  A simple window for controlling your keyboard lighting.
  No command lines needed.

  Start it with Lighting-Panel.bat, or run this file directly.
#>

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------- paths
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$SelfPath = $MyInvocation.MyCommand.Path
$Engine  = Join-Path $Here 'Aura-Background.ps1'
$script:SkipSave = $false
$script:Suppress = $true   # no auto-apply until the form has finished loading
$CfgDir  = Join-Path $env:LOCALAPPDATA 'KeyboardLighting'
$LiveFile = Join-Path $CfgDir 'live.txt'
$CfgFile = Join-Path $CfgDir 'panel.json'
$TaskName = 'KeyboardLighting'

if (-not (Test-Path $Engine)) {
    [System.Windows.Forms.MessageBox]::Show(
        "Cannot find Aura-Background.ps1.`n`nIt must sit in the same folder as this panel:`n$Here",
        'Missing file','OK','Error') | Out-Null
    return
}
if (-not (Test-Path $CfgDir)) { New-Item -ItemType Directory -Path $CfgDir -Force | Out-Null }

# ---------------------------------------------------------------- state
# The palette is cyclic: the last colour blends back into the first, so do
# NOT repeat the first colour at the end.
$script:Swatches = @('#FF0000','#FF7F00','#FFFF00','#00FF00','#0000FF','#8B00FF')
$script:Running  = $null

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

# Which effects actually use the colour list
$UsesPalette = @('gradient')
$UsesOne     = @('static','wave','comet','scanner','breathe')

# ---------------------------------------------------------------- helpers
function Save-Config {
    $o = [pscustomobject]@{
        Effect     = $cboEffect.SelectedItem
        Swatches   = $script:Swatches
        Speed      = $trkSpeed.Value
        Brightness = $trkBright.Value
        Mirror     = $chkMirror.Checked
        Reverse    = $chkReverse.Checked
        Equalise   = $chkEq.Checked
        Loop       = $chkLoop.Checked
    }
    try { $o | ConvertTo-Json -Depth 4 | Set-Content -Path $CfgFile -Encoding UTF8 } catch { }
}

function Load-Config {
    if (-not (Test-Path $CfgFile)) { return }
    try {
        $o = Get-Content -Raw $CfgFile | ConvertFrom-Json
        if ($o.Swatches)   { $script:Swatches = @($o.Swatches) }
        if ($o.Effect -and $cboEffect.Items.Contains($o.Effect)) { $cboEffect.SelectedItem = $o.Effect }
        if ($o.Speed)      { $trkSpeed.Value  = [Math]::Min(50,[Math]::Max(1,[int]$o.Speed)) }
        if ($o.Brightness) { $trkBright.Value = [Math]::Min(100,[Math]::Max(5,[int]$o.Brightness)) }
        $chkMirror.Checked  = [bool]$o.Mirror
        $chkReverse.Checked = [bool]$o.Reverse
        if ($null -ne $o.Equalise) { $chkEq.Checked = [bool]$o.Equalise }
        if ($null -ne $o.Loop)     { $chkLoop.Checked = [bool]$o.Loop }
    } catch { }
}

function Stop-Lighting {
    Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
            if ($cl -and $cl -like '*Aura-Background*') { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    $script:Running = $null
}

function Get-EngineArgs {
    $key = $cboEffect.SelectedItem
    $eff = $Effects[$key]
    # Force a dot decimal separator regardless of Windows regional settings,
    # otherwise "1,5" reaches the engine and the parameter bind fails.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $spd = ($trkSpeed.Value  / 10.0).ToString('0.##', $inv)
    $brt = ($trkBright.Value / 100.0).ToString('0.##', $inv)

    $a = @(
        '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden'
        '-File', ('"{0}"' -f $Engine)
        '-Effect', $eff
        '-Speed', $spd
        '-Brightness', $brt
        '-Fps','60'
        '-Quiet'
    )
    if ($script:Swatches.Count -gt 0) {
        $a += '-Colors'; $a += ('"{0}"' -f ($script:Swatches -join ','))
        $a += '-Color';  $a += ('"{0}"' -f $script:Swatches[0])
        if ($script:Swatches.Count -gt 1) { $a += '-Color2'; $a += ('"{0}"' -f $script:Swatches[1]) }
    }
    if ($chkMirror.Checked)  { $a += '-Mirror' }
    if ($chkReverse.Checked) { $a += '-Reverse' }
    $eqv = if ($chkEq.Checked) { 'on' } else { 'off' }
    $a += '-Equalise'; $a += $eqv
    $lay = if ($chkLoop.Checked) { 'loop' } else { 'across' }
    $a += '-Layout'; $a += $lay
    return $a
}

# Write the live brightness file. A running engine polls this and applies
# it within ~120ms, so the slider works without restarting anything.
function Set-LiveBrightness([int]$pct) {
    try {
        if (-not (Test-Path $CfgDir)) { New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null }
        $lvl = [int]([Math]::Round($pct * 10))
        Set-Content -Path $LiveFile -Value $lvl -Encoding ASCII -ErrorAction SilentlyContinue
    } catch { }
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Apply-Lighting {
    Stop-Lighting
    Start-Sleep -Milliseconds 250
    try {
        $script:Running = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList (Get-EngineArgs) -WindowStyle Hidden -PassThru

        # The engine exits immediately if it cannot open the keyboard
        # (almost always: not running as Administrator). Give it a moment
        # and check it is actually still alive, rather than claiming
        # "Running" for a process that already died.
        Start-Sleep -Milliseconds 900
        $alive = $false
        try { $alive = -not $script:Running.HasExited } catch { $alive = $false }

        if ($alive) {
            $lblStatus.Text      = '  Running'
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(70,200,120)
        } else {
            $lblStatus.Text      = '  Could not control the keyboard'
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(230,90,90)
            if (-not (Test-IsAdmin)) {
                [System.Windows.Forms.MessageBox]::Show(
                    "The lighting engine could not open the keyboard.`n`nThis panel is not running as Administrator, which is required for direct keyboard access.`n`nClose this window, then right-click Lighting-Panel.bat and choose `"Run as administrator`".",
                    'Administrator required','OK','Warning') | Out-Null
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "The lighting engine started but exited straight away.`n`nMost likely cause: Windows Dynamic Lighting is switched ON and is holding the keyboard.`n`nGo to Settings > Personalization > Dynamic Lighting and turn it OFF, then press Apply again.",
                    'Could not control the keyboard','OK','Warning') | Out-Null
            }
        }
    } catch {
        $lblStatus.Text      = '  Failed to start'
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(230,90,90)
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error','OK','Error') | Out-Null
    }
    Save-Config
}

function Set-AllOff {
    Stop-Lighting
    Start-Sleep -Milliseconds 250
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -Wait -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $Engine),'-Effect','off','-Quiet'
    ) | Out-Null
    $lblStatus.Text      = '  Stopped'
    $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(150,150,160)
}

# ---------------------------------------------------------------- window
$bg    = [System.Drawing.Color]::FromArgb(24,26,34)
$card  = [System.Drawing.Color]::FromArgb(34,37,48)
$fg    = [System.Drawing.Color]::FromArgb(232,234,240)
$muted = [System.Drawing.Color]::FromArgb(140,147,167)
$acc   = [System.Drawing.Color]::FromArgb(0,180,255)

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Keyboard Lighting'
$form.ClientSize      = New-Object System.Drawing.Size(462, 700)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false
$form.BackColor       = $bg
$form.ForeColor       = $fg
$form.Font            = New-Object System.Drawing.Font('Segoe UI', 9.5)

function New-Label($text, $x, $y, $w, $col, $size, $bold) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text      = $text
    $l.Location  = New-Object System.Drawing.Point($x, $y)
    $l.Size      = New-Object System.Drawing.Size($w, 22)
    $l.ForeColor = $col
    $style = if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $l.Font      = New-Object System.Drawing.Font('Segoe UI', $size, $style)
    $form.Controls.Add($l)
    return $l
}

$y = 18
New-Label 'Keyboard Lighting' 24 $y 300 $fg 14 $true | Out-Null
$y += 30
New-Label 'ROG Strix G16  -  16 zones' 24 $y 300 $muted 8.5 $false | Out-Null

# ---- effect ----
$y += 36
New-Label 'PATTERN' 24 $y 200 $muted 8 $true | Out-Null
$y += 24
$cboEffect = New-Object System.Windows.Forms.ComboBox
$cboEffect.Location      = New-Object System.Drawing.Point(24, $y)
$cboEffect.Size          = New-Object System.Drawing.Size(410, 28)
$cboEffect.DropDownStyle = 'DropDownList'
$cboEffect.BackColor     = $card
$cboEffect.ForeColor     = $fg
$cboEffect.FlatStyle     = 'Flat'
$cboEffect.Font          = New-Object System.Drawing.Font('Segoe UI', 10)
foreach ($k in $Effects.Keys) { [void]$cboEffect.Items.Add($k) }
$cboEffect.SelectedIndex = 0
$form.Controls.Add($cboEffect)

# ---- colours ----
$y += 42
$lblCol = New-Label 'COLOURS    (click a square to change it)' 24 $y 340 $muted 8 $true

$y += 24
$pnlCol = New-Object System.Windows.Forms.Panel
$pnlCol.Location = New-Object System.Drawing.Point(24, $y)
$pnlCol.Size     = New-Object System.Drawing.Size(410, 46)
$pnlCol.BackColor = $bg
$form.Controls.Add($pnlCol)

function Redraw-Swatches {
    $pnlCol.Controls.Clear()
    $x = 0
    for ($i = 0; $i -lt $script:Swatches.Count; $i++) {
        $idx = $i
        $b = New-Object System.Windows.Forms.Button
        $b.Size      = New-Object System.Drawing.Size(42, 42)
        $b.Location  = New-Object System.Drawing.Point($x, 0)
        $b.FlatStyle = 'Flat'
        $b.FlatAppearance.BorderSize  = 2
        $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,64,80)
        $b.Cursor    = 'Hand'
        try {
            $b.BackColor = [System.Drawing.ColorTranslator]::FromHtml($script:Swatches[$idx])
        } catch {
            $b.BackColor = [System.Drawing.Color]::Gray
        }
        $b.Tag = $idx
        $b.Add_Click({
            $i = $this.Tag
            $dlg = New-Object System.Windows.Forms.ColorDialog
            $dlg.FullOpen = $true
            try { $dlg.Color = [System.Drawing.ColorTranslator]::FromHtml($script:Swatches[$i]) } catch { }
            if ($dlg.ShowDialog() -eq 'OK') {
                $script:Swatches[$i] = '#{0:X2}{1:X2}{2:X2}' -f $dlg.Color.R, $dlg.Color.G, $dlg.Color.B
                Redraw-Swatches
                Save-Config
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
            Save-Config
        })
        $pnlCol.Controls.Add($add)
        $x += 40
    }

    if ($script:Swatches.Count -gt 2) {
        $rem = New-Object System.Windows.Forms.Button
        $rem.Text      = [char]0x2212
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
                Save-Config
            }
        })
        $pnlCol.Controls.Add($rem)
    }
}

# ---- preview strip ----
$y += 58
New-Label 'PREVIEW' 24 $y 200 $muted 8 $true | Out-Null
$y += 22
$pbPreview = New-Object System.Windows.Forms.PictureBox
$pbPreview.Location  = New-Object System.Drawing.Point(24, $y)
$pbPreview.Size      = New-Object System.Drawing.Size(410, 38)
$pbPreview.BackColor = [System.Drawing.Color]::Black
$form.Controls.Add($pbPreview)

$script:phase = 0.0

# ---- colour maths, mirrored from the engine so the preview tells the truth ----
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
$script:PalGain = @()
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
    $g = $_.Graphics
    $w = $pbPreview.Width
    $h = $pbPreview.Height
    $n = 16
    $cw = $w / [double]$n
    $pal = @()
    foreach ($s in $script:Swatches) {
        try { $pal += ,([System.Drawing.ColorTranslator]::FromHtml($s)) } catch { $pal += ,([System.Drawing.Color]::Gray) }
    }
    if ($pal.Count -lt 2) { $pal += $pal[0] }
    $pc = $pal.Count
    $bright = $trkBright.Value / 100.0
    Update-PalGain $pal

    # The preview is a smooth strip: it shows the gradient as it travels
    # across the physical width, which is what the keyboard now does.
    for ($i = 0; $i -lt $n; $i++) {
        # 'Wrap around the light bar' means the gradient covers a full loop,
        # so the strip shows one complete cycle end to end.
        $u0 = $i / [double]($n - 1)
        if ($chkLoop -and $chkLoop.Checked) { $u0 = $i / [double]$n }
        $f = (($u0 + $script:phase) % 1.0) * $pc
        if ($f -lt 0) { $f += $pc }
        $a = [int][Math]::Floor($f)
        $u = $f - $a
        $b2 = ($a + 1) % $pc
        $a  = $a % $pc
        # Blend in linear light with a smoothstep crossfade, exactly like
        # the engine, so the preview is honest.
        $w = $u * $u * (3.0 - 2.0 * $u)
        $ga = $script:PalGain[$a]; $gb = $script:PalGain[$b2]
        $lr = (Lin $pal[$a].R) * $ga; $lr = $lr + (((Lin $pal[$b2].R) * $gb) - $lr) * $w
        $lg = (Lin $pal[$a].G) * $ga; $lg = $lg + (((Lin $pal[$b2].G) * $gb) - $lg) * $w
        $lb = (Lin $pal[$a].B) * $ga; $lb = $lb + (((Lin $pal[$b2].B) * $gb) - $lb) * $w
        # Engine scales brightness in GAMMA space, so do the same here.
        $r = [int]((Srgb $lr) * $bright)
        $gg= [int]((Srgb $lg) * $bright)
        $bb= [int]((Srgb $lb) * $bright)
        $br = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb($r,$gg,$bb))
        $g.FillRectangle($br, [float]($i*$cw), 0.0, [float]($cw+1), [float]$h)
        $br.Dispose()
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 33          # ~30fps preview
$timer.Add_Tick({
    $dir = 1.0
    if ($chkReverse.Checked) { $dir = -1.0 }
    # Match the engine: gradient phase advances at Speed * 0.25 per second.
    $script:phase = ($script:phase + (0.25 * ($trkSpeed.Value/10.0) * $dir) * 0.033) % 1.0
    if ($script:phase -lt 0) { $script:phase += 1.0 }
    $pbPreview.Invalidate()
})

# ---- sliders ----
$y += 52
$lblSpd = New-Label 'SPEED     1.0x' 24 $y 200 $muted 8 $true
$y += 22
$trkSpeed = New-Object System.Windows.Forms.TrackBar
$trkSpeed.Location   = New-Object System.Drawing.Point(20, $y)
$trkSpeed.Size       = New-Object System.Drawing.Size(414, 40)
$trkSpeed.Minimum    = 1
$trkSpeed.Maximum    = 50
$trkSpeed.Value      = 10
$trkSpeed.TickStyle  = 'None'
$trkSpeed.BackColor  = $bg
$trkSpeed.Add_ValueChanged({
    $lblSpd.Text = 'SPEED     {0:N1}x' -f ($trkSpeed.Value/10.0)
})
$form.Controls.Add($trkSpeed)

$y += 42
$lblBrt = New-Label 'BRIGHTNESS     100%' 24 $y 250 $muted 8 $true
$y += 22
$trkBright = New-Object System.Windows.Forms.TrackBar
$trkBright.Location  = New-Object System.Drawing.Point(20, $y)
$trkBright.Size      = New-Object System.Drawing.Size(414, 40)
$trkBright.Minimum   = 5
$trkBright.Maximum   = 100
$trkBright.Value     = 100
$trkBright.TickStyle = 'None'
$trkBright.BackColor = $bg
$trkBright.Add_ValueChanged({
    $lblBrt.Text = 'BRIGHTNESS     {0}%' -f $trkBright.Value
    $pbPreview.Invalidate()
    # Live: nudge the running engine instead of making the user re-Apply.
    Set-LiveBrightness $trkBright.Value
})
$form.Controls.Add($trkBright)

# ---- checkboxes ----
$y += 44
$chkMirror = New-Object System.Windows.Forms.CheckBox
$chkMirror.Text      = 'Mirror from centre'
$chkMirror.Location  = New-Object System.Drawing.Point(24, $y)
$chkMirror.Size      = New-Object System.Drawing.Size(170, 24)
$chkMirror.ForeColor = $fg
$form.Controls.Add($chkMirror)

$chkReverse = New-Object System.Windows.Forms.CheckBox
$chkReverse.Text      = 'Reverse direction'
$chkReverse.Location  = New-Object System.Drawing.Point(210, $y)
$chkReverse.Size      = New-Object System.Drawing.Size(170, 24)
$chkReverse.ForeColor = $fg
$form.Controls.Add($chkReverse)

$y += 30
$chkLoop = New-Object System.Windows.Forms.CheckBox
$chkLoop.Text      = 'Wrap around the light bar'
$chkLoop.Location  = New-Object System.Drawing.Point(24, $y)
$chkLoop.Size      = New-Object System.Drawing.Size(280, 24)
$chkLoop.ForeColor = $fg
$chkLoop.Checked   = $true
$form.Controls.Add($chkLoop)

$y += 30
$chkEq = New-Object System.Windows.Forms.CheckBox
$chkEq.Text      = 'Even out colour brightness'
$chkEq.Location  = New-Object System.Drawing.Point(24, $y)
$chkEq.Size      = New-Object System.Drawing.Size(280, 24)
$chkEq.ForeColor = $fg
$chkEq.Checked   = $true
$form.Controls.Add($chkEq)

$y += 30
$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.Text      = 'Start automatically when I log in'
$chkAuto.Location  = New-Object System.Drawing.Point(24, $y)
$chkAuto.Size      = New-Object System.Drawing.Size(300, 24)
$chkAuto.ForeColor = $fg
$form.Controls.Add($chkAuto)

# ---- buttons ----
$y += 38
$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text      = 'Apply to keyboard'
$btnApply.Location  = New-Object System.Drawing.Point(24, $y)
$btnApply.Size      = New-Object System.Drawing.Size(250, 44)
$btnApply.FlatStyle = 'Flat'
$btnApply.BackColor = $acc
$btnApply.ForeColor = [System.Drawing.Color]::White
$btnApply.Font      = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Bold)
$btnApply.FlatAppearance.BorderSize = 0
$btnApply.Cursor    = 'Hand'
$form.Controls.Add($btnApply)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text      = 'Turn off'
$btnStop.Location  = New-Object System.Drawing.Point(284, $y)
$btnStop.Size      = New-Object System.Drawing.Size(150, 44)
$btnStop.FlatStyle = 'Flat'
$btnStop.BackColor = $card
$btnStop.ForeColor = $fg
$btnStop.Font      = New-Object System.Drawing.Font('Segoe UI', 10)
$btnStop.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(60,64,80)
$btnStop.Cursor    = 'Hand'
$form.Controls.Add($btnStop)

$y += 50
$lblStatus = New-Label '  Not running' 24 $y 400 $muted 9 $false

# ---- check for updates (small, bottom right) ----
$btnUpd = New-Object System.Windows.Forms.LinkLabel
$btnUpd.Text          = 'Check for updates'
$btnUpd.Location      = New-Object System.Drawing.Point(300, ($y + 1))
$btnUpd.Size          = New-Object System.Drawing.Size(140, 20)
$btnUpd.TextAlign     = 'MiddleRight'
$btnUpd.Font          = New-Object System.Drawing.Font('Segoe UI', 8.5)
$btnUpd.LinkColor     = $muted
$btnUpd.ActiveLinkColor = $acc
$btnUpd.Cursor        = 'Hand'
$form.Controls.Add($btnUpd)

# ---------------------------------------------------------------- wiring
$cboEffect.Add_SelectedIndexChanged({
    $key = $cboEffect.SelectedItem
    if (-not $key) { return }
    $eff = $Effects[$key]
    $usesPal = $UsesPalette -contains $eff
    $usesOne = $UsesOne -contains $eff
    $pnlCol.Visible = ($usesPal -or $usesOne)
    if ($usesPal) {
        $lblCol.Text = 'COLOURS    (click a square to change it)'
    } elseif ($usesOne) {
        $lblCol.Text = 'COLOURS    (this pattern uses the first one)'
    } else {
        $lblCol.Text = 'COLOURS    (this pattern picks its own)'
    }
    $lblCol.Visible = $true
    Save-Config
})

# ---- auto-apply -----------------------------------------------------------
# Effect, colours and the layout/equalise toggles need the engine restarted.
# Do it automatically on a short debounce so rapid changes don't thrash it.
$script:ReapplyTimer = New-Object System.Windows.Forms.Timer
$script:ReapplyTimer.Interval = 450
$script:ReapplyTimer.Add_Tick({
    $script:ReapplyTimer.Stop()
    if ($script:Running -and -not $script:Running.HasExited) { Apply-Lighting }
})
function Request-Reapply {
    if ($script:Suppress) { return }
    $script:ReapplyTimer.Stop()
    $script:ReapplyTimer.Start()
}

$cboEffect.Add_SelectedIndexChanged({ Request-Reapply })
$chkLoop.Add_CheckedChanged({   $pbPreview.Invalidate(); Request-Reapply })
$chkEq.Add_CheckedChanged({     $pbPreview.Invalidate(); Request-Reapply })
$chkMirror.Add_CheckedChanged({ Request-Reapply })
$chkReverse.Add_CheckedChanged({ $pbPreview.Invalidate(); Request-Reapply })
$trkSpeed.Add_ValueChanged({    Request-Reapply })

$btnApply.Add_Click({ Apply-Lighting })
$btnStop.Add_Click({ Set-AllOff })

$chkAuto.Add_Click({
    if ($chkAuto.Checked) {
        try {
            $argLine = ((Get-EngineArgs) -join ' ')
            $act  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine
            $trg  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
            $prin = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            $set  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                        -DontStopOnIdleEnd -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable
            if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            }
            Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg `
                -Principal $prin -Settings $set -Description 'Keyboard lighting' | Out-Null
            $lblStatus.Text = '  Will start automatically at log in'
            $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(70,200,120)
        } catch {
            $chkAuto.Checked = $false
            [System.Windows.Forms.MessageBox]::Show(
                "Could not create the startup task.`n`nThis needs Administrator. Close the panel, right-click Lighting-Panel.bat and choose Run as administrator.`n`n$($_.Exception.Message)",
                'Needs Administrator','OK','Warning') | Out-Null
        }
    } else {
        try {
            if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            }
            $lblStatus.Text = '  Automatic start removed'
            $lblStatus.ForeColor = $muted
        } catch { }
    }
})

$form.Add_Shown({
    Load-Config
    Redraw-Swatches
    $lblSpd.Text = 'SPEED     {0:N1}x' -f ($trkSpeed.Value/10.0)
    $lblBrt.Text = 'BRIGHTNESS     {0}%' -f $trkBright.Value
    try { $chkAuto.Checked = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) } catch { }
    $timer.Start()
    $script:Suppress = $false      # loading done; auto-apply is live now
})

$btnUpd.Add_LinkClicked({
    $btnUpd.Text = 'Checking...'
    $form.Refresh()
    $base  = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting'
    $files = @('Aura-Background.ps1','Lighting-Panel.ps1','Lighting-Panel.bat','Update.bat','Update.ps1','Check.bat','Check.ps1','MyEffect.ps1','Find-Lamps.ps1')
    $changed = @(); $failed = @()
    try {
        [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
        foreach ($f in $files) {
            $dest = Join-Path $Here $f
            $tmp  = Join-Path $env:TEMP ("kbl_" + $f)
            try {
                Invoke-WebRequest "$base/$f" -OutFile $tmp -UseBasicParsing -TimeoutSec 20
                $newHash = (Get-FileHash $tmp -Algorithm SHA256).Hash
                $oldHash = if (Test-Path $dest) { (Get-FileHash $dest -Algorithm SHA256).Hash } else { '' }
                if ($newHash -ne $oldHash) {
                    Copy-Item $tmp $dest -Force
                    Unblock-File $dest
                    $changed += $f
                }
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            } catch { $failed += $f }
        }
    } catch { $failed += 'connection' }

    $btnUpd.Text = 'Check for updates'

    if ($failed.Count -gt 0 -and $changed.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Could not reach the update server.`n`nCheck your internet connection and try again.",
            'Update failed', 'OK', 'Warning') | Out-Null
        return
    }
    if ($changed.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "You already have the latest version.", 'Up to date', 'OK', 'Information') | Out-Null
        return
    }

    $msg = "Updated:`n`n  " + ($changed -join "`n  ") +
           "`n`nThe panel needs to restart to load the new version.`n`nRestart now?"
    if ([System.Windows.Forms.MessageBox]::Show($msg,'Update installed','YesNo','Question') -eq 'Yes') {
        Save-Config
        Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$SelfPath`"")
        $script:SkipSave = $true
        $form.Close()
    }
})

$form.Add_FormClosing({
    $timer.Stop()
    if (-not $script:SkipSave) { Save-Config }
})

[void]$form.ShowDialog()
