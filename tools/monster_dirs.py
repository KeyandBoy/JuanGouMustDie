"""把「单张正面像素怪」加工成 4 方向行走条带（front / back / left / right）。

用法：
    python tools\\monster_dirs.py

输出到 ``art/sprites/monsters/<name>_walk_<dir>.png``（每个方向 4 帧横排）。

加工思路（不改原画，只做可复现的像素处理）：
- front：原图裁掉透明边 → 等比缩放到画布 → 底部居中
- left / right：front 的水平镜像（同源素材只有正面，左右互为镜像）
- back：把「脸」那块矩形内的不透明像素填成同族颜色（从脸上/头发/头盔取样），
  保留外轮廓，再整体压暗 6%，读起来就是后脑勺
- 走路 4 帧：上半身整体上抬 1px + 下半身左右各错 1px（f1/f3），中间两帧回正
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "art", "sprites", "monsters")

# canvas: 单帧画布；fill: 内容占画布高度比例；patch: [(x0,y0,x1,y1, 取样点x, 取样点y)]（原图坐标）
MONSTERS = {
    "skeleton": {
        "src": os.path.join(ROOT, "素材", "怪物", "Skeleton.png"),
        "canvas": (96, 96),
        "fill": 0.92,
        "patch": [(56, 4, 80, 30)],
        "dark": 0.94,
    },
    "zombie": {
        "src": os.path.join(ROOT, "素材", "怪物", "zombie.png"),
        "canvas": (64, 64),
        "fill": 0.94,
        "patch": [(25, 8, 44, 27)],
        "dark": 0.94,
    },
    "puppet": {
        "src": os.path.join(ROOT, "素材", "怪物", "puppet.png"),
        "canvas": (96, 96),
        "fill": 0.90,
        "patch": [(51, 21, 85, 50), (46, 18, 92, 24)],
        "dark": 0.94,
    },
    "minotaur": {
        "src": os.path.join(ROOT, "素材", "怪物", "minotaur.png"),
        "canvas": (112, 112),
        "fill": 0.93,
        "patch": [(50, 28, 84, 60), (54, 22, 80, 30)],
        "dark": 0.95,
    },
}


def dominant_color(im: Image.Image, rect) -> tuple:
    """取矩形内「不透明且不太黑」的最常见颜色（避开描边/眼睛）。"""
    px = im.load()
    x0, y0, x1, y1 = rect
    counts = {}
    for y in range(y0, min(y1, im.height)):
        for x in range(x0, min(x1, im.width)):
            r, g, b, a = px[x, y]
            if a <= 8:
                continue
            if (r * 0.299 + g * 0.587 + b * 0.114) < 38:
                continue
            key = (r, g, b)
            counts[key] = counts.get(key, 0) + 1
    if not counts:
        return (128, 128, 128, 255)
    best = max(counts.items(), key=lambda kv: kv[1])[0]
    return (best[0], best[1], best[2], 255)


def patch_back(im: Image.Image, patches) -> Image.Image:
    """把脸部矩形内的不透明像素压成同族颜色（保留外轮廓），加一点上下明暗。"""
    out = im.copy()
    px = out.load()
    for rect in patches:
        x0, y0, x1, y1 = rect
        fill = dominant_color(im, rect)
        lighter = (min(255, int(fill[0] * 1.10)), min(255, int(fill[1] * 1.10)), min(255, int(fill[2] * 1.10)), 255)
        darker = (int(fill[0] * 0.82), int(fill[1] * 0.82), int(fill[2] * 0.82), 255)
        for y in range(y0, min(y1, out.height)):
            for x in range(x0, min(x1, out.width)):
                r, g, b, a = px[x, y]
                if a <= 8:
                    continue
                rel_y = (y - y0) / max(1.0, float(y1 - y0))
                if rel_y < 0.12:
                    px[x, y] = lighter
                elif rel_y > 0.82:
                    px[x, y] = darker
                else:
                    px[x, y] = fill
    return out


def compose(im: Image.Image, canvas, fill_ratio: float) -> Image.Image:
    """裁透明边 → 等比缩放到画布 → 底部居中。"""
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    cw, ch = canvas
    max_w = cw - 4
    max_h = int(ch * fill_ratio)
    scale = min(max_w / float(im.width), max_h / float(im.height))
    w = max(1, int(round(im.width * scale)))
    h = max(1, int(round(im.height * scale)))
    im = im.resize((w, h), Image.NEAREST)
    out = Image.new("RGBA", canvas, (0, 0, 0, 0))
    out.alpha_composite(im, ((cw - w) // 2, ch - 2 - h))
    return out


def make_frame(base: Image.Image, top_dy: int, legs_dx: int) -> Image.Image:
    """上半身整体上抬 top_dy，下半身横移 legs_dx；下半身先贴、上半身后贴，避免接缝。"""
    w, h = base.size
    split = int(h * 0.70)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    legs = base.crop((0, split, w, h))
    out.alpha_composite(legs, (legs_dx, split))
    top = base.crop((0, 0, w, split + 2))
    out.alpha_composite(top, (0, top_dy))
    return out


def darken(im: Image.Image, mul: float) -> Image.Image:
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (int(r * mul), int(g * mul), int(b * mul), a)
    return im


def build(name: str, cfg: dict) -> None:
    src = Image.open(cfg["src"]).convert("RGBA")
    front_src = src
    back_src = darken(patch_back(src, cfg["patch"]), cfg.get("dark", 0.94))

    front = compose(front_src, cfg["canvas"], cfg["fill"])
    back = compose(back_src, cfg["canvas"], cfg["fill"])
    left = front.transpose(Image.FLIP_LEFT_RIGHT)
    right = front

    dirs = {"front": front, "back": back, "left": left, "right": right}
    os.makedirs(OUT_DIR, exist_ok=True)
    for d, img in dirs.items():
        w, h = img.size
        strip = Image.new("RGBA", (w * 4, h), (0, 0, 0, 0))
        # 4 帧：站立 / 上抬+腿右 / 站立 / 上抬+腿左
        frames = [make_frame(img, 0, 0), make_frame(img, -1, 1), make_frame(img, 0, 0), make_frame(img, -1, -1)]
        for i, f in enumerate(frames):
            strip.alpha_composite(f, (i * w, 0))
        path = os.path.join(OUT_DIR, "%s_walk_%s.png" % (name, d))
        strip.save(path)
        print("wrote", os.path.relpath(path, ROOT), strip.size)


def main() -> int:
    for name, cfg in MONSTERS.items():
        if not os.path.exists(cfg["src"]):
            print("MISSING", cfg["src"], file=sys.stderr)
            return 1
        build(name, cfg)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
