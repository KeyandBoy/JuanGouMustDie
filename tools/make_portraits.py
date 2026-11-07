"""像素肖像生成器（复刻 pixel_art_portrait_generator 的 shader 与图层顺序）。

素材来源：素材/pixel_art_portrait_generator/portraits.pck（Godot 3.5）
pck 里只有 Godot 的 .stex（WEBP 封装），这里直接解析 pck + .import 映射，
在内存里解码图层，跑原版 shader 重新上色，再按原场景树顺序叠加。

原版 shader（见 pck 内 Portrait.tscn）：

    weight = min(10 * max(|r-g|, |b-g|), 1)
    value  = (r + g + b) / 3
    COLOR  = (dark*r + light*g + shadow*b) * weight
             + (black*(1-value) + white*value) * (1-weight)

也就是说：红通道 = dark，绿通道 = light，蓝通道 = shadow，
灰度像素按 value 在 black/white 之间插值。

用法：
  python tools/make_portraits.py            # 生成 art/portraits/*.png
  python tools/make_portraits.py --sheet    # 额外输出选型用的图层总览
"""

import io
import json
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pck_extract import parse_pck  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAK = os.path.join(ROOT, "素材", "pixel_art_portrait_generator", "portraits.pck")
OUT_DIR = os.path.join(ROOT, "art", "portraits")

RE_PATH = re.compile(r'path="res://\.import/([^"]+\.stex)"')
RE_SOURCE = re.compile(r'source_file="res://([^"]+)"')

# 原版默认的黑白（灰度层用）
BLACK = (0.06, 0.03, 0.08)
WHITE = (1.0, 1.0, 1.0)
# 原版所有材质的 shadow 槽默认色（偏冷的深紫蓝，充当描边）
SHADOW = (0.13, 0.15, 0.31)


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# ------------------------------------------------------------------ 调色板

PALETTES = {
    # 主角：黑发、白衬衫、藏青裤（肖像只到肩，裤子看不到）
    "player": {
        "skin": ("#f0c098", "#b97b56"),
        "hair": ("#3c3c48", "#16161e"),
        "primary": ("#f6f6f2", "#b9b9b4"),   # 白衬衫
        "secondary": ("#2c3c66", "#18233f"),  # 深蓝
        "detail": ("#c8a05a", "#7a5a2c"),
        "neck": ("#e8e8e4", "#a8a8a4"),       # 白衬衫领
        "eye": ("#8a5a30", "#2a1a12"),
    },
    # 卷狗：藏青校服外套、黑短发
    "juan": {
        "skin": ("#f0c098", "#b97b56"),
        "hair": ("#3c3c48", "#16161e"),
        "primary": ("#33477a", "#1c2744"),
        "secondary": ("#e8e8e4", "#a8a8a4"),
        "detail": ("#b03a3a", "#6a1e1e"),
        "neck": ("#e8e8e4", "#a8a8a4"),
        "eye": ("#6a4426", "#241610"),
    },
    # 学生：灰校服、短寸
    "student": {
        "skin": ("#f2c69e", "#bd8058"),
        "hair": ("#3c3c48", "#16161e"),
        "primary": ("#9a9aa2", "#5f5f68"),
        "secondary": ("#e6e6e2", "#a6a6a2"),
        "detail": ("#556080", "#2c3348"),
        "neck": ("#e6e6e2", "#a6a6a2"),
        "eye": ("#5a3c22", "#20140e"),
    },
    # 老师：地中海发型、浅蓝衬衫、红领带、眼镜
    "teacher": {
        "skin": ("#eab98f", "#b07450"),
        "hair": ("#a8a8b2", "#6a6a76"),
        "primary": ("#d8e2ee", "#8e9aac"),
        "secondary": ("#e8e8e4", "#a8a8a4"),
        "detail": ("#3a3a46", "#14141c"),
        "neck": ("#8a2424", "#4a0e0e"),
        "eye": ("#4a3a2a", "#1a120c"),
    },
    # 保安：深色制服、胡子
    "guard": {
        "skin": ("#d8a074", "#96603c"),
        "hair": ("#4a3a2c", "#241a12"),
        "primary": ("#39424e", "#1e242c"),
        "secondary": ("#8a8f98", "#565b64"),
        "detail": ("#c8a24a", "#7a5c1c"),
        "neck": ("#8a8f98", "#565b64"),
        "eye": ("#3c2a1c", "#140e08"),
    },
    # 暴君：黑皮、深红眼、皮革
    "tyrant": {
        "skin": ("#8a7a70", "#4e4038"),
        "hair": ("#2a2228", "#120c10"),
        "primary": ("#3a2c2c", "#1c1414"),
        "secondary": ("#7a2020", "#3c0c0c"),
        "detail": ("#b03030", "#5a1010"),
        "neck": ("#7a2020", "#3c0c0c"),
        "horn": ("#cbbba2", "#6e5c4a"),
        "eye": ("#ff4a3a", "#8a0c08"),
    },
}

