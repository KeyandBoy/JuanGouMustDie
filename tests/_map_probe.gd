extends Node

## 大地图专项探针：连续地图尺寸、一屏视野、死区相机、三态迷雾、小地图、套间/环路连通性。

var failures: Array[String] = []

const SEEDS := [4242, 2662436854, 3389636301, 1711209006, 544290074, 2351787729, 3835051054, 7]

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()

	GameState.seed_value = int(SEEDS[0])
	GameState.warnings = 0
	inst._start_level()
	for i in 8:
		await get_tree().process_frame
	var map = inst.map

	# --- 1. 连续大地图尺寸 / 一屏视野 ---
	# headless 下真实视口只有几十像素，一屏视野按设计分辨率(1280x720)算
	var design := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 720)))
	var zoom: float = inst.camera.zoom.x
	var screen_cells: float = design.x / (20.0 * zoom)
	_check(map.gw >= 55 and map.gh >= 40, "map is continuous and big (%dx%d cells)" % [map.gw, map.gh], failures)
	_check(screen_cells >= 62.0 and screen_cells <= 92.0, "one screen ~70-85 cells wide (%.0f)" % screen_cells, failures)
	_check(is_equal_approx(zoom, 0.85), "camera zoom fixed at 0.85 (%.2f)" % zoom, failures)
	_check(map.is_connected_plan(), "every room reachable from exit", failures)

	# --- 2. 死区跟随（死区大小按真实视口算，headless 也一样成立）---
	var vs: Vector2 = inst.get_viewport().get_visible_rect().size
	var dz: Vector2 = vs * 0.5 / zoom * Vector2(0.20, 0.22)
	var center: Vector2 = Vector2(map.world_rect.size.x * 0.5, map.world_rect.size.y * 0.5)
	inst.player.position = center
	inst.camera.reset_smoothing()
	inst.camera.global_position = center
	var cam0: Vector2 = inst.camera.global_position
	inst.player.position = cam0 + Vector2(dz.x * 0.4, dz.y * 0.4)
	await get_tree().process_frame
	await get_tree().process_frame
	var cam1: Vector2 = inst.camera.global_position
	_check(cam1.distance_to(cam0) < 2.0, "camera holds still inside dead zone (%.1f)" % cam1.distance_to(cam0), failures)
	inst.player.position = cam0 + Vector2(dz.x * 3.0, 0.0)
	for i in 3:
		await get_tree().process_frame
	var cam2: Vector2 = inst.camera.global_position
	_check(cam2.distance_to(cam0) > dz.x * 0.5, "camera scrolls after leaving dead zone (%.0f)" % cam2.distance_to(cam0), failures)

	# --- 3. 三态迷雾 ---
	var fog_i := -1
	for i in map.rooms.size():
		var t: String = String(map.room_types[i])
		if t != "hall" and t != "stair" and i != int(map.nested_room_index):
			fog_i = i
			break
	_check(fog_i >= 0, "normal room found for fog test", failures)
	if fog_i >= 0:
		inst.player.position = map._walkable_center(map.rooms[fog_i], fog_i)
		for i in 4:
			await get_tree().process_frame
		_check(map.explored[fog_i], "entering reveals the room", failures)
		var m: ColorRect = _mask_for(inst.fog, "r%d" % fog_i)
		_check(m != null and not m.visible, "current room is unmasked (evenly lit)", failures)
		inst.player.position = map.corridor_rect.get_center()
		inst.camera.reset_smoothing()
		inst.camera.global_position = inst.player.position
		await get_tree().create_timer(0.3).timeout
		m = _mask_for(inst.fog, "r%d" % fog_i)
		_check(m != null and m.visible and m.color.a > 0.05 and m.color.a < 0.9,
			"explored room dims after leaving (a=%.2f)" % (m.color.a if m != null else -1.0), failures)
		var dark_ok := true
		for i in map.rooms.size():
			if map.explored[i] or i == int(map.nested_room_index):
				continue
			var dm: ColorRect = _mask_for(inst.fog, "r%d" % i)
			if dm != null and dm.color.a < 0.99:
				dark_ok = false
				break
		_check(dark_ok, "unexplored rooms stay pitch black", failures)
		_check(inst.fog.halo != null and not inst.fog.halo.visible,
			"no flashlight halo outside blackout", failures)

	# --- 4. 小地图 ---
	_check(inst.minimap != null and inst.minimap.visible, "minimap enabled and visible", failures)
	if inst.minimap != null:
		_check(inst.minimap.size.x >= 150.0 and inst.minimap.size.y >= 100.0,
			"minimap has size (%.0fx%.0f)" % [inst.minimap.size.x, inst.minimap.size.y], failures)
		_check(inst.minimap.map == map, "minimap bound to map", failures)

	# --- 5. 套间 / 环路：多跑几个种子，至少要能生成 ---
	var nested_seen := 0
	var passage_seen := 0
	for si in range(1, SEEDS.size()):
		GameState.seed_value = int(SEEDS[si])
		inst._start_level()
		for i in 6:
			await get_tree().process_frame
		var m2 = inst.map
		_check(m2.doors.size() == m2.rooms.size(),
			"rooms/doors stay index aligned (%d/%d)" % [m2.rooms.size(), m2.doors.size()], failures)
		var nest := int(m2.nested_room_index)
		if nest >= 0:
			nested_seen += 1
			var nr: Rect2 = m2.rooms[nest]
			var nd: Vector2 = m2.doors[nest]["pos"]
			_check(m2.is_walkable(nr.get_center()), "nested room center walkable (seed %d)" % [GameState.seed_value], failures)
			_check(m2.is_walkable(nd), "nested doorway walkable (seed %d)" % [GameState.seed_value], failures)
			_check(m2.rooms[int(m2.nested_parent)].encloses(nr), "nested room sits inside its parent", failures)
			_check(int(m2.treasure_room_index) == nest, "nested room is the hidden treasure room", failures)
			_check(m2.is_connected_plan(), "nested room reachable (seed %d)" % [GameState.seed_value], failures)
			var nz := "r%d" % nest
			var has_mask := false
			for z in inst.fog._ov_zones:
				if String(z) == nz:
					has_mask = true
			_check(has_mask, "fog has its own mask for the nested room", failures)
		if m2.passage_rects.size() > 0:
			passage_seen += 1
			for i in m2.passage_rects.size():
				_check(m2.is_walkable(m2.passage_rects[i].get_center()),
					"loop passage walkable (seed %d)" % [GameState.seed_value], failures)
	_check(nested_seen >= 1, "at least one seed generates a nested room (%d)" % nested_seen, failures)
	_check(passage_seen >= 1, "at least one seed generates a loop passage (%d)" % passage_seen, failures)

	if failures.is_empty():
		print("MAP_PROBE: ALL PASSED")
	else:
		print("MAP_PROBE: %d FAILURES" % failures.size())
		for f in failures:
			print("  FAIL: ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)

func _check(cond: bool, label: String, fails: Array[String]) -> void:
	if cond:
		print("  PASS: ", label)
	else:
		fails.append(label)
		print("  FAIL: ", label)

func _mask_for(fog, zone: String) -> ColorRect:
	if fog == null:
		return null
	for i in fog._ov_zones.size():
		if String(fog._ov_zones[i]) == zone:
			return fog._ov_nodes[i]
	return null
