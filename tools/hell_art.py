"""第三层（11~15F）地狱美术管线。

产出三样东西：
1. ``art/sprites/floor/hell_styles.png`` —— 6 行（石砌/肉褶/血管/骨板/粘膜/酸蚀）× 6 变体的**灰度**图案。
   游戏里地板 = 灰度图案 × 房型颜色（和 ``tilemancer_styles.png`` 同一套用法），所以这里只出灰度。
2. ``art/furniture/hell/*.png`` —— 把学校那 46 张家具腐化改色（轮廓/尺寸不动，碰撞零改动），
   外加一批程序画的地狱家具（铁栅/炭盆/祭坛/骨堆/铁链/酸池/眼球/骨梁/吊钩/铁笼）。
3. ``tests/art_hell_*.png`` —— 两张**色板样张**（地牢风 / 器官风），用上面的素材拼出来。

用法::

    python tools/hell_art.py            # 全部
    python tools/hell_art.py --atlas    # 只出地板图集
    python tools/hell_art.py --mock     # 只出样张
"""
import math
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILE = 20
SRC_FURN = os.path.join(ROOT, "art", "furniture")
OUT_FURN = os.path.join(SRC_FURN, "hell")
OUT_ATLAS = os.path.join(ROOT, "art", "sprites", "floor", "hell_styles.png")

# ---------------------------------------------------------------- 色板
PAL = {
    "flesh": (200, 122, 114),
    "flesh_dark": (142, 74, 70),
    "purple": (74, 51, 88),
    "purple_dark": (46, 32, 56),
    "green": (62, 110, 92),
    "green_sick": (111, 158, 106),
    "bone": (216, 205, 190),
    "char": (26, 20, 24),
    "blood": (122, 31, 34),
    "rust": (138, 78, 52),
    "iron": (96, 96, 108),
}


def C(name, mul=1.0, alpha=255):
    r, g, b = PAL[name]
    return (int(r * mul), int(g * mul), int(b * mul), alpha)


# ---------------------------------------------------------------- 周期噪声
def _h(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 1442695041) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def pnoise(x, y, freq, seed):
    """x/y ∈ [0,1)，在 freq×freq 格上可平铺的值噪声。"""
    fx, fy = x * freq, y * freq
    ix, iy = int(math.floor(fx)), int(math.floor(fy))
    tx, ty = _smooth(fx - ix), _smooth(fy - iy)
    x0, y0 = ix % freq, iy % freq
    x1, y1 = (ix + 1) % freq, (iy + 1) % freq
    a = _h(x0, y0, seed)
    b = _h(x1, y0, seed)
    c = _h(x0, y1, seed)
    d = _h(x1, y1, seed)
    top = a + (b - a) * tx
    bot = c + (d - c) * tx
    return top + (bot - top) * ty


def fbm(x, y, seed, octaves=3, base=4):
    v, amp, tot = 0.0, 1.0, 0.0
    for o in range(octaves):
        v += pnoise(x, y, base * (2 ** o), seed + o * 17) * amp
        tot += amp
        amp *= 0.5
    return v / tot


# ---------------------------------------------------------------- 六种图案
def style_stone(x, y, v, seed):
    """石砌：错缝大方砖 + 裂缝。"""
    rows = 2
    row = int(y * rows)
    off = 0.5 if row % 2 else 0.0
    bx = (x + off) * 2.0
    fx, fy = bx - int(bx), y * rows - row
    mortar = 1.0
    if fy < 0.10 or fy > 0.93 or fx < 0.045 or fx > 0.955:
        mortar = 0.46
    # 每块砖自己的明度（用砖的整数坐标当种子）
    bid = int(bx) + row * 7 + v * 13
    brick = 0.80 + 0.20 * _h(bid, v, seed)
    n = fbm(x, y, seed + v * 31, 2, 4)
    # 砖面从左上到右下微微变暗
    shade = 1.0 - 0.10 * (fx * 0.6 + fy * 0.4)
    return max(0.34, min(1.0, brick * shade * (0.88 + 0.22 * n) * mortar))


