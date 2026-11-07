"""给暴君重做 4 方向走路条带：以原图第 1 帧为固定设计，做纸娃娃摆动。

背景：原来的 AI 8 帧条带里，角色结构逐帧漂移（巨型手臂/躯干左右跳），
脚也基本不交替，播放起来像“切图”。这里不再使用后 7 帧，全部从第 1 帧派生：

  left/right  大腿绕髋 ±20°，小腿在过腿相绕膝弯 15°（抬脚/收腿），
              手臂绕肩 ±12°，身体过腿时上抬 1px
  front/back  整条腿交替抬起 3px、向内侧收 1px，手臂 ±10°，
              身体左右 1px 重心偏移 + 过腿时上抬 1px

唯一基准是 art/sprites/tyrant/base_{front,back,left,right}.png（原始站姿），
不要从已经摆过的 walk 条带再派生，否则会累积变形。

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

LEG_TOP = 44
KNEE_Y = 52
ARM_TOP = 16
ARM_LEFT_X = 20
ARM_LEFT_WIDE_X = 26
ARM_RIGHT_X = 43


def split_parts(frame):
    keys = ("thighL", "shinL", "thighR", "shinR", "armL", "armR", "torso")
    layers = {k: Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0)) for k in keys}
    for y in range(CELL):
        for x in range(CELL):
            p = frame.getpixel((x, y))
            if p[3] == 0:
                continue
            if y >= LEG_TOP:
                side = "L" if x < 33 else "R"
                part = ("thigh" if y < KNEE_Y else "shin") + side
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


def rotate_point(point, pivot, angle):
    a = math.radians(angle)
    dx, dy = point[0] - pivot[0], point[1] - pivot[1]
    return (pivot[0] + dx * math.cos(a) - dy * math.sin(a),
            pivot[1] + dx * math.sin(a) + dy * math.cos(a))


def leg_pose(thigh, shin, hip, knee, angle, bend):
    """大腿绕髋；小腿先跟大腿一起绕髋，再绕新的膝盖弯曲。"""
    t = rotate(thigh, angle, hip)
    s = rotate(shin, angle, hip)
    knee2 = rotate_point(knee, hip, angle)
    s = rotate(s, bend, knee2)
    return t, s


def put(out, layer, dx=0, dy=0):
    out.alpha_composite(translate(layer, dx, dy))


def pose_side(frame, phase):
    """侧视：大腿前后摆 + 小腿过腿时弯曲抬脚，能看到跨步和收腿。"""
    L = split_parts(frame)
    s, c = math.sin(phase), math.cos(phase)
    angle = 22.0 * s
    bend_l = 16.0 * max(0.0, c)
    bend_r = 16.0 * max(0.0, -c)
    thighL, shinL = leg_pose(L["thighL"], L["shinL"], (25, 46), (24, 52), angle, bend_l)
    thighR, shinR = leg_pose(L["thighR"], L["shinR"], (38, 46), (39, 52), -angle, -bend_r)
    armL = rotate(L["armL"], -16.0 * s, (19, 20))
    armR = rotate(L["armR"], 16.0 * s, (44, 20))
    bob = -1 if abs(c) > 0.5 else 0
    sway = 1 if s > 0.3 else (-1 if s < -0.3 else 0)

    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    put(out, thighL)
    put(out, shinL)
    put(out, thighR)
    put(out, shinR)
    put(out, L["torso"], sway, bob)
    put(out, armL, sway, bob)
    put(out, armR, sway, bob)
    return out


def pose_front(frame, phase):
    """正视/背视：整条腿交替抬起并内收，身体轻微起伏。"""
    L = split_parts(frame)
    s = math.sin(phase)
    upL = s > 0.2
    upR = s < -0.2
    dxl, dyl = (2, -4) if upL else (0, 0)
    dxr, dyr = (-2, -4) if upR else (0, 0)
    # 正视/背视里手臂不要做左右旋转（会和同侧腿同向，看起来顺拐）；
    # 改成和抬腿相反的轻微上下位移，模拟前后摆的透视
    armL = translate(L["armL"], 0, 1 if upL else 0)
    armR = translate(L["armR"], 0, 1 if upR else 0)
    bob = -1 if abs(s) > 0.7 else 0
    sway = 2 if s > 0 else -2

    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    put(out, translate(L["thighL"], dxl, dyl))
    put(out, translate(L["shinL"], dxl, dyl))
    put(out, translate(L["thighR"], dxr, dyr))
    put(out, translate(L["shinR"], dxr, dyr))
    put(out, translate(L["torso"], sway, bob))
    put(out, translate(armL, sway, bob))
    put(out, translate(armR, sway, bob))
    return out


def build(key, pose):
    # 唯一基准：原始站姿 base_*.png；不要从已经摆过的 walk 条带再派生，否则会累积变形
    base_path = os.path.join(BASE, "base_%s.png" % key)
    if os.path.exists(base_path):
        base = Image.open(base_path).convert("RGBA").crop((0, 0, CELL, CELL))
    else:
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
