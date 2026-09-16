#requires -Version 5.1
<#
  FIND-LAMPS  -  step 1 of the background keyboard lighting tool.

  What this does:
    * Finds your keyboard's "LampArray" lighting interface directly, as a raw HID device.
    * Talks to it WITHOUT Windows Dynamic Lighting, so there is no focus / foreground rule.
    * Prints a map of your 16 zones (position + colour depth).
    * Runs a short colour test so you can see it working.

  Run it in Windows PowerShell as Administrator.
#>

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " FIND-LAMPS  -  direct HID keyboard lighting probe" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# ----------------------------------------------------------------------------
# 1. Native bindings
# ----------------------------------------------------------------------------
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

$HIDGUID  = '{4d1e55b2-f16f-11cf-88cb-001111000030}'
$INVALID  = [IntPtr](-1)
$HIDOK       = 0x00110000          # HIDP_STATUS_SUCCESS
$GENRW    = [uint32]3221225472  # GENERIC_READ | GENERIC_WRITE
$GENW     = [uint32]1073741824  # GENERIC_WRITE
$SHARERW  = [uint32]3
$OPENEXIST= [uint32]3

# LampArray usage IDs (HID Lighting & Illumination page 0x59)
$U_LAMPCOUNT = 0x03
$U_LAMPID    = 0x21
$U_POSX      = 0x23
$U_POSY      = 0x24
$U_POSZ      = 0x25
$U_PURPOSES  = 0x26
$U_REDLVL    = 0x28
$U_GRNLVL    = 0x29
$U_BLULVL    = 0x2A
$U_INTLVL    = 0x2B
$U_RED       = 0x51
$U_GREEN     = 0x52
$U_BLUE      = 0x53
$U_INTENSITY = 0x54
$U_FLAGS     = 0x55
$U_IDSTART   = 0x61
$U_IDEND     = 0x62
$U_AUTONOMOUS= 0x71

# ----------------------------------------------------------------------------
# 2. Find every HID interface whose usage page is 0x59 (LampArray)
# ----------------------------------------------------------------------------
Write-Host "[1/5] Scanning HID devices for a LampArray interface..." -ForegroundColor Yellow

$hits = New-Object System.Collections.ArrayList
$pnp  = Get-CimInstance -ClassName Win32_PnPEntity -Filter "PNPDeviceID LIKE 'HID%'" -ErrorAction SilentlyContinue

foreach ($d in $pnp) {
    $id = $d.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $path = '\\?\' + $id.Replace('\', '#').ToLower() + '#' + $HIDGUID

    $h = [HidNative]::CreateFileW($path, [uint32]0, $SHARERW, [IntPtr]::Zero, $OPENEXIST, [uint32]0, [IntPtr]::Zero)
    if ($h -eq $INVALID) { continue }

    $pp = [IntPtr]::Zero
    if ([HidNative]::HidD_GetPreparsedData($h, [ref]$pp)) {
        $caps = New-Object byte[] 64
        if ([HidNative]::HidP_GetCaps($pp, $caps) -eq $HIDOK) {
            $page = [BitConverter]::ToUInt16($caps, 2)
            if ($page -eq 0x59) {
                [void]$hits.Add([pscustomobject]@{
                    Path       = $path
                    PnpId      = $id
                    Name       = $d.Name
                    FeatureLen = [BitConverter]::ToUInt16($caps, 8)
                    OutputLen  = [BitConverter]::ToUInt16($caps, 6)
                    NumFeatVal = [BitConverter]::ToUInt16($caps, 60)
                    NumOutVal  = [BitConverter]::ToUInt16($caps, 54)
                })
            }
        }
        [void][HidNative]::HidD_FreePreparsedData($pp)
    }
    [void][HidNative]::CloseHandle($h)
}

if ($hits.Count -eq 0) {
    Write-Host ""
    Write-Host "  NO LAMPARRAY HID INTERFACE FOUND." -ForegroundColor Red
    Write-Host "  Copy everything above and send it back." -ForegroundColor Red
    Write-Host ""
    return
}

Write-Host ("  Found {0} LampArray interface(s):" -f $hits.Count) -ForegroundColor Green
foreach ($x in $hits) {
    Write-Host ("   - {0}" -f $x.Name)
    Write-Host ("     {0}" -f $x.PnpId) -ForegroundColor DarkGray
    Write-Host ("     feature report len = {0}   output report len = {1}" -f $x.FeatureLen, $x.OutputLen) -ForegroundColor DarkGray
}
Write-Host ""

$dev = $hits[0]

