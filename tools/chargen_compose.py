"""CharGen（LPC）素材合成器。

不启动 GUI，直接读取 素材/CharGen/data/chargen.pak（本质是 zip），
按 LPC 的“蓝色索引”规则重新上色并逐层合成 64x64 帧。

为什么不用 GUI：chargen.exe 0.9.3 的命令行只支持调色板 import/export/match，
角色生成本身只有 GUI，无法脚本化。这个脚本复刻了它的合成规则：
  - 源贴图里 R=0,G=0,B=idx   的像素 = 主色槽 idx
  - 源贴图里 R=0,G=255,B=idx 的像素 = 副色槽 idx
  - default.cm 的 colors 是 [idx, 0xRRGGBBAA, ...]，按 idx 替换

常用：
  python tools/chargen_compose.py --preview
  python tools/chargen_compose.py --build
"""

import argparse
import io
import json
import os
import sys
import zipfile

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAK = os.path.join(ROOT, "素材", "CharGen", "data", "chargen.pak")

CELL = 64
# character_walk.anim：行走 4 行，前两列同时是 idle
WALK_ROWS = {"up": 512, "left": 576, "down": 640, "right": 704}
IDLE_COLS = 2

PREVIEW_DIR = r"C:\Users\43590\AppData\Local\Temp\opencode\chargen\preview"


class Pak:
    def __init__(self, path):
        self.z = zipfile.ZipFile(path)
        self.names = set(self.z.namelist())
        self._cache = {}

    def has(self, name):
        return name in self.names

    def image(self, name):
        if name not in self._cache:
            with self.z.open(name) as f:
                self._cache[name] = Image.open(io.BytesIO(f.read())).convert("RGBA")
        return self._cache[name]

    def json(self, name):
        with self.z.open(name) as f:
            return json.loads(f.read().decode("utf-8"))


def load_colormaps(pak):
    data = pak.json("data/colormaps/default.cm")
    maps = {}
    for item in data["items"]:
        colors = item["colors"]
        table = {}
        for i in range(0, len(colors), 2):
            idx = int(colors[i])
            packed = int(colors[i + 1])
            table[idx] = (
                (packed >> 24) & 0xFF,
                (packed >> 16) & 0xFF,
                (packed >> 8) & 0xFF,
                packed & 0xFF,
            )
        maps[item["id"]] = table
    return maps


class Layer:
    """一层贴图：sheet 路径 + 主色/副色 colormap id（None = 保持原色）。"""

    def __init__(self, tex, primary=None, secondary=None):
        self.tex = tex
        self.primary = primary
        self.secondary = secondary


