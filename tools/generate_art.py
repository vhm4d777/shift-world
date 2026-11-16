#!/usr/bin/env python3
"""Generates the pixel-art backgrounds and the application icon for SHIFT WORLDS.

Everything is drawn procedurally (no external art), CC0.
Usage:  python3 tools/generate_art.py
"""
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
ART = os.path.join(ROOT, "assets")
W, H = 480, 272

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def dither_gradient(img, stops, y0=0, y1=None, levels=10):
    """Vertical gradient quantised into bands with ordered dithering."""
    y1 = y1 or img.height
    px = img.load()
    for y in range(y0, y1):
        t = (y - y0) / max(1, (y1 - y0 - 1))
        for x in range(img.width):
            tq = t * levels + (BAYER[y % 4][x % 4] / 16.0 - 0.5)
            tq = min(max(round(tq) / levels, 0.0), 1.0)
            # find stop pair
            for i in range(len(stops) - 1):
                p0, c0 = stops[i]
                p1, c1 = stops[i + 1]
                if p0 <= tq <= p1:
                    px[x, y] = lerp(c0, c1, (tq - p0) / max(1e-6, p1 - p0))
                    break


def ridge(seed, base, amp, rough, width=W):
    r = random.Random(seed)
    pts = []
    phase = [r.uniform(0, 6.28) for _ in range(4)]
    for x in range(width):
        y = base
        y += math.sin(x * 0.012 + phase[0]) * amp
        y += math.sin(x * 0.031 + phase[1]) * amp * 0.5
        y += math.sin(x * 0.077 + phase[2]) * amp * 0.25 * rough
        y += math.sin(x * 0.19 + phase[3]) * amp * 0.12 * rough
        pts.append(int(y))
    return pts


def fill_below(img, heights, color, edge=None, edge_w=1):
    px = img.load()
    for x, hy in enumerate(heights):
        for y in range(max(0, hy), img.height):
            px[x, y] = color
        if edge is not None:
            for k in range(edge_w):
                if 0 <= hy + k < img.height:
                    px[x, hy + k] = edge


def disc(img, cx, cy, r, color):
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def dithered_glow(img, cx, cy, r0, r1, color, max_a=0.6):
    px = img.load()
    for y in range(max(0, cy - r1), min(img.height, cy + r1)):
        for x in range(max(0, cx - r1), min(img.width, cx + r1)):
            d = math.hypot(x - cx, y - cy)
            if r0 <= d < r1:
                t = 1 - (d - r0) / (r1 - r0)
                if t * max_a * 16 > BAYER[y % 4][x % 4] + 0.5:
                    base = px[x, y]
                    px[x, y] = lerp(base, color, 0.5)


