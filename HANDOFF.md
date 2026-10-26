# HANDOFF（双工具交接状态）

- 更新时间：2026-10-26
- 最后操作：opencode
- 分支：main
- 当前 HEAD：0e0e75e（已推送）
- 工作区：干净（素材/ 与 SESSION.lock 已忽略）

## 当前目标

维护《卷狗必须死》并继续素材替换评估：先由用户从候选图中确认道具图标/角色模型是否替换，再进入实现。

## 本轮已完成

- 新手关：固定教学地图、7 步引导、广播/任务文案定稿、出发广播杂噪音效、新过场 CG（3 张 AI 图）、首次启动「CG → 新手关 → 新 CG → 主菜单」。
- 第 1 关广播提示删除；主菜单「重看开场动画」改名「重历开场」并重播全流程。
- 修复：暂停真正暂停场景树；追击者补碰撞体（不再贴脸）；烟雾/臭气弹无目标也可放下；空虚值每答对 +5；HUD 挡视野时换右上；门上瓦片层级；玩家高光移除；右上小地图下线（接口保留）。
- 素材包 `PixelSRPG-Forge-main` 已调研并按 409 个图标切片到 `素材/_preview/sliced/icons`（本地，不入库）；`素材/` 已加入 .gitignore 与 Web 导出排除。

## 未提交改动

无。若 `git status` 不干净，先看「下一步」与开发记录顶部最新条目，再决定提交。

## 下一步

<!-- NEXT_STEPS_START -->
1. 让用户看 `素材/_preview/items_final_candidates.png`：目前可用候选为 bread=b3_13、notes=b3_18、shovel=b3_21、portal=b12_0、lamp=b3_19（左半 24px）、stink=b13_17（上半裁剪），其余（咖啡/烟雾/椅子/鞋/秒表/情报/耳塞）素材库无合适同名图标 → 建议保留现有图标。
2. 让用户看 `素材/_preview/characters_candidates.png`：包内角色（Ghost/Slime/Skeleton/Priest/骑士/FarmLife）分辨率与风格均弱于现有 64–192px 素材 → 建议不替换；若要升级追击者，改用 `tools/gen_art.ps1` 生图管线出一张 124×192 透明底新立绘。
3. 用户批准后：把选中的图标复制到 `art/ui/icons/<id>.png`（保持 48px 内透明、NEAREST），重新导入并跑四套测试 + screenshot；角色替换同理。
4. 每次收工必须更新本文件、追加 `开发记录.md`、commit + push。
<!-- NEXT_STEPS_END -->

## 已拍板决策（详见 需求汇总.txt）

- 存档不加密、单槽、带版本迁移与 .bak；背包本版只做数据接口。
- 新手关不计正式进度；宽松模式不失败；真刷追击者演示；固定 3 道送分题；教学给 3 颗假星。
- 现有追击者不接溶解特效，只保留接口；暂停必须真暂停。
- 两个 AI 同一时间只开一个；交接用本文件 + Git；DSH 开场需手动贴提示。

## 已知问题 / 风险

- `素材/` 仅本机存在且被忽略；换机器时 DSH 看不到候选图，需要重新解压/生成预览。
- 部分切片把相邻图标粘连（如 b3_19 含灯+魔杖、b13_17 含上下两个物体），替换前必须再裁干净并目视。
- 素材包 README 声明版权不确定（仅仓库结构 MIT），**未确认授权前不要公开发布这些素材**。
- Web 包 35.7MB（已排除 tests/tools/素材）；线上部署需用户批准后 push 触发。

## 测试状态

2026-10-26 全绿：

```powershell
$G = "E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
& $G --headless --path . --quit-after 20000 res://tests/tutorial_test.tscn   # TUTORIAL_TEST: ALL PASSED
& $G --headless --path . --quit-after 8000 res://tests/flow_test.tscn        # FLOW_TEST: ALL PASSED
& $G --headless --path . --quit-after 8000 res://tests/_stalkerprobe.tscn    # STALKER_PROBE: ALL PASSED
& $G --headless --path . --quit-after 8000 res://tests/student_test.tscn     # BAD_FRAMES=0
& $G --path . res://tests/screenshot.tscn                                    # exit 0
```

## 环境

- 引擎：`E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe`
- 素材包：`E:\computerProgram2\JuanGouMustDie\素材\PixelSRPG-Forge-main`（本地，不入库）
- 参考库：`tools/_gen/godotarchive`（本地，不入库）
- 构建：`powershell -ExecutionPolicy Bypass -File tools\build_web.ps1`（需 `$env:GODOT`）
- 交接工具：`powershell -ExecutionPolicy Bypass -File tools\handoff.ps1`（可 `-Clipboard` 复制摘要）
