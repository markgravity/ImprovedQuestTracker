"""The addon's icon (## IconTexture, the AddOns list) and CurseForge logo,
in Improved Controller's line style: a quest list (cream) with green sort
arrows.

Writes textures/ic_addon.tga (128 x 128) and tools/addon_logo.png (400 x 400,
on the logo's dark grey).

Run: python3 tools/make_addon_icon.py   (needs Pillow)
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from radial_icon import GOLD, GREEN, Icon  # noqa: E402
from line_icon import render  # noqa: E402

HERE = os.path.dirname(__file__)
TGA = os.path.join(HERE, "..", "textures", "ic_addon.tga")
LOGO = os.path.join(HERE, "addon_logo.png")
LOGO_BG = (71, 71, 71, 255)


def layers(ss):
    icon = Icon(ss=ss)

    # The tracker: a page with three quest rows (marker + line)
    page = icon.mask()
    d = icon.draw(page)
    d.rounded_rectangle((icon.px(10), icon.px(16), icon.px(78), icon.px(112)), radius=icon.px(12), fill=255)

    rows = icon.mask()
    d = icon.draw(rows)
    for y in (42, 64, 86):
        icon.circle(d, 25, y, 3.5)
        icon.stroke(d, [(41, y), (63, y)], 5)

    # Sort arrows, thin enough to stay lines (a join thicker than the
    # outline width would turn hollow): up, then down
    arrows = icon.mask()
    d = icon.draw(arrows)
    icon.stroke(d, [(94, 100), (94, 34)], 5)
    icon.stroke(d, [(87, 33), (94, 26)], 4.5)
    icon.stroke(d, [(94, 26), (101, 33)], 4.5)
    icon.stroke(d, [(112, 28), (112, 94)], 5)
    icon.stroke(d, [(105, 95), (112, 102)], 4.5)
    icon.stroke(d, [(112, 102), (119, 95)], 4.5)

    return [(page, GOLD), (rows, GOLD), (arrows, GREEN)]


if __name__ == "__main__":
    render(TGA, layers(4))

    tmp = LOGO + ".icon.png"
    render(tmp, layers(16), ss=16, out_size=320)
    logo = Image.new("RGBA", (400, 400), LOGO_BG)
    logo.alpha_composite(Image.open(tmp).convert("RGBA"), (40, 40))
    logo.convert("RGB").save(LOGO)
    os.remove(tmp)
    print("wrote", LOGO)
