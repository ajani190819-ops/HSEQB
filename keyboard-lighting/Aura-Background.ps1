#requires -Version 5.1
<#
  AURA-BACKGROUND  v3
  Smooth animated keyboard lighting, direct HID LampArray control.

  WHAT CHANGED IN v3
    * The animation loop now runs in COMPILED C# on its own high-priority
      thread. PowerShell only sets things up. This is the real fix for the
      stutter: an interpreted loop cannot hold a 16 ms frame budget.
    * Frame pacing is sleep-then-spin, so frames land on time instead of
      drifting by whatever Start-Sleep felt like.
    * The gradient is now CYCLIC. The last colour blends back into the
      first, so a colour leaving the right edge returns on the left with
      no seam.

  QUICK USE
    .\Aura-Background.ps1 -Effect gradient -Colors "#FF0000,#FF7F00,#FFFF00,#00FF00,#0000FF,#8B00FF"
    .\Aura-Background.ps1 -Effect rainbow -Fps 60
    .\Aura-Background.ps1 -Effect off
    .\Aura-Background.ps1 -Restore
#>

[CmdletBinding()]
param(
    [ValidateSet('wave','rainbow','breathe','comet','pulse','scanner','fire',
                 'gradient','static','off')]
    [string]$Effect = 'gradient',

    [string]$Colors = '#FF0000,#FF7F00,#FFFF00,#00FF00,#0000FF,#8B00FF',
    [string]$Color  = '#00B4FF',
    [string]$Color2 = '#FF0066',

    [ValidateRange(0.01, 50.0)]
    [double]$Speed = 1.0,

    [ValidateRange(0.0, 1.0)]
    [double]$Brightness = 1.0,

    [ValidateRange(5, 144)]
    [int]$Fps = 60,

    [string]$Custom,

    [switch]$Mirror,
    [switch]$Reverse,
    [switch]$Restore,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
function Say($msg, $col = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $col } }

# ============================================================================
# NATIVE + COMPILED ENGINE
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

