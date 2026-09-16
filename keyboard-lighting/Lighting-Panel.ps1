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
$Engine  = Join-Path $Here 'Aura-Background.ps1'
$CfgDir  = Join-Path $env:LOCALAPPDATA 'KeyboardLighting'
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
    return $a
}

function Apply-Lighting {
    Stop-Lighting
    Start-Sleep -Milliseconds 250
    try {
        $script:Running = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList (Get-EngineArgs) -WindowStyle Hidden -PassThru
        $lblStatus.Text      = '  Running'
        $lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(70,200,120)
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
$form.Size            = New-Object System.Drawing.Size(470, 560)
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

    for ($i = 0; $i -lt $n; $i++) {
        $f = ((($i / [double]$n) + $script:phase) % 1.0) * $pc
        if ($f -lt 0) { $f += $pc }
        $a = [int][Math]::Floor($f)
        $u = $f - $a
        $b2 = ($a + 1) % $pc
        $a  = $a % $pc
        $r = [int](($pal[$a].R + ($pal[$b2].R - $pal[$a].R) * $u) * $bright)
        $gg= [int](($pal[$a].G + ($pal[$b2].G - $pal[$a].G) * $u) * $bright)
        $bb= [int](($pal[$a].B + ($pal[$b2].B - $pal[$a].B) * $u) * $bright)
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
})

$form.Add_FormClosing({
    $timer.Stop()
    Save-Config
})

[void]$form.ShowDialog()
