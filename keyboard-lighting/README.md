# Keyboard Lighting — ROG Strix G16 G615JPR

Animated keyboard backlight without Armoury Crate, without Windows Dynamic
Lighting, and without the "app must be in the foreground" restriction.

Talks straight to the keyboard's HID LampArray interface
(`HID\VID_0B05&PID_19B6&MI_01`, usage page `0x59`).

## Your hardware

| | |
|---|---|
| Zones | 16 |
| Colour depth | 255 levels per channel (full 8-bit RGB) |
| Zones 0–3 | keyboard deck, left to right |
| Zones 4–15 | perimeter light bar |
| Autonomous mode | can be disabled — host control confirmed working |

## Files

| File | What it does |
|---|---|
| `Find-Lamps.ps1` | Diagnostic. Prints the zone map and runs a colour test. |
| `Aura-Background.ps1` | The lighting engine. Nine effects. |
| `Install-Autostart.ps1` | Makes it start automatically at logon. |

## Setup

**Turn Windows Dynamic Lighting off first** — otherwise Windows fights the
script for control:
Settings → Personalization → Dynamic Lighting → **Use Dynamic Lighting on my
devices** → Off.

Open **Windows PowerShell as Administrator**, then download:

```powershell
[Net.ServicePointManager]::SecurityProtocol='Tls12'
$d="$env:USERPROFILE\Downloads"
$b='https://raw.githubusercontent.com/ajani190819-ops/HSEQB/arena/01a0a5d4-hseqb/keyboard-lighting'
foreach($f in 'Find-Lamps.ps1','Aura-Background.ps1','Install-Autostart.ps1'){
  Invoke-WebRequest "$b/$f" -OutFile "$d\$f" -UseBasicParsing
  Unblock-File "$d\$f"
}
```

## Run an effect

```powershell
cd $env:USERPROFILE\Downloads
powershell -ExecutionPolicy Bypass -File .\Aura-Background.ps1 -Effect rainbow
```

Ctrl+C stops it and hands lighting back to the firmware.

## Effects

| Name | Description |
|---|---|
| `wave` | colour sweeps left to right |
| `rainbow` | full spectrum scrolling across the zones |
| `breathe` | whole keyboard fades in and out |
| `comet` | bright head with a fading tail, looping |
| `pulse` | sharp flash then slow decay, colour shifts each beat |
| `scanner` | single bright zone bouncing left-right |
| `fire` | flickering warm embers |
| `static` | one solid colour |
| `off` | all lamps off |

## Options

| Switch | Default | Meaning |
|---|---|---|
| `-Effect` | `wave` | which effect |
| `-Color` | `#00B4FF` | main colour |
| `-Color2` | `#FF0066` | secondary colour (used by `wave`) |
| `-Speed` | `1.0` | higher is faster |
| `-Brightness` | `1.0` | `0.0`–`1.0` |
| `-Fps` | `30` | frames per second |
| `-Restore` | | give control back to the firmware and exit |
| `-Quiet` | | no console output |

Example:

```powershell
powershell -ExecutionPolicy Bypass -File .\Aura-Background.ps1 -Effect comet -Color "#FF2200" -Speed 1.6 -Brightness 0.6
```

## Start it automatically at logon

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-Autostart.ps1 -Effect rainbow -Brightness 0.8
```

Creates a scheduled task that runs the engine hidden at logon. No window, no
tray icon, one PowerShell process.

```powershell
.\Install-Autostart.ps1 -Status      # is it installed?
.\Install-Autostart.ps1 -Uninstall   # remove everything
```

To change the effect later, run the installer again with a different
`-Effect`. It replaces the old task.

## Writing your own effect

Open `Aura-Background.ps1` and find the `switch ($Effect)` block. Each effect
fills one frame by calling `Set-Zone` once per zone:

```powershell
'myeffect' {
    for ($i = 0; $i -lt $N; $i++) {
        # $t  = seconds elapsed, already multiplied by -Speed
        # $N  = zone count (16)
        # $i  = slot number, 0 = leftmost, ordered by physical X position
        # values are 0-255 per channel
        $w = (1.0 + [Math]::Sin($t * 2.0 - $i * 0.4)) / 2.0
        Set-Zone $i (255 * $w) 0 (255 * (1 - $w))
    }
}
```

Then add `myeffect` to the `ValidateSet` list at the top of the file.

`Set-Zone` takes a *slot* number, not a raw lamp ID — slots are sorted
left-to-right by the physical X position the keyboard reports, so animations
travel across the deck in the right order. `Push-Frame` handles the
translation and only writes zones whose colour actually changed.

## Notes

- Needs Administrator — raw HID access requires it.
- `Ctrl+C` and `-Uninstall` both re-enable autonomous mode, restoring the
  keyboard's built-in lighting.
- Nothing is written to the keyboard's persistent memory. A reboot always
  returns it to firmware default.
- If the keyboard stops responding to the script, unplug/replug or reboot to
  reset the HID interface.
