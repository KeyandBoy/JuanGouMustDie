extends Node

## 第三层（地狱 11~15F）布局 + 家具探针。
## 验证：区域制规模沿用第二层 / 房型全是地狱的 13 种（零学校残留）/
## 石房:器官房比例随楼层下降 / 地板走地狱图集 / 每房有学习点 /
## 大件家具贴图取到 hell/ / 每层恰好 1 张原版课桌 / 安全屋 2 间。
## 运行：& $G --headless --path . --quit-after 180000 res://tests/_hell_probe.tscn

const SEED := 515151

## 第三层允许出现的房型（设计 5.2/5.3/5.4）
const HELL_TYPES := [
	"cell", "torture", "altar", "forge", "jailer", "ossuary", "bloodpool",
	"heart", "stomach", "lung", "marrow", "eye", "womb",
]
const SCHOOL_TYPES := [
	"classroom", "lab", "library", "medical", "office",
	"storage", "broadcast", "toilet",
]

var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS: ", label)
	else:
		failures.append(label)
		print("  FAIL: ", label)

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()

	GameState.seed_value = SEED
	var map = inst.map
	var stone_counts: Array[int] = []

	for lv in range(11, 16):
		GameState.set_level(lv)
		map.generate(SEED, 0)
		await get_tree().process_frame
		var tag := "%dF" % lv

		# --- 规模沿用第二层：28~34 房 / 4 区 / 5 走廊 ---
		_check(map.rooms.size() >= 28 and map.rooms.size() <= 34,
			"%s 房间数 28~34（实测 %d）" % [tag, map.rooms.size()])
		_check(map.zone_rects.size() == 4, "%s 区数 = 4（实测 %d）" % [tag, map.zone_rects.size()])
		_check(map.corridor_rects.size() == 5,
			"%s 走廊数 = 5（实测 %d）" % [tag, map.corridor_rects.size()])

		# --- 房型：全是地狱的，学校房型一间都不能有 ---
		var bad_school := 0
		var bad_hell := 0
		for t in map.room_types:
			if t in SCHOOL_TYPES:
				bad_school += 1
			elif not (t in HELL_TYPES) and t != "hall" and t != "stair":
				bad_hell += 1
		_check(bad_school == 0, "%s 零学校房型（实测 %d）" % [tag, bad_school])
		_check(bad_hell == 0, "%s 只有地狱房型/hall/stair（异常 %d）" % [tag, bad_hell])

		# --- 石房:器官房比例（设计 5.1：11F 7:1 -> 15F 1:3）---
		var stone := 0
		var organ := 0
		for t in map.room_types:
			if t in ["cell", "torture", "altar", "forge", "jailer", "ossuary", "bloodpool"]:
				stone += 1
			elif t in ["heart", "stomach", "lung", "marrow", "eye", "womb"]:
				organ += 1
		stone_counts.append(stone)
		var want: float = map.hell_stone_ratio()
		_check(want > 0.0 and want <= 1.0, "%s hell_stone_ratio 有值（%.3f）" % [tag, want])
		if organ + stone > 0:
			var got := float(stone) / float(stone + organ)
			_check(absf(got - want) < 0.28,
				"%s 石房占比 %.2f ≈ 参数 %.2f" % [tag, got, want])
		print("    %s 石房 %d / 器官房 %d" % [tag, stone, organ])

		# --- 地板：地狱图集的 6 种行都能取到（world==3 分支生效）---
		for t in HELL_TYPES:
			var st: int = map._floor_style(t)
			_check(st >= 0 and st <= 5, "%s %s 地板行 %d 在 0~5" % [tag, t, st])
			var pat: Array = map._floor_pat(t)
			_check(pat.size() > 0 and pat[0] >= 0 and pat[0] <= 5,
				"%s %s 地板变体合法（%s）" % [tag, t, str(pat)])

		# --- 每间非安全屋至少 1 个学习点（点的 pos 落在房间矩形内）---
		# hall（首区中庭）是过渡区，第一二层同样没有学习点，这里保持一致不改。
		var no_study := 0
		for i in map.rooms.size():
			var role: String = map.room_roles[i] if i < map.room_roles.size() else "normal"
			if role == "safe" or role == "hall":
				continue
			var found := false
			for sp in map.study_points:
				if map.rooms[i].grow(-4.0).has_point(sp["pos"]):
					found = true
					break
			if not found:
				no_study += 1
				print("    缺学习点: idx=%d type=%s role=%s rect=%s" % [
					i, String(map.room_types[i]), role, str(map.rooms[i])])
		_check(no_study == 0, "%s 每间非安全屋都有学习点（缺 %d）" % [tag, no_study])

		# --- 大件家具：地狱房型要出大件，且贴图能从 hell/ 取到 ---
		var hell_big := 0
		var missing_tex := 0
		for it in map.big_items:
			var rt: int = int(it["room"])
			if rt < 0 or rt >= map.room_types.size():
				continue
			var t: String = String(map.room_types[rt])
			if not (t in HELL_TYPES):
				continue
			hell_big += 1
			var spr := String(it.get("sprite", ""))
			var hp := "res://art/furniture/hell/%s.png" % spr
			if not ResourceLoader.exists(hp):
				missing_tex += 1
		_check(hell_big > 0, "%s 地狱房型出了大件（%d）" % [tag, hell_big])
		_check(missing_tex == 0, "%s 大件贴图都在 hell/ 下（缺 %d）" % [tag, missing_tex])

		# --- 偶现课桌：恰好 1 张，且是 raw（原图不腐化）---
		var raw_desk := 0
		for it in map.big_items:
			if String(it.get("sprite", "")) == "desk_small" and bool(it.get("raw", false)):
				raw_desk += 1
		_check(raw_desk == 1, "%s 恰好 1 张原版课桌（实测 %d）" % [tag, raw_desk])

		# --- 安全屋 2 间、禁止答题 ---
		_check(map.safe_room_indices.size() == 2,
			"%s 安全屋 2 间（实测 %d）" % [tag, map.safe_room_indices.size()])
		for si in map.safe_room_indices:
			_check(not map.study_allowed_at(map.rooms[si].get_center()),
				"%s 安全屋 %d 禁止答题" % [tag, si])

		# --- 导航连通 ---
		_check(map.is_connected_plan(), "%s 所有房间可从入口走到" % tag)

		# --- 入口 / 出生点 ---
		_check(map.entry_room_index >= 0, "%s 入口房已分配" % tag)
		_check(map.spawn_points(14, true).size() == 14, "%s 走廊刷怪点 >= 14" % tag)

	# --- 跨楼层：石房 11F 明显多于 15F ---
	_check(stone_counts.size() == 5, "跨楼层收集 5 组石房计数")
	if stone_counts.size() == 5:
		print("  石房数 11F~15F: ", stone_counts)
		_check(stone_counts[0] > stone_counts[4],
			"11F 石房多于 15F（%d > %d）" % [stone_counts[0], stone_counts[4]])

	# --- MAX_LEVEL 已放行到 15 ---
	_check(GameState.MAX_LEVEL == 15, "MAX_LEVEL = 15")
	_check(GameState.world_of_level(11) == 3 and GameState.world_of_level(15) == 3,
		"11~15F 归第三层")
	_check(GameState.last_level_of_world(11) == 15, "第三层最后一关 = 15F")

	# --- 三 P1 刷怪：全怪物 / 零人类 / 数量按 HELL_PATROL / 宝箱怪 13F 起 ---
	var human_roles := ["student", "juan", "teacher", "guard"]
	var known_roles := ["skeleton", "zombie", "puppet", "minotaur", "grotesque", "slime"]
	for lv in range(11, 16):
		GameState.seed_value = SEED
		inst._start_level(lv)
		for i in 12:
			await get_tree().process_frame
		var stag := "%dF" % lv
		var want_n := int(inst.HELL_PATROL.get(lv, 0))
		var want_mimic := 0
		if lv >= 13:
			want_mimic = 1
		if lv >= 15:
			want_mimic = 2
		var patrol := 0
		var humans := 0
		var mimics := 0
		var bad_kind := 0
		var worst_chase := 0.0
		var worst_speed_mult := 0.0
		var worst_vision_mult := 0.0
		var kinds: Array[String] = []
		for s in get_tree().get_nodes_in_group("students"):
			if not is_instance_valid(s):
				continue
			var r := String(s.role)
			if r == "mimic":
				mimics += 1
				continue
			patrol += 1
			if not (r in kinds):
				kinds.append(r)
			if r in human_roles:
				humans += 1
			elif not (r in known_roles):
				bad_kind += 1
			worst_chase = maxf(worst_chase, float(s.chase_speed))
			worst_speed_mult = maxf(worst_speed_mult, float(s.level_speed_mult))
			worst_vision_mult = maxf(worst_vision_mult, float(s.level_vision_mult))
		_check(want_n > 0 and patrol == want_n,
			"%s 巡逻数 = 设计 §9 的 %d（实测 %d）" % [stag, want_n, patrol])
		_check(humans == 0, "%s 零人类（实测 %d 个人形）" % [stag, humans])
		_check(bad_kind == 0, "%s 名单全是已登记怪物角色（异常 %d）" % [stag, bad_kind])
		_check(mimics == want_mimic, "%s 宝箱怪 %d 只（实测 %d）" % [stag, want_mimic, mimics])
		_check(worst_speed_mult <= 1.501 and worst_vision_mult <= 1.601,
			"%s 楼层缩放已封顶（速度 ×%.2f / 视野 ×%.2f）" % [
				stag, worst_speed_mult, worst_vision_mult])
		_check(worst_chase < 260.0,
			"%s 最快追击 %.0f 仍跑得过玩家冲刺 260" % [stag, worst_chase])
		# --- 三 P1 顺带补上的第三层数值（设计 §9）---
		var want_goal := float([36.0, 41.0, 46.0, 51.0, 56.0][lv - 11])
		_check(is_equal_approx(GameState.study_goal, want_goal),
			"%s 学习目标 = %.0f（实测 %.0f，不落到默认 5）" % [
				stag, want_goal, GameState.study_goal])
		var want_decay := float([1.28, 1.39, 1.52, 1.65, 1.76][lv - 11])
		_check(is_equal_approx(GameState.emptiness_decay_rate(), want_decay),
			"%s 空虚衰减 = %.2f/s（实测 %.2f）" % [
				stag, want_decay, GameState.emptiness_decay_rate()])
		print("    %s 巡逻 %d [%s] 宝箱怪 %d 追击 %.0f 目标 %.0f 衰减 %.2f" % [
			stag, patrol, ", ".join(kinds), mimics, worst_chase,
			GameState.study_goal, GameState.emptiness_decay_rate()])

	# --- 全局封顶的两处副作用，写死在这里当回归护栏 ---
	# 10F：视野原为 1.72，现在被 cap 到 1.60（速度 1.45 本来就低于 1.50，不变）
	GameState.seed_value = SEED
	inst._start_level(10)
	for i in 12:
		await get_tree().process_frame
	var s10 = null
	for s in get_tree().get_nodes_in_group("students"):
		if is_instance_valid(s) and String(s.role) != "mimic":
			s10 = s
			break
	_check(s10 != null and absf(float(s10.level_vision_mult) - 1.60) < 0.001
		and absf(float(s10.level_speed_mult) - 1.45) < 0.001,
		"10F 封顶后 视野 ×1.60 / 速度 ×1.45（原视野 ×1.72）")
	# 5F：第一层完全没被碰到（仍是 1.20 / 1.32）
	inst._start_level(5)
	for i in 12:
		await get_tree().process_frame
	var s5 = null
	for s in get_tree().get_nodes_in_group("students"):
		if is_instance_valid(s) and String(s.role) != "mimic":
			s5 = s
			break
	_check(s5 != null and absf(float(s5.level_speed_mult) - 1.20) < 0.001
		and absf(float(s5.level_vision_mult) - 1.32) < 0.001,
		"5F 未受影响：速度 ×1.20 / 视野 ×1.32")
	# 空虚衰减：一、二层不能被第三层的按层查表改到
	GameState.contamination = 80.0
	_check(is_equal_approx(GameState.emptiness_decay_rate(), 1.0),
		"5F 空虚衰减仍是恒定 1.0（不看污染）")
	GameState.set_level(10)
	_check(is_equal_approx(GameState.emptiness_decay_rate(), 0.4 + 1.6 * 0.8),
		"10F 空虚衰减仍由污染驱动（污染 80 → 1.68/s）")

	print("")
	if failures.is_empty():
		print("HELL_PROBE: ALL PASSED")
	else:
		print("HELL_PROBE: %d FAILED" % failures.size())
		for f in failures:
			print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)