# ----------------------------------------------------------------------------
# 3. Open it for writing and work out which report IDs do what
# ----------------------------------------------------------------------------
Write-Host "[2/5] Opening it for read/write..." -ForegroundColor Yellow

$h = [HidNative]::CreateFileW($dev.Path, $GENRW, $SHARERW, [IntPtr]::Zero, $OPENEXIST, [uint32]0, [IntPtr]::Zero)
if ($h -eq $INVALID) {
    Write-Host "  read/write refused, trying write-only..." -ForegroundColor DarkYellow
    $h = [HidNative]::CreateFileW($dev.Path, $GENW, $SHARERW, [IntPtr]::Zero, $OPENEXIST, [uint32]0, [IntPtr]::Zero)
}
if ($h -eq $INVALID) {
    Write-Host ""
    Write-Host ("  COULD NOT OPEN THE DEVICE. Win32 error {0}." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) -ForegroundColor Red
    Write-Host "  Make sure this PowerShell window says 'Administrator' in the title bar." -ForegroundColor Red
    Write-Host ""
    return
}
Write-Host "  Opened OK." -ForegroundColor Green

$pp = [IntPtr]::Zero
[void][HidNative]::HidD_GetPreparsedData($h, [ref]$pp)
$caps = New-Object byte[] 64
[void][HidNative]::HidP_GetCaps($pp, $caps)
$featLen = [int][BitConverter]::ToUInt16($caps, 8)
$outLen  = [int][BitConverter]::ToUInt16($caps, 6)

# Walk the value caps for Feature (2) and Output (1) and note usage -> report id
$reports = @{}   # key "<type>:<rid>" -> @{ Type=; Rid=; Usages=@{usage=reportCount} }

function Read-ValueCaps([int]$type, [int]$count) {
    if ($count -le 0) { return }
    $n   = [uint16]$count
    $buf = New-Object byte[] (72 * $count)
    $st  = [HidNative]::HidP_GetValueCaps($type, $buf, [ref]$n, $script:pp)
    if ($st -ne $script:HIDOK) { return }
    for ($i = 0; $i -lt [int]$n; $i++) {
        $o   = $i * 72
        $pg  = [BitConverter]::ToUInt16($buf, $o)
        if ($pg -ne 0x59) { continue }
        $rid = [int]$buf[$o + 2]
        $rc  = [int][BitConverter]::ToUInt16($buf, $o + 20)
        $isR = $buf[$o + 12]
        $u1  = [int][BitConverter]::ToUInt16($buf, $o + 56)
        $u2  = if ($isR -ne 0) { [int][BitConverter]::ToUInt16($buf, $o + 58) } else { $u1 }
        $key = "{0}:{1}" -f $type, $rid
        if (-not $script:reports.ContainsKey($key)) {
            $script:reports[$key] = @{ Type = $type; Rid = $rid; Usages = @{} }
        }
        for ($u = $u1; $u -le $u2; $u++) { $script:reports[$key].Usages[$u] = $rc }
    }
}

Read-ValueCaps 2 ([int][BitConverter]::ToUInt16($caps, 60))   # feature
Read-ValueCaps 1 ([int][BitConverter]::ToUInt16($caps, 54))   # output

Write-Host ""
Write-Host "[3/5] Report map:" -ForegroundColor Yellow
foreach ($k in ($reports.Keys | Sort-Object)) {
    $r  = $reports[$k]
    $tn = if ($r.Type -eq 2) { 'Feature' } else { 'Output ' }
    $us = ($r.Usages.Keys | Sort-Object | ForEach-Object { '0x{0:X2}' -f $_ }) -join ' '
    Write-Host ("   {0} id {1,-3} : {2}" -f $tn, $r.Rid, $us) -ForegroundColor DarkGray
}

function Find-Report([int[]]$must, [int[]]$mustNot) {
    foreach ($k in ($script:reports.Keys | Sort-Object)) {
        $r = $script:reports[$k]
        $good = $true
        foreach ($m in $must)    { if (-not $r.Usages.ContainsKey($m)) { $good = $false; break } }
        if ($good -and $mustNot) { foreach ($m in $mustNot) { if ($r.Usages.ContainsKey($m)) { $good = $false; break } } }
        if ($good) { return $r }
    }
    return $null
}

$rAttr  = Find-Report @($U_LAMPCOUNT)                 @()
$rCtrl  = Find-Report @($U_AUTONOMOUS)                @()
$rRange = Find-Report @($U_IDSTART, $U_IDEND, $U_RED) @()
$rMulti = Find-Report @($U_RED, $U_LAMPID)            @($U_IDSTART)
$rReq   = Find-Report @($U_LAMPID)                    @($U_RED, $U_POSX)
$rResp  = Find-Report @($U_POSX)                      @()

