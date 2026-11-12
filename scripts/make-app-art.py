#!/usr/bin/env python3
"""Draws the Armada Ports app's own Steam artwork (capsule, wide capsule, hero, logo, icon) into
app/art. Run it after changing the look; the images are committed.

    python3 scripts/make-app-art.py      # needs Pillow
"""
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'app')
OUT = os.path.join(ROOT, 'art')
FONT = os.path.join(ROOT, 'fonts', 'Outfit.ttf')
BG_TOP = (14, 22, 38)
BG_BOTTOM = (8, 10, 15)
COLORS = [(90, 169, 255), (140, 196, 255), (242, 244, 248)]


def font(size, weight=700):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except (OSError, AttributeError):
        pass
    return f


def background(w, h):
    img = Image.new('RGB', (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    glow = Image.new('L', (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.45, -h * 0.4, w * 1.3, h * 0.7), fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(min(w, h) * 0.18))
    tint = Image.new('RGB', (w, h), (40, 110, 210))
    return Image.composite(tint, img, glow)


def chevrons(d, x, y, width, stroke, gap):
    for i, c in enumerate(COLORS):
        top = y + i * gap
        d.line([(x, top), (x + width / 2, top + width * 0.29), (x + width, top)], fill=c, width=stroke,
               joint='curve')


def wordmark(img, x, y, size, center=False):
    d = ImageDraw.Draw(img)
    big = font(size, 800)
    small = font(int(size * 0.42), 500)
    w1 = d.textlength('ARMADA', font=big)
    w2 = d.textlength('PORTS', font=big)
    width = max(w1, w2)
    left = x - width / 2 if center else x
    d.text((left + (width - w1) / 2 if center else left, y), 'ARMADA', font=big, fill=(242, 244, 248))
    d.text((left + (width - w2) / 2 if center else left, y + size * 0.95), 'PORTS', font=big, fill=COLORS[0])
    tag = 'ARM64 games for ArmadaOS'
    wt = d.textlength(tag, font=small)
    d.text((x - wt / 2 if center else left, y + size * 2.15), tag, font=small, fill=(163, 171, 189))


def capsule(w, h):
    img = background(w, h)
    d = ImageDraw.Draw(img)
    size = int(w * 0.36)
    chevrons(d, w / 2 - size / 2, h * 0.2, size, max(8, w // 28), int(size * 0.3))
    wordmark(img, w / 2, h * 0.52, int(w * 0.15), center=True)
    return img


def wide(w, h):
    img = background(w, h)
    d = ImageDraw.Draw(img)
    size = int(h * 0.42)
    chevrons(d, w * 0.1, h * 0.3, size, max(8, h // 22), int(size * 0.3))
    wordmark(img, w * 0.1 + size * 1.35, h * 0.22, int(h * 0.18))
    return img


def hero(w, h):
    img = background(w, h)
    d = ImageDraw.Draw(img, 'RGBA')
    for i in range(14):
        x = w * 0.42 + i * w * 0.045
        d.line([(x, h), (x + h * 0.9, 0)], fill=(90, 169, 255, 14 + i * 2), width=3)
    size = int(h * 0.55)
    chevrons(d, w * 0.72, h * 0.2, size, max(10, h // 18), int(size * 0.3))
    return img


def logo(w, h):
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = int(h * 0.62)
    chevrons(d, 8, h * 0.12, size, max(8, h // 14), int(size * 0.3))
    f = font(int(h * 0.42), 800)
    x = size + h * 0.3
    d.text((x, h * 0.04), 'ARMADA', font=f, fill=(242, 244, 248))
    d.text((x, h * 0.48), 'PORTS', font=f, fill=COLORS[0])
    return img


def icon(s):
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=s // 4.5, fill=(14, 17, 24, 255))
    chevrons(d, s * 0.2, s * 0.27, s * 0.6, max(6, s // 11), int(s * 0.17))
    return img


os.makedirs(OUT, exist_ok=True)
capsule(600, 900).save(os.path.join(OUT, 'grid.png'))
wide(920, 430).save(os.path.join(OUT, 'wide.png'))
hero(1920, 620).save(os.path.join(OUT, 'hero.png'))
logo(1200, 300).save(os.path.join(OUT, 'logo.png'))
icon(256).save(os.path.join(OUT, 'icon.png'))
print('art written to', OUT)
