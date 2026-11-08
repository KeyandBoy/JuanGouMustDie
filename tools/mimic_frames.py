"""宝箱怪（Mimic）：把 4 张单帧 100×100 的宝箱怪做成 4 方向 × 4 帧条带。

- front = 原图裁透明边、等比缩放到 96×96
- left / right = 镜像 / 原样
- back = 整体压暗 10%
- 4 帧：整体上下 1px 呼吸（蹲着的时候只播第 0 帧，看起来就是个箱子）

输出：``art/sprites/monsters/mimic_01..04_walk_{front,back,left,right}.png``
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "素材", "怪物")
OUT = os.path.join(ROOT, "art", "sprites", "monsters")
CANVAS = (96, 96)
FILES = ["Mimic.gif", "Green-Mimic.gif", "Blue-Mimic.gif", "Corrupt-Mimic.gif"]


def compose(im: Image.Image) -> Image.Image:
    bbox = im.getbbox()
    if bbox:
        im = im.crop(bbox)
    cw, ch = CANVAS
    max_w = cw - 4
    max_h = int(ch * 0.94)
    scale = min(max_w / float(im.width), max_h / float(im.height))
    w = max(1, int(round(im.width * scale)))
    h = max(1, int(round(im.height * scale)))
    im = im.resize((w, h), Image.NEAREST)
    out = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    out.alpha_composite(im, ((cw - w) // 2, ch - 2 - h))
    return out


def darken(im: Image.Image, mul: float) -> Image.Image:
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (int(r * mul), int(g * mul), int(b * mul), a)
    return im


def bump(im: Image.Image, dy: int) -> Image.Image:
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(im, (0, dy))
    return out


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    for i, f in enumerate(FILES, 1):
        src = os.path.join(SRC, f)
        if not os.path.exists(src):
            print("MISSING", src)
            return 1
        im = Image.open(src).convert("RGBA")
        front = compose(im)
        back = darken(compose(im), 0.90)
        left = front.transpose(Image.FLIP_LEFT_RIGHT)
        right = front
        for d, img in [("front", front), ("back", back), ("left", left), ("right", right)]:
            strip = Image.new("RGBA", (CANVAS[0] * 4, CANVAS[1]), (0, 0, 0, 0))
            for k, dy in enumerate([0, -1, 0, 1]):
                strip.alpha_composite(bump(img, dy), (k * CANVAS[0], 0))
            path = os.path.join(OUT, "mimic_%02d_walk_%s.png" % (i, d))
            strip.save(path)
            print("wrote", os.path.relpath(path, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
