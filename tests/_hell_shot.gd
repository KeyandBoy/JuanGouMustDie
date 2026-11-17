extends Node

## 第三层（地狱 11~15F）截图探针：游玩视角 + 整层俯瞰 + 楼层选择页。
## 运行（不要加 --headless）：& $G --path . res://tests/_hell_shot.tscn

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	RenderingServer.set_default_clear_color(Color(0.14, 0.10, 0.16))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame

	# --- 楼层选择页（第三层页签）---
	inst._show_level_select(3)
	for i in 2:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_level_select_w3.png")
	print("SHOT_LEVEL_SELECT_W3")
	inst._close_all_modals()
	for i in 2:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()

	# --- 11F 游玩视角 ---
	GameState.seed_value = 20261117
	inst._start_level(11)
	for i in 24:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout

	img = get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_hell_11f_play.png")
	print("SHOT_11F_PLAY rooms=", inst.map.rooms.size(),
		" types=", str(inst.map.room_types),
		" study=", inst.map.study_points.size())

	# --- 11F 整层俯瞰 ---
	inst.set_process(false)
	if inst.hud != null:
		inst.hud.visible = false
	if inst.minimap != null:
		inst.minimap.visible = false
	if inst.fog != null:
		inst.fog.visible = false
	if inst.player != null:
		inst.player.visible = false
	inst.camera.limit_left = -100000
	inst.camera.limit_right = 100000
	inst.camera.limit_top = -100000
	inst.camera.limit_bottom = 100000
	var wr: Rect2 = inst.map.world_rect
	var vs := get_viewport().get_visible_rect().size
	var z := minf(vs.x / wr.size.x, vs.y / wr.size.y) * 0.94
	inst.camera.zoom = Vector2(z, z)
	inst.camera.global_position = wr.get_center()
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_hell_11f_map.png")
	print("SHOT_11F_MAP world=", wr, " zoom=", z)
	get_tree().quit()