# 每个角色用到的图层（None = 不用）
CHARACTERS = {
    "player": {
        "body": "body/male01.png",
        "cloths": "cloths/male01_primary.png",
        "cloths_secondary": None,
        "cloths_details": None,
        "neck": "neck/collar.png",
        "mouth": "mouth/neutral01.png",
        "nose": "nose/small01.png",
        "brows": "brows/neutral01.png",
        "eyes": "eyes/male01.png",
        "hair": "hair/base/male01.png",
        "hair_front": "hair/front/male01.png",
        "hair_back": "hair/back/short01.png",
        "beard": None,
        "glasses": None,
        "horns": None,
    },
    "juan": {
        "body": "body/male01.png",
        "cloths": "cloths/male03_primary.png",
        "cloths_secondary": "cloths/male03_secondary.png",
        "cloths_details": None,
        "neck": "neck/collar.png",
        "mouth": "mouth/neutral02.png",
        "nose": "nose/neutral01.png",
        "brows": "brows/neutral02.png",
        "eyes": "eyes/male01.png",
        "hair": "hair/base/male04.png",
        "hair_front": None,
        "hair_back": "hair/back/short01.png",
        "beard": None,
        "glasses": None,
        "horns": None,
    },
    "student": {
        "body": "body/male02.png",
        "cloths": "cloths/male04_primary.png",
        "cloths_secondary": "cloths/male04_secondary.png",
        "cloths_details": None,
        "neck": "neck/collar.png",
        "mouth": "mouth/neutral01.png",
        "nose": "nose/small01.png",
        "brows": "brows/flat01.png",
        "eyes": "eyes/male02.png",
        "hair": "hair/base/male02.png",
        "hair_front": "hair/front/male02.png",
        "hair_back": None,
        "beard": None,
        "glasses": None,
        "horns": None,
    },
    "teacher": {
        "body": "body/male03.png",
        "cloths": "cloths/male05_primary.png",
        "cloths_secondary": None,
        "cloths_details": None,
        "neck": "neck/tie.png",
        "mouth": "mouth/sad01.png",
        "nose": "nose/pointy01.png",
        "brows": "brows/angry01.png",
        "eyes": "eyes/male03.png",
        "hair": "hair/base/male03.png",
        "hair_front": None,
        "hair_back": None,
        "beard": None,
        "glasses": "glasses/glasses03.png",
        "horns": None,
    },
    "guard": {
        "body": "body/male01.png",
        "cloths": "cloths/male06_primary.png",
        "cloths_secondary": "cloths/male06_secondary.png",
        "cloths_details": None,
        "neck": "neck/collar.png",
        "mouth": "mouth/neutral02.png",
        "nose": "nose/large01.png",
        "brows": "brows/angry02.png",
        "eyes": "eyes/male01.png",
        "hair": "hair/base/male06.png",
        "hair_front": None,
        "hair_back": None,
        "beard": "beard/beard02.png",
        "glasses": None,
        "horns": None,
    },
    "tyrant": {
        "body": "body/male_android.png",
        "cloths": "cloths/male08_primary.png",
        "cloths_secondary": "cloths/male08_secondary.png",
        "cloths_details": "cloths/male08_details.png",
        "neck": None,
        "mouth": "mouth/grin02.png",
        "nose": "nose/large02.png",
        "brows": "brows/angry02.png",
        "eyes": "eyes/angled01.png",
        "hair": "hair/base/male07.png",
        "hair_front": None,
        "hair_back": None,
        "beard": None,
        "glasses": None,
        "horns": "horns/massive01.png",
    },
}


