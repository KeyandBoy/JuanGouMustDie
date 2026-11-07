# HANDOFF（双工具交接状态）

- 更新时间：2026-11-07
- 最后操作：opencode
- 分支：main
- 当前 HEAD：`3fe38ff`（Deep-Fold 怪物生成器 + 暴君预览修复）
- 已推送 origin/main：`3fe38ff`
- 工作区：`tests/shot_*.png` 已重拍但故意不提交；另有另一窗口的 `_blob_probe` / `intro.gd` / `art/cutscene` 等改动，**不要误提交**。
- 另外：`素材/` 被 gitignore 且授权不明；`art/furniture/README.md` 已标注「授权未确认，发布前替换」。

## 最简用法（推荐）

- **用 DSH**：双击项目根目录的 `开始DSH.bat` → 打开 DSH，`Ctrl+V` 粘贴一次 → 开始开发；收工双击根目录 `结束会话.bat`。
  - `开始DSH.bat` 会自动加锁、把「开场提示 + 当前进度」放进剪贴板（`tools\start_dsh.bat` 是同一功能的副本）。
  - `结束会话.bat` 解锁；收工前仍要按 AGENTS 跑测试、更新 HANDOFF、commit + push。
- **用 opencode**：直接打开即可，不需要手动跑加锁/摘要命令。
- `git pull` 只在换电脑、或另一个工具刚推送过时执行。
- 如果加锁提示 `LOCK BUSY`：说明上一个会话没正常结束，双击根目录 `结束会话.bat` 解锁即可。

## 当前目标

大工程「连续卷轴大地图 + 房间区分度 + 探索感」的 **Phase 1~4 已完成并提交**：单张连通大地图、
10 房型放大、死区相机、三态探索迷雾、小地图启用、房型专属家具、套间/环路 + 隐藏奖励。

接下来是 **Phase 5 收尾**：只看真实手感做微调（装饰/课桌/敌人密度、房间辨识度），
以及把 EFG 剩余大件逐个单独立项（E1 模板插门、E6 SubViewport 小地图、F5 情报共享、F6 Boss 多阶段、
G1 12 格背包、G2 点选放置、G8 护符、G12 掉落权重表）。
D8 脚步采样已补齐（Kenney CC0）；**只剩 D6 的同 BPM 追逐鼓点层**需等分轨素材。

## 本轮已完成

- **暴君走路重做（2026-11-07，opencode）**：
  - 原 AI 8 帧结构逐帧漂移、双脚永远贴地；新增 `tools/tyrant_walk_rig.py`，以每个方向第 1 帧为固定设计做纸娃娃摆动。
  - 侧视：腿绕髋 ±15°、臂绕肩 ±9°（能看到跨步/交叉）；正视/背视：左右腿交替抬起 2px + 内收 1px、臂 ±6°。
  - 重新生成 4 方向 8 帧 walk、idle、turnaround；`tyrant_view.html` 同步更新。
  - 验证：4 方向条带目视 + flow/student/tutorial/_b/_stalker 通过。
- **Deep-Fold 怪物生成 + 暴君预览修复（2026-11-07，opencode）**：
  - `tyrant_view.html` 的 `background-size` 高度写成了 4 行，导致暴君条带被纵向拉伸、只剩半身；已改成 1 行。
  - 新增 `tools/deepfold_monsters.py`：按 Deep-Fold/SpriteGenerator（MIT）源码移植；保留对称随机块、4 步 CA、余弦调色板、洪水填色、眼睛/描边，增加 `--mood flesh|necro|void|all` 猎奇配色。
  - 产出 `art/sprites/monsters/`：`monster_01..30`（48px 原版色）、`grotesque_101..118`（64px 猎奇色）、两张联系表、`README.md`（来源/授权/命令）。
  - PixelDudes Maker（0x72）本机无法访问 itch、也没有本地副本，本轮未使用；拿到 zip 放 `素材/` 后可继续。
  - 验证：Godot 成功导入 50 张 PNG；联系表目视正常。
