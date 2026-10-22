# 协作约定（给 AI / 接手开发者）

1. 动手前先读 `开发记录.md`（架构、约定、坑、路线图）和 `需求汇总.txt`（需求来源）。
2. 每次改动必须：
   - 跑三套测试：`flow_test` / `_stalkerprobe` / `student_test`（命令见 `开发记录.md` 第 2 节）；
   - 涉及画面时跑 `tests/screenshot.tscn` 并目视检查 `tests/shot_*.png`；
   - 在 `开发记录.md` 的「变更日志」顶部追加：日期、改了什么、为什么、怎么验证；
   - 需求有增减时同步 `需求汇总.txt`。
3. 不改中文文件编码（必须 UTF-8 无 BOM）；不要用会写 GBK 的 PowerShell 追加方式。
4. 引擎固定为 Godot 4.7.2，路径见 `开发记录.md`；不擅自更换引擎版本或框架。
5. 未经用户明确要求，不提交 git、不删除 `tests/shot_*.png` 基线、不改动 `assets/music/CREDITS.txt` 的授权信息。
6. **开发者版 / 正式版**：新增任何"只在开发者版出现"的功能（调试可视化、参数热调、作弊入口），
   必须在 `scripts/dev_mode.gd` 加开关，并在 `开发记录.md` 4.9 的差异清单登记一行。
   正式版由 `OS.is_debug_build()` 自动关闭，不要用密码/隐藏按钮之类记不住的手段。
7. **弹窗层级**：所有弹窗只能通过 `main.gd` 的 `_push_modal()` / `_pop_modal()` 创建和关闭，
   禁止写死 `layer.layer`；层号唯一来源是 `main.gd` 顶部的 `L_*` 常量。
