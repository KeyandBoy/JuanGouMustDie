"""残影（echo）素材：把学生行走帧压成暗紫剪影。

第三层的"残影"不是敌人，是环境演出（见 `设计_第三层世界_11-15F.md` §7.1）：
走廊尽头有个人影走过、背对你排队、在黑里招手——追过去什么都没有。

为了不引入新美术，直接用第一层学生的行走/站立帧做剪影：
- 保留 alpha 轮廓，颜色换成暗紫（上浅下深，像背光）
- 边缘提亮 1 格做"微光"，否则在暗背景里会糊成一块
- 不画脸（本来就是纯色剪影）

输出：``art/sprites/echo/echo_{walk,idle}_{front,back,left,right}.png``（512×64 / 128×64）

用法::

    python tools/echo_frames.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "sprites", "lpc")
OUT = os.path.join(ROOT, "art", "sprites", "echo")

FRAME = 64
DIRS = ["front", "back", "left", "right"]
# 上浅下深的暗紫（#3A2846 → #1C1224）
TOP = (58, 40, 70)
BOTTOM = (28, 18, 36)
ALPHA = 236


def silhouette(im: Image.Image) -> Image.Image:
    w, h = im.size
    src = im.load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    for y in range(h):
        t = y / float(max(1, h - 1))
        col = (
            int(TOP[0] + (BOTTOM[0] - TOP[0]) * t),
            int(TOP[1] + (BOTTOM[1] - TOP[1]) * t),
            int(TOP[2] + (BOTTOM[2] - TOP[2]) * t),
        )
        for x in range(w):
            if src[x, y][3] > 48:
                dst[x, y] = (col[0], col[1], col[2], ALPHA)

    # 边缘微光：贴着透明的像素提亮一点，暗处才看得出轮廓
    rim = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rp = rim.load()
    for y in range(h):
        for x in range(w):
            if dst[x, y][3] == 0:
                continue
            edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h or dst[nx, ny][3] == 0:
                    edge = True
                    break
            if edge:
                r, g, b, a = dst[x, y]
                rp[x, y] = (min(255, int(r * 1.55)), min(255, int(g * 1.45)), min(255, int(b * 1.7)), a)
    out.alpha_composite(rim)
    return out


def build_sheet(images, path):
    """四方向 × 8 帧总览，2 倍放大，深色底。"""
    cw, ch = FRAME * 2, FRAME * 2
    pad = 24
    sheet = Image.new("RGBA", (8 * cw + pad, len(DIRS) * ch + pad), (18, 14, 22, 255))
    for row, d in enumerate(DIRS):
        im = images["walk"][d]
        for i in range(8):
            f = im.crop((i * FRAME, 0, (i + 1) * FRAME, FRAME))
            f = f.resize((cw, ch), Image.NEAREST)
            sheet.alpha_composite(f, (i * cw + pad // 2, row * ch + pad // 2))
    sheet.convert("RGB").save(path)
    return path


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for kind in ("walk", "idle"):
        made[kind] = {}
        for d in DIRS:
            src = os.path.join(SRC, "student_%s_%s.png" % (kind, d))
            if not os.path.exists(src):
                print("MISSING", src)
                continue
            im = Image.open(src).convert("RGBA")
            sil = silhouette(im)
            dst = os.path.join(OUT, "echo_%s_%s.png" % (kind, d))
            sil.save(dst)
            made[kind][d] = sil
            print("wrote", os.path.relpath(dst, ROOT), sil.size)
    if "walk" in made and len(made["walk"]) == 4:
        p = build_sheet(made, os.path.join(ROOT, "tests", "art_echo_sheet.png"))
        print("sheet ->", os.path.relpath(p, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