def spires(img, seed, count, color, rim=None, ymin=120, ymax=200, wmin=6, wmax=16):
    r = random.Random(seed)
    d = ImageDraw.Draw(img)
    for _ in range(count):
        x = r.randint(-10, W + 10)
        top = r.randint(ymin, ymax)
        w = r.randint(wmin, wmax)
        poly = [(x - w // 2, H), (x - w // 4, top + w), (x, top), (x + w // 4, top + w), (x + w // 2, H)]
        d.polygon(poly, fill=color)
        if rim:
            d.line([(x, top), (x + w // 4, top + w), (x + w // 2, H)], fill=rim)


# ---------------------------------------------------------------- light world

def light_far():
    img = Image.new("RGBA", (W, H))
    dither_gradient(img, [(0, hexc("#5f8cf2")), (0.55, hexc("#a8b8ff")), (1.0, hexc("#efe2ff"))], levels=14)
    dithered_glow(img, 370, 58, 12, 70, hexc("#ffffff"), 0.75)
    disc(img, 370, 58, 13, hexc("#fffaf0"))
    disc(img, 370, 58, 10, hexc("#ffffff"))
    fill_below(img, ridge(3, 170, 22, 1.2), hexc("#b9b0f2"), hexc("#d9d3ff"))
    fill_below(img, ridge(7, 196, 16, 1.6), hexc("#9d92e4"), hexc("#bdb5f5"))
    # floating islands
    d = ImageDraw.Draw(img)
    for (x, y, w) in [(70, 70, 40), (190, 100, 26), (430, 120, 30)]:
        d.polygon([(x - w, y), (x + w, y), (x + w // 3, y + w // 2), (x, y + w), (x - w // 3, y + w // 2)], fill=hexc("#b4abef"))
        d.line([(x - w, y), (x + w, y)], fill=hexc("#ffffff"))
    return img


def light_mid():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    r = random.Random(11)
    d = ImageDraw.Draw(img)
    # soft cloud bands
    for _ in range(9):
        cx, cy = r.randint(0, W), r.randint(20, 150)
        for k in range(5):
            rx = r.randint(14, 30)
            ox = cx + k * 14 - 28
            d.ellipse([ox - rx, cy - rx // 3, ox + rx, cy + rx // 3], fill=hexc("#ffffff", 150))
    spires(img, 21, 14, hexc("#8a7fd8"), hexc("#e9e4ff"), 150, 215, 8, 18)
    fill_below(img, ridge(31, 238, 6, 2.0), hexc("#7a6ccc"), hexc("#a99ff0"))
    return img


# ---------------------------------------------------------------- dark world

def dark_far():
    img = Image.new("RGBA", (W, H))
    dither_gradient(img, [(0, hexc("#030007")), (0.6, hexc("#14041f")), (1.0, hexc("#2c0a3a"))], levels=12)
    px = img.load()
    r = random.Random(5)
    for _ in range(140):
        x, y = r.randint(0, W - 1), r.randint(0, 150)
        px[x, y] = hexc(r.choice(["#ffffff", "#ff8fa8", "#b38cff"]))
    dithered_glow(img, 110, 64, 18, 80, hexc("#ff2e55"), 0.55)
    disc(img, 110, 64, 19, hexc("#ff2e55"))
    disc(img, 110, 64, 16, hexc("#c3123f"))
    disc(img, 104, 58, 5, hexc("#e0284f"))
    disc(img, 118, 72, 3, hexc("#a10e35"))
    fill_below(img, ridge(13, 168, 26, 2.2), hexc("#1d0828"), hexc("#3e0b24"))
    fill_below(img, ridge(17, 200, 14, 2.6), hexc("#140519"), hexc("#5e1030"))
    return img


def dark_mid():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    spires(img, 41, 18, hexc("#0c0312"), hexc("#4c0d28"), 120, 210, 8, 22)
    fill_below(img, ridge(51, 236, 8, 2.5), hexc("#09020d"), hexc("#4c0d28"))
    return img


# ---------------------------------------------------------------- icon & cover

def icon(size=256):
    """Split-world emblem: a hooded traveller over a sun/moon disc."""
    s = 32
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], 6, fill=hexc("#120618"))
    # left half light, right half dark
    for y in range(1, s - 1):
        for x in range(1, s - 1):
            if img.getpixel((x, y))[3] == 0:
                continue
            light = x + (y - s / 2) * 0.35 < s / 2
            img.putpixel((x, y), hexc("#a9b8ff") if light else hexc("#1a0726"))
    d.ellipse([7, 6, 25, 24], fill=hexc("#ffffff"))
    for y in range(6, 25):
        for x in range(7, 26):
            p = img.getpixel((x, y))
            if p[:3] == (255, 255, 255) and not (x + (y - s / 2) * 0.35 < s / 2):
                img.putpixel((x, y), hexc("#ff2e55"))
    # traveller silhouette
    fig = [
        "....oooo....",
        "...occcco...",
        "..occcccco..",
        "..occfefeo..",
        "..occffffo..",
        "..osssssso..",
        "..ohccccco..",
        ".ohcccccco..",
        ".ohhcccccco.",
        ".ohhcccccco.",
        "..ohhcccco..",
        "...oo..oo...",
    ]
    cols = {"o": hexc("#0b0410"), "c": hexc("#f4f2ff"), "h": hexc("#c9c3f0"), "f": hexc("#2a1f4f"),
            "e": hexc("#7fe3ff"), "s": hexc("#ff2e55")}
    ox, oy = 10, 14
    for y, row in enumerate(fig):
        for x, ch in enumerate(row):
            if ch in cols:
                img.putpixel((ox + x, oy + y), cols[ch])
    d.rounded_rectangle([0, 0, s - 1, s - 1], 6, outline=hexc("#ff2e55"))
    return img.resize((size, size), Image.NEAREST)


def main():
    os.makedirs(ART, exist_ok=True)
    for name, fn in [("bg_light_far", light_far), ("bg_light_mid", light_mid),
                     ("bg_dark_far", dark_far), ("bg_dark_mid", dark_mid)]:
        fn().save(os.path.join(ART, name + ".png"))
        print("  " + name)
    ic = icon(256)
    ic.save(os.path.join(ART, "icon.png"))
    ic.save(os.path.join(ART, "icon.ico"), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print("  icon.png / icon.ico")


if __name__ == "__main__":
    main()