def style_flesh(x, y, v, seed):
    """肉褶：低频起伏的褶皱，带湿光。"""
    s = math.sin((y * 2.0 + fbm(x, y, seed + v, 2, 3) * 0.9) * math.pi * 2.0)
    ridge = 0.5 + 0.5 * s
    n = fbm(x, y, seed + 51 + v, 3, 5)
    edge = abs(fbm(x, y, seed + 91 + v, 2, 6) - 0.5) * 2.0
    val = 0.82 + 0.11 * ridge + 0.07 * n
    val -= 0.06 * max(0.0, 0.20 - edge) / 0.20
    return max(0.62, min(1.0, val))


def style_vessel(x, y, v, seed):
    """血管：膜底 + 分叉细管。"""
    base = 0.86 + 0.08 * fbm(x, y, seed + v, 3, 4)
    d = 1.0
    for k in range(3):
        amp = 0.18 + 0.06 * k
        ph = 0.7 * y + 1.7 * x + k * 0.33 + fbm(x, y, seed + 7 * k + v, 1, 2) * 0.4
        line = abs(math.sin(ph * math.pi * 2.0))
        d = min(d, line * 0.5 + amp * 0.5)
    if d < 0.12:
        base *= 0.80
    elif d < 0.20:
        base *= 0.92
    return max(0.62, min(1.0, base))


def style_bone(x, y, v, seed):
    """骨板：多边形板块 + 深缝。"""
    a = fbm(x, y, seed + v, 3, 3)
    b = fbm(x + 0.37, y + 0.21, seed + 13 + v, 3, 3)
    plate = 0.5 + 0.5 * math.sin((a - b) * 8.0)
    seam = abs(a - b)
    val = 0.66 + 0.28 * plate
    if seam < 0.035:
        val *= 0.62
    val += 0.08 * fbm(x, y, seed + 41 + v, 2, 8)
    return max(0.40, min(1.0, val))


def style_mucosa(x, y, v, seed):
    """粘膜：平滑斑块 + 高光点。"""
    n = fbm(x, y, seed + v, 3, 2)
    val = 0.76 + 0.18 * n
    hi = fbm(x, y, seed + 77 + v, 2, 7)
    if hi > 0.82:
        val += 0.05
    if hi < 0.18:
        val -= 0.04
    return max(0.68, min(1.0, val))


def style_acid(x, y, v, seed):
    """酸蚀：坑洞 + 不均匀侵蚀。"""
    n = fbm(x, y, seed + v, 3, 5)
    val = 0.84 + 0.10 * n
    pit = fbm(x, y, seed + 61 + v, 2, 8)
    if pit > 0.76:
        val *= 0.78
    elif pit > 0.68:
        val *= 0.90
    return max(0.62, min(1.0, val))


STYLES = [
    ("stone", style_stone),
    ("flesh", style_flesh),
    ("vessel", style_vessel),
    ("bone", style_bone),
    ("mucosa", style_mucosa),
    ("acid", style_acid),
]
VARIANTS = 6


def build_atlas():
    img = Image.new("L", (TILE * VARIANTS, TILE * len(STYLES)), 0)
    px = img.load()
    vmul = [1.00, 0.96, 1.03, 0.94, 1.02, 0.97]
    vshift = [(0.00, 0.00), (0.37, 0.11), (0.71, 0.53), (0.19, 0.83), (0.55, 0.29), (0.88, 0.67)]
    for si, (_, fn) in enumerate(STYLES):
        for v in range(VARIANTS):
            dx, dy = vshift[v]
            for y in range(TILE):
                for x in range(TILE):
                    u = ((x / TILE) + dx) % 1.0
                    w = ((y / TILE) + dy) % 1.0
                    val = fn(u, w, v, 100 + si * 7) * vmul[v]
                    px[v * TILE + x, si * TILE + y] = int(max(0, min(255, val * 255)))
    img.convert("RGBA").save(OUT_ATLAS)
    print("atlas ->", os.path.relpath(OUT_ATLAS, ROOT), img.size)
    return img


# ---------------------------------------------------------------- 家具腐化
def _pick_tint(name):
    h = sum(ord(c) * (i + 7) for i, c in enumerate(name))
    return [C("flesh", 0.92), C("purple", 1.05), C("green", 1.05), C("rust", 0.95)][h % 4]


