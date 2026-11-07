extends Node

## 临时截图：把 4 只怪物摆到玩家面前，检查方向帧/体型/影子。

const ROLES := ["skeleton", "zombie", "puppet", "minotaur"]

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.2, 0.25, 0.3))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 3:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()
	GameState.seed_value = 20261107
	inst._start_level(5)
	for i in 8:
		await get_tree().process_frame

	var map = inst.map
	var room_i := -1
	for i in map.rooms.size():
		if String(map.room_types[i]) == "classroom":
			room_i = i
			break
	if room_i < 0:
		room_i = 0
	var center: Vector2 = map._walkable_center(map.rooms[room_i], room_i)
	inst.player.position = center + Vector2(0.0, 70.0)
	inst.camera.reset_smoothing()
	inst.camera.global_position = center
	await get_tree().create_timer(0.3).timeout

	var found: Array[String] = []
	var students := get_tree().get_nodes_in_group("students")
	for k in ROLES.size():
		var picked = null
		for st in students:
			if String(st.get("role")) == ROLES[k]:
				picked = st
				break
		if picked == null:
			continue
		found.append(ROLES[k])
		picked.position = center + Vector2(-105.0 + k * 70.0, 20.0)
		picked.state = "patrol"
		picked.path = PackedVector2Array()
		picked.facing = Vector2.DOWN
	await get_tree().create_timer(0.5).timeout
	# 第二批：随机怪物（grotesque）4 个变体，排在第二行
	var student_script = load("res://scripts/student.gd")
	var variants := [1, 5, 11, 17]
	for k in variants.size():
		var mon = student_script.new()
		mon.collision_layer = 0
		mon.collision_mask = 0
		inst.add_child(mon)
		mon.monster_variant = variants[k]
		mon.set_role("grotesque")
		mon.position = center + Vector2(-105.0 + k * 70.0, 90.0)
		mon.state = "patrol"
		mon.path = PackedVector2Array()
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_monsters.png")
	print("MONSTERS found=", found, " all=", ROLES.size())
	get_tree().quit(0)
