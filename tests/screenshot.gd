extends Node

const SAVE_USER_PATH := "user://save_juangou.json"
var _save_text := ""
var _had_save := false

func _ready() -> void:
	_stash_save()
	RenderingServer.set_default_clear_color(Color(0.2, 0.25, 0.3))
	var intro = load("res://scripts/intro.gd").new()
	add_child(intro)
	intro.play()
	await _wait_until(func(): return intro._line.text.length() > 8, 300)
	_snap("res://tests/shot_intro.png")
	print("INTRO line=", intro._line.text)
	print("INTRO_BACKDROP opaque=", intro._backdrop != null and intro._backdrop.color.a >= 0.99)
	await _wait_until(func(): return intro._chalk != null and intro._chalk.text.length() >= 2, 1200)
	await get_tree().create_timer(0.2).timeout
	_snap("res://tests/shot_intro_chalk.png")
	print("INTRO_CHALK text=", intro._chalk.text if intro._chalk != null else "-")
	await _wait_until(func(): return intro._chalk == null and intro._line.text.find("躺平世界") >= 0, 1800)
	await get_tree().create_timer(0.25).timeout
	_snap("res://tests/shot_intro_scene4.png")
	print("INTRO_SCENE4 chalk_cleared=", intro._chalk == null, " line_len=", intro._line.text.length())
	intro._skip = true
	await get_tree().create_timer(1.2).timeout
	intro.queue_free()
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_save(inst, "res://tests/shot_menu.png")
	inst._show_level_select()
	await get_tree().process_frame
	await get_tree().process_frame
	_save(inst, "res://tests/shot_level_select.png")
	inst._pop_modal(inst.modal_stack[inst.modal_stack.size() - 1])
	await get_tree().process_frame
	inst._show_shop()
	await get_tree().process_frame
	await get_tree().process_frame
	_save(inst, "res://tests/shot_shop_from_menu.png")
	var top_layer := -1
	if inst.modal_stack.size() > 0:
		top_layer = inst.modal_stack[inst.modal_stack.size() - 1].layer
	print("SHOP_FROM_MENU stack=", inst.modal_stack.size(), " top_layer=", top_layer, " menu_layer=", inst.menu_layer.layer if inst.menu_layer != null else -1)
	inst._close_all_modals()
	await get_tree().process_frame
	inst.menu_layer = null
	inst._start_level()
	GameState.inventory.clear()
	GameState.upgrades.clear()
	GameState.stars = 999
	GameState.buy_upgrade("capacity")
	GameState.buy_upgrade("capacity")
	GameState.add_item("coffee")
	GameState.add_item("notes")
	GameState.add_item("stopwatch")
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	_save(inst, "res://tests/shot_world.png")

	GameState.correct_streak = 9
	GameState.hot_changed.emit(GameState.hot_level())
	for i in 4:
		await get_tree().process_frame
	_save(inst, "res://tests/shot_hot.png")
	GameState.correct_streak = 0
	GameState.hot_changed.emit(GameState.hot_level())

	for s in [7, 2024, 31337]:
		GameState.seed_value = s
		inst._setup_level()
		for i in 12:
			await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout
		_save(inst, "res://tests/shot_%d.png" % s)

	var qdesk: Dictionary = inst.map.desks[0]
	var dpos: Vector2 = qdesk["pos"]
	for off: Vector2 in [Vector2(0.0, 30.0), Vector2(0.0, -30.0), Vector2(30.0, 0.0), Vector2(-30.0, 0.0), Vector2(0.0, 40.0), Vector2(40.0, 0.0)]:
		if inst.map.is_walkable(dpos + off):
			inst.player.position = dpos + off
			break
	inst.camera.reset_smoothing()
	inst.camera.global_position = inst.player.position
	await get_tree().create_timer(0.1).timeout
	inst._toggle_study()
	await get_tree().create_timer(0.5).timeout
	_save(inst, "res://tests/shot_quiz.png")
	var qid1: String = String(inst.quiz.current_question.get("id", ""))
	print("G_START study_eff=", inst.study_efficiency, " open=", inst.quiz.is_open, " qid=", qid1)
	inst._toggle_study()
	await get_tree().create_timer(0.5).timeout
	_save(inst, "res://tests/shot_paused.png")
	print("G_PAUSE paused=", inst.study_paused, " open=", inst.quiz.is_open, " held=", String(inst.held_question.get("id", "")))
	inst._toggle_study()
	await get_tree().create_timer(0.5).timeout
	_save(inst, "res://tests/shot_resumed.png")
	var qid2: String = String(inst.quiz.current_question.get("id", ""))
	print("G_RESUME open=", inst.quiz.is_open, " qid=", qid2, " same=", qid2 == qid1)
	inst.quiz._stand_up()
	await get_tree().create_timer(0.5).timeout
	print("STAND_UP studying=", inst.studying, " open=", inst.quiz.is_open)

	inst._show_pause_menu()
	await get_tree().create_timer(0.3).timeout
	_save(inst, "res://tests/shot_pausemenu.png")
	var pv: Array = []
	for n in get_tree().get_nodes_in_group("ui_modal"):
		for c in n.get_children():
			_find_volume_sliders(c, pv)
	print("PAUSEMENU volume_sliders=", pv.size(), " values=", pv)
	for n in get_tree().get_nodes_in_group("ui_modal"):
		n.queue_free()
	await get_tree().process_frame

	GameState.run_state = GameState.RunState.MENU
	var door = inst.map.door_nodes[0]
	var away := Vector2(0.0, -54.0) if door.axis == "h" else Vector2(-54.0, 0.0)
	var near := Vector2(0.0, 46.0) if door.axis == "h" else Vector2(46.0, 0.0)
	inst.player.position = door.position + near
	inst.camera.reset_smoothing()
	inst.camera.global_position = inst.player.position
	var guard = get_tree().get_nodes_in_group("students")[0]
	guard.position = door.position + away
	guard.state = "chase"
	guard.alert_level = 80.0
	guard.facing = (inst.player.position - guard.position).normalized()
	guard.set_physics_process(false)
	door.set_open(false)
	for i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	_save(inst, "res://tests/shot_door.png")
	door.set_open(true)
	for i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	_save(inst, "res://tests/shot_door_open.png")

	GameState.run_state = GameState.RunState.EXPLORING
	for s2 in get_tree().get_nodes_in_group("students"):
		s2.set_physics_process(true)
	var sts: Array = get_tree().get_nodes_in_group("students")
	var qd2: Dictionary = inst.map.desks[0]
	var dp2: Vector2 = qd2["pos"]
	var spot2 := Vector2.ZERO
	for off: Vector2 in [Vector2(0.0, 30.0), Vector2(0.0, -30.0), Vector2(30.0, 0.0), Vector2(-30.0, 0.0)]:
		if inst.map.is_walkable(dp2 + off):
			spot2 = dp2 + off
			break
	inst.player.position = spot2
	inst.camera.reset_smoothing()
	inst.camera.global_position = inst.player.position
	GameState.warnings = 1
	var w2: Node2D = null
	for offs: Vector2 in [Vector2(70.0, 0.0), Vector2(-70.0, 0.0), Vector2(0.0, 70.0), Vector2(0.0, -70.0), Vector2(70.0, 70.0)]:
		var sp2: Vector2 = spot2 + offs
		if inst.map.is_walkable(sp2) and inst.map.vision_clear(sp2, spot2):
			w2 = sts[0]
			w2.position = sp2
			w2.facing = (spot2 - sp2).normalized()
			w2.state = "patrol"
			w2.path = PackedVector2Array()
			break
	for i in 40:
		await get_tree().process_frame
	await get_tree().create_timer(0.2).timeout
	_save(inst, "res://tests/shot_stalk.png")
	print("STALK watcher=", w2 != null, " state=", w2.state if w2 != null else "-")
	DevMode.show_vision_cones = true
	await get_tree().process_frame
	await get_tree().process_frame
	_save(inst, "res://tests/shot_dev_cones.png")
	DevMode.show_vision_cones = false
	if w2 != null:
		w2.set_physics_process(false)
		w2.can_see = true
		w2.state = "stalk"
		w2.alert_level = w2.max_alert
		await get_tree().process_frame
		await get_tree().process_frame
		_save(inst, "res://tests/shot_watch_hint.png")
		w2.set_physics_process(true)
	inst._toggle_study()
	for i in 420:
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout
	_save(inst, "res://tests/shot_hunt.png")
	var sl := PackedStringArray()
	for s3 in sts:
		sl.append(String(s3.state))
	print("HUNT warnings=", GameState.warnings, " quiz_open=", inst.quiz.is_open, " states=", ", ".join(sl))
	if inst.quiz.is_open:
		inst.quiz._stand_up()

	GameState.warnings = 0
	GameState.set_level(2)
	inst.fog.forget_after = 0.05
	inst.fog.forget_ramp = 0.2
	var fi := -1
	for i in inst.map.rooms.size():
		var t := String(inst.map.room_types[i])
		if t != "hall" and t != "stair" and t != "corridor":
			fi = i
			break
	if fi >= 0:
		inst.player.position = inst.map.rooms[fi].get_center()
		inst.camera.reset_smoothing()
		inst.camera.global_position = inst.player.position
		await get_tree().create_timer(0.15).timeout
		var spot: Vector2 = Vector2(inst.map.rooms[fi].get_center().x, inst.map.corridor_rect.get_center().y)
		if not inst.map.is_walkable(spot):
			spot = inst.map.corridor_rect.get_center()
		inst.player.position = spot
		inst.camera.reset_smoothing()
		inst.camera.global_position = spot
		await get_tree().create_timer(0.6).timeout
		_save(inst, "res://tests/shot_forget.png")
		print("FORGET room=", fi, " type=", inst.map.room_types[fi], " amount=", inst.fog.forget_amount(fi), " player=", inst.player.position)

	GameState.warnings = 0
	var n0 = get_tree().get_nodes_in_group("students")[0]
	n0.position = inst.player.position + Vector2(50.0, 0.0)
	n0.state = "patrol"
	n0.path = PackedVector2Array()
	n0.alert_level = n0.max_alert
	for i in 4:
		await get_tree().process_frame
	_save(inst, "res://tests/shot_noalert.png")
	print("NOALERT warnings=", GameState.warnings, " alert=", n0.alert_level)

	GameState.set_level(1)
	GameState.warnings = 0
	GameState.dash_energy = 100.0
	inst.player.dashing = false
	inst.player._start_dash()
	await get_tree().create_timer(0.15).timeout
	_save(inst, "res://tests/shot_dash.png")
	print("DASH dodging=", inst.player.is_dodging(), " energy=", GameState.dash_energy)

	GameState.set_level(5)
	GameState.tyrant_active = true
	inst.fog.set_tyrant_active(true, 5)
	await get_tree().create_timer(0.6).timeout
	_save(inst, "res://tests/shot_level5.png")
	print("LEVEL5 halo=", inst.fog.halo_clear, "/", inst.fog.halo_fade, " ambient=", inst.fog.ambient_density)

	GameState.set_level(4)
	inst._setup_level(false)
	GameState.study = GameState.study_goal * 0.5
	var tri := -1
	for i in inst.map.rooms.size():
		var t := String(inst.map.room_types[i])
		if t != "hall" and t != "stair" and t != "corridor":
			tri = i
			break
	if tri >= 0:
		inst.player.position = inst.map._walkable_center(inst.map.rooms[tri])
		inst.camera.reset_smoothing()
		inst.camera.global_position = inst.player.position
	await get_tree().create_timer(0.2).timeout
	inst._start_tyrant_intro()
	await get_tree().create_timer(2.6).timeout
	_save(inst, "res://tests/shot_tyrant_comic.png")
	await get_tree().create_timer(6.5).timeout
	_save(inst, "res://tests/shot_tyrant_chase.png")
	print("TYRANT spawned=", inst.tyrant_spawned, " intro=", GameState.tyrant_intro_seen, " active=", GameState.tyrant_active, " ambient=", inst.fog.ambient_density)
	if inst.tyrant != null and is_instance_valid(inst.tyrant):
		print("TYRANT art use_generated=", inst.tyrant.use_generated, " tex=", inst.tyrant.tex_front)
		for s4 in get_tree().get_nodes_in_group("tyrants"):
			s4.set_physics_process(false)
			s4.velocity = Vector2.ZERO
		var tp: Vector2 = inst.tyrant.position
		var spot3 := Vector2.INF
		for off3: Vector2 in [Vector2(0.0, 70.0), Vector2(0.0, -70.0), Vector2(70.0, 0.0), Vector2(-70.0, 0.0), Vector2(0.0, 110.0), Vector2(110.0, 0.0)]:
			if inst.map.is_walkable(tp + off3):
				spot3 = tp + off3
				break
		if spot3 != Vector2.INF:
			inst.player.position = spot3
			inst.camera.reset_smoothing()
			inst.camera.global_position = (tp + spot3) * 0.5
			await get_tree().create_timer(0.3).timeout
			_save(inst, "res://tests/shot_tyrant_sprite.png")
			print("TYRANT_SPRITE pos=", tp, " player=", spot3)
	# 开场动画叠在真实世界上：验证换图/首帧不会透出第一关画面
	inst._start_level(1)
	await get_tree().create_timer(0.3).timeout
	inst._play_intro()
	await get_tree().create_timer(0.15).timeout
	var intro_node: Node = null
	for c in inst.get_children():
		if c is CanvasLayer and c.layer == 60:
			intro_node = c
	_save(inst, "res://tests/shot_intro_overworld.png")
	print("INTRO_OVERWORLD found=", intro_node != null)
	if intro_node != null:
		intro_node._skip = true
		await get_tree().create_timer(0.9).timeout

	inst._start_level(1)
	await get_tree().process_frame
	GameState.questions_answered = 10
	GameState.quiz_correct = 9
	GameState.caught_count = 0
	GameState.level_time = 60.0
	GameState.quiz_time = 50.0
	inst._on_level_cleared()
	await get_tree().create_timer(1.6).timeout
	_save(inst, "res://tests/shot_clear_panel.png")

	_restore_save()
	get_tree().quit()