# ------------------------------------------------------------------ pck 读取

class PortraitPak:
    def __init__(self, path):
        info = parse_pck(path)
        self.data = info["data"]
        self.entries = {name: (off, size) for name, off, size, _f, _m in info["entries"]}
        self.entries_by_base = {os.path.basename(n): v for n, v in self.entries.items()}
        self.map = {}
        for name in self.entries:
            if not name.endswith(".import"):
                continue
            off, size = self.entries[name]
            text = self.data[off:off + size].decode("utf-8", "replace")
            m_path = RE_PATH.search(text)
            m_src = RE_SOURCE.search(text)
            if m_path and m_src:
                self.map[m_path.group(1)] = m_src.group(1)

    def image(self, rel):
        rel = rel.replace("\\", "/")
        if not rel.startswith("images/"):
            rel = "images/" + rel
        stex = None
        for k, v in self.map.items():
            if v == rel:
                stex = k
                break
        if stex is None or stex not in self.entries_by_base:
            raise KeyError("找不到图层：" + rel)
        off, size = self.entries_by_base[stex]
        raw = self.data[off:off + size]
        idx = raw.find(b"RIFF")
        return Image.open(io.BytesIO(raw[idx:])).convert("RGBA")

    def names(self):
        return sorted(self.map.values())


# ------------------------------------------------------------------ shader

def apply_shader(img, light, dark, shadow=SHADOW, white=WHITE, black=BLACK):
    """复刻原版 canvas_item shader（逐像素向量化）。"""
    a = np.asarray(img, dtype=np.float32) / 255.0
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    alpha = a[:, :, 3]

    weight = np.minimum(10.0 * np.maximum(np.abs(r - g), np.abs(b - g)), 1.0)
    value = (r + g + b) / 3.0

    def col(c):
        return np.array(c, dtype=np.float32)

    light = col(light)
    dark = col(dark)
    shadow = col(shadow)
    white = col(white)
    black = col(black)

    out = np.zeros((a.shape[0], a.shape[1], 3), dtype=np.float32)
    for ch in range(3):
        slot = dark[ch] * r + light[ch] * g + shadow[ch] * b
        grey = black[ch] * (1.0 - value) + white[ch] * value
        out[:, :, ch] = slot * weight + grey * (1.0 - weight)
    out = np.clip(out, 0.0, 1.0)
    rgba = np.dstack([out, alpha])
    return Image.fromarray((rgba * 255.0 + 0.5).astype(np.uint8), "RGBA")


# ------------------------------------------------------------------ 合成

def palette_for(name, key):
    pal = PALETTES[name]
    if key not in pal:
        key = "detail" if "detail" in pal else "primary"
    light, dark = pal[key]
    return hx(light), hx(dark), SHADOW


def shadow_variant(pak, rel):
    """xxx.png -> xxx_shadow.png（存在才返回）"""
    if not rel:
        return None
    stem, ext = os.path.splitext(rel)
    cand = stem + "_shadow" + ext
    return cand if cand in pak.map.values() else None