- **暴君补齐 4 方向站姿 / 转身模型图（2026-11-07，opencode）**：
  - 保留原 AI 恐怖画风，不改成 LPC；从已有 4 方向 walk 条带取第 1 帧做站姿，再生成一帧「脚底不动、身体压缩 97%」的呼吸帧。
  - 新增 `tools/tyrant_multiview.py` → `idle_{front,back,left,right}.png`（2 帧）+ `turnaround.png`（4 方向转身模型图）。
  - `tyrant.gd` 站立时播 4 方向 idle（2.4fps），移动仍播 8 帧 walk；咆哮/攻击/破门/眩晕仍是单张立绘。
  - 验证：flow / student / _b / _stalker 通过；`shot_tutorial_tyrant` 目视。
- **修正 LPC 行走行映射 + 暴君改回原形象（2026-11-07，opencode）**：
  - `data/character.anim` 是 CharGen 拼接后的导出表坐标，不是原始 LPC 图层坐标；之前把 `thrust` 当成了 `walk`（游戏里主角走路是「拳头往前」）。现按原始 universal 表取帧：walk y=512~704、slash 768、shoot 1024、hurt 1280 等，5 个角色全部重新导出。
  - 暴君按需求保留原 AI 恐怖形象：`tyrant.gd` 走路改回 `art/sprites/tyrant/walk_*.png`，删除 LPC 暴君素材；暴君肖像改为从原立绘裁头肩。
  - 十二套测试全绿；`shot_world` 走路姿态、`shot_tutorial_tyrant` 暴君形象已目视。
- **角色全动作 / 地板美化 / 像素肖像（2026-11-07，opencode）**：
  - 角色：`tools/chargen_compose.py` 直接解析 CharGen 的 `chargen.pak` + LPC 色表，6 套配方（juan/player/student/teacher/guard/tyrant）输出 4 方向 walk 8 帧 + idle 2 帧 + `actions/` 每人 29 组全动作（180 个文件）。暴君用最近邻 2 倍做「大体积」。`player.gd` / `student.gd` / `tyrant.gd` 已接入；`VISUAL_SCALE=0.78`，影子 y=23.5。
  - 地板：`tools/tilemancer_tiles.py` 复刻 Tilemancer 的节点算法，生成 6 风格 × 6 变体 20px 无缝图集；`school_map.gd` 按房型取行、乘房间基色。
  - 肖像：`tools/pck_extract.py` + `extract_portrait_layers.py` 从 Godot 3.5 PCK 解出 295 张 WEBP 图层；`make_portraits.py` 复刻原版 shader（红=暗、绿=亮、蓝=阴、灰度按明度插值）生成 6 张 96px 头肩 + 64px 头像裁切；`dialogue_db.gd` 已接说话人 → 头像。
  - 验证：12 套测试全绿（`_e_probe` 首跑有已知偶发 e3/e4，重跑通过）；`shot_world` / `shot_tutorial` / `shot_tutorial_tyrant` 目视正常；对话框 44px 头像用临时探针确认。
- **正式关不再弹窗（2026-11-06，opencode）**：`_on_level_card_pressed()` 不再调 `_maybe_show_level_dialogue()`，1~5F 进关没有任何「广播/系统」弹窗；新手关引导保留。
- **第三轮验收：圆形照明 / 房型专属物品 / 排排列列 / 效率重做（2026-11-06，opencode）**：
  - 照明改「玩家周身圆形光」：遮罩 R 通道存当前区域，着色器做圆形光照 + 羽化，**光被墙挡住**；圈外已探索压暗/未探索更暗。
  - 厕所改成一排 3×4 格隔间（带碰撞薄隔板）+ 每间一个坐便器 + 门口洗手台，**不再有课桌**；储物间/楼梯间也没有课桌。
  - 各房型按场景给物品：讲台/书架/工位/实验台/病床+帘子/主播台+机柜/货架。
  - 课桌按列距 6、行距 5 的网格摆（中间纵向过道）；同墙多件家具均分槽位对齐。
  - 效率重做：`study_points` + `study_efficiency_at()`，空地 1.0、靠近学习点线性变化，负向点（厕所 0.60 等）取 min；HUD 实时显示倍率。
  - 验证：`_map_probe` / `_big_probe` 全绿；样张 `shot_room_toilet` / `shot_room_classroom` / `shot_corridor_glow`。