def corrupt_furniture():
    os.makedirs(OUT_FURN, exist_ok=True)
    names = sorted(f for f in os.listdir(SRC_FURN) if f.endswith(".png"))
    for idx, fname in enumerate(names):
        im = Image.open(os.path.join(SRC_FURN, fname)).convert("RGBA")
        w, h = im.size
        px = im.load()
        tint = _pick_tint(fname)
        seed = 900 + idx * 13
        out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        op = out.load()
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a == 0:
                    continue
                lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                # 3/4 换成尸色，1/4 保留原色（不然认不出是什么家具）
                tr = tint[0] * (0.45 + 0.72 * lum)
                tg = tint[1] * (0.45 + 0.72 * lum)
                tb = tint[2] * (0.45 + 0.72 * lum)
                nr = tr * 0.70 + r * 0.30
                ng = tg * 0.70 + g * 0.30
                nb = tb * 0.70 + b * 0.30
                # 淤斑：低频噪声压暗
                blot = pnoise(x / max(1, w), y / max(1, h), 4, seed)
                if blot < 0.40:
                    k = 0.84 + blot * 0.4
                    nr, ng, nb = nr * k, ng * k, nb * k
                # 轻微去高光
                nr, ng, nb = nr * 0.96, ng * 0.96, nb * 0.96
                op[x, y] = (
                    max(0, min(255, int(nr))),
                    max(0, min(255, int(ng))),
                    max(0, min(255, int(nb))),
                    a,
                )
        # 轮廓加深：贴着透明的像素再压暗
        for y in range(h):
            for x in range(w):
                if op[x, y][3] == 0:
                    continue
                edge = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if nx < 0 or ny < 0 or nx >= w or ny >= h or op[nx, ny][3] == 0:
                        edge = True
                        break
                if edge:
                    r, g, b, a = op[x, y]
                    op[x, y] = (int(r * 0.68), int(g * 0.68), int(b * 0.68), a)
        out.save(os.path.join(OUT_FURN, fname))
    print("furniture ->", os.path.relpath(OUT_FURN, ROOT), len(names), "files")


# ---------------------------------------------------------------- 程序画的地狱道具
def _canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def _px(d, x, y, col):
    d.point((x, y), fill=col)


def prop_bars():
    im = _canvas(46, 40)
    d = ImageDraw.Draw(im)
    for i in range(4):
        x = 4 + i * 11
        d.rectangle([x, 0, x + 3, 39], fill=C("iron", 0.55))
        d.rectangle([x, 0, x + 1, 39], fill=C("iron", 0.75))
        d.rectangle([x, 6, x + 3, 7], fill=C("rust"))
        d.rectangle([x, 28, x + 3, 29], fill=C("rust"))
    d.rectangle([0, 0, 45, 2], fill=C("iron", 0.45))
    d.rectangle([0, 37, 45, 39], fill=C("iron", 0.40))
    return im


def prop_brazier():
    im = _canvas(30, 34)
    d = ImageDraw.Draw(im)
    d.polygon([(13, 34), (11, 26), (19, 26), (17, 34)], fill=C("iron", 0.45))
    d.rectangle([4, 16, 26, 26], fill=C("iron", 0.60))
    d.rectangle([4, 16, 26, 18], fill=C("iron", 0.80))
    d.rectangle([6, 12, 24, 16], fill=C("char"))
    d.ellipse([7, 9, 23, 18], fill=(196, 92, 44, 255))
    d.ellipse([10, 7, 20, 14], fill=(232, 152, 62, 255))
    d.ellipse([12, 5, 18, 10], fill=(252, 214, 130, 255))
    return im


def prop_altar():
    im = _canvas(48, 40)
    d = ImageDraw.Draw(im)
    # 台基
    d.rectangle([0, 28, 47, 39], fill=C("purple_dark", 1.25))
    d.rectangle([0, 28, 47, 30], fill=C("purple", 0.95))
    # 台面
    d.rectangle([3, 16, 44, 31], fill=C("purple", 1.05))
    d.rectangle([3, 16, 44, 18], fill=C("purple", 1.30))
    d.rectangle([3, 29, 44, 31], fill=C("purple_dark", 1.1))
    # 中间凹陷（黑）
    d.rectangle([11, 20, 36, 28], fill=(12, 8, 12, 255))
    d.rectangle([11, 20, 36, 21], fill=C("blood", 0.55))
    # 边缘阴影
    d.rectangle([3, 16, 4, 31], fill=C("purple_dark", 1.0))
    d.rectangle([43, 16, 44, 31], fill=C("purple_dark", 1.0))
    # 三根矮烛
    for i, x in enumerate((8, 23, 38)):
        d.rectangle([x, 10, x + 1, 16], fill=C("bone", 0.85))
        _px(d, x, 9, (252, 214, 130, 255))
        _px(d, x + 1, 9, (232, 152, 62, 220))
    return im


