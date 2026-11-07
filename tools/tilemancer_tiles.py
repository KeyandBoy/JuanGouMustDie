"""Tilemancer 风格地板砖生成器（Python 原型 / 离线导出）。

Tilemancer 0.2.1 只有 GUI，没有命令行。这里按它的 Nodes/*.lua 复刻核心算法：
  - perlin_noise.lua  -> perlin()
  - cells.lua         -> cells()
  - bricks.lua        -> bricks()
  - blur.lua          -> blur()
  - directional_blur  -> dir_blur()
  - blend.lua         -> blend()
  - lighting.lua      -> lighting()
然后用 colorizer 的思路做「暗->亮」色带；游戏里再乘房间基色。

输出：art/sprites/floor/tilemancer_styles.png
  6 种风格 x 6 个变体，每格 20x20（灰度+光照，RGBA）
"""

import math
import os
import random

from PIL import Image

TILE = 20
VARIANTS = 6

# ---------------------------------------------------------------- helpers


def clamp01(v):
    return max(0.0, min(1.0, v))


def wrap(i, n):
    return i % n


def smooth(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def new_grid(v=0.0):
    return [[v] * TILE for _ in range(TILE)]


def sample(img, x, y):
    return img[wrap(int(y), TILE)][wrap(int(x), TILE)]


def norm3(x, y, z):
    l = math.sqrt(x * x + y * y + z * z)
    if l == 0:
        return 0.0, 0.0, 0.0
    return x / l, y / l, z / l


# ---------------------------------------------------------------- nodes


def perlin(seed, size=4, layers=3, lacunarity=200, gain=80, intensity=1.0):
    rng = random.Random(seed)
    out = [[0.0] * TILE for _ in range(TILE)]
    for ll in range(layers):
        gx = int(size * (lacunarity / 100.0) ** ll)
        gy = gx
        gx = max(2, gx)
        gy = max(2, gy)
        vx = [[0.0] * gx for _ in range(gy)]
        vy = [[0.0] * gx for _ in range(gy)]
        for y in range(gy):
            for x in range(gx):
                a = rng.uniform(-1, 1)
                b = rng.uniform(-1, 1)
                a, b = norm3(a, b, 0)[:2]
                if a == 0 and b == 0:
                    a = 1.0
                vx[y][x] = a
                vy[y][x] = b
        # 可平铺：右/下边界复制左/上
        for y in range(gy):
            vx[y][gx - 1] = vx[y][0]
            vy[y][gx - 1] = vy[y][0]
        for x in range(gx):
            vx[gy - 1][x] = vx[0][x]
            vy[gy - 1][x] = vy[0][x]
        stepx = TILE / (gx - 1)
        stepy = TILE / (gy - 1)
        for y in range(TILE):
            for x in range(TILE):
                gxi = min(int(x / stepx), gx - 2)
                gyi = min(int(y / stepy), gy - 2)
                d = []
                for ny in (0, 1):
                    for nx in (0, 1):
                        dx = (x - (gxi + nx) * stepx) / stepx
                        dy = (y - (gyi + ny) * stepy) / stepy
                        d.append(dx * vx[gyi + ny][gxi + nx] + dy * vy[gyi + ny][gxi + nx])
                ax = smooth((x - gxi * stepx) / stepx)
                ay = smooth((y - gyi * stepy) / stepy)
                top = d[0] * (1 - ax) + d[1] * ax
                bot = d[2] * (1 - ax) + d[3] * ax
                c = (top * (1 - ay) + bot * ay + 1.0) * 0.5
                if ll == 0:
                    out[y][x] = c
                else:
                    a = (gain / 100.0) ** ll
                    old = out[y][x]
                    c = c * a + old * (1 - a)
                    out[y][x] = old * (old + 2 * c * (1 - old))
    if intensity != 1.0:
        for y in range(TILE):
            for x in range(TILE):
                out[y][x] = clamp01(out[y][x] * intensity)
    return out


def cells(seed, size=2, falloff=25, intensity=1.0):
    rng = random.Random(seed)
    pts = [(rng.random(), rng.random()) for _ in range(size * size)]
    out = new_grid()
    for y in range(TILE):
        for x in range(TILE):
            nx = int(x / (TILE / size))
            ny = int(y / (TILE / size))
            fx = x / (TILE / size) - nx
            fy = y / (TILE / size) - ny
            md = 100.0
            mrx = mry = 0.0
            mgx = mgy = 0
            for i in (-1, 0, 1):
                for j in (-1, 0, 1):
                    idx = wrap(ny + j, size) * size + wrap(nx + i, size)
                    dx = i + pts[idx][0] - fx
                    dy = j + pts[idx][1] - fy
                    d = dx * dx + dy * dy
                    if d < md:
                        md = d
                        mrx, mry = dx, dy
                        mgx, mgy = i, j
            md = 100.0
            for i in range(-2, 3):
                for j in range(-2, 3):
                    idx = wrap(ny + j + mgy, size) * size + wrap(nx + i + mgx, size)
                    dx = i + mgx + pts[idx][0] - fx
                    dy = j + mgy + pts[idx][1] - fy
                    ex, ey = mrx - dx, mry - dy
                    if ex * ex + ey * ey > 0.00001:
                        hx, hy = 0.5 * (mrx + dx), 0.5 * (mry + dy)
                        nx2, ny2, _ = norm3(dx - mrx, dy - mry, 0)
                        md = min(md, hx * nx2 + hy * ny2)
            out[y][x] = clamp01(md / falloff) * intensity
    return out


def bricks(seed, grid=2, max_w=1, max_h=1, falloff=50, intensity=1.0):
    """简化版 bricks.lua：grid x grid 块砖；缝隙=0，砖面=1，边缘 2px 倒角。"""
    rng = random.Random(seed)
    w = TILE / grid
    tone = [[rng.uniform(-0.06, 0.10) for _ in range(grid)] for _ in range(grid)]
    bevel = max(1.0, w * 0.18)
    out = new_grid()
    for y in range(TILE):
        for x in range(TILE):
            gx = min(int(x / w), grid - 1)
            gy = min(int(y / w), grid - 1)
            lx = x - gx * w
            ly = y - gy * w
            edge = min(lx, ly, w - lx, w - ly)
            # 缝隙
            h = clamp01((edge - 0.5) / bevel)
            out[y][x] = clamp01((h + tone[gy][gx]) * intensity)
    return out


def blur(img, intensity):
    radius = int(TILE * intensity)
    if radius <= 0:
        return [row[:] for row in img]
    b = 1.0 / (math.sqrt(2.0 * math.pi) * radius)
    kernel = []
    total = 0.0
    for i in range(radius * 2 + 1):
        r = i - radius
        v = b * math.exp(-(r * r) * b)
        kernel.append(v)
        total += v
    kernel = [k / total for k in kernel]
    tmp = new_grid()
    for y in range(TILE):
        for x in range(TILE):
            s = 0.0
            for k in range(radius * 2 + 1):
                s += sample(img, x - radius + k, y) * kernel[k]
            tmp[y][x] = s
    out = new_grid()
    for y in range(TILE):
        for x in range(TILE):
            s = 0.0
            for k in range(radius * 2 + 1):
                s += sample(tmp, x, y - radius + k) * kernel[k]
            out[y][x] = s
    return out


def dir_blur(img, direction, intensity):
    """direction 0..1（对应 0..360°），intensity 0..1。"""
    dist = TILE * intensity
    samples = max(1, int(dist))
    ang = direction * 360.0 * math.pi / 180.0
    dx, dy, _ = norm3(math.sin(ang), -math.cos(ang), 0)
    out = new_grid()
    for y in range(TILE):
        for x in range(TILE):
            s = 0.0
            for k in range(samples):
                s += sample(img, x + dx * dist * k / samples, y + dy * dist * k / samples)
            out[y][x] = s / samples
    return out


def blend(a, b, mode, factor=1.0):
    out = new_grid()
    for y in range(TILE):
        for x in range(TILE):
            ar, br = a[y][x], b[y][x]
            if mode == 0:
                v = ar + br * factor
            elif mode == 1:
                v = ar - br * factor
            elif mode == 2:
                v = ar * (br * factor + (1 - factor))
            elif mode == 3:
                v = ar / max(0.0001, br * factor + (1 - factor))
            elif mode == 4:
                v = min(ar, br * factor)
            else:
                v = max(ar, br * factor)
            out[y][x] = v
    return out


def lighting(height, direction=-22.0, ao_intensity=10.0):
    ao = blur(height, ao_intensity / 100.0)
    ang = direction * math.pi / 180.0
    lx, ly, lz = norm3(math.sin(ang), -math.cos(ang), 0.2)
    out = new_grid()
    for y in range(TILE):
        for x in range(TILE):
            s11 = sample(height, x, y)
            s01 = sample(height, x - 1, y)
            s21 = sample(height, x + 1, y)
            s10 = sample(height, x, y - 1)
            s12 = sample(height, x, y + 1)
            vax, vay, vaz = norm3(64.0 / TILE, 0, (s21 - s01) * 3.6)
            vbx, vby, vbz = norm3(0, 64.0 / TILE, (s12 - s10) * 3.6)
            nx, ny, nz = norm3(vay * vbz - vaz * vby,
                               vaz * vbx - vax * vbz,
                               vax * vby - vay * vbx)
            d = clamp01(lx * nx + ly * ny + lz * nz)
            aoc = clamp01(s11 + 1.0 - ao[y][x])
            out[y][x] = d * aoc
    return out


# ---------------------------------------------------------------- styles


def style_wood(seed):
    h = bricks(seed, grid=2, falloff=70, intensity=1.0)
    grain = perlin(seed + 11, size=3, layers=4, lacunarity=200, gain=70)
    h = blend(h, grain, mode=2, factor=0.45)
    h = blur(h, 0.06)
    return lighting(h, -22.0, 8.0)


def style_tile(seed):
    h = bricks(seed, grid=2, falloff=45, intensity=1.0)
    n = perlin(seed + 21, size=5, layers=3, gain=80)
    h = blend(h, n, mode=2, factor=0.35)  # multiply，轻微脏污
    h = blur(h, 0.06)
    return lighting(h, -22.0, 8.0)


def style_concrete(seed):
    c = cells(seed, size=3, falloff=0.30, intensity=1.0)
    n = perlin(seed + 31, size=5, layers=4, gain=70)
    h = blend(c, n, mode=2, factor=0.30)
    h = blur(h, 0.13)
    return lighting(h, -22.0, 12.0)


def style_stone(seed):
    c = cells(seed, size=2, falloff=0.24, intensity=1.0)
    n = perlin(seed + 41, size=4, layers=4, gain=75)
    h = blend(c, n, mode=2, factor=0.35)
    h = blur(h, 0.13)
    return lighting(h, -22.0, 12.0)


def style_sand(seed):
    c = cells(seed, size=3, falloff=0.38, intensity=0.7)
    inv = [[1.0 - c[y][x] for x in range(TILE)] for y in range(TILE)]
    d = dir_blur(inv, 0.6, 0.3)
    d = blur(d, 0.10)
    n = perlin(seed + 51, size=8, layers=6, gain=90, intensity=0.35)
    h = blend(d, n, mode=0)
    return lighting(h, -22.0, 6.0)


def style_carpet(seed):
    n = perlin(seed, size=6, layers=5, gain=60)
    h = [[0.55 + 0.35 * n[y][x] for x in range(TILE)] for y in range(TILE)]
    h = blur(h, 0.05)
    return lighting(h, -22.0, 4.0)


STYLES = [
    ("wood", style_wood),
    ("tile", style_tile),
    ("concrete", style_concrete),
    ("stone", style_stone),
    ("sand", style_sand),
    ("carpet", style_carpet),
]

# 键：下面这行给 GDScript 用的风格索引
STYLE_ORDER = [s[0] for s in STYLES]


def to_image(light):
    im = Image.new("RGBA", (TILE, TILE))
    px = im.load()
    for y in range(TILE):
        for x in range(TILE):
            v = clamp01(light[y][x])
            # 亮度 0.55..1.12：游戏里再乘房间基色
            k = 0.50 + 0.66 * v
            r = g = b = int(max(0, min(255, k * 255)))
            px[x, y] = (r, g, b, 255)
    return im


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "art", "sprites", "floor")
    os.makedirs(out_dir, exist_ok=True)
    atlas = Image.new("RGBA", (TILE * VARIANTS, TILE * len(STYLES)), (0, 0, 0, 255))
    for si, (name, fn) in enumerate(STYLES):
        for v in range(VARIANTS):
            seed = 1000 + si * 97 + v * 31
            img = to_image(fn(seed))
            atlas.paste(img, (v * TILE, si * TILE))
            img.save(os.path.join(out_dir, f"{name}_{v}.png"))
    atlas.save(os.path.join(out_dir, "tilemancer_styles.png"))
    print("saved", os.path.join(out_dir, "tilemancer_styles.png"), atlas.size)

    # 预览：每种风格 4x4 平铺，再放大 6 倍
    scale = 6
    pad = 8
    pw = TILE * 4 * scale
    preview = Image.new("RGB", (pw * len(STYLES) + pad * (len(STYLES) + 1),
                                pw + 2 * pad), (30, 32, 38))
    for si, (name, fn) in enumerate(STYLES):
        tile = to_image(fn(1000 + si * 97))
        big = tile.resize((TILE * scale, TILE * scale), Image.NEAREST)
        ox = pad + si * (pw + pad)
        for ty in range(4):
            for tx in range(4):
                preview.paste(big, (ox + tx * TILE * scale, pad + ty * TILE * scale))
    prev_path = os.path.join(out_dir, "tilemancer_preview.png")
    preview.save(prev_path)
    print("saved", prev_path, preview.size)


if __name__ == "__main__":
    main()