- **系统说明只在新手关（2026-11-06，opencode）**：删掉 `_on_level_card_pressed` 里「首次进入弹系统说明」的分支（`story_flags["dlg_tutorial"]` 会被读档覆盖，导致每关都弹）；两条「系统」说明挪到 `tutorial.gd` 第 1 步开场对白最前面，1~5 关只保留剧情提示。
- **验收第二轮修正（2026-11-06，opencode）**：
  - 小地图改挂**左侧状态卡正下方**（`main._layout_minimap()` 每帧跟随状态卡，卡片换边也跟着换）。
  - 探索遮罩重写：整张图按「每格 1 像素」烘一张三态遮罩纹理 + `shaders/fog_mask_soft.gdshader` 3×3 帐篷模糊，房间/走廊边界变成约 2 格宽的柔和光晕，不再是硬边方块；测试改读 `fog.zone_alpha(zone)`。
  - 删除假的「视差楼体剪影」（`parallax_bg.gd` 与 `backdrop_brick` 着色器都删了）：读参考项目 `PixelGame-Public-master` 后确认他们地图外就是**纯色相机底色**（`Camera.main.backgroundColor = (24,20,37)`），没有任何视差假剪影；假剪影的视差位移会飘进房间变成「跟着主角走的黑条」。
  - 地图四周补 20 格实心砖墙（`school_map.MAP_PAD` + `_pad_map()` + 图集深色砖纹），镜头贴边时看到的是墙体；镜头边界改回 `world_rect`；小地图改用 `content_rect()` 计算比例。
  - 参考项目另外两处值得记住的写法：相机是「跟玩家 + 鼠标方向 look-ahead + `Lerp(1/damp*dt)` + `Mathf.Floor` 像素对齐 + 边界 `Clamp`」；小地图是**第二台相机**而不是 UI 手绘（本作目前仍是 Control 自绘，够用）。
- **验收反馈修正（2026-11-06，opencode）**：
  - 镜头改「房间居中」：目标 = 当前房间/走廊段中心，只在玩家偏离超过 26% 视口半宽时拉回（`zone_center_at` + `CAMERA_PLAYER_MAX_OFF`），边界放宽 16 格让最外圈房间也能居中；`DEAD_ZONE_*` 已删除。
  - 房间再放大（教室 34~46 格宽、进深 22~30，最小房型 ≥24 格），`zoom 0.85 → 0.95`，课桌上限 18；最大的房间也仍能整间入镜。
  - 迷雾配比：未探索 0.86（暗但看得出轮廓，不再死黑）、已探索 0.46、当前不遮。
  - 小地图 184×126（仍在状态卡下方），配合房间居中不再压住主角。
  - 新增 `shaders/backdrop_brick.gdshader` + 深蓝灰 clear color，地图外不再是纯色空白。
  - 十二套 + `_map_probe` 全绿；截图重拍。
- **连续卷轴大地图 Phase 1~4（2026-11-06，opencode，大工程）**：
  - `school_map.gd`：10 房型（教室/实验室/图书/医务/办公/储物/广播/厕所/楼梯/大厅），每层保底教室+厕所；房间放大 2~3 倍、走廊 10~12 格；两行地砖图集（每房型 6 种地板图案 + 16 邻接墙砖）；课桌/敌人按面积；`big_items` 房型专属大件（碰撞 + 贴墙装饰 + 地毯）从 `art/furniture/` 贴图绘制。
  - `main.gd`：相机固定 zoom 0.85（教程 1.45）+ 死区跟随（0.20/0.22）；小地图常开移到状态卡下方；敌人 7~16 按地图面积。
  - `fog.gd`：三态遮罩（未探索纯黑 / 已探索压暗 0.58 / 当前整间亮），走廊按门到门切段点亮；删除 30 秒忘记机制；手电锥只在停电时开。
  - `minimap.gd`：只画已探索房间/走廊段、按房型着色、楼梯/道具/答题点标记、敌人仅情报生效时显示。
  - 套间：大房间 65% 概率掏「里间」（1 格墙 + 2 格开口 + 门），独立探索、固定当宝箱房、额外塞一件奖励；环路：8 房以上 50% 概率在同排相邻房之间多开 2 格通道。
  - 关键坑：里间矩形在母房内部 → 所有「按点找房间」的函数必须倒序遍历；`_walkable_center` 必须传 `room_idx`；家具只能放 `_room_cell == 本房` 的格子。
  - 测试：新增 `_map_probe` / `_big_probe` / `_nested_shot`；十二套全绿 + 两个新探针全 PASS；截图目视 `shot_world` / `shot_nested_parent` / `shot_nested_inside` / `shot_loop_passage`。