def compose(pak, name):
    spec = CHARACTERS[name]
    canvas = Image.new("RGBA", (96, 96), (0, 0, 0, 0))

    def draw(rel, pal_key, use_shadow=False):
        if not rel:
            return
        try:
            img = pak.image(rel)
        except KeyError:
            return
        light, dark, shadow = palette_for(name, pal_key)
        canvas.alpha_composite(apply_shader(img, light, dark, shadow))

    def draw_pair(rel, pal_key):
        if not rel:
            return
        s = shadow_variant(pak, rel)
        if s:
            draw(s, pal_key)
        draw(rel, pal_key)

    # 场景树顺序（Portrait.tscn）
    draw_pair(spec["hair_back"], "hair")
    draw(spec["body"], "skin")
    # Cloths：Shadow（在父节点之后，先画）
    p = spec["cloths"]
    if p:
        s = shadow_variant(pak, p)
        if s:
            draw(s, "primary")
    draw(p, "primary")
    draw(spec["cloths_secondary"], "secondary")
    draw(spec["cloths_details"], "detail")
    draw(spec["neck"], "neck" if spec["neck"] and "tie" in spec["neck"] else "secondary")
    draw(spec["mouth"], "secondary")
    draw_pair(spec["beard"], "hair")
    draw(spec["nose"], "skin")
    # Hair 容器
    draw_pair(spec["hair"], "hair")
    if spec["hair_front"]:
        s = shadow_variant(pak, spec["hair_front"])
        if s:
            draw(s, "hair")
    draw(spec["eyes"], "eye")
    draw_pair(spec["glasses"], "detail")
    draw(spec["brows"], "hair")
    draw(spec["hair"], "hair")
    draw(spec["hair_front"], "hair")
    draw_pair(spec["horns"], "horn")
    return canvas


def add_bg(img, pad=6):
    w, h = img.size
    out = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    out.alpha_composite(img, (pad, pad))
    return out


def frame(img, color=(46, 50, 60, 255), border=2):
    w, h = img.size
    out = Image.new("RGBA", (w + border * 2, h + border * 2), color)
    out.alpha_composite(img, (border, border))
    return out


def save_sheet(images, path, scale=2):
    cols = len(images)
    cw, ch = 96 * scale, 96 * scale
    pad = 12
    sheet = Image.new("RGBA", (cols * cw + pad * (cols + 1), ch + pad * 2 + 24), (32, 34, 40, 255))
    d = ImageDraw.Draw(sheet)
    for i, (name, im) in enumerate(images):
        big = im.resize((cw, ch), Image.NEAREST)
        x = pad + i * (cw + pad)
        sheet.alpha_composite(big, (x, pad + 20))
        d.text((x, 4), name, fill=(255, 220, 120, 255))
    sheet.convert("RGB").save(path)
    print("saved", path, sheet.size)


def main():
    sheet = "--sheet" in sys.argv
    pak = PortraitPak(PAK)
    os.makedirs(OUT_DIR, exist_ok=True)

    images = []
    for name in CHARACTERS:
        im = compose(pak, name)
        out = os.path.join(OUT_DIR, name + ".png")
        im.save(out)
        # 对话框头像位只有 44x44，再裁一张只剩头肩的 64x64 版本
        head = im.crop((16, 0, 80, 64))
        head.save(os.path.join(OUT_DIR, name + "_head.png"))
        print("saved", out, im.size)
        images.append((name, im))

    save_sheet(images, os.path.join(OUT_DIR, "portraits_sheet.png"))

    if sheet:
        # 选型用：所有布料 / 头发图层用统一调色板渲染
        def rel(n):
            return n[len("images/"):] if n.startswith("images/") else n

        groups = {
            "cloths": [rel(n) for n in pak.names() if rel(n).startswith("cloths/male") and n.endswith(".png") and "_shadow" not in n],
            "hair": [rel(n) for n in pak.names() if rel(n).startswith("hair/base/male") and n.endswith(".png") and "_shadow" not in n and "decoration" not in n],
            "eyes": [rel(n) for n in pak.names() if rel(n).startswith("eyes/") and n.endswith(".png")],
            "beard": [rel(n) for n in pak.names() if rel(n).startswith("beard/") and n.endswith(".png") and "_shadow" not in n and "moustache" not in n],
        }
        for gname, rels in groups.items():
            tiles = []
            for rel in rels:
                im = apply_shader(pak.image(rel), *palette_for("player", "skin"))
                tiles.append((os.path.basename(rel)[:-4], im))
            path = os.path.join(OUT_DIR, "_pick_" + gname + ".png")
            save_sheet(tiles, path, scale=1)


if __name__ == "__main__":
    main()
