# 家具原型贴图（art/furniture）

> **授权状态：未确认，仅本地原型用，发布前必须替换。**

## 来源

- 原图：`素材/_extracted/建筑/室内家具/Interior_1.png`（675×672，RGBA）
- 该素材目录为外部素材包解包结果，**授权信息不明**；参考项目 PixelGame 是 AGPL-3.0，本仓库只学思路不抄代码与素材。
- 本目录的 PNG 是用连通域扫描从原图裁出的单个家具，**没有做任何美术加工**，只做了裁剪。

## 用途

`scripts/school_map.gd` 的 `big_items`（房型专属大件家具）通过 `load("res://art/furniture/<name>.png")`
读取这些图，用 `draw_texture_rect()` 统一压成冷色调绘制，并按 `kind/rect/room` 参与碰撞。

## 发布前要做的事

1. 用自有美术或确认授权的素材替换 `art/furniture/*.png`（尺寸可保持相近，代码里按 rect 缩放）。
2. 替换后删除本 README 的"未确认"标记。
3. 若最终确认可商用，把授权原文写进 `assets/music/CREDITS.txt` 同级的素材清单里。

## 清单（按**真实图案**标注；名字只是历史遗留，别按名字理解）

| 文件 | 实际图案 | 当前用途 |
| --- | --- | --- |
| bed_a / bed_b / bed_c / bed_head | 病床（蓝/粉/灰）与床头板 | 医务室 |
| shelf_tall / shelf_wide | 摆满书的书架 | 教室 / 图书室 / 储物间 / 广播室 |
| cab_tall | 空的高书架 | 办公室 |
| cab_mid / cab_short | 双开门衣柜 | 储物间 / 厕所隔间 / 医务室 |
| wardrobe / wardrobe2 | 布帘隔间（蓝/粉） | 医务室帘子 / 广播室录音间 |
| locker | 木梯 | 实验室 / 储物间 |
| crate_stack | 点唱机/机器 | 广播室 / 实验室仪器 |
| desk_office2 | 素面木桌 | 办公桌 / 实验台 / 控制台 |
| desk_office | 铺桌布的餐桌（**暂未使用**） | — |
| desk_small / stool_a / stool_b | 小木桌、方凳 | 实验台、教室内小桌、厕所洗手台 |
| chair_a / chair_b / chair_c | 木桌（圆/方/带桌布） | 办公室（**名字叫 chair 其实是桌子**） |
| plant_pot / plant_pot2 / barrel / canister / box_small / box_small2 / plant_bush / plant_tall | 各种盆栽、花篮、带盆栽的架子 | 各房型绿植 |
| poster_c | 风景画 | 墙饰 |
| poster_d / fence / clock | 空画框 | 墙饰 |
| poster_a / poster_b | 折叠床、陶罐（**暂未使用**） | — |
| rug_a / rug_b / rug_c / rug_d | 地毯（红椭圆 / 棕花纹 / 米色椭圆） | 贴地件，画在最底层 |
| counter_long / counter_mid / bench | 木栅栏（**暂未使用**） | — |
| gate | 黑色拱门（**暂未使用**） | — |
| ladder / door_wood | 木门、白色门板（**暂未使用**） | — |
