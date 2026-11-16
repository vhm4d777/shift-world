#!/usr/bin/env python3
"""Builds the itch.io cover image and upscaled screenshots.

Input: a folder of raw 480x272 captures made by tests/marketing_shots.gd.
Usage: python3 tools/make_store_assets.py <captures_dir>
"""
import os
import re
import sys

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "itch")


def load_glyphs():
    src = open(os.path.join(ROOT, "scripts", "pixel_font.gd"), encoding="utf-8").read()
    glyphs = {}
    for m in re.finditer(r'^\t"(.)": \[([^\]]*)\]', src, re.M):
        rows = re.findall(r'"([.#]+)"', m.group(2))
        if len(rows) == 7:
            glyphs[m.group(1)] = rows
    return glyphs


GLYPHS = load_glyphs()


def text_width(text, scale):
    w = 0
    for ch in text:
        w += (4 if ch == " " else len(GLYPHS[ch][0]) + 1)
    return (w - 1) * scale


def draw_text(img, text, x, y, scale, color):
    d = ImageDraw.Draw(img)
    for ch in text:
        if ch == " ":
            x += 4 * scale
            continue
        rows = GLYPHS[ch]
        for ry, row in enumerate(rows):
            for rx, c in enumerate(row):
                if c == "#":
                    d.rectangle([x + rx * scale, y + ry * scale, x + (rx + 1) * scale - 1, y + (ry + 1) * scale - 1], fill=color)
        x += (len(rows[0]) + 1) * scale


def logo(img, cx, y, scale):
    w = text_width("SHIFT", scale)
    x = cx - w // 2
    off = max(2, scale // 3)
    draw_text(img, "SHIFT", x - off, y, scale, (79, 195, 255, 235))
    draw_text(img, "SHIFT", x + off, y + scale // 4, scale, (255, 46, 85, 235))
    draw_text(img, "SHIFT", x, y, scale, (255, 255, 255, 255))
    s2 = max(2, scale // 2)
    w2 = text_width("WORLDS", s2)
    x2 = cx - w2 // 2
    y2 = y + 7 * scale + scale
    draw_text(img, "WORLDS", x2 + s2 // 2, y2 + s2 // 2, s2, (11, 4, 16, 255))
    for i, ch in enumerate("WORLDS"):
        col = (217, 228, 255, 255) if i < 3 else (255, 85, 119, 255)
        draw_text(img, ch, x2, y2, s2, col)
        x2 += (len(GLYPHS[ch][0]) + 1) * s2
    return y2 + 7 * s2


def split(light, dark, size):
    """Diagonal split: light world top-left, dark world bottom-right."""
    w, h = size
    out = Image.new("RGBA", size)
    mask = Image.new("L", size, 0)
    d = ImageDraw.Draw(mask)
    d.polygon([(0, 0), (int(w * 0.62), 0), (int(w * 0.38), h), (0, h)], fill=255)
    out.paste(dark, (0, 0))
    out.paste(light, (0, 0), mask)
    # seam glow
    d2 = ImageDraw.Draw(out)
    d2.line([(int(w * 0.62), 0), (int(w * 0.38), h)], fill=(255, 255, 255, 255), width=3)
    d2.line([(int(w * 0.62) + 3, 0), (int(w * 0.38) + 3, h)], fill=(255, 46, 85, 255), width=2)
    d2.line([(int(w * 0.62) - 3, 0), (int(w * 0.38) - 3, h)], fill=(79, 195, 255, 255), width=2)
    return out


def crop_scaled(im, scale, size, focus=(0.5, 0.5)):
    big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    w, h = size
    x = int((big.width - w) * focus[0])
    y = int((big.height - h) * focus[1])
    return big.crop((x, y, x + w, y + h))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "/tmp/marketing"
    os.makedirs(os.path.join(OUT, "screenshots"), exist_ok=True)
    shots = sorted(f for f in os.listdir(src) if f.endswith(".png") and "_cover" not in f)
    for f in shots:
        im = Image.open(os.path.join(src, f)).convert("RGB")
        im.resize((im.width * 4, im.height * 4), Image.NEAREST).crop((0, 4, 1920, 1084)).save(os.path.join(OUT, "screenshots", f))
    light = Image.open(os.path.join(src, "light_cover.png")).convert("RGBA")
    dark = Image.open(os.path.join(src, "dark_cover.png")).convert("RGBA")

    # Cover 630x500 (itch.io recommended size)
    size = (630, 500)
    cov = split(crop_scaled(light, 2, size, (0.45, 0.9)), crop_scaled(dark, 2, size, (0.45, 0.9)), size)
    shade = Image.new("RGBA", size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for y in range(230):
        sd.line([(0, y), (size[0], y)], fill=(8, 2, 14, int(190 * (1 - y / 230))))
    cov = Image.alpha_composite(cov, shade)
    end = logo(cov, size[0] // 2, 34, 13)
    tag = "A PUZZLE-PLATFORMER BETWEEN TWO WORLDS"
    draw_text(cov, tag, size[0] // 2 - text_width(tag, 2) // 2 + 2, end + 22, 2, (0, 0, 0, 200))
    draw_text(cov, tag, size[0] // 2 - text_width(tag, 2) // 2, end + 20, 2, (255, 243, 160, 255))
    cov.convert("RGB").save(os.path.join(OUT, "cover.png"))

    # Wide banner 1920x480 for the itch page header / GitHub social preview (1280x640)
    for name, bsize, sc in [("banner.png", (1920, 480), 4), ("social_preview.png", (1280, 640), 3)]:
        b = split(crop_scaled(light, sc, bsize, (0.5, 0.85)), crop_scaled(dark, sc, bsize, (0.5, 0.85)), bsize)
        shade = Image.new("RGBA", bsize, (8, 2, 14, 120))
        b = Image.alpha_composite(b, shade)
        logo(b, bsize[0] // 2, bsize[1] // 2 - 130 if sc == 4 else bsize[1] // 2 - 150, 18 if sc == 4 else 17)
        b.convert("RGB").save(os.path.join(OUT, name))
    print("cover, banner, social preview and %d screenshots written to %s" % (len(shots), OUT))


if __name__ == "__main__":
    main()
