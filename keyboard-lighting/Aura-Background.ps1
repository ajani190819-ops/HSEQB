#requires -Version 5.1
<#
  AURA-BACKGROUND
  Animated keyboard lighting that keeps running when this window is NOT focused.

  It does NOT use Windows Dynamic Lighting, so the "app must be in the
  foreground" rule does not apply. It talks straight to the keyboard's
  LampArray HID interface.

  USAGE
    .\Aura-Background.ps1                         # default: wave
    .\Aura-Background.ps1 -Effect rainbow
    .\Aura-Background.ps1 -Effect breathe -Color "#FF2200"
    .\Aura-Background.ps1 -Effect comet -Speed 2.0 -Brightness 0.5
    .\Aura-Background.ps1 -Effect off
    .\Aura-Background.ps1 -Restore                # hand control back to firmware

  EFFECTS
    wave      colour sweeps left to right
    rainbow   full spectrum scrolling across the zones
    breathe   whole keyboard fades in and out
    comet     bright head with a fading tail, looping
    pulse     sharp flash then slow decay
    scanner   single bright zone bouncing left-right
    fire      flickering warm embers
    static    one solid colour
    off       all lamps off
#>

[CmdletBinding()]
param(
    [ValidateSet('wave','rainbow','breathe','comet','pulse','scanner','fire','static','off')]
    [string]$Effect = 'wave',

    [string]$Color = '#00B4FF',
    [string]$Color2 = '#FF0066',

    [ValidateRange(0.05, 20.0)]
    [double]$Speed = 1.0,

    [ValidateRange(0.0, 1.0)]
    [double]$Brightness = 1.0,

    [ValidateRange(5, 60)]
    [int]$Fps = 30,

    [switch]$Restore,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Say($msg, $col = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $col } }

