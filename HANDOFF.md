# HANDOFF（双工具交接状态）

- 更新时间：2026-11-03
- 最后操作：opencode
- 分支：main
- 当前 HEAD：`add1c53`（字体切到方舟像素字体 Ark Pixel 12px）
- 工作区：干净（`horror_rebuild/ai`、`ai_norm` 已忽略）

## 最简用法（推荐）

- **用 DSH**：双击项目根目录的 `开始DSH.bat` → 打开 DSH，`Ctrl+V` 粘贴一次 → 开始开发；收工双击根目录 `结束会话.bat`。
  - `开始DSH.bat` 会自动加锁、把「开场提示 + 当前进度」放进剪贴板（`tools\start_dsh.bat` 是同一功能的副本）。
  - `结束会话.bat` 解锁；收工前仍要按 AGENTS 跑测试、更新 HANDOFF、commit + push。
- **用 opencode**：直接打开即可，不需要手动跑加锁/摘要命令。
- `git pull` 只在换电脑、或另一个工具刚推送过时执行。
- 如果加锁提示 `LOCK BUSY`：说明上一个会话没正常结束，双击根目录 `结束会话.bat` 解锁即可。

## 当前目标

暴君恐怖化重做已完成并替换进游戏：新立绘（7 套动作）+ 新 4 方向像素走路条带（32 帧、归一化调色）。
下一步请**实际玩一局第 5 关/新手关**看暴君在真实光照下的效果，重点看：暗处是否太暗、血是否看得清、走路 9fps 是否顺、动作立绘与走路切换是否跳大小/跳色。

## 本轮已完成

- **字体切换为方舟像素字体（2026-11-04）**：
  - 用户指定 <https://github.com/TakWolf/ark-pixel-font>；采用 `12px proportional zh_hans`（OFL-1.1）。
  - 新文件 `assets/fonts/ark_pixel_12px_zh_hans.ttf` + 授权 `assets/fonts/OFL_ark-pixel-font.txt`。
  - `ui_theme.gd` 的 `font()` 改为 Ark → zpix → 引擎默认三级回退，并缓存；关闭 subpixel/hinting。`intro.gd` 改为复用 `UiTheme.font()`。
  - 字号一个没动；`zpix.ttf` 保留作兜底。
- **暴君走路四方向朝向修复（2026-11-03/04）**：
  - 用户发现 `back/left/right` 三条带其实都是正脸；已重写 24 帧 prompt（镜头方向前置、背面写死「NO face / NO eyes visible」、侧面写「pure side profile + 朝左/右边缘行走」），只重出 back/left/right。
  - 去底规则补了「暗洋红地面阴影」与「地面孤立色块」清理，脚下不再有粉边/悬空血点。
  - `thw_back_08` 走了 pollinations 兜底（灰底+水印），已单帧重抽。
  - 4 条条带已重新生成（色调统一 + 16 色量化）并覆盖 `art/sprites/tyrant/walk_*.png`。
- **暴君恐怖化重做（2026-11-03）**：
  - 风格定稿 D1：苍白尸体皮肤 + 粗缝合线 + 胸口/右臂撕裂露红肉肋骨 + 滴血 + 肩部骷髅脸 + 三只红眼（含额头第三眼）+ 骨刺 + 单手巨大变异臂。
  - **断脚解法**：不要用「破烂裤脚 + 裸足」，改用 **厚黑皮靴 + 裤脚塞进靴筒**，7 张立绘与 32 帧走路脚部全部连续。
  - 7 套立绘 `tyrant_{front,chase,idle,roar,attack,break,stun}.png` 已重出并覆盖原资源。
  - 32 帧走路（4 方向 × 8 帧，含血迹/滴血/血溅）已重出 → 去底 → 缩 192 → alpha 二值化 → **帧间色调统一 + 16 色固定调色板量化** → 拼 64×64×8 条带，覆盖 `art/sprites/tyrant/walk_*.png`。
  - `tyrant.gd` 未改（`WALK_FPS=9`、`TARGET_SCREEN_H=54`、优先播放像素走路）。
  - 中间帧 `art/sprites/tyrant/horror_rebuild/ai/`、`ai_norm/` 已 gitignore（可再生）；入库的是立绘、`norm/` 条带、样张与 3 个 manifest。
- **程序化随机数学题库**（2026-10-30）：`scripts/math_gen.gd` 按需生成，`question_bank.gd` 用 `MATH_GEN_CHANCE = 0.33` 混入固定题库。
- 双工具交接制度：`HANDOFF.md` + `tools/handoff.ps1`（`-Start/-End/-Force/-Clipboard`）+ `SESSION.lock`。
- 新手关：固定教学地图、7 步引导、新过场 CG、首次启动「CG → 新手关 → 新 CG → 主菜单」。
- 主角走路/冲刺 AI 逐帧（`art/sprites/64/anim/player_walk_{front,back,left,right}.png`），冲刺复用走路帧加速（11fps → 18fps）。

## 未提交改动

