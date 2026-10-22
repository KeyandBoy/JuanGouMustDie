# AI 出图管线（可复用 / 可产品化）

> 用途：用**免费**文生图 API 批量产出游戏素材（过场图、角色立绘、漫画分镜），
> 并自动完成「纯色背景抠图 → 裁边 → 缩放 → 落盘」。
> 本项目已用它产出 10 张图（见 `art/cutscene/`、`art/sprites/tyrant/`）。
>
> **背景：这套流程后续会反复使用。如果效果好，可以作为独立产品做。第 8 节是产品化清单。**

---

## 1. 文件

| 文件 | 作用 |
|---|---|
| `tools/gen_art.ps1` | 批量出图。**纯 ASCII**（原因见第 7 节坑 1） |
| `tools/post_art.gd` | Godot headless 后处理：抠图 / 裁边 / 缩放 / 落盘 |
| `tools/_gen/` | 原始 PNG 缓存 + `_manifest.json`（可整目录删除重建） |
| `art/cutscene/`、`art/sprites/tyrant/` | 后处理成品 |

---

## 2. 快速开始

```powershell
$G = "E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"

# 全量：出图 + 后处理（已有图会跳过）
powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1 -Post

# 只出一张
powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1 -Only tyrant_front -Post

# 重出（覆盖已有）
powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1 -Force -Post

# 用外部清单（不篡改默认清单）
powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1 -Manifest my.json -Post

# 只跑后处理
& $G --headless --path . --script res://tools/post_art.gd

# 新图必须导入，之后才能在游戏里 load()
& $G --headless --path . --import
```

---

## 3. 清单格式

`gen_art.ps1` 内置了本项目的 10 条清单；也可以用 `-Manifest` 传自己的 JSON 数组：

```json
[
  {
    "name": "tyrant_front",
    "prompt": "Full body game sprite of ... isolated on a solid flat magenta background, no text",
    "ratio": "3:4",
    "out": "res://art/sprites/tyrant/tyrant_front.png",
    "key": true,
    "resize_h": 192
  }
]
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | 是 | 原始图存为 `tools/_gen/<name>.png` |
| `prompt` | 是 | 英文提示词（模型对英文更稳） |
| `ratio` | 否 | `16:9` / `4:3` / `3:4` / `1:1`，默认 `1:1` |
| `out` | 是* | 成品路径（`res://` 开头），后处理用 |
| `key` | 否 | `true` 时做洋红抠图（prompt 里要写 `isolated on a solid flat magenta background`） |
| `resize_h` | 否 | `key=true` 时的目标高度，默认 192 |

\* `out` 为空时 `post_art.gd` 会跳过该条（只留原始图）。

`gen_art.ps1` 会把归一化后的清单写到 `tools/_gen/_manifest.json`，`post_art.gd` 优先读它；
清单不存在时退回到 `post_art.gd` 里的内置兜底表。所以两个脚本可以独立运行。

---

## 4. API 细节（2026-10 实测）

### 4.1 imagefree.net（主通道，免 key）

```
POST https://imagefree.net/api/generate
Content-Type: application/json
{ "prompt": "...", "aspect_ratio": "3:4" }

-> 200 { "taskId": "<uuid>", "status": "pending" }
```

```
GET https://imagefree.net/api/generate/status?taskId=<uuid>

-> { "status": "pending" }
-> { "status": "completed", "image": "https://pub-....r2.dev/images/<uuid>.png", "progress": 100 }
-> { "status": "failed" }
```

- 出图约 10~30s，脚本每 3s 轮询，最多 40 次。
- 成品在 Cloudflare R2 上，直接 GET 下载即可。
- **turnstile_token**：官网前端会带 Cloudflare Turnstile token，但实测**不传也能出图**。
  若将来被拦，`POST` 会返回 `errorCode`，需要接验证码或换通道。
- **限流**：`FREE_TASK_IP_ACTIVE` / `FREE_TASK_BROWSER_ACTIVE` —— 同一 IP 同时只能跑一个任务，
  所以**必须串行**，不能并发。脚本已按串行设计。

### 4.2 pollinations.ai（回退，免 key）

```
GET https://image.pollinations.ai/prompt/<urlencoded prompt>?width=1024&height=576&nologo=true&model=flux
```

- 直接返回图片字节，无任务/轮询概念。
- 尺寸靠 `width/height` 控制（脚本按 ratio 映射为 1024x576 / 1024x768 / 768x1024 / 1024x1024）。
- 质量与可复现性不如 imagefree，仅作兜底。

---

## 5. 抠图算法（`post_art.gd`）

**目标**：把「纯洋红背景 + 主体」的图变成透明底 PNG。

### 5.1 判据：亮度不变的洋红比值

```
m     = min(r, b)
ratio = g / m          # 纯洋红 r、b 高、g 低 -> ratio 很小
```

- `ratio < 0.50` → 完全透明
- `0.50 <= ratio < 0.68` → 羽化（按比例给 alpha，保留抗锯齿边缘）
- 否则 → 保留
- `m < 0.05`（近黑）直接保留，避免暗部误判

**为什么不用别的**（都试过，失败）：

