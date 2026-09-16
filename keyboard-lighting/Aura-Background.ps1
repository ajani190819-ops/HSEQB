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
                 'gradient','static','off',
                 'spectrum','vumeter','beat','pulsebass',
                 'ambient','cycle','strobe','stars','ripple','aurora',
                 'battery','cpu','clock')]
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

    # Briefly show battery status when the charger is plugged in or pulled
    # out, and when the battery gets low, then return to the chosen effect.
    [switch]$OverlayOn,
    [switch]$Restore,
    [switch]$Quiet,

    # Even out the apparent brightness of the palette so no one colour
    # (yellow especially) drowns out the rest. On by default.
    [ValidateSet('on','off')]
    [string]$Equalise = 'on',

    # across = left-to-right. loop = travels around the chassis perimeter,
    # so the light bar genuinely circles instead of pulsing as one block.
    [switch]$NoLive,
    [ValidateSet('across','loop')]
    [string]$Layout = 'loop'
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

  // ---- device-loss recovery ----
  // After sleep the USB port is power-cycled and this handle is dead.
  // Writes then fail silently forever, so count them and rebuild.
  public volatile bool DeviceLost = false;
  public volatile int  Reopens = 0;
  int failRun = 0;

  IntPtr h = IntPtr.Zero;
  Thread th;
  volatile bool running;
  byte[][] bufs;
  int nbatch;
  double[] fr, fg, fb;
  double[] heat;
  Random rnd = new Random();

  // LampArrayControl report, prebuilt by PowerShell. Sending this on OUR
  // OWN handle re-asserts host control: some firmware drops back to
  // autonomous mode when the handle that disabled it is closed, which
  // makes every update silently do nothing.
  public byte[] CtrlOff = null;

  // Optional data sources for the reactive / info effects.
  public AudioCap Audio  = null;
  public SysInfo  Sys    = null;
  public ScreenCap Screen = null;
  public volatile int  OverlayMode = 0;    // 0 none, 1 battery, 2 cpu
  public volatile double OverlayUntil = 0.0;
  public double Now = 0.0;

  // Channel stride within one report. Planar layouts put each colour plane
  // Slots apart (stride 1 between lamps of the same channel); interleaved
  // layouts store R,G,B,I together so consecutive lamps are 4 apart.
  public bool Interleaved = false;

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
        b[Interleaved ? (OffI + s*4) : (OffI + s)] = (byte)MaxI;
      }
      bufs[bi] = b;
    }
    fr = new double[LampCount]; fg = new double[LampCount]; fb = new double[LampCount];
    er = new double[LampCount]; eg = new double[LampCount]; eb = new double[LampCount];
    pr = new int[LampCount]; pg = new int[LampCount]; pb = new int[LampCount];
    for (int i = 0; i < LampCount; i++) { pr[i] = -1; pg[i] = -1; pb[i] = -1; }
    heat = new double[LampCount];

    // Gamma tables + palette gains must exist before any colour is produced.
    PrepPalette();
    if (SlotPos == null || SlotPos.Length != LampCount) {
      SlotPos = new double[LampCount];
      for (int i = 0; i < LampCount; i++)
        SlotPos[i] = (LampCount > 1) ? (i / (double)(LampCount - 1)) : 0.0;
    }
    return true;
  }


  // Battery as a filling bar: green when full, red when nearly empty.
  // While charging a bright head runs along the bar.
  void DrawBattery(int N) {
    int pct = (Sys != null) ? Sys.Battery : -1;
    bool chg = (Sys != null) && Sys.Charging;
    if (pct < 0) pct = 100;
    double f = pct / 100.0;
    double hue = 120.0 * f;                       // 0 red .. 120 green
    double hr, hg, hb;
    Hsv(hue, 1.0, 1.0, out hr, out hg, out hb);
    double head = chg ? ((Now * 0.5) % 1.0) : -1.0;
    bool low = (!chg && f <= 0.15);
    double blink = low ? (0.35 + 0.65 * (0.5 + 0.5 * Math.Sin(Now * 5.0))) : 1.0;
    for (int i = 0; i < N; i++) {
      double u = SlotPos[i];
      double on;
      if (u <= f) on = 1.0;
      else {
        double d = (u - f) / 0.05;
        on = (d < 1.0) ? (1.0 - d) : 0.0;
      }
      double r = hr * on, g = hg * on, b = hb * on;
      if (on < 0.02) { r = 6; g = 6; b = 6; }     // faint track
      if (chg && head >= 0) {
        double d2 = Math.Abs(u - head * f);
        double w = Math.Exp(-d2 * 20.0);
        r += 255 * w * 0.8; g += 255 * w * 0.8; b += 200 * w * 0.8;
      }
      SetZone(i, r * blink, g * blink, b * blink);
    }
  }

  // CPU load meter: green at idle through to red under full load.
  void DrawCpu(int N) {
    double c = (Sys != null) ? Sys.Cpu : 0.0;
    double hue = 120.0 - 120.0 * c;
    double hr, hg, hb;
    Hsv(hue, 1.0, 1.0, out hr, out hg, out hb);
    for (int i = 0; i < N; i++) {
      double u = SlotPos[i];
      double on;
      if (u <= c) on = 1.0;
      else {
        double d = (u - c) / 0.05;
        on = (d < 1.0) ? (1.0 - d) : 0.0;
      }
      double r = hr * on, g = hg * on, b = hb * on;
      if (on < 0.02) { r = 5; g = 5; b = 5; }
      SetZone(i, r, g, b);
    }
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

    // Brightness is applied as a GAMMA-SPACE scale, which is what the
    // Windows Dynamic Lighting slider does. Scaling linear light instead
    // feels top-heavy: 50% would still look ~79% bright.
    if (Brightness < 0.999) { r *= Brightness; g *= Brightness; b *= Brightness; }

    // Keep full precision here; quantisation happens once, in Push(),
    // where the dither error can be carried between frames.
    if (r < 0) r = 0; else if (r > 255) r = 255;
    if (g < 0) g = 0; else if (g > 255) g = 255;
    if (b < 0) b = 0; else if (b > 255) b = 255;
    fr[i] = r; fg[i] = g; fb[i] = b;
  }

  int[] pr, pg, pb;        // last bytes actually sent
  double[] er, eg, eb;     // carried quantisation error, for temporal dither

  void Push() { Push(false); }

  // Quantise with error feedback: the fraction we throw away this frame is
  // added to the next one. At 60fps the eye integrates the result, so a
  // value creeping at 0.4 LSB/frame fades smoothly instead of holding for
  // two frames and then stepping - which is the flicker seen at low speeds.
  static int Dither(double v, double scale, ref double err) {
    double x = v * scale / 255.0 + err;
    int q = (int)(x + 0.5);
    if (q < 0) q = 0; else if (q > 255) q = 255;
    err = x - q;
    if (err > 1.0) err = 1.0; else if (err < -1.0) err = -1.0;
    return q;
  }

  void Push(bool force) {
    int last = nbatch - 1;
    bool changed = force;

    for (int bi = 0; bi < nbatch; bi++) {
      byte[] b = bufs[bi];
      int first = bi * Slots;
      int n = Math.Min(Slots, LampCount - first);
      for (int s = 0; s < n; s++) {
        int i = first + s;
        int st = Interleaved ? s*4 : s;
        int qr = Dither(fr[i], MaxR, ref er[i]);
        int qg = Dither(fg[i], MaxG, ref eg[i]);
        int qb = Dither(fb[i], MaxB, ref eb[i]);
        if (qr != pr[i] || qg != pg[i] || qb != pb[i]) changed = true;
        pr[i] = qr; pg[i] = qg; pb[i] = qb;
        b[OffR + st] = (byte)qr;
        b[OffG + st] = (byte)qg;
        b[OffB + st] = (byte)qb;
      }
      b[OffFlags] = (bi == last) ? (byte)1 : (byte)0;
    }

    // Nothing moved, not even by one dithered step: skip the transfer.
    if (!changed) return;

    bool allOk = true;
    for (int bi = 0; bi < nbatch; bi++) {
      byte[] b = bufs[bi];
      if (!HidD_SetFeature(h, b, b.Length)) allOk = false;
    }

    // One failed write is noise (a busy endpoint). A run of them means the
    // handle is dead - almost always a resume from sleep.
    if (allOk) { failRun = 0; }
    else {
      failRun++;
      if (failRun >= 8) { DeviceLost = true; failRun = 0; }
    }
  }

  // Tell the firmware again that WE drive the lamps. This is idempotent
  // and cheap, and it is the only thing that reliably recovers control
  // after the EC has taken the keyboard back (lid close, Modern Standby,
  // display off) WITHOUT the USB device ever disappearing - in which case
  // no write ever fails and nothing else would notice.
  public void ReAssert() {
    if (h == IntPtr.Zero || h == (IntPtr)(-1)) return;
    if (CtrlOff != null) HidD_SetFeature(h, CtrlOff, CtrlOff.Length);
    // Whatever the panel is showing is now wrong: force the next Push to
    // resend every zone even if the computed colours are identical.
    if (pr != null) {
      for (int i = 0; i < LampCount; i++) { pr[i] = -1; pg[i] = -1; pb[i] = -1; }
    }
  }

  // Rebuild the connection after the device has gone away and come back.
  // Safe to call from the render thread.
  public bool Reopen() {
    try {
      if (h != IntPtr.Zero && h != (IntPtr)(-1)) CloseHandle(h);
    } catch { }
    h = IntPtr.Zero;

    IntPtr nh = CreateFileW(DevicePath, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (nh == (IntPtr)(-1)) nh = CreateFileW(DevicePath, 0x40000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (nh == (IntPtr)(-1)) { LastError = "reopen failed: " + Marshal.GetLastWin32Error(); return false; }
    h = nh;

    // The firmware reverts to autonomous mode across a power cycle, so it
    // must be told again to hand control over.
    if (CtrlOff != null) HidD_SetFeature(h, CtrlOff, CtrlOff.Length);

    // Force a full repaint: the cached previous values no longer reflect
    // anything the hardware is showing.
    if (pr != null) {
      for (int i = 0; i < LampCount; i++) { pr[i] = -1; pg[i] = -1; pb[i] = -1; }
    }
    if (er != null) {
      for (int i = 0; i < LampCount; i++) { er[i] = 0; eg[i] = 0; eb[i] = 0; }
    }
    failRun = 0;
    DeviceLost = false;
    Reopens++;
    return true;
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

  // ---- colour science -------------------------------------------------
  //
  // An LED's brightness is proportional to the byte we send (linear light),
  // but sRGB colour values are gamma-encoded. Blending or dimming the raw
  // bytes therefore produces mid-tones that are far too bright, which reads
  // as washed-out, muddy colour. Everything below works in LINEAR light and
  // converts back to gamma only at the very end.

  static double[] _toLin;    // gamma byte -> linear 0..1
  static double[] _toSrgb;   // linear (4096 steps) -> gamma byte

  static void BuildTables() {
    if (_toLin != null) return;
    _toLin = new double[256];
    for (int i = 0; i < 256; i++) {
      double c = i / 255.0;
      _toLin[i] = (c <= 0.04045) ? (c / 12.92) : Math.Pow((c + 0.055) / 1.055, 2.4);
    }
    _toSrgb = new double[4097];
    for (int i = 0; i <= 4096; i++) {
      double c = i / 4096.0;
      double s = (c <= 0.0031308) ? (12.92 * c) : (1.055 * Math.Pow(c, 1.0 / 2.4) - 0.055);
      _toSrgb[i] = s * 255.0;
    }
  }

  static double ToLin(double v) {
    if (v <= 0) return 0;
    if (v >= 255) return 1;
    int i = (int)v;
    double f = v - i;
    if (i >= 255) return 1;
    return _toLin[i] + (_toLin[i + 1] - _toLin[i]) * f;
  }

  static double ToSrgb(double lv) {
    if (lv <= 0) return 0;
    if (lv >= 1) return 255;
    double x = lv * 4096.0;
    int i = (int)x;
    double f = x - i;
    if (i >= 4096) return 255;
    return _toSrgb[i] + (_toSrgb[i + 1] - _toSrgb[i]) * f;
  }

  // Rec.709 luminance of a linear colour - how bright the eye judges it.
  static double Luma(double lr, double lg, double lb) {
    return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb;
  }

  // Set to true to even out the palette so no single colour dominates.
  public bool Equalise = true;

  // Live control. The panel writes a small file; the engine picks it up
  // without restarting, so changes apply instantly.
  // ---- live control ------------------------------------------------
  // Written from the PowerShell thread, read on the render thread. Only
  // types C# allows to be volatile are used, so doubles travel as ints.
  public volatile int    LiveBrightness = -1;   // 0..1000, -1 = untouched
  public volatile int    LiveSpeedMilli = -1;   // Speed * 1000
  public volatile string LiveEffect     = null;
  public volatile int[]  LivePalR       = null;
  public volatile int[]  LivePalG       = null;
  public volatile int[]  LivePalB       = null;
  public volatile int    LiveFlags      = -1;   // 1 mirror 2 reverse 4 equalise 8 loop
  public volatile bool   LiveDirty      = false;

  // Both layouts are worked out up front so the loop/across switch can be
  // flipped live without tearing the engine down.
  public double[] SlotPosAcross;
  public double[] SlotPosLoop;

  // Per-stop gain applied in linear light, computed once at startup.
  double[] palGain;
  double[] plR, plG, plB;    // palette in linear light

  void PrepPalette() {
    BuildTables();
    int pc = PalR.Length;
    plR = new double[pc]; plG = new double[pc]; plB = new double[pc];
    palGain = new double[pc];

    for (int i = 0; i < pc; i++) {
      plR[i] = ToLin(PalR[i]);
      plG[i] = ToLin(PalG[i]);
      plB[i] = ToLin(PalB[i]);
      palGain[i] = 1.0;
    }
    if (!Equalise || pc == 0) return;

    // Pull every stop towards a common apparent brightness. Full
    // equalisation would crush saturated blues to nothing, so aim at the
    // geometric mean and only go part of the way (exponent 0.5).
    double logSum = 0; int n = 0;
    for (int i = 0; i < pc; i++) {
      double L = Luma(plR[i], plG[i], plB[i]);
      if (L > 0.0005) { logSum += Math.Log(L); n++; }
    }
    if (n == 0) return;
    double target = Math.Exp(logSum / n);

    for (int i = 0; i < pc; i++) {
      double L = Luma(plR[i], plG[i], plB[i]);
      if (L <= 0.0005) continue;
      double gain = Math.Pow(target / L, 0.5);
      // Never amplify past the point where the brightest channel clips,
      // and never dim a colour into the mud.
      double peak = Math.Max(plR[i], Math.Max(plG[i], plB[i]));
      if (peak > 0 && gain * peak > 1.0) gain = 1.0 / peak;
      if (gain < 0.25) gain = 0.25;
      if (gain > 4.00) gain = 4.00;
      palGain[i] = gain;
    }
  }

  // Cyclic palette sample. f is 0..1 around the whole loop.
  // Interpolates in LINEAR light so blends keep their brightness and the
  // colours stay distinct instead of passing through a dark muddy band.
  void Pal(double f, out double r, out double g, out double b) {
    int pc = plR.Length;
    f = f % 1.0; if (f < 0) f += 1.0;
    double x = f * pc;
    int a = (int)Math.Floor(x);
    double u = x - a;
    int n2 = (a + 1) % pc;
    a = a % pc;

    // Smoothstep the crossfade: less time in the ambiguous middle, so each
    // stop reads as its own colour for longer.
    double w = u * u * (3.0 - 2.0 * u);

    double ga = palGain[a], gb = palGain[n2];
    double lr = (plR[a] * ga) + ((plR[n2] * gb) - (plR[a] * ga)) * w;
    double lg = (plG[a] * ga) + ((plG[n2] * gb) - (plG[a] * ga)) * w;
    double lb = (plB[a] * ga) + ((plB[n2] * gb) - (plB[a] * ga)) * w;

    r = ToSrgb(lr); g = ToSrgb(lg); b = ToSrgb(lb);
  }

  // Apply a 0..1 fade weight to a colour in LINEAR light, so tails and
  // pulses ramp the way the eye expects instead of staying bright then
  // falling off a cliff.
  static void Fade(double r, double g, double b, double w,
                   out double orr, out double og, out double ob) {
    if (w <= 0) { orr = 0; og = 0; ob = 0; return; }
    if (w >= 1) { orr = r; og = g; ob = b; return; }
    orr = ToSrgb(ToLin(r) * w);
    og  = ToSrgb(ToLin(g) * w);
    ob  = ToSrgb(ToLin(b) * w);
  }

  void Frame(double t) { Frame(t, 1.0 / Fps); }

  void Frame(double t, double dt) {
    if (LiveDirty) {
      LiveDirty = false;        // clear first, so a write mid-apply is not lost
      bool repal = false;

      int lb = LiveBrightness;
      if (lb >= 0) Brightness = lb / 1000.0;

      int ls = LiveSpeedMilli;
      if (ls >= 0) Speed = ls / 1000.0;

      string le = LiveEffect;
      if (le != null && le.Length > 0) Effect = le;

      int[] pr = LivePalR, pg = LivePalG, pb = LivePalB;
      if (pr != null && pg != null && pb != null && pr.Length > 0 &&
          pr.Length == pg.Length && pr.Length == pb.Length) {
        PalR = pr; PalG = pg; PalB = pb; repal = true;
      }

      int lf = LiveFlags;
      if (lf >= 0) {
        Mirror  = (lf & 1) != 0;
        Reverse = (lf & 2) != 0;
        bool eq = (lf & 4) != 0;
        if (eq != Equalise) { Equalise = eq; repal = true; }
        bool lp = (lf & 8) != 0;
        double[] want = lp ? SlotPosLoop : SlotPosAcross;
        if (want != null && want.Length == LampCount) SlotPos = want;
      }

      if (repal) PrepPalette();
    }
    int N = LampCount;
    double dir = Reverse ? -1.0 : 1.0;
    Now = t;

    // An overlay temporarily takes over the keyboard (battery unplugged,
    // battery low, etc), then hands it straight back to the chosen effect.
    int ov = OverlayMode;
    if (ov != 0) {
      if (t < OverlayUntil) {
        if (ov == 1) DrawBattery(N);
        else if (ov == 2) DrawCpu(N);
        return;
      }
      OverlayMode = 0;
    }

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
          double cr, cg, cb;
          Fade(PalR[0], PalG[0], PalB[0], w, out cr, out cg, out cb);
          SetZone(i, cr, cg, cb);
        }
        break;
      }
      case "scanner": {
        double p = (t * 0.55) % 2.0; if (p < 0) p += 2.0;
        if (p > 1.0) p = 2.0 - p;           // bounce 0..1..0
        for (int i = 0; i < N; i++) {
          double w = 1.0 - (Math.Abs(SlotPos[i] - p) / 0.18);
          if (w < 0) w = 0; w = w * w;
          double cr, cg, cb;
          Fade(PalR[0], PalG[0], PalB[0], w, out cr, out cg, out cb);
          SetZone(i, cr, cg, cb);
        }
        break;
      }
      case "breathe": {
        double w = (1.0 + Math.Sin(t * 1.6 * Math.PI)) / 2.0;
        w = 0.02 + 0.98 * w * w;
        double cr, cg, cb;
        Fade(PalR[0], PalG[0], PalB[0], w, out cr, out cg, out cb);
        for (int i = 0; i < N; i++) SetZone(i, cr, cg, cb);
        break;
      }
      case "pulse": {
        double w = Math.Exp(-(t % 1.0) * 4.5);
        double r, g, b;
        Hsv(Math.Floor(t) * 47.0, 1.0, 1.0, out r, out g, out b);
        double pr2, pg2, pb2;
        Fade(r, g, b, w, out pr2, out pg2, out pb2);
        for (int i = 0; i < N; i++) SetZone(i, pr2, pg2, pb2);
        break;
      }
      // ---------------- audio reactive ----------------
      case "spectrum": {
        // Each zone is one frequency band, low on the left.
        float[] bd = (Audio != null && Audio.Ok) ? Audio.Bands : null;
        for (int i = 0; i < N; i++) {
          double u = SlotPos[i];
          double v = 0.0;
          if (bd != null) {
            int b = (int)(u * (AudioCap.BANDS - 1) + 0.5);
            if (b < 0) b = 0; if (b >= AudioCap.BANDS) b = AudioCap.BANDS - 1;
            v = bd[b];
          }
          double r, g, b2;
          Pal(u, out r, out g, out b2);
          SetZone(i, r * v, g * v, b2 * v);
        }
        break;
      }
      case "vumeter": {
        // Palette bar that fills from the left with overall loudness.
        double lv = (Audio != null && Audio.Ok) ? Audio.Level : 0.0;
        for (int i = 0; i < N; i++) {
          double u = SlotPos[i];
          double on = (u <= lv) ? 1.0 : 0.0;
          if (on < 1.0) {
            double d = (u - lv) / 0.08;        // soft edge
            on = (d < 1.0) ? (1.0 - d) : 0.0;
            if (on < 0) on = 0;
          }
          double r, g, b;
          Pal(u, out r, out g, out b);
          SetZone(i, r * on, g * on, b * on);
        }
        break;
      }
      case "beat": {
        // Whole keyboard flashes on the beat, colour cycles per hit.
        double e = (Audio != null && Audio.Ok) ? Audio.Beat : 0.0;
        double bass = (Audio != null && Audio.Ok) ? Audio.Bass : 0.0;
        double w = e * 0.75 + bass * 0.45;
        if (w > 1.0) w = 1.0;
        w = 0.04 + 0.96 * w * w;
        double r0, g0, b0;
        Pal(t * 0.08, out r0, out g0, out b0);
        for (int i = 0; i < N; i++) SetZone(i, r0 * w, g0 * w, b0 * w);
        break;
      }
      case "pulsebass": {
        // Bass drives a wave outward from the centre.
        double bass = (Audio != null && Audio.Ok) ? Audio.Bass : 0.0;
        for (int i = 0; i < N; i++) {
          double d = Math.Abs(SlotPos[i] - 0.5) * 2.0;
          double v = bass - d * 0.55;
          if (v < 0) v = 0; if (v > 1) v = 1;
          v = v * v;
          double r, g, b;
          Pal(SlotPos[i] + t * 0.05, out r, out g, out b);
          SetZone(i, r * v, g * v, b * v);
        }
        break;
      }

      // ---------------- ambient (screen mirror) ----------------
      case "ambient": {
        int[] cols = (Screen != null && Screen.Ok) ? Screen.Cols : null;
        for (int i = 0; i < N; i++) {
          double u = SlotPos[i];
          double r = 0, g = 0, b = 0;
          if (cols != null && cols.Length > 0) {
            double f = u * (cols.Length - 1);
            int a = (int)f; if (a < 0) a = 0; if (a >= cols.Length) a = cols.Length - 1;
            int c2 = a + 1; if (c2 >= cols.Length) c2 = cols.Length - 1;
            double w = f - a;
            int ca = cols[a], cb = cols[c2];
            r = ((ca >> 16) & 0xFF) * (1 - w) + ((cb >> 16) & 0xFF) * w;
            g = ((ca >>  8) & 0xFF) * (1 - w) + ((cb >>  8) & 0xFF) * w;
            b = ( ca        & 0xFF) * (1 - w) + ( cb        & 0xFF) * w;
            // Screens are mostly desaturated; push saturation so the
            // keyboard shows a colour rather than a grey wash.
            double mx = Math.Max(r, Math.Max(g, b));
            double mn = Math.Min(r, Math.Min(g, b));
            if (mx > 1.0) {
              double mid = (mx + mn) * 0.5;
              r = mid + (r - mid) * 1.55;
              g = mid + (g - mid) * 1.55;
              b = mid + (b - mid) * 1.55;
              double k = 255.0 / Math.Max(255.0, Math.Max(r, Math.Max(g, b)));
              r *= k; g *= k; b *= k;
              if (r < 0) r = 0; if (g < 0) g = 0; if (b < 0) b = 0;
            }
          }
          SetZone(i, r, g, b);
        }
        break;
      }

      // ---------------- classic presets ----------------
      case "cycle": {
        // Whole keyboard one colour, slowly walking the hue wheel.
        double r, g, b;
        Hsv((t * 18.0 * dir) % 360.0, 1.0, 1.0, out r, out g, out b);
        for (int i = 0; i < N; i++) SetZone(i, r, g, b);
        break;
      }
      case "strobe": {
        double ph = t * 6.0;
        double w = (ph - Math.Floor(ph)) < 0.5 ? 1.0 : 0.0;
        double r, g, b;
        Pal(Math.Floor(ph) * 0.13, out r, out g, out b);
        for (int i = 0; i < N; i++) SetZone(i, r * w, g * w, b * w);
        break;
      }
      case "stars": {
        // Twinkling points of light on a dark keyboard.
        double fade = Math.Pow(0.28, dt);
        double born = 1.0 - Math.Pow(1.0 - 0.055, dt * 60.0);
        for (int i = 0; i < N; i++) {
          heat[i] *= fade;
          if (rnd.NextDouble() < born) heat[i] = 0.75 + rnd.NextDouble() * 0.25;
          double v = heat[i];
          double r, g, b;
          Pal((i * 0.137) % 1.0, out r, out g, out b);
          SetZone(i, r * v, g * v, b * v);
        }
        break;
      }
      case "ripple": {
        // Expanding rings from the centre.
        double sp = 0.55 * dir;
        double v0 = (t * sp) % 1.0;
        for (int i = 0; i < N; i++) {
          double d = Math.Abs(SlotPos[i] - 0.5) * 2.0;
          double ph = d - v0;
          ph = ph - Math.Floor(ph);
          double w = Math.Exp(-ph * 5.0);
          double r, g, b;
          Pal(SlotPos[i] + t * 0.1, out r, out g, out b);
          SetZone(i, r * w, g * w, b * w);
        }
        break;
      }
      case "aurora": {
        // Three slow sine layers - the soft drifting look.
        for (int i = 0; i < N; i++) {
          double u = SlotPos[i];
          double a = 0.5 + 0.5 * Math.Sin((u * 2.1 + t * 0.21 * dir) * Math.PI * 2.0);
          double b2 = 0.5 + 0.5 * Math.Sin((u * 1.3 - t * 0.14 * dir + 0.33) * Math.PI * 2.0);
          double c = 0.5 + 0.5 * Math.Sin((u * 3.7 + t * 0.09 * dir + 0.66) * Math.PI * 2.0);
          double f = (a * 0.5 + b2 * 0.35 + c * 0.15);
          double r, g, bb;
          Pal(f, out r, out g, out bb);
          double v = 0.35 + 0.65 * f;
          SetZone(i, r * v, g * v, bb * v);
        }
        break;
      }

      // ---------------- information ----------------
      case "battery": {
        DrawBattery(N);
        break;
      }
      case "cpu": {
        DrawCpu(N);
        break;
      }
      case "clock": {
        // Hue follows time of day; a bright marker walks with the minutes.
        DateTime nowT = DateTime.Now;
        double dayF = (nowT.Hour * 3600.0 + nowT.Minute * 60.0 + nowT.Second) / 86400.0;
        double mF   = (nowT.Minute * 60.0 + nowT.Second) / 3600.0;
        for (int i = 0; i < N; i++) {
          double r, g, b;
          Hsv(210.0 + 150.0 * Math.Sin(dayF * Math.PI * 2.0 - Math.PI / 2.0), 0.85, 1.0, out r, out g, out b);
          double d = Math.Abs(SlotPos[i] - mF);
          if (d > 0.5) d = 1.0 - d;
          double mark = Math.Exp(-d * 26.0);
          double v = 0.16 + 0.84 * mark;
          SetZone(i, r * v, g * v, b * v);
        }
        break;
      }
      case "fire": {
        // Cool every zone, then randomly spark a few. The old model added
        // heat every frame, which drove the steady state above 1.0 so every
        // zone sat clamped at maximum - a flat, pale glow with no life.
        double cool  = Math.Pow(0.02, dt);              // frame-rate independent
        double spark = 1.0 - Math.Pow(1.0 - 0.10, dt * 60.0);
        for (int i = 0; i < N; i++) {
          heat[i] *= cool;
          if (rnd.NextDouble() < spark) heat[i] += 0.30 + rnd.NextDouble() * 0.45;
          if (heat[i] > 1.0) heat[i] = 1.0;
          double v = heat[i];
          // Blackbody-ish ramp in LINEAR light. Blue is held at zero until
          // the zone is genuinely hot, so the fire stays saturated instead
          // of washing out to pale orange.
          double lr = v * 1.45; if (lr > 1.0) lr = 1.0;
          double g2 = (v - 0.32) * 1.5; if (g2 < 0) g2 = 0; if (g2 > 1) g2 = 1;
          double b2 = (v - 0.78) * 3.0; if (b2 < 0) b2 = 0; if (b2 > 1) b2 = 1;
          SetZone(i, ToSrgb(lr), ToSrgb(g2 * g2), ToSrgb(b2 * b2 * b2));
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
    double lastNow = 0.0;
    double phase   = 0.0;
    long freq = Stopwatch.Frequency;
    long per  = freq / Fps;
    long next = sw.ElapsedTicks + per;
    double nextAssert = 0.0;
    bool woke = false;
    try {
      while (running) {
        double now = sw.ElapsedTicks / (double)freq;
        double dt  = now - lastNow;

        // A frame that took far longer than it should means the machine was
        // suspended or the thread was frozen. That is direct evidence of a
        // wake, and unlike PowerModeChanged it works for Modern Standby.
        if (dt > 1.5) woke = true;

        lastNow = now;
        if (dt <= 0 || dt > 0.25) dt = 1.0 / Fps;
        // Accumulate phase rather than using now*Speed: that would teleport
        // the animation every time the speed slider moved.
        phase += dt * Speed;

        // Reconnect before drawing, so the very first frame after a resume
        // already lands on the keyboard.
        if (DeviceLost) {
          if (!Reopen()) {
            // Device not back yet. Wait a beat instead of hammering it.
            Thread.Sleep(400);
            next = sw.ElapsedTicks + per;
            continue;
          }
        }

        // Re-assert ownership on a slow heartbeat, and immediately after a
        // detected wake. Costs one 51-byte feature report every 3 seconds.
        if (woke || now >= nextAssert) {
          ReAssert();
          nextAssert = now + 3.0;
          woke = false;
        }

        Frame(phase, dt);
        // Reopen()/ReAssert() invalidate the previous-colour cache, so the
        // next frame is a full repaint even for a static effect.
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
    for (int i = 0; i < LampCount; i++) {
      fr[i]=0; fg[i]=0; fb[i]=0;
      er[i]=0; eg[i]=0; eb[i]=0;
    }
    Push(true);
  }

  public void Solid(int r, int g, int b) {
    // Static colour: zero the dither error so the output is perfectly
    // steady rather than shimmering between two adjacent bytes.
    double rr = r * Brightness, gg = g * Brightness, bb = b * Brightness;
    if (rr > 255) rr = 255; if (gg > 255) gg = 255; if (bb > 255) bb = 255;
    if (rr < 0) rr = 0;     if (gg < 0) gg = 0;     if (bb < 0) bb = 0;
    for (int i = 0; i < LampCount; i++) {
      fr[i]=rr; fg[i]=gg; fb[i]=bb;
      er[i]=0;  eg[i]=0;  eb[i]=0;
    }
    Push(true);
  }

  public void Close() {
    if (h != IntPtr.Zero) { CloseHandle(h); h = IntPtr.Zero; }
  }
}
// ====================================================================
//  AUDIO LOOPBACK CAPTURE
//  Pure WASAPI over COM interop - no NAudio, no drivers, no downloads.
//  Captures whatever the speakers are playing and turns it into a
//  16-band spectrum the lighting effects can read.
// ====================================================================
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
  int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
  int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
}

[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
  int Activate(ref Guid iid, int clsCtx, IntPtr actParams,
               [MarshalAs(UnmanagedType.IUnknown)] out object iface);
}

[ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioClient {
  int Initialize(int shareMode, int streamFlags, long bufDuration,
                 long periodicity, IntPtr format, IntPtr sessionGuid);
  int GetBufferSize(out uint frames);
  int GetStreamLatency(out long latency);
  int GetCurrentPadding(out uint padding);
  int IsFormatSupported(int shareMode, IntPtr format, IntPtr closest);
  int GetMixFormat(out IntPtr format);
  int GetDevicePeriod(out long defPeriod, out long minPeriod);
  int Start();
  int Stop();
  int Reset();
  int SetEventHandle(IntPtr h);
  int GetService(ref Guid riid, [MarshalAs(UnmanagedType.IUnknown)] out object ppv);
}

[ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioCaptureClient {
  int GetBuffer(out IntPtr data, out uint frames, out uint flags,
                out long devPos, out long qpcPos);
  int ReleaseBuffer(uint frames);
  int GetNextPacketSize(out uint frames);
}

public class AudioCap {
  const int N = 1024;                 // FFT size
  public const int BANDS = 16;

  public volatile bool  Ok      = false;
  public volatile string Err    = "";
  public volatile float[] Bands = new float[BANDS];
  public volatile float Level   = 0f;   // overall loudness 0..1
  public volatile float Bass    = 0f;   // low-end energy 0..1
  public volatile float Beat    = 0f;   // decays after a bass hit

  IAudioClient cli;
  IAudioCaptureClient cap;
  Thread th;
  volatile bool run = false;

  int rate = 48000, chans = 2, bits = 32;
  bool isFloat = true;

  readonly double[] ring = new double[N];
  int ringPos = 0;
  readonly double[] re = new double[N];
  readonly double[] im = new double[N];
  readonly double[] win = new double[N];
  readonly float[] smooth = new float[BANDS];
  readonly int[] bandLo = new int[BANDS];
  readonly int[] bandHi = new int[BANDS];
  double bassAvg = 0.0;

  public AudioCap() {
    for (int i = 0; i < N; i++)                     // Hann window
      win[i] = 0.5 * (1.0 - Math.Cos(2.0 * Math.PI * i / (N - 1)));
  }

  public bool Start() {
    try {
      Type t = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
      IMMDeviceEnumerator en = (IMMDeviceEnumerator)Activator.CreateInstance(t);
      IMMDevice dev;
      // 0 = eRender (speakers), 0 = eConsole
      if (en.GetDefaultAudioEndpoint(0, 0, out dev) != 0 || dev == null) {
        Err = "no playback device"; return false;
      }
      Guid iidAc = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
      object o;
      if (dev.Activate(ref iidAc, 23, IntPtr.Zero, out o) != 0) {
        Err = "activate failed"; return false;
      }
      cli = (IAudioClient)o;

      IntPtr fmt;
      if (cli.GetMixFormat(out fmt) != 0 || fmt == IntPtr.Zero) {
        Err = "no mix format"; return false;
      }
      int tag = Marshal.ReadInt16(fmt, 0) & 0xFFFF;
      chans   = Marshal.ReadInt16(fmt, 2) & 0xFFFF;
      rate    = Marshal.ReadInt32(fmt, 4);
      bits    = Marshal.ReadInt16(fmt, 14) & 0xFFFF;
      isFloat = (tag == 3);
      if (tag == 0xFFFE && Marshal.ReadInt16(fmt, 16) >= 22) {
        // WAVEFORMATEXTENSIBLE: the real type is in SubFormat at +24
        int sub = Marshal.ReadInt32(fmt, 24);
        isFloat = (sub == 3);
      }
      if (chans < 1) chans = 2;

      // 0 = shared, 0x00020000 = loopback, 200ms buffer
      int hr = cli.Initialize(0, 0x00020000, 2000000, 0, fmt, IntPtr.Zero);
      Marshal.FreeCoTaskMem(fmt);
      if (hr != 0) { Err = "init failed 0x" + hr.ToString("X"); return false; }

      Guid iidCap = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
      object oc;
      if (cli.GetService(ref iidCap, out oc) != 0) { Err = "no capture service"; return false; }
      cap = (IAudioCaptureClient)oc;

      PrepBands();
      if (cli.Start() != 0) { Err = "start failed"; return false; }

      run = true;
      th = new Thread(new ThreadStart(Pump));
      th.IsBackground = true;
      th.Priority = ThreadPriority.BelowNormal;
      th.Start();
      Ok = true;
      return true;
    } catch (Exception ex) {
      Err = ex.Message;
      return false;
    }
  }

  // Log-spaced band edges:pitch perception is logarithmic, so linear bins
  // would put almost everything in the first two bars.
  void PrepBands() {
    // Start at 80Hz, not 40: at 48kHz/1024 one bin is 47Hz, so bands below
    // ~90Hz would all collapse onto bins 1-2 and the first three bars would
    // move as one. Also force every band to start above the previous one.
    double lo = 80.0, hi = Math.Min(15000.0, rate / 2.0 - 1.0);
    double binHz = (double)rate / N;
    int prev = 0;
    for (int b = 0; b < BANDS; b++) {
      double f0 = lo * Math.Pow(hi / lo, b / (double)BANDS);
      double f1 = lo * Math.Pow(hi / lo, (b + 1) / (double)BANDS);
      int i0 = (int)(f0 / binHz), i1 = (int)(f1 / binHz);
      if (i0 <= prev) i0 = prev + 1;      // never reuse the previous band
      if (i0 < 1) i0 = 1;
      if (i1 < i0) i1 = i0;
      if (i1 > N / 2 - 1) i1 = N / 2 - 1;
      if (i0 > N / 2 - 1) i0 = N / 2 - 1;
      bandLo[b] = i0; bandHi[b] = i1;
      prev = i1;
    }
  }

  public void Stop() {
    run = false;
    try { if (th != null) th.Join(400); } catch { }
    try { if (cli != null) cli.Stop(); } catch { }
    cap = null; cli = null; Ok = false;
  }

  void Pump() {
    while (run) {
      try {
        uint avail;
        if (cap.GetNextPacketSize(out avail) != 0) { Thread.Sleep(10); continue; }
        if (avail == 0) { Thread.Sleep(8); Decay(); continue; }

        while (avail > 0 && run) {
          IntPtr p; uint frames, flags; long dp, qp;
          if (cap.GetBuffer(out p, out frames, out flags, out dp, out qp) != 0) break;
          bool silent = (flags & 0x2) != 0;
          if (frames > 0) {
            if (silent) {
              for (int i = 0; i < frames; i++) { ring[ringPos] = 0.0; ringPos = (ringPos + 1) % N; }
            } else {
              Ingest(p, (int)frames);
            }
          }
          cap.ReleaseBuffer(frames);
          if (cap.GetNextPacketSize(out avail) != 0) break;
        }
        Analyse();
      } catch {
        Thread.Sleep(50);
      }
    }
  }

  // Mix all channels down to mono and push into the ring buffer.
  void Ingest(IntPtr p, int frames) {
    int stride = (bits / 8) * chans;
    for (int f = 0; f < frames; f++) {
      double s = 0.0;
      IntPtr baseP = (IntPtr)(p.ToInt64() + (long)f * stride);
      for (int c = 0; c < chans; c++) {
        if (isFloat && bits == 32) {
          // ReadInt32 + BitConverter avoids an unsafe float* cast
          int raw = Marshal.ReadInt32(baseP, c * 4);
          s += BitConverter.ToSingle(BitConverter.GetBytes(raw), 0);
        } else if (bits == 16) {
          s += Marshal.ReadInt16(baseP, c * 2) / 32768.0;
        } else if (bits == 32) {
          s += Marshal.ReadInt32(baseP, c * 4) / 2147483648.0;
        }
      }
      ring[ringPos] = s / chans;
      ringPos = (ringPos + 1) % N;
    }
  }

  void Decay() {
    float[] outB = new float[BANDS];
    for (int b = 0; b < BANDS; b++) { smooth[b] *= 0.86f; outB[b] = smooth[b]; }
    Bands = outB;
    Level *= 0.86f;
    Bass  *= 0.86f;
    Beat  *= 0.80f;
  }

  void Analyse() {
    for (int i = 0; i < N; i++) {
      re[i] = ring[(ringPos + i) % N] * win[i];
      im[i] = 0.0;
    }
    Fft();

    float[] outB = new float[BANDS];
    double rms = 0.0;
    for (int i = 0; i < N; i++) rms += ring[i] * ring[i];
    rms = Math.Sqrt(rms / N);

    for (int b = 0; b < BANDS; b++) {
      double sum = 0.0; int n = 0;
      for (int i = bandLo[b]; i <= bandHi[b]; i++) {
        double mag = Math.Sqrt(re[i] * re[i] + im[i] * im[i]) / (N / 2.0);
        sum += mag; n++;
      }
      double v = (n > 0) ? sum / n : 0.0;
      // dB scale: raw magnitudes are uselessly spiky
      double db = 20.0 * Math.Log10(v + 1e-9);
      double nv = (db + 62.0) / 52.0;          // -62dB..-10dB -> 0..1
      if (nv < 0) nv = 0; if (nv > 1) nv = 1;
      // Tilt: high frequencies carry far less energy, lift them so the
      // top of the spectrum is not permanently dead.
      nv *= 0.72 + 0.55 * (b / (double)(BANDS - 1));
      if (nv > 1) nv = 1;
      float f = (float)nv;
      // fast attack, slow release
      if (f > smooth[b]) smooth[b] = smooth[b] + (f - smooth[b]) * 0.55f;
      else               smooth[b] = smooth[b] + (f - smooth[b]) * 0.16f;
      outB[b] = smooth[b];
    }
    Bands = outB;

    double lvl = (rms * 4.0); if (lvl > 1) lvl = 1;
    Level = (float)(Level * 0.7 + lvl * 0.3);

    double bs = (outB[0] + outB[1] + outB[2]) / 3.0;
    Bass = (float)bs;
    bassAvg = bassAvg * 0.95 + bs * 0.05;
    if (bs > bassAvg * 1.35 && bs > 0.18) Beat = 1.0f;
    else Beat *= 0.88f;
  }

  // In-place iterative radix-2 FFT.
  void Fft() {
    int n = N;
    for (int i = 1, j = 0; i < n; i++) {
      int bit = n >> 1;
      for (; (j & bit) != 0; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) {
        double tr = re[i]; re[i] = re[j]; re[j] = tr;
        double ti = im[i]; im[i] = im[j]; im[j] = ti;
      }
    }
    for (int len = 2; len <= n; len <<= 1) {
      double ang = -2.0 * Math.PI / len;
      double wr = Math.Cos(ang), wi = Math.Sin(ang);
      for (int i = 0; i < n; i += len) {
        double cr = 1.0, ci = 0.0;
        for (int k = 0; k < len / 2; k++) {
          int a = i + k, b = i + k + len / 2;
          double xr = re[b] * cr - im[b] * ci;
          double xi = re[b] * ci + im[b] * cr;
          re[b] = re[a] - xr; im[b] = im[a] - xi;
          re[a] = re[a] + xr; im[a] = im[a] + xi;
          double ncr = cr * wr - ci * wi;
          ci = cr * wi + ci * wr;
          cr = ncr;
        }
      }
    }
  }
}

// ====================================================================
//  SYSTEM INFO  -  battery and CPU load, cheap P/Invoke only
// ====================================================================
public class SysInfo {
  [StructLayout(LayoutKind.Sequential)]
  struct PWR {
    public byte ACLineStatus;
    public byte BatteryFlag;
    public byte BatteryLifePercent;
    public byte SystemStatusFlag;
    public int  BatteryLifeTime;
    public int  BatteryFullLifeTime;
  }
  [DllImport("kernel32.dll")] static extern bool GetSystemPowerStatus(out PWR s);
  [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kern, out long usr);

  public volatile int   Battery  = -1;      // 0..100, -1 unknown
  public volatile bool  Charging = false;
  public volatile bool  OnAc     = false;
  public volatile float Cpu      = 0f;      // 0..1 smoothed

  long pIdle = 0, pKern = 0, pUsr = 0;
  double cpuSm = 0.0;

  public void Poll() {
    try {
      PWR p;
      if (GetSystemPowerStatus(out p)) {
        Battery  = (p.BatteryLifePercent <= 100) ? p.BatteryLifePercent : -1;
        OnAc     = (p.ACLineStatus == 1);
        Charging = ((p.BatteryFlag & 8) != 0) || (OnAc && Battery >= 0 && Battery < 100);
      }
    } catch { }
    try {
      long i2, k2, u2;
      if (GetSystemTimes(out i2, out k2, out u2)) {
        long di = i2 - pIdle, dk = k2 - pKern, du = u2 - pUsr;
        pIdle = i2; pKern = k2; pUsr = u2;
        long tot = dk + du;                    // kernel already includes idle
        if (tot > 0) {
          double busy = (tot - di) / (double)tot;
          if (busy < 0) busy = 0; if (busy > 1) busy = 1;
          cpuSm = cpuSm * 0.7 + busy * 0.3;
          Cpu = (float)cpuSm;
        }
      }
    } catch { }
  }
}

// ====================================================================
//  SCREEN SAMPLER  -  average screen colour for the ambient mode.
//  Raw GDI so it needs no System.Drawing reference.
// ====================================================================
public class ScreenCap {
  [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
  [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int i);
  [DllImport("gdi32.dll")]  static extern IntPtr CreateCompatibleDC(IntPtr dc);
  [DllImport("gdi32.dll")]  static extern bool DeleteDC(IntPtr dc);
  [DllImport("gdi32.dll")]  static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
  [DllImport("gdi32.dll")]  static extern bool DeleteObject(IntPtr o);
  [DllImport("gdi32.dll")]  static extern bool StretchBlt(IntPtr d, int dx, int dy, int dw, int dh,
                                                          IntPtr s, int sx, int sy, int sw, int sh, int rop);
  [DllImport("gdi32.dll")]  static extern int SetStretchBltMode(IntPtr dc, int mode);
  [DllImport("gdi32.dll")]  static extern IntPtr CreateDIBSection(IntPtr dc, ref BITMAPINFO bmi, uint usage,
                                                                  out IntPtr bits, IntPtr sect, uint off);
  [StructLayout(LayoutKind.Sequential)]
  struct BITMAPINFOHEADER {
    public uint biSize; public int biWidth; public int biHeight;
    public ushort biPlanes; public ushort biBitCount; public uint biCompression;
    public uint biSizeImage; public int biXPelsPerMeter; public int biYPelsPerMeter;
    public uint biClrUsed; public uint biClrImportant;
  }
  [StructLayout(LayoutKind.Sequential)]
  struct BITMAPINFO { public BITMAPINFOHEADER h; public uint c0; }

  const int W = 16, H = 9;
  public volatile int[] Cols = new int[W];    // one colour per column, 0xRRGGBB
  public volatile int Avg = 0;
  public volatile bool Ok = false;
  Thread th; volatile bool run = false;

  public void Start() {
    run = true;
    th = new Thread(new ThreadStart(Pump));
    th.IsBackground = true;
    th.Priority = ThreadPriority.Lowest;
    th.Start();
  }
  public void Stop() {
    run = false;
    try { if (th != null) th.Join(400); } catch { }
    Ok = false;
  }

  void Pump() {
    while (run) {
      try { Grab(); Ok = true; } catch { Ok = false; }
      Thread.Sleep(55);                 // ~18 fps is plenty for ambient
    }
  }

  void Grab() {
    int sw = GetSystemMetrics(0), sh = GetSystemMetrics(1);
    if (sw <= 0 || sh <= 0) return;
    IntPtr screen = GetDC(IntPtr.Zero);
    IntPtr mem = CreateCompatibleDC(screen);
    BITMAPINFO bi = new BITMAPINFO();
    bi.h.biSize = 40; bi.h.biWidth = W; bi.h.biHeight = -H;   // top-down
    bi.h.biPlanes = 1; bi.h.biBitCount = 32; bi.h.biCompression = 0;
    IntPtr bits;
    IntPtr dib = CreateDIBSection(mem, ref bi, 0, out bits, IntPtr.Zero, 0);
    IntPtr old = SelectObject(mem, dib);
    SetStretchBltMode(mem, 4);                                 // HALFTONE
    StretchBlt(mem, 0, 0, W, H, screen, 0, 0, sw, sh, 0x00CC0020);

    int[] cols = new int[W];
    long ar = 0, ag = 0, ab = 0;
    for (int x = 0; x < W; x++) {
      long r = 0, g = 0, b = 0;
      for (int y = 0; y < H; y++) {
        int px = Marshal.ReadInt32(bits, (y * W + x) * 4);
        b += (px & 0xFF); g += ((px >> 8) & 0xFF); r += ((px >> 16) & 0xFF);
      }
      r /= H; g /= H; b /= H;
      cols[x] = (int)((r << 16) | (g << 8) | b);
      ar += r; ag += g; ab += b;
    }
    Cols = cols;
    Avg = (int)(((ar / W) << 16) | ((ag / W) << 8) | (ab / W));

    SelectObject(mem, old);
    DeleteObject(dib);
    DeleteDC(mem);
    ReleaseDC(IntPtr.Zero, screen);
  }
}

'@
}

$HIDGUID='{4d1e55b2-f16f-11cf-88cb-001111000030}'
$INVALID=[IntPtr](-1); $HIDOK=0x00110000
$GENRW=[uint32]3221225472; $GENW=[uint32]1073741824
$SHARERW=[uint32]3; $OPENEXIST=[uint32]3

$U_LAMPCOUNT=0x03; $U_LAMPID=0x21; $U_POSX=0x23; $U_POSY=0x24
$U_REDLVL=0x28; $U_GRNLVL=0x29; $U_BLULVL=0x2A; $U_INTLVL=0x2B
$U_RED=0x51; $U_GREEN=0x52; $U_BLUE=0x53; $U_INTENSITY=0x54; $U_FLAGS=0x55
$U_IDSTART=0x61; $U_IDEND=0x62; $U_AUTONOMOUS=0x71

# ============================================================================
# DISCOVERY  (proven working; unchanged in shape)
# ============================================================================
Say ""
Say ("AURA-BACKGROUND v15   effect={0}  fps={1}  speed={2}" -f $Effect,$Fps,$Speed) 'Cyan'
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
$posY=New-Object int[] $lampCount
for ($i=0;$i -lt $lampCount;$i++) { $posX[$i]=$i*1000; $posY[$i]=0 }
if ($rReq -and $rResp) {
    $pos=New-Object object[] $lampCount
    for ($i=0;$i -lt $lampCount;$i++) {
        $q=New-Rpt $rReq; Set-Val $rReq $q $U_LAMPID $i; [void](Send-Rpt $rReq $q)
        $rb=New-Rpt $rResp; $x=$i*1000; $y=0
        if ([HidNative]::HidD_GetFeature($h,$rb,$rb.Length)) {
            $gx=Get-Val $rResp $rb $U_POSX; if ($null -ne $gx) { $x=$gx }
            $gy=Get-Val $rResp $rb $U_POSY; if ($null -ne $gy) { $y=$gy }
            if ($i -eq 0) {
                $v=Get-Val $rResp $rb $U_REDLVL; if ($v) { $RMAX=$v }
                $v=Get-Val $rResp $rb $U_GRNLVL; if ($v) { $GMAX=$v }
                $v=Get-Val $rResp $rb $U_BLULVL; if ($v) { $BMAX=$v }
                $v=Get-Val $rResp $rb $U_INTLVL; if ($v) { $IMAX=$v }
            }
        }
        $posX[$i]=$x; $posY[$i]=$y
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
$interleaved=$false
if ($rMulti) {
    $mlen=Rpt-Len $rMulti

    # ReportCount from the descriptor is the count for ONE usage entry and
    # on this firmware it reads back as 1 even though the report really
    # carries 8 lamps. Derive the true slot count from the report length:
    #   len = 1 id + 1 count + 1 flags + slots*2 (lamp ids) + slots*4 (rgbi)
    $slots=[int]$rMulti.Usages[$U_RED]; if ($slots -lt 1) { $slots=1 }
    $byLen=[int][Math]::Floor(($mlen - 3) / 6)
    if ($byLen -gt $slots) {
        Say ("  Descriptor says {0} slot(s); report length implies {1}. Using {1}." -f $slots,$byLen) 'DarkGray'
        $slots=$byLen
    }
    if ($slots -lt 1) { $slots=1 }

    $offCnt=Probe-Off $rMulti $U_LAMPCOUNT 1
    $offFlg=Probe-Off $rMulti $U_FLAGS     1
    $offId =Probe-Off $rMulti $U_LAMPID    1
    $offR  =Probe-Off $rMulti $U_RED       1
    $offG  =Probe-Off $rMulti $U_GREEN     1
    $offB  =Probe-Off $rMulti $U_BLUE      1
    $offI  =Probe-Off $rMulti $U_INTENSITY 1

    # Probe-Off reports the LAST byte HidP_SetUsageValue touched, which for
    # a multi-instance usage is the final instance. Two layouts are possible.
    #
    #   planar:      R R R R R R R R G G G G G G G G B B ... I I
    #                planes are $slots apart
    #   interleaved: R G B I  R G B I  R G B I ...
    #                channels are 1 apart, lamps are 4 apart
    #
    # Consecutive r/g/b/i offsets can only mean interleaved.
    if ($offR -ge 0 -and $offG -eq ($offR+1) -and $offB -eq ($offG+1) -and $offI -eq ($offB+1)) {
        $interleaved=$true
        # Wind back from the last instance to the first.
        $offR=$offR-($slots-1)*4; $offG=$offR+1; $offB=$offR+2; $offI=$offR+3
        if ($offCnt -ge 0 -and $offFlg -ge 0 -and $offId -ge 0 -and $offR -gt $offId) {
            $fast=$true
            Say ("  Interleaved layout, {0} lamps per report." -f $slots) 'DarkGray'
        }
    }
    elseif ($offId -ge 0 -and $offR -ge 0 -and $offG -ge 0 -and $offB -ge 0 -and $offI -ge 0 -and
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
            if ($interleaved) { $bb2[$offI+$s*4]=[byte]$IMAX } else { $bb2[$offI+$s]=[byte]$IMAX } }
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
                        $st=if ($interleaved) { $s*4 } else { $s }
                        $bb2[$offR+$st]=[byte](($fr[$i]*$RMAX)/255)
                        $bb2[$offG+$st]=[byte](($fg[$i]*$GMAX)/255)
                        $bb2[$offB+$st]=[byte](($fb[$i]*$BMAX)/255) }
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

# --- optional data sources -------------------------------------------
# Only started when an effect actually needs them, so the idle cost of a
# plain gradient stays exactly what it was.
$script:Sys = New-Object SysInfo
$script:Sys.Poll()
$eng.Sys = $script:Sys
$script:Audio  = $null
$script:Screen = $null

function Need-Audio  { param($e) return @('spectrum','vumeter','beat','pulsebass') -contains $e }
function Need-Screen { param($e) return ($e -eq 'ambient') }

function Sync-Sources {
    param($tok)
    if (Need-Audio $tok) {
        if (-not $script:Audio) {
            $script:Audio = New-Object AudioCap
            if ($script:Audio.Start()) {
                $eng.Audio = $script:Audio
                Say ("  Audio capture: on") 'DarkGray'
            } else {
                Say ("  Audio capture failed: " + $script:Audio.Err) 'Yellow'
                $script:Audio = $null
            }
        }
    } elseif ($script:Audio) {
        $script:Audio.Stop(); $eng.Audio = $null; $script:Audio = $null
    }

    if (Need-Screen $tok) {
        if (-not $script:Screen) {
            $script:Screen = New-Object ScreenCap
            $script:Screen.Start()
            $eng.Screen = $script:Screen
            Say "  Screen sampling: on" 'DarkGray'
        }
    } elseif ($script:Screen) {
        $script:Screen.Stop(); $eng.Screen = $null; $script:Screen = $null
    }
}
$eng.Interleaved = $interleaved
$eng.Equalise   = ($Equalise -eq 'on')
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

# ---- where each zone sits, as a number the effects can travel along ----
#
# -Layout across : left-to-right only. Zones stacked at the same X (the
#                  light-bar corners) therefore all share a colour.
# -Layout loop   : distance walked around the CHASSIS PERIMETER. This is
#                  what makes a gradient actually circle the light bar
#                  instead of flashing the whole bar at once.
$xs = @($order | ForEach-Object { $posX[$_] })
$ys = @($order | ForEach-Object { $posY[$_] })
$xmin = ($xs | Measure-Object -Minimum).Minimum
$xmax = ($xs | Measure-Object -Maximum).Maximum
$ymin = ($ys | Measure-Object -Minimum).Minimum
$ymax = ($ys | Measure-Object -Maximum).Maximum
$spanX = $xmax - $xmin
$spanY = $ymax - $ymin

$sp = New-Object double[] $lampCount

# Both layouts are always computed so the control panel can switch between
# them live without restarting the engine.
$spAcross = New-Object double[] $lampCount
for ($s=0; $s -lt $lampCount; $s++) {
    if ($spanX -gt 0) { $spAcross[$s] = ($xs[$s] - $xmin) / [double]$spanX }
    elseif ($lampCount -gt 1) { $spAcross[$s] = $s / [double]($lampCount-1) }
    else { $spAcross[$s] = 0.0 }
}

$spLoop = $null
if ($spanX -gt 0 -and $spanY -gt 0) {
    $perimA = 2.0 * ($spanX + $spanY)
    $innerA = 0.12 * [Math]::Min($spanX, $spanY)
    $spLoop = New-Object double[] $lampCount
    for ($s=0; $s -lt $lampCount; $s++) {
        $x = $xs[$s] - $xmin
        $y = $ys[$s] - $ymin
        $dT = $y; $dB = $spanY - $y; $dL = $x; $dR = $spanX - $x
        $mm = [Math]::Min([Math]::Min($dT,$dB),[Math]::Min($dL,$dR))
        if     ($mm -gt $innerA) { $spLoop[$s] = $x / $perimA }
        elseif ($mm -eq $dT)     { $spLoop[$s] = $x / $perimA }
        elseif ($mm -eq $dR)     { $spLoop[$s] = ($spanX + $y) / $perimA }
        elseif ($mm -eq $dB)     { $spLoop[$s] = ($spanX + $spanY + ($spanX - $x)) / $perimA }
        else                     { $spLoop[$s] = ($spanX + $spanY + $spanX + ($spanY - $y)) / $perimA }
    }
}

if ($Layout -eq 'loop' -and $spanX -gt 0 -and $spanY -gt 0) {
    # Walk the rectangle clockwise from the top-left corner.
    $perim = 2.0 * ($spanX + $spanY)
    $d = New-Object double[] $lampCount
    # Zones sitting well inside the rectangle are the keyboard deck, not the
    # light bar. Nearest-edge would scatter that row around the loop, so
    # project interior zones onto the top edge by X and keep the row intact.
    $inner = 0.12 * [Math]::Min($spanX, $spanY)
    for ($s=0; $s -lt $lampCount; $s++) {
        $x = $xs[$s] - $xmin
        $y = $ys[$s] - $ymin
        $dTop = $y; $dBot = $spanY - $y; $dLeft = $x; $dRight = $spanX - $x
        $m = [Math]::Min([Math]::Min($dTop,$dBot),[Math]::Min($dLeft,$dRight))
        if     ($m -gt $inner)  { $d[$s] = $x }                                      # interior
        elseif ($m -eq $dTop)   { $d[$s] = $x }
        elseif ($m -eq $dRight) { $d[$s] = $spanX + $y }
        elseif ($m -eq $dBot)   { $d[$s] = $spanX + $spanY + ($spanX - $x) }
        else                    { $d[$s] = $spanX + $spanY + $spanX + ($spanY - $y) }
    }
    for ($s=0; $s -lt $lampCount; $s++) { $sp[$s] = $d[$s] / $perim }
    Say "  Layout: loop (gradient travels around the chassis)." 'DarkGray'
}
else {
    for ($s=0; $s -lt $lampCount; $s++) {
        if ($spanX -gt 0) { $sp[$s] = ($xs[$s] - $xmin) / [double]$spanX }
        else {
            $sp[$s] = if ($lampCount -gt 1) { $s / [double]($lampCount-1) } else { 0.0 }
        }
    }
    if ($Layout -eq 'loop') { Say "  Layout: loop requested but zones are in a line; using across." 'Yellow' }
}
$eng.SlotPos       = $sp
$eng.SlotPosAcross = $spAcross
if ($spLoop) { $eng.SlotPosLoop = $spLoop } else { $eng.SlotPosLoop = $spAcross }
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
# NOTE: 'static' deliberately falls through to the normal run loop. It used
# to paint once and exit, which meant the app could not change the colour,
# brightness or effect afterwards without killing and relaunching. The
# render loop handles it through the default branch (solid palette[0]) and
# costs nothing, so live control keeps working.
if ($Effect -eq 'static' -and $NoLive) {
    $eng.Solid($stops[0][0],$stops[0][1],$stops[0][2]); $eng.Close()
    Say "  Solid colour applied." 'Green'
    return
}

Say ""
Say (" Running at {0} fps on a compiled thread. Ctrl+C to stop." -f $eng.Fps) 'Green'
Say ""

Sync-Sources $Effect
$eng.Start()

# ---------------------------------------------------------------------------
# LIVE CONTROL
#
# Two ways to change brightness while the effect is running:
#
#  1. The keyboard's own backlight keys. ASUS fires WMI events 0xC4 (up),
#     0xC5 (down) and 0xC7 (toggle) from the ATK driver. We watch for those
#     and move our own brightness, so the hardware keys keep working even
#     though the firmware is not driving the LEDs any more.
#
#  2. A tiny state file the control panel writes. Lets the panel change
#     brightness without killing and relaunching the engine.
# ---------------------------------------------------------------------------
$stateDir  = Join-Path $env:LOCALAPPDATA 'KeyboardLighting'
if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Force -Path $stateDir | Out-Null }
$liveFile  = Join-Path $stateDir 'live.txt'
$themeFile = Join-Path $stateDir 'theme.json'
$script:SysTick = 0
$script:LastAc  = $null
$script:LastPct = 100
$script:LiveLevel = [int]([Math]::Round($Brightness * 1000))
# Ignore whatever theme file is already on disk: the arguments we were
# launched with already describe it. Only react to later writes.
$script:ThemeStamp = 0
if (Test-Path $themeFile) {
    try { $script:ThemeStamp = (Get-Item $themeFile).LastWriteTimeUtc.Ticks } catch { }
}

function Set-Live([int]$level) {
    if ($level -lt 0)    { $level = 0 }
    if ($level -gt 1000) { $level = 1000 }
    $script:LiveLevel = $level
    $eng.LiveBrightness = $level
    $eng.LiveDirty = $true
    try { Set-Content -Path $liveFile -Value $level -Encoding ASCII -ErrorAction SilentlyContinue } catch { }
}

# --- wake from sleep -------------------------------------------------
# On resume the USB port has been power-cycled: the handle is dead and the
# firmware is back in autonomous mode. The render loop notices failed
# writes on its own, but this makes it immediate rather than ~8 frames
# later, and covers the case where the device stops ACKing without
# actually failing.
$resumeOk  = $false
$sessionOk = $false
try {
    Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) `
        -EventName PowerModeChanged -SourceIdentifier 'AuraPower' `
        -ErrorAction Stop | Out-Null
    $resumeOk = $true
} catch {
    Say "  Sleep/resume watch: unavailable." 'DarkGray'
}
# Lid close / lock / unlock often raises this when PowerModeChanged stays
# silent, which is exactly the Modern Standby case.
try {
    Register-ObjectEvent -InputObject ([Microsoft.Win32.SystemEvents]) `
        -EventName SessionSwitch -SourceIdentifier 'AuraSession' `
        -ErrorAction Stop | Out-Null
    $sessionOk = $true
} catch { }

# --- hardware backlight keys via ASUS ATK WMI ---
$wmiOk = $false
try {
    Register-WmiEvent -Class AsusAtkWmiEvent -Namespace 'root\wmi' `
        -SourceIdentifier 'AuraAtk' -ErrorAction Stop | Out-Null
    $wmiOk = $true
    Say "  Keyboard backlight keys: active (Fn brightness keys adjust this effect)." 'Green'
} catch {
    Say "  Keyboard backlight keys: unavailable (ASUS ATK WMI not present)." 'DarkGray'
}

$step = 125    # 8 steps across the full range, like the firmware
try {
    while ($true) {
        # --- resume from sleep / display wake ---
        if ($resumeOk) {
            $pe = Get-Event -SourceIdentifier 'AuraPower' -ErrorAction SilentlyContinue
            while ($pe) {
                $mode = ''
                try { $mode = [string]$pe.SourceEventArgs.Mode } catch { }
                Remove-Event -EventIdentifier $pe.EventIdentifier -ErrorAction SilentlyContinue
                if ($mode -eq 'Resume') {
                    # Do not force a Reopen here: after Modern Standby the
                    # handle is usually still valid and only ownership was
                    # lost. ReAssert covers that; genuine disconnects are
                    # still caught by failed writes in Push().
                    Start-Sleep -Milliseconds 800
                    $eng.ReAssert()
                    $eng.LiveDirty = $true
                }
                $pe = Get-Event -SourceIdentifier 'AuraPower' -ErrorAction SilentlyContinue
            }
        }

        # --- system info + automatic overlays ---
        $script:SysTick++
        if ($script:SysTick -ge 4) {          # ~ every 500ms
            $script:SysTick = 0
            $script:Sys.Poll()

            if ($OverlayOn) {
                $b   = $script:Sys.Battery
                $ac  = $script:Sys.OnAc
                $now = $eng.Now

                # power cable plugged in or pulled out
                if ($script:LastAc -ne $null -and $ac -ne $script:LastAc) {
                    $eng.OverlayMode  = 1
                    $eng.OverlayUntil = $now + 4.0
                }
                $script:LastAc = $ac

                # crossed a low-battery threshold on battery power
                if (-not $ac -and $b -ge 0) {
                    foreach ($thr in 20, 10, 5) {
                        if ($b -le $thr -and $script:LastPct -gt $thr) {
                            $eng.OverlayMode  = 1
                            $eng.OverlayUntil = $now + 6.0
                        }
                    }
                }
                if ($b -ge 0) { $script:LastPct = $b }
            }
        }

        # --- lock / unlock / lid ---
        if ($sessionOk) {
            $se = Get-Event -SourceIdentifier 'AuraSession' -ErrorAction SilentlyContinue
            while ($se) {
                Remove-Event -EventIdentifier $se.EventIdentifier -ErrorAction SilentlyContinue
                $eng.ReAssert()
                $eng.LiveDirty = $true
                $se = Get-Event -SourceIdentifier 'AuraSession' -ErrorAction SilentlyContinue
            }
        }

        if ($wmiOk) {
            $ev = Get-Event -SourceIdentifier 'AuraAtk' -ErrorAction SilentlyContinue
            while ($ev) {
                $code = 0
                try { $code = [int]$ev.SourceEventArgs.NewEvent.EventID } catch { }
                Remove-Event -EventIdentifier $ev.EventIdentifier -ErrorAction SilentlyContinue
                switch ($code) {
                    0xC4 { Set-Live ($script:LiveLevel + $step) }
                    0xC5 { Set-Live ($script:LiveLevel - $step) }
                    0xC7 {
                        $nl = 0
                        if ($script:LiveLevel -le 0) { $nl = 1000 }
                        Set-Live $nl
                    }
                }
                $ev = Get-Event -SourceIdentifier 'AuraAtk' -ErrorAction SilentlyContinue
            }
        }

        # --- panel-written brightness file (kept: the Fn keys use it too) ---
        if (Test-Path $liveFile) {
            try {
                $txt = (Get-Content $liveFile -Raw -ErrorAction Stop).Trim()
                $val = 0
                if ([int]::TryParse($txt, [ref]$val)) {
                    if ($val -ne $script:LiveLevel) {
                        $script:LiveLevel = $val
                        $eng.LiveBrightness = $val
                        $eng.LiveDirty = $true
                    }
                }
            } catch { }
        }

        # --- full live theme: effect, colours, speed and the toggles ---
        # The control panel writes this whenever anything changes, so the
        # lighting follows along without being torn down and restarted.
        if (Test-Path $themeFile) {
            try {
                $stamp = (Get-Item $themeFile -ErrorAction Stop).LastWriteTimeUtc.Ticks
                if ($stamp -ne $script:ThemeStamp) {
                    $script:ThemeStamp = $stamp
                    $j = Get-Content $themeFile -Raw -ErrorAction Stop | ConvertFrom-Json

                    if ($j.Effect) {
                        $eng.LiveEffect = [string]$j.Effect
                        Sync-Sources ([string]$j.Effect)
                    }

                    if ($null -ne $j.Speed) {
                        $eng.LiveSpeedMilli = [int]([Math]::Round([double]$j.Speed * 1000))
                    }

                    if ($j.Colors) {
                        $ns = @()
                        foreach ($cs in ([string]$j.Colors -split ',')) {
                            if ($cs.Trim()) { $ns += ,(ConvertFrom-Hex $cs) }
                        }
                        if ($ns.Count -eq 1) { $ns = @($ns[0], $ns[0]) }
                        if ($ns.Count -gt 2 -and
                            $ns[0][0] -eq $ns[-1][0] -and
                            $ns[0][1] -eq $ns[-1][1] -and
                            $ns[0][2] -eq $ns[-1][2]) {
                            $ns = @($ns[0..($ns.Count-2)])
                        }
                        if ($ns.Count -gt 0) {
                            $eng.LivePalR = [int[]]@($ns | ForEach-Object { $_[0] })
                            $eng.LivePalG = [int[]]@($ns | ForEach-Object { $_[1] })
                            $eng.LivePalB = [int[]]@($ns | ForEach-Object { $_[2] })
                        }
                    }

                    $fl = 0
                    if ([bool]$j.Mirror)   { $fl = $fl -bor 1 }
                    if ([bool]$j.Reverse)  { $fl = $fl -bor 2 }
                    if ([bool]$j.Equalise) { $fl = $fl -bor 4 }
                    if ([bool]$j.Loop)     { $fl = $fl -bor 8 }
                    $eng.LiveFlags = $fl

                    if ($null -ne $j.Brightness) {
                        $bv = [int]([Math]::Round([double]$j.Brightness * 1000))
                        if ($bv -lt 0) { $bv = 0 }
                        if ($bv -gt 1000) { $bv = 1000 }
                        $script:LiveLevel = $bv
                        $eng.LiveBrightness = $bv
                        try { Set-Content -Path $liveFile -Value $bv -Encoding ASCII -ErrorAction SilentlyContinue } catch { }
                    }

                    $eng.LiveDirty = $true
                }
            } catch { }
        }

        Start-Sleep -Milliseconds 120
    }
}
finally {
    Unregister-Event -SourceIdentifier 'AuraAtk' -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier 'AuraPower' -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier 'AuraSession' -ErrorAction SilentlyContinue
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
