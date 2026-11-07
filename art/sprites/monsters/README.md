# 怪物素材（Deep-Fold Pixel Sprite Generator 移植）

## 来源与授权

- 算法：**Deep-Fold / SpriteGenerator**（MIT License）
  - 源码：<https://github.com/Deep-Fold/SpriteGenerator>
  - 工具页：<https://deep-fold.itch.io/pixel-sprite-generator>
- 本项目的离线移植：`tools/deepfold_monsters.py`
  - 保留原版 MapGenerator / CellularAutomata / 余弦调色板 / 洪水填色 / 眼睛 / 描边
  - 用纯 Python Perlin 噪声替代 Godot 的 OpenSimplexNoise（只影响花纹，不影响轮廓）
  - 因此同一个 seed **不会**和原工具逐像素一致
- 生成物按原工具/MIT 的授权可自由使用。

## 生成命令

```powershell
# 原版随机调色板：30 只，48px
python tools\deepfold_monsters.py --count 30 --size 48

# 猎奇配色（血肉 / 尸绿 / 虚空轮换）：18 只，64px
python tools\deepfold_monsters.py --count 18 --size 64 --start 101 --mood all --prefix grotesque --sheet grotesque_sheet.png
```

## 文件

- `monster_XX.png`：原版随机调色板，48×48（含 1px 描边）
- `grotesque_XX.png`：猎奇配色，64×64
- `monsters_sheet.png` / `grotesque_sheet.png`：联系表（4 倍放大）

## PixelDudes Maker

- 工具页：<https://0x72.itch.io/pixeldudesmaker>
- 本机无法直连 itch.io，且本地未找到该工具，所以本轮没有使用。
- 拿到 `pixeldudesmaker` 的下载后放到 `素材/` 下，即可继续生成人形猎奇角色。
