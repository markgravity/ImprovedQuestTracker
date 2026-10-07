"""Icons in the addon logo's style (tools/addon_logo.png): shapes drawn as
cream outlines (a filled shape becomes its outline, a thin stroke stays a
line), accents in green, a soft dark shadow so they read on any background,
a gap where a shape in front crosses one behind (as the logo's infinity).

Shapes come as radial_icon.Icon masks (white = shape), so its drawing
helpers make them; render() turns a list of (mask, palette) layers, back
to front, into the icon. Palettes: radial_icon's RED, GREEN and BLUE are
accents (green), the others the main colour (cream).
"""
from PIL import Image, ImageChops, ImageFilter

from radial_icon import BLUE, GREEN, RED

CREAM = (255, 255, 192)
ACCENT = (124, 204, 140)
LINE = 6.5          # outline width, final pixels at 128
GAP = 4.5           # around a shape in front


def _grow(mask, px, ss):
    """The mask grown by px (final pixels)"""
    r = max(1, int(px * ss))
    return mask.filter(ImageFilter.MaxFilter(r * 2 + 1)) if r <= 6 else \
        mask.filter(ImageFilter.GaussianBlur(r * 0.55)).point(lambda v: 255 if v > 24 else 0)


def _shrink(mask, px, ss):
    r = max(1, int(px * ss))
    return mask.filter(ImageFilter.MinFilter(r * 2 + 1)) if r <= 6 else \
        mask.filter(ImageFilter.GaussianBlur(r * 0.55)).point(lambda v: 255 if v > 231 else 0)


def _outline(mask, ss):
    """A shape's outline, LINE wide on its edge; a shape thinner than that
    stays whole (a line)"""
    half = LINE / 2
    inner = _shrink(mask, half, ss)
    return ImageChops.subtract(_grow(mask, half, ss), inner)


def render(path, layers, size=128, ss=4, out_size=None):
    """out_size: save at another size (masks drawn at size * ss)"""
    S = size * ss
    lines = []
    for i, (mask, palette) in enumerate(layers):
        line = _outline(mask, ss)
        # Cut where shapes in front of it lie (and a gap round them)
        for front, _ in layers[i + 1:]:
            line = ImageChops.subtract(line, _grow(front, LINE / 2 + GAP, ss))
        accent = palette in (RED, GREEN, BLUE)
        lines.append((line, ACCENT if accent else CREAM))
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # A soft shadow under everything
    union = Image.new("L", (S, S), 0)
    for line, _ in lines:
        union = ImageChops.lighter(union, line)
    shadow = union.filter(ImageFilter.GaussianBlur(3 * ss)).point(lambda v: min(200, v * 2))
    out.paste((10, 10, 10, 255), (0, 0), shadow)
    for line, color in lines:
        out.paste(color + (255,), (0, 0), line)
    out_size = out_size or size
    out = out.resize((out_size, out_size), Image.LANCZOS)
    out.save(path)
    print("wrote", path)
