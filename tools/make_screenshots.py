#!/usr/bin/env python3
"""Render Turnstile AI's App Store screenshots from the app's screen designs.

There is no Mac or simulator in this loop, so each screen is drawn with Pillow
to the same layout as the SwiftUI views: the dark board, raised slabs, bright
tiles, accepted and rejected lanes, the 3x3 tile picker and the score ring.
Each image is a full-bleed dark poster: a frameless screen with a soft glow
and a large caption underneath.

    appstore/iphone-6.7/01..05_*.png   1290x2796  (APP_IPHONE_67)
    appstore/ipad-13/01..05_*.png      2048x2732  (APP_IPAD_PRO_3GEN_129)

Every tile row below is labelled by the real rule engine for one machine
(rule: the first and third tiles are the same colour). If you edit the rows,
re-check them with engine/rules.py.

    python3 tools/make_screenshots.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "appstore")
FONT_DIR = "C:/Windows/Fonts"
FONTS = {"regular": "Inter-Regular.ttf", "medium": "Inter-Medium.ttf", "semibold": "Inter-SemiBold.ttf",
         "heavy": "Inter-SemiBold.ttf"}

# Mirrors Palette in Turnstile/Theme.swift.
C = {
    "ink": (11, 18, 21), "slate": (20, 29, 33), "slate_high": (30, 41, 46), "edge": (38, 47, 51),
    "text": (234, 242, 241), "muted": (143, 163, 166), "brand": (45, 212, 191),
    "pass": (52, 211, 153), "stop": (248, 113, 113), "gold": (250, 204, 21),
    "t_red": (239, 68, 68), "t_blue": (59, 130, 246), "t_yellow": (250, 204, 21),
}
SHAPES = ("circle", "square", "triangle")
TILE_COLOURS = ("t_red", "t_blue", "t_yellow")

# ----- the machine every screen shows (verified with engine/rules.py) -----
EXAMPLES = [([0, 3, 6], True), ([1, 4, 7], True), ([0, 4, 8], False), ([2, 4, 3], False)]
TRIED = [([0, 4, 6], True, "Not all one colour, so \u201call three the same\u201d is out."),
         ([4, 0, 6], False, "Last two match and it still rejects: it is the ends.")]
FINAL = [([0, 1, 6], True), ([4, 4, 8], False), ([2, 3, 5], True), ([7, 2, 3], None)]
RULE_TEXT = "The first and third tiles are the same colour."
NOTE = "Every accepted row is all one colour, so the natural guess is \u2018all three the same\u2019."
GPT_TRIED = [([3, 1, 0], True, "Ends both red but not all one colour."),
             ([2, 8, 0], False, "First two match, ends do not: the ends decide.")]
GPT_CALLS = (True, True, False, True)


_fonts = {}


def font(weight, px):
    key = (weight, int(px))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(os.path.join(FONT_DIR, FONTS[weight]), int(px))
    return _fonts[key]


def wrap(text, f, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if f.getlength(trial) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


class Screen:
    """A device screen drawn in points; s = pixels per point."""

    def __init__(self, w_px, h_px, s, margin):
        self.im = Image.new("RGB", (w_px, h_px), C["ink"])
        self.d = ImageDraw.Draw(self.im)
        self.s = s
        self.W, self.H = w_px / s, h_px / s
        self.m = margin

    def p(self, v):
        return round(v * self.s)

    def text(self, x, y, t, weight="regular", size=16, color=None, anchor="la", max_w=None, lh=1.28):
        f = font(weight, size * self.s)
        lines = wrap(t, f, max_w * self.s) if max_w else [t]
        for i, line in enumerate(lines):
            self.d.text((self.p(x), self.p(y + i * size * lh)), line, font=f, fill=color or C["text"], anchor=anchor)
        return y + len(lines) * size * lh

    def text_h(self, t, weight, size, max_w, lh=1.28):
        return len(wrap(t, font(weight, size * self.s), max_w * self.s)) * size * lh

    def width(self, t, weight, size):
        return font(weight, size * self.s).getlength(t) / self.s

    def rrect(self, x, y, w, h, r, fill=None, outline=None, width=1.0):
        self.d.rounded_rectangle((self.p(x), self.p(y), self.p(x + w), self.p(y + h)), self.p(r),
                                 fill=fill, outline=outline, width=max(1, self.p(width)) if outline else 0)

    def slab(self, y, h):
        x, w = self.m, self.W - 2 * self.m
        self.rrect(x, y, w, h, 22, fill=C["slate"], outline=C["edge"], width=1)
        return x, y, w

    def circle(self, cx, cy, r, fill=None, outline=None, width=1.5):
        self.d.ellipse((self.p(cx - r), self.p(cy - r), self.p(cx + r), self.p(cy + r)),
                       fill=fill, outline=outline, width=max(1, self.p(width)) if outline else 0)

    def line(self, x1, y1, x2, y2, color, width=1.0):
        self.d.line((self.p(x1), self.p(y1), self.p(x2), self.p(y2)), fill=color, width=max(1, self.p(width)))

    def eyebrow(self, x, y, t, color=None):
        f = font("semibold", 11 * self.s)
        cx = x
        for ch in t.upper():
            self.d.text((self.p(cx), self.p(y)), ch, font=f, fill=color or C["muted"])
            cx += f.getlength(ch) / self.s + 1.1
        return y + 18

    # ----- pieces -----

    def tile(self, x, y, size, t):
        self.rrect(x, y, size, size, size * 0.26, fill=C["slate_high"])
        col = C[TILE_COLOURS[t % 3]]
        pad = size * 0.2
        x0, y0, x1, y1 = x + pad, y + pad, x + size - pad, y + size - pad
        shape = SHAPES[t // 3]
        if shape == "circle":
            self.d.ellipse((self.p(x0), self.p(y0), self.p(x1), self.p(y1)), fill=col)
        elif shape == "square":
            self.rrect(x0, y0, x1 - x0, y1 - y0, size * 0.06, fill=col)
        else:
            self.d.polygon([(self.p((x0 + x1) / 2), self.p(y0)), (self.p(x1), self.p(y1)), (self.p(x0), self.p(y1))], fill=col)

    def strip(self, x, y, row, size=34):
        gap = size * 0.14
        for i, t in enumerate(row):
            self.tile(x + i * (size + gap), y, size, t)
        return x + 3 * size + 2 * gap

    def mark(self, x, y, accepted, size=24):
        col = C["pass"] if accepted else C["stop"]
        cx, cy, r = x + size / 2, y + size / 2, size / 2
        tint = tuple(round(C["slate"][i] + (col[i] - C["slate"][i]) * 0.22) for i in range(3))
        self.circle(cx, cy, r, fill=tint)
        w = size * 0.11
        if accepted:
            self.line(cx - r * 0.42, cy + r * 0.02, cx - r * 0.1, cy + r * 0.34, col, w)
            self.line(cx - r * 0.1, cy + r * 0.34, cx + r * 0.46, cy - r * 0.34, col, w)
        else:
            self.line(cx - r * 0.34, cy - r * 0.34, cx + r * 0.34, cy + r * 0.34, col, w)
            self.line(cx + r * 0.34, cy - r * 0.34, cx - r * 0.34, cy + r * 0.34, col, w)

    def ai_tag(self, x, y):
        w = self.width("AI", "semibold", 10) + 10
        self.rrect(x, y, w, 16, 4, fill=C["brand"])
        self.text(x + w / 2, y + 2, "AI", "semibold", 10, C["ink"], anchor="ma")
        return x + w

    def bright_button(self, y, label, dim=False):
        x, w = self.m + 18, self.W - 2 * self.m - 36
        col = C["brand"] if not dim else tuple(round(C["slate_high"][i] + (C["brand"][i] - C["slate_high"][i]) * 0.45) for i in range(3))
        self.rrect(x, y, w, 50, 25, fill=col)
        self.text(x + w / 2, y + 16, label, "semibold", 16, C["ink"], anchor="ma")

    def ring(self, cx, cy, diameter, score, out_of):
        r = diameter / 2
        for k in range(out_of):
            start = -90 + 360 * (k / out_of) + 3
            end = -90 + 360 * ((k + 1) / out_of) - 3
            col = C["brand"] if k < score else C["slate_high"]
            self.d.arc((self.p(cx - r), self.p(cy - r), self.p(cx + r), self.p(cy + r)), start, end,
                       fill=col, width=self.p(diameter * 0.09))
        self.text(cx, cy - diameter * 0.26, str(score), "semibold", diameter * 0.34, C["text"], anchor="ma")
        self.text(cx, cy + diameter * 0.14, f"of {out_of}", "semibold", 11, C["muted"], anchor="ma")

    # ----- chrome -----

    def status_bar(self):
        self.text(self.m + 12, 16, "9:41", "semibold", 16, C["text"])
        x = self.W - self.m - 12
        self.rrect(x - 26, 17, 24, 12, 3, outline=C["text"], width=1.2)
        self.rrect(x - 24, 19, 19, 8, 1.5, fill=C["text"])

    def top_bar(self, title, back=False, icons=True):
        y = 50
        if back:
            self.line(self.m + 14, y + 6, self.m + 6, y + 13, C["brand"], 2.2)
            self.line(self.m + 6, y + 13, self.m + 14, y + 20, C["brand"], 2.2)
            self.text(self.W / 2, y + 4, title, "semibold", 17, C["text"], anchor="ma")
        else:
            self.text(self.m + 2, y, title, "semibold", 20, C["text"])
        if icons:
            ix = self.W - self.m - 10
            for k in range(3):
                self.line(ix - 16, y + 7 + k * 6, ix, y + 7 + k * 6, C["brand"], 2)
            self.text(ix - 40, y, "?", "semibold", 19, C["brand"])
        return y + 42


# ----- screens -----

def lanes_card(sc, y, size=34, show_intro=True):
    x, _, w = sc.m, y, sc.W - 2 * sc.m
    intro = "This machine follows a secret rule. Here is what it did with 4 rows."
    ih = sc.text_h(intro, "regular", 13, w - 36) if show_intro else 0
    rows_h = 2 * (size + 10)
    h = 18 + ih + (14 if show_intro else 0) + 22 + rows_h + 10
    sc.slab(y, h)
    ry = y + 18
    if show_intro:
        ry = sc.text(x + 18, ry, intro, "regular", 13, C["muted"], max_w=w - 36) + 14
    half = (w - 36 - 14) / 2
    for li, (title, want, tint) in enumerate((("Accepted", True, C["pass"]), ("Rejected", False, C["stop"]))):
        lx = x + 18 + li * (half + 14)
        sc.circle(lx + 4, ry + 6, 4, fill=tint)
        sc.eyebrow(lx + 14, ry, title)
        ty = ry + 22
        for seq, acc in EXAMPLES:
            if acc == want:
                sc.strip(lx, ty, seq, size)
                ty += size + 10
    return y + h + 14


def screen_home(sc):
    sc.status_bar()
    y = sc.top_bar("Turnstile")
    y = sc.text(sc.m + 2, y + 2, "Monday 14 September", "semibold", 29, C["text"]) + 4
    sc.text(sc.m + 2, y, "New machines in 9h 12m  \u00b7  184 people have played", "regular", 13, C["muted"])
    y += 30
    for k in range(3):
        sc.rrect(sc.m + 2 + k * 22, y + 5, 18, 6, 3, fill=C["brand"] if k == 0 else C["slate_high"])
    sc.text(sc.m + 80, y, "Today the rule checks one thing about the row, or the opposite of one thing.",
            "regular", 13, C["muted"], max_w=sc.W - 2 * sc.m - 82)
    y += 46

    machines = [("Claude Opus 5\u2019s machine", "Play", EXAMPLES, False),
                ("GPT-6\u2019s machine", "2 tries left", [([6, 2, 6], True), ([5, 5, 2], True), ([0, 0, 7], False), ([7, 7, 7], False)], False)]
    for title, status, rows, _ in machines:
        h = 150
        x, _, w = sc.slab(y, h)
        sc.text(x + 18, y + 18, title, "semibold", 18, C["text"])
        sc.ai_tag(x + 24 + sc.width(title, "semibold", 18), y + 21)
        sc.text(x + w - 34, y + 20, status, "semibold", 12, C["brand"], anchor="ra")
        sc.line(x + w - 22, y + 21, x + w - 17, y + 26, C["muted"], 1.8)
        sc.line(x + w - 17, y + 26, x + w - 22, y + 31, C["muted"], 1.8)
        half = (w - 36 - 16) / 2
        for li, (lt, want, tint) in enumerate((("Accepted", True, C["pass"]), ("Rejected", False, C["stop"]))):
            lx = x + 18 + li * (half + 16)
            sc.eyebrow(lx, y + 56, lt, tint)
            ty = y + 78
            for seq, acc in [r for r in rows if r[1] == want][:2]:
                sc.strip(lx, ty, seq, 24)
                ty += 32
        y += h + 14

    h = 128
    x, _, w = sc.slab(y, h)
    sc.ring(x + 18 + 48, y + h / 2, 96, 6, 8)
    sc.text(x + 138, y + 30, "Yesterday", "semibold", 18, C["text"])
    sc.text(x + 138, y + 56, "\u2605 1 rule named", "semibold", 14, C["gold"])
    sc.text(x + 138, y + 80, "Placed 12 of 171", "regular", 13, C["muted"])


def screen_try(sc):
    sc.status_bar()
    y = sc.top_bar("Claude Opus 5\u2019s machine", back=True, icons=False)
    y = lanes_card(sc, y + 4, size=28, show_intro=False)

    h = 30 + len(TRIED) * 62 + 14
    x, _, w = sc.slab(y, h)
    sc.eyebrow(x + 18, y + 16, "Rows you tried")
    ry = y + 40
    for i, (seq, acc, note) in enumerate(TRIED):
        sc.text(x + 18, ry + 6, str(i + 1), "semibold", 11, C["muted"])
        sc.strip(x + 34, ry, seq, 28)
        sc.mark(x + w - 46, ry + 2, acc, 28)
        sc.text(x + 34, ry + 34, note, "regular", 12, C["muted"], max_w=w - 100)
        ry += 62
    y += h + 14

    h = 384
    x, _, w = sc.slab(y, h)
    sc.text(x + 18, y + 18, "Try a row", "semibold", 18, C["text"])
    sc.text(x + w - 18, y + 22, "2 of 4 left", "semibold", 11, C["muted"], anchor="ra")
    sy = y + 54
    sc.tile(x + 18, sy, 52, 2)
    sc.tile(x + 80, sy, 52, 5)
    sc.rrect(x + 142, sy, 52, 52, 14, fill=C["slate_high"], outline=C["brand"], width=2.4)
    gy = sy + 66
    cell = (w - 36 - 20) / 3
    for shape in range(3):
        for colour in range(3):
            t = shape * 3 + colour
            sc.tile(x + 18 + colour * (cell + 10) + (cell - 40) / 2, gy + shape * 46, 40, t)
    ny = gy + 3 * 46 + 6
    sc.rrect(x + 18, ny, w - 36, 40, 14, fill=C["slate_high"])
    sc.text(x + 46, ny + 12, "If the ends must match, yellow is accepted.", "regular", 13, C["muted"])
    sc.bright_button(ny + 54, "Ask the machine")


def screen_final(sc):
    sc.status_bar()
    y = sc.top_bar("Claude Opus 5\u2019s machine", back=True, icons=False)
    y = lanes_card(sc, y + 4, size=28, show_intro=False)

    h = 116 + len(FINAL) * 92 + 44
    x, _, w = sc.slab(y, h)
    sc.text(x + 18, y + 18, "The final four", "semibold", 20, C["text"])
    sc.text(x + 18, y + 48, "Which of these rows does the machine accept? Exactly two of them.", "regular", 13, C["muted"], max_w=w - 36)
    ry = y + 98
    pill_w = (w - 36 - 10) / 2
    for seq, pick in FINAL:
        sc.strip(x + 18, ry, seq, 40)
        by = ry + 48
        for k, (label, tint) in enumerate((("Accept", C["pass"]), ("Reject", C["stop"]))):
            chosen = (pick is True and k == 0) or (pick is False and k == 1)
            px = x + 18 + k * (pill_w + 10)
            sc.rrect(px, by, pill_w, 34, 12, fill=tint if chosen else C["slate_high"])
            sc.text(px + pill_w / 2, by + 9, label, "semibold", 14, C["ink"] if chosen else C["text"], anchor="ma")
        ry += 92
    sc.bright_button(ry + 4, "Lock in my answers", dim=True)


def screen_verdict(sc):
    sc.status_bar()
    y = sc.top_bar("Claude Opus 5\u2019s machine", back=True, icons=False)

    h = 140
    x, _, w = sc.slab(y + 4, h)
    sc.ring(x + w / 2, y + 4 + h / 2, 112, 4, 4)
    y += 4 + h + 14

    rule_h = sc.text_h(RULE_TEXT, "semibold", 22, w - 36, lh=1.2)
    note_h = sc.text_h(NOTE, "regular", 14, w - 36 - 18)
    h = 18 + 18 + rule_h + 16 + 18 + note_h + 18
    sc.slab(y, h)
    ry = sc.eyebrow(x + 18, y + 18, "The secret rule")
    ry = sc.text(x + 18, ry + 2, RULE_TEXT, "semibold", 22, C["text"], max_w=w - 36, lh=1.2) + 14
    sc.rrect(x + 18, ry, 3, 20 + note_h, 1.5, fill=C["brand"])
    sc.text(x + 30, ry, "Claude Opus 5", "semibold", 11, C["muted"])
    sc.ai_tag(x + 36 + sc.width("Claude Opus 5", "semibold", 11), ry - 1)
    sc.text(x + 30, ry + 20, NOTE, "regular", 14, (210, 220, 219), max_w=w - 36 - 18)
    y += h + 14

    h = 150
    sc.slab(y, h)
    sc.eyebrow(x + 18, y + 18, "How everyone did")
    figs = [("184", "played it"), ("52%", "got all four"), ("2.9", "average out of 4"), ("31%", "named the rule")]
    for k, (v, cap) in enumerate(figs):
        fx = x + 18 + (k % 2) * ((w - 36) / 2)
        fy = y + 46 + (k // 2) * 50
        sc.text(fx, fy, v, "semibold", 22, C["text"])
        sc.text(fx, fy + 28, cap, "regular", 12, C["muted"])
    y += h + 14

    h = 58 + len(GPT_TRIED) * 58 + 40
    sc.slab(y, h)
    sc.text(x + 18, y + 18, "GPT-6", "semibold", 18, C["text"])
    sc.ai_tag(x + 24 + sc.width("GPT-6", "semibold", 18), y + 21)
    sc.text(x + w - 18, y + 18, "3/4", "semibold", 18, C["text"], anchor="ra")
    ry = y + 52
    for i, (seq, acc, note) in enumerate(GPT_TRIED):
        sc.strip(x + 18, ry, seq, 26)
        sc.mark(x + w - 44, ry, acc, 26)
        sc.text(x + 18, ry + 32, note, "regular", 12, C["muted"], max_w=w - 80)
        ry += 58
    sc.text(x + 18, ry + 6, "Its calls", "regular", 12, C["muted"])
    mx = x + 18 + sc.width("Its calls", "regular", 12) + 10
    for k, right in enumerate(GPT_CALLS):
        sc.mark(mx + k * 26, ry + 2, right, 20)


def screen_standings(sc):
    sc.status_bar()
    y = sc.top_bar("Standings", back=True, icons=False)
    x, w = sc.m, sc.W - 2 * sc.m
    sc.rrect(x, y + 4, w, 34, 10, fill=C["slate"])
    seg = w / 3
    sc.rrect(x + 2, y + 6, seg - 2, 30, 9, fill=C["slate_high"])
    for k, label in enumerate(("Today", "30 days", "AI builders")):
        sc.text(x + seg * (k + 0.5), y + 13, label, "semibold" if k == 0 else "regular", 13,
                C["text"] if k == 0 else C["muted"], anchor="ma")
    y += 54

    rows = [(1, "GPT-6", True, 8, 2), (2, "Claude Opus 5", True, 8, 2), (3, "tilemaster", False, 8, 1),
            (4, "Rowan", False, 7, 1), (5, "Claude Sonnet 5", True, 7, 0), (6, "quietfox", False, 6, 1),
            (7, "Mara K", False, 6, 0), (8, "Claude Haiku 4.5", True, 5, 0), (9, "Player 3f1c", False, 4, 0)]
    h = 16 + len(rows) * 46 + 44
    sc.slab(y, h)
    ry = y + 16
    for rank, name, ai, score, stars in rows:
        sc.text(x + 18, ry + 12, str(rank), "semibold", 14, C["muted"])
        sc.text(x + 52, ry + 12, name, "regular", 15, C["text"])
        if ai:
            sc.ai_tag(x + 58 + sc.width(name, "regular", 15), ry + 14)
        if stars:
            sc.text(x + w - 60, ry + 12, "\u2605" * stars, "regular", 13, C["gold"], anchor="ra")
        sc.text(x + w - 18, ry + 12, str(score), "semibold", 15, C["text"], anchor="ra")
        sc.line(x + 18, ry + 44, x + w - 18, ry + 44, C["edge"], 0.8)
        ry += 46
    sc.text(x + 18, ry + 10, "Press and hold a name to report it or hide that player.", "regular", 12, C["muted"])


SCREENS = [
    ("01_home", screen_home, "Two machines a day.\nWork out each secret rule."),
    ("02_try", screen_try, "Try up to four rows\nof your own."),
    ("03_final", screen_final, "Then call four rows\nyou have never seen."),
    ("04_verdict", screen_verdict, "See the rule, the trap,\nand how the other AI did."),
    ("05_standings", screen_standings, "Claude and GPT build them.\nYou crack them."),
]


def poster(shot, caption, size, cap_px, screen_frac, radius_frac):
    """Dark poster: glow, frameless rounded screen high up, big caption below."""
    W, H = size
    canvas = Image.new("RGB", size, C["ink"])
    glow = Image.new("RGB", size, C["ink"])
    gd = ImageDraw.Draw(glow)
    gd.ellipse((W * 0.1, H * 0.12, W * 0.9, H * 0.7), fill=(18, 64, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=W * 0.12))
    canvas.paste(glow)
    dw = int(W * screen_frac)
    dh = int(shot.height * dw / shot.width)
    top = int(H * 0.045)
    max_h = int(H * 0.775)
    if dh > max_h:                      # crop the bottom of a tall screen rather than shrink it
        crop_px = int(max_h * shot.width / dw)
        shot = shot.crop((0, 0, shot.width, crop_px))
        dh = max_h
    shot = shot.resize((dw, dh), Image.LANCZOS)
    x = (W - dw) // 2
    r = int(dw * radius_frac)
    mask = Image.new("L", (dw, dh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, dw - 1, dh - 1), r, fill=255)
    rim = Image.new("RGB", (dw + 6, dh + 6), C["edge"])
    rim_mask = Image.new("L", (dw + 6, dh + 6), 0)
    ImageDraw.Draw(rim_mask).rounded_rectangle((0, 0, dw + 5, dh + 5), r + 3, fill=255)
    canvas.paste(rim, (x - 3, top - 3), rim_mask)
    canvas.paste(shot, (x, top), mask)
    d = ImageDraw.Draw(canvas)
    f = font("semibold", cap_px)
    y = top + dh + int(H * 0.035)
    for line in caption.split("\n"):
        d.text((W / 2, y), line, font=f, fill=C["text"], anchor="ma")
        y += int(cap_px * 1.2)
    # a small row of the game's tiles as a signature under the caption
    t = int(cap_px * 0.55)
    sx = W / 2 - (3 * t + 2 * t * 0.3) / 2
    for i, tile in enumerate((0, 4, 8)):
        tx = int(sx + i * t * 1.3)
        ty = int(y + cap_px * 0.35)
        d.rounded_rectangle((tx, ty, tx + t, ty + t), int(t * 0.26), fill=C["slate_high"])
        col = C[TILE_COLOURS[tile % 3]]
        pad = int(t * 0.2)
        if i == 0:
            d.ellipse((tx + pad, ty + pad, tx + t - pad, ty + t - pad), fill=col)
        elif i == 1:
            d.rounded_rectangle((tx + pad, ty + pad, tx + t - pad, ty + t - pad), 2, fill=col)
        else:
            d.polygon([(tx + t // 2, ty + pad), (tx + t - pad, ty + t - pad), (tx + pad, ty + t - pad)], fill=col)
    return canvas


def main():
    targets = {
        # folder: (canvas size, px per pt, margin pt, caption px, screen width fraction, corner fraction)
        "iphone-6.7": ((1290, 2796), 3.0, 16, 78, 0.82, 0.09),
        "ipad-13": ((2048, 2732), 2.6, 20, 92, 0.66, 0.05),
    }
    for folder, (size, s, margin, cap_px, frac, radius) in targets.items():
        out = os.path.join(OUT, folder)
        os.makedirs(out, exist_ok=True)
        for old in os.listdir(out):
            if old.endswith(".png"):
                os.remove(os.path.join(out, old))
        for name, draw, caption in SCREENS:
            sc = Screen(size[0], size[1], s, margin)
            draw(sc)
            img = poster(sc.im, caption, size, cap_px, frac, radius)
            img.save(os.path.join(out, f"{name}.png"), optimize=True)
            print(f"{folder}/{name}.png {img.size}")


if __name__ == "__main__":
    main()