func _stash_save() -> void:
	var path := ProjectSettings.globalize_path(SAVE_USER_PATH)
	_had_save = FileAccess.file_exists(SAVE_USER_PATH)
	if _had_save:
		var f := FileAccess.open(SAVE_USER_PATH, FileAccess.READ)
		if f != null:
			_save_text = f.get_as_text()
	DirAccess.remove_absolute(path)

func _restore_save() -> void:
	var path := ProjectSettings.globalize_path(SAVE_USER_PATH)
	if _had_save and _save_text != "":
		var f := FileAccess.open(SAVE_USER_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(_save_text)
	else:
		DirAccess.remove_absolute(path)

func _snap(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print(path)

func _wait_until(cond: Callable, max_frames: int) -> void:
	for i in max_frames:
		if cond.call():
			return
		await get_tree().process_frame

func _find_volume_sliders(n: Node, out: Array) -> void:
	if n is HSlider:
		out.append(n.value)
		return
	for c in n.get_children():
		_find_volume_sliders(c, out)

func _save(inst, path: String) -> void:
	print(path, " rooms=", inst.map.rooms.size(), " l=", inst.map.is_l_shape, " world=", inst.map.world_rect, " zoom=", inst.camera.zoom, " player=", inst.player.position)
	for s in get_tree().get_nodes_in_group("students"):
		print("   student pos=", s.position, " state=", s.state, " walk=", inst.map.is_walkable(s.position), " path=", s.path.size())
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
