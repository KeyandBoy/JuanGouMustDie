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

## 素材库怪物（2026-11-07 新增）

`素材/怪物/` 里的单张正面图（Skeleton / zombie / puppet / minotaur）由
`tools/monster_dirs.py` 加工成游戏用的 4 方向行走条带：

- `skeleton_walk_{front,back,left,right}.png`（96×96 × 4 帧）
- `zombie_walk_*.png`（64×64 × 4 帧）
- `puppet_walk_*.png`（96×96 × 4 帧）
- `minotaur_walk_*.png`（112×112 × 4 帧）

规则：

- front = 原图去透明边后等比缩放、底部居中
- left / right = front 的水平镜像（同源素材只有正面）
- back = 把脸部矩形压成同族颜色（自动取该区域主色）+ 上下明暗 + 整体压暗 6%
- 走路 4 帧 = 上半身上抬 1px + 下半身左右各错 1px

接进游戏：`scripts/student.gd` 的 `ROLE_TEX` / `ROLE_FRAMES` / `ROLE_SCALE` / `ROLE_STATS`，
由 `main._spawn_students()` 按楼层混入（3F 骷髅+僵尸、4F 加傀儡、5F 加牛头人）。

## 第二批：batareya 包 20 只（2026-11-07）

```powershell
python tools\monster_dirs.py --pack
```

- 输出 `pack_01..20_walk_{front,back,left,right}.png`（64×96 × 4 帧）。
- 背面：脚本自动找眼睛（亮色像素）框出"脸"，用**矩形外圈的主色**填充，再加明暗并压暗 6%。
- 游戏里由 `student.gd` 的 `grotesque` 角色按 `monster_variant`（1~20）运行时载入；2F 起混入。
- 预览场景：`tests/_pack_demo.tscn`（20 变体循环）。

## 第三批：MonsterGirl 史莱姆 15 只（2026-11-08）

```powershell
python tools\slime_frames.py
```

- 源：`素材/怪物/MonsterGirl_0.1/Slime_{Human,Mix,Monster}_{Dark,Fire,Ice,Nature,Water}.png`（128×32 = 4 帧 × 32×32）。
- 输出 `slime_01..15_walk_{front,back,left,right}.png`：front 原样、left 镜像、right 原样、back 压暗 14%。
- 游戏里由 `student.gd` 的 `slime` 角色按 `slime_variant`（1~15）运行时载入；2F 起出现。
- 预览场景：`tests/_slime_demo.tscn`（15 变体 5×3 循环）。
- `Slime__Leader.png` 是单张 640×192 大图且造型暴露，暂不接入（全年龄定位）。

## 第四批：宝箱怪 Mimic（2026-11-08）

```powershell
python tools\mimic_frames.py
```

- 源：`素材/怪物/{Mimic,Green-Mimic,Blue-Mimic,Corrupt-Mimic}.gif`（单帧 100×100）。
- 输出 `mimic_01..04_walk_{front,back,left,right}.png`（96×96 × 4 帧，上下 1px 呼吸；蹲着时只播第 0 帧）。
- 游戏里由 `student.gd` 的 `mimic` 角色按 `mimic_variant`（1~4）载入；`disguise` 状态站着不动，玩家进 92px 后惊醒并追击。
- 生成位置：储物间的箱子堆（2F 1 只、4F 起 2 只）。
- 预览场景：`tests/_mimic_demo.tscn`。

## PixelDudes Maker

- 工具页：<https://0x72.itch.io/pixeldudesmaker>
- 本机无法直连 itch.io，且本地未找到该工具，所以本轮没有使用。
- 拿到 `pixeldudesmaker` 的下载后放到 `素材/` 下，即可继续生成人形猎奇角色。
