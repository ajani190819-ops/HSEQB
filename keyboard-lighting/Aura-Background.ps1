#requires -Version 5.1
<#
  AURA-BACKGROUND  v2
  Smooth animated keyboard lighting, direct HID LampArray control.
  Keeps running when the window is not focused. No Dynamic Lighting.

  WHAT CHANGED IN v2
    * Uses LampMultiUpdateReport (8 zones per USB transfer) instead of one
      transfer per zone. 16 transfers per frame became 2. That was the stutter.
    * Buffers are allocated once and reused, not rebuilt every frame.
    * 1 ms timer resolution and an absolute frame schedule, so frames land
      evenly instead of drifting.
    * New "gradient" effect: your own list of colours, scrolling.
    * -Custom lets you load your own effect from a file.

  QUICK USE
    .\Aura-Background.ps1 -Effect gradient -Colors "#FF0000,#FFA500,#FFFF00"
    .\Aura-Background.ps1 -Effect rainbow -Fps 60
    .\Aura-Background.ps1 -Custom .\MyEffect.ps1
    .\Aura-Background.ps1 -Effect off
    .\Aura-Background.ps1 -Restore
#>

[CmdletBinding()]
param(
    [ValidateSet('wave','rainbow','breathe','comet','pulse','scanner','fire',
                 'gradient','static','off')]
    [string]$Effect = 'gradient',

    # Gradient colour stops, comma separated. Any number of them.
    [string]$Colors = '#FF0000,#FF00FF,#0000FF,#00FFFF,#00FF00,#FFFF00,#FF0000',

    [string]$Color  = '#00B4FF',
    [string]$Color2 = '#FF0066',

    [ValidateRange(0.01, 50.0)]
    [double]$Speed = 1.0,

    [ValidateRange(0.0, 1.0)]
    [double]$Brightness = 1.0,

    [ValidateRange(5, 120)]
    [int]$Fps = 45,

    # Path to a .ps1 file that returns a scriptblock. See MyEffect.ps1.
    [string]$Custom,

    # Mirror the pattern from the centre outwards.
    [switch]$Mirror,

    # Reverse the scroll direction.
    [switch]$Reverse,

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
  [DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint p);
  [DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint p);
}
'@
}

$HIDGUID='{4d1e55b2-f16f-11cf-88cb-001111000030}'
$INVALID=[IntPtr](-1); $HIDOK=0x00110000
$GENRW=[uint32]3221225472; $GENW=[uint32]1073741824
$SHARERW=[uint32]3; $OPENEXIST=[uint32]3

$U_LAMPCOUNT=0x03; $U_LAMPID=0x21; $U_POSX=0x23
$U_REDLVL=0x28; $U_GRNLVL=0x29; $U_BLULVL=0x2A; $U_INTLVL=0x2B
$U_RED=0x51; $U_GREEN=0x52; $U_BLUE=0x53; $U_INTENSITY=0x54; $U_FLAGS=0x55
$U_IDSTART=0x61; $U_IDEND=0x62; $U_AUTONOMOUS=0x71

# ============================================================================
# FIND DEVICE
# ============================================================================
Say ""
Say ("AURA-BACKGROUND v2   effect={0}  fps={1}  speed={2}" -f $Effect,$Fps,$Speed) 'Cyan'
Say ""

