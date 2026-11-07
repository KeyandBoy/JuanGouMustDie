"""给暴君重做 4 方向走路条带：以原图第 1 帧为固定设计，做纸娃娃摆动。

背景：原来的 AI 8 帧条带里，角色结构逐帧漂移（巨型手臂/躯干左右跳），
脚也基本不交替，播放起来像“切图”。这里不再使用后 7 帧，全部从第 1 帧派生：

  left/right  腿绕髋部旋转 ±15°，手臂绕肩 ±9° —— 产生前后跨步
  front/back  左右腿交替抬起 2px 并向内收 1px，手臂 ±6° —— 产生踏步

输出覆盖 art/sprites/tyrant/walk_{front,back,left,right}.png，
然后由 tools/tyrant_multiview.py 重新生成 idle / turnaround。

用法：python tools/tyrant_walk_rig.py
"""

import math
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(ROOT, "art", "sprites", "tyrant")
CELL = 64
FRAMES = 8

# 部件分割（按原图 64x64 的固定布局；四个方向的基准帧通用）
LEG_TOP = 44
ARM_TOP = 16
ARM_LEFT_X = 20        # 左臂：x < 20
ARM_LEFT_WIDE_X = 26   # 左臂下段放宽到 x < 26
ARM_RIGHT_X = 43       # 右臂：x > 43


def split_parts(frame):
    layers = {k: Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)) for k in
              ("legL", "legR", "armL", "armR", "torso")}
    for y in range(CELL):
        for x in range(CELL):
            p = frame.getpixel((x, y))
            if p[3] == 0:
                continue
            if y >= LEG_TOP:
                part = "legL" if x < 33 else "legR"
            elif y >= ARM_TOP and (x < ARM_LEFT_X or (x < ARM_LEFT_WIDE_X and y >= 34)):
                part = "armL"
            elif y >= ARM_TOP and x > ARM_RIGHT_X:
                part = "armR"
            else:
                part = "torso"
            layers[part].putpixel((x, y), p)
    return layers


def rotate(layer, angle, pivot):
    if abs(angle) < 0.01:
        return layer
    return layer.rotate(angle, center=pivot, resample=Image.NEAREST)


def translate(layer, dx, dy):
    if dx == 0 and dy == 0:
        return layer
    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    out.alpha_composite(layer, (dx, dy))
    return out


def compose(layers, legL, legR, armL, armR):
    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    out.alpha_composite(legL)
    out.alpha_composite(legR)
    out.alpha_composite(layers["torso"])
    out.alpha_composite(armL)
    out.alpha_composite(armR)
    return out


def pose_side(frame, phase):
    """侧视：腿绕髋旋转，手臂反向摆，能看到腿交叉。"""
    L = split_parts(frame)
    s = math.sin(phase)
    legL = rotate(L["legL"], 15.0 * s, (25, 46))
    legR = rotate(L["legR"], -15.0 * s, (38, 46))
    armL = rotate(L["armL"], 9.0 * s, (19, 20))
    armR = rotate(L["armR"], -9.0 * s, (44, 20))
    return compose(L, legL, legR, armL, armR)


def pose_front(frame, phase):
    """正视/背视：左右腿交替抬起并内收，避免平面旋转变成劈叉。"""
    L = split_parts(frame)
    s = math.sin(phase)
    upL = s > 0.2
    upR = s < -0.2
    legL = translate(L["legL"], 1 if upL else 0, -2 if upL else 0)
    legR = translate(L["legR"], -1 if upR else 0, -2 if upR else 0)
    legL = rotate(legL, 4.0 * s, (25, 46))
    legR = rotate(legR, 4.0 * s, (38, 46))
    armL = rotate(L["armL"], 6.0 * s, (19, 20))
    armR = rotate(L["armR"], -6.0 * s, (44, 20))
    return compose(L, legL, legR, armL, armR)


def build(key, pose):
    src = Image.open(os.path.join(BASE, "walk_%s.png" % key)).convert("RGBA")
    base = src.crop((0, 0, CELL, CELL))
    strip = Image.new("RGBA", (CELL * FRAMES, CELL), (0, 0, 0, 0))
    for i in range(FRAMES):
        strip.alpha_composite(pose(base, i / float(FRAMES) * math.tau), (i * CELL, 0))
    path = os.path.join(BASE, "walk_%s.png" % key)
    strip.save(path)
    print("saved", path)


def main():
    build("left", pose_side)
    build("right", pose_side)
    build("front", pose_front)
    build("back", pose_front)


if __name__ == "__main__":
    main()