def tint_sheet(img, colormaps, layer):
    """按 LPC 索引规则把纯蓝/纯绿索引像素替换成目标色（整张表缓存）。"""
    key = (layer.tex, layer.primary, layer.secondary)
    if key in _TINT_CACHE:
        return _TINT_CACHE[key]
    src = img.load()
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    dst = out.load()
    ptab = colormaps.get(layer.primary, {}) if layer.primary else {}
    stab = colormaps.get(layer.secondary, {}) if layer.secondary else {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            if a == 0:
                continue
            if r == 0 and g == 0 and b > 0:
                dst[x, y] = ptab.get(b, (r, g, b, a))
            elif r == 0 and g == 255 and b > 0:
                dst[x, y] = stab.get(b, (r, g, b, a))
            else:
                dst[x, y] = (r, g, b, a)
    _TINT_CACHE[key] = out
    return out


_TINT_CACHE = {}


def compose_frame(pak, colormaps, layers, row, col, scale=1):
    canvas = Image.new("RGBA", (CELL * scale, CELL * scale), (0, 0, 0, 0))
    for layer in layers:
        if not layer.tex or not pak.has(layer.tex):
            continue
        sheet = tint_sheet(pak.image(layer.tex), colormaps, layer)
        tile = sheet.crop((col * CELL, row, (col + 1) * CELL, row + CELL))
        if scale != 1:
            tile = tile.resize((CELL * scale, CELL * scale), Image.NEAREST)
        canvas.alpha_composite(tile)
    return canvas


def compose_strip(pak, colormaps, layers, direction, frames=8, scale=1, idle=False):
    row = WALK_ROWS[direction]
    n = IDLE_COLS if idle else frames
    strip = Image.new("RGBA", (CELL * scale * n, CELL * scale), (0, 0, 0, 0))
    for i in range(n):
        strip.alpha_composite(
            compose_frame(pak, colormaps, layers, row, i, scale=scale),
            (i * CELL * scale, 0),
        )
    return strip


def compose_all(pak, colormaps, layers, scale=1):
    """LPC 标准 4 行行走表：up / left / down / right，每行 8 帧。"""
    sheet = Image.new("RGBA", (CELL * scale * 8, CELL * scale * 4), (0, 0, 0, 0))
    for i, d in enumerate(["up", "left", "down", "right"]):
        sheet.alpha_composite(
            compose_strip(pak, colormaps, layers, d, scale=scale),
            (0, i * CELL * scale),
        )
    return sheet


def compose_at(pak, colormaps, layers, x, y, scale=1):
    """按源表里的像素坐标 (x, y) 合成单帧（用于非行走动作）。"""
    canvas = Image.new("RGBA", (CELL * scale, CELL * scale), (0, 0, 0, 0))
    for layer in layers:
        if not layer.tex or not pak.has(layer.tex):
            continue
        sheet = tint_sheet(pak.image(layer.tex), colormaps, layer)
        tile = sheet.crop((x, y, x + CELL, y + CELL))
        if scale != 1:
            tile = tile.resize((CELL * scale, CELL * scale), Image.NEAREST)
        canvas.alpha_composite(tile)
    return canvas


# 原始 LPC universal 表的行布局（每个图层 832x1344 = 13x21 格）：
#   0~3    spellcast（7 帧）
#   4~7    thrust（8 帧，最后 1 帧是循环复制）
#   8~11   walk（9 帧，最后 1 帧是循环复制）
#   12~15  slash（6 帧）
#   16~19  shoot（13 帧）
#   20     hurt（6 帧，单行、朝下）
# 注意：chargen.pak 里的 data/character.anim 是 CharGen「拼接后的导出表」坐标，
# 不能直接拿来裁原始图层，否则会把 thrust 当成 walk。
ANIM_ROWS = {
    "cast": (0, 6),
    "thrust": (256, 7),
    "walk": (512, 8),
    "slash": (768, 5),
    "islash": (768, 5),
    "shoot": (1024, 12),
    "hurt": (1280, 5),
}
DIR_ROW = {"up": 0, "left": 1, "down": 2, "right": 3}


def animation_frames(anim_id):
    """返回 (起始行, 帧数, 是否倒放)。idle 复用 walk 前 2 帧。"""
    name, _, direction = anim_id.rpartition("_")
    if name == "idle":
        row = ANIM_ROWS["walk"][0] + DIR_ROW[direction] * CELL
        return row, 2, False
    if name == "hurt":
        return ANIM_ROWS["hurt"][0], ANIM_ROWS["hurt"][1], False
    base, count = ANIM_ROWS[name]
    row = base + DIR_ROW[direction] * CELL
    return row, count, name == "islash"


def compose_animation(pak, colormaps, layers, anim_id, scale=1):
    """按原始 LPC 行布局把一条动画拼成横向条带。"""
    row, count, reverse = animation_frames(anim_id)
    order = list(range(count))
    if reverse:
        order.reverse()
    strip = Image.new("RGBA", (CELL * scale * count, CELL * scale), (0, 0, 0, 0))
    for i, col in enumerate(order):
        strip.alpha_composite(
            compose_frame(pak, colormaps, layers, row, col, scale=scale),
            (i * CELL * scale, 0),
        )
    return strip


def animation_ids():
    """与 CharGen 导出一致的 29 组动画。"""
    out = []
    for d in ("up", "left", "down", "right"):
        out.append(f"idle_{d}")
    for a in ("cast", "thrust", "walk", "slash", "islash", "shoot"):
        for d in ("up", "left", "down", "right"):
            out.append(f"{a}_{d}")
    out.append("hurt_down")
    return out


# ---------------------------------------------------------------- recipes
# 现代校园角色：短发、衬衫、长裤、皮鞋。颜色 id 全部来自 default.cm。
RECIPES = {
    # 卷狗（默认追击者）：藏青校服外套、深色长裤、黑短发
    "juan": {
        "body": Layer("textures/character/body/humanoid_m1.png", "human_skin_peach"),
        "head": Layer("textures/character/head/human_m.png", "human_skin_peach"),
        "pants": Layer("textures/gear/pants/pants/pants_m1.png", "cloth_black1"),
        "shirt": Layer("textures/gear/shirt/shirt/shirtls1_m1.png", "cloth_white2"),
        "jacket": Layer("textures/gear/jacket/collared/collared1_m1.png", "cloth_blue1"),
        "shoes": Layer("textures/gear/shoes/shoes/shoes_m1.png", "cloth_black1"),
        "eyes": Layer("textures/character/eyes/human_m.png", "human_eyes_brown"),
        "hair": Layer("textures/character/hair/human/bangs_m.png", "human_hair_black"),
    },
    # 主角：黑发短刘海、白衬衫、藏青长裤
    "player": {
        "body": Layer("textures/character/body/humanoid_m1.png", "human_skin_olive"),
        "head": Layer("textures/character/head/human_m.png", "human_skin_olive"),
        "pants": Layer("textures/gear/pants/pants/pants_m1.png", "cloth_blue3"),
        "shirt": Layer("textures/gear/shirt/shirt/shirtls1_m1.png", "cloth_white1"),
        "shoes": Layer("textures/gear/shoes/shoes/shoes_m1.png", "cloth_black1"),
        "eyes": Layer("textures/character/eyes/human_m.png", "human_eyes_brown"),
        "hair": Layer("textures/character/hair/human/bangs_m.png", "human_hair_black"),
    },
    # 普通学生：寸头、灰衬衫、深灰长裤
    "student": {
        "body": Layer("textures/character/body/humanoid_m2.png", "human_skin_light"),
        "head": Layer("textures/character/head/human_m.png", "human_skin_light"),
        "pants": Layer("textures/gear/pants/pants/pants_m2.png", "cloth_gray2"),
        "shirt": Layer("textures/gear/shirt/shirt/shirtls1_m1.png", "cloth_gray1"),
        "shoes": Layer("textures/gear/shoes/shoes/shoes_m1.png", "cloth_brown1"),
        "eyes": Layer("textures/character/eyes/human_m.png", "human_eyes_brown"),
        "hair": Layer("textures/character/hair/human/buzzcut_m.png", "human_hair_black"),
    },
    # 老师：灰发、白衬衫、红领带、深色西裤
    "teacher": {
        "body": Layer("textures/character/body/humanoid_m1.png", "human_skin_light"),
        "head": Layer("textures/character/head/human_m.png", "human_skin_light"),
        "pants": Layer("textures/gear/pants/formal/formal_m1.png", "cloth_blue4"),
        "shirt": Layer("textures/gear/shirt/formal/shirt1_m1.png", "cloth_white2"),
        "neck": Layer("textures/gear/shirt/neck/tie_m.png", "cloth_red2"),
        "shoes": Layer("textures/gear/shoes/shoes/shoes_m1.png", "cloth_black1"),
        "eyes": Layer("textures/character/eyes/human_m.png", "human_eyes_gray"),
        "hair": Layer("textures/character/hair/human/balding_m.png", "human_hair_gray2"),
    },
    # 保安：棕皮夹克、黑裤、靴子
    "guard": {
        "body": Layer("textures/character/body/humanoid_m2.png", "human_skin_brown"),
        "head": Layer("textures/character/head/human_m.png", "human_skin_brown"),
        "pants": Layer("textures/gear/pants/loose/loose_m1.png", "cloth_black1"),
        "shirt": Layer("textures/gear/shirt/leather/leather1_m1.png", "cloth_brown3"),
        "shoes": Layer("textures/gear/shoes/boots/bootsfold1_m1.png", "cloth_black1"),
        "eyes": Layer("textures/character/eyes/human_m.png", "human_eyes_brown"),
        "hair": Layer("textures/character/hair/human/cowlick1_m.png", "human_hair_black"),
    },
    # 暴君：特殊体积单位，保留原来的 AI 恐怖立绘，不在这里做 LPC 版本
}

# 大体积方案（仅记录，当前未使用）：LPC 没有 large 贴图，做法是最近邻放大 2 倍，
# 输出 128px 帧，游戏里再按内容高度 48/64 换算缩放。暴君按需求改回原立绘。
LARGE_SCALE = 2

# 绘制顺序：躯干 → 头 → 腿 → 鞋 → 上衣 → 领带 → 眼睛 → 头发
DRAW_ORDER = ["body", "head", "pants", "shoes", "shirt", "jacket", "neck", "eyes", "hair"]

# 每个角色输出的放大倍率（1 = 64px 帧）
SCALES = {"juan": 1, "player": 1, "student": 1, "teacher": 1, "guard": 1}


def build_layers(recipe):
    return [recipe[k] for k in DRAW_ORDER if k in recipe]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="输出到临时预览目录")
    ap.add_argument("--build", action="store_true", help="输出到 art/sprites/lpc/")
    ap.add_argument("--which", default="all")
    args = ap.parse_args()

    pak = Pak(PAK)
    colormaps = load_colormaps(pak)
    out_dir = os.path.join(ROOT, "art", "sprites", "lpc") if args.build else PREVIEW_DIR
    os.makedirs(out_dir, exist_ok=True)

    names = list(RECIPES) if args.which == "all" else [args.which]
    for name in names:
        layers = build_layers(RECIPES[name])
        scale = SCALES.get(name, 1)
        sheet = compose_all(pak, colormaps, layers, scale=scale)
        sheet.save(os.path.join(out_dir, f"{name}_walk.png"))
        print("saved", f"{name}_walk.png", sheet.size)

        # 4 张单方向条带（现有 Godot 代码直接吃这个命名）
        for key, d in (("front", "down"), ("back", "up"), ("left", "left"), ("right", "right")):
            strip = compose_strip(pak, colormaps, layers, d, scale=scale)
            strip.save(os.path.join(out_dir, f"{name}_walk_{key}.png"))
        # idle 2 帧
        for key, d in (("front", "down"), ("back", "up"), ("left", "left"), ("right", "right")):
            strip = compose_strip(pak, colormaps, layers, d, scale=scale, idle=True)
            strip.save(os.path.join(out_dir, f"{name}_idle_{key}.png"))

        # 全部动作（idle / walk / slash / thrust / cast / shoot / hurt 等）按方向单独出条带
        if args.build:
            act_dir = os.path.join(out_dir, "actions", name)
            os.makedirs(act_dir, exist_ok=True)
            index = {"cell": CELL * scale, "animations": {}}
            ids = animation_ids()
            for anim_id in ids:
                img = compose_animation(pak, colormaps, layers, anim_id, scale=scale)
                img.save(os.path.join(act_dir, f"{anim_id}.png"))
                index["animations"][anim_id] = animation_frames(anim_id)[1]
            with open(os.path.join(act_dir, "index.json"), "w", encoding="utf-8") as f:
                json.dump(index, f, ensure_ascii=False, indent=2)
            print("saved", f"actions/{name}/", len(ids), "animations")


if __name__ == "__main__":
    main()
