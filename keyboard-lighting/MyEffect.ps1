# ============================================================================
#  MY EFFECT  -  write your own keyboard animation here
# ============================================================================
#
#  Run it with:
#     powershell -ExecutionPolicy Bypass -File .\Aura-Background.ps1 -Custom .\MyEffect.ps1
#
#  RULES
#    * This file must END with a scriptblock:  { param($t, $N)  ... }
#    * It is called once per frame.
#    * $t = seconds since start, already multiplied by -Speed
#    * $N = number of zones (16 on your keyboard)
#    * Call  Set-Zone <slot> <red> <green> <blue>  once per zone.
#         slot  0 = far LEFT, $N-1 = far RIGHT (sorted by real position)
#         red/green/blue = 0 to 255
#    * -Brightness is applied for you. Don't scale manually.
#
#  Helpers you can use:
#     Convert-Hsv <hue 0-360> <sat 0-1> <val 0-1>   -> @(r,g,b)
#     ConvertFrom-Hex "#FF8800"                      -> @(r,g,b)
#
#  Below are several ready-made examples. Only the LAST scriptblock in the
#  file actually runs, so move the one you want to the bottom, or just edit
#  the active one.
# ============================================================================


# ---------------------------------------------------------------------------
# EXAMPLE 1  -  Two-colour scrolling gradient  (edit these two colours)
# ---------------------------------------------------------------------------
# {
#     param($t, $N)
#     $a = ConvertFrom-Hex "#FF0066"     # colour A
#     $b = ConvertFrom-Hex "#00B4FF"     # colour B
#     for ($i = 0; $i -lt $N; $i++) {
#         # position along the strip, scrolling with time
#         $p = (($i / [double]$N) + $t * 0.25) % 1.0
#         # triangle wave: 0 -> 1 -> 0, so it loops seamlessly
#         $w = if ($p -lt 0.5) { $p * 2.0 } else { (1.0 - $p) * 2.0 }
#         Set-Zone $i `
#             ($a[0] + ($b[0] - $a[0]) * $w) `
#             ($a[1] + ($b[1] - $a[1]) * $w) `
#             ($a[2] + ($b[2] - $a[2]) * $w)
#     }
# }


# ---------------------------------------------------------------------------
# EXAMPLE 2  -  Police lights
# ---------------------------------------------------------------------------
# {
#     param($t, $N)
#     $flash = [int]($t * 4) % 2
#     $half  = [int]($N / 2)
#     for ($i = 0; $i -lt $N; $i++) {
#         if ($i -lt $half) {
#             if ($flash -eq 0) { Set-Zone $i 255 0 0 } else { Set-Zone $i 0 0 0 }
#         } else {
#             if ($flash -eq 1) { Set-Zone $i 0 0 255 } else { Set-Zone $i 0 0 0 }
#         }
#     }
# }


# ---------------------------------------------------------------------------
# EXAMPLE 3  -  Two waves crossing each other
# ---------------------------------------------------------------------------
# {
#     param($t, $N)
#     for ($i = 0; $i -lt $N; $i++) {
#         $w1 = (1 + [Math]::Sin($t * 2.0 - $i * 0.5)) / 2
#         $w2 = (1 + [Math]::Sin($t * 1.3 + $i * 0.7)) / 2
#         Set-Zone $i (255 * $w1) (40 * $w1 * $w2) (255 * $w2)
#     }
# }


# ---------------------------------------------------------------------------
# EXAMPLE 4  -  Slow colour breathing through the whole rainbow
# ---------------------------------------------------------------------------
# {
#     param($t, $N)
#     $hue = ($t * 20) % 360
#     $pulse = 0.3 + 0.7 * ((1 + [Math]::Sin($t * 1.5)) / 2)
#     $c = Convert-Hsv $hue 1.0 $pulse
#     for ($i = 0; $i -lt $N; $i++) { Set-Zone $i $c[0] $c[1] $c[2] }
# }


# ---------------------------------------------------------------------------
# ACTIVE EFFECT  -  multi-stop gradient that scrolls across the keyboard
#                   Add, remove or change colours in the list below.
# ---------------------------------------------------------------------------
{
    param($t, $N)

    # >>> YOUR COLOURS. Any number of them. The list wraps around, so the
    # >>> last colour blends smoothly back into the first.
    $palette = @(
        "#FF0000"   # red
        "#FF7F00"   # orange
        "#FFFF00"   # yellow
        "#00FF00"   # green
        "#0000FF"   # blue
        "#8B00FF"   # violet
    )

    # >>> How fast it scrolls. Bigger = faster. Negative = other direction.
    $scrollSpeed = 0.20

    # ---- nothing below here needs editing ----
    if (-not $script:__pal) {
        $script:__pal = @()
        foreach ($hx in $palette) { $script:__pal += ,(ConvertFrom-Hex $hx) }
    }
    $pal = $script:__pal
    $n   = $pal.Count

    for ($i = 0; $i -lt $N; $i++) {
        # where this zone sits in the palette, 0..n, scrolling over time
        $f = ((($i / [double]$N) + $t * $scrollSpeed) % 1.0) * $n
        if ($f -lt 0) { $f += $n }

        $a = [int][Math]::Floor($f)
        $u = $f - $a
        $b = ($a + 1) % $n
        $a = $a % $n

        Set-Zone $i `
            ($pal[$a][0] + ($pal[$b][0] - $pal[$a][0]) * $u) `
            ($pal[$a][1] + ($pal[$b][1] - $pal[$a][1]) * $u) `
            ($pal[$a][2] + ($pal[$b][2] - $pal[$a][2]) * $u)
    }
}