def prop_bone_pile():
    im = _canvas(40, 24)
    d = ImageDraw.Draw(im)
    for i in range(7):
        x = 2 + (i * 5) % 34
        y = 10 + (i * 7) % 12
        d.rectangle([x, y, x + 8, y + 2], fill=C("bone", 0.62 + 0.05 * (i % 3)))
        d.ellipse([x - 1, y - 1, x + 2, y + 2], fill=C("bone", 0.82))
        d.ellipse([x + 6, y - 1, x + 9, y + 2], fill=C("bone", 0.82))
    d.ellipse([12, 2, 24, 14], fill=C("bone", 0.86))
    d.ellipse([15, 6, 17, 9], fill=C("char"))
    d.ellipse([20, 6, 22, 9], fill=C("char"))
    return im


def prop_chain():
    im = _canvas(16, 40)
    d = ImageDraw.Draw(im)
    for i in range(8):
        y = i * 5
        c = C("iron", 0.72 if i % 2 == 0 else 0.52)
        if i % 2 == 0:
            d.ellipse([3, y, 12, y + 5], outline=c)
        else:
            d.ellipse([5, y, 10, y + 5], outline=c)
    return im


def prop_acid_pool():
    im = _canvas(52, 30)
    d = ImageDraw.Draw(im)
    d.ellipse([0, 3, 51, 29], fill=C("green", 0.30, 240))
    d.ellipse([2, 5, 49, 27], fill=C("green", 0.62, 245))
    d.ellipse([5, 9, 46, 24], fill=C("green_sick", 0.80, 245))
    d.ellipse([9, 12, 42, 21], fill=(150, 206, 132, 245))
    for i in range(11):
        x = 8 + (i * 13) % 36
        y = 11 + (i * 7) % 11
        _px(d, x, y, (222, 244, 198, 235))
    for i in range(6):
        x = 12 + (i * 17) % 30
        d.ellipse([x, 8 + (i % 3) * 4, x + 2, 10 + (i % 3) * 4], fill=(206, 240, 180, 210))
    return im


def prop_eye():
    im = _canvas(56, 44)
    d = ImageDraw.Draw(im)
    d.ellipse([0, 4, 55, 43], fill=C("flesh", 0.72))
    d.ellipse([4, 8, 51, 40], fill=(226, 220, 205, 255))
    d.ellipse([16, 12, 40, 36], fill=C("green", 0.95))
    d.ellipse([23, 19, 33, 29], fill=(18, 16, 20, 255))
    for i in range(6):
        a = i / 6.0 * math.pi * 2
        x = 28 + math.cos(a) * 20
        y = 24 + math.sin(a) * 14
        d.line([(28, 24), (x, y)], fill=C("blood", 1.0, 150), width=1)
    _px(d, 24, 20, (255, 255, 255, 230))
    return im


def prop_bone_beam():
    im = _canvas(72, 18)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 5, 71, 15], fill=C("bone", 0.62))
    d.rectangle([0, 5, 71, 7], fill=C("bone", 0.82))
    d.rectangle([0, 13, 71, 15], fill=C("bone", 0.45))
    for i in range(4):
        x = 8 + i * 17
        d.ellipse([x, 3, x + 12, 17], fill=C("bone", 0.72))
        d.ellipse([x + 3, 7, x + 9, 13], fill=C("flesh_dark", 0.9))
    return im


def prop_hook():
    im = _canvas(18, 34)
    d = ImageDraw.Draw(im)
    d.rectangle([8, 0, 9, 20], fill=C("iron", 0.70))
    d.arc([2, 16, 16, 34], 200, 20, fill=C("iron", 0.78), width=3)
    return im


def prop_cage():
    im = _canvas(26, 34)
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 25, 2], fill=C("iron", 0.55))
    for i in range(4):
        x = 1 + i * 8
        d.rectangle([x, 2, x + 1, 33], fill=C("iron", 0.62))
    d.rectangle([0, 31, 25, 33], fill=C("iron", 0.50))
    d.rectangle([0, 12, 25, 13], fill=C("iron", 0.45))
    return im