| 方案 | 失败原因 |
|---|---|
| 四角采样 + 欧氏距离 | 生成图背景有**渐晕**，中心亮、四角暗，单一背景色覆盖不了 |
| `min(r,b) - g` 固定阈值 | 暗部洋红的差值变小，逃过阈值，残留在成品里 |
| 按 `alpha > 0` 求包围盒 | 羽化残留在画面四角仍有 alpha，包围盒 = 整张图 |
| `Image.create` + `blit_rect` 缩放 | `blit_rect` 是**裁剪**不是缩放，只会取左上角 |

**比值判据的好处**：洋红整体变亮/变暗时 r、g、b 等比缩放，`g/min(r,b)` 不变，
所以对渐晕、曝光差异都稳健。

### 5.2 裁边

用 `ratio >= 0.68`（确定是主体）的像素求包围盒，再 `get_region()`。
不能用 `alpha > 0`（见上表）。

### 5.3 缩放

```gdscript
var out := img.duplicate()
out.resize(nw, target, Image.INTERPOLATE_LANCZOS)
```

必须 `duplicate()` 后 `resize()`。

### 5.4 参数怎么调

- 主体里**紫色/品红**元素被误抠 → 调低 `ratio_feather`（如 0.60）或调低 `ratio_solid`（如 0.45）。
- 背景残留 → 调高 `ratio_solid`（如 0.55）。
- 边缘发黑/发脏 → 调高 `ratio_feather`，给更大的羽化区间。
- 换背景色（绿幕）→ 把判据改成 `ratio = max(r,b) / g` 之类，并同步改 `_trim_to_subject`。

---

## 6. 在 Godot 里使用成品

- **必须 `load()`，不能 `preload()`**：新图导入前 `preload` 会让脚本解析失败。
- 用 `ResourceLoader.exists(path)` 守卫，缺失时回退占位图（本项目暴君就是这么做的）。
- 立绘脚底对齐：`sprite.centered = true` + `sprite.offset = Vector2(0, -h * 0.5)`。
- 高分辨率绘制图用 `TEXTURE_FILTER_LINEAR`；像素图才用 `NEAREST`。
- 全屏过场图：`TextureRect` + `EXPAND_IGNORE_SIZE` + `STRETCH_KEEP_ASPECT_COVERED`。

---

## 7. 已知坑

1. **PowerShell 5.1 按 ANSI/GBK 解码无 BOM 的 UTF-8 脚本**。
   `.ps1` 里写中文注释会吃掉换行/大括号，报 `意外的标记 }`。
   → **`.ps1` 永久保持纯 ASCII**；中文写进本 md。
2. **图片查看器常忽略 alpha**，直接把 RGB 显示出来 —— 看上去「洋红还在」，
   其实 alpha 已经是 0。验证要写脚本读 alpha 通道并统计。
3. **`--script` 跑 SceneTree 脚本时，`_init` 里 `await process_frame` 会挂死**。
   只做同步操作，最后 `quit()`。
4. **imagefree 限流**：并发会返回 `FREE_TASK_IP_ACTIVE`，必须串行。
5. 生成模型**不擅长写汉字**，会出乱码。做法：图里不写文字，文字用游戏内字体叠加
   （本项目「内卷即死」就是 `intro.gd` 用像素字体叠上去的）。
6. 提示词里加 `no text` 能明显减少乱码字符。
7. 生成立绘时 `isolated on a solid flat magenta background, no ground shadow, no text`
   是稳定配方；**不要**用绿色（模型容易画出绿植/绿光）。

---

## 8. 产品化清单（如果要做成独立工具）

当前形态是「项目内脚本」。要变成独立产品，按优先级：

**P0（能用）**
- [ ] 把 `gen_art.ps1` 的默认清单抽出成 `presets/*.json`，脚本只做执行器
- [ ] `post_art.gd` 改成可传参（config 路径、key 颜色、阈值），去掉硬编码兜底表
- [ ] 一条命令跑完全流程：`gen.exe --manifest x.json --out ./assets --post`
- [ ] 失败重试与断点续传（按 `name` 记录已完成项）

**P1（好用）**
- [ ] 多通道抽象：`imagefree` / `pollinations` / 本地 SD / 付费 API 统一成 `Provider` 接口
- [ ] 预览图 + 自动裁切检查（边缘残留率、透明像素占比），低质量自动重出
- [ ] 抠图支持多色键 + 白底/黑底，并支持 alpha matting 细化边缘
- [ ] 批量并发队列（不同 provider 各自的限流策略）

**P2（产品）**
- [ ] GUI：拖入清单 / 预览九宫格 / 单张重出 / 调阈值实时预览
- [ ] 预设市场：像素风立绘、漫画分镜、过场背景、道具图标
- [ ] 输出管线对接引擎：Godot/Unity 资源目录 + `.import` 自动生成
- [ ] 成本与合规：各 provider 的服务条款、生成内容版权归属、商用授权说明

**技术债（做产品前必须还）**
- Turnstile 依赖第三方网页的「未公开行为」，随时可能变；产品化必须换**正规 API key** 通道。
- 免费通道不可承诺 SLA；要有明确的降级与错误提示。
- 抠图只对「纯色背景」有效，真实产品需要 rembg/alpha matting 一类方案。

---

## 9. 授权

- 生成图：本项目所用通道生成的内容无第三方素材版权；发布前仍应确认各 provider 当时的条款。
- 字体 `assets/fonts/zpix.ttf`：SIL OFL 1.1（可商用/可嵌入）。
- 详见 `assets/music/CREDITS.txt` 的非音频素材段。
