extends Node

## E 组探针：E2 最远入口、E3 主路标签、E4 Boss/宝箱房。
## 运行：& $G --headless --path . --quit-after 25000 res://tests/_e_probe.tscn

var failures: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	inst._start_level(1)
	await get_tree().process_frame
	await get_tree().process_frame

	var map = inst.map
	# E2：入口存在且是全图离楼梯最远的房间
	_check(map.entry_room_index >= 0, "e2: entry room assigned")
	if map.entry_room_index >= 0:
		_check(String(map.room_roles[map.entry_room_index]) != "stair", "e2: entry is not the stair room")
		_check(map.exit_pos.distance_to(map._walkable_center(map.rooms[map.entry_room_index], map.entry_room_index)) < 2.0,
			"e2: spawn sits in entry room")
		var max_depth := 0
		for i in map.rooms.size():
			if String(map.room_types[i]) == "stair" or String(map.room_types[i]) == "hall":
				continue
			max_depth = maxi(max_depth, int(map.room_depth[i]))
		_check(int(map.room_depth[map.entry_room_index]) >= max_depth,
			"e2: entry is deepest (%d >= %d)" % [int(map.room_depth[map.entry_room_index]), max_depth])

	# E3：主路包含入口与楼梯；支路房不进主路
	var stair_i: int = map.room_types.find("stair")
	_check(not map.main_path_rooms.is_empty(), "e3: main path computed")
	_check(map.is_main_path(map.entry_room_index), "e3: entry is on main path")
	if stair_i >= 0:
		_check(map.is_main_path(stair_i), "e3: stair is on main path")
	_check(map.treasure_room_index < 0 or not map.is_main_path(map.treasure_room_index),
		"e3: treasure room is a sidetrack")

	# E4：宝箱房
	_check(map.treasure_room_index >= 0, "e4: treasure room assigned")
	if map.treasure_room_index >= 0:
		_check(String(map.room_roles[map.treasure_room_index]) == "treasure", "e4: treasure role")
		_check(map.treasure_room_index != map.entry_room_index, "e4: treasure != entry")

	# E4：L4 生成 Boss 房，暴君优先在 Boss 房登场
	GameState.level = 4
	map.generate(424242, 0)
	await get_tree().process_frame
	stair_i = map.room_types.find("stair")
	_check(map.boss_room_index >= 0, "e4: L4 boss room assigned")
	if map.boss_room_index >= 0:
		_check(String(map.room_roles[map.boss_room_index]) == "boss", "e4: boss role")
		# 玩家放到楼梯房，确保 Boss 房足够远
		if stair_i >= 0:
			inst.player.position = map._walkable_center(map.rooms[stair_i])
		var boss_center: Vector2 = map._walkable_center(map.rooms[map.boss_room_index], map.boss_room_index)
		inst.tyrant_spawned = false
		inst._spawn_tyrant(0.0)
		if inst.tyrant != null:
			_check(inst.tyrant.position.distance_to(boss_center) < 4.0,
				"e4: tyrant spawns in boss room (%s vs %s)" % [inst.tyrant.position, boss_center])
		else:
			_check(false, "e4: tyrant spawned")

	if failures.is_empty():
		print("E_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("E_PROBE: FAILED ", failures.size())
	get_tree().quit()
