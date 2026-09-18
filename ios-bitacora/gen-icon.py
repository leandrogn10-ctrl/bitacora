#!/usr/bin/env python3
"""Draws Assets.xcassets/AppIcon.appiconset/icon-1024.png — the app's mark, in the app's palette.

Cabaret Clásico at 60pt on a home screen: a wine ground, a gold italic B, one magenta neon
bloom, the paper's double rule. Nothing more survives that size.
Regenerate: python3 ios-bitacora/gen-icon.py"""
import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
S = 1024
BG, PAPER = (0x16, 0x08, 0x10), (0x2c, 0x12, 0x1c)      # --bg, --paper
GOLD, MAGENTA, SPILL = (0xf5, 0xc8, 0x60), (0xff, 0x3d, 0x8a), (0x6b, 0x16, 0x3c)


def ground():
    """Wine, lifting toward the paper tone at the foot — depth, not a flat swatch."""
    img = Image.new('RGB', (S, S), BG)
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = (y / S) ** 1.4
        d.line([(0, y), (S, y)],
               fill=tuple(int(BG[i] + (PAPER[i] - BG[i]) * t * 0.85) for i in range(3)))
    return img


def neon():
    """One magenta bloom, low and left: the cabaret sign just outside the frame."""
    g = Image.new('RGB', (S, S), (0, 0, 0))
    ImageDraw.Draw(g).ellipse([-S * 0.30, S * 0.52, S * 0.72, S * 1.30], fill=(62, 11, 31))
    return g.filter(ImageFilter.GaussianBlur(S * 0.13))


img = ImageChops.add(ground(), neon())                   # additive: the glow lights the ground
d = ImageDraw.Draw(img)

f = ImageFont.truetype(os.path.join(HERE, 'Fonts', 'InstrumentSerif-Italic.ttf'), 660)
box = d.textbbox((0, 0), 'B', font=f)
x = (S - (box[2] - box[0])) / 2 - box[0]
y = (S - (box[3] - box[1])) / 2 - box[1] - S * 0.045

d.text((x - 9, y + 7), 'B', font=f, fill=SPILL)          # neon spill, not a drop shadow
d.text((x, y), 'B', font=f, fill=GOLD)

ry = int(S * 0.845)                                      # the paper's double rule
d.line([(S * 0.30, ry), (S * 0.70, ry)], fill=GOLD, width=8)
d.line([(S * 0.34, ry + 22), (S * 0.66, ry + 22)], fill=MAGENTA, width=5)

out = os.path.join(HERE, 'Assets.xcassets', 'AppIcon.appiconset', 'icon-1024.png')
os.makedirs(os.path.dirname(out), exist_ok=True)
img.save(out, 'PNG')
print('wrote', out, img.size)
