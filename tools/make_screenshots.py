#!/usr/bin/env python3
"""Render App Store screenshots for Turnstile from the screen designs.

No Mac and no simulator in this loop, so the five store screenshots are drawn
with Pillow to the same layout as the SwiftUI views (grouped background, cards,
tiles, verdict badges, tab bar). Each is a caption plus a bezelled device
screen, the usual App Store style. Outputs:

    appstore/iphone-6.7/01..05_*.png   1290x2796  (APP_IPHONE_67, required)
    appstore/ipad-13/01..05_*.png      2048x2732  (APP_IPAD_PRO_3GEN_129, required for iPad apps)

Replace with real captures from TestFlight whenever convenient; the upload
script (Downloads/setup_turnstile_asc.py) takes any folder. Fonts: Inter.

    python tools/make_screenshots.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "appstore")
FONT_DIR = "C:/Windows/Fonts"
FONTS = {"regular": "Inter-Regular.ttf", "medium": "Inter-Medium.ttf", "semibold": "Inter-SemiBold.ttf"}

C = {
    "bg": (242, 242, 247), "card": (255, 255, 255), "accent": (15, 118, 110), "text": (21, 32, 43),
    "secondary": (138, 138, 142), "fill": (229, 229, 234), "sep": (216, 216, 220), "white": (255, 255, 255),
    "green": (52, 152, 84), "red": (211, 47, 47), "bezel": (24, 30, 37), "tab_bg": (249, 249, 249),
    "page": (238, 243, 243), "gold": (214, 158, 12),
    "t_red": (220, 38, 38), "t_blue": (37, 99, 235), "t_yellow": (242, 184, 13),
}
SHAPES = ("circle", "square", "triangle")
COLOURS = ("t_red", "t_blue", "t_yellow")


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


_font_cache = {}


def font(weight, px):
    key = (weight, int(px))
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(os.path.join(FONT_DIR, FONTS[weight]), int(px))
    return _font_cache[key]


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


class UI:
    """A phone/tablet screen drawn in logical points; s = pixels per point."""

    def __init__(self, w_px, h_px, s, margin):
        self.im = Image.new("RGB", (w_px, h_px), C["bg"])
        self.d = ImageDraw.Draw(self.im)
        self.s = s
        self.W, self.H = w_px / s, h_px / s
        self.m = margin

    def p(self, v):
        return round(v * self.s)

    def text(self, x, y, t, weight="regular", size=17, color=None, anchor="la", max_w=None):
        f = font(weight, size * self.s)
        lines = wrap(t, f, max_w * self.s) if max_w is not None else [t]
        lh = size * 1.25
        for i, line in enumerate(lines):
            self.d.text((self.p(x), self.p(y + i * lh)), line, font=f, fill=color or C["text"], anchor=anchor)
        return y + len(lines) * lh

    def width(self, t, weight, size):
        return font(weight, size * self.s).getlength(t) / self.s

    def text_h(self, t, weight, size, max_w):
        """Height in points that text() will occupy, so cards can be sized first."""
        return len(wrap(t, font(weight, size * self.s), max_w * self.s)) * size * 1.25

    def rrect(self, x, y, w, h, r, fill, outline=None, width=1):
        self.d.rounded_rectangle((self.p(x), self.p(y), self.p(x + w), self.p(y + h)), self.p(r),
                                 fill=fill, outline=outline, width=self.p(width) if outline else 0)

    def card(self, y, h, x=None, w=None):
        x = self.m if x is None else x
        w = (self.W - 2 * self.m) if w is None else w
        self.rrect(x, y, w, h, 14, C["card"])
        return x, y, w

    def circle(self, cx, cy, r, fill, outline=None, width=1.5):
        self.d.ellipse((self.p(cx - r), self.p(cy - r), self.p(cx + r), self.p(cy + r)),
                       fill=fill, outline=outline, width=self.p(width) if outline else 0)

    def line(self, x1, y1, x2, y2, color, width=1):
        self.d.line((self.p(x1), self.p(y1), self.p(x2), self.p(y2)), fill=color, width=max(1, self.p(width)))

    def empty_slot(self, x, y, size, color):
        """The next (selected) tile slot in the experiment builder."""
        self.rrect(x, y, size, size, size * 0.22, None, outline=color, width=2.2)
        self.line(x + size * 0.34, y + size / 2, x + size * 0.66, y + size / 2, color, 2.2)
        self.line(x + size / 2, y + size * 0.34, x + size / 2, y + size * 0.66, color, 2.2)

    # ----- tiles -----

    def tile(self, x, y, size, t, bg=None):
        """One tile: shape-major id 0..8 (0 circle red ... 8 triangle yellow)."""
        self.rrect(x, y, size, size, size * 0.22, bg or C["fill"])
        col = C[COLOURS[t % 3]]
        pad = size * 0.2
        box = (x + pad, y + pad, x + size - pad, y + size - pad)
        shape = SHAPES[t // 3]
        if shape == "circle":
            self.d.ellipse((self.p(box[0]), self.p(box[1]), self.p(box[2]), self.p(box[3])), fill=col)
        elif shape == "square":
            self.rrect(box[0], box[1], box[2] - box[0], box[3] - box[1], size * 0.07, col)
        else:
            self.d.polygon([(self.p((box[0] + box[2]) / 2), self.p(box[1])),
                            (self.p(box[2]), self.p(box[3])), (self.p(box[0]), self.p(box[3]))], fill=col)

    def seq(self, x, y, tiles, size=40, gap=6):
        for i, t in enumerate(tiles):
            self.tile(x + i * (size + gap), y, size, t)
        return x + len(tiles) * (size + gap) - gap

    def verdict(self, x, y, accepted, label=True, size=17):
        col = C["green"] if accepted else C["red"]
        r = size * 0.55
        cy = y + size * 0.55
        self.circle(x + r, cy, r, col)
        if accepted:
            self.line(x + r * 0.6, cy, x + r * 0.92, cy + r * 0.42, C["white"], size * 0.11)
            self.line(x + r * 0.92, cy + r * 0.42, x + r * 1.45, cy - r * 0.45, C["white"], size * 0.11)
        else:
            for dx in (1, -1):
                self.line(x + r - r * 0.45 * dx, cy - r * 0.45, x + r + r * 0.45 * dx, cy + r * 0.45, C["white"], size * 0.11)
        if label:
            self.text(x + 2 * r + 6, y, "Accept" if accepted else "Reject", "semibold", size, col)
            return x + 2 * r + 6 + self.width("Accept", "semibold", size)
        return x + 2 * r

    # ----- chrome -----

    def status_bar(self):
        self.text(self.m + 12, 16, "9:41", "semibold", 16)
        x = self.W - self.m - 12
        self.rrect(x - 26, 17, 24, 12, 3, None, outline=C["text"], width=1.2)
        self.rrect(x - 24, 19, 19, 8, 1.5, C["text"])
        self.rrect(x - 1, 20.5, 2, 5, 1, C["text"])
        wx = x - 42
        for r, wdt in ((9, 1.8), (6, 1.8), (3, 1.8)):
            self.d.arc((self.p(wx - r), self.p(23 - r), self.p(wx + r), self.p(23 + r)), 225, 315, fill=C["text"], width=self.p(wdt))
        sx = wx - 30
        for i in range(4):
            self.rrect(sx + i * 6, 25 - i * 2.5 - 4, 4, 4 + i * 2.5, 1, C["text"])

    def nav_title(self, title, y=48):
        self.text(self.m, y, title, "semibold", 34)
        return y + 50

    def nav_inline(self, title, y=44):
        """Inline (small) navigation title with a back chevron."""
        self.line(self.m + 14, y + 10, self.m + 7, y + 16, C["accent"], 2)
        self.line(self.m + 7, y + 16, self.m + 14, y + 22, C["accent"], 2)
        self.text(self.W / 2, y + 7, title, "semibold", 17, anchor="ma")
        return y + 40

    def tab_bar(self, active):
        top = self.H - 83
        self.d.rectangle((0, self.p(top), self.im.width, self.im.height), fill=C["tab_bg"])
        self.line(0, top, self.W, top, C["sep"], 0.6)
        tabs = ["Today", "Yesterday", "Board", "You"]
        slot = self.W / 4
        for i, name in enumerate(tabs):
            cx = slot * i + slot / 2
            col = C["accent"] if name == active else C["secondary"]
            gy = top + 20
            if name == "Today":
                self.circle(cx, gy, 6, None, outline=col, width=1.8)
                for k in range(8):
                    a = k * math.pi / 4
                    self.line(cx + 9.5 * math.cos(a), gy + 9.5 * math.sin(a), cx + 12.5 * math.cos(a), gy + 12.5 * math.sin(a), col, 1.8)
            elif name == "Yesterday":
                self.circle(cx, gy, 11, None, outline=col, width=1.8)
                self.line(cx, gy - 6, cx, gy, col, 1.8)
                self.line(cx, gy, cx + 5, gy + 3, col, 1.8)
            elif name == "Board":
                for k in range(3):
                    yy = gy - 8 + k * 8
                    self.text(cx - 13, yy - 4.5, str(k + 1), "semibold", 8, col)
                    self.line(cx - 4, yy, cx + 13, yy, col, 1.8)
            else:
                self.circle(cx, gy - 4, 5.5, None, outline=col, width=1.8)
                self.d.arc((self.p(cx - 11), self.p(gy + 2), self.p(cx + 11), self.p(gy + 20)), 200, 340, fill=col, width=self.p(1.8))
            self.text(cx, top + 38, name, "medium", 10, col, anchor="ma")
        self.rrect(self.W / 2 - 67, self.H - 12, 134, 5, 2.5, C["text"])

    def section(self, x, y, title):
        self.text(x, y, title.upper(), "regular", 12, C["secondary"])
        return y + 20

    def cpu_glyph(self, x, y, col, size=15):
        self.rrect(x, y, size, size, size * 0.2, None, outline=col, width=1.4)
        self.rrect(x + size * 0.3, y + size * 0.3, size * 0.4, size * 0.4, 1, col)
        for k in range(3):
            off = size * (0.25 + 0.25 * k)
            self.line(x + off, y - size * 0.22, x + off, y, col, 1.2)
            self.line(x + off, y + size, x + off, y + size * 1.22, col, 1.2)
            self.line(x - size * 0.22, y + off, x, y + off, col, 1.2)
            self.line(x + size, y + off, x + size * 1.22, y + off, col, 1.2)
        return x + size + 9   # clear of the glyph's pins


# ----- content -----
# One coherent machine across all five screens. Secret rule: the first and third
# tiles have the same colour. Decoy the examples invite: all three the same
# colour. Every sequence below is labelled by the real rule; check with
# `python engine/rules.py` if you edit them.

EXAMPLES = [([0, 3, 6], True), ([1, 4, 7], True), ([0, 4, 8], False), ([2, 4, 3], False)]
TRIED = [([0, 4, 6], True, "Not all one colour, so “all three the same” is out."),
         ([4, 0, 6], False, "Last two match and it still rejects: it is the ends.")]
TESTS = [([0, 1, 6], 1), ([4, 4, 8], 0), ([2, 3, 5], 1), ([7, 2, 3], None)]
RULE_TEXT = "The first and third tiles are the same colour."
SETTER_NOTE = ("Claude Opus 5: “Every accepted row is all one colour, so the natural "
               "guess is ‘all three the same’.”")
GPT_TRIED = [([3, 1, 0], True, "Ends both red but not all one colour."),
             ([2, 8, 0], False, "First two match, ends do not: so the ends decide.")]
GPT_MARKS = (True, True, False, True)


# ----- screens -----

def screen_today(ui):
    ui.status_bar()
    y = ui.nav_title("Turnstile")
    ui.text(ui.m + 4, y, "Sep 14", "semibold", 17)
    ui.text(ui.m + 4, y + 22, "Closes in 9h 12m", "regular", 12, C["secondary"])
    ui.text(ui.W - ui.m - 4, y, "184", "semibold", 17, anchor="ra")
    ui.text(ui.W - ui.m - 4, y + 22, "played so far", "regular", 12, C["secondary"], anchor="ra")
    y += 48

    x, cy, w = ui.card(y, 84)
    ui.text(x + 16, cy + 14, "LEVEL 1 OF 3", "semibold", 12, C["accent"])
    ui.text(x + w - 16, cy + 14, "Two machines, four tries each", "regular", 12, C["secondary"], anchor="ra")
    ui.text(x + 16, cy + 38, "Today the rule checks one thing about the row, or the opposite of one thing.", "regular", 15, max_w=w - 32)
    y += 94

    machines = [
        ("Claude Opus 5's machine", "Play", "4 rows judged · not started", EXAMPLES[:3]),
        ("GPT-6's machine", "2 tries left", "you have tried 2 rows", [([6, 2, 6], True), ([0, 0, 7], False), ([5, 5, 2], False)]),
    ]
    for name, status, sub, examples in machines:
        h = 116
        x, cy, w = ui.card(y, h)
        gx = ui.cpu_glyph(x + 16, cy + 18, C["text"], 16)
        ui.text(gx, cy + 15, name, "semibold", 17)
        ui.text(x + w - 30, cy + 16, status, "semibold", 13, C["accent"], anchor="ra")
        ui.line(x + w - 20, cy + 19, x + w - 15, cy + 24, C["secondary"], 1.6)
        ui.line(x + w - 15, cy + 24, x + w - 20, cy + 29, C["secondary"], 1.6)
        ui.text(x + 16, cy + 44, sub, "regular", 12, C["secondary"])
        ex = x + 16
        for seq, acc in examples:
            end = ui.seq(ex, cy + 70, seq, size=26, gap=4)
            ui.verdict(end + 7, cy + 72, acc, label=False, size=18)
            ex = end + 40
        y += h + 12

    x, cy, w = ui.card(y, 132)
    ui.section(x + 16, cy + 14, "How it works")
    for i, step in enumerate(("See which rows it accepted and rejected.",
                              "Try up to four rows of your own.",
                              "Call four rows you have never seen.")):
        ry = cy + 40 + i * 28
        ui.circle(x + 26, ry + 8, 9, mix(C["accent"], C["card"], 0.85))
        ui.text(x + 26, ry + 2, str(i + 1), "semibold", 11, C["accent"], anchor="ma")
        ui.text(x + 44, ry, step, "regular", 14)
    y += 142

    x, cy, w = ui.card(y, 68)
    ui.text(x + 16, cy + 13, "YESTERDAY", "regular", 12, C["secondary"])
    ui.text(x + 16, cy + 36, "You 6/8 ★   ·   Claude 8/8   ·   GPT 4/8", "regular", 15)
    ui.tab_bar("Today")


def screen_experiment(ui):
    ui.status_bar()
    y = ui.nav_inline("Claude Opus 5's machine")

    cw = ui.W - 2 * ui.m
    intro = "This machine follows a secret rule. It accepted these rows and rejected these."
    intro_h = ui.text_h(intro, "regular", 14, cw - 32)
    h = 14 + intro_h + 16 + len(EXAMPLES) * 52
    x, cy, w = ui.card(y, h)
    ry = ui.text(x + 16, cy + 14, intro, "regular", 14, C["secondary"], max_w=w - 32) + 16
    for seq, acc in EXAMPLES:
        ui.seq(x + 16, ry, seq, size=40, gap=6)
        ui.verdict(x + w - 108, ry + 9, acc)
        ry += 52
    y += h + 12

    h = 36 + len(TRIED) * 68
    x, cy, w = ui.card(y, h)
    ui.section(x + 16, cy + 12, "Rows you tried")
    ry = cy + 38
    for i, (seq, acc, note) in enumerate(TRIED):
        ui.circle(x + 26, ry + 11, 9, mix(C["accent"], C["card"], 0.85))
        ui.text(x + 26, ry + 5, str(i + 1), "semibold", 11, C["accent"], anchor="ma")
        ui.seq(x + 42, ry, seq, size=22, gap=4)
        ui.verdict(x + w - 100, ry + 1, acc, size=15)
        ui.text(x + 42, ry + 30, note, "regular", 12, C["secondary"], max_w=w - 70)
        ry += 68
    y += h + 12

    hint = "Build a row of three tiles and the machine will accept it or reject it."
    hint_h = ui.text_h(hint, "regular", 13, ui.W - 2 * ui.m - 32)
    h = 14 + 22 + 6 + hint_h + 18 + 56 + 26 + 34 + 18 + 42 + 14 + 44 + 16
    x, cy, w = ui.card(y, h)
    ui.text(x + 16, cy + 14, "Your turn (3 of 4)", "semibold", 17)
    sy = ui.text(x + 16, cy + 42, hint, "regular", 13, C["secondary"], max_w=w - 32) + 18
    ui.tile(x + 16, sy, 56, 2)
    ui.tile(x + 82, sy, 56, 5)
    ui.empty_slot(x + 148, sy, 56, C["accent"])
    py = sy + 56 + 26
    for t in range(9):
        ui.tile(x + 16 + t * ((w - 32 - 34) / 8), py, 34, t)
    ny = py + 34 + 18
    ui.rrect(x + 16, ny, w - 32, 42, 10, C["fill"])
    ui.text(x + 30, ny + 12, "If the ends must match, yellow accepts.", "regular", 14, C["secondary"])
    by = ny + 42 + 14
    ui.rrect(x + 16, by, w - 32, 44, 11, C["accent"])
    ui.text(x + w / 2, by + 12, "Ask the machine", "semibold", 17, C["white"], anchor="ma")


def screen_tests(ui):
    ui.status_bar()
    y = ui.nav_inline("Claude Opus 5's machine")

    cw = ui.W - 2 * ui.m

    # Examples and experiments stay on screen above the tests, as in the app.
    h = 34 + len(EXAMPLES) * 38
    x, cy, w = ui.card(y, h)
    ui.section(x + 16, cy + 12, "What the machine did")
    ry = cy + 36
    for seq, acc in EXAMPLES:
        ui.seq(x + 16, ry, seq, size=28, gap=4)
        ui.verdict(x + w - 104, ry + 3, acc, size=15)
        ry += 38
    y += h + 12

    x, cy, w = ui.card(y, 34 + 38)
    ui.section(x + 16, cy + 12, "Rows you tried")
    ex = x + 16
    for seq, acc, _ in TRIED:
        end = ui.seq(ex, cy + 36, seq, size=28, gap=4)
        ui.verdict(end + 7, cy + 39, acc, label=False, size=18)
        ex = end + 42
    y += 34 + 38 + 12

    ask = "Which of these rows does the machine accept? Exactly two of them."
    ask_h = ui.text_h(ask, "regular", 13, cw - 32)
    h = 14 + 26 + 8 + ask_h + 16 + len(TESTS) * 58 + 66
    x, cy, w = ui.card(y, h)
    ui.text(x + 16, cy + 14, "The final four", "semibold", 20)
    ry = ui.text(x + 16, cy + 48, ask, "regular", 13, C["secondary"], max_w=w - 32) + 16
    for i, (seq, pick) in enumerate(TESTS):
        ui.text(x + 20, ry + 12, str(i + 1), "semibold", 12, C["secondary"])
        ui.seq(x + 38, ry, seq, size=38, gap=5)
        seg_w, seg_x = 150, x + w - 166
        ui.rrect(seg_x, ry + 4, seg_w, 32, 8, C["fill"])
        if pick is not None:
            slot = 0 if pick == 1 else 1   # Accept is the left half, Reject the right
            ui.rrect(seg_x + 2 + slot * (seg_w / 2 - 2), ry + 6, seg_w / 2 - 2, 28, 7, C["white"])
        ui.text(seg_x + seg_w / 4, ry + 12, "Accept", "medium" if pick == 1 else "regular", 13,
                C["text"] if pick == 1 else C["secondary"], anchor="ma")
        ui.text(seg_x + seg_w * 3 / 4, ry + 12, "Reject", "medium" if pick == 0 else "regular", 13,
                C["text"] if pick == 0 else C["secondary"], anchor="ma")
        ry += 58
    ui.rrect(x + 16, ry + 6, w - 32, 44, 11, mix(C["accent"], C["card"], 0.45))
    ui.text(x + w / 2, ry + 18, "Lock in my answers", "semibold", 17, C["white"], anchor="ma")


def screen_reveal(ui):
    ui.status_bar()
    y = ui.nav_inline("Claude Opus 5's machine")

    x, cy, w = ui.card(y, 96)
    ui.text(x + w / 2, cy + 12, "YOUR SCORE", "regular", 12, C["secondary"], anchor="ma")
    ui.text(x + w / 2 - 12, cy + 32, "4", "semibold", 52, anchor="ma")
    ui.text(x + w / 2 + 26, cy + 48, "/4", "semibold", 22, C["secondary"], anchor="ma")
    y += 106

    cw = ui.W - 2 * ui.m
    rule_h = ui.text_h(RULE_TEXT, "semibold", 20, cw - 32)
    note_h = ui.text_h(SETTER_NOTE, "regular", 13, cw - 32 - 26)
    h = 14 + 20 + 4 + rule_h + 16 + note_h + 18
    x, cy, w = ui.card(y, h)
    ui.section(x + 16, cy + 14, "The rule")
    ny = ui.text(x + 16, cy + 38, RULE_TEXT, "semibold", 20, max_w=w - 32) + 16
    gx = ui.cpu_glyph(x + 16, ny + 2, C["secondary"], 15)
    ui.text(gx, ny, SETTER_NOTE, "regular", 13, C["secondary"], max_w=w - 32 - 26)
    y += h + 10

    x, cy, w = ui.card(y, 96)
    ui.section(x + 16, cy + 12, "Everyone else")
    stats = [("184", "played"), ("52%", "got all four"), ("2.9", "average"), ("31%", "named the rule")]
    for i, (v, label) in enumerate(stats):
        cx = x + w * (i + 0.5) / 4
        ui.text(cx, cy + 38, v, "semibold", 19, anchor="ma")
        ui.text(cx, cy + 64, label, "regular", 11, C["secondary"], anchor="ma")
        if i:
            ui.line(x + w * i / 4, cy + 36, x + w * i / 4, cy + 74, C["sep"], 0.8)
    y += 106

    blurb = "The rows it tried, before you saw this machine:"
    h = 14 + 22 + 6 + ui.text_h(blurb, "regular", 12, cw - 32) + 12 + len(GPT_TRIED) * 66 + 30 + 24
    x, cy, w = ui.card(y, h)
    gx = ui.cpu_glyph(x + 16, cy + 18, C["text"], 16)
    ui.text(gx, cy + 15, "GPT-6", "semibold", 17)
    ui.text(x + w - 16, cy + 15, "3/4", "semibold", 17, anchor="ra")
    ry = ui.text(x + 16, cy + 44, blurb, "regular", 12, C["secondary"], max_w=w - 32) + 12
    for i, (seq, acc, note) in enumerate(GPT_TRIED):
        ui.circle(x + 26, ry + 11, 9, mix(C["accent"], C["card"], 0.85))
        ui.text(x + 26, ry + 5, str(i + 1), "semibold", 11, C["accent"], anchor="ma")
        ui.seq(x + 42, ry, seq, size=22, gap=4)
        ui.verdict(x + w - 96, ry + 1, acc, size=15)
        ui.text(x + 42, ry + 28, note, "regular", 12, C["secondary"], max_w=w - 70)
        ry += 66
    label = "Final four:"
    ui.text(x + 16, ry + 4, label, "regular", 12, C["secondary"])
    marks_x = x + 16 + ui.width(label, "regular", 12) + 8
    for k, ok in enumerate(GPT_MARKS):
        ui.verdict(marks_x + k * 24, ry + 1, ok, label=False, size=15)
    ui.text(x + 16, ry + 30, "It guessed: at least two tiles share a colour", "regular", 12, C["secondary"])


def screen_board(ui):
    ui.status_bar()
    y = ui.nav_title("Board")
    seg_w = ui.W - 2 * ui.m
    ui.rrect(ui.m, y, seg_w, 34, 9, C["fill"])
    ui.rrect(ui.m + 2 + 2 * (seg_w / 3 - 2), y + 2, seg_w / 3 - 2, 30, 8, C["white"])
    for i, label in enumerate(("Today", "30 days", "Setters")):
        ui.text(ui.m + seg_w * (i + 0.5) / 3, y + 8, label, "medium" if i == 2 else "regular", 14,
                C["text"] if i == 2 else C["secondary"], anchor="ma")
    y += 48
    ui.text(ui.m + 4, y, "Claude and GPT build the machines, so they are scored on how well they pitch them: best when 40 to 70 percent of people get all four.",
            "regular", 12, C["secondary"], max_w=ui.W - 2 * ui.m - 8)
    y += 46

    # Points follow the stated rule: 2 inside 40-70%, 1 inside 30-80%, else 0;
    # +1 when the rival AI scored under 4 and at least 40% of people solved it.
    setters = [
        ("Claude Opus 5", 17, 9, [("Sep 13", 1, "52% got all four", "other AI 3/4", 3),
                                  ("Sep 12", 2, "61% got all four", "other AI 4/4", 2),
                                  ("Sep 11", 2, "38% got all four", "other AI 2/4", 1),
                                  ("Sep 10", 2, "45% got all four", "other AI 4/4", 2),
                                  ("Sep 09", 1, "71% got all four", "other AI 4/4", 1)]),
        ("GPT-6", 14, 9, [("Sep 13", 1, "44% got all four", "other AI 4/4", 2),
                          ("Sep 12", 2, "84% got all four", "other AI 4/4", 0),
                          ("Sep 11", 2, "49% got all four", "other AI 1/4", 3),
                          ("Sep 10", 2, "56% got all four", "other AI 4/4", 2),
                          ("Sep 09", 1, "35% got all four", "other AI 2/4", 1)]),
    ]
    for name, pts, machines, rows in setters:
        h = 52 + len(rows) * 26
        x, cy, w = ui.card(y, h)
        gx = ui.cpu_glyph(x + 16, cy + 17, C["text"], 16)
        ui.text(gx, cy + 14, name, "semibold", 17)
        ui.text(x + w - 16, cy + 15, f"{pts} points · {machines} machines", "medium", 14, anchor="ra")
        ry = cy + 46
        for date, tier, result, rival, gain in rows:
            ui.text(x + 16, ry, date, "regular", 12, C["secondary"])
            ui.text(x + 68, ry, f"L{tier}", "semibold", 11, C["accent"])
            ui.text(x + 94, ry, result, "regular", 12)
            ui.text(x + w - 60, ry, rival, "regular", 12, C["secondary"], anchor="ra")
            ui.text(x + w - 16, ry, f"+{gain}", "semibold", 12, anchor="ra")
            ry += 26
        y += h + 12
    ui.tab_bar("Board")


SCREENS = [
    ("01_today", screen_today, "Two machines a day.\nOne set by Claude, one by GPT."),
    ("02_experiment", screen_experiment, "Four tries.\nPick the row that settles it."),
    ("03_tests", screen_tests, "Then call four rows\nyou have never seen."),
    ("04_reveal", screen_reveal, "See the rule, the trap,\nand where the other AI went wrong."),
    ("05_board", screen_board, "The AIs are scored too,\non how well they set."),
]


def compose(shot, caption, size, caption_px, device_frac, radius_frac):
    W, H = size
    canvas = Image.new("RGB", size, C["page"])
    d = ImageDraw.Draw(canvas)
    f = font("semibold", caption_px)
    y = int(H * 0.055)
    for line in caption.split("\n"):
        d.text((W / 2, y), line, font=f, fill=C["text"], anchor="ma")
        y += int(caption_px * 1.22)
    y += int(H * 0.035)
    dw = int(W * device_frac)
    scale = dw / shot.width
    dh = int(shot.height * scale)
    shot = shot.resize((dw, dh), Image.LANCZOS)
    r = int(dw * radius_frac)
    bezel = max(8, int(dw * 0.014))
    x = (W - dw) // 2
    d.rounded_rectangle((x - bezel, y - bezel, x + dw + bezel, y + dh + bezel), r + bezel, fill=C["bezel"])
    mask = Image.new("L", (dw, dh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, dw - 1, dh - 1), r, fill=255)
    canvas.paste(shot, (x, y), mask)
    return canvas


def main():
    targets = {
        # folder: canvas size, scale (px per pt), margin (pt), caption px, device width fraction, corner radius fraction
        "iphone-6.7": ((1290, 2796), 3.0, 16, 64, 0.84, 0.115),
        "ipad-13": ((2048, 2732), 2.6, 20, 76, 0.80, 0.045),
    }
    for folder, (size, s, margin, cap_px, dev_frac, r_frac) in targets.items():
        out = os.path.join(OUT, folder)
        os.makedirs(out, exist_ok=True)
        for name, draw, caption in SCREENS:
            ui = UI(size[0], size[1], s, margin)
            draw(ui)
            img = compose(ui.im, caption, size, cap_px, dev_frac, r_frac)
            path = os.path.join(out, f"{name}.png")
            img.save(path, optimize=True)
            print(f"{folder}/{name}.png {img.size}")


if __name__ == "__main__":
    main()