- **D8 脚步材质（2026-11-06，opencode）**：
  - 素材：Kenney「Impact Sounds」（CC0）concrete/wood/carpet 各 5 条 → `assets/sfx/step/step_{tile,wood,carpet}_1..5.ogg`；峰值归一 -3dBFS、单声道 OGG，授权原件与 CREDITS 均已登记。
  - `play_footstep()` 5 变体随机；材质映射：教室/办公室/储物间=wood、安全屋(L6+)=carpet、楼梯及其余=tile。
  - `_d_probe` 断言改为「三种采样存在且能播」；D_PROBE + 四套测试全绿。
  - `main.gd` 与另一会话并发：只用 `git hash-object`+`update-index` 暂存了 `_floor_material_at` 一个 hunk，镜头死区改动仍留在工作区未提交。
- **B12 条件化 + 安全屋分层（2026-11-06）**：
  - 手电只在 `GameState.dark_vision`（停电/剧情 blackout/开发者关灯）时亮，普通关默认熄灭。
  - `fog.gdshader` 增加锥形可视区（24°/260px）；停电时圆形视野缩至 55%、雾气 alpha 提高，手电外几乎全黑。
  - 红眼只在黑暗状态亮，且仍只出现在手电/圆形视野内。
  - 第 4 关随机停电：间隔 8~16s、每次 0.3~1.0s 后恢复；停电关走廊灯、压暗世界、首次提示。
  - 安全屋改为第 6 层起启用（`SAFE_ROOM_MIN_LEVEL=6`），前五层没有安全屋。
  - 测试：`_b_probe` / `_fx_probe` / `_e_probe` 已更新；十二套全绿；`tests/_b_shot.tscn` 输出停电样张。
- **修复「黑色球状图层跟着主角跑」（2026-11-05，opencode）**：
  - 病根是 B13 视差 `parallax_bg.gd`：`off = -cam*f` 写反了（应为 `+cam*(1-f)`），树影以 1.16 倍相机速度漂移，看着就黏在主角身上；首帧 `_cam_pos = INF` 还会画出退化图形。
  - 已改公式、初始化相机位置、加 `is_nan` 保护；因窗外是纯黑，树冠/枝影用 `SHOW_TREES = false` 默认关闭（要开改 true，且窗外必须有亮部）。
- **B 组收口（2026-11-05）**：
  - B12：`torch_light.gd` 纯代码手电锥（24°/128px，随 face_dir 旋转）；`eye_glow.gd` 敌人红眼（暴君常亮、学生 chase/search/stalk，L1 白天不可见）。
  - B13：`parallax_bg.gd` 两层程序视差（窗外树冠 16%、楼体 7%），z=-7，12Hz 重绘。
  - `flow_test` 旧“玩家不能有 PointLight2D”断言改为“手电存在且有锥形贴图”；新增 `_b_probe`；十二套测试全绿。
- **E/F/G 批次（2026-11-05）**：
  - E2：入口改为离楼梯最远房间；随机出生排除入口。
  - E3：`main_path_rooms` + `is_main_path()`。
  - E4：L4+ Boss 房（暴君优先登场）、宝箱房（首件道具优先）。
  - F8：学生每层视野 +8%、移速 +5%；F1：0.3s 决策 tick。
  - G11：残页 5 张换提示符，答题可排除一个错项；G5：四档稀有度 + 加权掉落。
  - 新增 `_e_probe` / `_f_probe` / `_g_probe`；十一套测试全绿。
- **D 组音频（2026-11-05）**：
  - D5：新增 Ambience 播放器，L2~L5 循环 `broadcast_noise`（-27dB、2s 淡入），菜单/教学/过场关闭。
  - D6：新增 Pressure 播放器，`tyrant_active` 时叠 `amb_tyrant_drone`（-19dB、1.8s 淡入）；曲库改 active。
  - D8：`AudioManager.play_footstep()` + `main` 按移动距离/房间材质触发；脚步素材缺文件时静音。
  - 新增 `tests/_d_probe.tscn`；八套测试全绿。