无（本轮改动全部提交）。若 `git status` 不干净，先看「下一步」与开发记录顶部最新条目，再决定提交。

## 下一步

<!-- NEXT_STEPS_START -->
1. **实机验收四方向**：走一圈看正面/背面/左右是否对得上移动方向（`tyrant.gd` 里 `facing.x>0` 用 right、`<0` 用 left，且走路帧强制 `flip_h=false`）。
2. 若某个方向个别帧糊/畸形，单帧重抽：`powershell -ExecutionPolicy Bypass -File tools\gen_art.ps1 -Manifest tools\manifests\_tyrant_horror_walk_fix.json -Only twf_back_03 -Force`，再把 `tools/_gen/twf_*.png` 改名成 `thw_*.png`，依次跑 `make_ai_frames.py` → `normalize_walk_frames.py` → `build_strips.py`（脚本在 `%TEMP%\opencode\`）。
3. 觉得走路不够「沉重」可调 `scripts/tyrant.gd` 的 `WALK_FPS`（9 → 7~8）。
4. 实际玩几局看随机数学题：难度/干扰项是否合理；比例改 `question_bank.gd` 的 `MATH_GEN_CHANCE`。
5. **git push 被代理阻塞的解法**：`git -c http.proxy= -c https.proxy= push`（本机 git 配了 127.0.0.1:7897，代理没开就连不上）。
6. 每次收工必须更新本文件、追加 `开发记录.md`、commit + push。
<!-- NEXT_STEPS_END -->

## 已拍板决策（详见 需求汇总.txt）

- 暴君恐怖风格 = 剥皮 + 尸体 + 畸形 融合，基准 D1；**像素走路优先于立绘**；结构（两条腿）必须对，风格可后修。
- 暴君/怪物画脚一律用「厚黑皮靴 + 裤脚塞进靴筒」，禁用「破烂裤脚 + 裸足」（必断脚）。
- 存档不加密、单槽、带版本迁移与 .bak；背包本版只做数据接口。
- 新手关不计正式进度；宽松模式不失败；真刷追击者演示；固定 3 道送分题；教学给 3 颗假星。
- 现有追击者不接溶解特效，只保留接口；暂停必须真暂停。
- 两个 AI 同一时间只开一个；交接用本文件 + Git；DSH 开场需手动贴提示。

## 已知问题 / 风险

- **git push 被代理阻塞的解法**：本机 `git config` 里存了 `http.proxy/https.proxy = http://127.0.0.1:7897`，代理没启动时会报 `Failed to connect to github.com port 443 via 127.0.0.1`。绕过：`git -c http.proxy= -c https.proxy= push`（2026-11-03 实测可用）。
- `horror_rebuild/ai`、`ai_norm` 是本地中间帧（已忽略）；换机器后想再看逐帧需要重跑生成管线。
- 免费出图通道（imagefree / pollinations）偶发 503、连接失败、返回 JPEG 却存成 `.png`（Godot 报 `Error 16`）；用 PIL 转真 PNG 再单独跑 `--script res://tools/post_art.gd`。
- 立绘姿势区分度有限：`chase`/`idle`/`stun` 差别偏小，靠游戏内动作时序区分。
- `素材/` 仅本机存在且被忽略；换机器时 DSH 看不到候选图。
- Web 包 35.7MB（已排除 tests/tools/素材）；线上部署需用户批准后 push 触发。

## 测试状态

2026-11-04 全绿（四方向朝向修复 + 去底规则调整后）：

```powershell
$G = "E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
& $G --headless --path . --quit-after 20000 res://tests/tutorial_test.tscn   # TUTORIAL_TEST: ALL PASSED
& $G --headless --path . --quit-after 8000 res://tests/flow_test.tscn        # FLOW_TEST: ALL PASSED
& $G --headless --path . --quit-after 8000 res://tests/_stalkerprobe.tscn    # STALKER_PROBE: ALL PASSED
& $G --headless --path . --quit-after 8000 res://tests/student_test.tscn     # BAD_FRAMES=0
& $G --path . res://tests/screenshot.tscn                                    # exit 0，shot_* 全部重拍
```

> 注：Godot 测试进程有时会脱离控制台，管道里拿不到输出；最稳的读法是看 `%APPDATA%\Godot\app_userdata\卷狗必须死\logs\godot.log`（历史日志会归档成 `godot<时间戳>.log`，需逐个搜）。

## 环境

- 引擎：`E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe`
- 素材包：`E:\computerProgram2\JuanGouMustDie\素材\PixelSRPG-Forge-main`（本地，不入库）
- 参考库：`tools/_gen/godotarchive`（本地，不入库）
- 构建：`powershell -ExecutionPolicy Bypass -File tools\build_web.ps1`（需 `$env:GODOT`）
- 交接工具：`powershell -ExecutionPolicy Bypass -File tools\handoff.ps1`（`-Clipboard` 复制摘要；`-Start <tool> -Intent "..."` 加锁，`-End` 解锁）
