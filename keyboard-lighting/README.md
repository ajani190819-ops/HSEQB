# Keyboard Lighting for ROG Strix G16 (G615JPR)

Custom animated keyboard lighting without Armoury Crate.

## Install

Download **Install.bat**, double-click it, click **Yes**. That is the
whole install.

It downloads everything, builds `KeyboardLighting.exe`, adds it to your
Start menu and Desktop, sets it to start when you log in, and runs it.

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

## Controls

| Control | What it does |
|---|---|
| Pattern | The animation: gradient, rainbow, wave, comet, scanner, breathing, pulse, fire, solid |
| Colours | Click a square to change it. `+` and `-` add and remove colours |
| Speed | How fast the animation moves |
| Brightness | Overall brightness. The Fn brightness keys also work while an effect runs |
| Mirror | Mirrors the pattern around the middle |
| Reverse direction | Runs the animation backwards |
| Wrap around the light bar | Sends the gradient around the chassis instead of straight across |
| Even colour brightness | Evens out how bright each colour looks, so blues are not lost next to yellows |
| Start when I log in | Starts automatically with Windows |

## Updating

It checks for updates in the background at startup. If it finds one, the
tray menu shows **Restart to finish update**.

## Where things live

| What | Where |
|---|---|
| Program | the folder you ran `Install.bat` from |
| Settings | `%LOCALAPPDATA%\KeyboardLighting\panel.json` |
| Log | `%LOCALAPPDATA%\KeyboardLighting\log.txt` |
| Startup entry | Task Scheduler, task `KeyboardLighting` |

## Important

Turn **Dynamic Lighting off** in *Settings > Personalization > Dynamic
Lighting*, or Windows fights this app for control of the keyboard.

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

Run **Check.bat**. It re-downloads everything and prints a diagnostic;
the banner should say **v15**. The log file is in the tray menu under
*Open log file*.

## How it works

`Tray.ps1` is the application: window, tray icon, settings, updater.
`ui_controls.cs.txt` is the interface, compiled at startup.
`Aura-Background.ps1` is the lighting engine, a compiled C# render loop
driving the keyboard's HID LampArray interface directly. The app talks to
a running engine through `theme.json`, so changes apply without a
restart. `KeyboardLighting.exe` is a small launcher stub, compiled on
your machine by the C# compiler included with Windows.
