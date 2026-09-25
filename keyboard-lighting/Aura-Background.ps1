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
                 'battery','cpu','clock',
                 'zonetest')]
    [string]$Effect = 'gradient',

    [string]$Colors = '#FF0000,#FF7F00,#FFFF00,#00FF00,#0000FF,#8B00FF',
    [string]$Color  = '#00B4FF',
    [string]$Color2 = '#FF0066',

    # Relative band width per colour, same order and count as -Colors.
    # '2,1' gives the first colour twice the strip of the second. Empty or
    # the wrong count means even, which is what it always did.
    [string]$Widths = '',
    [string]$BarWidths = '',

    [ValidateRange(0.01, 50.0)]
    [double]$Speed = 1.0,

    [ValidateRange(0.0, 1.0)]
    [double]$Brightness = 1.0,

    [ValidateRange(5, 144)]
    # Back to 60 after measuring what a frame actually costs. Each frame
    # sends two synchronous feature reports, and on this EC-backed keyboard
    # those take milliseconds; at 120 the pair can eat most of the 8.3 ms
    # budget, so frames land whenever the previous write returns rather
    # than on a steady beat - which looks like flicker, not smoothness.
    # 60 leaves generous headroom. The engine measures its own write cost
    # and backs the rate off further if even this is too fast.
    [int]$Fps = 60,

    [string]$Custom,

    # Process id of the app that launched us, or 0 when run by hand.
    #
    # Nothing else ties this process to the tray app, so if the app died the
    # engine carried on forever: an invisible powershell.exe still driving
    # the keyboard, with no tray icon left to stop it. The only way out was
    # Task Manager. When an owner is given we watch it, and shut ourselves
    # down properly the moment it disappears.
    #
    # Zones.ps1, MyEffect.ps1 and a manual run pass nothing, so they keep
    # the old behaviour of running until told to stop.
    [int]$OwnerPid = 0,

    [switch]$Mirror,
    [switch]$Reverse,

    # Briefly show battery status when the charger is plugged in or pulled
    # out, and when the battery gets low, then return to the chosen effect.
    [switch]$OverlayOn,

    # ---- light bar overrides -------------------------------------------
    # Anything omitted follows the keyboard's setting.
    [string]$BarEffect,
    [string]$BarColors,
    [double]$BarSpeed = -1,
    [double]$BarBrightness = -1,
    [switch]$BarMirror,
    [switch]$BarReverse,
    [ValidateSet('','on','off')]
    [string]$BarEqualise = '',
    [ValidateSet('','across','loop')]
    [string]$BarLayout = '',
    [switch]$BarOff,
    [switch]$KbdOff,
    # Master level, applied on top of each group's own brightness. The
    # Fn keys and the panel's master slider both drive this.
    [double]$Master = 1.0,
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
    [string]$Layout = 'loop',

    # Used by Zones.ps1: light only these zone numbers, hold, then exit.
    [string]$ZoneTest = '',
    [double]$HoldSeconds = 1.5,

    # What to leave the keyboard doing when this stops.
    #   off      all lamps dark
    #   white    plain white, so the keys stay readable
    #   firmware hand control back and let the keyboard do its own thing
    [ValidateSet('off','white','firmware')]
    [string]$OnExit = 'off',

    # Used by Zones.ps1: walk the ring one lamp at a time to show the path.
    [switch]$ChaseTest,
    [ValidateSet('bar','kbd')]
    [string]$ChaseWhich = 'bar'
)

$ErrorActionPreference = 'Stop'
function Say($msg, $col = 'Gray') { if (-not $Quiet) { Write-Host $msg -ForegroundColor $col } }