- **C 组 UI（2026-11-05）**：
  - C6：`hud.toast()` 改队列，同屏最多 3 条、错峰淡出，通知与底部交互提示分离。
  - C1/C8：主菜单左下角版本号 `v0.9.0` + 当前 BGM 曲名/作者（读 `catalog.json`）。
  - C5：`hud.bind_tooltip()`，悬停 0.4s 显示道具名/描述，自动贴边。
  - C4：限时效果条（图标 + 竖向剩余条 + 秒数），数据走 `GameState.active_effects`。
  - C10/C13：失败界面补正确率、最近 3 道错题、随机小贴士。
  - C2：楼层卡片显示历史最佳时间/冲星分，存档新增 `level_best`。
  - C3：HUD 状态条按重要度分层（理智 18 / 净答对 12 / 闪避 7）。
  - 新增 `tests/_c_ui_probe.tscn`；七套测试全绿。
- **B 组第一批（2026-11-05）**：
  - B4：`scripts/shadow.gd` 统一椭圆影子（三层柔边），player/student/tyrant 已挂；主角按走路条带脚底 y=62 定位（y+21.5），暴君按 `offset=-h/2` 对齐到原点。
  - B9：`tools/repack_icons.py` 把 17 个 UI 图标统一成 32×32（内容 ≤24×24），未重画。
  - B14：`interactable.gd` 课桌双层暖色呼吸描边（~10Hz）。
  - B11：`school_map.gd` 的 `decor_items` + `_spawn_decor()` + `_draw_decor()`，每房 3~12 个靠墙装饰，避开课桌/门/导航点/房间名/黑板。
  - B1/B5/B6/B7：写进 `tools/ART_PIPELINE.md` 第 10 节（20px 网格、角色尺寸档、命名、图层常量）；B2/B3 的描边与色板规范同节。
  - 验证：六套测试全绿，`screenshot.tscn` 非 headless 跑通。
- **A 组收口（2026-11-05）**：
  - A9：`Fx.slowmo(0.3, 0.4)`，与 `hitstop` 不叠加、计时器 `ignore_time_scale`；暴君死亡流程未做，先留 API。
  - A4/A6：`_shake_camera` 取更大者不叠加 + 0.04s 量化 + `round()`；5 处硬编码全改 `Fx.shake(tier)`。
  - A8：`hud.fly_item()` 图标从地面飞入背包槽、落位闪金；音效留给音频窗口。
  - A10：`scripts/breath.gd`（calm/tense/panic/blind，panic > blind > tense > calm）；main 每帧汇总 chased/uneasy/dark，被抓/暴君撞 `notify_hurt(10s)`；只出状态与预留音轨槽。
  - A13：死亡定格 0.4s → 0.3s。
  - 事故：`main.gd` 曾被 PowerShell 按 GBK 重写成乱码并解析失败，已从 git 恢复 + edit 重做；以后只用 edit 工具改中文源文件。
- **设置面板 + 右下角圆形设置按钮（2026-11-05）**：
  - `scripts/gear_button.gd`：52×52 圆形深色圆盘 + 代码绘制齿轮，hover 提亮/齿轮转金，按下 92%，无需美术素材。
  - 主菜单齿轮从右上角移到右下角，删除底部「设置」长条按钮；游戏内 HUD 右下角常驻同款齿轮（`SettingsGear`），教学关「跳过教学」左移避让。
  - `scripts/settings_ui.gd`：左分类/右内容、分类数据驱动；声音（主/音乐/音效三条真滑条 + 静音）、画面（全屏、震屏 0/50/100）、操作、关于。打开暂停游戏，关闭恢复原状态。
  - `tests/_settings_probe.tscn` 断言齿轮位置、暂停/恢复、弹窗栈；截图 `_shot_menu_gear.png`、`_shot_settings_audio.png`、`_shot_hud_gear.png`。