NEW_PROPS = {
    "bars": prop_bars,
    "brazier": prop_brazier,
    "altar": prop_altar,
    "bone_pile": prop_bone_pile,
    "chain": prop_chain,
    "acid_pool": prop_acid_pool,
    "eye": prop_eye,
    "bone_beam": prop_bone_beam,
    "hook": prop_hook,
    "cage": prop_cage,
}


def build_props():
    os.makedirs(OUT_FURN, exist_ok=True)
    for name, fn in NEW_PROPS.items():
        fn().save(os.path.join(OUT_FURN, name + ".png"))
    print("props ->", len(NEW_PROPS), "files")


# ---------------------------------------------------------------- 样张
# 这些道具在第三层保持原样（学校残片）
RELIC = {"desk_small", "desk_office", "chair_a"}


def _furn_path(name):
    if name in RELIC:
        return os.path.join(SRC_FURN, name + ".png")
    p = os.path.join(OUT_FURN, name + ".png")
    return p if os.path.exists(p) else os.path.join(SRC_FURN, name + ".png")


class Mock:
    """把灰度图案按房型颜色拼成一张俯视房间图（模拟 school_map 的绘制方式）。"""

    def __init__(self, w_cells, h_cells):
        self.cw, self.ch = w_cells, h_cells
        self.img = Image.new("RGBA", (w_cells * TILE, h_cells * TILE), C("char"))
        self.atlas = Image.open(OUT_ATLAS).convert("L")

    def _tile(self, style_row, variant, color):
        src = self.atlas.crop((variant * TILE, style_row * TILE, (variant + 1) * TILE, (style_row + 1) * TILE))
        out = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
        sp, op = src.load(), out.load()
        for y in range(TILE):
            for x in range(TILE):
                v = sp[x, y] / 255.0
                op[x, y] = (
                    int(color[0] * v * 255),
                    int(color[1] * v * 255),
                    int(color[2] * v * 255),
                    255,
                )
        return out

    def room(self, rect, floor_style, floor_col, wall_style, wall_col, top_col):
        x0, y0, x1, y1 = rect
        rng = random.Random(7)
        for cy in range(self.ch):
            for cx in range(self.cw):
                inside = x0 <= cx < x1 and y0 <= cy < y1
                if inside:
                    t = self._tile(floor_style, rng.randrange(VARIANTS), floor_col)
                else:
                    t = self._tile(wall_style, rng.randrange(VARIANTS), wall_col)
                self.img.alpha_composite(t, (cx * TILE, cy * TILE))
        # 墙脚阴影：越靠墙越暗（模拟 school_map 的 WallShadow）
        for cy in range(y0, y1):
            for cx in range(x0, x1):
                dep = min(cx - x0, cy - y0, x1 - 1 - cx, y1 - 1 - cy)
                if dep >= 3:
                    continue
                fac = (0.52, 0.72, 0.88)[dep]
                for yy in range(cy * TILE, (cy + 1) * TILE):
                    for xx in range(cx * TILE, (cx + 1) * TILE):
                        r, g, b, a = self.img.getpixel((xx, yy))
                        self.img.putpixel((xx, yy), (int(r * fac), int(g * fac), int(b * fac), a))
        # 墙的亮顶边（贴着房间内侧的那一圈）
        d = ImageDraw.Draw(self.img)
        for cx in range(x0, x1):
            d.rectangle([cx * TILE, (y0 - 1) * TILE, cx * TILE + TILE - 1, (y0 - 1) * TILE + 1], fill=top_col)
        for cy in range(y0, y1):
            d.rectangle([(x0 - 1) * TILE, cy * TILE, (x0 - 1) * TILE + 1, cy * TILE + TILE - 1], fill=top_col)
            d.rectangle([(x1) * TILE - 2, cy * TILE, (x1) * TILE - 1, cy * TILE + TILE - 1],
                        fill=(int(top_col[0] * 0.45), int(top_col[1] * 0.45), int(top_col[2] * 0.45), 255))

    def prop(self, name, cx, cy):
        p = _furn_path(name)
        if not os.path.exists(p):
            return
        im = Image.open(p).convert("RGBA")
        px, py = int(cx * TILE), int(cy * TILE)
        # 影子
        d = ImageDraw.Draw(self.img)
        d.ellipse([px - 2, py + im.height - 6, px + im.width + 2, py + im.height + 3],
                  fill=(0, 0, 0, 90))
        self.img.alpha_composite(im, (px, py))

    def light(self, cx, cy, radius, tint, strength=0.55):
        """圆形照明：中心提亮、边缘压暗。"""
        w, h = self.img.size
        lx, ly = cx * TILE, cy * TILE
        px = self.img.load()
        r2 = (radius * TILE) ** 2
        for y in range(h):
            for x in range(w):
                d2 = (x - lx) ** 2 + (y - ly) ** 2
                if d2 < r2:
                    k = 1.0 - 0.30 * (d2 / r2)
                    r, g, b, a = px[x, y]
                    nr = r * k + tint[0] * strength * (1.0 - d2 / r2) * 0.5
                    ng = g * k + tint[1] * strength * (1.0 - d2 / r2) * 0.5
                    nb = b * k + tint[2] * strength * (1.0 - d2 / r2) * 0.5
                else:
                    f = 0.66
                    r, g, b, a = px[x, y]
                    nr, ng, nb = r * f, g * f, b * f
                px[x, y] = (min(255, int(nr)), min(255, int(ng)), min(255, int(nb)), a)

    def monster(self, name, cx, cy):
        p = os.path.join(ROOT, "art", "sprites", "monsters", name + "_walk_front.png")
        if not os.path.exists(p):
            return
        strip = Image.open(p).convert("RGBA")
        fw = strip.width // 4
        f = strip.crop((0, 0, fw, strip.height))
        f = f.resize((fw * 2, f.height * 2), Image.NEAREST)
        px, py = int(cx * TILE), int(cy * TILE)
        self.img.alpha_composite(f, (px, py))

    def save(self, path):
        self.img.convert("RGB").save(path)
        print("mock ->", os.path.relpath(path, ROOT), self.img.size)