# ============================================================================
# NATIVE
# ============================================================================
if (-not ('HidNative' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class HidNative {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr CreateFileW(string path, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool WriteFile(IntPtr h, byte[] buf, uint n, out uint written, IntPtr ov);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern bool HidD_GetPreparsedData(IntPtr h, out IntPtr pp);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern bool HidD_FreePreparsedData(IntPtr pp);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern int HidP_GetCaps(IntPtr pp, byte[] caps);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern int HidP_GetValueCaps(int type, byte[] vc, ref ushort len, IntPtr pp);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern int HidP_SetUsageValue(int type, ushort page, ushort coll, ushort usage, uint val, IntPtr pp, byte[] rpt, uint len);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern int HidP_GetUsageValue(int type, ushort page, ushort coll, ushort usage, out uint val, IntPtr pp, byte[] rpt, uint len);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern bool HidD_SetFeature(IntPtr h, byte[] buf, int len);
  [DllImport("hid.dll", SetLastError=true)]
  public static extern bool HidD_GetFeature(IntPtr h, byte[] buf, int len);
}
'@
}

$HIDGUID   = '{4d1e55b2-f16f-11cf-88cb-001111000030}'
$INVALID   = [IntPtr](-1)
$HIDOK        = 0x00110000
$GENRW     = [uint32]3221225472
$GENW      = [uint32]1073741824
$SHARERW   = [uint32]3
$OPENEXIST = [uint32]3

$U_LAMPCOUNT=0x03; $U_LAMPID=0x21; $U_POSX=0x23
$U_REDLVL=0x28; $U_GRNLVL=0x29; $U_BLULVL=0x2A; $U_INTLVL=0x2B
$U_RED=0x51; $U_GREEN=0x52; $U_BLUE=0x53; $U_INTENSITY=0x54; $U_FLAGS=0x55
$U_IDSTART=0x61; $U_IDEND=0x62; $U_AUTONOMOUS=0x71

# ============================================================================
# DISCOVERY
# ============================================================================
Say ""
Say "AURA-BACKGROUND  effect=$Effect  speed=$Speed  brightness=$Brightness" 'Cyan'
Say ""
Say "Looking for the keyboard lighting interface..." 'Yellow'

$devPath = $null
foreach ($d in (Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'HID%'" -ErrorAction SilentlyContinue)) {
    $id = $d.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $p = '\\?\' + $id.Replace('\','#').ToLower() + '#' + $HIDGUID
    $t = [HidNative]::CreateFileW($p, [uint32]0, $SHARERW, [IntPtr]::Zero, $OPENEXIST, [uint32]0, [IntPtr]::Zero)
    if ($t -eq $INVALID) { continue }
    $tpp = [IntPtr]::Zero
    if ([HidNative]::HidD_GetPreparsedData($t, [ref]$tpp)) {
        $c = New-Object byte[] 64
        if ([HidNative]::HidP_GetCaps($tpp, $c) -eq $HIDOK -and [BitConverter]::ToUInt16($c,2) -eq 0x59) {
            $devPath = $p
            Say ("  Found: {0}" -f $d.Name) 'Green'
        }
        [void][HidNative]::HidD_FreePreparsedData($tpp)
    }
    [void][HidNative]::CloseHandle($t)
    if ($devPath) { break }
}

if (-not $devPath) {
    Write-Host "  No LampArray HID interface found. Run Find-Lamps.ps1 and send me the output." -ForegroundColor Red
    return
}

$h = [HidNative]::CreateFileW($devPath, $GENRW, $SHARERW, [IntPtr]::Zero, $OPENEXIST, [uint32]0, [IntPtr]::Zero)
if ($h -eq $INVALID) { $h = [HidNative]::CreateFileW($devPath, $GENW, $SHARERW, [IntPtr]::Zero, $OPENEXIST, [uint32]0, [IntPtr]::Zero) }
if ($h -eq $INVALID) {
    Write-Host ("  Could not open the device (error {0}). Run PowerShell as Administrator." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) -ForegroundColor Red
    return
}

$pp = [IntPtr]::Zero
[void][HidNative]::HidD_GetPreparsedData($h, [ref]$pp)
$caps = New-Object byte[] 64
[void][HidNative]::HidP_GetCaps($pp, $caps)
$featLen = [int][BitConverter]::ToUInt16($caps,8)
$outLen  = [int][BitConverter]::ToUInt16($caps,6)

$reports = @{}
function Read-ValueCaps([int]$type, [int]$count) {
    if ($count -le 0) { return }
    $n = [uint16]$count
    $buf = New-Object byte[] (72 * $count)
    if ([HidNative]::HidP_GetValueCaps($type, $buf, [ref]$n, $script:pp) -ne $script:HIDOK) { return }
    for ($i = 0; $i -lt [int]$n; $i++) {
        $o = $i * 72
        if ([BitConverter]::ToUInt16($buf,$o) -ne 0x59) { continue }
        $rid = [int]$buf[$o+2]
        $rc  = [int][BitConverter]::ToUInt16($buf,$o+20)
        $isR = $buf[$o+12]
        $u1  = [int][BitConverter]::ToUInt16($buf,$o+56)
        $u2  = if ($isR -ne 0) { [int][BitConverter]::ToUInt16($buf,$o+58) } else { $u1 }
        $key = "{0}:{1}" -f $type, $rid
        if (-not $script:reports.ContainsKey($key)) { $script:reports[$key] = @{ Type=$type; Rid=$rid; Usages=@{} } }
        for ($u = $u1; $u -le $u2; $u++) { $script:reports[$key].Usages[$u] = $rc }
    }
}
Read-ValueCaps 2 ([int][BitConverter]::ToUInt16($caps,60))
Read-ValueCaps 1 ([int][BitConverter]::ToUInt16($caps,54))

function Find-Report([int[]]$must, [int[]]$mustNot) {
    foreach ($k in ($script:reports.Keys | Sort-Object)) {
        $r = $script:reports[$k]; $good = $true
        foreach ($m in $must) { if (-not $r.Usages.ContainsKey($m)) { $good = $false; break } }
        if ($good -and $mustNot) { foreach ($m in $mustNot) { if ($r.Usages.ContainsKey($m)) { $good = $false; break } } }
        if ($good) { return $r }
    }
    return $null
}

$rAttr  = Find-Report @($U_LAMPCOUNT) @()
$rCtrl  = Find-Report @($U_AUTONOMOUS) @()
$rRange = Find-Report @($U_IDSTART,$U_IDEND,$U_RED) @()
$rReq   = Find-Report @($U_LAMPID) @($U_RED,$U_POSX)
$rResp  = Find-Report @($U_POSX) @()

if (-not $rRange) {
    Write-Host "  This device has no LampRangeUpdateReport. Run Find-Lamps.ps1 and send me the report map." -ForegroundColor Red
    return
}

function New-Rpt($r) {
    $len = if ($r.Type -eq 2) { $script:featLen } else { $script:outLen }
    $b = New-Object byte[] $len; $b[0] = [byte]$r.Rid; return ,$b
}
function Set-Val($r, $buf, [int]$usage, [int]$value) {
    [void][HidNative]::HidP_SetUsageValue($r.Type, 0x59, 0, [uint16]$usage, [uint32]$value, $script:pp, $buf, [uint32]$buf.Length)
}
function Send-Rpt($r, $buf) {
    if ($r.Type -eq 2) { return [HidNative]::HidD_SetFeature($script:h, $buf, $buf.Length) }
    $w = [uint32]0
    return [HidNative]::WriteFile($script:h, $buf, [uint32]$buf.Length, [ref]$w, [IntPtr]::Zero)
}
function Get-Val($r, $buf, [int]$usage) {
    $v = [uint32]0
    if ([HidNative]::HidP_GetUsageValue($r.Type, 0x59, 0, [uint16]$usage, [ref]$v, $script:pp, $buf, [uint32]$buf.Length) -ne $script:HIDOK) { return $null }
    return [int]$v
}

# lamp count + channel depth
$lampCount = 0; $RMAX = 255; $GMAX = 255; $BMAX = 255; $IMAX = 255
if ($rAttr) {
    $b = New-Rpt $rAttr
    if ([HidNative]::HidD_GetFeature($h, $b, $b.Length)) {
        $v = Get-Val $rAttr $b $U_LAMPCOUNT; if ($v) { $lampCount = $v }
    }
}
if ($lampCount -le 0) { $lampCount = 16 }

if ($rReq -and $rResp) {
    $q = New-Rpt $rReq; Set-Val $rReq $q $U_LAMPID 0; [void](Send-Rpt $rReq $q)
    $rb = New-Rpt $rResp
    if ([HidNative]::HidD_GetFeature($h, $rb, $rb.Length)) {
        $v = Get-Val $rResp $rb $U_REDLVL; if ($v) { $RMAX = $v }
        $v = Get-Val $rResp $rb $U_GRNLVL; if ($v) { $GMAX = $v }
        $v = Get-Val $rResp $rb $U_BLULVL; if ($v) { $BMAX = $v }
        $v = Get-Val $rResp $rb $U_INTLVL; if ($v) { $IMAX = $v }
    }
}
$RMAX = [Math]::Max(1,$RMAX); $GMAX = [Math]::Max(1,$GMAX)
$BMAX = [Math]::Max(1,$BMAX); $IMAX = [Math]::Max(1,$IMAX)

# Build a left-to-right ordering of the zones from their real X positions,
# so a "wave" actually travels across the keyboard instead of jumping around.
$order = @(0..($lampCount - 1))
if ($rReq -and $rResp) {
    $pos = @()
    for ($i = 0; $i -lt $lampCount; $i++) {
        $q = New-Rpt $rReq; Set-Val $rReq $q $U_LAMPID $i; [void](Send-Rpt $rReq $q)
        $rb = New-Rpt $rResp
        $x = $i * 1000
        if ([HidNative]::HidD_GetFeature($h, $rb, $rb.Length)) {
            $gx = Get-Val $rResp $rb $U_POSX
            if ($null -ne $gx) { $x = $gx }
        }
        $pos += [pscustomobject]@{ Idx = $i; X = $x }
    }
    $order = @($pos | Sort-Object X | ForEach-Object { $_.Idx })
}

Say ("  {0} zones,  colour depth R{1} G{2} B{3}" -f $lampCount, $RMAX, $GMAX, $BMAX) 'DarkGray'

# take control away from the firmware
if ($rCtrl) {
    $b = New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 0; [void](Send-Rpt $rCtrl $b)
}

if ($Restore) {
    if ($rCtrl) {
        $b = New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 1; [void](Send-Rpt $rCtrl $b)
        Say "Autonomous mode restored - the keyboard firmware has its lighting back." 'Green'
    }
    [void][HidNative]::HidD_FreePreparsedData($pp); [void][HidNative]::CloseHandle($h)
    return
}

# ============================================================================
# COLOUR HELPERS
# ============================================================================
function ConvertFrom-Hex([string]$hex) {
    $s = $hex.TrimStart('#')
    if ($s.Length -eq 3) { $s = "$($s[0])$($s[0])$($s[1])$($s[1])$($s[2])$($s[2])" }
    return @(
        [Convert]::ToInt32($s.Substring(0,2),16),
        [Convert]::ToInt32($s.Substring(2,2),16),
        [Convert]::ToInt32($s.Substring(4,2),16)
    )
}
function Convert-Hsv([double]$hDeg, [double]$s, [double]$v) {
    $hDeg = $hDeg % 360.0; if ($hDeg -lt 0) { $hDeg += 360.0 }
    $c = $v * $s
    $x = $c * (1.0 - [Math]::Abs((($hDeg / 60.0) % 2.0) - 1.0))
    $m = $v - $c
    switch ([int][Math]::Floor($hDeg / 60.0)) {
        0 { $r=$c; $g=$x; $b=0 }
        1 { $r=$x; $g=$c; $b=0 }
        2 { $r=0;  $g=$c; $b=$x }
        3 { $r=0;  $g=$x; $b=$c }
        4 { $r=$x; $g=0;  $b=$c }
        default { $r=$c; $g=0; $b=$x }
    }
    return @([int](255*($r+$m)), [int](255*($g+$m)), [int](255*($b+$m)))
}

$C1 = ConvertFrom-Hex $Color
$C2 = ConvertFrom-Hex $Color2

# frame buffers
$fr = New-Object int[] $lampCount
$fg = New-Object int[] $lampCount
$fb = New-Object int[] $lampCount
$pr = New-Object int[] $lampCount
$pg = New-Object int[] $lampCount
$pb = New-Object int[] $lampCount
for ($i=0; $i -lt $lampCount; $i++) { $pr[$i] = -1 }

function Push-Frame {
    $changed = @()
    for ($i = 0; $i -lt $script:lampCount; $i++) {
        if ($script:fr[$i] -ne $script:pr[$i] -or $script:fg[$i] -ne $script:pg[$i] -or $script:fb[$i] -ne $script:pb[$i]) {
            $changed += $i
        }
    }
    if ($changed.Count -eq 0) { return }
    for ($n = 0; $n -lt $changed.Count; $n++) {
        $i = $changed[$n]
        $last = if ($n -eq ($changed.Count - 1)) { 1 } else { 0 }
        $b = New-Rpt $script:rRange
        Set-Val $script:rRange $b $U_FLAGS     $last
        Set-Val $script:rRange $b $U_IDSTART   $i
        Set-Val $script:rRange $b $U_IDEND     $i
        Set-Val $script:rRange $b $U_RED       ([int]($script:fr[$i] * $script:RMAX / 255))
        Set-Val $script:rRange $b $U_GREEN     ([int]($script:fg[$i] * $script:GMAX / 255))
        Set-Val $script:rRange $b $U_BLUE      ([int]($script:fb[$i] * $script:BMAX / 255))
        Set-Val $script:rRange $b $U_INTENSITY $script:IMAX
        [void](Send-Rpt $script:rRange $b)
        $script:pr[$i] = $script:fr[$i]; $script:pg[$i] = $script:fg[$i]; $script:pb[$i] = $script:fb[$i]
    }
}
function Set-Zone([int]$slot, [double]$r, [double]$g, [double]$b) {
    $i = $script:order[$slot]
    $k = $script:Brightness
    $script:fr[$i] = [Math]::Max(0, [Math]::Min(255, [int]($r * $k)))
    $script:fg[$i] = [Math]::Max(0, [Math]::Min(255, [int]($g * $k)))
    $script:fb[$i] = [Math]::Max(0, [Math]::Min(255, [int]($b * $k)))
}

# ============================================================================
# ONE-SHOT EFFECTS
# ============================================================================
if ($Effect -eq 'off' -or $Effect -eq 'static') {
    for ($i = 0; $i -lt $lampCount; $i++) {
        if ($Effect -eq 'off') { Set-Zone $i 0 0 0 } else { Set-Zone $i $C1[0] $C1[1] $C1[2] }
    }
    Push-Frame
    Say ("  {0} applied. Exiting - the colour stays." -f $Effect.ToUpper()) 'Green'
    [void][HidNative]::HidD_FreePreparsedData($pp); [void][HidNative]::CloseHandle($h)
    return
}

# ============================================================================
# ANIMATION LOOP
# ============================================================================
Say ""
Say "  Running. This keeps going whether or not this window is focused." 'Green'
Say "  Press Ctrl+C to stop." 'DarkGray'
Say ""

$frameMs = [int](1000 / $Fps)
$sw = [Diagnostics.Stopwatch]::StartNew()
$rand = New-Object System.Random
$heat = New-Object double[] $lampCount

try {
    while ($true) {
        $t = $sw.Elapsed.TotalSeconds * $Speed
        $N = $lampCount

        switch ($Effect) {

            'wave' {
                for ($i = 0; $i -lt $N; $i++) {
                    $ph = ($t * 1.2) - ($i / [double]$N) * 2.0
                    $w  = (1.0 + [Math]::Sin($ph * [Math]::PI)) / 2.0
                    $w  = [Math]::Pow($w, 2.0)
                    Set-Zone $i ($C1[0]*$w + $C2[0]*(1-$w)*0.15) ($C1[1]*$w + $C2[1]*(1-$w)*0.15) ($C1[2]*$w + $C2[2]*(1-$w)*0.15)
                }
            }

            'rainbow' {
                for ($i = 0; $i -lt $N; $i++) {
                    $hue = (($i / [double]$N) * 360.0) + ($t * 90.0)
                    $c = Convert-Hsv $hue 1.0 1.0
                    Set-Zone $i $c[0] $c[1] $c[2]
                }
            }

            'breathe' {
                $w = (1.0 + [Math]::Sin($t * 1.6 * [Math]::PI)) / 2.0
                $w = 0.04 + 0.96 * [Math]::Pow($w, 2.2)
                for ($i = 0; $i -lt $N; $i++) { Set-Zone $i ($C1[0]*$w) ($C1[1]*$w) ($C1[2]*$w) }
            }

            'comet' {
                $head = ($t * 6.0) % $N
                for ($i = 0; $i -lt $N; $i++) {
                    $d = $head - $i
                    if ($d -lt 0) { $d += $N }
                    $w = [Math]::Exp(-$d * 0.9)
                    Set-Zone $i ($C1[0]*$w) ($C1[1]*$w) ($C1[2]*$w)
                }
            }

            'pulse' {
                $ph = $t % 1.0
                $w = [Math]::Exp(-$ph * 4.5)
                $hue = [Math]::Floor($t) * 47.0
                $c = Convert-Hsv $hue 1.0 1.0
                for ($i = 0; $i -lt $N; $i++) { Set-Zone $i ($c[0]*$w) ($c[1]*$w) ($c[2]*$w) }
            }

            'scanner' {
                $span = ($N - 1) * 2.0
                $p = ($t * 7.0) % $span
                if ($p -gt ($N - 1)) { $p = $span - $p }
                for ($i = 0; $i -lt $N; $i++) {
                    $d = [Math]::Abs($i - $p)
                    $w = [Math]::Max(0.0, 1.0 - ($d / 2.2))
                    $w = $w * $w
                    Set-Zone $i ($C1[0]*$w) ($C1[1]*$w) ($C1[2]*$w)
                }
            }

            'fire' {
                for ($i = 0; $i -lt $N; $i++) {
                    $heat[$i] = $heat[$i] * 0.86 + $rand.NextDouble() * 0.30
                    if ($heat[$i] -gt 1.0) { $heat[$i] = 1.0 }
                    $v = $heat[$i]
                    Set-Zone $i (255*$v) (90*$v*$v) (10*$v*$v*$v)
                }
            }
        }

        Push-Frame
        Start-Sleep -Milliseconds $frameMs
    }
}
finally {
    Say ""
    Say "  Stopping - handing lighting back to the keyboard firmware." 'Yellow'
    if ($rCtrl) {
        $b = New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 1; [void](Send-Rpt $rCtrl $b)
    }
    [void][HidNative]::HidD_FreePreparsedData($pp)
    [void][HidNative]::CloseHandle($h)
}
