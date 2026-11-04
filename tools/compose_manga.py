"""把逐格 AI 素材排版成真正的漫画页（分格线 / 对白泡泡 / 拟声词 / 时间戳框）。

设计要点：
  * 每页 3 格，格子比例尽量贴近原图比例，避免大幅裁切；
  * 全页强制「黑白 + 单一红」：保留原图的红色像素（眼睛/血），其余转灰度并提对比；
  * 所有文字用系统字体在本地绘制，不依赖 AI 写字（AI 写中文必糊）。

用法：
  python compose_manga.py <gen_dir> <out_dir>
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1200, 900
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MARGIN = 36
GUTTER = 18
BORDER = 5
RED = (198, 24, 30)
PAPER = (255, 255, 255)
INK = (12, 12, 14)

FONT_DIR = r"C:\Windows\Fonts"
F_NARR = os.path.join(FONT_DIR, "msyhbd.ttc")
F_TALK = os.path.join(FONT_DIR, "simhei.ttf")
F_SFX = os.path.join(FONT_DIR, "STXINGKA.TTF")


# ---------------------------------------------------------------- image utils
def unify_mono(img):
    """黑白漫画化：保留红色像素（眼睛/血），其余转灰度 + 提对比。"""
    import numpy as np

    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    t = np.clip(0.5 + (lum / 255.0 - 0.5) * 1.35, 0.0, 1.0)
    t = t * t * (3 - 2 * t)
    v = (t * 255).astype(np.uint8)
    out = np.dstack([v, v, v])

    red_mask = (r - g > 42) & (r - b > 42) & (r > 55)
    k = np.clip(r / 220.0, 0.35, 1.0)
    for i, c in enumerate(RED):
        out[:, :, i] = np.where(red_mask, (c * k).astype(np.uint8), out[:, :, i])
    return Image.fromarray(out, "RGB")


def trim_white(img, tol=244, max_frac=0.20):
    """裁掉 AI 出图四边的纯白留白（有些模型会加白边），避免拼页时露出白条。"""
    import numpy as np

    a = np.asarray(img.convert("L"))
    h, w = a.shape

    def col_white(x):
        return (a[:, x] >= tol).mean() > 0.985

    def row_white(y):
        return (a[y, :] >= tol).mean() > 0.985

    limx, limy = int(w * max_frac), int(h * max_frac)
    x0 = 0
    while x0 < limx and col_white(x0):
        x0 += 1
    x1 = w - 1
    while x1 > w - 1 - limx and col_white(x1):
        x1 -= 1
    y0 = 0
    while y0 < limy and row_white(y0):
        y0 += 1
    y1 = h - 1
    while y1 > h - 1 - limy and row_white(y1):
        y1 -= 1
    if (x1 - x0) < w * 0.6 or (y1 - y0) < h * 0.6:
        return img
    return img.crop((x0, y0, x1 + 1, y1 + 1))


def cover_crop(img, tw, th, bias=0.5, hbias=0.5):
    """等比缩放到覆盖目标框，再裁切。bias 控制垂直取景（0=顶部，1=底部）。"""
    sw, sh = img.size
    scale = max(tw / sw, th / sh)
    nw, nh = max(1, round(sw * scale)), max(1, round(sh * scale))
    img = img.resize((nw, nh), Image.LANCZOS)
    left = (nw - tw) * hbias
    top = (nh - th) * bias
    return img.crop((round(left), round(top), round(left) + tw, round(top) + th))


# ---------------------------------------------------------------- text utils
def wrap_text(draw, text, font, max_w):
    lines = []
    for raw in text.split("\n"):
        cur = ""
        for ch in raw:
            if draw.textlength(cur + ch, font=font) <= max_w:
                cur += ch
            else:
                if cur:
                    lines.append(cur)
                cur = ch
        lines.append(cur)
    return lines


def draw_block_text(draw, box, text, font, fill, align="center", spacing=8):
    x, y, w, h = box
    lines = wrap_text(draw, text, font, w)
    lh = font.size + spacing
    total = lh * len(lines) - spacing
    cy = y + (h - total) / 2
    for line in lines:
        tw = draw.textlength(line, font=font)
        if align == "center":
            tx = x + (w - tw) / 2
        else:
            tx = x
        draw.text((tx, cy), line, font=font, fill=fill)
        cy += lh


def narration_box(page, box, text, size=30):
    d = ImageDraw.Draw(page)
    x, y, w, h = box
    d.rectangle([x, y, x + w, y + h], fill=INK)
    d.rectangle([x, y, x + w, y + h], outline=(255, 255, 255), width=2)
    font = ImageFont.truetype(F_NARR, size)
    draw_block_text(d, (x + 18, y + 12, w - 36, h - 24), text, font, (245, 245, 240))


def speech_bubble(page, cx, cy, rx, ry, text, tail_to=None, size=30):
    d = ImageDraw.Draw(page)
    # 尾巴
    if tail_to:
        tx, ty = tail_to
        d.polygon([(cx - rx * 0.25, cy + ry * 0.75),
                   (cx + rx * 0.25, cy + ry * 0.7),
                   (tx, ty)], fill=(255, 255, 255), outline=INK)
        d.line([(cx - rx * 0.25, cy + ry * 0.78), (tx, ty)], fill=INK, width=4)
        d.line([(cx + rx * 0.25, cy + ry * 0.72), (tx, ty)], fill=INK, width=4)
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(255, 255, 255), outline=INK, width=5)
    font = ImageFont.truetype(F_TALK, size)
    draw_block_text(d, (cx - rx * 0.78, cy - ry * 0.62, rx * 1.56, ry * 1.2), text, font, INK)


def sfx(page, xy, text, size=90, fill=(255, 255, 255), outline=INK, stroke=10):
    d = ImageDraw.Draw(page)
    font = ImageFont.truetype(F_SFX, size)
    x, y = xy
    d.text((x, y), text, font=font, fill=fill, stroke_width=stroke, stroke_fill=outline)


def auto_sfx(page, xy, text, size=90, red=False):
    """按文字背后的明暗自动选描边色，避免白字压在白墙上。"""
    import numpy as np

    font = ImageFont.truetype(F_SFX, size)
    d = ImageDraw.Draw(page)
    x, y = xy
    bbox = d.textbbox((x, y), text, font=font, stroke_width=8)
    x0, y0 = max(0, bbox[0]), max(0, bbox[1])
    x1, y1 = min(page.width, bbox[2]), min(page.height, bbox[3])
    if x1 <= x0 or y1 <= y0:
        lum = 255.0
    else:
        patch = np.asarray(page.crop((x0, y0, x1, y1)).convert("L")).astype(np.float32)
        lum = float(patch.mean())
    if red:
        fill, outline = RED, ((255, 255, 255) if lum < 120 else INK)
    else:
        fill, outline = ((255, 255, 255) if lum < 120 else INK), ((INK) if lum < 120 else (255, 255, 255))
    d.text((x, y), text, font=font, fill=fill, stroke_width=10, stroke_fill=outline)


def red_sfx(page, xy, text, size=96):
    auto_sfx(page, xy, text, size=size, red=True)


# ---------------------------------------------------------------- page build
def build_page(slots, out_path, deco=None):
    page = Image.new("RGB", (W, H), PAPER)
    for src, box, bias, hbias in slots:
        x, y, w, h = box
        img = Image.open(src)
        img = trim_white(img)
        img = unify_mono(img)
        img = cover_crop(img, w, h, bias=bias, hbias=hbias)
        page.paste(img, (x, y))
        d = ImageDraw.Draw(page)
        d.rectangle([x, y, x + w - 1, y + h - 1], outline=INK, width=BORDER)
    if deco:
        deco(page)
    page.save(out_path)
    print("page ->", out_path, page.size)


def main():
    gen = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "tools", "_gen")
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "art", "cutscene")
    os.makedirs(out, exist_ok=True)

    def p(name):
        return os.path.join(gen, name + ".png")

    # ---------------- 第 1 页：走廊尽头 ----------------
    def deco1(page):
        narration_box(page, (754, 620, 420, 244), "23:47\n教学楼 · 三层", size=34)

    build_page([
        (p("ti_p1_1"), (MARGIN, MARGIN, 700, 394), 0.5, 0.5),
        (p("ti_p1_3"), (MARGIN, MARGIN + 394 + GUTTER, 700, 394), 0.5, 0.5),
        (p("ti_p1_2"), (MARGIN + 700 + GUTTER, MARGIN, 420, 560), 0.42, 0.5),
    ], os.path.join(out, "page1.png"), deco1)

    # ---------------- 第 2 页：它看见你了 ----------------
    def deco2(page):
        red_sfx(page, (700, 470), "咚！", size=110)
        narration_box(page, (654, 754, 520, 110), "别 · 出 · 声", size=32)

    build_page([
        (p("ti_p2_1"), (MARGIN, MARGIN, 600, 800), 0.3, 0.5),
        (p("ti_p2_2"), (MARGIN + 600 + GUTTER, MARGIN, 520, 390), 0.32, 0.5),
        (p("ti_p2_3"), (MARGIN + 600 + GUTTER, MARGIN + 390 + GUTTER, 520, 292), 0.55, 0.5),
    ], os.path.join(out, "page2.png"), deco2)

    # ---------------- 第 3 页：追 ----------------
    def deco3(page):
        speech_bubble(page, 940, 386, 96, 58, "跑！", tail_to=(1012, 318), size=50)
        red_sfx(page, (838, 610), "砰！", size=120)
        auto_sfx(page, (96, 516), "哗啦", size=54)

    build_page([
        (p("ti_p3_1"), (MARGIN, MARGIN, 760, 428), 0.5, 0.5),
        (p("ti_p3_2"), (MARGIN + 760 + GUTTER, MARGIN, 380, 506), 0.5, 0.5),
        (p("ti_p3_3"), (MARGIN, MARGIN + 428 + GUTTER, 700, 400), 0.45, 0.5),
    ], os.path.join(out, "page3.png"), deco3)

    # ---------------- 第 4 页：别回头 ----------------
    def deco4(page):
        narration_box(page, (MARGIN, MARGIN + 560 + GUTTER, 420, 268), "死 路", size=64)

    build_page([
        (p("ti_p4_2"), (MARGIN, MARGIN, 420, 560), 0.28, 0.5),
        (p("ti_p4_1"), (MARGIN + 420 + GUTTER, MARGIN, 700, 394), 0.5, 0.5),
        (p("ti_p4_3"), (MARGIN + 420 + GUTTER, MARGIN + 394 + GUTTER, 700, 394), 0.5, 0.5),
    ], os.path.join(out, "page4.png"), deco4)


if __name__ == "__main__":
    main()
