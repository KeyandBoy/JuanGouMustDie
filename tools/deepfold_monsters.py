"""Deep-Fold 的 Pixel Sprite Generator 离线移植（MIT）。

算法来源：https://github.com/Deep-Fold/SpriteGenerator （Godot 3，MIT License）
原工具：https://deep-fold.itch.io/pixel-sprite-generator

这里只做“生成 + 导出 PNG”，保留原版的核心：
  MapGenerator      对称随机块 + 2 次随机游走
  CellularAutomata  4 步（birth>5 / death<4）
  ColorScheme       余弦调色板（Inigo Quilez palette）
  ColorFiller       洪水填充 + 噪声选色 + 描边 + 空洞当眼睛
  GroupDrawer       丢弃小于最大组 25% 的碎块；贴边空洞不作为眼睛

差异：Godot 的 OpenSimplexNoise 用纯 Python 的 Perlin 噪声代替（只影响花纹，
不影响怪物轮廓/眼睛结构）；RNG 也用 Python random，所以同一个 seed 不会和
Godot 原工具逐像素一致。

用法：
  python tools/deepfold_monsters.py --count 30 --size 48
  python tools/deepfold_monsters.py --seed 7 --size 64 --out art/sprites/monsters/one.png
"""

import argparse
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "art", "sprites", "monsters")

BIRTH = 5
DEATH = 4
STEPS = 4
N_COLORS = 12
OUTLINE = True


# ------------------------------------------------------------------ Perlin


class Perlin:
    """一维/二维 Perlin 噪声，替代 Godot 的 OpenSimplexNoise。"""

    def __init__(self, seed):
        rnd = random.Random(seed)
        p = list(range(256))
        rnd.shuffle(p)
        self.p = p + p

    @staticmethod
    def _fade(t):
        return t * t * t * (t * (t * 6 - 15) + 10)

    def _grad(self, h, x, y):
        h &= 3
        if h == 0:
            return x + y
        if h == 1:
            return -x + y
        if h == 2:
            return x - y
        return -x - y

    def noise2(self, x, y):
        xi, yi = math.floor(x) & 255, math.floor(y) & 255
        xf, yf = x - math.floor(x), y - math.floor(y)
        u, v = self._fade(xf), self._fade(yf)
        p = self.p
        aa = p[p[xi] + yi]
        ab = p[p[xi] + yi + 1]
        ba = p[p[xi + 1] + yi]
        bb = p[p[xi + 1] + yi + 1]
        x1 = self._grad(aa, xf, yf) * (1 - u) + self._grad(ba, xf - 1, yf) * u
        x2 = self._grad(ab, xf, yf - 1) * (1 - u) + self._grad(bb, xf - 1, yf - 1) * u
        return (x1 * (1 - v) + x2 * v) * 0.7


class Noise2:
    """两层不同频率的噪声，对应原版 noise / noise2。"""

    def __init__(self, seed):
        self.a = Perlin(seed)
        self.b = Perlin(seed + 991)

    def n1(self, x, y):
        return self.a.noise2(x * 0.08, y * 0.08)

    def n2(self, x, y):
        return (self.b.noise2(x * 0.05, y * 0.05) * 0.6 +
                self.b.noise2(x * 0.15, y * 0.15) * 0.3 +
                self.b.noise2(x * 0.45, y * 0.45) * 0.1)


# ------------------------------------------------------------------ 地图


def rand_bool(rnd, chance):
    return rnd.random() > chance


def random_map(rnd, size):
    w, h = size
    m = [[False] * h for _ in range(w)]
    half = math.ceil(w * 0.5)
    center_a = math.floor(w * 0.5) - 1
    center_b = math.floor(w * 0.5) - 2
    for x in range(half):
        arr = []
        for y in range(h):
            filled = rand_bool(rnd, 0.48)
            to_center = (abs(y - h * 0.5) * 2.0) / h
            if x == center_a or x == center_b:
                if rnd.uniform(0.0, 0.4) > to_center:
                    filled = True
            arr.append(filled)
        m[x] = list(arr)
        m[w - x - 1] = list(arr)
    return m


