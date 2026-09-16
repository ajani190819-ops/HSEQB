# Keyboard Lighting for ROG Strix G16 (G615JPR)

Custom animated keyboard lighting without Armoury Crate.

## Install

Download **Setup.bat**, double-click it, click **Yes**. That is the
whole install.

**`Setup.bat` is the only file you ever run.** Run it again any time to
update, repair, or test - it works out what is needed. If something is
wrong it tells you what, and copies a report to your clipboard.

It downloads everything, builds `KeyboardLighting.exe`, adds it to your
Start menu and Desktop, sets it to start when you log in, tells G-Helper
to leave the keyboard colours alone, checks it all works, and runs it.

## Using it

It is one normal program. A window with the controls, and an icon in the
system tray next to the clock.

* **Closing the window** puts it in the tray. It keeps running.
* **Double-click the tray icon** to bring the window back.
* **Right-click the tray icon** for the menu (restart, turn off, updates,
  log file, exit).

Everything you change applies to the keyboard immediately. There is no
Apply button and nothing restarts while you adjust things.

To pin it: Start menu, right-click **Keyboard Lighting**, then *Pin to
Start* or *More > Pin to taskbar*.

## The two sections

Your laptop has two separate sets of lights, and this app treats them as
two separate things:

* **Keyboard** - the four zones under the keys.
* **Light bar** - the twelve lights around the edge of the chassis.

The **Keyboard / Light bar** switch near the top chooses which one you
are editing. Everything below the switch - pattern, colours, speed,
brightness, and the four toggles - applies only to the section that is
selected. So you can run a slow blue breathing effect under the keys and
a fast rainbow around the light bar at the same time.

The strip at the top previews both at once: the short block on the left
is the keyboard, the long block on the right is the light bar. It is not
a mock-up - the engine reports the exact colours it is sending to the
keyboard, so the preview matches the hardware even for fire, the music
modes and the meters. The light bar is shown in physical order around
the chassis, not the order the lamps happen to be numbered in, and each
lamp is drawn where it physically sits. The light bar's twelve lamps are
not evenly spaced - they sit in clusters of three with wide gaps - so the
preview blends between them the way the diffuser does, rather than
chopping the bar into twelve equal blocks. If the
engine is not running the strip dims and the labels say OFF.

* **This part is on** turns off just the section you are looking at.
* **Match both** copies whatever you do to the other section as well.
  Turn it on if you want them to stay identical.
* **Master brightness** sits above the switch because it dims
  everything. Each section also has its own brightness underneath, which
  is applied on top of the master. The Fn brightness keys drive the
  master.

## Controls

| Control | What it does |
|---|---|
| Keyboard / Light bar | Chooses which section the controls below affect |
| This part is on | Turns the selected section off on its own |
| Match both | Applies every change to both sections |
| Master brightness | Dims everything. The Fn brightness keys use this |
| Pattern | The animation. 22 of them, including music, screen mirror and meters |
| Colours | Click a square to change it. `+` and `-` add and remove colours |
| Speed | How fast the animation moves in this section |
| Brightness for this part | This section's own level, on top of the master |
| Mirror | Mirrors the pattern around the middle |
| Reverse | Runs the animation backwards |
| Wrap around | Sends the pattern around the loop instead of straight across |
| Even brightness | Evens out how bright each colour looks, so blues are not lost next to yellows |
| Flash the battery level | Briefly shows the battery when you plug in or unplug |
| Start when I log in | Starts automatically with Windows |

Every one of these takes effect the moment you change it. Nothing
restarts and there is no Apply button.

## Updating

It checks for updates in the background at startup. If it finds one, the
tray menu shows **Restart to finish update**.

## Where things live

| What | Where |
|---|---|
| Program | the folder you ran `Setup.bat` from |
| Settings | `%LOCALAPPDATA%\KeyboardLighting\panel.json` |
| Log | `%LOCALAPPDATA%\KeyboardLighting\log.txt` |
| Startup entry | Task Scheduler, task `KeyboardLighting` |

## Important

Turn **Dynamic Lighting off** in *Settings > Personalization > Dynamic
Lighting*, or Windows fights this app for control of the keyboard.

## When you close the app

Right-click the tray icon and look under **When closed**:

  Turn the lighting off      dark once the app quits. This is the default.
  Leave it plain white       keys stay readable in the dark.
  Let the keyboard take over  hands control back to the keyboard's own
                             firmware, so it does whatever it did before
                             this app was installed.

Quitting used to leave the last pattern frozen on the keys, because the
lighting was being killed outright rather than asked to stop.