if (-not ('LampEngine' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
using System.Diagnostics;

public class LampEngine {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  static extern IntPtr CreateFileW(string p, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)]
  static extern bool CloseHandle(IntPtr h);
  [DllImport("hid.dll", SetLastError=true)]
  static extern bool HidD_SetFeature(IntPtr h, byte[] b, int len);
  [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint p);
  [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint p);

  // ---- set these from PowerShell before Start() ----
  public string DevicePath = "";
  public int    LampCount  = 16;
  public int[]  Order;                 // slot -> real lamp id
  public int    ReportId   = 4;
  public int    Slots      = 8;
  public int    ReportLen  = 51;
  public int    OffCount, OffFlags, OffId, OffR, OffG, OffB, OffI;
  public int    MaxR = 255, MaxG = 255, MaxB = 255, MaxI = 255;

  public string Effect     = "gradient";
  public double Speed      = 1.0;
  public double Brightness = 1.0;
  public int    Fps        = 60;
  public bool   Mirror     = false;
  public bool   Reverse    = false;
  public int[]  PalR, PalG, PalB;

  // Normalised physical position of each slot, 0.0 = far left, 1.0 = far right.
  // Position-based effects use this instead of the slot index, because the
  // zones are NOT evenly spaced across the keyboard.
  public double[] SlotPos;

  public string LastError = "";

  IntPtr h = IntPtr.Zero;
  Thread th;
  volatile bool running;
  byte[][] bufs;
  int nbatch;
  int[] fr, fg, fb;
  double[] heat;
  Random rnd = new Random();

  // LampArrayControl report, prebuilt by PowerShell. Sending this on OUR
  // OWN handle re-asserts host control: some firmware drops back to
  // autonomous mode when the handle that disabled it is closed, which
  // makes every update silently do nothing.
  public byte[] CtrlOff = null;

  public bool Open() {
    h = CreateFileW(DevicePath, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (h == (IntPtr)(-1)) h = CreateFileW(DevicePath, 0x40000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (h == (IntPtr)(-1)) { LastError = "CreateFile failed: " + Marshal.GetLastWin32Error(); h = IntPtr.Zero; return false; }

    if (CtrlOff != null) HidD_SetFeature(h, CtrlOff, CtrlOff.Length);

    nbatch = (LampCount + Slots - 1) / Slots;
    bufs = new byte[nbatch][];
    for (int bi = 0; bi < nbatch; bi++) {
      byte[] b = new byte[ReportLen];
      b[0] = (byte)ReportId;
      int first = bi * Slots;
      int n = Math.Min(Slots, LampCount - first);
      b[OffCount] = (byte)n;
      for (int s = 0; s < n; s++) {
        int lid = first + s;
        b[OffId + s*2]     = (byte)(lid & 0xFF);
        b[OffId + s*2 + 1] = (byte)((lid >> 8) & 0xFF);
        b[OffI + s]        = (byte)MaxI;
      }
      bufs[bi] = b;
    }
    fr = new int[LampCount]; fg = new int[LampCount]; fb = new int[LampCount];
    pr = new int[LampCount]; pg = new int[LampCount]; pb = new int[LampCount];
    for (int i = 0; i < LampCount; i++) { pr[i] = -1; pg[i] = -1; pb[i] = -1; }
    heat = new double[LampCount];
    if (SlotPos == null || SlotPos.Length != LampCount) {
      SlotPos = new double[LampCount];
      for (int i = 0; i < LampCount; i++)
        SlotPos[i] = (LampCount > 1) ? (i / (double)(LampCount - 1)) : 0.0;
    }
    return true;
  }

  void SetZone(int slot, double r, double g, double b) {
    if (slot < 0 || slot >= LampCount) return;
    int q = slot;
    if (Mirror) {
      int half = (LampCount + 1) / 2;
      q = (slot < half) ? (half - 1 - slot) : (slot - half);
      if (q >= LampCount) q = LampCount - 1;
    }
    int i = Order[q];
    int rr = (int)(r * Brightness); if (rr < 0) rr = 0; else if (rr > 255) rr = 255;
    int gg = (int)(g * Brightness); if (gg < 0) gg = 0; else if (gg > 255) gg = 255;
    int bb = (int)(b * Brightness); if (bb < 0) bb = 0; else if (bb > 255) bb = 255;
    fr[i] = rr; fg[i] = gg; fb[i] = bb;
  }

  int[] pr, pg, pb;   // last values actually sent

  void Push() { Push(false); }

  void Push(bool force) {
    // Skip the whole frame if not a single channel byte changed. Sending
    // identical frames gains nothing and adds bus traffic that shows up
    // as flicker.
    if (!force) {
      bool same = true;
      for (int i = 0; i < LampCount; i++) {
        if (fr[i] != pr[i] || fg[i] != pg[i] || fb[i] != pb[i]) { same = false; break; }
      }
      if (same) return;
    }

    int last = nbatch - 1;
    for (int bi = 0; bi < nbatch; bi++) {
      byte[] b = bufs[bi];
      int first = bi * Slots;
      int n = Math.Min(Slots, LampCount - first);
      for (int s = 0; s < n; s++) {
        int i = first + s;
        b[OffR + s] = (byte)(fr[i] * MaxR / 255);
        b[OffG + s] = (byte)(fg[i] * MaxG / 255);
        b[OffB + s] = (byte)(fb[i] * MaxB / 255);
      }
      b[OffFlags] = (bi == last) ? (byte)1 : (byte)0;
      HidD_SetFeature(h, b, b.Length);
    }

    for (int i = 0; i < LampCount; i++) { pr[i] = fr[i]; pg[i] = fg[i]; pb[i] = fb[i]; }
  }

  static void Hsv(double hDeg, double s, double v, out double r, out double g, out double b) {
    hDeg = hDeg % 360.0; if (hDeg < 0) hDeg += 360.0;
    double c = v * s;
    double x = c * (1.0 - Math.Abs(((hDeg / 60.0) % 2.0) - 1.0));
    double m = v - c;
    double rr, gg, bb;
    int seg = (int)Math.Floor(hDeg / 60.0);
    if      (seg == 0) { rr=c; gg=x; bb=0; }
    else if (seg == 1) { rr=x; gg=c; bb=0; }
    else if (seg == 2) { rr=0; gg=c; bb=x; }
    else if (seg == 3) { rr=0; gg=x; bb=c; }
    else if (seg == 4) { rr=x; gg=0; bb=c; }
    else               { rr=c; gg=0; bb=x; }
    r = 255*(rr+m); g = 255*(gg+m); b = 255*(bb+m);
  }

  // Cyclic palette sample. f is 0..1 around the whole loop.
  void Pal(double f, out double r, out double g, out double b) {
    int pc = PalR.Length;
    f = f % 1.0; if (f < 0) f += 1.0;
    double x = f * pc;
    int a = (int)Math.Floor(x);
    double u = x - a;
    int n2 = (a + 1) % pc;
    a = a % pc;
    r = PalR[a] + (PalR[n2] - PalR[a]) * u;
    g = PalG[a] + (PalG[n2] - PalG[a]) * u;
    b = PalB[a] + (PalB[n2] - PalB[a]) * u;
  }

  void Frame(double t) {
    int N = LampCount;
    double dir = Reverse ? -1.0 : 1.0;

    switch (Effect) {
      case "gradient": {
        double phase = t * 0.25 * dir;
        for (int i = 0; i < N; i++) {
          double r, g, b;
          // Use real physical position so the gradient travels evenly across
          // the keyboard. Slot index would bunch it at the edges.
          Pal(SlotPos[i] + phase, out r, out g, out b);
          SetZone(i, r, g, b);
        }
        break;
      }
      case "rainbow": {
        for (int i = 0; i < N; i++) {
          double r, g, b;
          Hsv(SlotPos[i] * 360.0 + t * 90.0 * dir, 1.0, 1.0, out r, out g, out b);
          SetZone(i, r, g, b);
        }
        break;
      }
      case "wave": {
        double r0 = PalR[0], g0 = PalG[0], b0 = PalB[0];
        int p1 = PalR.Length > 1 ? 1 : 0;
        double r1 = PalR[p1], g1 = PalG[p1], b1 = PalB[p1];
        for (int i = 0; i < N; i++) {
          double ph = (t * 1.2 * dir) - SlotPos[i] * 2.0;
          double w = (1.0 + Math.Sin(ph * Math.PI)) / 2.0; w = w * w;
          SetZone(i, r0*w + r1*(1-w)*0.15, g0*w + g1*(1-w)*0.15, b0*w + b1*(1-w)*0.15);
        }
        break;
      }
      case "comet": {
        // Head travels 0..1 across the real width, wrapping.
        double head = (t * 0.45 * dir) % 1.0; if (head < 0) head += 1.0;
        for (int i = 0; i < N; i++) {
          double d = head - SlotPos[i];
          if (d < 0) d += 1.0;
          double w = Math.Exp(-d * 9.0);
          SetZone(i, PalR[0]*w, PalG[0]*w, PalB[0]*w);
        }
        break;
      }
      case "scanner": {
        double p = (t * 0.55) % 2.0; if (p < 0) p += 2.0;
        if (p > 1.0) p = 2.0 - p;           // bounce 0..1..0
        for (int i = 0; i < N; i++) {
          double w = 1.0 - (Math.Abs(SlotPos[i] - p) / 0.18);
          if (w < 0) w = 0; w = w * w;
          SetZone(i, PalR[0]*w, PalG[0]*w, PalB[0]*w);
        }
        break;
      }
      case "breathe": {
        double w = (1.0 + Math.Sin(t * 1.6 * Math.PI)) / 2.0;
        w = 0.04 + 0.96 * Math.Pow(w, 2.2);
        for (int i = 0; i < N; i++) SetZone(i, PalR[0]*w, PalG[0]*w, PalB[0]*w);
        break;
      }
      case "pulse": {
        double w = Math.Exp(-(t % 1.0) * 4.5);
        double r, g, b;
        Hsv(Math.Floor(t) * 47.0, 1.0, 1.0, out r, out g, out b);
        for (int i = 0; i < N; i++) SetZone(i, r*w, g*w, b*w);
        break;
      }
      case "fire": {
        for (int i = 0; i < N; i++) {
          heat[i] = heat[i] * 0.86 + rnd.NextDouble() * 0.30;
          if (heat[i] > 1.0) heat[i] = 1.0;
          double v = heat[i];
          SetZone(i, 255*v, 90*v*v, 10*v*v*v);
        }
        break;
      }
      default: {
        for (int i = 0; i < N; i++) SetZone(i, PalR[0], PalG[0], PalB[0]);
        break;
      }
    }
  }

  void Loop() {
    timeBeginPeriod(1);
    Stopwatch sw = Stopwatch.StartNew();
    long freq = Stopwatch.Frequency;
    long per  = freq / Fps;
    long next = sw.ElapsedTicks + per;
    try {
      while (running) {
        double t = (sw.ElapsedTicks / (double)freq) * Speed;
        Frame(t);
        Push();

        long remain = next - sw.ElapsedTicks;
        if (remain > 0) {
          int ms = (int)((remain * 1000) / freq);
          if (ms > 1) Thread.Sleep(ms - 1);
          while (sw.ElapsedTicks < next) Thread.SpinWait(40);
        } else {
          next = sw.ElapsedTicks;   // fell behind, resync rather than spiral
        }
        next += per;
      }
    } catch (Exception ex) {
      LastError = ex.Message;
    } finally {
      timeEndPeriod(1);
    }
  }

  public void Start() {
    running = true;
    th = new Thread(new ThreadStart(Loop));
    th.IsBackground = true;
    try { th.Priority = ThreadPriority.AboveNormal; } catch { }
    th.Start();
  }

  public void Stop() {
    running = false;
    if (th != null) { try { th.Join(600); } catch { } }
  }

  public void Blank() {
    for (int i = 0; i < LampCount; i++) { fr[i]=0; fg[i]=0; fb[i]=0; }
    Push(true);
  }

  public void Solid(int r, int g, int b) {
    for (int i = 0; i < LampCount; i++) {
      int rr=(int)(r*Brightness), gg=(int)(g*Brightness), bb=(int)(b*Brightness);
      if(rr>255)rr=255; if(gg>255)gg=255; if(bb>255)bb=255;
      if(rr<0)rr=0; if(gg<0)gg=0; if(bb<0)bb=0;
      fr[i]=rr; fg[i]=gg; fb[i]=bb;
    }
    Push(true);
  }

  public void Close() {
    if (h != IntPtr.Zero) { CloseHandle(h); h = IntPtr.Zero; }
  }
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
# DISCOVERY  (proven working; unchanged in shape)
# ============================================================================
Say ""
Say ("AURA-BACKGROUND v3   effect={0}  fps={1}  speed={2}" -f $Effect,$Fps,$Speed) 'Cyan'
Say ""

# A laptop exposes MANY HID collections on the same VID/PID, and more than
# one of them can declare the Lighting page (0x59). Taking the first match
# picks the wrong collection, so score every candidate and keep the one
# that really carries a LampArray: it must advertise a lamp count, a
# multi-update report and an attributes report.
function Test-LampCandidate([string]$path) {
    $res=[pscustomobject]@{ Ok=$false; Score=0; FeatLen=0 }
    $t=[HidNative]::CreateFileW($path,[uint32]0,$SHARERW,[IntPtr]::Zero,$OPENEXIST,[uint32]0,[IntPtr]::Zero)
    if ($t -eq $INVALID) { return $res }
    $tpp=[IntPtr]::Zero
    if (-not [HidNative]::HidD_GetPreparsedData($t,[ref]$tpp)) {
        [void][HidNative]::CloseHandle($t); return $res
    }
    try {
        $c=New-Object byte[] 64
        if ([HidNative]::HidP_GetCaps($tpp,$c) -ne $HIDOK) { return $res }
        if ([BitConverter]::ToUInt16($c,2) -ne 0x59) { return $res }

        $fl=[int][BitConverter]::ToUInt16($c,8)
        $res.FeatLen=$fl

        # Walk this collection's feature value caps looking for the
        # usages that define a real LampArray.
        # offset 60 = NumberFeatureValueCaps (same offset the main
        # discovery path uses; do not change without checking HIDP_CAPS)
        $nfc=[int][BitConverter]::ToUInt16($c,60)
        if ($nfc -le 0) { return $res }
        $n=[uint16]$nfc; $buf=New-Object byte[] (72*$nfc)
        if ([HidNative]::HidP_GetValueCaps(2,$buf,[ref]$n,$tpp) -ne $HIDOK) { return $res }

        $seen=@{}
        for ($i=0;$i -lt [int]$n;$i++) {
            $o=$i*72
            if ([BitConverter]::ToUInt16($buf,$o) -ne 0x59) { continue }
            $isR=$buf[$o+12]
            $u1=[int][BitConverter]::ToUInt16($buf,$o+56)
            $u2=if ($isR -ne 0) { [int][BitConverter]::ToUInt16($buf,$o+58) } else { $u1 }
            for ($u=$u1; $u -le $u2; $u++) { $seen[$u]=$true }
        }
        $sc=0
        if ($seen.ContainsKey($U_LAMPCOUNT)) { $sc+=4 }   # attributes report
        if ($seen.ContainsKey($U_RED))       { $sc+=3 }   # an update report
        if ($seen.ContainsKey($U_LAMPID))    { $sc+=2 }
        if ($seen.ContainsKey($U_AUTONOMOUS)){ $sc+=2 }   # control report
        if ($seen.ContainsKey($U_POSX))      { $sc+=1 }   # attributes response
        $res.Score=$sc
        # Require at least a lamp count and a colour channel to qualify.
        $res.Ok = ($seen.ContainsKey($U_LAMPCOUNT) -and $seen.ContainsKey($U_RED))
    }
    finally {
        [void][HidNative]::HidD_FreePreparsedData($tpp)
        [void][HidNative]::CloseHandle($t)
    }
    return $res
}

$devPath=$null; $devName=$null; $bestScore=-1
$cands=@()
foreach ($d in (Get-CimInstance Win32_PnPEntity -Filter "PNPDeviceID LIKE 'HID%'" -ErrorAction SilentlyContinue)) {
    $id=$d.PNPDeviceID
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    $p='\\?\'+$id.Replace('\','#').ToLower()+'#'+$HIDGUID
    $r=Test-LampCandidate $p
    if ($r.Score -gt 0) { $cands+=[pscustomobject]@{Name=$d.Name;Path=$p;Score=$r.Score;Ok=$r.Ok;FeatLen=$r.FeatLen} }
    if ($r.Ok -and $r.Score -gt $bestScore) { $bestScore=$r.Score; $devPath=$p; $devName=$d.Name }
}

if ($cands.Count -gt 1) {
    Say ("  {0} lighting-page collections found; picking the best." -f $cands.Count) 'DarkGray'
    foreach ($c in ($cands | Sort-Object -Property Score -Descending)) {
        $mark=if ($c.Path -eq $devPath) { '->' } else { '  ' }
        Say ("   {0} score {1}  featlen {2}  {3}" -f $mark,$c.Score,$c.FeatLen,$c.Name) 'DarkGray'
    }
}

if (-not $devPath) { Write-Host "  No LampArray HID interface found." -ForegroundColor Red; return }
Say ("  Device: {0}" -f $devName) 'Green'

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

$U_MINUPD=0x08
$lampCount=0; $RMAX=255;$GMAX=255;$BMAX=255;$IMAX=255; $minUpdUs=0
if ($rAttr) {
    $b=New-Rpt $rAttr
    if ([HidNative]::HidD_GetFeature($h,$b,$b.Length)) {
        $v=Get-Val $rAttr $b $U_LAMPCOUNT; if ($v) { $lampCount=$v }
        # The device declares how fast it can actually accept updates.
        # Pushing faster than this is what causes visible flicker.
        $v=Get-Val $rAttr $b $U_MINUPD;    if ($v) { $minUpdUs=$v }
    }
}
if ($lampCount -le 0) { $lampCount=16 }

$order=@(0..($lampCount-1))
$posX=New-Object int[] $lampCount
for ($i=0;$i -lt $lampCount;$i++) { $posX[$i]=$i*1000 }
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
        $posX[$i]=$x
        $pos[$i]=[pscustomobject]@{Idx=$i;X=$x}
    }
    $order=@($pos|Sort-Object X|ForEach-Object{$_.Idx})
}
$RMAX=[Math]::Max(1,$RMAX); $GMAX=[Math]::Max(1,$GMAX)
$BMAX=[Math]::Max(1,$BMAX); $IMAX=[Math]::Max(1,$IMAX)

if ($rCtrl) { $b=New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 0; [void](Send-Rpt $rCtrl $b) }

if ($Restore) {
    if ($rCtrl) { $b=New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 1; [void](Send-Rpt $rCtrl $b)
        Say "  Autonomous mode restored." 'Green' }
    [void][HidNative]::HidD_FreePreparsedData($pp); [void][HidNative]::CloseHandle($h); return
}

# ---- resolve the multi-update byte layout ----
$slots=1; $offId=-1;$offR=-1;$offG=-1;$offB=-1;$offI=-1;$offCnt=-1;$offFlg=-1; $fast=$false
function Probe-Off($r,[int]$usage,[int]$val) {
    $len=Rpt-Len $r
    $b=New-Object byte[] $len; $b[0]=[byte]$r.Rid
    if ([HidNative]::HidP_SetUsageValue($r.Type,0x59,0,[uint16]$usage,[uint32]$val,$script:pp,$b,[uint32]$len) -ne $script:HIDOK) { return -1 }
    for ($i=1;$i -lt $len;$i++) { if ($b[$i] -ne 0) { return $i } }
    return -1
}
if ($rMulti) {
    $slots=[int]$rMulti.Usages[$U_RED]; if ($slots -lt 1) { $slots=1 }
    $mlen=Rpt-Len $rMulti
    $offCnt=Probe-Off $rMulti $U_LAMPCOUNT 1
    $offFlg=Probe-Off $rMulti $U_FLAGS     1
    $offId =Probe-Off $rMulti $U_LAMPID    1
    $offR  =Probe-Off $rMulti $U_RED       1
    $offG  =Probe-Off $rMulti $U_GREEN     1
    $offB  =Probe-Off $rMulti $U_BLUE      1
    $offI  =Probe-Off $rMulti $U_INTENSITY 1
    if ($offId -ge 0 -and $offR -ge 0 -and $offG -ge 0 -and $offB -ge 0 -and $offI -ge 0 -and
        $offCnt -ge 0 -and $offFlg -ge 0 -and ($offI+$slots) -le $mlen -and
        $offR -eq ($offId+$slots*2) -and $offG -eq ($offR+$slots) -and
        $offB -eq ($offG+$slots) -and $offI -eq ($offB+$slots)) { $fast=$true }
    if (-not $fast -and $mlen -eq (3 + $slots*2 + $slots*4)) {
        $offCnt=1; $offFlg=2; $offId=3
        $offR=$offId+$slots*2; $offG=$offR+$slots; $offB=$offG+$slots; $offI=$offB+$slots
        $fast=$true
        Say "  Using HID spec layout." 'DarkGray'
    }
}

# ============================================================================
# COLOUR
# ============================================================================
function ConvertFrom-Hex([string]$hex) {
    $s=$hex.Trim().TrimStart('#')
    if ($s.Length -eq 3) { $s="$($s[0])$($s[0])$($s[1])$($s[1])$($s[2])$($s[2])" }
    if ($s.Length -ne 6) { throw "Bad colour '$hex'. Use #RRGGBB." }
    return ,@([Convert]::ToInt32($s.Substring(0,2),16),
              [Convert]::ToInt32($s.Substring(2,2),16),
              [Convert]::ToInt32($s.Substring(4,2),16))
}

$stops=@()
foreach ($cs in ($Colors -split ',')) { if ($cs.Trim()) { $stops+=,(ConvertFrom-Hex $cs) } }
if ($stops.Count -eq 0) { $stops=@((ConvertFrom-Hex $Color),(ConvertFrom-Hex $Color2)) }
# The palette is cyclic now, so a repeated first/last colour would double up.
if ($stops.Count -gt 2 -and
    $stops[0][0] -eq $stops[-1][0] -and
    $stops[0][1] -eq $stops[-1][1] -and
    $stops[0][2] -eq $stops[-1][2]) {
    $stops=@($stops[0..($stops.Count-2)])
}
if ($stops.Count -eq 1) { $stops=@($stops[0],$stops[0]) }

# ============================================================================
# CUSTOM EFFECT  (stays on the PowerShell path)
# ============================================================================
if ($Custom) {
    if (-not (Test-Path $Custom)) { Write-Host ("  Custom file not found: {0}" -f $Custom) -ForegroundColor Red; return }
    $CustomBlock = [scriptblock]::Create((Get-Content -Raw $Custom)).Invoke() | Select-Object -Last 1
    if ($CustomBlock -is [System.Management.Automation.PSObject]) { $CustomBlock=$CustomBlock.BaseObject }
    if ($CustomBlock -isnot [scriptblock]) {
        Write-Host "  Custom file must end with a scriptblock: { param(`$t,`$N) ... }" -ForegroundColor Red
        return
    }
    Say ("  Custom effect: {0}  (PowerShell path, slower than built-ins)" -f (Split-Path -Leaf $Custom)) 'Yellow'

    $fr=New-Object int[] $lampCount; $fg=New-Object int[] $lampCount; $fb=New-Object int[] $lampCount
    function Convert-Hsv([double]$hd,[double]$s,[double]$v) {
        $hd=$hd%360.0; if ($hd -lt 0) { $hd+=360.0 }
        $c=$v*$s; $x=$c*(1.0-[Math]::Abs((($hd/60.0)%2.0)-1.0)); $m=$v-$c
        switch ([int][Math]::Floor($hd/60.0)) {
            0 {$r=$c;$g=$x;$b=0} 1 {$r=$x;$g=$c;$b=0} 2 {$r=0;$g=$c;$b=$x}
            3 {$r=0;$g=$x;$b=$c} 4 {$r=$x;$g=0;$b=$c} default {$r=$c;$g=0;$b=$x}
        }
        return ,@([int](255*($r+$m)),[int](255*($g+$m)),[int](255*($b+$m)))
    }
    function Set-Zone([int]$slot,[double]$r,[double]$g,[double]$b) {
        if ($slot -lt 0 -or $slot -ge $script:lampCount) { return }
        $q=$slot
        if ($script:Mirror) {
            $half=[int][Math]::Ceiling($script:lampCount/2.0)
            $q=if ($slot -lt $half) { $half-1-$slot } else { $slot-$half }
            if ($q -ge $script:lampCount) { $q=$script:lampCount-1 }
        }
        $i=$script:order[$q]; $k=$script:Brightness
        $rr=[int]($r*$k); $gg=[int]($g*$k); $bb=[int]($b*$k)
        if($rr -lt 0){$rr=0}elseif($rr -gt 255){$rr=255}
        if($gg -lt 0){$gg=0}elseif($gg -gt 255){$gg=255}
        if($bb -lt 0){$bb=0}elseif($bb -gt 255){$bb=255}
        $script:fr[$i]=$rr; $script:fg[$i]=$gg; $script:fb[$i]=$bb
    }
    $mbuf=$null
    if ($fast) { $mbufs=@(); for ($bi=0;$bi -lt [Math]::Ceiling($lampCount/[double]$slots);$bi++) {
        $bb2=New-Object byte[] (Rpt-Len $rMulti); $bb2[0]=[byte]$rMulti.Rid
        $first=$bi*$slots; $n=[Math]::Min($slots,$lampCount-$first); $bb2[$offCnt]=[byte]$n
        for ($s=0;$s -lt $n;$s++) { $lid=$first+$s
            $bb2[$offId+$s*2]=[byte]($lid -band 0xFF); $bb2[$offId+$s*2+1]=[byte](($lid -shr 8) -band 0xFF)
            $bb2[$offI+$s]=[byte]$IMAX }
        $mbufs+=,$bb2 } }
    $sw=[Diagnostics.Stopwatch]::StartNew()
    $ms=[int](1000/$Fps)
    try {
        while ($true) {
            $t=$sw.Elapsed.TotalSeconds*$Speed
            & $CustomBlock $t $lampCount
            if ($fast) {
                $lastB=$mbufs.Count-1
                for ($bi=0;$bi -le $lastB;$bi++) {
                    $bb2=$mbufs[$bi]; $first=$bi*$slots
                    $n=[Math]::Min($slots,$lampCount-$first)
                    for ($s=0;$s -lt $n;$s++) { $i=$first+$s
                        $bb2[$offR+$s]=[byte](($fr[$i]*$RMAX)/255)
                        $bb2[$offG+$s]=[byte](($fg[$i]*$GMAX)/255)
                        $bb2[$offB+$s]=[byte](($fb[$i]*$BMAX)/255) }
                    if ($bi -eq $lastB) { $bb2[$offFlg]=[byte]1 } else { $bb2[$offFlg]=[byte]0 }
                    [void][HidNative]::HidD_SetFeature($h,$bb2,$bb2.Length)
                }
            }
            Start-Sleep -Milliseconds $ms
        }
    } finally {
        if ($rCtrl) { $b=New-Rpt $rCtrl; Set-Val $rCtrl $b $U_AUTONOMOUS 1; [void](Send-Rpt $rCtrl $b) }
        [void][HidNative]::HidD_FreePreparsedData($pp); [void][HidNative]::CloseHandle($h)
    }
    return
}

# ============================================================================
# COMPILED ENGINE PATH
# ============================================================================
if (-not $fast) {
    Write-Host "  Could not resolve the multi-update report layout." -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "  Diagnostic detail:" -ForegroundColor Yellow
    Write-Host ("    feature report length : {0}" -f $featLen)
    Write-Host ("    output report length  : {0}" -f $outLen)
    Write-Host ("    lamp count            : {0}" -f $lampCount)
    if ($rMulti) {
        Write-Host ("    multi-update report   : id {0}, type {1}, len {2}" -f $rMulti.Rid,$rMulti.Type,(Rpt-Len $rMulti))
        Write-Host ("    slots (red count)     : {0}" -f $slots)
        Write-Host ("    expected len for spec : {0}" -f (3 + $slots*2 + $slots*4))
        Write-Host ("    probed offsets        : cnt={0} flg={1} id={2} r={3} g={4} b={5} i={6}" -f `
                    $offCnt,$offFlg,$offId,$offR,$offG,$offB,$offI)
    } else {
        Write-Host "    multi-update report   : NOT FOUND" -ForegroundColor Red
    }
    Write-Host ("    reports discovered    : {0}" -f (($reports.Keys | Sort-Object) -join ', '))
    Write-Host ""
    Write-Host "  Copy the lines above and send them to me." -ForegroundColor Yellow
    [void][HidNative]::HidD_FreePreparsedData($pp); [void][HidNative]::CloseHandle($h)
    return
}

# Build the "autonomous mode off" report now, while the preparsed data is
# still valid, so the engine can re-send it on its own handle.
$ctrlOffBuf = $null
if ($rCtrl) {
    $ctrlOffBuf = New-Rpt $rCtrl
    Set-Val $rCtrl $ctrlOffBuf $U_AUTONOMOUS 0
}

# PowerShell's handle is no longer needed; the engine opens its own.
[void][HidNative]::HidD_FreePreparsedData($pp)
[void][HidNative]::CloseHandle($h)

$eng = New-Object LampEngine
$eng.DevicePath = $devPath
$eng.LampCount  = $lampCount
$eng.Order      = [int[]]$order
$eng.ReportId   = $rMulti.Rid
$eng.Slots      = $slots
$eng.ReportLen  = (Rpt-Len $rMulti)
$eng.CtrlOff    = $ctrlOffBuf
$eng.OffCount   = $offCnt
$eng.OffFlags   = $offFlg
$eng.OffId      = $offId
$eng.OffR       = $offR
$eng.OffG       = $offG
$eng.OffB       = $offB
$eng.OffI       = $offI
$eng.MaxR       = $RMAX
$eng.MaxG       = $GMAX
$eng.MaxB       = $BMAX
$eng.MaxI       = $IMAX
$eng.Effect     = $Effect
$eng.Speed      = $Speed
$eng.Brightness = $Brightness

# Never drive the device faster than it says it can accept, or it flickers.
$fpsCap = $Fps
if ($minUpdUs -gt 0) {
    $devMax = [int][Math]::Floor(1000000.0 / $minUpdUs)
    if ($devMax -ge 1 -and $devMax -lt $fpsCap) {
        Say ("  Device max update rate is {0} fps (min interval {1} us). Capping." -f $devMax,$minUpdUs) 'Yellow'
        $fpsCap = $devMax
    }
}
$eng.Fps        = $fpsCap

# Normalised physical position per slot: 0.0 far left, 1.0 far right.
$xs = @($order | ForEach-Object { $posX[$_] })
$xmin = ($xs | Measure-Object -Minimum).Minimum
$xmax = ($xs | Measure-Object -Maximum).Maximum
$span = $xmax - $xmin
$sp = New-Object double[] $lampCount
for ($s=0; $s -lt $lampCount; $s++) {
    if ($span -gt 0) { $sp[$s] = ($xs[$s] - $xmin) / [double]$span }
    else { $sp[$s] = if ($lampCount -gt 1) { $s / [double]($lampCount-1) } else { 0.0 } }
}
$eng.SlotPos    = $sp
$eng.Mirror     = [bool]$Mirror
$eng.Reverse    = [bool]$Reverse
$eng.PalR       = [int[]]@($stops | ForEach-Object { $_[0] })
$eng.PalG       = [int[]]@($stops | ForEach-Object { $_[1] })
$eng.PalB       = [int[]]@($stops | ForEach-Object { $_[2] })

if (-not $eng.Open()) {
    Write-Host ("  Engine could not open the device. {0}" -f $eng.LastError) -ForegroundColor Red
    Write-Host "  Run PowerShell as Administrator." -ForegroundColor Red
    return
}

Say ("  {0} zones, {1} per transfer, {2} transfers/frame, {3} colours (cyclic)" -f `
     $lampCount, $slots, [Math]::Ceiling($lampCount/[double]$slots), $stops.Count) 'Green'

if ($Effect -eq 'off') {
    $eng.Blank(); $eng.Close()
    Say "  OFF applied." 'Green'
    return
}
if ($Effect -eq 'static') {
    $eng.Solid($stops[0][0],$stops[0][1],$stops[0][2]); $eng.Close()
    Say "  Solid colour applied." 'Green'
    return
}

Say ""
Say (" Running at {0} fps on a compiled thread. Ctrl+C to stop." -f $eng.Fps) 'Green'
Say ""

$eng.Start()
try {
    while ($true) { Start-Sleep -Seconds 1 }
}
finally {
    Say ""
    Say "  Stopping. Handing lighting back to the keyboard firmware." 'Yellow'
    $eng.Stop()
    $eng.Blank()
    $eng.Close()
    $h2=[HidNative]::CreateFileW($devPath,$GENRW,$SHARERW,[IntPtr]::Zero,$OPENEXIST,[uint32]0,[IntPtr]::Zero)
    if ($h2 -ne $INVALID) {
        $pp2=[IntPtr]::Zero
        if ([HidNative]::HidD_GetPreparsedData($h2,[ref]$pp2)) {
            if ($rCtrl) {
                $cb=New-Object byte[] $featLen; $cb[0]=[byte]$rCtrl.Rid
                [void][HidNative]::HidP_SetUsageValue(2,0x59,0,[uint16]$U_AUTONOMOUS,[uint32]1,$pp2,$cb,[uint32]$cb.Length)
                [void][HidNative]::HidD_SetFeature($h2,$cb,$cb.Length)
            }
            [void][HidNative]::HidD_FreePreparsedData($pp2)
        }
        [void][HidNative]::CloseHandle($h2)
    }
}
