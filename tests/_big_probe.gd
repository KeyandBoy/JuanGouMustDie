extends Node

## 临时探针：检查大件家具落位 + 套间/环路开凿 + 迷雾遮罩是否跟着建好。
## 每个种子都会整层重生成一次，打印一行摘要；第一个种子额外打印每间房的家具。

var seeds := [11, 22, 33, 44, 55, 66, 99, 123]

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()
	var failures := 0
	for si in seeds.size():
		GameState.seed_value = int(seeds[si])
		inst._start_level()
		for i in 6:
			await get_tree().process_frame
		var map = inst.map
		var bad := _check_map(map, inst, si == 0)
		failures += bad
		if si == 0:
			_dump_rooms(map)
	print("BIG_PROBE seeds=%d failures=%d" % [seeds.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)

func _check_map(map, inst, verbose: bool) -> int:
	var bad := 0
	if map.doors.size() != map.rooms.size():
		print("  FAIL doors/rooms mismatch %d vs %d" % [map.doors.size(), map.rooms.size()])
		bad += 1
	var nest := int(map.nested_room_index)
	var nest_txt := "none"
	if nest >= 0:
		var nr: Rect2 = map.rooms[nest]
		var parent := int(map.nested_parent)
		var ok_center: bool = map.is_walkable(nr.get_center())
		var dp: Vector2 = map.doors[nest]["pos"]
		var ok_door: bool = map.is_walkable(dp)
		var inside: bool = parent >= 0 and map.rooms[parent].encloses(nr)
		var is_treasure: bool = int(map.treasure_room_index) == nest
		nest_txt = "%s %dx%d center=%s door=%s inside=%s treasure=%s" % [
			String(map.room_types[nest]), int(nr.size.x / 20.0), int(nr.size.y / 20.0),
			ok_center, ok_door, inside, is_treasure,
		]
		if not (ok_center and ok_door and inside and is_treasure):
			print("  FAIL nested: ", nest_txt)
			bad += 1
	var pass_txt := "none"
	if map.passage_rects.size() > 0:
		var parts: Array[String] = []
		for i in map.passage_rects.size():
			var pr: Rect2 = map.passage_rects[i]
			var ok: bool = map.is_walkable(pr.get_center())
			parts.append("%s->%s:%s" % [map.room_types[map.passage_owner[i]], map.room_types[map.passage_other[i]], ok])
			if not ok:
				print("  FAIL passage not walkable: ", pr)
				bad += 1
		pass_txt = _join(parts)
	# 迷雾遮罩：母房要挖洞、门洞要单独一档
	var zones: Array = inst.fog._ov_zones
	if nest >= 0:
		if not zones.has("r%d" % nest):
			print("  FAIL fog: no mask for nested room")
			bad += 1
		if not zones.has("r%d" % int(map.nested_parent)):
			print("  FAIL fog: no mask for nested parent")
			bad += 1
	for i in map.passage_rects.size():
		if not zones.has("p%d" % i):
			print("  FAIL fog: no mask for passage ", i)
			bad += 1
	if int(map.treasure_room_index) < 0:
		print("  FAIL no treasure room")
		bad += 1
	print("MAP seed=%d rooms=%d world=%dx%d nested=%s passages=%d" % [
		GameState.seed_value, map.rooms.size(), map.gw, map.gh, nest_txt, map.passage_rects.size(),
	])
	if pass_txt != "none":
		print("   passages: ", pass_txt)
	if verbose:
		var missing := 0
		for it in map.big_items:
			if not ResourceLoader.exists("res://art/furniture/%s.png" % String(it["sprite"])):
				missing += 1
		print("   big_items=%d solid_rects=%d missing_textures=%d" % [
			map.big_items.size(), map.big_rects.size(), missing,
		])
		if missing > 0:
			bad += 1
	return bad

func _dump_rooms(map) -> void:
	for i in map.rooms.size():
		var r: Rect2 = map.rooms[i]
		var sprites: Array[String] = []
		for it in map.big_items:
			if int(it["room"]) == i:
				var rc: Rect2 = it["rect"]
				sprites.append("%s[%dx%d%s]" % [
					String(it["sprite"]), int(rc.size.x / 20.0), int(rc.size.y / 20.0),
					"" if bool(it["solid"]) else "·",
				])
		print("  room%d %s %dx%d desks=%d : %s" % [
			i, String(map.room_types[i]),
			int(r.size.x / 20.0), int(r.size.y / 20.0),
			_desk_count(map, i), _join(sprites),
		])

func _desk_count(map, room: int) -> int:
	var n := 0
	for d in map.desks:
		if int(d["room"]) == room:
			n += 1
	return n

func _join(parts: Array) -> String:
	var out := ""
	for p in parts:
		if out != "":
			out += ", "
		out += String(p)
	return out