## If the lighting goes to the wrong places

Run **Zones.bat**. It is a small checker for working out which physical
light is which, and correcting the map if it is wrong.

  Show the map    a picture of where the app thinks each zone sits.
  Identify        lights each zone on its own, one at a time, and tells
                  you its number. Write down what is actually where.
  Correct         type the numbers in the order they really appear.
                  For the keyboard that is left to right. For the light
                  bar it is the order a light would travel going all the
                  way round, for example 4,5,7,9,11,13,15,14,12,10,8,6 -
                  do not repeat the first number at the end, the ring
                  closes by itself. Patterns then follow exactly that
                  path.
  Reset           throw your correction away and go back to automatic.

Your correction is saved separately and is never overwritten by an
update. The lighting has to be closed while Identify runs, because only
one program can drive the keyboard at a time - the checker will say so
if it needs you to exit first.

## G-Helper

You can keep using G-Helper. `Setup.bat` sets one option in it,
`skip_aura`, which stops it pushing its own keyboard colours when it
starts. Everything else in G-Helper is untouched: fan curves,
performance modes, the Fn brightness keys, battery limits, all of it.

Without that setting the two apps fight over the keyboard every time
G-Helper launches. With it, your colours and patterns always win.

If you ever want G-Helper's own lighting modes back, open
`%AppData%\GHelper\config.json` and change `"skip_aura": 1` to `0`, or
just uninstall this app.

## Writing your own effect

Edit `MyEffect.ps1`. It must end with a block like this:

```powershell
{
    param($t, $N)
    for ($i = 0; $i -lt $N; $i++) {
        $c = Convert-Hsv (($i / $N) * 360 + $t * 60) 1 1
        Set-Zone $i $c[0] $c[1] $c[2]
    }
}
```

`$t` is seconds since start, `$N` is the zone count (16). `Set-Zone
<index> <r> <g> <b>` takes 0-255. Helpers: `ConvertFrom-Hex "#FF8800"`
and `Convert-Hsv <hue> <sat> <val>`.

Run it with:

```
Aura-Background.ps1 -Custom MyEffect.ps1
```

## Patterns

Scrolling gradient and Wave are deliberately different:

  Scrolling gradient   your colours as solid bands that roll along and
                       wrap around - a colour slides off one end and
                       comes back on the other, like one face of a
                       rotating roll of tape. Brightness stays constant.
  Wave                 the opposite: the colour stays put and a crest of
                       brightness travels along it, like wind over grass.

Animated: Scrolling gradient, Rainbow, Wave, Comet, Scanner, Breathing,
Pulse, Fire, Colour cycle, Strobe, Starry night, Ripple, Aurora, Solid.

Music (listens to your speakers):
  Music - spectrum      each zone is a frequency band
  Music - level meter   a bar that fills with loudness
  Music - beat flash    the whole keyboard flashes on the beat
  Music - bass pulse    bass pushes a wave out from the centre

Screen mirror: the keyboard copies the colours on your screen.

Information:
  Battery meter   fills with charge. Green full, red empty. A bright dot
                  runs along it while charging, and it blinks under 15%.
  CPU meter       fills with how hard the computer is working.
  Clock           colour follows the time of day.

Battery flash: leave "Flash battery on plug / unplug" on and the keyboard
briefly shows your battery level whenever you plug in or unplug the
charger, or drop past 20 / 10 / 5 percent, then goes back to your pattern.

The music and screen modes only start capturing while they are selected,
so the other patterns cost nothing extra.

## Sleep

Closing the lid, locking, or sleeping makes the laptop's own controller
take the keyboard back. The app re-claims it every few seconds, so your
effect returns by itself within about three seconds of waking. You should
never have to restart anything.

## If something goes wrong

Run **Setup.bat**. It re-downloads everything and prints a diagnostic;
the banner should say **v16**. The log file is in the tray menu under
*Open log file*.

## How it works

`Tray.ps1` is the application: window, tray icon, settings, updater.
`ui_controls.cs.txt` is the interface, compiled at startup.
`Aura-Background.ps1` is the lighting engine, a compiled C# render loop
driving the keyboard's HID LampArray interface directly. The sixteen
lamps are split into two independent render groups - four keyboard zones
and twelve light-bar zones - each with its own pattern, palette, speed,
brightness and phase. The app talks to a running engine through
`theme.json`, which carries a block per group, so every change applies
without a restart. `KeyboardLighting.exe` is a small launcher stub, compiled on
your machine by the C# compiler included with Windows.
