extends Node

## 临时截图：套间（母房视角 / 里间视角）+ 环路门洞。

const SEEDS := [2662436854, 3389636301, 1711209006, 544290074, 2351787729, 3835051054]

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.2, 0.25, 0.3))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 3:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()

	var found := false
	for s in SEEDS:
		GameState.seed_value = s
		inst._start_level()
		for i in 8:
			await get_tree().process_frame
		if inst.map.nested_room_index >= 0:
			found = true
			break
	var map = inst.map
	print("NESTED found=", found, " idx=", map.nested_room_index, " parent=", map.nested_parent,
		" rooms=", map.rooms.size(), " passages=", map.passage_rects.size())
	if not found:
		get_tree().quit(1)
		return

	var ni: int = map.nested_room_index
	var pi: int = map.nested_parent

	var pp: Vector2 = map._walkable_center(map.rooms[pi], pi)
	_move(inst, pp)
	await get_tree().create_timer(0.45).timeout
	await _shot("res://tests/shot_nested_parent.png")
	print("PARENT zone=", map.current_zone_at(pp), " nested_explored=", map.explored[ni],
		" parent_explored=", map.explored[pi])

	var np: Vector2 = map._walkable_center(map.rooms[ni], ni)
	_move(inst, np)
	await get_tree().create_timer(0.55).timeout
	await _shot("res://tests/shot_nested_inside.png")
	print("INSIDE zone=", map.current_zone_at(np), " nested_explored=", map.explored[ni],
		" parent_explored=", map.explored[pi], " nested_type=", map.room_types[ni])

	if map.passage_rects.size() > 0:
		var rp: Vector2 = map.passage_rects[0].get_center()
		_move(inst, rp)
		await get_tree().create_timer(0.45).timeout
		await _shot("res://tests/shot_loop_passage.png")
		print("PASSAGE zone=", map.current_zone_at(rp), " seen=", map.passage_seen(0))
	get_tree().quit(0)

func _move(inst, p: Vector2) -> void:
	inst.player.position = p
	if inst.camera != null:
		inst.camera.reset_smoothing()
		inst.camera.global_position = p

func _shot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
