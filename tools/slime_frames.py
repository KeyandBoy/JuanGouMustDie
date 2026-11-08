"""把 MonsterGirl 的史莱姆 4 帧条带加工成游戏用的 4 方向条带。

源文件是 128×32（4 帧 × 32×32），只有正面朝向。
- front = 原条带
- left  = 水平镜像
- right = 原条带
- back  = 原条带整体压暗 14%（史莱姆没有背面细节，靠明暗区分）

输出：``art/sprites/monsters/slime_XX_walk_{front,back,left,right}.png``（128×32）
编号：01~05 = Human（Dark/Fire/Ice/Nature/Water），06~10 = Mix，11~15 = Monster。
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "素材", "怪物", "MonsterGirl_0.1")
OUT = os.path.join(ROOT, "art", "sprites", "monsters")

TYPES = [("Human", 1), ("Mix", 6), ("Monster", 11)]
COLORS = ["Dark", "Fire", "Ice", "Nature", "Water"]


def darken(im: Image.Image, mul: float) -> Image.Image:
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (int(r * mul), int(g * mul), int(b * mul), a)
    return im


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    for tname, start in TYPES:
        for ci, cname in enumerate(COLORS):
            src = os.path.join(SRC, "Slime_%s_%s.png" % (tname, cname))
            if not os.path.exists(src):
                print("MISSING", src)
                return 1
            im = Image.open(src).convert("RGBA")
            if im.size != (128, 32):
                print("UNEXPECTED SIZE", src, im.size)
                return 1
            frames = [im.crop((i * 32, 0, (i + 1) * 32, 32)) for i in range(4)]
            front = Image.new("RGBA", (128, 32), (0, 0, 0, 0))
            for i, f in enumerate(frames):
                front.alpha_composite(f, (i * 32, 0))
            left = front.transpose(Image.FLIP_LEFT_RIGHT)
            right = front
            back = darken(front.copy(), 0.86)
            n = start + ci
            for d, img in [("front", front), ("back", back), ("left", left), ("right", right)]:
                path = os.path.join(OUT, "slime_%02d_walk_%s.png" % (n, d))
                img.save(path)
                print("wrote", os.path.relpath(path, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
