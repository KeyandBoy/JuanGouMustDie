extends Node

## 第二层（地牢）截图探针：正常游玩视角 + 整层俯瞰。
## 运行（不要加 --headless）：& $G --path . res://tests/_dungeon_shot.tscn

func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	RenderingServer.set_default_clear_color(Color(0.2, 0.25, 0.3))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	var shot_img := get_viewport().get_texture().get_image()
	inst._show_level_select(1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	shot_img = get_viewport().get_texture().get_image()
	shot_img.save_png("res://tests/shot_level_select_w1.png")
	inst._pop_modal(inst.modal_stack[inst.modal_stack.size() - 1])
	await get_tree().process_frame
	inst._show_level_select(2)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	shot_img = get_viewport().get_texture().get_image()
	shot_img.save_png("res://tests/shot_level_select_w2.png")
	inst._close_all_modals()
	await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()
	GameState.seed_value = 20261115
	inst._start_level(6)
	for i in 20:
		await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout

	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_dungeon_play.png")
	print("SHOT_DUNGEON_PLAY rooms=", inst.map.rooms.size(), " player=", inst.player.position)

	# 整层俯瞰：停掉 _process（不然镜头会跟玩家），隐藏雾/HUD/小地图
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
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_dungeon_map.png")
	print("SHOT_DUNGEON_MAP world=", wr, " zoom=", z)
	get_tree().quit()