Write-Host ""
Write-Host ("   attributes  : {0}" -f $(if ($rAttr)  { 'id ' + $rAttr.Rid }  else { 'MISSING' }))
Write-Host ("   control     : {0}" -f $(if ($rCtrl)  { 'id ' + $rCtrl.Rid }  else { 'MISSING' }))
Write-Host ("   range update: {0}" -f $(if ($rRange) { 'id ' + $rRange.Rid } else { 'MISSING' }))
Write-Host ("   multi update: {0}" -f $(if ($rMulti) { ('id {0} ({1} slots)' -f $rMulti.Rid, $rMulti.Usages[$U_RED]) } else { 'MISSING' }))
Write-Host ("   lamp request: {0}" -f $(if ($rReq)   { 'id ' + $rReq.Rid }   else { 'MISSING' }))
Write-Host ("   lamp reply  : {0}" -f $(if ($rResp)  { 'id ' + $rResp.Rid }  else { 'MISSING' }))

# ----------------------------------------------------------------------------
# 4. Helpers
# ----------------------------------------------------------------------------
function New-Rpt($r) {
    $len = if ($r.Type -eq 2) { $script:featLen } else { $script:outLen }
    $b = New-Object byte[] $len
    $b[0] = [byte]$r.Rid
    return ,$b
}
function Set-Val($r, $buf, [int]$usage, [int]$value) {
    $st = [HidNative]::HidP_SetUsageValue($r.Type, 0x59, 0, [uint16]$usage, [uint32]$value, $script:pp, $buf, [uint32]$buf.Length)
    if ($st -ne $script:HIDOK) {
        Write-Host ("     ! set 0x{0:X2} failed 0x{1:X8}" -f $usage, $st) -ForegroundColor DarkYellow
    }
}
function Send-Rpt($r, $buf) {
    if ($r.Type -eq 2) { return [HidNative]::HidD_SetFeature($script:h, $buf, $buf.Length) }
    $w = [uint32]0
    return [HidNative]::WriteFile($script:h, $buf, [uint32]$buf.Length, [ref]$w, [IntPtr]::Zero)
}
function Get-Val($r, $buf, [int]$usage) {
    $v = [uint32]0
    $st = [HidNative]::HidP_GetUsageValue($r.Type, 0x59, 0, [uint16]$usage, [ref]$v, $script:pp, $buf, [uint32]$buf.Length)
    if ($st -ne $script:HIDOK) { return $null }
    return [int]$v
}

# ----------------------------------------------------------------------------
# 5. Read the lamp map
# ----------------------------------------------------------------------------
$lampCount = 0
$maxR = 255; $maxG = 255; $maxB = 255; $maxI = 255

if ($rAttr) {
    $b = New-Rpt $rAttr
    if ([HidNative]::HidD_GetFeature($h, $b, $b.Length)) {
        $v = Get-Val $rAttr $b $U_LAMPCOUNT
        if ($v) { $lampCount = $v }
    }
}
Write-Host ""
Write-Host ("[4/5] Lamp count: {0}" -f $lampCount) -ForegroundColor Yellow

if ($lampCount -gt 0 -and $rReq -and $rResp) {
    $b = New-Rpt $rReq
    Set-Val $rReq $b $U_LAMPID 0
    [void](Send-Rpt $rReq $b)

    Write-Host "      id      X(um)      Y(um)   Rlv  Glv  Blv  Ilv" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $lampCount; $i++) {
        $q = New-Rpt $rReq
        Set-Val $rReq $q $U_LAMPID $i
        [void](Send-Rpt $rReq $q)

        $rb = New-Rpt $rResp
        if ([HidNative]::HidD_GetFeature($h, $rb, $rb.Length)) {
            $lid = Get-Val $rResp $rb $U_LAMPID
            $px  = Get-Val $rResp $rb $U_POSX
            $py  = Get-Val $rResp $rb $U_POSY
            $rl  = Get-Val $rResp $rb $U_REDLVL
            $gl  = Get-Val $rResp $rb $U_GRNLVL
            $bl  = Get-Val $rResp $rb $U_BLULVL
            $il  = Get-Val $rResp $rb $U_INTLVL
            if ($rl) { $maxR = $rl }; if ($gl) { $maxG = $gl }
            if ($bl) { $maxB = $bl }; if ($il) { $maxI = $il }
            Write-Host ("     {0,3}  {1,9}  {2,9}   {3,3}  {4,3}  {5,3}  {6,3}" -f $lid, $px, $py, $rl, $gl, $bl, $il)
        }
    }
}