def set_at(m, pos, val):
    x, y = pos
    if x < 0 or x >= len(m) or y < 0 or y >= len(m[x]):
        return False
    m[x][y] = val
    return True


def random_walk(rnd, size, m):
    w, h = size
    pos = [rnd.randrange(w), rnd.randrange(h)]
    for _ in range(100):
        set_at(m, pos, True)
        set_at(m, (w - pos[0] - 1, pos[1]), True)
        pos[0] += rnd.randrange(3) - 1
        pos[1] += rnd.randrange(3) - 1


def generate_map(rnd, size):
    m = random_map(rnd, size)
    for _ in range(2):
        random_walk(rnd, size, m)
    return m


def get_at(m, x, y):
    if x < 0 or x >= len(m) or y < 0 or y >= len(m[x]):
        return None
    return m[x][y]


def ca_steps(m):
    for _ in range(STEPS):
        dup = [row[:] for row in m]
        for x in range(len(m)):
            for y in range(len(m[x])):
                n = 0
                for i in (-1, 0, 1):
                    for j in (-1, 0, 1):
                        if i == 0 and j == 0:
                            continue
                        if get_at(m, x + i, y + j):
                            n += 1
                if m[x][y] and n < DEATH:
                    dup[x][y] = False
                elif not m[x][y] and n > BIRTH:
                    dup[x][y] = True
        m = dup
    return m


# ------------------------------------------------------------------ 调色


# 猎奇配色：不改变 Deep-Fold 的轮廓/眼睛算法，只把随机余弦调色板换成
# 「血肉 / 尸绿 / 虚空」渐变，让生成物更像病变组织而不是彩色小怪物。
MOODS = {
    "flesh": {
        "body": ["#14080a", "#3a1016", "#6e2028", "#a8443e", "#d08168", "#e8b49a"],
        "eye": ["#120806", "#4a2a10", "#9a7a20", "#e8d060"],
    },
    "necro": {
        "body": ["#0c120e", "#1e2a1c", "#3c4c30", "#66744a", "#96a06e", "#c0c49a"],
        "eye": ["#140606", "#4a0e0e", "#9a1c1c", "#e83a2a"],
    },
    "void": {
        "body": ["#08080e", "#141428", "#2c2c50", "#4e4e7c", "#7a7aac", "#adb0d4"],
        "eye": ["#100612", "#3a1050", "#7a20a0", "#d060ff"],
    },
}


def gradient_scheme(anchors, n=N_COLORS):
    cols = []
    rgb = []
    for a in anchors:
        a = a.lstrip("#")
        rgb.append(tuple(int(a[i:i + 2], 16) / 255.0 for i in (0, 2, 4)))
    for i in range(n):
        t = i / float(n - 1)
        pos = t * (len(rgb) - 1)
        i0 = min(int(pos), len(rgb) - 2)
        f = pos - i0
        cols.append(tuple(rgb[i0][k] * (1 - f) + rgb[i0 + 1][k] * f for k in range(3)))
    return cols


def make_scheme(rnd, n=N_COLORS):
    a = [rnd.uniform(0.0, 0.5) for _ in range(3)]
    b = [rnd.uniform(0.1, 0.6) for _ in range(3)]
    c = [rnd.uniform(0.15, 0.8) for _ in range(3)]
    d = [rnd.uniform(0.0, 1.0) for _ in range(3)]
    cols = []
    for i in range(n):
        t = i / float(n - 1)
        rgb = []
        for k in range(3):
            v = a[k] + b[k] * math.cos(6.28318 * (c[k] * t + d[k])) + t * 0.8
            rgb.append(min(1.0, max(0.0, v)))
        cols.append(tuple(rgb))
    return cols


# ------------------------------------------------------------------ 填色


