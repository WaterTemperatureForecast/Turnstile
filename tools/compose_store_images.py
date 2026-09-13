#!/usr/bin/env python3
"""Turn phone captures into captioned App Store sets for iPhone 6.5" and iPad 13".

    python compose_store_images.py <captures_dir> <out_dir> [--captions captions.txt] [--bg 14,30,52]

captures_dir: PNG/JPG screenshots straight from an iPhone (any size; sorted by name).
captions.txt: one caption per line, in the same order (use \\n for a line break);
              missing lines get no caption.
Writes <out_dir>/iphone-6.5/NN.png (1284x2778) and <out_dir>/ipad-13/NN.png (2048x2732),
each a caption over a bezelled screen, the style used for Tag Stream and Schelling.
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_screenshots import font  # noqa: E402


def compose(shot, caption, size, caption_px, device_frac, radius_frac, bg, fg):
    W, H = size
    canvas = Image.new("RGB", size, bg)
    d = ImageDraw.Draw(canvas)
    y = int(H * 0.05)
    if caption:
        f = font("semibold", caption_px)
        for line in caption.split("\\n"):
            d.text((W / 2, y), line, font=f, fill=fg, anchor="ma")
            y += int(caption_px * 1.22)
        y += int(H * 0.035)
    else:
        y = int(H * 0.06)
    dw = int(W * device_frac)
    scale = dw / shot.width
    dh = int(shot.height * scale)
    shot = shot.resize((dw, dh), Image.LANCZOS)
    r = int(dw * radius_frac)
    bezel = max(8, int(dw * 0.014))
    x = (W - dw) // 2
    d.rounded_rectangle((x - bezel, y - bezel, x + dw + bezel, y + dh + bezel), r + bezel, fill=(20, 20, 24))
    mask = Image.new("L", (dw, dh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, dw - 1, dh - 1), r, fill=255)
    canvas.paste(shot, (x, y), mask)
    return canvas


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("captures")
    ap.add_argument("out")
    ap.add_argument("--captions")
    ap.add_argument("--bg", default="14,30,52", help="background RGB")
    ap.add_argument("--fg", default="240,244,248", help="caption RGB")
    a = ap.parse_args()
    bg = tuple(int(v) for v in a.bg.split(","))
    fg = tuple(int(v) for v in a.fg.split(","))
    files = sorted(f for f in os.listdir(a.captures) if f.lower().endswith((".png", ".jpg", ".jpeg")))[:10]
    if not files:
        raise SystemExit("no captures found")
    captions = []
    if a.captions:
        captions = [l.rstrip("\n") for l in open(a.captions, encoding="utf-8")]
    targets = {"iphone-6.5": ((1284, 2778), 64, 0.84, 0.115), "ipad-13": ((2048, 2732), 76, 0.62, 0.10)}
    for folder, (size, cap_px, dev_frac, r_frac) in targets.items():
        out = os.path.join(a.out, folder)
        os.makedirs(out, exist_ok=True)
        for i, f in enumerate(files, 1):
            shot = Image.open(os.path.join(a.captures, f)).convert("RGB")
            cap = captions[i - 1] if i - 1 < len(captions) else ""
            compose(shot, cap, size, cap_px, dev_frac, r_frac, bg, fg).save(os.path.join(out, f"{i:02d}.png"), optimize=True)
            print(f"{folder}/{i:02d}.png  <- {f}")


if __name__ == "__main__":
    main()
