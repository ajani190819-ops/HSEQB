# Keyboard lighting for ROG Strix G16 (G615JPR)

Custom animated keyboard lighting without Armoury Crate.

## Install

Download **Install.bat** and double-click it. Click **Yes** on the
permission prompt. That is the whole install.

It will:

* download everything it needs
* build `KeyboardLighting.exe`
* add it to your **Start menu** and your **Desktop**
* set it to **start automatically when you log in**
* start the lighting straight away

## Using it

The app lives in the **system tray** (the little icons next to the clock,
click the `^` arrow if you do not see it).

* **Double-click the tray icon** - open the control panel
* **Right-click the tray icon** - menu:
  * Open control panel
  * Restart lighting
  * Turn lighting off
  * Start when I log in (tick / untick)
  * Check for updates
  * Open log file
  * Open folder
  * Exit

To pin it: find **Keyboard Lighting** in the Start menu, right-click it,
choose *Pin to Start* or *More > Pin to taskbar*.

## Updating

It updates itself quietly in the background when it starts. You can also
force it from the tray menu with **Check for updates**.

## Where things live

| What | Where |
|---|---|
| Program files | the folder you ran `Install.bat` from |
| Settings | `%LOCALAPPDATA%\KeyboardLighting\panel.json` |
| Log file | `%LOCALAPPDATA%\KeyboardLighting\log.txt` |
| Startup entry | Task Scheduler, task name `KeyboardLighting` |

## Effects

Scrolling gradient, Rainbow, Wave, Comet, Scanner, Breathing, Pulse,
Fire, Solid colour. Speed, brightness, mirror, reverse, colour
equalisation and "wrap around the light bar" are all in the panel.

The brightness keys on the keyboard (Fn + the brightness keys) change the
lighting brightness live while an effect is running.

## Important

Turn **Dynamic Lighting off** in
*Settings > Personalization > Dynamic Lighting*, or Windows will fight
this app for control of the keyboard.

## Writing your own effect

Edit `MyEffect.ps1`. It must end with a block shaped like this:

```powershell
{
    param($t, $N)
    for ($i = 0; $i -lt $N; $i++) {
        $c = Convert-Hsv (($i / $N) * 360 + $t * 60) 1 1
        Set-Zone $i $c[0] $c[1] $c[2]
    }
}
```

`$t` is seconds since start, `$N` is the number of zones (16).
`Set-Zone <index> <r> <g> <b>` takes 0-255. Helpers:
`ConvertFrom-Hex "#FF8800"` and `Convert-Hsv <hue> <sat> <val>`.

## Troubleshooting

Run **Check.bat** - it re-downloads everything and prints a diagnostic.
The banner should say **v11**.