- **房间角色/纵深（2026-11-05）**：`school_map.gd` 用导航图多源 BFS 算 depth（与布局无关），角色 stair/hall/deep/safe/normal；安全屋禁止答题、回理智 +8、每层一次；deep 课桌效率 ×1.35。
- **反馈层 S1（2026-11-05）**：`fx.gd` + HUD 飘字池/红晕/星数滚动；答题/被抓/暴君撞/死亡定格补齐多层反馈；`_fx_probe` 全绿。
- **新手关结尾 3 张 CG 水墨化（2026-11-05）**：
  - `tutorial_outro_1~3` 换成水墨版（`tools/manifests/outro_panels.json` → `tools/finalize_cg.py` → `art/cutscene/`）：空教室晨光 / 暗走廊无脸人影 + 红色应急灯 / 仰视楼梯过曝门洞。
  - `intro.gd` 的 `OUTRO_SCENES` 补上推镜参数：1 号 1.01→1.09（抖动 0.6）、2 号危险镜头默认、3 号 1.02→1.16（抖动 1.0）。
- **开场 CG 重做 + 伪动效（2026-11-04）**：
  - 三张 16:9 水墨稿覆盖 `art/cutscene/intro_classroom|intro_board|intro_hall.png`，清单 `tools/manifests/intro_panels.json`。
  - 新增 `tools/finalize_cg.py`：裁白边 + 强制黑白单红，可选 `--dark` / `--blur`（黑板那张就是压暗+虚化出来的）。
  - `intro.gd` 新增 `_cam` 摄影机层：整幅缓慢推近（`TRANS_SINE/EASE_OUT`）+ 每帧手持抖动（`jitter`），危险镜头自动加到 2.4px、红闪瞬间 9px；每场景可用 `zoom_from/zoom_to/jitter` 覆盖。

- **D7 UI 三音（2026-11-05）**：
  - 素材来自 Kenney「Interface Sounds」（CC0，无需署名）：`ui_hover` / `ui_click` / `ui_confirm`，峰值归一 -3dBFS + OGG q5。
  - 4 个 UI 播放器挂 UI 总线，音量跟「音效音量」滑条。
  - 悬停用轮询 `gui_get_hovered_control()`（菜单按钮是运行时建的，连信号会漏）；点击走 `_input` 左键 + `ui_accept`。
  - 用户明确：**不要程序合成音效，一律找现成素材**。
- **音频结构 D1~D4（2026-11-04）**：
  - D4：`default_bus_layout.tres` = Master / Music / SFX / UI / Ambience，音量统一走 `AudioServer`，设置仍存 ConfigFile（新增 `sfx` 键）。
  - D1：BGM 双轨交叉淡入，循环曲 1.5s、一次性短句 0.25s。
  - D2：12 + 8 音效池，同名最多 3 个；暴君挥击不再每次 new 节点。
  - D3：`assets/sfx/{alarm,ambient,creature,impact,step,ui,pickup}`，引用路径全部更新。
  - 未做：D5/D6/D7/D8、SFX 滑条 UI（`set_sfx_volume()` 已就绪）。
- **暴君登场分镜重做 · 真漫画页（2026-11-04）**：
  - 旧 `tyrant_p1~p4` 是四张单幅插画硬拼，没有分格/格线/对白 → 用户判定「不是分镜」。
  - 改为 **12 格逐格出图 → 程序排版成 4 页 1200×900（4:3）**：
    `tools/manifests/tyrant_intro_panels.json`（12 条 prompt）+ `tools/gen_panels.py`（只用 imagefree，429 退避，**不走 pollinations 兜底**）+ `tools/compose_manga.py`（格线 / 对白泡泡 / 拟声词 / 旁白黑框 / 黑白+单红统一 / 裁白边）。
  - 游戏内 `main.gd` 暴君登场改为**逐页全屏播放**（底部字幕 + 右上角 `1 / 4` 页码），`tests/screenshot.gd` 的后续等待 6.5s → 11.0s。
  - AIMangaStudio / ComicFlow-Engine 两条路都已排除并记入开发记录：前者浏览器直连 Google 被墙且用户给的是 OAuth 令牌，后者只能 PDF 转短视频、无生成能力。