if ($lampCount -le 0) { $lampCount = 16 }
$RMAX = [Math]::Max(1, $maxR); $GMAX = [Math]::Max(1, $maxG)
$BMAX = [Math]::Max(1, $maxB); $IMAX = [Math]::Max(1, $maxI)

# ----------------------------------------------------------------------------
# 6. Take control and run a visible test
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host "[5/5] Taking control and running a 30 second colour test." -ForegroundColor Yellow
Write-Host "      >>> CLICK ON ANOTHER WINDOW NOW (a browser, Notepad, anything). <<<" -ForegroundColor Magenta
Write-Host "      If the keyboard still changes colour while this window is NOT focused," -ForegroundColor Magenta
Write-Host "      then background control works and we are done." -ForegroundColor Magenta
Write-Host ""

if ($rCtrl) {
    $b = New-Rpt $rCtrl
    Set-Val $rCtrl $b $U_AUTONOMOUS 0
    $sent = Send-Rpt $rCtrl $b
    Write-Host ("  autonomous mode off -> {0}" -f $sent) -ForegroundColor DarkGray
}

function Set-Range([int]$from, [int]$to, [int]$rr, [int]$gg, [int]$bb, [int]$complete) {
    if (-not $script:rRange) { return $false }
    $b = New-Rpt $script:rRange
    Set-Val $script:rRange $b $U_FLAGS     $complete
    Set-Val $script:rRange $b $U_IDSTART   $from
    Set-Val $script:rRange $b $U_IDEND     $to
    Set-Val $script:rRange $b $U_RED       ([Math]::Min($rr, $script:RMAX))
    Set-Val $script:rRange $b $U_GREEN     ([Math]::Min($gg, $script:GMAX))
    Set-Val $script:rRange $b $U_BLUE      ([Math]::Min($bb, $script:BMAX))
    Set-Val $script:rRange $b $U_INTENSITY $script:IMAX
    return (Send-Rpt $script:rRange $b)
}

$steps = @(
    @{ n = 'ALL RED';    r = 255; g = 0;   b = 0   },
    @{ n = 'ALL GREEN';  r = 0;   g = 255; b = 0   },
    @{ n = 'ALL BLUE';   r = 0;   g = 0;   b = 255 },
    @{ n = 'ALL WHITE';  r = 255; g = 255; b = 255 },
    @{ n = 'ALL OFF';    r = 0;   g = 0;   b = 0   }
)
foreach ($s in $steps) {
    $sent = Set-Range 0 ($lampCount - 1) $s.r $s.g $s.b 1
    Write-Host ("  {0,-10} sent={1}" -f $s.n, $sent)
    Start-Sleep -Milliseconds 1800
}

Write-Host ""
Write-Host "  Now a moving sweep across the zones for 12 seconds..." -ForegroundColor Cyan
$deadline = (Get-Date).AddSeconds(12)
$pos = 0
while ((Get-Date) -lt $deadline) {
    for ($i = 0; $i -lt $lampCount; $i++) {
        $d = [Math]::Abs($i - $pos)
        $f = [Math]::Max(0.0, 1.0 - ($d / 3.0))
        $last = if ($i -eq ($lampCount - 1)) { 1 } else { 0 }
        [void](Set-Range $i $i ([int](255 * $f)) ([int](40 * $f)) ([int](160 * $f)) $last)
    }
    $pos = ($pos + 1) % $lampCount
    Start-Sleep -Milliseconds 70
}

[void](Set-Range 0 ($lampCount - 1) 0 90 255 1)

Write-Host ""
Write-Host "  Test finished. Keyboard should be sitting on blue." -ForegroundColor Green
Write-Host ""
Write-Host "  Leaving the device in host-control mode." -ForegroundColor DarkGray
Write-Host "  (Run  Find-Lamps.ps1 -Restore  or just reboot to give it back to the firmware.)" -ForegroundColor DarkGray

if ($args -contains '-Restore' -and $rCtrl) {
    $b = New-Rpt $rCtrl
    Set-Val $rCtrl $b $U_AUTONOMOUS 1
    [void](Send-Rpt $rCtrl $b)
    Write-Host "  Autonomous mode restored." -ForegroundColor DarkGray
}

[void][HidNative]::HidD_FreePreparsedData($pp)
[void][HidNative]::CloseHandle($h)

Write-Host ""
Write-Host "==================== DONE ====================" -ForegroundColor Cyan
Write-Host ""