$devPath=$null
foreach ($d in (Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'HID%'" -ErrorAction SilentlyContinue)) {
    $id=$d.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $p='\\?\'+$id.Replace('\','#').ToLower()+'#'+$HIDGUID
    $t=[HidNative]::CreateFileW($p,[uint32]0,$SHARERW,[IntPtr]::Zero,$OPENEXIST,[uint32]0,[IntPtr]::Zero)
    if ($t -eq $INVALID) { continue }
    $tpp=[IntPtr]::Zero
    if ([HidNative]::HidD_GetPreparsedData($t,[ref]$tpp)) {
        $c=New-Object byte[] 64
        if ([HidNative]::HidP_GetCaps($tpp,$c) -eq $HIDOK -and [BitConverter]::ToUInt16($c,2) -eq 0x59) {
            $devPath=$p; Say ("  Device: {0}" -f $d.Name) 'Green'
        }
        [void][HidNative]::HidD_FreePreparsedData($tpp)
    }
    [void][HidNative]::CloseHandle($t)
    if ($devPath) { break }
}
if (-not $devPath) { Write-Host "  No LampArray HID interface found." -ForegroundColor Red; return }

$h=[HidNative]::CreateFileW($devPath,$GENRW,$SHARERW,[IntPtr]::Zero,$OPENEXIST,[uint32]0,[IntPtr]::Zero)
if ($h -eq $INVALID) { $h=[HidNative]::CreateFileW($devPath,$GENW,$SHARERW,[IntPtr]::Zero,$OPENEXIST,[uint32]0,[IntPtr]::Zero) }
if ($h -eq $INVALID) {
    Write-Host ("  Cannot open device (err {0}). Run PowerShell as Administrator." -f [Runtime.InteropServices.Marshal]::GetLastWin32Error()) -ForegroundColor Red
    return
}

$pp=[IntPtr]::Zero
[void][HidNative]::HidD_GetPreparsedData($h,[ref]$pp)
$caps=New-Object byte[] 64
[void][HidNative]::HidP_GetCaps($pp,$caps)
$featLen=[int][BitConverter]::ToUInt16($caps,8)
$outLen =[int][BitConverter]::ToUInt16($caps,6)

$reports=@{}
function Read-ValueCaps([int]$type,[int]$count) {
    if ($count -le 0) { return }
    $n=[uint16]$count; $buf=New-Object byte[] (72*$count)
    if ([HidNative]::HidP_GetValueCaps($type,$buf,[ref]$n,$script:pp) -ne $script:HIDOK) { return }
    for ($i=0;$i -lt [int]$n;$i++) {
        $o=$i*72
        if ([BitConverter]::ToUInt16($buf,$o) -ne 0x59) { continue }
        $rid=[int]$buf[$o+2]; $rc=[int][BitConverter]::ToUInt16($buf,$o+20)
        $isR=$buf[$o+12]
        $u1=[int][BitConverter]::ToUInt16($buf,$o+56)
        $u2=if ($isR -ne 0) { [int][BitConverter]::ToUInt16($buf,$o+58) } else { $u1 }
        $key="{0}:{1}" -f $type,$rid
        if (-not $script:reports.ContainsKey($key)) { $script:reports[$key]=@{Type=$type;Rid=$rid;Usages=@{}} }
        for ($u=$u1;$u -le $u2;$u++) { $script:reports[$key].Usages[$u]=$rc }
    }
}
Read-ValueCaps 2 ([int][BitConverter]::ToUInt16($caps,60))
Read-ValueCaps 1 ([int][BitConverter]::ToUInt16($caps,54))

function Find-Report([int[]]$must,[int[]]$mustNot) {
    foreach ($k in ($script:reports.Keys|Sort-Object)) {
        $r=$script:reports[$k]; $good=$true
        foreach ($m in $must) { if (-not $r.Usages.ContainsKey($m)) { $good=$false;break } }
        if ($good -and $mustNot) { foreach ($m in $mustNot) { if ($r.Usages.ContainsKey($m)) { $good=$false;break } } }
        if ($good) { return $r }
    }
    return $null
}
$rAttr =Find-Report @($U_LAMPCOUNT) @()
$rCtrl =Find-Report @($U_AUTONOMOUS) @()
$rRange=Find-Report @($U_IDSTART,$U_IDEND,$U_RED) @()
$rMulti=Find-Report @($U_RED,$U_LAMPID) @($U_IDSTART)
$rReq  =Find-Report @($U_LAMPID) @($U_RED,$U_POSX)
$rResp =Find-Report @($U_POSX) @()
if (-not $rRange -and -not $rMulti) { Write-Host "  No usable update report." -ForegroundColor Red; return }

function Rpt-Len($r) { if ($r.Type -eq 2) { return $script:featLen } else { return $script:outLen } }
function New-Rpt($r) { $b=New-Object byte[] (Rpt-Len $r); $b[0]=[byte]$r.Rid; return ,$b }
function Set-Val($r,$buf,[int]$usage,[int]$value) {
    [void][HidNative]::HidP_SetUsageValue($r.Type,0x59,0,[uint16]$usage,[uint32]$value,$script:pp,$buf,[uint32]$buf.Length)
}
function Send-Rpt($r,$buf) {
    if ($r.Type -eq 2) { return [HidNative]::HidD_SetFeature($script:h,$buf,$buf.Length) }
    $w=[uint32]0
    return [HidNative]::WriteFile($script:h,$buf,[uint32]$buf.Length,[ref]$w,[IntPtr]::Zero)
}
function Get-Val($r,$buf,[int]$usage) {
    $v=[uint32]0
    if ([HidNative]::HidP_GetUsageValue($r.Type,0x59,0,[uint16]$usage,[ref]$v,$script:pp,$buf,[uint32]$buf.Length) -ne $script:HIDOK) { return $null }
    return [int]$v
}

# ---- lamp count + channel depth ----
$lampCount=0; $RMAX=255;$GMAX=255;$BMAX=255;$IMAX=255
if ($rAttr) {
    $b=New-Rpt $rAttr
    if ([HidNative]::HidD_GetFeature($h,$b,$b.Length)) { $v=Get-Val $rAttr $b $U_LAMPCOUNT; if ($v) { $lampCount=$v } }
}
if ($lampCount -le 0) { $lampCount=16 }

# ---- zone order by physical X, and channel depth ----
$order=@(0..($lampCount-1))
if ($rReq -and $rResp) {
    $pos=New-Object object[] $lampCount
    for ($i=0;$i -lt $lampCount;$i++) {
        $q=New-Rpt $rReq; Set-Val $rReq $q $U_LAMPID $i; [void](Send-Rpt $rReq $q)
        $rb=New-Rpt $rResp; $x=$i*1000
        if ([HidNative]::HidD_GetFeature($h,$rb,$rb.Length)) {
            $gx=Get-Val $rResp $rb $U_POSX; if ($null -ne $gx) { $x=$gx }
            if ($i -eq 0) {
                $v=Get-Val $rResp $rb $U_REDLVL; if ($v) { $RMAX=$v }
                $v=Get-Val $rResp $rb $U_GRNLVL; if ($v) { $GMAX=$v }
                $v=Get-Val $rResp $rb $U_BLULVL; if ($v) { $BMAX=$v }
                $v=Get-Val $rResp $rb $U_INTLVL; if ($v) { $IMAX=$v }
            }
        }
        $pos[$i]=[pscustomobject]@{Idx=$i;X=$x}
    }
    $order=@($pos|Sort-Object X|ForEach-Object{$_.Idx})
}
$RMAX=[Math]::Max(1,$RMAX); $GMAX=[Math]::Max(1,$GMAX)
$BMAX=[Math]::Max(1,$BMAX); $IMAX=[Math]::Max(1,$IMAX)

# ---- take control ----
if ($rCtrl) { $b=New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 0; [void](Send-Rpt $rCtrl $b) }

if ($Restore) {
    if ($rCtrl) { $b=New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 1; [void](Send-Rpt $rCtrl $b)
        Say "  Autonomous mode restored." 'Green' }
    [void][HidNative]::HidD_FreePreparsedData($pp); [void][HidNative]::CloseHandle($h); return
}

# ============================================================================
# FAST PATH: discover the byte layout of LampMultiUpdateReport
# ============================================================================
# We probe by setting one usage at a time on a zeroed buffer and seeing which
# byte moves. That respects the real descriptor instead of assuming a layout.
$fast=$false; $slots=1
$offId=-1;$offR=-1;$offG=-1;$offB=-1;$offI=-1;$offCnt=-1;$offFlg=-1

function Probe-Off($r,[int]$usage,[int]$val) {
    $len=Rpt-Len $r
    $b=New-Object byte[] $len; $b[0]=[byte]$r.Rid
    $st=[HidNative]::HidP_SetUsageValue($r.Type,0x59,0,[uint16]$usage,[uint32]$val,$script:pp,$b,[uint32]$len)
    if ($st -ne $script:HIDOK) { return -1 }
    for ($i=1;$i -lt $len;$i++) { if ($b[$i] -ne 0) { return $i } }
    return -1
}

if ($rMulti) {
    $slots=[int]$rMulti.Usages[$U_RED]
    if ($slots -lt 1) { $slots=1 }
    # Probe with value 1 so we never exceed any field's logical maximum.
    $offCnt=Probe-Off $rMulti $U_LAMPCOUNT 1
    $offFlg=Probe-Off $rMulti $U_FLAGS     1
    $offId =Probe-Off $rMulti $U_LAMPID    1
    $offR  =Probe-Off $rMulti $U_RED       1
    $offG  =Probe-Off $rMulti $U_GREEN     1
    $offB  =Probe-Off $rMulti $U_BLUE      1
    $offI  =Probe-Off $rMulti $U_INTENSITY 1

    $mlen = Rpt-Len $rMulti
    if ($offId -ge 0 -and $offR -ge 0 -and $offG -ge 0 -and $offB -ge 0 -and
        $offI -ge 0 -and $offCnt -ge 0 -and $offFlg -ge 0 -and
        ($offI + $slots) -le $mlen -and
        $offR -eq ($offId + $slots*2) -and
        $offG -eq ($offR + $slots) -and
        $offB -eq ($offG + $slots) -and
        $offI -eq ($offB + $slots)) { $fast=$true }

    # HidP_SetUsageValue refuses value arrays, so probing can legitimately
    # fail on a perfectly good device. If the report length matches the HID
    # spec layout exactly, trust the spec and use those offsets.
    if (-not $fast) {
        $specLen = 3 + $slots*2 + $slots*4
        if ($mlen -eq $specLen) {
            $offCnt = 1
            $offFlg = 2
            $offId  = 3
            $offR   = $offId + $slots*2
            $offG   = $offR + $slots
            $offB   = $offG + $slots
            $offI   = $offB + $slots
            $fast   = $true
            Say ("  Using HID spec layout for report {0} ({1} bytes, {2} slots)." -f $rMulti.Rid,$mlen,$slots) 'DarkGray'
        }
    }
}

$batches=[Math]::Ceiling($lampCount/[double]$slots)
if ($fast) {
    Say ("  {0} zones, {1} slots/report, {2} transfers per frame" -f $lampCount,$slots,$batches) 'Green'
} else {
    Say ("  {0} zones, per-zone writes ({1} transfers per frame)" -f $lampCount,$lampCount) 'DarkYellow'
}

# Pre-build one reusable buffer per batch.
$bufs=$null
if ($fast) {
    $mlen=Rpt-Len $rMulti
    $bufs=New-Object object[] $batches
    for ($bi=0;$bi -lt $batches;$bi++) {
        $b=New-Object byte[] $mlen
        $b[0]=[byte]$rMulti.Rid
        $first=$bi*$slots
        $n=[Math]::Min($slots,$lampCount-$first)
        $b[$offCnt]=[byte]$n
        for ($s=0;$s -lt $n;$s++) {
            $lid=$first+$s
            $b[$offId+$s*2]=[byte]($lid -band 0xFF)
            $b[$offId+$s*2+1]=[byte](($lid -shr 8) -band 0xFF)
            $b[$offI+$s]=[byte]$IMAX
        }
        $bufs[$bi]=$b
    }
}

# frame buffers
$fr=New-Object int[] $lampCount
$fg=New-Object int[] $lampCount
$fb=New-Object int[] $lampCount

function Push-Frame {
    if ($script:fast) {
        $last=$script:batches-1
        for ($bi=0;$bi -lt $script:batches;$bi++) {
            $b=$script:bufs[$bi]
            $first=$bi*$script:slots
            $n=[Math]::Min($script:slots,$script:lampCount-$first)
            for ($s=0;$s -lt $n;$s++) {
                $i=$first+$s
                $b[$script:offR+$s]=[byte](($script:fr[$i]*$script:RMAX)/255)
                $b[$script:offG+$s]=[byte](($script:fg[$i]*$script:GMAX)/255)
                $b[$script:offB+$s]=[byte](($script:fb[$i]*$script:BMAX)/255)
            }
            if ($bi -eq $last) { $b[$script:offFlg]=[byte]1 } else { $b[$script:offFlg]=[byte]0 }
            [void][HidNative]::HidD_SetFeature($script:h,$b,$b.Length)
        }
    } else {
        for ($i=0;$i -lt $script:lampCount;$i++) {
            $b=New-Rpt $script:rRange
            $flag=0; if ($i -eq ($script:lampCount-1)) { $flag=1 }
            Set-Val $script:rRange $b $U_FLAGS $flag
            Set-Val $script:rRange $b $U_IDSTART $i
            Set-Val $script:rRange $b $U_IDEND   $i
            Set-Val $script:rRange $b $U_RED     ([int](($script:fr[$i]*$script:RMAX)/255))
            Set-Val $script:rRange $b $U_GREEN   ([int](($script:fg[$i]*$script:GMAX)/255))
            Set-Val $script:rRange $b $U_BLUE    ([int](($script:fb[$i]*$script:BMAX)/255))
            Set-Val $script:rRange $b $U_INTENSITY $script:IMAX
            [void](Send-Rpt $script:rRange $b)
        }
    }
}

# Set-Zone takes a SLOT (0 = leftmost) and maps it to the real lamp id.
function Set-Zone([int]$slot,[double]$r,[double]$g,[double]$b) {
    if ($slot -lt 0 -or $slot -ge $script:lampCount) { return }
    $q=$slot
    if ($script:Mirror) {
        $half=[int][Math]::Ceiling($script:lampCount/2.0)
        $q=if ($slot -lt $half) { $half-1-$slot } else { $slot-$half }
        if ($q -ge $script:lampCount) { $q=$script:lampCount-1 }
    }
    $i=$script:order[$q]
    $k=$script:Brightness
    $rr=[int]($r*$k); $gg=[int]($g*$k); $bb=[int]($b*$k)
    if ($rr -lt 0){$rr=0}elseif($rr -gt 255){$rr=255}
    if ($gg -lt 0){$gg=0}elseif($gg -gt 255){$gg=255}
    if ($bb -lt 0){$bb=0}elseif($bb -gt 255){$bb=255}
    $script:fr[$i]=$rr; $script:fg[$i]=$gg; $script:fb[$i]=$bb
}

# ============================================================================
# COLOUR
# ============================================================================
function ConvertFrom-Hex([string]$hex) {
    $s=$hex.Trim().TrimStart('#')
    if ($s.Length -eq 3) { $s="$($s[0])$($s[0])$($s[1])$($s[1])$($s[2])$($s[2])" }
    if ($s.Length -ne 6) { throw "Bad colour '$hex'. Use #RRGGBB, e.g. #FF8800." }
    return ,@([Convert]::ToInt32($s.Substring(0,2),16),
              [Convert]::ToInt32($s.Substring(2,2),16),
              [Convert]::ToInt32($s.Substring(4,2),16))
}
function Convert-Hsv([double]$hDeg,[double]$s,[double]$v) {
    $hDeg=$hDeg%360.0; if ($hDeg -lt 0) { $hDeg+=360.0 }
    $c=$v*$s; $x=$c*(1.0-[Math]::Abs((($hDeg/60.0)%2.0)-1.0)); $m=$v-$c
    switch ([int][Math]::Floor($hDeg/60.0)) {
        0 {$r=$c;$g=$x;$b=0} 1 {$r=$x;$g=$c;$b=0} 2 {$r=0;$g=$c;$b=$x}
        3 {$r=0;$g=$x;$b=$c} 4 {$r=$x;$g=0;$b=$c} default {$r=$c;$g=0;$b=$x}
    }
    return ,@([int](255*($r+$m)),[int](255*($g+$m)),[int](255*($b+$m)))
}

$C1=ConvertFrom-Hex $Color
$C2=ConvertFrom-Hex $Color2

# Build a 720-step lookup table from the gradient stops. Done once.
$LUTN=720
$lutR=New-Object int[] $LUTN
$lutG=New-Object int[] $LUTN
$lutB=New-Object int[] $LUTN
$stops=@()
foreach ($cs in ($Colors -split ',')) { if ($cs.Trim()) { $stops+=,(ConvertFrom-Hex $cs) } }
if ($stops.Count -eq 0) { $stops=@($C1,$C2) }
if ($stops.Count -eq 1) { $stops=@($stops[0],$stops[0]) }
for ($k=0;$k -lt $LUTN;$k++) {
    $f=($k/[double]$LUTN)*($stops.Count-1)
    $a=[int][Math]::Floor($f); if ($a -ge $stops.Count-1) { $a=$stops.Count-2 }
    $u=$f-$a
    $lutR[$k]=[int]($stops[$a][0]+($stops[$a+1][0]-$stops[$a][0])*$u)
    $lutG[$k]=[int]($stops[$a][1]+($stops[$a+1][1]-$stops[$a][1])*$u)
    $lutB[$k]=[int]($stops[$a][2]+($stops[$a+1][2]-$stops[$a][2])*$u)
}

# ============================================================================
# CUSTOM EFFECT
# ============================================================================
$CustomBlock=$null
if ($Custom) {
    if (-not (Test-Path $Custom)) { Write-Host ("  Custom file not found: {0}" -f $Custom) -ForegroundColor Red; return }
    $CustomBlock = [scriptblock]::Create((Get-Content -Raw $Custom)).Invoke() | Select-Object -Last 1
    if ($CustomBlock -is [System.Management.Automation.PSObject]) { $CustomBlock = $CustomBlock.BaseObject }
    if ($CustomBlock -isnot [scriptblock]) {
        Write-Host "  Custom file must END with a scriptblock, e.g.  { param($t,$N) ... }" -ForegroundColor Red
        return
    }
    Say ("  Custom effect loaded from {0}" -f (Split-Path -Leaf $Custom)) 'Green'
}

# ============================================================================
# ONE-SHOT
# ============================================================================
if (-not $CustomBlock -and ($Effect -eq 'off' -or $Effect -eq 'static')) {
    for ($i=0;$i -lt $lampCount;$i++) {
        if ($Effect -eq 'off') { Set-Zone $i 0 0 0 } else { Set-Zone $i $C1[0] $C1[1] $C1[2] }
    }
    Push-Frame
    Say ("  {0} applied." -f $Effect.ToUpper()) 'Green'
    [void][HidNative]::HidD_FreePreparsedData($pp); [void][HidNative]::CloseHandle($h); return
}

# ============================================================================
# LOOP
# ============================================================================
Say ""
Say "  Running. Works whether or not this window is focused. Ctrl+C to stop." 'Green'
Say ""

[void][HidNative]::timeBeginPeriod(1)
$sw=[Diagnostics.Stopwatch]::StartNew()
$tps=[Diagnostics.Stopwatch]::Frequency
$frameTicks=[long]($tps/$Fps)
$next=$sw.ElapsedTicks+$frameTicks
$rand=New-Object System.Random
$heat=New-Object double[] $lampCount
$dir=if ($Reverse) { -1.0 } else { 1.0 }

try {
    while ($true) {
        $t=($sw.ElapsedTicks/[double]$tps)*$Speed
        $N=$lampCount

        if ($CustomBlock) {
            & $CustomBlock $t $N
        }
        else {
        switch ($Effect) {
            'gradient' {
                $scroll=$t*120.0*$dir
                for ($i=0;$i -lt $N;$i++) {
                    $k=[int](((($i/[double]$N)*$LUTN)+$scroll)%$LUTN)
                    if ($k -lt 0) { $k+=$LUTN }
                    Set-Zone $i $lutR[$k] $lutG[$k] $lutB[$k]
                }
            }
            'wave' {
                for ($i=0;$i -lt $N;$i++) {
                    $ph=($t*1.2*$dir)-($i/[double]$N)*2.0
                    $w=[Math]::Pow((1.0+[Math]::Sin($ph*[Math]::PI))/2.0,2.0)
                    Set-Zone $i ($C1[0]*$w+$C2[0]*(1-$w)*0.15) ($C1[1]*$w+$C2[1]*(1-$w)*0.15) ($C1[2]*$w+$C2[2]*(1-$w)*0.15)
                }
            }
            'rainbow' {
                for ($i=0;$i -lt $N;$i++) {
                    $c=Convert-Hsv ((($i/[double]$N)*360.0)+($t*90.0*$dir)) 1.0 1.0
                    Set-Zone $i $c[0] $c[1] $c[2]
                }
            }
            'breathe' {
                $w=0.04+0.96*[Math]::Pow((1.0+[Math]::Sin($t*1.6*[Math]::PI))/2.0,2.2)
                for ($i=0;$i -lt $N;$i++) { Set-Zone $i ($C1[0]*$w) ($C1[1]*$w) ($C1[2]*$w) }
            }
            'comet' {
                $head=($t*6.0)%$N
                for ($i=0;$i -lt $N;$i++) {
                    $d=$head-$i; if ($d -lt 0) { $d+=$N }
                    $w=[Math]::Exp(-$d*0.9)
                    Set-Zone $i ($C1[0]*$w) ($C1[1]*$w) ($C1[2]*$w)
                }
            }
            'pulse' {
                $w=[Math]::Exp(-($t%1.0)*4.5)
                $c=Convert-Hsv ([Math]::Floor($t)*47.0) 1.0 1.0
                for ($i=0;$i -lt $N;$i++) { Set-Zone $i ($c[0]*$w) ($c[1]*$w) ($c[2]*$w) }
            }
            'scanner' {
                $span=($N-1)*2.0; $p=($t*7.0)%$span
                if ($p -gt ($N-1)) { $p=$span-$p }
                for ($i=0;$i -lt $N;$i++) {
                    $w=[Math]::Max(0.0,1.0-([Math]::Abs($i-$p)/2.2)); $w=$w*$w
                    Set-Zone $i ($C1[0]*$w) ($C1[1]*$w) ($C1[2]*$w)
                }
            }
            'fire' {
                for ($i=0;$i -lt $N;$i++) {
                    $heat[$i]=$heat[$i]*0.86+$rand.NextDouble()*0.30
                    if ($heat[$i] -gt 1.0) { $heat[$i]=1.0 }
                    $v=$heat[$i]
                    Set-Zone $i (255*$v) (90*$v*$v) (10*$v*$v*$v)
                }
            }
        }
        }

        Push-Frame

        $remain=$next-$sw.ElapsedTicks
        if ($remain -gt 0) {
            $ms=[int]($remain*1000/$tps)
            if ($ms -gt 0) { Start-Sleep -Milliseconds $ms }
        } else {
            $next=$sw.ElapsedTicks   # we fell behind; resync instead of spiralling
        }
        $next+=$frameTicks
    }
}
finally {
    [void][HidNative]::timeEndPeriod(1)
    Say ""
    Say "  Stopping. Handing lighting back to the keyboard firmware." 'Yellow'
    if ($rCtrl) { $b=New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 1; [void](Send-Rpt $rCtrl $b) }
    [void][HidNative]::HidD_FreePreparsedData($pp)
    [void][HidNative]::CloseHandle($h)
}