- **补首批配乐 · Audionautix（2026-11-04）**：
  - 新入库 5 首（全部 CC BY 4.0，**必须署名**）：`cutscene_dread.ogg`（The Childrens Room，过场）、`clear_victory.ogg`（Big Intro #2，11 秒胜利短句）、`gameover_somber.ogg`（Somber，失败）、`tension_mid.ogg`（Night Runner，L2~L4 紧张，**standby**）、`amb_tyrant_drone.ogg`（Horror Drone #1，暴君压迫层临时替代，**standby**）。
  - 统一转码 OGG Vorbis + loudnorm -16 LUFS；命名 `<槽位>_<气质>.ogg`。
  - `_desired_key()`：`cutscene` / `cleared` / `gameover` 三个状态真正响应对应曲子（之前分别是静音 / 复用 happy / 静音）。
  - 新增 `catalog_slot_loop()`，按曲库 `loop` 字段决定是否循环（胜利短句只播一次）。
  - 署名写进 `assets/music/CREDITS.txt`（新增分段）、`catalog.json`、`CATALOG.md`。
- **背景音乐曲库化（2026-11-04）**：
  - 新增 `assets/music/catalog.json`（唯一真相源，18 条 = 在用 6 + 备用 3 + 待补 9），双主键（玩法状态 + 情绪），含 `level_scope` / `layer_role` / `intensity 1~5` / `elements` 描述标签 / `license`。
  - 新增 `tools/music_catalog.py`：校验 + 导出 `assets/music/CATALOG.md`（在用表、备用表、待补表、状态索引、声音元素索引、授权审计）。
  - `audio_manager.gd` 改为按 `slots` + `level_scope` 从曲库解析文件，`TRACK_PATHS` 降级为兜底；状态机 `_desired_key()` 未改，行为零变化。
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

- `tests/shot_*.png`：本轮 `screenshot.tscn` 重拍产生的基线变化，故意不提交（经常被重拍）。
- `tests/_blob_probe.*` / `tests/_blob_a|b.png` 等：来自另一窗口的探针文件，**不要误提交**。
- 其余本轮的代码 / 工具 / `art/` 资源已随本次提交入库。

## 下一步

<!-- NEXT_STEPS_START -->
1. **角色素材收尾（下一步优先，本轮刚做完）**：`art/sprites/lpc/actions/` 已有每人 29 组全动作，但游戏还没接攻击/施法；如果后续给暴君加技能或给玩家加动作，直接按 `index.json` 取条带。另：老师/保安/学生/卷狗现在只在追击者里出现，若后续加对话，头像已在 `dialogue_db.PORTRAITS` 登记。
2. **Phase 5 手感微调**：拿 `_big_probe` 输出的每间房课桌/家具数量，把装饰密度往「8~12 件」收、确认大教室里课桌不空、确认敌人 7~16 的曲线；觉得房间还不够好认时优先补「墙面特征」（黑板/画框/出口标识），不要加新系统。
3. **套间/环路手感**：里间门口的「门」现在和普通门一样（E 开关）；如果玩家根本找不到，考虑给套间门加一点视觉提示（半开/门牌），但别破坏「探索才找到」的意图；环路门洞目前是墙上的 2 格缺口，可考虑加门框描边。
4. **家具贴图是原型**：`art/furniture/README.md` 已写明来源与「授权未确认，发布前替换」；确认授权或自绘后按同名覆盖即可（代码按 rect 拉伸，尺寸可不同）。
5. **EFG 剩余大件**（每项先确认再动）：E1 模板插门、E6 SubViewport 小地图（本轮小地图是 Control 直接画，需复核是否还要独立 Viewport）、F5 情报共享、F6 Boss 多阶段、G1 12 格背包、G2 点选放置、G8 护符、G12 掉落权重表。
6. **A9 接调用点**：等「击败暴君」流程落地后，在暴君死亡演出第一帧调 `Fx.slowmo(0.3, 0.4)`（命中仍用 `Fx.hitstop`，两者共用 `time_scale`、不会叠加）。
7. **A10 / A8 接线**：音频窗口按 `Breath.state` 播放呼吸循环（`assets/sfx/breath/breath_{tense,panic,blind}.ogg` 已预留）；拾取「叮」在 `main._on_item_picked()` 接 `AudioManager.play_sfx`。
8. **D6 追逐鼓点层**：仍需与 `chase_electro` 同 BPM 的分轨素材；D8 三套脚步采样已齐。
9. **测试命令**：十二套（flow / _b / _fx / _settings / _c_ui / _d / _e / _f / _g / student→BAD_FRAMES=0 / tutorial / _stalker）+ 本轮新增 `_map_probe` / `_big_probe`；截图用 `screenshot.tscn`（非 headless），套间样张用 `_nested_shot.tscn`。
10. 每次收工必须更新本文件、追加 `开发记录.md`、commit + push。
11. **禁止用 PowerShell `Get-Content/Set-Content` 改中文源文件**（会按 GBK 重写成乱码并吃掉引号）；一律用 edit/write 工具。
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

