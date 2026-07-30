#!/usr/bin/env python3
"""Regenerate all app-icon assets from resources/porydaw-1024.png.

Outputs (all under resources/):
  porydaw-{16,32,48,128,256}.png  Qt runtime window-icon ladder (qrc)
  porydaw.png                     256px AppImage/.desktop icon
  porydaw.ico                     Windows executable icon (porydaw.rc)
  porydaw.icns                    macOS bundle icon

The 16/24/32px renders get a saturation + alpha boost: plain Lanczos
downscaling thins the artwork's pale cyan and soft alpha edges into
near-invisibility at title-bar sizes.

Requires Pillow.
"""

import os

from PIL import Image, ImageEnhance

RES = os.path.join(os.path.dirname(__file__), "..", "resources")
MASTER = os.path.join(RES, "porydaw-1024.png")

# size -> (saturation multiplier, alpha multiplier)
SMALL_BOOST = {16: (1.35, 1.6), 24: (1.28, 1.45), 32: (1.2, 1.3)}


def render(master, size):
    im = master.resize((size, size), Image.LANCZOS)
    if size not in SMALL_BOOST:
        return im
    sat, alpha_mul = SMALL_BOOST[size]
    r, g, b, a = im.split()
    rgb = ImageEnhance.Color(Image.merge("RGB", (r, g, b))).enhance(sat)
    a = a.point(lambda v: min(255, int(v * alpha_mul)))
    return Image.merge("RGBA", (*rgb.split(), a))


def main():
    master = Image.open(MASTER).convert("RGBA")
    assert master.size == (1024, 1024), master.size

    for size in (16, 32, 48, 128, 256):
        render(master, size).save(os.path.join(RES, f"porydaw-{size}.png"))
    render(master, 256).save(os.path.join(RES, "porydaw.png"))

    ico_sizes = (16, 24, 32, 48, 64, 256)
    frames = [render(master, s) for s in ico_sizes]
    frames[-1].save(
        os.path.join(RES, "porydaw.ico"),
        format="ICO",
        sizes=[(s, s) for s in ico_sizes],
        append_images=frames[:-1],
    )

    master.save(os.path.join(RES, "porydaw.icns"), format="ICNS")

    for name in ("porydaw.ico", "porydaw.icns"):
        im = Image.open(os.path.join(RES, name))
        print(name, "->", sorted(im.info.get("sizes", [im.size])))
    print("regenerated icon assets in", os.path.normpath(RES))


if __name__ == "__main__":
    main()
