#!/usr/bin/env python3
"""Regenerates AppIcon.appiconset from ui/theme/Color.kt's palette.

The mark is the app: flight strips on a dark bay, each with its priority tab. Three of them,
because one reads as a bookmark and five turn to mush at 16pt.

Run from this directory:  python3 make_icon.py
"""

import json
import os

from PIL import Image, ImageDraw

BAY = (0x14, 0x17, 0x1C, 255)
SURFACE = (0x1C, 0x20, 0x27, 255)
PAPER = (0xF4, 0xEF, 0xE1, 255)
INK = (0x26, 0x22, 0x20, 255)
URGENT = (0xC0, 0x39, 0x2B, 255)
AMBER = (0xE0, 0xA6, 0x3A, 255)
NORMAL = (0x3D, 0x7A, 0x5C, 255)

MASTER = 1024
# macOS icons sit inside their canvas rather than bleeding to the edge.
INSET = 100
RADIUS = 185

# (size in points, scale) -> what Xcode expects in an appiconset.
VARIANTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2),
            (512, 1), (512, 2)]


def draw_master():
    image = Image.new("RGBA", (MASTER, MASTER), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    body = (INSET, INSET, MASTER - INSET, MASTER - INSET)
    draw.rounded_rectangle(body, radius=RADIUS, fill=BAY)
    # A hair of lift at the top, so the tile doesn't read as a flat black hole in the Dock.
    draw.rounded_rectangle((INSET, INSET, MASTER - INSET, INSET + 260), radius=RADIUS, fill=SURFACE)
    draw.rectangle((INSET, INSET + 200, MASTER - INSET, INSET + 260), fill=SURFACE)
    draw.rounded_rectangle(body, radius=RADIUS, outline=(0, 0, 0, 60), width=6)

    strip_left, strip_right = 180, 844
    tab_width, height, gap = 52, 160, 45
    total = 3 * height + 2 * gap
    top = INSET + (MASTER - 2 * INSET - total) // 2

    for index, tab in enumerate((URGENT, AMBER, NORMAL)):
        y = top + index * (height + gap)
        draw.rounded_rectangle((strip_left, y, strip_right, y + height), radius=14, fill=PAPER)
        # The priority tab: square against the paper, rounded on the outer edge only.
        draw.rounded_rectangle((strip_left, y, strip_left + tab_width + 14, y + height),
                               radius=14, fill=tab)
        draw.rectangle((strip_left + tab_width, y, strip_left + tab_width + 14, y + height),
                       fill=PAPER)
        # Two ink bars standing in for the title and its detail line.
        text_left = strip_left + tab_width + 44
        draw.rounded_rectangle((text_left, y + 42, text_left + 380, y + 72), radius=15, fill=INK)
        draw.rounded_rectangle((text_left, y + 92, text_left + 210, y + 114), radius=11,
                               fill=(*INK[:3], 110))
    return image


def main():
    master = draw_master()
    here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AppIcon.appiconset")
    os.makedirs(here, exist_ok=True)

    images = []
    for points, scale in VARIANTS:
        pixels = points * scale
        name = "icon_{0}x{0}{1}.png".format(points, "@2x" if scale == 2 else "")
        master.resize((pixels, pixels), Image.LANCZOS).save(os.path.join(here, name))
        images.append({
            "idiom": "mac",
            "size": "{0}x{0}".format(points),
            "scale": "{}x".format(scale),
            "filename": name,
        })
        print("wrote {} ({}px)".format(name, pixels))

    with open(os.path.join(here, "Contents.json"), "w") as out:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, out, indent=2)
    with open(os.path.join(os.path.dirname(here), "Contents.json"), "w") as out:
        json.dump({"info": {"version": 1, "author": "xcode"}}, out, indent=2)


if __name__ == "__main__":
    main()
