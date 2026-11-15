"""第三层候选怪物总览图。

把 ``art/sprites/reserve/`` 里已经切好的 4 方向角色排成一张图，用来挑 11~15F 用哪几种。
自动挑"角色像素最多"的一帧——`art/sprites/reserve/巨头婴/f01.png` 是抽取时混进来的
"Sprites" 占位图，直接用 f01 会显示成一串字。

输出：``tests/art_hell_monsters.png``

用法::

    python tools/monster_sheet.py
"""
import glob
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "art", "sprites", "reserve")
OUT = os.path.join(ROOT, "tests", "art_hell_monsters.png")

## 设计文档 §7 里 11~15F 的候选怪（目录名）
NAMES = [
    "骷髅", "蜘蛛马", "泥土怪", "绿球怪", "寄生猪", "巨头婴",
    "幽灵老师", "护士小姐", "史莱姆(金属融合)", "史莱姆", "感叹号",
]


def load_font(size):
    for f in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf",
              "C:/Windows/Fonts/simsun.ttc"):
        if os.path.exists(f):
            try:
                return ImageFont.truetype(f, size)
            except Exception:
                pass
    return ImageFont.load_default()


def best_frame(files):
    """挑不透明像素最多的一帧，避开抽取时混进来的占位图。"""
    best, best_score = None, -1
    for f in files:
        im = Image.open(f).convert("RGBA")
        score = sum(im.getchannel("A").histogram()[40:])
        if score > best_score:
            best, best_score = im, score
    return best


def main() -> int:
    font = load_font(16)
    cols, cw, ch = 4, 230, 200
    rows = (len(NAMES) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (30, 24, 32, 255))
    d = ImageDraw.Draw(sheet)
    for i, name in enumerate(NAMES):
        folder = os.path.join(RES, name)
        files = sorted(glob.glob(os.path.join(folder, "f*.png")))
        if not files:
            print("MISSING/EMPTY", folder)
            continue
        chosen = best_frame(files)
        sc = min((cw - 24) / chosen.width, (ch - 52) / chosen.height, 4.0)
        sc = max(1.0, sc)
        im2 = chosen.resize((max(1, int(chosen.width * sc)), max(1, int(chosen.height * sc))),
                            Image.NEAREST)
        ox, oy = (i % cols) * cw, (i // cols) * ch
        sheet.alpha_composite(im2, (ox + (cw - im2.width) // 2, oy + (ch - 34 - im2.height) // 2 + 6))
        d.text((ox + 10, oy + ch - 24), "%s  (%d frames)" % (name, len(files)),
               font=font, fill=(228, 216, 200, 255))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.convert("RGB").save(OUT)
    print("sheet ->", os.path.relpath(OUT, ROOT), len(NAMES), "monsters")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