def flood_fill(m, scheme, eye_scheme, noise, is_negative=False):
    w, h = len(m), len(m[0])
    checked = [[False] * h for _ in range(w)]
    groups = []

    def edge(pos):
        x, y = pos
        if x < 0 or x >= w or y < 0 or y >= h:
            return None
        return m[x][y]

    def color_at(pos, right, left, down, up, group):
        x, y = pos
        col_x = math.ceil(abs(x - (w - 1) * 0.5))
        n = pow(abs(noise.n1(col_x, y)), 1.5) * 3.0
        n2 = pow(abs(noise.n2(col_x, y)), 1.5) * 3.0

        if not down:
            n = (n - (0.1 if is_negative else 0.45))
            n *= 0.8
            if OUTLINE:
                group.append({"p": (x, y + 1), "c": (0.0, 0.0, 0.0)})
        if not right:
            n = (n + (0.1 if is_negative else 0.2))
            n *= 1.1
            if OUTLINE:
                group.append({"p": (x + 1, y), "c": (0.0, 0.0, 0.0)})
        if not up:
            n = (n + (0.15 if is_negative else 0.45))
            n *= 1.2
            if OUTLINE:
                group.append({"p": (x, y - 1), "c": (0.0, 0.0, 0.0)})
        if not left:
            n = (n + (0.1 if is_negative else 0.2))
            n *= 1.1
            if OUTLINE:
                group.append({"p": (x - 1, y), "c": (0.0, 0.0, 0.0)})

        def idx(v):
            k = int(math.floor(v * (N_COLORS - 1))) % N_COLORS
            return k

        c0 = scheme[idx(noise.n1(col_x, y))]
        c1 = scheme[idx(noise.n1(col_x, y - 1))]
        c2 = scheme[idx(noise.n1(col_x, y + 1))]
        c3 = scheme[idx(noise.n1(col_x - 1, y))]
        c4 = scheme[idx(noise.n1(col_x + 1, y))]
        diff = (sum(abs(c0[k] - c1[k]) for k in range(3)) +
                sum(abs(c0[k] - c2[k]) for k in range(3)) +
                sum(abs(c0[k] - c3[k]) for k in range(3)) +
                sum(abs(c0[k] - c4[k]) for k in range(3)))
        if diff > 2.0:
            n = (n + 0.3) * 1.5
            n2 = (n2 + 0.3) * 1.5

        n = min(1.0, max(0.0, n))
        n2 = min(1.0, max(0.0, n2))
        col = (eye_scheme if is_negative else scheme)[idx(n2 if is_negative else n)]
        return col

    for x in range(w):
        for y in range(h):
            if checked[x][y]:
                continue
            checked[x][y] = True
            if not m[x][y]:
                continue

            group = {"cells": [], "valid": True}
            bucket = [(x, y)]
            while bucket:
                pos = bucket.pop()
                px, py = pos
                right = edge((px + 1, py))
                left = edge((px - 1, py))
                down = edge((px, py + 1))
                up = edge((px, py - 1))
                if is_negative and (right is None or left is None or down is None or up is None):
                    group["valid"] = False
                col = color_at(pos, right, left, down, up, group["cells"])
                group["cells"].append({"p": pos, "c": col})
                for nxt, ok in (((px + 1, py), right), ((px - 1, py), left),
                                ((px, py + 1), down), ((px, py - 1), up)):
                    if ok and not checked[nxt[0]][nxt[1]]:
                        checked[nxt[0]][nxt[1]] = True
                        bucket.append(nxt)
            groups.append(group)
    return groups


# ------------------------------------------------------------------ 渲染


def _touching(g1, g2):
    for c1 in g1:
        for c2 in g2:
            x1, y1 = c1["p"]
            x2, y2 = c2["p"]
            if x1 == x2 and abs(y1 - y2) == 1:
                return True
            if y1 == y2 and abs(x1 - x2) == 1:
                return True
    return False


