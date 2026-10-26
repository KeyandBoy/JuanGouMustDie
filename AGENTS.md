# 协作约定（给 AI / 接手开发者）

1. 动手前先读 `开发记录.md`（架构、约定、坑、路线图）和 `需求汇总.txt`（需求来源）。
2. **双工具交接（opencode / DeepSeek Harness）**：
   - 同一时间只开一个 AI；开工运行 `powershell -ExecutionPolicy Bypass -File tools\handoff.ps1 -Start <tool> -Intent "..."`，
     收工运行 `-End`（`SESSION.lock` 会阻止第二个工具同时开工）。
   - 开工顺序：`git pull` → 读 `HANDOFF.md` → `tools\handoff.ps1`（或 `-Clipboard` 复制摘要）→ 读 `开发记录.md` 顶部 3 条 → `git status`。
   - 收工顺序：跑四套测试（必要时截图）→ 更新 `HANDOFF.md`（下一步用 `<!-- NEXT_STEPS_START -->` / `<!-- NEXT_STEPS_END -->` 包裹）→ 追加 `开发记录.md` → `commit + push` → 把 HEAD 写回 HANDOFF。
   - DSH 不会自动读本文件，每次开场粘贴：
     ```
     先读 AGENTS.md 和 HANDOFF.md，运行 git status，复述「当前目标/下一步/测试命令」，确认后再改。
     收工按 AGENTS.md 更新 HANDOFF、追加开发记录，并 commit + push。
     ```
3. 每次改动必须：
   - 跑四套测试：`flow_test` / `_stalkerprobe` / `student_test` / `tutorial_test`（命令见 `开发记录.md` 第 2 节）；
   - 涉及画面时跑 `tests/screenshot.tscn` 并目视检查 `tests/shot_*.png`；
   - 在 `开发记录.md` 的「变更日志」顶部追加：日期、改了什么、为什么、怎么验证；
   - 需求有增减时同步 `需求汇总.txt`。
4. 不改中文文件编码（必须 UTF-8 无 BOM）；不要用会写 GBK 的 PowerShell 追加方式。
5. 引擎固定为 Godot 4.7.2，路径见 `开发记录.md`；不擅自更换引擎版本或框架。
6. **提交规则（用户已授权）**：每次会话收工必须 `commit + push`（允许 WIP 提交）；不删除 `tests/shot_*.png` 基线、不改动 `assets/music/CREDITS.txt` 的授权信息、不提交 `素材/` 与 `tools/_gen/`。
7. **开发者版 / 正式版**：新增任何"只在开发者版出现"的功能（调试可视化、参数热调、作弊入口），
   必须在 `scripts/dev_mode.gd` 加开关，并在 `开发记录.md` 4.9 的差异清单登记一行。
   正式版由 `OS.is_debug_build()` 自动关闭，不要用密码/隐藏按钮之类记不住的手段。
8. **弹窗层级**：所有弹窗只能通过 `main.gd` 的 `_push_modal()` / `_pop_modal()` 创建和关闭，
   禁止写死 `layer.layer`；层号唯一来源是 `main.gd` 顶部的 `L_*` 常量。
