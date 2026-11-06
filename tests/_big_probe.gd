extends Node

## 临时探针：打印每间房的大件家具清单，确认贴图真的放下去了。

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()
	GameState.seed_value = 777
	inst._start_level()
	for i in 6:
		await get_tree().process_frame

	var map = inst.map
	print("BIG_PROBE rooms=", map.rooms.size(), " big=", map.big_items.size(), " solid_rects=", map.big_rects.size())
	for i in map.rooms.size():
		var r: Rect2 = map.rooms[i]
		var sprites: Array[String] = []
		for it in map.big_items:
			if int(it["room"]) == i:
				var rc: Rect2 = it["rect"]
				sprites.append("%s[%dx%d%s%s]" % [
					String(it["sprite"]),
					int(rc.size.x / 20.0), int(rc.size.y / 20.0),
					"" if bool(it["solid"]) else "·",
					"W" if bool(it["decal"]) else ("F" if bool(it["floor"]) else ""),
				])
		print("  room%d %s %dx%d cells desks=%d : %s" % [
			i, String(map.room_types[i]),
			int(r.size.x / 20.0), int(r.size.y / 20.0),
			_desk_count(map, i), _join(sprites),
		])
	var missing := 0
	for it in map.big_items:
		var path := "res://art/furniture/%s.png" % String(it["sprite"])
		if not ResourceLoader.exists(path):
			missing += 1
			print("  MISSING TEXTURE: ", path)
	print("BIG_PROBE missing_textures=", missing)
	get_tree().quit(0)

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