# ============================================================================
# NATIVE + COMPILED ENGINE
# ============================================================================
# The C# below is ~66 KB and used to be handed to Add-Type on every single
# start, which meant waiting for a compiler before a single key lit up.
# Setup now pre-builds it into Engine.dll, so the normal path is just loading
# an assembly. The source is still here and still compiles on demand: that is
# what happens if the DLL is missing, stale, or built by a different runtime,
# so a failed or half-finished Setup degrades to "slow" instead of "broken".
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$EngineDll = Join-Path $Here 'Engine.dll'
if (-not ('LampEngine' -as [type])) {
    if (Test-Path $EngineDll) {
        try {
            $src = Get-Item (Join-Path $Here 'Aura-Background.ps1') -ErrorAction SilentlyContinue
            $dll = Get-Item $EngineDll
            # A DLL older than the script it came from is from a previous
            # version. Ignore it rather than run yesterday's engine.
            if (-not $src -or $dll.LastWriteTime -ge $src.LastWriteTime) {
                Add-Type -Path $EngineDll -ErrorAction Stop
            }
        } catch { }
    }
}

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
# If this fails to compile the process would otherwise die here with the
# error going nowhere, and the keyboard would just stay dark. Record it.
try {
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Diagnostics;


// One palette, complete, as handed from the settings watcher to the render
// thread. Build it, publish it, never touch it again - that is what makes
// the hand-off safe without a lock. W may be null, meaning even bands.
public class PalSet {
  public readonly int[] R, G, B;
  public readonly double[] W;
  public PalSet(int[] r, int[] g, int[] b, double[] w) { R = r; G = g; B = b; W = w; }
  public int Count { get { return R.Length; } }
}

// One independently-controlled set of lamps. The deck keys and the light
// bar each get one of these, so they can run different effects, palettes
// and speeds at the same time.
public class Zone {
  public string Name = "";
  public int[]  Idx  = new int[0];     // indices into the engine's lamp arrays
  public double[] Pos = new double[0]; // 0..1 travel position within this group
  public double[] PosAcross = null;
  public double[] PosLoop   = null;
  public int N { get { return Idx.Length; } }

  public string Effect = "gradient";
  public double Speed  = 1.0;
  public double Brightness = 1.0;   // this group's own slider, 0..1
  public double Master     = 1.0;   // master slider / Fn keys, 0..1
  public bool   Mirror = false, Reverse = false, Equalise = true, Loop = false;
  public bool   Enabled = true;
  public double Dir { get { return Reverse ? -1.0 : 1.0; } }

  public int[] PalR = new int[] { 255, 0, 0 };
  public int[] PalG = new int[] { 0, 255, 0 };
  public int[] PalB = new int[] { 0, 0, 255 };
  // How wide each colour's band is, relative to the others. All 1 = the
  // even spacing this had before widths existed. Null or wrong-length is
  // treated as all 1, so an old theme file still behaves the same.
  public double[] PalW = null;

  public double[] plR, plG, plB, palGain;

  // The palette being faded OUT of, held for the length of a changeover.
  //
  // Swapping the palette outright is what made changing a colour flash.
  // The cycle keeps running while the colours underneath it are replaced,
  // so whatever the lamps were showing jumped straight to whatever the new
  // palette says for that same point in the cycle - measured at up to the
  // full 255 in a single frame, worst exactly when the strip was already
  // mid-crossfade. Keeping the old palette for a moment and easing across
  // turns that step into a short, deliberate blend, which is what the eye
  // reads as "the colours changed" rather than "something glitched".
  public double[] oldR, oldG, oldB, oldGain;
  public double[] oldW = null;
  public int      oldCount = 0;
  public double   XfadeLeft = 0.0;      // seconds remaining, 0 = not fading
  public double   XfadeTotal = 0.0;

  public double[] Heat = new double[0];
  public double Phase = 0.0;

  // live-update inbox, same pattern as the engine's
  public volatile int    LiveBrightness = -1;
  public volatile int    LiveMaster     = -1;
  public volatile int    LiveSpeedMilli = -1;
  public volatile string LiveEffect     = null;
  public volatile int    LiveFlags = -1;
  public volatile int    LiveEnabled = -1;
  public volatile bool   LiveDirty = false;

  // A whole palette handed over in one go.
  //
  // These used to be four separate volatile arrays (LivePalR, LivePalG,
  // LivePalB, LivePalW) assigned one after another by the watcher thread
  // while the render thread read them. Changing a colour without changing
  // how MANY colours there are keeps every length the same, so the
  // length check could not tell a half-applied update from a finished
  // one, and a frame could be drawn with red from the new palette and
  // blue from the old one. One wrong frame is a visible flash - the
  // flicker seen on every change.
  //
  // Bundling them means the hand-off is a single reference assignment,
  // which is atomic: the render thread sees either the entire old palette
  // or the entire new one. Nothing is ever mutated after publishing, so
  // there is nothing to tear.
  public volatile PalSet LivePal = null;

  public void Alloc() {
    Heat = new double[Idx.Length];
  }
}

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

  // Temporal dither trades a 1-level flicker for extra apparent colour
  // depth. That is a good trade on a coarse panel and a bad one here: this
  // keyboard reports a full 255 levels per channel, so there is no extra
  // depth to win, and the error feedback just toggles the bottom bit
  // forever (40,41,40,41...). The four keyboard lamps almost always carry
  // the same colour, so they toggle in lockstep and it reads as a shimmer;
  // the twelve bar lamps sit at different phases and average out, which is
  // why the bar looked smooth while the keyboard did not.
  // -1 = decide from the device scale, 0 = force off, 1 = force on.
  public volatile int DitherMode = -1;
  public bool UseDither {
    get {
      int m = DitherMode;
      if (m == 0) return false;
      if (m == 1) return true;
      // Auto: only worth it when the panel is coarser than our 0..255.
      return MaxR < 255 || MaxG < 255 || MaxB < 255;
    }
  }

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
  public Zone[] Groups = new Zone[0];

  public AudioCap Audio  = null;
  public SysInfo  Sys    = null;
  public ScreenCap Screen = null;
  public volatile int  OverlayMode = 0;    // 0 none, 1 battery, 2 cpu
  // NOTE: C# forbids "volatile" on double (CS0677). This is only ever
  // written by the poll loop and read by the render thread, and a torn
  // read would at worst end an overlay one frame early, so a plain field
  // is correct here.
  public double OverlayUntil = 0.0;
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
    // Same for every group: Heat must be sized or fire/stars index past the
    // end, and the palette must exist before the first RenderGroup call.
    for (int z = 0; z < Groups.Length; z++) {
      Zone gz = Groups[z];
      gz.Alloc();
      PrepPaletteG(gz);
      if (gz.Pos == null || gz.Pos.Length != gz.N) {
        gz.Pos = new double[gz.N];
        for (int i = 0; i < gz.N; i++) gz.Pos[i] = (gz.N > 1) ? (i / (double)(gz.N - 1)) : 0.0;
      }
    }
    if (SlotPos == null || SlotPos.Length != LampCount) {
      SlotPos = new double[LampCount];
      for (int i = 0; i < LampCount; i++)
        SlotPos[i] = (LampCount > 1) ? (i / (double)(LampCount - 1)) : 0.0;
    }
    return true;
  }


  // Battery as a filling bar: green when full, red when nearly empty.
  // While charging a bright head runs along the bar.
  // Battery as a filling bar: green when full, red when nearly empty.
  // While charging a bright head runs along the bar.
  void DrawBattery(Zone gr) {
    int pct = (Sys != null) ? Sys.Battery : -1;
    bool chg = (Sys != null) && Sys.Charging;
    if (pct < 0) pct = 100;
    double f = pct / 100.0;
    double hr, hg, hb;
    Hsv(120.0 * f, 1.0, 1.0, out hr, out hg, out hb);
    double head = chg ? ((Now * 0.5) % 1.0) : -1.0;
    bool low = (!chg && f <= 0.15);
    double blink = low ? (0.35 + 0.65 * (0.5 + 0.5 * Math.Sin(Now * 5.0))) : 1.0;
    for (int i = 0; i < gr.N; i++) {
      double u = PosOf(gr, i);
      double on;
      if (u <= f) on = 1.0;
      else { double d = (u - f) / 0.05; on = (d < 1.0) ? (1.0 - d) : 0.0; }
      double r = hr * on, g = hg * on, b = hb * on;
      if (on < 0.02) { r = 6; g = 6; b = 6; }
      if (chg && head >= 0) {
        double d2 = Math.Abs(u - head * f);
        double w = Math.Exp(-d2 * 20.0);
        r += 255 * w * 0.8; g += 255 * w * 0.8; b += 200 * w * 0.8;
      }
      SetZoneG(gr, i, r * blink, g * blink, b * blink);
    }
  }

  // CPU load meter: green at idle through to red under full load.
  void DrawCpu(Zone gr) {
    double c = (Sys != null) ? Sys.Cpu : 0.0;
    double hr, hg, hb;
    Hsv(120.0 - 120.0 * c, 1.0, 1.0, out hr, out hg, out hb);
    for (int i = 0; i < gr.N; i++) {
      double u = PosOf(gr, i);
      double on;
      if (u <= c) on = 1.0;
      else { double d = (u - c) / 0.05; on = (d < 1.0) ? (1.0 - d) : 0.0; }
      double r = hr * on, g = hg * on, b = hb * on;
      if (on < 0.02) { r = 5; g = 5; b = 5; }
      SetZoneG(gr, i, r, g, b);
    }
  }

  void SetZoneG(Zone gr, int slot, double r, double g, double b) {
    int n = gr.N;
    if (slot < 0 || slot >= n) return;
    // Mirror is handled by folding the sampling POSITION (see PosOf), not
    // by shuffling which lamp gets written. The old code remapped the
    // index here as slot -> (half-1-slot)/(slot-half), which only ever
    // produced 0..half-1: half the lamps were never written and kept
    // whatever they last had, which read as reversed rather than
    // mirrored.
    int i = gr.Idx[slot];
    if (i < 0 || i >= LampCount) return;

    // Dim in LINEAR light, not on the sRGB-encoded value.
    //
    // Multiplying the encoded number is both wrong and lossy. Wrong
    // because sRGB is a curve, so half the encoded value is about a fifth
    // of the actual light - the slider never matched what the eye saw.
    // Lossy because the surviving values bunch together: at 30% a full
    // 0-255 sweep collapsed to roughly 78 distinct steps instead of 150,
    // and bunched steps are exactly what makes a slow gradient sit still
    // and then jump. Converting to linear, scaling there, and converting
    // back keeps the steps evenly spread and makes the slider mean what
    // it says. Both directions are interpolated lookups, so this costs
    // very little per lamp. BuildTables is idempotent and returns
    // immediately once built - called here because SetZoneG has callers
    // (the all-off path, for one) that never touch PrepPaletteG, and a
    // null table would be a crash rather than a wrong colour.
    double br = gr.Brightness * gr.Master;
    if (br < 0.999) {
      BuildTables();
      r = ToSrgb(ToLin(r) * br);
      g = ToSrgb(ToLin(g) * br);
      b = ToSrgb(ToLin(b) * br);
    }
    if (r < 0) r = 0; else if (r > 255) r = 255;
    if (g < 0) g = 0; else if (g > 255) g = 255;
    if (b < 0) b = 0; else if (b > 255) b = 255;
    fr[i] = r; fg[i] = g; fb[i] = b;
  }

  // Rebuild the working palette. When xfade is true, the palette being
  // replaced is kept so GroupPal can ease across to the new one instead of
  // cutting to it. Startup passes false: there is nothing to fade from,
  // and fading up from an unset palette would itself be a visible blink.
  void PrepPaletteG(Zone gr) { PrepPaletteG(gr, false); }
  void PrepPaletteG(Zone gr, bool xfade) {
    BuildTables();

    // Snapshot the outgoing palette BEFORE the new one overwrites it.
    // Only worth doing if there is a complete one to snapshot.
    if (xfade && gr.plR != null && gr.plR.Length > 0 &&
        gr.palGain != null && gr.palGain.Length == gr.plR.Length) {

      if (gr.XfadeLeft > 0.0 && gr.oldCount > 0 && gr.oldR != null) {
        // A changeover is already running, so the palette in gr.plR is one
        // the user has never actually seen in full - the lamps are showing
        // a blend of it and the one before. Starting the next fade from
        // gr.plR would jump straight to that unseen palette first, which
        // is what made clicking quickly through colours look worse than
        // one slow change. Freeze what is genuinely on screen right now
        // and fade from that instead.
        int fc = gr.plR.Length;
        double[] fr2 = new double[fc], fg2 = new double[fc], fb2 = new double[fc];
        double[] fgain = new double[fc];
        double u0 = 1.0 - (gr.XfadeLeft / gr.XfadeTotal);
        if (u0 < 0.0) u0 = 0.0; else if (u0 > 1.0) u0 = 1.0;
        u0 = u0 * u0 * (3.0 - 2.0 * u0);
        for (int i = 0; i < fc; i++) {
          // Sample the two palettes entry-by-entry. Index against the OLD
          // palette's own length: the two need not be the same size.
          int oi = (gr.oldCount > 0) ? (i % gr.oldCount) : 0;
          double og = gr.oldGain[oi], ng = gr.palGain[i];
          double La, Aa, Ba, Lb, Ab, Bb, mr, mg, mb;
          ToOklab(gr.oldR[oi]*og, gr.oldG[oi]*og, gr.oldB[oi]*og,
                  out La, out Aa, out Ba);
          ToOklab(gr.plR[i]*ng, gr.plG[i]*ng, gr.plB[i]*ng,
                  out Lb, out Ab, out Bb);
          MixOklab(La, Aa, Ba, Lb, Ab, Bb, u0, out mr, out mg, out mb);
          fr2[i] = mr; fg2[i] = mg; fb2[i] = mb; fgain[i] = 1.0;
        }
        gr.oldR = fr2; gr.oldG = fg2; gr.oldB = fb2; gr.oldGain = fgain;
        gr.oldW = gr.PalW;
        gr.oldCount = fc;
      } else {
        gr.oldR = gr.plR; gr.oldG = gr.plG; gr.oldB = gr.plB;
        gr.oldGain = gr.palGain;
        gr.oldW = gr.PalW;
        gr.oldCount = gr.plR.Length;
      }
      gr.XfadeTotal = PalXfadeSeconds;
      gr.XfadeLeft  = PalXfadeSeconds;
    } else if (!xfade) {
      gr.XfadeLeft = 0.0;
      gr.oldCount = 0;
    }

    int pc = gr.PalR.Length;
    if (pc == 0) { pc = 1; gr.PalR = new int[]{255}; gr.PalG = new int[]{255}; gr.PalB = new int[]{255}; }
    gr.plR = new double[pc]; gr.plG = new double[pc]; gr.plB = new double[pc];
    gr.palGain = new double[pc];
    for (int i = 0; i < pc; i++) {
      gr.plR[i] = ToLin(gr.PalR[i]);
      gr.plG[i] = ToLin(gr.PalG[i]);
      gr.plB[i] = ToLin(gr.PalB[i]);
      gr.palGain[i] = 1.0;
    }
    if (gr.Equalise) {
      double logSum = 0; int n = 0;
      for (int i = 0; i < pc; i++) {
        double L = Luma(gr.plR[i], gr.plG[i], gr.plB[i]);
        if (L > 0.0005) { logSum += Math.Log(L); n++; }
      }
      if (n > 0) {
        double target = Math.Exp(logSum / n);
        for (int i = 0; i < pc; i++) {
          double L = Luma(gr.plR[i], gr.plG[i], gr.plB[i]);
          if (L <= 0.0005) continue;
          double gain = Math.Pow(target / L, 0.5);
          double peak = Math.Max(gr.plR[i], Math.Max(gr.plG[i], gr.plB[i]));
          if (peak > 0 && gain * peak > 1.0) gain = 1.0 / peak;
          if (gain < 0.25) gain = 0.25;
          if (gain > 4.00) gain = 4.00;
          gr.palGain[i] = gain;
        }
      }
    }

  }

  // OKLab, from LINEAR sRGB. Used only when the palette changes, to measure
  // how far apart two colours LOOK rather than how far apart their numbers
  // are. Plain RGB and HSV both lie about this: equal steps in either can
  // be an obvious jump in one part of the spectrum and invisible in
  // another, which is what made one palette colour hold the strip longer
  // than the next.
  // Inverse of ToOklab: perceptual coordinates back to LINEAR sRGB.
  static void FromOklab(double L, double A, double B2,
                        out double r, out double g, out double b) {
    double l_ = L + 0.3963377774 * A + 0.2158037573 * B2;
    double m_ = L - 0.1055613458 * A - 0.0638541728 * B2;
    double s_ = L - 0.0894841775 * A - 1.2914855480 * B2;
    double l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    r =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    b = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
  }

  // Straight-line blend between two colours in OKLab, pulled back into the
  // displayable range if it strays outside.
  //
  // A mix of two in-gamut colours can land on a colour the LEDs cannot
  // make. Clamping each channel would bend the hue - a red that cannot go
  // bright enough turns pink rather than just dimmer. Instead keep the
  // lightness and the hue direction and ease the saturation back until it
  // fits, which is the smallest change that stays honest to the colour.
  static void MixOklab(double L1, double A1, double B1,
                       double L2, double A2, double B2, double w,
                       out double r, out double g, out double b) {
    double L = L1 + (L2 - L1) * w;
    double A = A1 + (A2 - A1) * w;
    double B = B1 + (B2 - B1) * w;
    FromOklab(L, A, B, out r, out g, out b);
    if (r >= -1e-9 && g >= -1e-9 && b >= -1e-9 &&
        r <= 1.000000001 && g <= 1.000000001 && b <= 1.000000001) return;
    double lo = 0.0, hi = 1.0;
    for (int it = 0; it < 18; it++) {
      double mid = (lo + hi) * 0.5;
      FromOklab(L, A * mid, B * mid, out r, out g, out b);
      if (r >= -1e-9 && g >= -1e-9 && b >= -1e-9 &&
          r <= 1.000000001 && g <= 1.000000001 && b <= 1.000000001) lo = mid;
      else hi = mid;
    }
    FromOklab(L, A * lo, B * lo, out r, out g, out b);
    if (r < 0) r = 0; else if (r > 1) r = 1;
    if (g < 0) g = 0; else if (g > 1) g = 1;
    if (b < 0) b = 0; else if (b > 1) b = 1;
  }

  static void ToOklab(double r, double g, double b,
                      out double L, out double A, out double B2) {
    double l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    double m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    double s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
    l = Math.Pow(l < 0 ? 0 : l, 1.0 / 3.0);
    m = Math.Pow(m < 0 ? 0 : m, 1.0 / 3.0);
    s = Math.Pow(s < 0 ? 0 : s, 1.0 / 3.0);
    L  = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
    A  = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
    B2 = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  }

  // How long a palette change takes to ease in.
  //
  // The eased curve peaks at 1.5x the average rate, so the worst per-frame
  // step for a full-range edit (a colour taken to black, say) is about
  // 1.5 * 255 / (seconds * fps). At 60fps: 0.15s leaves a 42/255 step,
  // 0.22s leaves 29, 0.30s leaves 21. Below roughly 20 it stops reading as
  // a step at all. Going longer keeps helping in theory, but the panel
  // starts to feel like it is lagging behind the click, and dragging a
  // width bar would stack fades on top of each other.
  public const double PalXfadeSeconds = 0.30;

  void GroupPal(Zone gr, double f, out double r, out double g, out double b) {
    if (gr.plR == null || gr.plR.Length == 0) PrepPaletteG(gr);

    // Normal case: one palette, sample it and done.
    if (gr.XfadeLeft <= 0.0 || gr.oldCount <= 0 || gr.oldR == null) {
      SamplePal(gr, gr.plR, gr.plG, gr.plB, gr.palGain, gr.PalW, f,
                out r, out g, out b);
      return;
    }

    // Mid-changeover: sample BOTH palettes at this point in the cycle and
    // ease from the old one to the new one. Both are sampled at the same
    // phase, so the animation carries on travelling at the same speed
    // throughout - only the colours move, which is exactly what a colour
    // change should look like.
    double o_r, o_g, o_b, n_r, n_g, n_b;
    SamplePal(gr, gr.oldR, gr.oldG, gr.oldB, gr.oldGain, gr.oldW, f,
              out o_r, out o_g, out o_b);
    SamplePal(gr, gr.plR, gr.plG, gr.plB, gr.palGain, gr.PalW, f,
              out n_r, out n_g, out n_b);

    double u = 1.0 - (gr.XfadeLeft / gr.XfadeTotal);
    if (u < 0.0) u = 0.0; else if (u > 1.0) u = 1.0;
    u = u * u * (3.0 - 2.0 * u);     // ease in and out, no hard start/stop

    // Cross in OKLab for the same reason the palette itself blends there:
    // a straight line in sRGB dips in brightness through the middle, which
    // would read as a dim pulse - precisely the artefact being removed.
    double La, Aa, Ba, Lb, Ab, Bb, mr, mg, mb;
    ToOklab(o_r, o_g, o_b, out La, out Aa, out Ba);
    ToOklab(n_r, n_g, n_b, out Lb, out Ab, out Bb);
    MixOklab(La, Aa, Ba, Lb, Ab, Bb, u, out mr, out mg, out mb);
    r = ToSrgb(mr); g = ToSrgb(mg); b = ToSrgb(mb);
  }

  // Sample one palette at position f. Split out of GroupPal so the same
  // layout maths serves both the live palette and the one being faded out.
  void SamplePal(Zone gr, double[] plR, double[] plG, double[] plB,
                 double[] palGain, double[] PalW, double f,
                 out double r, out double g, out double b) {
    int pc = plR.Length;
    f = f % 1.0; if (f < 0) f += 1.0;
    // Hold each palette colour, then cross in a short window.
    //
    // The ask is for the palette colours themselves to dominate and the
    // blend between them to be a small part of the cycle, rather than an
    // even sweep where every in-between shade gets equal time. So the
    // first and last 30% of each step are flat - exactly the palette
    // colour - and the middle 40% does the whole transition, eased at both
    // ends so it does not start or stop abruptly.
    //
    // How wide that middle window is depends on how many lamps the zone
    // has, and it has to.
    //
    // On the twelve light-bar lamps a narrow window is exactly right: at
    // any moment different lamps sit at different points, so the strip
    // shows solid blocks of colour with a short blend between them, which
    // is the look that was asked for.
    //
    // The keyboard has four lamps. With a narrow window all four sit
    // inside the flat holds nearly all the time, so instead of a gradient
    // travelling across the keys they sit on one colour, all flip
    // together, and sit on the next - blocks snapping rather than motion.
    // Widening the span does not help; it just lands more lamps in the
    // holds. The only fix is to give a sparse zone more of its cycle to
    // move in.
    //
    // So: twelve or more lamps keep a 35% window, four or fewer get 50%,
    // and anything between is interpolated. Both zones keep the same
    // palette and the same blend, so the colours are unchanged.
    //
    // The sparse zone used to get 75%. That was set when the blend still
    // went round the HSV hue circle and spent most of its length in a
    // washed-out smear, so a wide window was needed to keep the four
    // keyboard lamps from all sitting on an endpoint and flipping in
    // unison. Blending in OKLab removed the smear, which means the window
    // can come back in and give the palette colours themselves more of the
    // strip - measured on purple/orange, the second colour goes from 27.9%
    // of the cycle to 35.3% and the muddy middle drops from 31.8% to 21.2%.
    //
    // 0.50 is the floor, not a preference. At 0.40 the four keyboard lamps
    // are pinned on an endpoint 60% of the time and start snapping between
    // colours together, which was rejected before; 0.50 holds that at 50.8%
    // with a worst per-frame step of 7.7/255, still smooth.
    double nlamp = (double)gr.N;
    double trans;
    if (nlamp >= 12.0) trans = 0.35;
    else if (nlamp <= 4.0) trans = 0.50;
    else trans = 0.50 + (0.35 - 0.50) * ((nlamp - 4.0) / 8.0);

    // Lay the cycle out as: hold colour 0, fade, hold colour 1, fade, ...
    // Every fade is the same length; the holds are what the width sliders
    // change. Widths are relative, so 2 and 1 means the first colour gets
    // twice the strip of the second whatever the numbers actually are.
    //
    // With every width equal this is arithmetically identical to the fixed
    // 1/pc slots it replaces - verified to 1e-15 - so a palette nobody has
    // touched looks exactly as it did.
    double fade = trans / pc;             // one fade, in cycle units
    double holdTot = 1.0 - fade * pc;     // what is left for the flat holds
    if (holdTot < 0.0) holdTot = 0.0;

    double wsum = 0.0;
    bool haveW = (PalW != null && PalW.Length == pc);
    if (haveW) {
      for (int i = 0; i < pc; i++) {
        double v = PalW[i];
        if (v < 0.0) v = 0.0;
        wsum += v;
      }
      if (wsum <= 1e-9) haveW = false;    // all zero: fall back to even
    }

    // Start half a hold early so colour 0 sits centred on f=0, which is
    // where the old layout put it.
    double firstHold = holdTot * (haveW ? (Math.Max(0.0, PalW[0]) / wsum) : (1.0 / pc));
    double xx = f + firstHold * 0.5;
    xx = xx % 1.0; if (xx < 0) xx += 1.0;

    int a = pc - 1, n2 = 0;
    double w = 1.0;
    double pos = 0.0;
    for (int i = 0; i < pc; i++) {
      double hi = holdTot * (haveW ? (Math.Max(0.0, PalW[i]) / wsum) : (1.0 / pc));
      if (xx < pos + hi) { a = i; n2 = (i + 1) % pc; w = 0.0; break; }
      pos += hi;
      if (xx < pos + fade) {
        a = i; n2 = (i + 1) % pc;
        double tt = (fade > 1e-12) ? (xx - pos) / fade : 1.0;
        if (tt < 0.0) tt = 0.0; else if (tt > 1.0) tt = 1.0;
        w = tt * tt * (3.0 - 2.0 * tt);
        break;
      }
      pos += fade;
    }

    double ga = palGain[a], gb = palGain[n2];
    double ar = plR[a] * ga, ag2 = plG[a] * ga, ab = plB[a] * ga;
    double br = plR[n2] * gb, bg = plG[n2] * gb, bb = plB[n2] * gb;

    // Blend in OKLab - a straight line between the two colours in a space
    // built so that equal steps look equal.
    //
    // This used to rotate around the HSV hue circle, which is what made
    // one band look thinner than its neighbour. Every HSV hue from violet
    // round to red holds green at zero, so purple to orange kept green at
    // zero for 90% of the sweep and only found orange's green=120 right at
    // the end: the strip showed purple, then a long magenta-pink smear,
    // then a moment of orange. Measured over the whole blend that is 70%
    // pink and 7% orange, and the halfway point - where the colour stops
    // being nearer purple and starts being nearer orange - sat at 0.69
    // instead of 0.50.
    //
    // OKLab puts that halfway point at 0.500 for this palette and within
    // 0.01 of it for every pair tested, and cuts the pink from 70% to 35%.
    double lr, lg, lb;
    double La, Aa, Ba, Lb, Ab, Bb;
    ToOklab(ar, ag2, ab, out La, out Aa, out Ba);
    ToOklab(br, bg, bb, out Lb, out Ab, out Bb);
    MixOklab(La, Aa, Ba, Lb, Ab, Bb, w, out lr, out lg, out lb);
    r = ToSrgb(lr); g = ToSrgb(lg); b = ToSrgb(lb);
  }

  // Pull every group's live inbox into its active settings.
  void ApplyLive() {
    for (int z = 0; z < Groups.Length; z++) {
      Zone gr = Groups[z];
      if (!gr.LiveDirty) continue;
      gr.LiveDirty = false;          // clear first so a concurrent write is kept
      bool repal = false;

      int lb = gr.LiveBrightness;
      if (lb >= 0) gr.Brightness = lb / 1000.0;
      int lm = gr.LiveMaster;
      if (lm >= 0) gr.Master = lm / 1000.0;
      int ls = gr.LiveSpeedMilli;
      if (ls >= 0) gr.Speed = ls / 1000.0;
      string le = gr.LiveEffect;
      if (le != null && le.Length > 0) gr.Effect = le;
      int en = gr.LiveEnabled;
      if (en >= 0) gr.Enabled = (en != 0);

      // One read of one reference: whatever we get here is a complete,
      // self-consistent palette. It cannot be a mix of the old and new
      // ones, which is what used to put a wrong-coloured frame on the
      // keyboard every time a colour was changed.
      PalSet ps = gr.LivePal;
      if (ps != null && ps.Count > 0 &&
          ps.G.Length == ps.Count && ps.B.Length == ps.Count) {
        gr.PalR = ps.R; gr.PalG = ps.G; gr.PalB = ps.B;
        // Widths travel with the colours, so they can never be applied
        // against a palette of a different size.
        gr.PalW = (ps.W != null && ps.W.Length == ps.Count) ? ps.W : null;
        repal = true;
      }

      int lf = gr.LiveFlags;
      if (lf >= 0) {
        gr.Mirror  = (lf & 1) != 0;
        gr.Reverse = (lf & 2) != 0;
        bool eq = (lf & 4) != 0;
        if (eq != gr.Equalise) { gr.Equalise = eq; repal = true; }
        bool lp = (lf & 8) != 0;
        if (lp != gr.Loop) {
          gr.Loop = lp;
          double[] want = lp ? gr.PosLoop : gr.PosAcross;
          if (want != null && want.Length == gr.N) gr.Pos = want;
        }
      }
      // true = ease across from the palette being replaced rather than
      // cutting straight to the new one.
      if (repal) PrepPaletteG(gr, true);
    }
  }


  int[] pr, pg, pb;
  int[] nr, ng, nb2;       // this frame's bytes, promoted only once sent

  // Measured cost of talking to the device. Every frame on an animating
  // effect issues two synchronous feature reports, and on an EC-backed
  // keyboard each can take milliseconds. If the pair costs more than the
  // frame budget the render loop cannot hold its cadence and the lighting
  // lands unevenly - which looks like flicker. These are read by the
  // status line so it can be measured rather than guessed at.
  public volatile int  WriteUs   = 0;   // last frame's two writes, microsec
  public volatile int  WriteUsMax = 0;  // worst seen
  public volatile int  LateFrames = 0;  // frames that missed their deadline
  int overrun = 0;                      // consecutive frames whose writes overflowed
  double[] er, eg, eb;     // carried quantisation error, for temporal dither

  // ---- live frame publishing -------------------------------------
  // The control panel used to redraw the preview by re-implementing the
  // effects in PowerShell, which only ever matched for the simplest ones.
  // Instead we publish the real post-dither bytes - exactly what went out
  // over USB - and let the panel just display them.
  public string FramePath = null;      // null = don't publish
  public int    FrameHz    = 20;       // cap: the panel cannot use more
  double nextFrameAt = -1.0;
  byte[] frameBuf = null;
  char[] hexPairs = "0123456789abcdef".ToCharArray();

  // Physical layout, written whenever it changes. gr.Pos switches between
  // the across and loop maps when the user toggles Loop, so this cannot be
  // written once at startup - it has to follow the live zone state.
  public string LayoutPath = null;
  string lastLayout = null;

  void PublishLayout() {
    if (LayoutPath == null || Groups == null || Groups.Length == 0) return;
    System.Text.StringBuilder sb = new System.Text.StringBuilder();
    string[] names = new string[] { "kbd", "bar" };
    for (int gi = 0; gi < Groups.Length && gi < 2; gi++) {
      Zone gr = Groups[gi];
      if (gr == null || gr.N == 0) continue;
      // Order this group's lamps by where they physically are.
      int[] ord = new int[gr.N];
      for (int i = 0; i < gr.N; i++) ord[i] = i;
      for (int a2 = 1; a2 < gr.N; a2++) {
        int key = ord[a2]; int b2 = a2 - 1;
        while (b2 >= 0 && gr.Pos[ord[b2]] > gr.Pos[key]) { ord[b2 + 1] = ord[b2]; b2--; }
        ord[b2 + 1] = key;
      }
      sb.Append(names[gi]).Append('=');
      for (int i = 0; i < gr.N; i++) {
        if (i > 0) sb.Append(',');
        sb.Append(gr.Idx[ord[i]].ToString());
      }
      // Tell the panel whether this group is a closed ring, so it can
      // blend across the seam instead of stopping at the last lamp.
      sb.Append('\n').Append(names[gi]).Append("ring=")
        .Append(gr.Loop ? "1" : "0");
      sb.Append('\n').Append(names[gi]).Append("pos=");
      double lo = gr.Pos[ord[0]], hi = gr.Pos[ord[gr.N - 1]], sp = hi - lo;
      for (int i = 0; i < gr.N; i++) {
        if (i > 0) sb.Append(',');
        double v = (sp > 0) ? (gr.Pos[ord[i]] - lo) / sp
                            : (gr.N > 1 ? i / (double)(gr.N - 1) : 0.0);
        sb.Append(v.ToString("0.####", System.Globalization.CultureInfo.InvariantCulture));
      }
      sb.Append('\n');
    }
    string txt = sb.ToString();
    if (txt == lastLayout) return;      // only write on a real change
    lastLayout = txt;
    try { File.WriteAllText(LayoutPath, txt); } catch { }
  }

  void PublishFrame() {
    if (FramePath == null) return;
    if (Now < nextFrameAt) return;
    nextFrameAt = Now + (1.0 / (double)(FrameHz > 0 ? FrameHz : 20));
    PublishLayout();

    int n = LampCount;
    // "<count>;" then 6 hex chars per lamp, in device lamp order.
    int need = 12 + n * 6;
    if (frameBuf == null || frameBuf.Length < need) frameBuf = new byte[need];
    int w = 0;
    string head = n.ToString() + ";";
    for (int i = 0; i < head.Length; i++) frameBuf[w++] = (byte)head[i];
    for (int i = 0; i < n; i++) {
      int r = pr[i], g = pg[i], b2 = pb[i];
      if (r < 0) r = 0; if (g < 0) g = 0; if (b2 < 0) b2 = 0;
      // pr/pg/pb are device levels (0..MaxR); scale back to 0..255 so the
      // panel does not need to know the device's logical maximum.
      if (MaxR > 0 && MaxR != 255) r = (r * 255) / MaxR;
      if (MaxG > 0 && MaxG != 255) g = (g * 255) / MaxG;
      if (MaxB > 0 && MaxB != 255) b2 = (b2 * 255) / MaxB;
      if (r > 255) r = 255; if (g > 255) g = 255; if (b2 > 255) b2 = 255;
      frameBuf[w++] = (byte)hexPairs[(r >> 4) & 15]; frameBuf[w++] = (byte)hexPairs[r & 15];
      frameBuf[w++] = (byte)hexPairs[(g >> 4) & 15]; frameBuf[w++] = (byte)hexPairs[g & 15];
      frameBuf[w++] = (byte)hexPairs[(b2 >> 4) & 15]; frameBuf[w++] = (byte)hexPairs[b2 & 15];
    }
    try {
      // Write the whole thing in one call and keep the handle for the
      // shortest possible time; the reader tolerates a torn read anyway.
      using (FileStream fs = new FileStream(FramePath, FileMode.Create,
                                            FileAccess.Write, FileShare.ReadWrite)) {
        fs.Write(frameBuf, 0, w);
      }
    } catch { }
  }

  void Push() { Push(false); }

  // Quantise with error feedback: the fraction we throw away this frame is
  // added to the next one. At 60fps the eye integrates the result, so a
  // value creeping at 0.4 LSB/frame fades smoothly instead of holding for
  // two frames and then stepping - which is the flicker seen at low speeds.
  static int Dither(double v, double scale, ref double err, bool on) {
    double x = v * scale / 255.0;
    if (!on) {
      // Straight rounding. Clearing the carry matters: a stale error would
      // bias the very next frame after dither is switched back off.
      err = 0.0;
      int p = (int)(x + 0.5);
      return p < 0 ? 0 : (p > 255 ? 255 : p);
    }
    x += err;
    int q = (int)(x + 0.5);
    if (q < 0) q = 0; else if (q > 255) q = 255;
    err = x - q;
    if (err > 1.0) err = 1.0; else if (err < -1.0) err = -1.0;
    return q;
  }

  void Push(bool force) {
    int last = nbatch - 1;
    bool changed = force;
    bool dith = UseDither;

    // Staging buffers for what this frame WANTS to send. pr/pg/pb must keep
    // describing what the device actually has until the writes come back
    // clean - see the promotion step at the bottom.
    if (nr == null) { nr = new int[LampCount]; ng = new int[LampCount]; nb2 = new int[LampCount]; }

    for (int bi = 0; bi < nbatch; bi++) {
      byte[] b = bufs[bi];
      int first = bi * Slots;
      int n = Math.Min(Slots, LampCount - first);
      for (int s = 0; s < n; s++) {
        int i = first + s;
        int st = Interleaved ? s*4 : s;
        int qr = Dither(fr[i], MaxR, ref er[i], dith);
        int qg = Dither(fg[i], MaxG, ref eg[i], dith);
        int qb = Dither(fb[i], MaxB, ref eb[i], dith);
        if (qr != pr[i] || qg != pg[i] || qb != pb[i]) changed = true;
        nr[i] = qr; ng[i] = qg; nb2[i] = qb;
        b[OffR + st] = (byte)qr;
        b[OffG + st] = (byte)qg;
        b[OffB + st] = (byte)qb;
      }
      b[OffFlags] = (bi == last) ? (byte)1 : (byte)0;
    }

    // Nothing moved, not even by one dithered step: skip the transfer.
    if (!changed) return;

    long t0 = Stopwatch.GetTimestamp();
    bool allOk = true;
    for (int bi = 0; bi < nbatch; bi++) {
      byte[] b = bufs[bi];
      if (!HidD_SetFeature(h, b, b.Length)) allOk = false;
    }
    int us = (int)((Stopwatch.GetTimestamp() - t0) * 1000000L / Stopwatch.Frequency);
    WriteUs = us;
    if (us > WriteUsMax) WriteUsMax = us;

    // Only now is it true that the device holds these colours. Recording
    // them earlier was the flicker: a failed write left the keyboard on a
    // stale frame while pr/pg/pb claimed otherwise, so the next frame sent
    // only the small delta from a frame that never landed and the lamps
    // sat frozen until a later write happened to catch up. It bites the
    // keyboard hardest because lamps 0-3 are the buffered batch - the
    // device withholds them until the batch carrying the apply flag
    // arrives, so losing that second write strands exactly those lamps.
    if (allOk) {
      for (int i = 0; i < LampCount; i++) { pr[i] = nr[i]; pg[i] = ng[i]; pb[i] = nb2[i]; }
    }

    // One failed write is noise (a busy endpoint). A run of them means the
    // handle is dead - almost always a resume from sleep.
    if (allOk) { failRun = 0; }
    else {
      failRun++;
      if (failRun >= 8) { DeviceLost = true; failRun = 0; }
    }
  }

  // Re-send the "host is in charge" control report. This is the only thing
  // that recovers the lighting after the EC quietly takes the keyboard back
  // - lid close, Modern Standby, display off - WITHOUT the USB device ever
  // disappearing. No write fails in that case, so nothing else notices.
  //
  // History worth keeping, because I got this wrong: this ran every 3
  // seconds, I removed it while chasing a flicker, the flicker turned out
  // to be brightness quantisation, and the lighting then stopped coming
  // back after the lid was opened. The cost argument was wrong too - the
  // measurements put one extra control transfer at well under a millisecond
  // on a 16.7ms budget, once every 180 frames.
  //
  // So the heartbeat is back, with the part that actually could be seen
  // removed: it no longer invalidates the colour cache. Re-asserting
  // ownership does not change what the lamps are showing, so forcing a
  // full 16-lamp repaint every 3 seconds was pure cost. A real wake still
  // passes force=true and does invalidate, because there the cache genuinely
  // is stale.
  public void ReAssert() { ReAssert(true); }
  public void ReAssert(bool force) {
    if (h == IntPtr.Zero || h == (IntPtr)(-1)) return;
    if (CtrlOff != null) HidD_SetFeature(h, CtrlOff, CtrlOff.Length);
    if (!force) return;
    // Only after a real wake: whatever the device was showing is gone, so
    // the next Push has to resend every zone even if the computed colours
    // are identical.
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
    ApplyLive();
    Now = t;

    // An overlay temporarily takes over every group, then hands control
    // straight back to whatever each group was doing.
    int ov = OverlayMode;
    if (ov != 0) {
      if (t < OverlayUntil) {
        for (int z = 0; z < Groups.Length; z++) {
          if (ov == 1) DrawBattery(Groups[z]);
          else         DrawCpu(Groups[z]);
        }
        return;
      }
      OverlayMode = 0;
    }

    for (int z = 0; z < Groups.Length; z++) {
      Zone gr = Groups[z];
      if (!gr.Enabled) { BlankGroup(gr); continue; }

      // Run down a palette changeover in real time, so it takes the same
      // length whatever the frame rate. Released once finished: the old
      // palette is only needed while it is still visible.
      if (gr.XfadeLeft > 0.0) {
        gr.XfadeLeft -= dt;
        if (gr.XfadeLeft <= 0.0) {
          gr.XfadeLeft = 0.0;
          gr.oldR = null; gr.oldG = null; gr.oldB = null;
          gr.oldGain = null; gr.oldW = null; gr.oldCount = 0;
        }
      }

      // Each group keeps its own phase so changing one group's speed can
      // never jump the other one.
      gr.Phase += dt * gr.Speed;
      RenderGroup(gr, gr.Phase, dt);
    }
  }

  void BlankGroup(Zone gr) {
    for (int i = 0; i < gr.N; i++) SetZoneG(gr, i, 0, 0, 0);
  }

  // Distance from a to b along the group. On a ring the short way round
  // may cross the seam, so 0.95 and 0.02 are 0.07 apart, not 0.93. Without
  // this a travelling head disappears at the seam instead of carrying on.
  static double Gap(Zone gr, double a, double b) {
    double d = a - b;
    if (!gr.Loop) return d;
    while (d > 0.5) d -= 1.0;
    while (d < -0.5) d += 1.0;
    return d;
  }

  // Where slot i samples the effect from, 0..1 within the group.
  // Mirror folds this into a triangle so the pattern runs out from the
  // centre to both ends and is symmetric; without it this is just the
  // lamp's real physical position.
  static double PosOf(Zone gr, int i) {
    double u = gr.Pos[i];
    if (!gr.Mirror) return u;
    double f = 1.0 - Math.Abs(2.0 * u - 1.0);
    if (f < 0) f = 0; else if (f > 1) f = 1;
    return f;
  }

  void RenderGroup(Zone gr, double t, double dt) {
    switch (gr.Effect) {
          case "gradient": {
            // A band of colour that rolls through and wraps around, like
            // looking at one face of a rotating roll of tape: each colour
            // holds as a solid block, slides off one end and comes back on
            // the other.
            //
            // The strip used to show exactly one full palette loop, which
            // pinned the two ends to the same colour - nothing could move
            // past the edge, so it cycled in place and looked like a pulse.
            // Showing only PART of the loop at a time is what makes the
            // colours hold and travel.
            //
            // Span shrinks as colours are added so each one keeps a
            // readable block: 2 colours -> 0.5 of the loop on screen,
            // 3 -> 0.42, 4 -> 0.38.
            int pcg = gr.PalR.Length; if (pcg < 1) pcg = 1;
            double span = (pcg <= 1) ? 1.0 : 1.0 / (1.0 + 0.5 * (double)pcg);
            // A ring has no ends: the last lamp sits right next to the
            // first, so the pattern has to close on itself. That only
            // happens if a whole number of palette loops fits around it -
            // any fraction leaves a visible break at the seam and the
            // colours never appear to travel round. Use exactly one loop.
            if (gr.Loop) span = 1.0;
            double phase = t * 0.25 * gr.Dir;
            for (int i = 0; i < gr.N; i++) {
              double r, g, b;
              // Real physical position, so the band travels at an even
              // speed across unevenly-spaced lamps.
              GroupPal(gr, PosOf(gr, i) * span + phase, out r, out g, out b);
              SetZoneG(gr, i, r, g, b);
            }
            break;
          }
          case "rainbow": {
            for (int i = 0; i < gr.N; i++) {
              double r, g, b;
              Hsv(PosOf(gr, i) * 360.0 + t * 90.0 * gr.Dir, 1.0, 1.0, out r, out g, out b);
              SetZoneG(gr, i, r, g, b);
            }
            break;
          }
          case "wave": {
            // Deliberately NOT a second scrolling gradient. Gradient moves
            // colour; wave holds the colour still and moves BRIGHTNESS - a
            // crest of light travelling along a steady colour bed, like
            // wind over a field.
            //
            // The colour changes slowly over time rather than with
            // position, so at any instant the strip is essentially one
            // colour with a bright crest running through it. That is what
            // makes it read differently from gradient.
            double baseF = t * 0.07 * gr.Dir;
            for (int i = 0; i < gr.N; i++) {
              double r, g, b;
              GroupPal(gr, baseF, out r, out g, out b);
              // Two crests along the strip, travelling.
              double ph = (t * 0.7 * gr.Dir) - PosOf(gr, i) * 2.0;
              double w = (1.0 + Math.Sin(ph * Math.PI)) / 2.0;
              double lvl = 0.30 + 0.70 * (w * w);
              SetZoneG(gr, i, r * lvl, g * lvl, b * lvl);
            }
            break;
          }
          case "comet": {
            // Head travels 0..1 across the real width, wrapping.
            double head = (t * 0.45 * gr.Dir) % 1.0; if (head < 0) head += 1.0;
            // The head used to be locked to colour 1 and every other colour
            // was ignored. Walk the palette as the comet travels, so a
            // two-colour comet visibly changes colour lap to lap and the
            // trail shades through the palette behind the head.
            for (int i = 0; i < gr.N; i++) {
              // Distance behind the head, wrapping round the seam on a ring
              // so the tail follows the comet all the way round.
              double d = head - PosOf(gr, i);
              if (gr.Loop) { while (d < 0) d += 1.0; while (d >= 1.0) d -= 1.0; }
              else if (d < 0) d += 1.0;
              double w = Math.Exp(-d * 9.0);
              double pr2, pg2, pb2;
              GroupPal(gr, (t * 0.45 * gr.Dir) - d, out pr2, out pg2, out pb2);
              double cr, cg, cb;
              Fade(pr2, pg2, pb2, w, out cr, out cg, out cb);
              SetZoneG(gr, i, cr, cg, cb);
            }
            break;
          }
          case "scanner": {
            // A ring has no ends to bounce off, so sweep continuously
            // round it. Bouncing only makes sense on a straight run.
            double p;
            if (gr.Loop) {
              p = (t * 0.55 * gr.Dir) % 1.0; if (p < 0) p += 1.0;
            } else {
              p = (t * 0.55) % 2.0; if (p < 0) p += 2.0;
              if (p > 1.0) p = 2.0 - p;         // bounce 0..1..0
            }
            // Take the colour from the palette at the sweep's position, so
            // a multi-colour scanner changes colour as it crosses instead
            // of always being colour 1.
            double sr, sg, sb;
            GroupPal(gr, t * 0.275 * gr.Dir, out sr, out sg, out sb);
            for (int i = 0; i < gr.N; i++) {
              double w = 1.0 - (Math.Abs(Gap(gr, PosOf(gr, i), p)) / 0.18);
              if (w < 0) w = 0; w = w * w;
              double cr, cg, cb;
              Fade(sr, sg, sb, w, out cr, out cg, out cb);
              SetZoneG(gr, i, cr, cg, cb);
            }
            break;
          }
          case "breathe": {
            double w = (1.0 + Math.Sin(t * 1.6 * Math.PI)) / 2.0;
            w = 0.02 + 0.98 * w * w;
            // Advance through the palette as it breathes, so every colour
            // you picked gets its turn rather than only the first.
            double br2, bg2, bb2;
            GroupPal(gr, t * 0.8 * gr.Dir / (double)Math.Max(1, gr.PalR.Length),
                     out br2, out bg2, out bb2);
            double cr, cg, cb;
            Fade(br2, bg2, bb2, w, out cr, out cg, out cb);
            for (int i = 0; i < gr.N; i++) SetZoneG(gr, i, cr, cg, cb);
            break;
          }
          case "pulse": {
            double w = Math.Exp(-(t % 1.0) * 4.5);
            double r, g, b;
            Hsv(Math.Floor(t) * 47.0, 1.0, 1.0, out r, out g, out b);
            double pr2, pg2, pb2;
            Fade(r, g, b, w, out pr2, out pg2, out pb2);
            for (int i = 0; i < gr.N; i++) SetZoneG(gr, i, pr2, pg2, pb2);
            break;
          }
          // ---------------- audio reactive ----------------
          case "spectrum": {
            // Each zone is one frequency band, low on the left.
            float[] bd = (Audio != null && Audio.Ok) ? Audio.Bands : null;
            for (int i = 0; i < gr.N; i++) {
              double u = PosOf(gr, i);
              double v = 0.0;
              if (bd != null) {
                int b = (int)(u * (AudioCap.BANDS - 1) + 0.5);
                if (b < 0) b = 0; if (b >= AudioCap.BANDS) b = AudioCap.BANDS - 1;
                v = bd[b];
              }
              double r, g, b2;
              GroupPal(gr, u, out r, out g, out b2);
              SetZoneG(gr, i, r * v, g * v, b2 * v);
            }
            break;
          }
          case "vumeter": {
            // Palette bar that fills from the left with overall loudness.
            double lv = (Audio != null && Audio.Ok) ? Audio.Level : 0.0;
            for (int i = 0; i < gr.N; i++) {
              double u = PosOf(gr, i);
              double on = (u <= lv) ? 1.0 : 0.0;
              if (on < 1.0) {
                double d = (u - lv) / 0.08;        // soft edge
                on = (d < 1.0) ? (1.0 - d) : 0.0;
                if (on < 0) on = 0;
              }
              double r, g, b;
              GroupPal(gr, u, out r, out g, out b);
              SetZoneG(gr, i, r * on, g * on, b * on);
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
            GroupPal(gr, t * 0.08, out r0, out g0, out b0);
            for (int i = 0; i < gr.N; i++) SetZoneG(gr, i, r0 * w, g0 * w, b0 * w);
            break;
          }
          case "pulsebass": {
            // Bass drives a wave outward from the centre.
            double bass = (Audio != null && Audio.Ok) ? Audio.Bass : 0.0;
            for (int i = 0; i < gr.N; i++) {
              double d = Math.Abs(PosOf(gr, i) - 0.5) * 2.0;
              double v = bass - d * 0.55;
              if (v < 0) v = 0; if (v > 1) v = 1;
              v = v * v;
              double r, g, b;
              GroupPal(gr, PosOf(gr, i) + t * 0.05, out r, out g, out b);
              SetZoneG(gr, i, r * v, g * v, b * v);
            }
            break;
          }

          // ---------------- ambient (screen mirror) ----------------
          case "ambient": {
            int[] cols = (Screen != null && Screen.Ok) ? Screen.Cols : null;
            for (int i = 0; i < gr.N; i++) {
              double u = PosOf(gr, i);
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
              SetZoneG(gr, i, r, g, b);
            }
            break;
          }

          // ---------------- classic presets ----------------
          case "cycle": {
            // Whole keyboard one colour, slowly walking the hue wheel.
            double r, g, b;
            Hsv((t * 18.0 * gr.Dir) % 360.0, 1.0, 1.0, out r, out g, out b);
            for (int i = 0; i < gr.N; i++) SetZoneG(gr, i, r, g, b);
            break;
          }
          case "strobe": {
            double ph = t * 6.0;
            double w = (ph - Math.Floor(ph)) < 0.5 ? 1.0 : 0.0;
            double r, g, b;
            GroupPal(gr, Math.Floor(ph) * 0.13, out r, out g, out b);
            for (int i = 0; i < gr.N; i++) SetZoneG(gr, i, r * w, g * w, b * w);
            break;
          }
          case "stars": {
            // Twinkling points of light on a dark keyboard.
            double fade = Math.Pow(0.28, dt);
            double born = 1.0 - Math.Pow(1.0 - 0.055, dt * 60.0);
            for (int i = 0; i < gr.N; i++) {
              gr.Heat[i] *= fade;
              if (rnd.NextDouble() < born) gr.Heat[i] = 0.75 + rnd.NextDouble() * 0.25;
              double v = gr.Heat[i];
              double r, g, b;
              GroupPal(gr, (i * 0.137) % 1.0, out r, out g, out b);
              SetZoneG(gr, i, r * v, g * v, b * v);
            }
            break;
          }
          case "ripple": {
            // Expanding rings from the centre.
            double sp = 0.55 * gr.Dir;
            double v0 = (t * sp) % 1.0;
            for (int i = 0; i < gr.N; i++) {
              double d = Math.Abs(PosOf(gr, i) - 0.5) * 2.0;
              double ph = d - v0;
              ph = ph - Math.Floor(ph);
              double w = Math.Exp(-ph * 5.0);
              double r, g, b;
              GroupPal(gr, PosOf(gr, i) + t * 0.1, out r, out g, out b);
              SetZoneG(gr, i, r * w, g * w, b * w);
            }
            break;
          }
          case "aurora": {
            // Three slow sine layers - the soft drifting look.
            for (int i = 0; i < gr.N; i++) {
              double u = PosOf(gr, i);
              double a = 0.5 + 0.5 * Math.Sin((u * 2.1 + t * 0.21 * gr.Dir) * Math.PI * 2.0);
              double b2 = 0.5 + 0.5 * Math.Sin((u * 1.3 - t * 0.14 * gr.Dir + 0.33) * Math.PI * 2.0);
              double c = 0.5 + 0.5 * Math.Sin((u * 3.7 + t * 0.09 * gr.Dir + 0.66) * Math.PI * 2.0);
              double f = (a * 0.5 + b2 * 0.35 + c * 0.15);
              double r, g, bb;
              GroupPal(gr, f, out r, out g, out bb);
              double v = 0.35 + 0.65 * f;
              SetZoneG(gr, i, r * v, g * v, bb * v);
            }
            break;
          }

          // ---------------- information ----------------
          case "battery": {
            DrawBattery(gr);
            break;
          }
          case "cpu": {
            DrawCpu(gr);
            break;
          }
          case "clock": {
            // Hue follows time of day; a bright marker walks with the minutes.
            DateTime nowT = DateTime.Now;
            double dayF = (nowT.Hour * 3600.0 + nowT.Minute * 60.0 + nowT.Second) / 86400.0;
            double mF   = (nowT.Minute * 60.0 + nowT.Second) / 3600.0;
            for (int i = 0; i < gr.N; i++) {
              double r, g, b;
              Hsv(210.0 + 150.0 * Math.Sin(dayF * Math.PI * 2.0 - Math.PI / 2.0), 0.85, 1.0, out r, out g, out b);
              double d = Math.Abs(PosOf(gr, i) - mF);
              if (d > 0.5) d = 1.0 - d;
              double mark = Math.Exp(-d * 26.0);
              double v = 0.16 + 0.84 * mark;
              SetZoneG(gr, i, r * v, g * v, b * v);
            }
            break;
          }
          case "fire": {
            // Cool every zone, then randomly spark a few. The old model added
            // heat every frame, which drove the steady state above 1.0 so every
            // zone sat clamped at maximum - a flat, pale glow with no life.
            double cool  = Math.Pow(0.02, dt);              // frame-rate independent
            double spark = 1.0 - Math.Pow(1.0 - 0.10, dt * 60.0);
            for (int i = 0; i < gr.N; i++) {
              gr.Heat[i] *= cool;
              if (rnd.NextDouble() < spark) gr.Heat[i] += 0.30 + rnd.NextDouble() * 0.45;
              if (gr.Heat[i] > 1.0) gr.Heat[i] = 1.0;
              double v = gr.Heat[i];
              // Blackbody-ish ramp in LINEAR light. Blue is held at zero until
              // the zone is genuinely hot, so the fire stays saturated instead
              // of washing out to pale orange.
              double lr = v * 1.45; if (lr > 1.0) lr = 1.0;
              double g2 = (v - 0.32) * 1.5; if (g2 < 0) g2 = 0; if (g2 > 1) g2 = 1;
              double b2 = (v - 0.78) * 3.0; if (b2 < 0) b2 = 0; if (b2 > 1) b2 = 1;
              SetZoneG(gr, i, ToSrgb(lr), ToSrgb(g2 * g2), ToSrgb(b2 * b2 * b2));
            }
            break;
          }
          default: {
            for (int i = 0; i < gr.N; i++) SetZoneG(gr, i, gr.PalR[0], gr.PalG[0], gr.PalB[0]);
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
        // detected wake. One 51-byte feature report every 3 seconds, which
        // the measurements show is nothing next to the frame budget.
        //
        // The heartbeat is what handles a lid open: the EC grabs the
        // keyboard back without the USB device ever going away, so no write
        // fails, DeviceLost never trips, and the wake detectors can stay
        // silent. Nothing else would ever notice.
        if (woke) {
          ReAssert(true);
          nextAssert = now + 3.0;
          woke = false;
        } else if (now >= nextAssert) {
          ReAssert(false);          // no cache invalidation, no repaint
          nextAssert = now + 3.0;
        }

        Frame(phase, dt);
        // Reopen()/ReAssert() invalidate the previous-colour cache, so the
        // next frame is a full repaint even for a static effect.
        Push();
        // Publish AFTER Push, so pr/pg/pb hold this frame's real bytes.
        // Outside the "changed" test on purpose: a static effect still has
        // to show up in the panel's preview.
        PublishFrame();

        long remain = next - sw.ElapsedTicks;
        if (remain > 0) {
          int ms = (int)((remain * 1000) / freq);
          if (ms > 1) Thread.Sleep(ms - 1);
          while (sw.ElapsedTicks < next) Thread.SpinWait(40);
        } else {
          // Missed the deadline. Count it, but do NOT slow down just
          // because of this: measurement on real hardware shows the two
          // writes taking about 11% of a 60fps budget, and the misses
          // being roughly 1% of frames caused by ordinary scheduler
          // jitter. Backing off there would permanently degrade a device
          // with 15ms of slack every frame - an earlier version of this
          // code did exactly that.
          //
          // Only react when the writes themselves genuinely cannot fit in
          // the budget, which is a real capacity limit rather than a
          // hiccup. Requires a sustained run, so one slow write cannot
          // trigger it.
          LateFrames++;
          long budgetUs = (per * 1000000L) / freq;
          if (WriteUs > (budgetUs * 3) / 4) {
            overrun++;
            if (overrun >= 120 && per < freq / 15) {
              per = per + per / 4;        // 20% slower, floor at ~15 fps
              overrun = 0;
              Fps = (int)(freq / per);
            }
          } else if (overrun > 0) {
            overrun--;
          }
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

  // Light one raw lamp by its device index, bypassing all grouping and
  // effects. Used by the zone checker so the number shown on screen is
  // unambiguously the number of the lamp that lit up.
  public void SetOne(int idx, int r, int g, int b) {
    if (idx < 0 || idx >= LampCount) return;
    fr[idx] = r; fg[idx] = g; fb[idx] = b;
    er[idx] = 0; eg[idx] = 0; eb[idx] = 0;
  }

  // Send whatever is staged, unconditionally.
  public void Flush() {
    Push(true);
    nextFrameAt = -1.0; PublishFrame();
  }

  public void Blank() {
    for (int i = 0; i < LampCount; i++) {
      fr[i]=0; fg[i]=0; fb[i]=0;
      er[i]=0; eg[i]=0; eb[i]=0;
    }
    Push(true);
    nextFrameAt = -1.0; PublishFrame();
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
    nextFrameAt = -1.0; PublishFrame();
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
  // OpenPropertyStore is never called, but COM dispatches by slot order,
  // so it cannot be left out or GetId would land on the wrong function.
  // Declared with a plain pointer to avoid dragging in IPropertyStore.
  int OpenPropertyStore(int stgmAccess, out IntPtr props);
  // Out as IntPtr, not [MarshalAs(LPWStr)] string: the string is allocated
  // by COM and the caller has to free it. Marshalling it as a string would
  // copy it and leak the original on every poll.
  int GetId(out IntPtr id);
  int GetState(out int state);
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

  // Endpoint id of the device we are currently capturing, so a switch can
  // be spotted. Null until the first successful open.
  string curId = null;

  // Ask Windows which device sound is going to right now, and what its
  // endpoint id is. Returns null if there is nothing to play through.
  static IMMDevice GetDefaultRender(out string id) {
    id = null;
    Type t = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
    IMMDeviceEnumerator en = (IMMDeviceEnumerator)Activator.CreateInstance(t);
    IMMDevice dev;
    // 0 = eRender (speakers), 0 = eConsole
    if (en.GetDefaultAudioEndpoint(0, 0, out dev) != 0 || dev == null) return null;
    IntPtr p = IntPtr.Zero;
    try {
      if (dev.GetId(out p) == 0 && p != IntPtr.Zero) id = Marshal.PtrToStringUni(p);
    } catch { }
    finally { if (p != IntPtr.Zero) Marshal.FreeCoTaskMem(p); }
    return dev;
  }

  // True when Windows is now playing through a different device than the
  // one we opened. Cheap enough to call once a second.
  bool DeviceChanged() {
    try {
      string id;
      IMMDevice d = GetDefaultRender(out id);
      if (d != null) Marshal.ReleaseComObject(d);
      if (id == null) return false;              // nothing to switch to yet
      return (curId != null && id != curId);
    } catch { return false; }
  }

  public bool Start() {
    bool ok = Open();
    if (!ok) return false;
    run = true;
    th = new Thread(new ThreadStart(Pump));
    th.IsBackground = true;
    th.Priority = ThreadPriority.BelowNormal;
    th.Start();
    Ok = true;
    return true;
  }

  // Open (or re-open) the capture client on whatever the default playback
  // device is right now. Split out from Start so the pump thread can call
  // it again after the user switches to Bluetooth headphones.
  bool Open() {
    try {
      IMMDevice dev = GetDefaultRender(out curId);
      if (dev == null) { Err = "no playback device"; return false; }
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
      Err = "";
      return true;
    } catch (Exception ex) {
      Err = ex.Message;
      return false;
    }
  }

  // Drop the current client without touching the pump thread.
  void CloseClient() {
    try { if (cli != null) cli.Stop(); } catch { }
    try { if (cap != null) Marshal.ReleaseComObject(cap); } catch { }
    try { if (cli != null) Marshal.ReleaseComObject(cli); } catch { }
    cap = null; cli = null;
  }

  // Re-open on the current default device. Called from the pump thread
  // when the endpoint changes or goes invalid.
  bool Reopen() {
    CloseClient();
    bool got = Open();
    Ok = got;
    return got;
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
    CloseClient();
    Ok = false;
  }

  // AUDCLNT_E_DEVICE_INVALIDATED - the endpoint went away underneath us.
  const int E_INVALIDATED = unchecked((int)0x88890004);

  void Pump() {
    int sinceCheck = 0;     // ms since we last asked "is this still the device?"
    int retryIn    = 0;     // ms to wait before trying to open again

    while (run) {
      try {
        // Not currently attached: keep trying to come back. This is the
        // path taken when Bluetooth headphones connect and briefly leave
        // the machine with no usable endpoint at all.
        if (cli == null || cap == null) {
          Decay();
          Thread.Sleep(120);
          retryIn -= 120;
          if (retryIn <= 0) { if (!Reopen()) retryIn = 900; }
          continue;
        }

        // A loopback client stays bound to the endpoint it was opened on,
        // for ever. Switching output to Bluetooth headphones does not move
        // it - it just goes quiet, because the speakers it is still
        // watching are no longer being fed. Poll for the switch and
        // re-open on the new device.
        sinceCheck += 8;
        if (sinceCheck >= 1000) {
          sinceCheck = 0;
          if (DeviceChanged()) { Reopen(); continue; }
        }

        uint avail;
        int hr = cap.GetNextPacketSize(out avail);
        if (hr == E_INVALIDATED) { CloseClient(); Ok = false; retryIn = 0; continue; }
        if (hr != 0) { Thread.Sleep(10); continue; }
        if (avail == 0) { Thread.Sleep(8); Decay(); continue; }

        while (avail > 0 && run) {
          IntPtr p; uint frames, flags; long dp, qp;
          int hb = cap.GetBuffer(out p, out frames, out flags, out dp, out qp);
          if (hb == E_INVALIDATED) { CloseClient(); Ok = false; retryIn = 0; break; }
          if (hb != 0) break;
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
        if (cli == null) continue;      // invalidated inside the drain loop
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

'@ -ErrorAction Stop
} catch {
    $msg = $_.Exception.Message
    try {
        # This runs before the main log path is worked out, so repeat the
        # choice here: program folder first, AppData if that fails. Uses
        # $Here, set at the top of the script - $MyInvocation inside a
        # catch block does not reliably refer to the script itself.
        $sd = Join-Path $Here 'logs'
        try { New-Item -ItemType Directory -Force -Path $sd -ErrorAction Stop | Out-Null }
        catch {
            $sd = Join-Path (Join-Path $env:LOCALAPPDATA 'KeyboardLighting') 'logs'
            New-Item -ItemType Directory -Force -Path $sd | Out-Null
        }
        Add-Content -Path (Join-Path $sd 'engine.log') -Encoding UTF8 -ErrorAction SilentlyContinue `
            -Value ('{0}  ERROR  engine failed to compile: {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $msg)
    } catch { }
    Write-Host ''
    Write-Host '  The lighting engine could not be compiled.' -ForegroundColor Red
    Write-Host ("  {0}" -f $msg) -ForegroundColor Red
    Write-Host '  This has been written to logs\engine.log.' -ForegroundColor Red
    exit 2
}
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
$bannerBar = $Effect; if ($BarEffect) { $bannerBar = $BarEffect }
Say ("AURA-BACKGROUND v16   keyboard={0}  bar={1}  fps={2}" -f $Effect,$bannerBar,$Fps) 'Cyan'
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

# Either group can demand a source, so decide from both at once.
function Sync-Sources2 {
    param([bool]$wantAudio, [bool]$wantScreen)
    if ($wantAudio) {
        if (-not $script:Audio) {
            $script:Audio = New-Object AudioCap
            if ($script:Audio.Start()) {
                $eng.Audio = $script:Audio
                Say "  Audio capture: on" 'DarkGray'
            } else {
                Say ("  Audio capture failed: " + $script:Audio.Err) 'Yellow'
                $script:Audio = $null
            }
        }
    } elseif ($script:Audio) {
        $script:Audio.Stop(); $eng.Audio = $null; $script:Audio = $null
    }

    if ($wantScreen) {
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
} else {
    # The device declared no minimum interval. Each frame is two synchronous
    # feature reports, and HID control transfers are scheduled per 1 ms USB
    # frame, so much past this the writes simply queue and the render thread
    # blocks - which looks like stutter rather than smoothness.
    if ($fpsCap -gt 250) { $fpsCap = 250 }
}
Say ("  Update rate {0} fps (asked {1}, device min interval {2} us)." -f $fpsCap, $Fps, $minUpdUs) 'Gray'
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

# ---- split the lamps into deck and light bar -------------------------
# A zone well inside the chassis rectangle is a keyboard-deck key; one
# hugging an edge is part of the light bar. Same interior test the loop
# layout already uses, so the two always agree.
$deckIdx = New-Object System.Collections.ArrayList
$barIdx  = New-Object System.Collections.ArrayList
if ($spanX -gt 0 -and $spanY -gt 0) {
    $innerSplit = 0.12 * [Math]::Min($spanX, $spanY)
    for ($s = 0; $s -lt $lampCount; $s++) {
        $x = $xs[$s] - $xmin
        $y = $ys[$s] - $ymin
        $mm = [Math]::Min([Math]::Min($y, ($spanY - $y)), [Math]::Min($x, ($spanX - $x)))
        if ($mm -gt $innerSplit) { [void]$deckIdx.Add($s) } else { [void]$barIdx.Add($s) }
    }
}
# If the geometry does not separate (some firmware reports everything on
# one line), fall back to a single group so nothing breaks.
if ($deckIdx.Count -eq 0 -or $barIdx.Count -eq 0) {
    $deckIdx = New-Object System.Collections.ArrayList
    for ($s = 0; $s -lt $lampCount; $s++) { [void]$deckIdx.Add($s) }
    $barIdx = New-Object System.Collections.ArrayList
}

function New-Zone {
    # $UseListOrder: take the travel order straight from the order the
    # members were listed in, rather than from the geometry the driver
    # worked out. This is what makes a hand-written ring order in
    # zonemap.json actually do something - without it the members were
    # reordered by their computed positions and the list was ignored.
    param([string]$Name, $Members, [switch]$UseListOrder)
    $z = New-Object Zone
    $z.Name = $Name
    $z.Idx  = [int[]]@($Members)
    $n = $z.Idx.Length
    if ($n -eq 0) { return $z }

    if ($UseListOrder) {
        # Spread evenly along the sequence given. On a ring the last lamp
        # must not land on 1.0 - it sits one step before the seam, so the
        # pattern carries on round instead of snapping back.
        $acrL = New-Object double[] $n
        $lopL = New-Object double[] $n
        for ($k = 0; $k -lt $n; $k++) {
            if ($n -gt 1) { $acrL[$k] = $k / [double]($n - 1) } else { $acrL[$k] = 0.0 }
            $lopL[$k] = $k / [double]$n
        }
        $z.PosAcross = $acrL
        $z.PosLoop   = $lopL
        $z.Pos       = $acrL
        $z.Alloc()
        return $z
    }

    # Re-normalise both travel maps so each group spans a full 0..1 on its
    # own. Without this the deck would only ever use the 0.05..0.23 slice
    # of a gradient and look almost static.
    $acr = New-Object double[] $n
    $lop = New-Object double[] $n
    $aVals = @(); $lVals = @()
    foreach ($m in $z.Idx) { $aVals += $spAcross[$m]; if ($spLoop) { $lVals += $spLoop[$m] } else { $lVals += $spAcross[$m] } }
    $aMin = ($aVals | Measure-Object -Minimum).Minimum
    $aMax = ($aVals | Measure-Object -Maximum).Maximum
    $lMin = ($lVals | Measure-Object -Minimum).Minimum
    $lMax = ($lVals | Measure-Object -Maximum).Maximum
    for ($k = 0; $k -lt $n; $k++) {
        if ($aMax -gt $aMin) { $acr[$k] = ($aVals[$k] - $aMin) / ($aMax - $aMin) }
        elseif ($n -gt 1)    { $acr[$k] = $k / [double]($n - 1) }
        else                 { $acr[$k] = 0.0 }
        # The loop map is a CLOSED ring: the first and last lamps are
        # physically next to each other at the seam. Stretching them to
        # exactly 0 and 1 puts them at opposite ends of the gradient, so
        # the pattern ran 0..1 across the bar and then snapped back -
        # which made the first colour appear to last far longer than the
        # second. Normalise over the full ring instead, leaving one step
        # of room for the seam so the pattern carries on around evenly.
        if ($lMax -gt $lMin -and $n -gt 1) {
            $lSpan = ($lMax - $lMin) * $n / [double]($n - 1)
            $lop[$k] = ($lVals[$k] - $lMin) / $lSpan
        }
        elseif ($n -gt 1)    { $lop[$k] = $k / [double]$n }
        else                 { $lop[$k] = 0.0 }
    }
    $z.PosAcross = $acr
    $z.PosLoop   = $lop
    $z.Pos       = $acr
    $z.Alloc()
    return $z
}

# A correction saved by Zones.ps1 wins over automatic detection. This is
# the escape hatch for a machine whose zones are grouped or ordered wrongly.
$zoneMapFile = Join-Path $env:LOCALAPPDATA 'KeyboardLighting\zonemap.json'
$zoneRingOverride = $null
$zoneOrderFromUser = $false
$barListOrder = $false
if (Test-Path $zoneMapFile) {
    try {
        $zm = Get-Content $zoneMapFile -Raw | ConvertFrom-Json
        $okK = @(); $okB = @()
        foreach ($v in @($zm.Kbd)) { $iv = [int]$v; if ($iv -ge 0 -and $iv -lt $lampCount) { $okK += $iv } }
        foreach ($v in @($zm.Bar)) { $iv = [int]$v; if ($iv -ge 0 -and $iv -lt $lampCount) { $okB += $iv } }
        # Ignore a map that would leave nothing to light, or double up a zone.
        $both = @($okK) + @($okB)
        $uniq = @($both | Select-Object -Unique)
        if ($both.Count -gt 0 -and $both.Count -eq $uniq.Count) {
            $deckIdx = New-Object System.Collections.ArrayList
            foreach ($v in $okK) { [void]$deckIdx.Add($v) }
            $barIdx = New-Object System.Collections.ArrayList
            foreach ($v in $okB) { [void]$barIdx.Add($v) }
            if ($null -ne $zm.BarRing) { $zoneRingOverride = [bool]$zm.BarRing }
            $zoneOrderFromUser = $true
            Say "  Using your saved zone map (Zones.ps1). Delete zonemap.json to go back." 'Yellow'
        } else {
            Say "  Saved zone map looks wrong (empty or repeated zones); ignoring it." 'Yellow'
        }
    } catch {
        Say "  Could not read zonemap.json; ignoring it." 'Yellow'
    }
}

# The firmware's reported coordinates for the light bar do not describe
# the real strip: ordering by them puts lamps that are physically next to
# each other at opposite ends, so a pattern jumps about instead of
# travelling. Measured against the true order on this hardware, the
# firmware's own path is 1.8x shorter than reality - it is not a
# description of the bar at all.
#
# Real two-sided bars run up one side and back down the other, with the
# two sides interleaved in the numbering. Use that unless the user has
# saved their own order.
if (-not $zoneOrderFromUser -and $barIdx.Count -gt 3) {
    # One side carries the odd offsets, the other the even ones. Run up the
    # first side, then back down the second. The lowest-numbered lamp is the
    # LAST stop on the way back, not the first: it sits next to the start, so
    # putting it first would make the return leg climb 4 -> 14 before
    # descending, which is not how the strip runs.
    $sorted = @($barIdx | Sort-Object)
    $loB = $sorted[0]
    $sideA = @($sorted | Where-Object { ($_ - $loB) % 2 -eq 1 })
    $sideB = @($sorted | Where-Object { ($_ - $loB) % 2 -eq 0 } | Sort-Object -Descending)
    $ringOrder = @($sideA + $sideB)
    if ($ringOrder.Count -eq $barIdx.Count) {
        $barIdx = New-Object System.Collections.ArrayList
        foreach ($v in $ringOrder) { [void]$barIdx.Add([int]$v) }
        $barListOrder = $true
        Say ("  Light bar path: " + ($ringOrder -join ' ')) 'DarkGray'
    }
}

$zDeck = New-Zone 'deck' $deckIdx -UseListOrder:$zoneOrderFromUser
$zBar  = New-Zone 'bar'  $barIdx  -UseListOrder:($zoneOrderFromUser -or $barListOrder)

if ($barIdx.Count -gt 0) { $eng.Groups = [Zone[]]@($zDeck, $zBar) }
else                     { $eng.Groups = [Zone[]]@($zDeck) }
Say ("  Groups: keyboard {0} zones, light bar {1} zones." -f $deckIdx.Count, $barIdx.Count) 'DarkGray'

if ($spLoop) { $eng.SlotPosLoop = $spLoop } else { $eng.SlotPosLoop = $spAcross }
$eng.Mirror     = [bool]$Mirror
$eng.Reverse    = [bool]$Reverse
$eng.PalR       = [int[]]@($stops | ForEach-Object { $_[0] })
$eng.PalG       = [int[]]@($stops | ForEach-Object { $_[1] })
$eng.PalB       = [int[]]@($stops | ForEach-Object { $_[2] })

# ---- seed each group ------------------------------------------------
# Bar settings fall back to the keyboard's when not given, so a plain
# command line behaves exactly like it did before groups existed.
$palR = [int[]]@($stops | ForEach-Object { $_[0] })
$palG = [int[]]@($stops | ForEach-Object { $_[1] })
$palB = [int[]]@($stops | ForEach-Object { $_[2] })

function Parse-Stops {
    param([string]$csv)
    if (-not $csv) { return $null }
    $out = @()
    foreach ($tok in ($csv -split ',')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        try { $out += ,(ConvertFrom-Hex $t) } catch { }
    }
    if ($out.Count -eq 0) { return $null }
    return $out
}

# Relative band widths, as a CSV of numbers matching the colour count.
# Anything unparseable, negative, or the wrong length is dropped and the
# zone falls back to even bands.
function Parse-Widths {
    param([string]$csv, [int]$want)
    if (-not $csv) { return $null }
    $out = @()
    foreach ($tok in ($csv -split ',')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        $v = 0.0
        if (-not [double]::TryParse($t, [ref]$v)) { return $null }
        if ($v -lt 0) { $v = 0.0 }
        $out += $v
    }
    if ($out.Count -ne $want) { return $null }
    $sum = 0.0; foreach ($v in $out) { $sum += $v }
    if ($sum -le 0) { return $null }
    return [double[]]$out
}

function Seed-Zone {
    param($z, $eff, $spd, $brt, $mir, $rev, $equ, $lay, $stopsIn, $on, $widthsIn)
    if ($z.Idx.Length -eq 0) { return }
    $z.Effect     = $eff
    $z.Speed      = [double]$spd
    $z.Brightness = [double]$brt
    $z.Mirror     = [bool]$mir
    $z.Reverse    = [bool]$rev
    $z.Equalise   = ($equ -eq 'on')
    $z.Enabled    = [bool]$on
    $z.Loop       = ($lay -eq 'loop')
    if ($z.Loop -and $z.PosLoop) { $z.Pos = $z.PosLoop } else { $z.Pos = $z.PosAcross }
    if ($stopsIn) {
        $z.PalR = [int[]]@($stopsIn | ForEach-Object { $_[0] })
        $z.PalG = [int[]]@($stopsIn | ForEach-Object { $_[1] })
        $z.PalB = [int[]]@($stopsIn | ForEach-Object { $_[2] })
    } else {
        $z.PalR = $palR; $z.PalG = $palG; $z.PalB = $palB
    }
    $z.PalW = Parse-Widths $widthsIn $z.PalR.Length
}

if ($Master -lt 0) { $Master = 0.0 }
if ($Master -gt 1) { $Master = 1.0 }

# keyboard deck
Seed-Zone $zDeck $Effect $Speed $Brightness $Mirror $Reverse $Equalise $Layout $null (-not $KbdOff) $Widths

# light bar: use its own switches where supplied
$barEff = $Effect;     if ($BarEffect)              { $barEff = $BarEffect }
$barSpd = $Speed;      if ($BarSpeed      -gt 0)    { $barSpd = $BarSpeed }
$barBrt = $Brightness; if ($BarBrightness -ge 0)    { $barBrt = $BarBrightness }
$barEqu = $Equalise;   if ($BarEqualise)            { $barEqu = $BarEqualise }
$barLay = $Layout;     if ($BarLayout)              { $barLay = $BarLayout }
$barStops = Parse-Stops $BarColors
$barWid = $Widths; if ($BarWidths) { $barWid = $BarWidths }
Seed-Zone $zBar $barEff $barSpd $barBrt ($BarMirror.IsPresent) ($BarReverse.IsPresent) $barEqu $barLay $barStops (-not $BarOff) $barWid

# A saved zone map is the user telling us the real shape of their hardware,
# so it wins over the panel's Wrap-around box. This has to run after
# Seed-Zone, which sets Loop from -BarLayout and would otherwise wipe it.
if ($null -ne $zoneRingOverride) {
    $zBar.Loop = $zoneRingOverride
    if ($zBar.Loop -and $zBar.PosLoop) { $zBar.Pos = $zBar.PosLoop } else { $zBar.Pos = $zBar.PosAcross }
    Say ("  Light bar ring: {0} (from your saved zone map)." -f $(if ($zBar.Loop) { 'on' } else { 'off' })) 'Yellow'
}

foreach ($z in @($zDeck, $zBar)) { $z.Master = [double]$Master }

# The panel draws its preview from this: the real bytes the engine sends,
# not a reproduction of the effect. Set before anything drives the device
# so Blank()/Solid() and the very first frames are all published.
$frameFile = Join-Path $env:LOCALAPPDATA 'KeyboardLighting\frame.txt'
try {
    $fd = Split-Path -Parent $frameFile
    if (-not (Test-Path $fd)) { New-Item -ItemType Directory -Force -Path $fd | Out-Null }
    $eng.FramePath  = $frameFile
    $eng.LayoutPath = Join-Path $fd 'layout.txt'
    $eng.FrameHz    = 20
} catch { }

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

# Zones.ps1 uses this: walk the light bar's ring order one lamp at a time
# so the travel path can be watched directly. Prints each lamp as it lights
# so what is on screen and what is on the keyboard can be compared.
if ($ChaseTest) {
    $grp = $zBar
    if ($ChaseWhich -eq 'kbd') { $grp = $zDeck }
    if ($grp.Idx.Length -eq 0) {
        $eng.Close(); Say "  That group has no zones." 'Red'; exit 4
    }
    # Walk in travel order: sort the slots by the position actually in use.
    $pairs = @()
    for ($k = 0; $k -lt $grp.Idx.Length; $k++) {
        $pairs += [pscustomobject]@{ Slot = $k; Lamp = $grp.Idx[$k]; P = $grp.Pos[$k] }
    }
    $walk = @($pairs | Sort-Object P)
    Say ("  Travel order: " + (($walk | ForEach-Object { $_.Lamp }) -join ' -> ')) 'Cyan'
    Say ("  Ring: " + $(if ($grp.Loop) { 'yes, it closes back to the start' } else { 'no, it is a straight run' })) 'Cyan'
    Say "" 
    $rgbC = ConvertFrom-Hex $Color
    $laps = 2
    for ($lap = 0; $lap -lt $laps; $lap++) {
        foreach ($w in $walk) {
            $eng.Blank()
            $eng.SetOne($w.Lamp, $rgbC[0], $rgbC[1], $rgbC[2])
            $eng.Flush()
            Say ("  lit zone {0}" -f $w.Lamp) 'Gray'
            Start-Sleep -Milliseconds ([int]($HoldSeconds * 1000))
        }
    }
    $eng.Blank(); $eng.Close()
    Say "" 
    Say "  Done." 'Green'
    return
}

# Zones.ps1 uses this: light only the zones asked for, hold, then hand the
# keyboard straight back. Lets the user see which physical light is which.
if ($ZoneTest) {
    $want = @()
    foreach ($tok in ($ZoneTest -split ',')) {
        $tk = "$tok".Trim()
        if ($tk -eq '') { continue }
        $iv = 0
        if ([int]::TryParse($tk, [ref]$iv) -and $iv -ge 0 -and $iv -lt $lampCount) { $want += $iv }
    }
    if ($want.Count -eq 0) {
        $eng.Close()
        Say ("  No valid zone numbers in '$ZoneTest' (device has $lampCount zones, 0..$($lampCount-1)).") 'Red'
        exit 3
    }
    $rgb = ConvertFrom-Hex $Color
    $eng.Blank()
    foreach ($z in $want) { $eng.SetOne($z, $rgb[0], $rgb[1], $rgb[2]) }
    $eng.Flush()
    $ms = [int]($HoldSeconds * 1000); if ($ms -lt 50) { $ms = 50 }
    Start-Sleep -Milliseconds $ms
    $eng.Blank()
    $eng.Close()
    Say ("  Lit zones: " + ($want -join ', ')) 'Green'
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

$aud = @('spectrum','vumeter','beat','pulsebass')
Sync-Sources2 (($aud -contains $Effect) -or ($aud -contains $barEff)) (($Effect -eq 'ambient') -or ($barEff -eq 'ambient'))
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
# Next to the program, matching the panel. $Here is set at the top of this
# script, where the cached Engine.dll is looked for. Same writability
# fallback as the panel: if the program folder cannot be written to, use
# AppData rather than lose the log.
$logDir = Join-Path $Here 'logs'
try {
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir -ErrorAction Stop | Out-Null }
    $probe = Join-Path $logDir '.writetest'
    Set-Content -Path $probe -Value 'x' -ErrorAction Stop
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
} catch {
    $logDir = Join-Path $stateDir 'logs'
    try { if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null } } catch { }
}
$engLog    = Join-Path $logDir 'engine.log'
$liveFile  = Join-Path $stateDir 'live.txt'
$themeFile = Join-Path $stateDir 'theme.json'

# Same shape as the panel's logger, including the trim: this file is
# appended to for as long as the engine runs, and without a cap it would
# grow without bound on a machine left on for weeks.
function Write-Log($msg, $level = 'INFO') {
    $line = '{0}  {1,-5}  {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $level, $msg
    try {
        Add-Content -Path $engLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        $fi = Get-Item $engLog -ErrorAction SilentlyContinue
        if ($fi -and $fi.Length -gt 262144) {
            $keep = Get-Content $engLog -Tail 400 -ErrorAction SilentlyContinue
            Set-Content -Path $engLog -Value $keep -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    } catch { }
}
$script:SysTick = 0
$script:LastAc  = $null
$script:LastPct = 100
$script:LiveLevel = [int]([Math]::Round($Master * 1000))
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
    # Fn keys are a master control: they scale every group without
    # touching each group's own brightness setting.
    foreach ($z in $eng.Groups) {
        $z.LiveMaster = $level
        $z.LiveDirty = $true
    }
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

# Report the real cost of talking to the device, once, after the loop has
# settled. This is the number that decides whether a frame rate is
# achievable: two synchronous feature reports per frame, and if that pair
# costs more than the frame budget the light cannot land evenly no matter
# what rate is requested.
$script:TimingAt = [DateTime]::UtcNow.AddSeconds(5)
$script:TimingDone = $false

$step = 125    # 8 steps across the full range, like the firmware
# The app asks us to stop by creating this file. Being killed outright
# skips the cleanup below, which is what used to leave the last frame
# frozen on the keyboard.
$stopFile = Join-Path $stateDir 'stop.flag'
if (Test-Path $stopFile) { Remove-Item $stopFile -Force -ErrorAction SilentlyContinue }

# Take a handle to the owning app once, so the check in the loop is a cheap
# flag read rather than a process lookup sixty times a second. If the owner
# has already gone by the time we get here, treat it as no owner: a one-shot
# launched by an app that has since exited should still finish its job.
$ownerProc = $null
if ($OwnerPid -gt 0) {
    try { $ownerProc = [System.Diagnostics.Process]::GetProcessById($OwnerPid) }
    catch { $ownerProc = $null; Write-Log ("owner pid {0} not found at startup" -f $OwnerPid) }
    if ($ownerProc) { Write-Log ("watching owner pid {0}" -f $OwnerPid) }
}
$ownerNext = [DateTime]::UtcNow.AddSeconds(1)

try {
    while ($true) {
        if (Test-Path $stopFile) {
            Remove-Item $stopFile -Force -ErrorAction SilentlyContinue
            Say "  Stop requested." 'Yellow'
            break
        }

        # The app that owns us has gone. Leave by the same door as a normal
        # stop, so -OnExit is honoured and the device is released instead of
        # being left frozen on the last frame.
        if ($ownerProc -and [DateTime]::UtcNow -gt $ownerNext) {
            $ownerNext = [DateTime]::UtcNow.AddSeconds(1)
            $gone = $false
            try { $gone = $ownerProc.HasExited } catch { $gone = $true }
            if ($gone) {
                Say "  The app that started us has closed. Shutting down." 'Yellow'
                Write-Log ("owner pid {0} exited - stopping" -f $OwnerPid)
                break
            }
        }

        # Sampled repeatedly rather than once. The interesting number is
        # not the steady state - that has measured fine - but the rare
        # stall, and a single reading five seconds in cannot show whether
        # those are isolated or building up. Each line resets the worst
        # and late counters so every entry describes its own interval.
        if ([DateTime]::UtcNow -gt $script:TimingAt) {
            $script:TimingAt = [DateTime]::UtcNow.AddSeconds(60)
            $budget = [int](1000000 / [Math]::Max(1, $eng.Fps))
            $msg = ('device write {0} us/frame (worst {1}), budget {2} us at {3} fps, late frames {4} in last interval' -f `
                    $eng.WriteUs, $eng.WriteUsMax, $budget, $eng.Fps, $eng.LateFrames)
            if (-not $script:TimingDone) {
                $script:TimingDone = $true
                Say ("  Timing: {0}" -f $msg) 'DarkGray'
            }
            Write-Log $msg
            $eng.WriteUsMax = 0
            $eng.LateFrames = 0
        }
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
                    foreach ($z in $eng.Groups) { $z.LiveDirty = $true }
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
                foreach ($z in $eng.Groups) { $z.LiveDirty = $true }
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
                        foreach ($z in $eng.Groups) {
                            $z.LiveMaster = $val
                            $z.LiveDirty = $true
                        }
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
                    # Parse BEFORE recording the stamp. Recording it first
                    # meant a read that failed - an empty or half-written
                    # file - consumed the change: the stamp said "seen" but
                    # nothing had been applied, and the update was lost
                    # until something else happened to touch the file. The
                    # panel now writes atomically, so this should not
                    # trigger, but a dropped settings change is bad enough
                    # to be worth being certain about.
                    $raw = Get-Content $themeFile -Raw -ErrorAction Stop
                    if (-not $raw -or -not $raw.Trim()) { throw 'empty theme file' }
                    $j = $raw | ConvertFrom-Json
                    $script:ThemeStamp = $stamp

                    # The panel writes one block per group. Anything the bar
                    # block leaves out inherits the keyboard's value, so an
                    # old single-group theme file still works unchanged.
                    $needAud = $false
                    $needScr = $false

                    # Smooth is engine-wide rather than per-group: it
                    # controls how colours are written to the hardware, not
                    # what any one zone is showing. Absent means auto.
                    if ($null -ne $j.Smooth) {
                        $eng.DitherMode = $(if ($j.Smooth) { 0 } else { 1 })
                    } else {
                        $eng.DitherMode = -1
                    }

                    $grp = @()
                    if ($eng.Groups.Length -gt 0) { $grp += ,@($eng.Groups[0], $j.Kbd, $j) }
                    if ($eng.Groups.Length -gt 1) { $grp += ,@($eng.Groups[1], $j.Bar, $j) }

                    foreach ($pair in $grp) {
                        $z    = $pair[0]
                        $blk  = $pair[1]
                        $root = $pair[2]
                        # fall back to the root object for old-format files
                        if (-not $blk) { $blk = $root }

                        $ef = $null
                        if ($blk.Effect) { $ef = [string]$blk.Effect }
                        elseif ($root.Effect) { $ef = [string]$root.Effect }
                        if ($ef) {
                            $z.LiveEffect = $ef
                            if (@('spectrum','vumeter','beat','pulsebass') -contains $ef) { $needAud = $true }
                            if ($ef -eq 'ambient') { $needScr = $true }
                        }

                        $sv = $null
                        if ($null -ne $blk.Speed) { $sv = [double]$blk.Speed }
                        elseif ($null -ne $root.Speed) { $sv = [double]$root.Speed }
                        if ($null -ne $sv) { $z.LiveSpeedMilli = [int]([Math]::Round($sv * 1000)) }

                        $cv = $null
                        if ($blk.Colors) { $cv = [string]$blk.Colors }
                        elseif ($root.Colors) { $cv = [string]$root.Colors }
                        if ($cv) {
                            $ns = @()
                            foreach ($cstr in ($cv -split ',')) {
                                if ($cstr.Trim()) { $ns += ,(ConvertFrom-Hex $cstr) }
                            }
                            if ($ns.Count -eq 1) { $ns = @($ns[0], $ns[0]) }
                            if ($ns.Count -gt 2 -and
                                $ns[0][0] -eq $ns[-1][0] -and
                                $ns[0][1] -eq $ns[-1][1] -and
                                $ns[0][2] -eq $ns[-1][2]) {
                                $ns = @($ns[0..($ns.Count-2)])
                            }
                            if ($ns.Count -gt 0) {
                                # Widths have to line up with the palette as
                                # the engine ended up holding it, not as the
                                # panel sent it: a single colour is doubled
                                # and a repeated last colour is dropped just
                                # above, so the counts can differ.
                                $wv = $null
                                if ($null -ne $blk.Widths) { $wv = [string]$blk.Widths }
                                $wOut = $null
                                if ($wv) {
                                    $tmp = @()
                                    $bad = $false
                                    foreach ($wtok in ($wv -split ',')) {
                                        $wt = $wtok.Trim()
                                        if (-not $wt) { continue }
                                        $wd = 0.0
                                        if ([double]::TryParse($wt, [ref]$wd)) {
                                            if ($wd -lt 0) { $wd = 0.0 }
                                            $tmp += $wd
                                        } else { $bad = $true }
                                    }
                                    if (-not $bad -and $tmp.Count -eq $ns.Count) {
                                        $tot = 0.0; foreach ($wd in $tmp) { $tot += $wd }
                                        if ($tot -gt 0) {
                                            $wOut = [double[]]@($tmp | ForEach-Object { [double]$_ })
                                        }
                                    }
                                }

                                # Build the whole palette first, then hand it
                                # over in ONE assignment. Assigning the three
                                # colour arrays separately let the render
                                # thread catch the set half-swapped and draw a
                                # frame with new reds against old blues - a
                                # visible flash on every colour change. Null
                                # widths mean even bands.
                                $z.LivePal = New-Object PalSet(
                                    [int[]]@($ns | ForEach-Object { $_[0] }),
                                    [int[]]@($ns | ForEach-Object { $_[1] }),
                                    [int[]]@($ns | ForEach-Object { $_[2] }),
                                    $wOut)
                            }
                        }

                        $fl = 0
                        $mv = $blk.Mirror;   if ($null -eq $mv) { $mv = $root.Mirror }
                        $rv = $blk.Reverse;  if ($null -eq $rv) { $rv = $root.Reverse }
                        $qv = $blk.Equalise; if ($null -eq $qv) { $qv = $root.Equalise }
                        $lv = $blk.Loop;     if ($null -eq $lv) { $lv = $root.Loop }
                        if ([bool]$mv) { $fl = $fl -bor 1 }
                        if ([bool]$rv) { $fl = $fl -bor 2 }
                        if ([bool]$qv) { $fl = $fl -bor 4 }
                        if ([bool]$lv) { $fl = $fl -bor 8 }
                        $z.LiveFlags = $fl

                        $onv = $blk.On
                        if ($null -eq $onv) { $onv = $true }
                        if ([bool]$onv) { $z.LiveEnabled = 1 } else { $z.LiveEnabled = 0 }

                        $bv2 = $null
                        if ($null -ne $blk.Brightness) { $bv2 = [double]$blk.Brightness }
                        elseif ($null -ne $root.Brightness) { $bv2 = [double]$root.Brightness }
                        if ($null -ne $bv2) {
                            $bi = [int]([Math]::Round($bv2 * 1000))
                            if ($bi -lt 0) { $bi = 0 }
                            if ($bi -gt 1000) { $bi = 1000 }
                            $z.LiveBrightness = $bi
                        }

                        $z.LiveDirty = $true
                    }

                    # Master brightness still drives the Fn keys and the
                    # shared live file.
                    if ($null -ne $j.Brightness) {
                        $bv = [int]([Math]::Round([double]$j.Brightness * 1000))
                        if ($bv -lt 0) { $bv = 0 }
                        if ($bv -gt 1000) { $bv = 1000 }
                        $script:LiveLevel = $bv
                        foreach ($z in $eng.Groups) {
                            $z.LiveMaster = $bv
                            $z.LiveDirty = $true
                        }
                    }

                    Sync-Sources2 $needAud $needScr
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
    switch ($OnExit) {
        'white'    { Say "  Stopping. Leaving the keyboard plain white." 'Yellow' }
        'firmware' { Say "  Stopping. Handing lighting back to the keyboard firmware." 'Yellow' }
        default    { Say "  Stopping. Turning the lighting off." 'Yellow' }
    }
    $eng.Stop()
    # Leave the keyboard in the state the user asked for. 'white' keeps the
    # keys readable in the dark once the app is gone.
    if ($OnExit -eq 'white') { $eng.Solid(255,255,255) } else { $eng.Blank() }
    $eng.Close()
    # Blank() publishes an all-off frame, but once we exit nothing is
    # driving the keyboard at all. Remove the file so the panel shows its
    # idle state rather than a stale frame.
    try {
        $ff = Join-Path $env:LOCALAPPDATA 'KeyboardLighting\frame.txt'
        if (Test-Path $ff) { Remove-Item $ff -Force -ErrorAction SilentlyContinue }
    } catch { }
    # Only hand control back to the keyboard's own firmware when that is
    # what was asked for. Re-enabling autonomous mode makes the firmware
    # repaint immediately, which would wipe the off/white we just set.
    $h2 = $INVALID
    if ($OnExit -eq 'firmware') {
        $h2=[HidNative]::CreateFileW($devPath,$GENRW,$SHARERW,[IntPtr]::Zero,$OPENEXIST,[uint32]0,[IntPtr]::Zero)
    }
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
