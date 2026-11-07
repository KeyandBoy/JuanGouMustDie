"""从暴君原有的 4 方向行走条带生成 4 方向站立/待机图与转身模型图。

原 AI 立绘只有 4 方向走路是逐帧的；站立姿势直接用走路第 1 帧，
第 2 帧做一次"脚底不动、身体轻微压缩"的呼吸，避免引入新的画风。

输出：
  art/sprites/tyrant/idle_front|back|left|right.png   （2 帧，64x64）
  art/sprites/tyrant/turnaround.png                  （4 方向站姿模型图，3x）
"""

import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "art", "sprites", "tyrant")
DIRS = [("front", "FRONT"), ("back", "BACK"), ("left", "LEFT"), ("right", "RIGHT")]
CELL = 64


def first_frame(path):
    strip = Image.open(path).convert("RGBA")
    if strip.height != CELL:
        raise ValueError("%s 不是 64px 条带：%s" % (path, strip.size))
    return strip.crop((0, 0, CELL, CELL))


def still_frame(key):
    """站姿优先用 base_*.png（原始站姿），没有才退回走路第 1 帧。"""
    base = os.path.join(BASE, "base_%s.png" % key)
    if os.path.exists(base):
        return Image.open(base).convert("RGBA").crop((0, 0, CELL, CELL))
    return first_frame(os.path.join(BASE, "walk_%s.png" % key))


def breath(frame):
    """脚底对齐，身体高度压到 97%，作为呼吸的第 2 帧。"""
    bbox = frame.getbbox()
    if bbox is None:
        return frame.copy()
    x0, y0, x1, y1 = bbox
    content = frame.crop(bbox)
    nh = max(1, int(content.height * 0.97))
    small = content.resize((content.width, nh), Image.NEAREST)
    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    out.alpha_composite(small, (x0, y1 - nh))
    return out


def main():
    os.makedirs(BASE, exist_ok=True)
    stills = []
    for key, _label in DIRS:
        walk = still_frame(key)
        strip = Image.new("RGBA", (CELL * 2, CELL), (0, 0, 0, 0))
        strip.alpha_composite(walk, (0, 0))
        strip.alpha_composite(breath(walk), (CELL, 0))
        strip.save(os.path.join(BASE, "idle_%s.png" % key))
        stills.append((key, walk))
        print("saved idle_%s.png" % key)

    # 转身模型图：4 个方向并排，3 倍最近邻
    S = 3
    pad = 16
    label_h = 22
    w = len(stills) * (CELL * S + pad) + pad
    h = CELL * S + label_h + pad * 2
    sheet = Image.new("RGBA", (w, h), (30, 32, 38, 255))
    d = ImageDraw.Draw(sheet)
    for i, (key, im) in enumerate(stills):
        x = pad + i * (CELL * S + pad)
        d.text((x, pad - 2), key.upper(), fill=(255, 220, 120, 255))
        sheet.alpha_composite(im.resize((CELL * S, CELL * S), Image.NEAREST),
                              (x, pad + label_h))
    out = os.path.join(BASE, "turnaround.png")
    sheet.convert("RGB").save(out)
    print("saved", out, sheet.size)


if __name__ == "__main__":
    main()
