extends Node

## 第二层（地牢）区域制布局探针（P1）。
## 验证 6~10F：28~34 房 / 4 区 / 5 条走廊（4 区走廊 + 主脊）/ 区间门 /
## 导航连通 / 2 间安全屋 / hall 在首区、stair 在末区 / 石砌比例随楼层上升。
## 运行：& $G --headless --path . --quit-after 120000 res://tests/_dungeon_probe.tscn

const SEED := 424242

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
	for lv in range(6, 11):
		GameState.set_level(lv)
		map.generate(SEED, 0)
		await get_tree().process_frame
		var tag := "%dF" % lv

		# --- 规模：28~34 房 / 4 区 / 5 条走廊 ---
		_check(map.rooms.size() >= 28 and map.rooms.size() <= 34,
			"%s 房间数 28~34（实测 %d）" % [tag, map.rooms.size()])
		_check(map.zone_rects.size() == 4, "%s 区数 = 4（实测 %d）" % [tag, map.zone_rects.size()])
		_check(map.zone_names.size() == 4, "%s 区名 = 4（实测 %d）" % [tag, map.zone_names.size()])
		_check(map.corridor_rects.size() == 5,
			"%s 走廊数 = 5（4 区走廊 + 主脊，实测 %d）" % [tag, map.corridor_rects.size()])

		# --- hall / stair 各 1，且分别落在首区 / 末区 ---
		var hall_i: int = map.room_types.find("hall")
		var stair_i: int = map.room_types.find("stair")
		_check(hall_i >= 0 and map.room_types.count("hall") == 1, "%s 恰好 1 间 hall" % tag)
		_check(stair_i >= 0 and map.room_types.count("stair") == 1, "%s 恰好 1 间 stair" % tag)
		if hall_i >= 0:
			var hc: Vector2 = map._walkable_center(map.rooms[hall_i], hall_i)
			_check(map.zone_index_at(hc) == 0, "%s hall 在首区（中庭）" % tag)
		if stair_i >= 0:
			var sc: Vector2 = map._walkable_center(map.rooms[stair_i], stair_i)
			_check(map.zone_index_at(sc) == 3, "%s stair 在末区（深处）" % tag)

		# --- 门：每间房 1 道 + 4 道区间门 ---
		_check(map.doors.size() == map.rooms.size() + 4,
			"%s 门数 = 房数 + 4（%d / %d）" % [tag, map.doors.size(), map.rooms.size()])

		# --- 每区固定 8 间房 ---
		var per_zone: Array[int] = [0, 0, 0, 0]
		for i in map.rooms.size():
			var c: Vector2 = map.rooms[i].get_center()
			var zi: int = map.zone_index_at(c)
			if zi >= 0 and zi < 4:
				per_zone[zi] += 1
		_check(per_zone == [8, 8, 8, 8], "%s 每区 8 房（%s）" % [tag, str(per_zone)])

		# --- 安全屋 2 间、不在主线、禁止答题 ---
		_check(map.safe_room_indices.size() == 2,
			"%s 安全屋 2 间（实测 %d）" % [tag, map.safe_room_indices.size()])
		for si in map.safe_room_indices:
			_check(si >= 0 and si < map.room_roles.size() and String(map.room_roles[si]) == "safe",
				"%s 安全屋 %d 角色 = safe" % [tag, si])
			_check(not map.is_main_path(si), "%s 安全屋 %d 不在主线" % [tag, si])
			_check(not map.study_allowed_at(map.rooms[si].get_center()),
				"%s 安全屋 %d 禁止答题" % [tag, si])

		# --- 导航图连通：所有房间都有深度，A* 也能走通所有房中心 ---
		var unreached := 0
		for i in map.rooms.size():
			if i >= map.room_depth.size() or int(map.room_depth[i]) < 0:
				unreached += 1
		_check(unreached == 0, "%s 导航图覆盖全部房间（未连 %d）" % [tag, unreached])
		_check(map.is_connected_plan(), "%s 所有房间可从入口走到" % tag)

		# --- 走廊中心线全程可走 ---
		var bad_corr := 0
		for r in map.corridor_rects:
			var horizontal: bool = r.size.x >= r.size.y
			var n := int((r.size.x if horizontal else r.size.y) / 40.0)
			for k in range(1, n):
				var p := Vector2.ZERO
				if horizontal:
					p = Vector2(r.position.x + 40.0 * k, r.get_center().y)
				else:
					p = Vector2(r.get_center().x, r.position.y + 40.0 * k)
				if not map.is_walkable(p):
					bad_corr += 1
		_check(bad_corr == 0, "%s 走廊中心线可走（坏点 %d）" % [tag, bad_corr])

		# --- 房间不重叠、都在地图里 ---
		var overlap := 0
		for i in map.rooms.size():
			if not map.world_rect.encloses(map.rooms[i]):
				overlap += 1
			for j in range(i + 1, map.rooms.size()):
				var a: Rect2 = map.rooms[i]
				var b: Rect2 = map.rooms[j]
				if a.intersects(b) and a.intersection(b).get_area() > 1.0:
					overlap += 1
		_check(overlap == 0, "%s 房间不重叠且都在图内（异常 %d）" % [tag, overlap])

		# --- 石砌比例：函数值与实际房型数 ---
		var stone := 0
		for t in map.room_types:
			if t == "cell" or t == "torture" or t == "altar":
				stone += 1
		stone_counts.append(stone)
		var want_ratio := 0.3 + 0.1 * float(lv - 6)
		_check(is_equal_approx(map.dungeon_stone_ratio(), want_ratio),
			"%s 石砌比例参数 = %.1f" % [tag, want_ratio])

		# --- 出生点 / 区域名 ---
		_check(map.entry_room_index >= 0, "%s 入口房已分配" % tag)
		_check(not map.zone_name_at(map.exit_pos).is_empty(), "%s 出生点能取到区名" % tag)
		_check(map.spawn_points(14, true).size() == 14, "%s 走廊刷怪点 >= 14" % tag)

	# --- 跨楼层：石砌房型 10F 明显多于 6F ---
	_check(stone_counts.size() == 5, "跨楼层收集 5 组石砌计数")
	if stone_counts.size() == 5:
		print("  石砌房型数 6F~10F: ", stone_counts)
		_check(stone_counts[4] > stone_counts[0],
			"10F 石砌房型多于 6F（%d > %d）" % [stone_counts[4], stone_counts[0]])

	print("")
	if failures.is_empty():
		print("DUNGEON_PROBE: ALL PASSED")
	else:
		print("DUNGEON_PROBE: %d FAILED" % failures.size())
		for f in failures:
			print("  - ", f)
	get_tree().quit(0 if failures.is_empty() else 1)
