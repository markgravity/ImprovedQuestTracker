"""Draws icons in the style of WoW Forever's radial menu icons (Character,
Bags, Talents...): painted shapes in a vertical colour gradient, a dark
outline, a glossy top, a darker bottom rim and a soft drop shadow, on a
clear background. Used by tools/make_*_icons.py; see the radial-icon skill.

    from radial_icon import Icon, GOLD, RED
    icon = Icon()
    m = icon.mask(); d = icon.draw(m)       # a shape layer (white = shape)
    icon.stroke(d, [(14, 76), (58, 28), (114, 76)], 10)
    icon.save("textures/ic_example.tga", [(m, GOLD)])

Coordinates are in final pixels of a 128 px icon (supersampled 4x for
smooth edges); layers are drawn in order, each with its own palette.
"""
import math
from PIL import Image, ImageChops, ImageDraw, ImageFilter

# Palettes: (top, middle, bottom) of the fill gradient
GOLD = ((255, 236, 150), (236, 170, 52), (176, 92, 18))
RED = ((255, 150, 120), (226, 52, 34), (140, 18, 12))
GREY = ((215, 212, 205), (150, 146, 138), (90, 86, 80))
STEEL = ((235, 240, 245), (150, 165, 180), (70, 80, 95))
GREEN = ((200, 255, 170), (90, 190, 60), (30, 100, 20))
BLUE = ((190, 225, 255), (70, 140, 230), (20, 60, 140))
LEATHER = ((235, 190, 120), (180, 120, 60), (110, 65, 25))
OUTLINE = (52, 26, 8, 255)


class Icon:
    def __init__(self, size=128, ss=4):
        self.size, self.ss = size, ss
        self.S = size * ss

    # Shapes ----------------------------------------------------------------
    def px(self, v):
        return int(v * self.ss)

    def mask(self):
        return Image.new("L", (self.S, self.S), 0)

    def draw(self, mask):
        return ImageDraw.Draw(mask)

    def stroke(self, d, pts, width):
        """A thick line through points, round ends."""
        px = self.px
        d.line([(px(x), px(y)) for x, y in pts], fill=255, width=px(width), joint="curve")
        for x, y in (pts[0], pts[-1]):
            r = px(width) / 2
            d.ellipse((px(x) - r, px(y) - r, px(x) + r, px(y) + r), fill=255)

    def arc(self, d, cx, cy, r, a0, a1, width):
        """A thick arc, angles in degrees (0 = right, 90 = down)."""
        pts = [(cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)))
               for a in range(a0, a1 + 1, 3)]
        self.stroke(d, pts, width)

    def circle(self, d, cx, cy, r, fill=255):
        px = self.px
        d.ellipse((px(cx - r), px(cy - r), px(cx + r), px(cy + r)), fill=fill)

    def polygon(self, d, pts, fill=255):
        d.polygon([(self.px(x), self.px(y)) for x, y in pts], fill=fill)

    def bar(self, d, x, y0, y1, w):
        """A rounded vertical bar."""
        px = self.px
        d.rounded_rectangle((px(x - w / 2), px(y0), px(x + w / 2), px(y1)), radius=px(w / 2), fill=255)

    def star(self, d, cx, cy, r_out, r_in, points, turn=-90, fill=255):
        """A star / jagged burst."""
        pts = []
        for i in range(points * 2):
            r = r_out if i % 2 == 0 else r_in
            a = math.radians(turn + i * 180 / points)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        self.polygon(d, pts, fill)

    def cut(self, mask, other):
        """mask minus other (a hole, a crack)."""
        return ImageChops.subtract(mask, other)

    # The painted look ------------------------------------------------------
    def gradient(self, colors):
        top, mid, bot = colors
        S = self.S
        g = Image.new("RGBA", (S, S))
        gd = ImageDraw.Draw(g)
        for y in range(S):
            t = y / (S - 1)
            a, b, u = (top, mid, t * 2) if t < 0.5 else (mid, bot, (t - 0.5) * 2)
            gd.line((0, y, S, y), fill=tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)) + (255,))
        return g

    def render(self, mask, colors):
        """Shadow, outline, gradient fill, gloss, rim."""
        px, S = self.px, self.S
        out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        shadow = mask.filter(ImageFilter.MaxFilter(px(2) * 2 + 1)).filter(ImageFilter.GaussianBlur(px(3)))
        shadow = ImageChops.offset(shadow, px(3), px(4)).point(lambda v: int(v * 0.65))
        out.paste((0, 0, 0, 255), (0, 0), shadow)
        outline = mask.filter(ImageFilter.MaxFilter(px(2.5) * 2 + 1))
        out.paste(OUTLINE, (0, 0), outline)
        out.paste(self.gradient(colors), (0, 0), mask)
        inner = mask.filter(ImageFilter.MinFilter(px(2) * 2 + 1))
        gloss = ImageChops.multiply(inner, ImageChops.offset(inner, 0, px(4)).point(lambda v: 255 - v))
        gloss = gloss.filter(ImageFilter.GaussianBlur(px(1.5))).point(lambda v: int(v * 0.85))
        out.paste((255, 250, 225, 255), (0, 0), gloss)
        rim = ImageChops.multiply(inner, ImageChops.offset(inner, 0, -px(3)).point(lambda v: 255 - v))
        out.paste((110, 50, 8, 255), (0, 0), rim.point(lambda v: int(v * 0.6)))
        return out

    def save(self, path, layers):
        """layers: [(mask, palette)], drawn in order; saved as TGA (or PNG)."""
        img = Image.new("RGBA", (self.S, self.S), (0, 0, 0, 0))
        for mask, colors in layers:
            img = Image.alpha_composite(img, self.render(mask, colors))
        img = img.resize((self.size, self.size), Image.LANCZOS)
        img.save(path)
        print("wrote", path)
        return img


def preview(paths, out, bg=(60, 30, 12, 255)):
    """A strip of icons on a dark brown backdrop, to check them."""
    imgs = [Image.open(p).convert("RGBA") for p in paths]
    w = sum(i.width for i in imgs)
    sheet = Image.new("RGBA", (w, max(i.height for i in imgs)), bg)
    x = 0
    for i in imgs:
        sheet.alpha_composite(i, (x, 0))
        x += i.width
    sheet.save(out)
    return out