2026-11-07 全绿（角色全动作 / 地板 / 肖像后）：

```powershell
$G = "E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe"
& $G --headless --path . --quit-after 15000 res://tests/flow_test.tscn        # FLOW_TEST: ALL PASSED
& $G --headless --path . --quit-after 50000 res://tests/_stalkerprobe.tscn    # STALKER_PROBE: ALL PASSED
& $G --headless --path . --quit-after 20000 res://tests/student_test.tscn     # BAD_FRAMES=0
& $G --headless --path . --quit-after 40000 res://tests/tutorial_test.tscn    # TUTORIAL_TEST: ALL PASSED
& $G --headless --path . --quit-after 15000 res://tests/_fx_probe.tscn        # FX_PROBE: ALL PASSED
& $G --headless --path . --quit-after 15000 res://tests/_settings_probe.tscn  # SETTINGS_PROBE: ALL PASSED
& $G --headless --path . --quit-after 30000 res://tests/_c_ui_probe.tscn      # C_UI_PROBE: ALL PASSED
& $G --headless --path . --quit-after 30000 res://tests/_d_probe.tscn         # D_PROBE: ALL PASSED
& $G --headless --path . --quit-after 35000 res://tests/_e_probe.tscn         # E_PROBE: ALL PASSED
& $G --headless --path . --quit-after 30000 res://tests/_f_probe.tscn         # F_PROBE: ALL PASSED
& $G --headless --path . --quit-after 35000 res://tests/_g_probe.tscn         # G_PROBE: ALL PASSED
& $G --headless --path . --quit-after 30000 res://tests/_b_probe.tscn         # B_PROBE: ALL PASSED
& $G --headless --path . --quit-after 60000 res://tests/_map_probe.tscn       # MAP_PROBE: ALL PASSED（地图/相机/迷雾/小地图/套间）
& $G --headless --path . --quit-after 90000 res://tests/_big_probe.tscn       # BIG_PROBE seeds=8 failures=0（家具落位）
& $G --path . --resolution 1280x720 res://tests/screenshot.tscn               # 重拍 shot_*.png
& $G --path . --resolution 1280x720 res://tests/_nested_shot.tscn             # 套间三张样张
```

> 注：Godot 测试进程有时会脱离控制台，管道里拿不到输出；最稳的读法是看 `%APPDATA%\Godot\app_userdata\卷狗必须死\logs\godot.log`（历史日志会归档成 `godot<时间戳>.log`，需逐个搜）。
> 本轮踩过的坑：headless 视口只有几十像素 —— 一屏格数要按 `display/window/size/viewport_width` 算。
> 探索遮罩现在是「纹理 + 着色器」，断言请用 `fog.zone_alpha(zone)`，不要再找 ColorRect。
> 套间/走廊样张用 `tests/_nested_shot.tscn`（输出 shot_nested_parent / shot_nested_inside / shot_corridor_glow / shot_loop_passage）。
> 2026-11-07 记：`_e_probe` 有既有偶发性，首次跑曾出现 `e3/e4`（宝箱房判定），单独重跑即 ALL PASSED；不是本轮素材改动引起。
> 新增 `art/sprites/lpc/`、`art/sprites/floor/`、`art/portraits/` 后必须先 `& $G --headless --import --path .`，否则 `preload` 会报找不到资源。

## 环境

- 引擎：`E:\computerProgram2\tools\godot-4.7.2\Godot_v4.7.2-stable_win64.exe`
- 素材包：`E:\computerProgram2\JuanGouMustDie\素材\PixelSRPG-Forge-main`（本地，不入库）
- 参考库：`tools/_gen/godotarchive`（本地，不入库）
- 构建：`powershell -ExecutionPolicy Bypass -File tools\build_web.ps1`（需 `$env:GODOT`）
- 交接工具：`powershell -ExecutionPolicy Bypass -File tools\handoff.ps1`（`-Clipboard` 复制摘要；`-Start <tool> -Intent "..."` 加锁，`-End` 解锁）