def make_mocks():
    # ---- 地牢风：石砌 + 焦黑墙 + 炭盆 + 铁栅 + 祭坛；右下角留一张没塌的课桌
    m = Mock(52, 29)
    m.room((2, 3, 50, 27), 0, (0.62, 0.48, 0.47), 0, (0.34, 0.26, 0.33), C("bone", 0.38)[:3])
    for cy in (4, 10, 16, 22):
        m.prop("bars", 3, cy)
    m.prop("altar", 23, 12)
    m.prop("brazier", 39, 6)
    m.prop("brazier", 8, 21)
    m.prop("bone_pile", 15, 20)
    m.prop("crate_stack", 43, 20)
    m.prop("barrel", 36, 22)
    m.prop("chain", 33, 6)
    m.prop("hook", 30, 5)
    m.prop("stool_a", 20, 7)
    m.prop("desk_small", 26, 22)       # 偶现课桌：不腐化
    m.prop("chair_a", 26, 25)
    m.monster("skeleton", 12, 12)
    m.light(26, 14, 17, (150, 170, 120), 0.35)
    m.save(os.path.join(ROOT, "tests", "art_hell_dungeon.png"))

    # ---- 器官风：肉褶地面 + 肉墙 + 眼球 + 酸池 + 骨梁
    m = Mock(52, 29)
    m.room((2, 3, 50, 27), 4, (0.86, 0.55, 0.50), 1, (0.52, 0.26, 0.30), C("flesh", 0.85)[:3])
    m.prop("eye", 22, 10)
    m.prop("acid_pool", 4, 20)
    m.prop("acid_pool", 38, 19)
    m.prop("bone_beam", 8, 5)
    m.prop("bone_beam", 30, 23)
    m.prop("cage", 44, 6)
    m.prop("chain", 40, 10)
    m.prop("bone_pile", 15, 23)
    m.prop("stool_b", 32, 14)
    m.prop("desk_small", 44, 14)       # 偶现课桌：不腐化
    m.monster("puppet", 14, 15)
    m.light(24, 13, 17, (110, 170, 120), 0.32)
    m.save(os.path.join(ROOT, "tests", "art_hell_organ.png"))


def main():
    import sys
    args = set(sys.argv[1:])
    os.makedirs(os.path.dirname(OUT_ATLAS), exist_ok=True)
    if not args or "--atlas" in args:
        build_atlas()
    if not args or "--furn" in args:
        corrupt_furniture()
        build_props()
    if not args or "--mock" in args:
        make_mocks()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