def render(seed, size=48, mood=None):
    rnd = random.Random(seed)
    noise = Noise2(seed)

    m = generate_map(rnd, size)
    m = ca_steps(m)
    if mood and mood in MOODS:
        scheme = gradient_scheme(MOODS[mood]["body"])
        eye_scheme = gradient_scheme(MOODS[mood]["eye"])
    else:
        scheme = make_scheme(rnd)
        eye_scheme = make_scheme(rnd)

    groups = flood_fill(m, scheme, eye_scheme, noise, False)
    negative = flood_fill([[not v for v in row] for row in m], scheme, eye_scheme, noise, True)

    w, h = size
    img = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    px = img.load()

    def put(p, c):
        x, y = p
        if 0 <= x + 1 < w + 2 and 0 <= y + 1 < h + 2:
            px[x + 1, y + 1] = (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), 255)

    largest = max(len(g["cells"]) for g in groups)
    keep = [g for g in groups if len(g["cells"]) >= largest * 0.25]
    # 原版 GroupDrawer 从后往前添加子节点；这里按同样顺序画，描边重叠时后画的在上
    for g in reversed(keep):
        for cell in g["cells"]:
            put(cell["p"], cell["c"])

    for g in negative:
        if not g["valid"]:
            continue
        if not any(_touching(g["cells"], k["cells"]) for k in keep):
            continue
        cells = g["cells"]
        eye = (len(cells) + len(negative)) % 5 >= 3
        if eye and cells:
            ax = sum(c["p"][0] for c in cells) / len(cells)
            ay = sum(c["p"][1] for c in cells) / len(cells)
            cutoff = math.sqrt(len(cells)) * 0.3
            for c in cells:
                if math.hypot(ax - c["p"][0], ay - c["p"][1]) < cutoff:
                    c = {"p": c["p"], "c": tuple(v * 0.15 for v in c["c"])}
                put(c["p"], c["c"])
        else:
            for c in cells:
                put(c["p"], c["c"])
    return img


# ------------------------------------------------------------------ 输出


def save_sheet(items, path, scale=4):
    from PIL import ImageDraw
    cell = max(im.width for _, im in items)
    pad = 6
    cols = min(6, len(items))
    rows = math.ceil(len(items) / cols)
    cw = cell * scale
    out = Image.new("RGBA", (cols * (cw + pad) + pad, rows * (cw + 20) + pad),
                    (28, 30, 36, 255))
    d = ImageDraw.Draw(out)
    for i, (seed, im) in enumerate(items):
        x = pad + (i % cols) * (cw + pad)
        y = pad + (i // cols) * (cw + 20)
        d.text((x, y), "seed %d" % seed, fill=(255, 220, 120, 255))
        out.alpha_composite(im.resize((im.width * scale, im.height * scale), Image.NEAREST),
                            (x, y + 14))
    out.convert("RGB").save(path)
    print("saved", path, out.size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=30)
    ap.add_argument("--start", type=int, default=1)
    ap.add_argument("--size", type=int, default=48)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--mood", default="",
                    help="留空 = 原版随机调色板；flesh / necro / void / all（轮换）")
    ap.add_argument("--prefix", default="monster")
    ap.add_argument("--sheet", default="monsters_sheet.png")
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)

    def mood_for(i):
        if args.mood == "all":
            return ["flesh", "necro", "void"][i % 3]
        return args.mood

    if args.seed is not None:
        mood = mood_for(0)
        im = render(args.seed, (args.size, args.size), mood)
        path = args.out or os.path.join(OUT_DIR, "%s_%d.png" % (args.prefix, args.seed))
        im.save(path)
        print("saved", path, im.size, "mood=", mood)
        return

    items = []
    for i in range(args.count):
        seed = args.start + i
        mood = mood_for(i)
        im = render(seed, (args.size, args.size), mood)
        path = os.path.join(OUT_DIR, "%s_%02d.png" % (args.prefix, seed))
        im.save(path)
        items.append((seed, im))
    save_sheet(items, os.path.join(OUT_DIR, args.sheet))
    print("generated", len(items), "monsters ->", OUT_DIR)


if __name__ == "__main__":
    main()
