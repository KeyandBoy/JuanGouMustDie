extends Node2D

## 层号唯一来源。改层号只改这里，别再写魔法数字。
## 10 HUD / 20 答题 / 32 抓获特效 / 40~43 弹窗栈/ 44 转场黑幕 / 48 暴君过场 / 60 开场动画
const L_HUD := 10
const L_QUIZ := 20
const L_FX := 32
const L_MODAL := 40
const L_MODAL_MAX := 43
const L_FADE := 44
const L_TYRANT_CUT := 48
const L_INTRO := 60

const ANTI_TYRANT_ITEMS: Array[String] = ["smoke", "chair", "stink"]
const GENERAL_ITEMS: Array[String] = ["coffee", "bread", "portal", "shovel", "lamp", "notes", "shoes", "stopwatch", "intel", "ears"]

var map: Node2D
var player: CharacterBody2D
var hud: CanvasLayer
var _last_hot_level := 0
var world_modulate: CanvasModulate
var player_light: PointLight2D
var level_lights: Node2D
var _light_tex: Texture2D
var _light_time := 0.0
var _lights_on := true
var _dialogue_prev_paused := false
var quiz: CanvasLayer
var camera: Camera2D
var minimap: Control
var menu_layer: CanvasLayer
var map_script := preload("res://scripts/school_map.gd")
var minimap_script := preload("res://scripts/minimap.gd")
var student_scene := preload("res://scripts/student.gd")
var desk_scene := preload("res://scripts/interactable.gd")
var active_desk: Dictionary = {}
var studying := false
var study_paused := false
var held_question: Dictionary = {}
var study_efficiency := 1.0
var emptiness_timer := 0.0
var auto_study_timer := 0.0
var sprint_noise_timer := 0.0
var camera_zoom_base := 1.0
var zoom_tween: Tween
var end_panel_shown := false
var study_hunt_timer := 0.0
var mark_drift_timer := 0.0
var fog: Node2D
var tyrant: Node2D = null
var tyrant_spawned := false
var clear_started := false
var transitioning := false
var cutscene_active := false
var screen_fade: ColorRect
var fade_layer: CanvasLayer
var clear_layer: CanvasLayer
var stair_pos := Vector2.ZERO
var room_heat: Array[float] = []
var room_heat_cd: Array[float] = []
var room_heat_tier: Array[int] = []
var rustle_timer := 0.0
var visited_rooms := {}
var item_spawn_script := load("res://scripts/pickup.gd")
var tyrant_script := load("res://scripts/tyrant.gd")
var portal_anchor := Vector2.INF
var lamp_timer := 0.0
var item_fx: ItemFx
var last_run_stars := 0
var last_star_gain := 0
var modal_stack: Array[CanvasLayer] = []

func _ready() -> void:
	GameState.get_random_phase()
	_build_world()
	item_fx = ItemFx.new()
	item_fx.player = player
	add_child(item_fx)
	if not SaveManager.has_seen_intro() and not _is_test_run():
		_play_intro()
	else:
		_show_menu()

func _is_test_run() -> bool:
	for a in OS.get_cmdline_args():
		if "tests/" in a:
			return true
	return false

func _play_intro() -> void:
	var intro_script := load("res://scripts/intro.gd")
	if intro_script == null:
		_show_menu()
		return
	var intro: Node = intro_script.new()
	intro.finished.connect(func() -> void:
		SaveManager.mark_intro_seen()
		intro.queue_free()
		_show_menu())
	add_child(intro)
	intro.play()

func _build_world() -> void:
	map = map_script.new()
	add_child(map)
	map.generate(12345, 0)

	player = CharacterBody2D.new()
	player.set_script(load("res://scripts/player.gd"))
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	player.add_child(shape)
	add_child(player)
	player.position = map.exit_pos

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 9.0
	add_child(camera)
	camera_zoom_base = _zoom_for_map()
	camera.zoom = Vector2(camera_zoom_base, camera_zoom_base)
	_apply_camera_limits()
	camera.global_position = player.global_position

	fog = load("res://scripts/fog.gd").new()
	add_child(fog)
	fog.setup(map, player)
	_setup_lighting()

	hud = load("res://scripts/hud.gd").new()
	add_child(hud)
	quiz = load("res://scripts/quiz_ui.gd").new()
	add_child(quiz)

	minimap = minimap_script.new()
	hud.add_child(minimap)
	minimap.setup(map, player)
	minimap.anchor_left = 1.0
	minimap.anchor_right = 1.0
	minimap.offset_left = -212.0
	minimap.offset_right = -12.0
	minimap.offset_top = 8.0
	minimap.offset_bottom = 148.0

	fade_layer = CanvasLayer.new()
	fade_layer.layer = L_FADE
	add_child(fade_layer)
	screen_fade = ColorRect.new()
	screen_fade.color = Color(0, 0, 0, 0)
	screen_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_fade.visible = false
	fade_layer.add_child(screen_fade)

	_spawn_students()
	_spawn_desks()

	player.interacted.connect(_on_player_interact)
	quiz.connect("answered", _on_answered)
	quiz.opened.connect(_on_quiz_opened)
	quiz.closed.connect(_on_quiz_closed)
	quiz.stood_up.connect(_on_quiz_stood_up)
	map.player_caught.connect(_on_player_caught)
	map.noise_made.connect(_on_noise_made)
	map.room_entered.connect(_on_room_entered)
	map.door_slam.connect(_on_door_slam)
	GameState.hot_changed.connect(_on_hot_changed)

func _light_texture() -> Texture2D:
	if _light_tex != null:
		return _light_tex
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size, size) * 0.5
	var half := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center) / half
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_light_tex = ImageTexture.create_from_image(img)
	return _light_tex

func _setup_lighting() -> void:
	if world_modulate == null:
		world_modulate = CanvasModulate.new()
		world_modulate.name = "WorldLight"
		add_child(world_modulate)
	world_modulate.color = Color(0.68, 0.72, 0.84)
	if player_light == null:
		player_light = PointLight2D.new()
		player_light.name = "PlayerLight"
		player_light.texture = _light_texture()
		player_light.color = Color(1.0, 0.93, 0.80)
		player_light.energy = 0.75
		player_light.texture_scale = 1.35
		player_light.position = Vector2(0, -4)
		player.add_child(player_light)
	if level_lights != null and is_instance_valid(level_lights):
		level_lights.queue_free()
	level_lights = Node2D.new()
	level_lights.name = "LevelLights"
	add_child(level_lights)
	var cr: Rect2 = map.corridor_rect
	for f in [0.2, 0.5, 0.8]:
		var p := Vector2(cr.position.x + cr.size.x * float(f), cr.get_center().y)
		if not map.is_walkable(p):
			continue
		var lamp := PointLight2D.new()
		lamp.texture = _light_texture()
		lamp.color = Color(1.0, 0.86, 0.66)
		lamp.energy = 0.42
		lamp.texture_scale = 0.62
		lamp.position = p
		level_lights.add_child(lamp)
	_apply_lighting_visibility()

func _apply_lighting_visibility() -> void:
	var on := true
	if DevMode.enabled and not DevMode.lighting:
		on = false
	_lights_on = on
	if world_modulate != null:
		world_modulate.visible = on
	if player_light != null:
		player_light.visible = on
	if level_lights != null:
		level_lights.visible = on

func _update_lights(delta: float) -> void:
	if DevMode.enabled and DevMode.lighting != _lights_on:
		_apply_lighting_visibility()
	if not _lights_on or level_lights == null:
		return
	_light_time += delta
	var i := 0
	for child in level_lights.get_children():
		if child is PointLight2D:
			child.energy = 0.42 + sin(_light_time * 2.1 + float(i) * 1.7) * 0.045
		i += 1

func _zoom_for_map() -> float:
	return clampf(1.375 - 0.0625 * float(map.rooms.size()), 0.72, 1.0)

func _apply_camera_limits() -> void:
	if map.world_rect.size.x <= 0.0:
		return
	camera.limit_left = int(map.world_rect.position.x)
	camera.limit_right = int(map.world_rect.end.x)
	camera.limit_top = int(map.world_rect.position.y)
	camera.limit_bottom = int(map.world_rect.end.y)

func _setup_level(p_spawn_random := false) -> void:
	_close_all_modals()
	menu_layer = null
	clear_layer = null
	_stop_study()
	end_panel_shown = false
	clear_started = false
	cutscene_active = false
	study_hunt_timer = 0.0
	mark_drift_timer = 0.0
	GameState.dash_energy = 0.0
	GameState.tyrant_active = false
	GameState.cutscene_active = false
	emptiness_timer = 0.0
	auto_study_timer = 0.0
	sprint_noise_timer = 0.0
	rustle_timer = 0.0
	lamp_timer = 0.0
	portal_anchor = Vector2.INF
	if item_fx != null:
		item_fx.clear()
	tyrant_spawned = false
	tyrant = null
	if clear_layer != null and is_instance_valid(clear_layer):
		_pop_modal(clear_layer)
		clear_layer = null
	if quiz != null and quiz.is_open:
		quiz.close()
	for n in get_tree().get_nodes_in_group("tyrants"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group("pickups"):
		n.queue_free()
	map.generate(GameState.seed_value + GameState.level * 7919, 0)
	stair_pos = map.exit_pos
	if not map.stair_rects.is_empty():
		stair_pos = map._walkable_center(map.stair_rects[0])
	fog.reset_forget()
	if fog.has_method("set_tyrant_active"):
		fog.set_tyrant_active(false, GameState.level)
	player.position = _random_spawn_position() if p_spawn_random else map.exit_pos
	player.velocity = Vector2.ZERO
	player.stun_timer = 0.0
	player.can_move = true
	player.clear_item_buffs()
	if GameState.ability("shoes") > 0:
		player.passive_speed_mult = 1.1
		player.noise_mult = 0.8
	if GameState.ability("stopwatch") > 0:
		player.dash_charge_mult = 1.2
	player.passive_speed_mult *= 1.0 + GameState.passive_speed_bonus()
	player.dash_charge_mult *= 1.0 + GameState.dash_charge_bonus()
	if screen_fade != null:
		screen_fade.color.a = 0.0
		screen_fade.visible = false
		screen_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if zoom_tween != null and zoom_tween.is_valid():
		zoom_tween.kill()
	camera_zoom_base = _zoom_for_map()
	camera.zoom = Vector2(camera_zoom_base, camera_zoom_base)
	_apply_camera_limits()
	camera.reset_smoothing()
	camera.global_position = player.global_position
	visited_rooms.clear()
	if minimap != null and minimap.has_method("reset_discovered"):
		minimap.reset_discovered()
	room_heat.clear()
	room_heat_cd.clear()
	room_heat_tier.clear()
	for i in map.rooms.size():
		room_heat.append(0.0)
		room_heat_cd.append(0.0)
		room_heat_tier.append(0)
	_spawn_students()
	_spawn_desks()
	_spawn_high_value_spots()
	_spawn_items()
	_setup_lighting()
	if GameState.run_state == GameState.RunState.CLEARED:
		GameState.run_state = GameState.RunState.EXPLORING

func _start_level(p_level: int = 1) -> void:
	GameState.start_run(GameState.grade_id, GameState.subjects)
	GameState.set_level(p_level)
	GameState.get_random_phase()
	_setup_level(false)
	hud.toast("第 %d 层 · %s · 目标：净答对 %.0f 题" % [GameState.level, GameState.get_phase_label(), GameState.study_goal])

func _random_spawn_position() -> Vector2:
	if map == null or map.rooms.is_empty():
		return map.exit_pos if map != null else Vector2.ZERO
	var candidates: Array[int] = []
	for i in map.rooms.size():
		var t: String = String(map.room_types[i])
		if t != "hall" and t != "stair":
			candidates.append(i)
	if candidates.is_empty():
		return map.exit_pos
	var idx: int = candidates[randi_range(0, candidates.size() - 1)]
	return map._walkable_center(map.rooms[idx])

func _spawn_students() -> void:
	for s in get_tree().get_nodes_in_group("students"):
		s.queue_free()
	if map.rooms.is_empty(): return
	var count: int = 7 + (GameState.level - 1)
	var spots: Array[Vector2] = map.spawn_points(count, true)
	var roles: Array[String] = ["student", "student", "student", "juan", "juan", "teacher", "guard"]
	roles.shuffle()
	for i in count:
		var student: CharacterBody2D = student_scene.new()
		student.collision_layer = 2
		student.collision_mask = 1
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 11.0
		shape.shape = circle
		student.add_child(shape)
		student.set_role(roles[i % roles.size()])
		student.position = spots[i] if i < spots.size() else map.exit_pos
		add_child(student)
		student.setup(map, player)

func _spawn_desks() -> void:
	for d in get_tree().get_nodes_in_group("interactables"):
		d.queue_free()
	for desk_data in map.desks:
		_make_desk(desk_data["pos"], desk_data["efficiency"], desk_data["room"], desk_data.get("rect", Rect2(-20.0, -10.0, 40.0, 20.0)))

func _make_desk(pos: Vector2, eff: float, room: int, rect: Rect2) -> Node2D:
	var desk: Node2D = desk_scene.new()
	desk.setup_desk(pos, eff, room)
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = rect.size
	shape.shape = rs
	body.add_child(shape)
	desk.add_child(body)
	add_child(desk)
	return desk

func _spawn_high_value_spots() -> void:
	var office_rooms: Array[int] = []
	for i in map.rooms.size():
		if String(map.room_types[i]) == "office":
			office_rooms.append(i)
	office_rooms.shuffle()
	var made := 0
	for idx in office_rooms:
		if made >= 1:
			break
		var pos: Vector2 = map._walkable_center(map.rooms[idx])
		if pos.distance_to(map.exit_pos) < 40.0:
			continue
		_make_desk(pos, 1.5, idx, Rect2(-20.0, -10.0, 40.0, 20.0))
		made += 1
	var room_pool: Array[int] = []
	for i in map.rooms.size():
		var t: String = String(map.room_types[i])
		if t != "hall" and t != "stair" and t != "office" and t != "toilet":
			room_pool.append(i)
	room_pool.shuffle()
	if not room_pool.is_empty():
		var idx: int = room_pool[0]
		var pos: Vector2 = map._walkable_center(map.rooms[idx])
		var too_close := false
		for d in get_tree().get_nodes_in_group("interactables"):
			if d.position.distance_to(pos) < 55.0:
				too_close = true
				break
		if not too_close:
			_make_desk(pos, 1.6, idx, Rect2(-20.0, -10.0, 40.0, 20.0))

func _spawn_items() -> void:
	var ids: Array[String] = ["coffee", "bread", "smoke", "chair", "stink", "portal", "shovel", "lamp", "notes", "shoes", "stopwatch", "intel", "ears"]
	ids.shuffle()
	var pool: Array[int] = []
	for i in map.rooms.size():
		var t: String = String(map.room_types[i])
		if t != "hall" and t != "stair":
			pool.append(i)
	if pool.is_empty():
		return
	pool.shuffle()
	var want: int = mini(4, pool.size())
	for i in want:
		var idx: int = pool[i]
		var pos: Vector2 = map._walkable_center(map.rooms[idx])
		var pickup = item_spawn_script.new()
		var id: String = ids[i % ids.size()]
		var def: Dictionary = GameState.get_item_def(id)
		pickup.setup(id, def.get("color", Color.WHITE))
		pickup.position = pos + Vector2(randf_range(-18, 18), randf_range(-12, 12))
		pickup.picked.connect(_on_item_picked)
		pickup.full.connect(_on_item_full)
		add_child(pickup)

func _spawn_anti_tyrant_drops() -> void:
	var pool: Array[int] = []
	for i in map.rooms.size():
		var t := String(map.room_types[i])
		if t != "hall" and t != "stair" and t != "corridor":
			pool.append(i)
	pool.shuffle()
	var spots: Array[Vector2] = []
	for idx in pool:
		var p: Vector2 = map._walkable_center(map.rooms[idx])
		var too_close := false
		for n in get_tree().get_nodes_in_group("pickups"):
			if n.position.distance_to(p) < 60.0:
				too_close = true
				break
		if too_close:
			continue
		if tyrant != null and is_instance_valid(tyrant) and p.distance_to(tyrant.position) < 120.0:
			continue
		spots.append(p)
		if spots.size() >= 2:
			break
	# 兜底：候选房间不足（附近已有掉落/暴君占位）时，放宽距离限制补满 2 个
	if spots.size() < 2:
		for idx in pool:
			var p: Vector2 = map._walkable_center(map.rooms[idx])
			var dup := false
			for s in spots:
				if s.distance_to(p) < 24.0:
					dup = true
					break
			if dup:
				continue
			spots.append(p)
			if spots.size() >= 2:
				break
	for i in spots.size():
		var id: String = ANTI_TYRANT_ITEMS[i % ANTI_TYRANT_ITEMS.size()]
		if i > 0 and randf() > 0.65:
			id = GENERAL_ITEMS[randi() % GENERAL_ITEMS.size()]
		var def: Dictionary = GameState.get_item_def(id)
		var pickup = item_spawn_script.new()
		pickup.setup(id, def.get("color", Color.WHITE))
		pickup.position = spots[i] + Vector2(randf_range(-18, 18), randf_range(-12, 12))
		pickup.picked.connect(_on_item_picked)
		pickup.full.connect(_on_item_full)
		add_child(pickup)

func _on_item_picked(item_id: String) -> void:
	var def: Dictionary = GameState.get_item_def(item_id)
	hud.toast("拾取 %s：%s" % [String(def.get("name", item_id)), String(def.get("desc", ""))])

func _on_item_full(item_id: String) -> void:
	var def: Dictionary = GameState.get_item_def(item_id)
	hud.toast("背包已满，无法拾取 %s" % String(def.get("name", item_id)))

func _process(delta: float) -> void:
	_update_lights(delta)
	if transitioning or cutscene_active:
		return
	camera.global_position = player.global_position
	map.explore_room_at(player.position)

	var rs := GameState.run_state
	if rs == GameState.RunState.GAMEOVER:
		_on_game_over()
		return
	if rs == GameState.RunState.CLEARED:
		if quiz.is_open:
			quiz.close()
		_on_level_cleared()
		return
	if rs != GameState.RunState.EXPLORING and rs != GameState.RunState.QUIZ:
		return

	GameState.level_time += delta
	GameState.play_time += delta
	if quiz.is_open and not study_paused:
		GameState.quiz_time += delta
	if GameState.intel_reveal_timer > 0.0:
		GameState.intel_reveal_timer = maxf(0.0, GameState.intel_reveal_timer - delta)
	_update_answer_efficiency()
	_update_room_heat(delta)
	if lamp_timer > 0.0:
		lamp_timer = maxf(0.0, lamp_timer - delta)

	var active_study: bool = studying and not study_paused
	if rs == GameState.RunState.EXPLORING:
		if player.velocity.length() > 5.0 and player.is_dashing():
			sprint_noise_timer += delta
			if sprint_noise_timer >= 0.7:
				sprint_noise_timer = 0.0
				map.noise_made.emit(player.position, 12.0)
		else:
			sprint_noise_timer = 0.0
		if active_study:
			_study_noise_tick(delta)
		else:
			emptiness_timer += delta
			if emptiness_timer >= 1.0:
				emptiness_timer = 0.0
				GameState.damage_emptiness(1.0)
		_mark_drift_tick(delta)
	elif rs == GameState.RunState.QUIZ and active_study:
		_study_noise_tick(delta)

	_maybe_spawn_tyrant()

	if GameState.run_state == GameState.RunState.GAMEOVER:
		_on_game_over()
		return
	if GameState.run_state == GameState.RunState.CLEARED:
		if quiz.is_open:
			quiz.close()
		_on_level_cleared()
		return
	_update_prompt()

func _update_answer_efficiency() -> void:
	if not studying:
		GameState.answer_efficiency = 1.0
		return
	var aura := 1.0
	if tyrant != null and is_instance_valid(tyrant) and tyrant.has_method("aura_factor"):
		aura = float(tyrant.aura_factor())
	var lamp := 2.0 if lamp_timer > 0.0 else 1.0
	var notes := 1.0 + 0.1 * float(GameState.ability("notes"))
	GameState.answer_efficiency = study_efficiency * aura * lamp * notes

func _study_noise_tick(delta: float) -> void:
	rustle_timer += delta
	var interval := 2.2
	if lamp_timer > 0.0:
		interval = 1.4
	if rustle_timer < interval:
		return
	rustle_timer = 0.0
	var strength := 18.0 if lamp_timer <= 0.0 else 28.0
	if GameState.ability("ears") > 0:
		strength *= 0.5
	strength *= player.noise_mult
	map.noise_made.emit(player.position, strength)
	if strength >= 8.0:
		_dispatch_investigators(1, 5.0, player.position)

func _update_room_heat(delta: float) -> void:
	for i in room_heat.size():
		if room_heat_cd[i] > 0.0:
			room_heat_cd[i] = maxf(0.0, room_heat_cd[i] - delta)
			continue
		if room_heat[i] > 0.0:
			room_heat[i] = maxf(0.0, room_heat[i] - delta / 12.0)
		var tier := _heat_tier(room_heat[i])
		room_heat_tier[i] = tier

func _heat_tier(value: float) -> int:
	if value >= 6.0:
		return 3
	if value >= 4.0:
		return 2
	if value >= 2.0:
		return 1
	return 0

func _add_room_heat(index: int) -> void:
	if index < 0 or index >= room_heat.size():
		return
	var old_tier := room_heat_tier[index]
	room_heat[index] += 1.0
	room_heat_cd[index] = 10.0
	var tier := _heat_tier(room_heat[index])
	room_heat_tier[index] = tier
	if tier <= old_tier or index >= map.rooms.size():
		return
	var target: Vector2 = map._walkable_center(map.rooms[index])
	if tier == 2:
		_dispatch_investigators(1, 20.0, target, 0.15)
		hud.toast("这间房被盯上了：巡查者正在赶来！")
	elif tier >= 3:
		_dispatch_investigators(3, 34.0, target, 0.25)
		_spawn_temp_investigator(target, 34.0, 0.25)
		hud.toast("搜查升级：多名巡查者冲向你所在的房间！")

func _mark_drift_tick(delta: float) -> void:
	var w: int = GameState.warnings
	if w < 1:
		mark_drift_timer = 0.0
		return
	mark_drift_timer += delta
	var interval := 15.0
	if w >= 2:
		interval = 10.0
	if mark_drift_timer < interval:
		return
	mark_drift_timer = 0.0
	_dispatch_investigators(1 if w == 1 else 2, 6.0, player.position)

func _dispatch_investigators(count: int, dur: float, target: Vector2, buff: float = 0.0) -> void:
	var candidates: Array = []
	for s in get_tree().get_nodes_in_group("students"):
		if s.stun_timer > 0.0:
			continue
		candidates.append(s)
	candidates.sort_custom(func(a, b): return a.position.distance_to(target) < b.position.distance_to(target))
	for i in mini(count, candidates.size()):
		candidates[i].investigate(target, dur, buff)

func _spawn_temp_investigator(target: Vector2, duration: float, buff: float = 0.0) -> void:
	if map == null or map.spawn_points(1, true).is_empty():
		return
	var spawn: Vector2 = map.spawn_points(1, true)[0]
	var student: CharacterBody2D = student_scene.new()
	student.collision_layer = 2
	student.collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 11.0
	shape.shape = circle
	student.add_child(shape)
	student.set_role("guard")
	student.position = spawn
	add_child(student)
	student.setup(map, player)
	student.investigate(target, duration, buff)
	student.set_meta("temp_investigator", true)
	get_tree().create_timer(duration + 8.0).timeout.connect(func():
		if is_instance_valid(student):
			student.queue_free()
	)

func _nearest_desk(max_dist: float) -> Node2D:
	var nearest: Node2D = null
	var best := max_dist
	for desk in get_tree().get_nodes_in_group("interactables"):
		var d: float = player.position.distance_to(desk.position)
		if d < best:
			best = d
			nearest = desk
	return nearest

func _nearest_door(max_dist: float) -> Node2D:
	var nearest: Node2D = null
	var best := max_dist
	for door in map.door_nodes:
		var d: float = player.position.distance_to(door.position)
		if d < best:
			best = d
			nearest = door
	return nearest

func _update_prompt() -> void:
	if studying and not study_paused:
		hud.set_prompt("学习中…（F 暂停 · ESC 起身）")
		return
	if studying and study_paused:
		var pd := _nearest_door(44.0)
		if pd != null:
			hud.set_prompt("按 E 关门" if pd.is_open else "按 E 开门")
		else:
			hud.set_prompt("学习已暂停（F 继续 · ESC 起身）")
		return
	var desk := _nearest_desk(40.0)
	var door := _nearest_door(44.0)
	if door != null and (desk == null or player.position.distance_to(door.position) <= player.position.distance_to(desk.position)):
		hud.set_prompt("按 E 关门" if door.is_open else "按 E 开门")
	elif desk != null:
		hud.set_prompt(desk.get_prompt())
	else:
		hud.set_prompt("按 F 学习（效率 0.5 倍）· Shift 闪避 · WASD 移动 · ESC 菜单")

func _on_player_interact() -> void:
	if GameState.run_state == GameState.RunState.QUIZ:
		return
	var door := _nearest_door(44.0)
	if door == null:
		return
	if not door.toggle_from_player():
		hud.toast("你堵在门口，先挪开")

func _stop_study() -> void:
	studying = false
	study_paused = false
	held_question = {}
	active_desk = {}
	GameState.break_hot()

func _on_quiz_stood_up() -> void:
	_stand_up()

func _stand_up() -> void:
	_stop_study()
	hud.toast("起身离开座位")

func _toggle_study() -> void:
	if GameState.run_state == GameState.RunState.QUIZ:
		if not quiz.is_open:
			return
		held_question = quiz.current_question
		study_paused = true
		quiz.close()
		hud.toast("已暂停学习（F 继续 · ESC 起身）")
		return
	if GameState.run_state != GameState.RunState.EXPLORING:
		return
	if studying:
		study_paused = false
		var q: Dictionary = held_question
		held_question = {}
		if q.is_empty():
			q = QuestionBank.pick_tiered(GameState.questions_answered, GameState.hot_level())
		if q.is_empty():
			_stop_study()
			hud.toast("题库为空！请检查题库配置！")
			return
		quiz.open(q)
		return
	var desk := _nearest_desk(40.0)
	study_efficiency = 0.5
	active_desk = {}
	if desk != null:
		study_efficiency = float(desk.efficiency)
		active_desk = {"room": int(desk.room_index)}
	_update_answer_efficiency()
	auto_study_timer = 0.0
	study_hunt_timer = 0.0
	emptiness_timer = 0.0
	rustle_timer = 0.0
	var question := QuestionBank.pick_tiered(GameState.questions_answered, GameState.hot_level())
	if question.is_empty():
		active_desk = {}
		hud.toast("题库为空！请检查题库配置！")
		return
	studying = true
	study_paused = false
	_update_answer_efficiency()
	quiz.open(question)

func _modal_open() -> bool:
	_prune_modal_stack()
	if not modal_stack.is_empty():
		return true
	for n in get_tree().get_nodes_in_group("ui_modal"):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			return true
	return false

func _prune_modal_stack() -> void:
	var kept: Array[CanvasLayer] = []
	for m in modal_stack:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			kept.append(m)
	modal_stack = kept

## 所有弹窗统一走这里：层号按栈深递增（40/41/42/43），
## 保证"后开的永远盖住先开的，且始终低于转场黑幕(44)。
func _push_modal(layer: CanvasLayer) -> CanvasLayer:
	_prune_modal_stack()
	layer.layer = mini(L_MODAL + modal_stack.size(), L_MODAL_MAX)
	layer.add_to_group("ui_modal")
	add_child(layer)
	modal_stack.append(layer)
	return layer

func _pop_modal(layer) -> void:
	if layer == null:
		return
	modal_stack.erase(layer)
	if is_instance_valid(layer) and not layer.is_queued_for_deletion():
		layer.queue_free()

## 关掉指定弹窗之上的所有弹窗（栈顶回落）
func _close_modals_above(layer: CanvasLayer) -> void:
	if layer == null or not is_instance_valid(layer):
		return
	var idx := modal_stack.find(layer)
	if idx < 0:
		return
	for i in range(modal_stack.size() - 1, idx, -1):
		var m = modal_stack[i]
		modal_stack.remove_at(i)
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			m.queue_free()

func _close_all_modals() -> void:
	var list := modal_stack.duplicate()
	modal_stack.clear()
	for m in list:
		if is_instance_valid(m) and not m.is_queued_for_deletion():
			m.queue_free()

func _on_answered(correct: bool) -> void:
	var room_i: int = map.room_index_at(player.position)
	if room_i >= 0:
		_add_room_heat(room_i)
	if correct:
		hud.toast("回答正确！净答对 %.1f / %.0f" % [GameState.study, GameState.study_goal])
	else:
		hud.toast("答错！净答对 -1、空虚值 -2，还制造了动静")
		map.noise_made.emit(player.position, 45.0)
	_update_answer_efficiency()
	if GameState.run_state == GameState.RunState.CLEARED:
		_on_level_cleared()
	elif GameState.run_state == GameState.RunState.GAMEOVER:
		_on_game_over()
	elif studying:
		var question := QuestionBank.pick_tiered(GameState.questions_answered, GameState.hot_level())
		if not question.is_empty():
			quiz.open(question)
		else:
			studying = false

func _on_quiz_opened() -> void:
	hud.set_prompt("学习中…（F 暂停 · ESC 起身）")
	_tween_zoom(minf(camera_zoom_base * 1.5, 1.6))

func _on_quiz_closed() -> void:
	_tween_zoom(camera_zoom_base)

func _on_hot_changed(level: int) -> void:
	if hud != null and level > _last_hot_level:
		var names := ["", "I", "II", "III"]
		var mults := [1.0, 1.1, 1.2, 1.3]
		if level < names.size():
			hud.toast("火热 %s！答题收益 ×%.1f" % [names[level], mults[level]])
	_last_hot_level = level

func _tween_zoom(to: float) -> void:
	if camera == null:
		return
	if zoom_tween != null and zoom_tween.is_valid():
		zoom_tween.kill()
	zoom_tween = create_tween()
	zoom_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	zoom_tween.tween_property(camera, "zoom", Vector2(to, to), 0.35)

func _on_noise_made(pos: Vector2, strength: float) -> void:
	for s in get_tree().get_nodes_in_group("students"):
		s.hear_noise(pos, strength)

func _on_room_entered(index: int) -> void:
	if map == null or index < 0 or index >= map.room_names.size():
		return
	if not visited_rooms.has(index):
		visited_rooms[index] = true
		GameState.explored_rooms += 1
		GameState.intel_found += 1
		if not GameState.exam_hint and GameState.explored_rooms >= int(ceil(float(map.rooms.size()) * 0.6)):
			GameState.exam_hint = true
			hud.toast("探索度已达 60%：解锁「考试范围」，答题会排除一个错误选项")
	hud.toast("进入 %s" % String(map.room_names[index]))

func _on_door_slam() -> void:
	hud.toast("门板砸中了！")

func _fx_flash(col: Color, peak: float, dur: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = L_FX
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(col.r, col.g, col.b, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)
	var t := create_tween()
	t.tween_property(rect, "color:a", peak, 0.08)
	t.tween_property(rect, "color:a", 0.0, dur)
	t.tween_callback(layer.queue_free)

func _punish_effect(by: Node2D) -> void:
	if player != null:
		_shake_camera(10.0, 0.45)
	var layer := CanvasLayer.new()
	layer.layer = L_FX
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	UiTheme.apply(root)
	var flash := ColorRect.new()
	flash.color = Color(0.55, 0.02, 0.02, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(flash)
	var vt := create_tween()
	vt.tween_property(flash, "color:a", 0.42, 0.12)
	vt.tween_property(flash, "color:a", 0.12, 0.6)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var center := Vector2(vs.x * 0.5, vs.y * 0.46)
	for i in 16:
		var line := Line2D.new()
		var ang := TAU * float(i) / 16.0 + randf_range(-0.12, 0.12)
		line.width = randf_range(3.0, 9.0)
		line.default_color = Color(0.85, 0.08, 0.06, 0.9)
		line.points = PackedVector2Array([center + Vector2(cos(ang), sin(ang)) * randf_range(90.0, 130.0), center + Vector2(cos(ang), sin(ang)) * randf_range(320.0, 460.0)])
		root.add_child(line)
		var lt := create_tween()
		lt.tween_property(line, "modulate:a", 0.0, 0.55)
	var burst := Label.new()
	burst.text = "被抓！"
	burst.add_theme_font_size_override("font_size", 92)
	burst.add_theme_color_override("font_color", Color(0.95, 0.12, 0.1))
	burst.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0))
	burst.add_theme_constant_override("outline_size", 12)
	burst.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	burst.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	burst.set_anchors_preset(Control.PRESET_FULL_RECT)
	burst.scale = Vector2(2.4, 2.4)
	burst.pivot_offset = Vector2(vs.x * 0.5, vs.y * 0.46)
	burst.modulate.a = 0.0
	root.add_child(burst)
	var bt := create_tween()
	bt.tween_property(burst, "modulate:a", 1.0, 0.08)
	bt.parallel().tween_property(burst, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.tween_interval(0.3)
	bt.parallel().tween_property(burst, "modulate:a", 0.0, 0.3)
	bt.tween_property(root, "modulate:a", 0.0, 0.3)
	bt.tween_callback(layer.queue_free)

func _on_player_caught(by: Node2D) -> void:
	if player != null and player.is_dodging():
		return
	var was_quiz: bool = GameState.run_state == GameState.RunState.QUIZ
	if not was_quiz and GameState.run_state != GameState.RunState.EXPLORING:
		return
	if was_quiz:
		if quiz.is_open:
			quiz.close()
		_stop_study()
		GameState.caught_count += 1
		_punish_effect(by)
		GameState.add_warning(1)
		GameState.damage_emptiness(6.0)
		player.stun(0.8)
		player.velocity = Vector2.ZERO
		if by != null and is_instance_valid(by):
			by.stun(2.5)
		if GameState.run_state == GameState.RunState.GAMEOVER:
			_on_game_over()
		elif GameState.warnings == 1:
			hud.toast("被抓！警告 %d/%d，答题中断——已被标记，巡查员会向你靠拢，快逃！" % [GameState.warnings, GameState.max_warnings])
		else:
			hud.toast("又被抓！警告 %d/%d，标记加深——他们更频繁逼近，快逃！" % [GameState.warnings, GameState.max_warnings])
		return
	GameState.caught_count += 1
	_punish_effect(by)
	GameState.add_warning(1)
	GameState.damage_emptiness(6.0)
	player.stun(1.2)
	player.position = map.exit_pos
	player.velocity = Vector2.ZERO
	camera.reset_smoothing()
	camera.global_position = player.global_position
	if by != null and is_instance_valid(by):
		by.stun(2.5)
	for s in get_tree().get_nodes_in_group("students"):
		s.alert_level = 0.0
		s.state = "patrol"
	if GameState.run_state == GameState.RunState.GAMEOVER:
		_on_game_over()
	else:
		hud.toast("被卷狗抓住！警告 %d/%d，空虚值 -6" % [GameState.warnings, GameState.max_warnings])

func _maybe_spawn_tyrant() -> void:
	if GameState.level < 4 or tyrant_spawned or clear_started:
		return
	if GameState.study < GameState.study_goal * 0.5:
		return
	if not GameState.tyrant_intro_seen:
		if map.room_index_at(player.position) < 0:
			return
		_start_tyrant_intro()
		return
	_spawn_tyrant(1.5)

func _spawn_tyrant(idle: float, forced_pos := Vector2.INF) -> Node2D:
	if tyrant_spawned and tyrant != null and is_instance_valid(tyrant):
		return tyrant
	var pos: Vector2 = forced_pos
	if pos == Vector2.INF:
		pos = _far_spawn_point(340.0)
	tyrant = tyrant_script.new()
	tyrant.collision_layer = 4
	tyrant.collision_mask = 1
	tyrant.position = pos
	add_child(tyrant)
	tyrant.setup(map, player, GameState.level)
	tyrant.idle_timer = idle
	tyrant.hit_player.connect(_on_tyrant_hit)
	tyrant_spawned = true
	GameState.tyrant_active = true
	if GameState.tyrant_intro_seen:
		tyrant.roar()
		_shake_camera(5.0, 0.3)
	if fog.has_method("set_tyrant_active"):
		fog.set_tyrant_active(true, GameState.level)
	_spawn_anti_tyrant_drops()
	return tyrant

func _far_spawn_point(min_dist: float) -> Vector2:
	var points: Array[Vector2] = map.spawn_points(28, true)
	if points.is_empty():
		return map.exit_pos
	points.shuffle()
	var best: Vector2 = points[0]
	var best_d := -1.0
	for p in points:
		var d: float = p.distance_to(player.position)
		if d >= min_dist:
			return p
		if d > best_d:
			best_d = d
			best = p
	return best

func _on_tyrant_hit() -> void:
	GameState.tyrant_hits += 1
	if quiz.is_open:
		quiz.close()
	_stop_study()
	hud.toast("暴君抓住了你！眩晕 1.5 秒，赶紧拉开距离！")
	_shake_camera(7.0, 0.35)

func _shake_camera(amount: float, duration: float) -> void:
	if camera == null:
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var steps := 7
	for i in steps:
		var off := Vector2(randf_range(-amount, amount), randf_range(-amount, amount))
		tw.tween_property(camera, "offset", off, duration / float(steps))
	tw.tween_property(camera, "offset", Vector2.ZERO, duration / float(steps))

func _wait(sec: float) -> void:
	if cutscene_active and (Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		await get_tree().process_frame
		return
	await get_tree().create_timer(sec, true).timeout

func _start_tyrant_intro() -> void:
	if cutscene_active or GameState.tyrant_intro_seen:
		return
	cutscene_active = true
	tyrant_spawned = true
	GameState.cutscene_active = true
	player.can_move = false
	player.velocity = Vector2.ZERO
	get_tree().paused = true

	var room_i: int = map.room_index_at(player.position)
	var room_center: Vector2 = map._walkable_center(map.rooms[room_i])
	var door_pos: Vector2 = room_center
	if room_i >= 0 and room_i < map.doors.size():
		var dp: Vector2 = map.doors[room_i]["pos"]
		var axis: String = String(map.doors[room_i].get("axis", "h"))
		door_pos = dp
		if axis == "h":
			door_pos.y += 30.0 * signf(map.corridor_rect.get_center().y - dp.y)
		else:
			door_pos.x += 30.0 * signf(map.corridor_rect.get_center().x - dp.x)

	var layer := CanvasLayer.new()
	layer.layer = L_TYRANT_CUT
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var alarm: AudioStream = load("res://assets/sfx/alarm.mp3")
	if alarm == null:
		alarm = load("res://assets/sfx/alarm_a.wav")
	if alarm != null:
		var alarm_player := AudioStreamPlayer.new()
		alarm_player.stream = alarm
		alarm_player.volume_db = -4.0
		layer.add_child(alarm_player)
		alarm_player.play()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)
	UiTheme.apply(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.03, 0.96)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	# 四格漫画版式：2×2 等大格子；图按 4:3 完整显示（不裁切），字幕条在图片下方
	var gutter := 14.0
	var cap_h := 34.0
	var pad := 3.0
	var margin := Vector2(vs.x * 0.045, vs.y * 0.045)
	var avail := vs - margin * 2.0
	var cell_w := (avail.x - gutter) * 0.5
	var cell_h := (avail.y - gutter) * 0.5
	var img_h := cell_h - cap_h
	var img_w := img_h * (4.0 / 3.0)
	if img_w > cell_w:
		img_w = cell_w
		img_h = img_w * 0.75
	var panel_w := img_w
	var panel_h := img_h + cap_h
	var grid_w := panel_w * 2.0 + gutter
	var grid_h := panel_h * 2.0 + gutter
	var ox := (vs.x - grid_w) * 0.5
	var oy := (vs.y - grid_h) * 0.5
	var corners: Array[Vector2] = [
		Vector2(ox, oy),
		Vector2(ox + panel_w + gutter, oy),
		Vector2(ox, oy + panel_h + gutter),
		Vector2(ox + panel_w + gutter, oy + panel_h + gutter),
	]
	var texts: Array[String] = [
		"走廊尽头\n有什么在靠近",
		"整栋楼\n都在看你，",
		"它闻到了\n你的气息",
		"别回头，",
	]
	var panels: Array[Control] = []
	var panel_paths: Array[String] = [
		"res://art/cutscene/tyrant_p1.png",
		"res://art/cutscene/tyrant_p2.png",
		"res://art/cutscene/tyrant_p3.png",
		"res://art/cutscene/tyrant_p4.png",
	]
	for i in 4:
		var wrap := Control.new()
		wrap.position = corners[i]
		wrap.size = Vector2(panel_w, panel_h)
		wrap.clip_contents = true
		wrap.modulate.a = 0.0
		wrap.scale = Vector2(0.92, 0.92)
		wrap.pivot_offset = Vector2(panel_w * 0.5, panel_h * 0.5)
		root.add_child(wrap)
		var frame := Panel.new()
		frame.size = Vector2(panel_w, panel_h)
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = Color(0.02, 0.02, 0.03)
		fsb.border_color = Color(0.72, 0.06, 0.06)
		fsb.set_border_width_all(int(pad))
		fsb.set_corner_radius_all(0)
		frame.add_theme_stylebox_override("panel", fsb)
		wrap.add_child(frame)
		var art_size := Vector2(panel_w - pad * 2.0, img_h - pad)
		var tex: Texture2D = load(panel_paths[i]) if ResourceLoader.exists(panel_paths[i]) else null
		if tex != null:
			var art := TextureRect.new()
			art.texture = tex
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			art.position = Vector2(pad, pad)
			wrap.add_child(art)
			art.size = art_size
		else:
			var paper := ColorRect.new()
			paper.color = Color(0.90, 0.88, 0.82)
			paper.position = Vector2(pad, pad)
			paper.size = art_size
			wrap.add_child(paper)
		var caption_bg := ColorRect.new()
		caption_bg.color = Color(0.04, 0.04, 0.05)
		caption_bg.position = Vector2(pad, img_h)
		caption_bg.size = Vector2(panel_w - pad * 2.0, panel_h - img_h - pad)
		wrap.add_child(caption_bg)
		var label := Label.new()
		label.text = texts[i].replace("\n", " ")
		label.position = Vector2(pad + 6.0, img_h)
		label.size = Vector2(panel_w - pad * 2.0 - 12.0, panel_h - img_h - pad)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		wrap.add_child(label)
		panels.append(wrap)

	for i in panels.size():
		var tw := create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(panels[i], "modulate:a", 1.0, 0.28)
		tw.parallel().tween_property(panels[i], "scale", Vector2.ONE, 0.28)
		await _wait(0.52)

	await _wait(0.45)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.9)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(flash)
	var ftw := create_tween()
	ftw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	ftw.tween_property(flash, "color:a", 0.0, 0.5)
	_shake_camera(11.0, 0.6)
	_spawn_tyrant(8.0, room_center)
	for i in 12:
		var debris := ColorRect.new()
		debris.color = Color(0.12, 0.10, 0.09, 0.9)
		debris.size = Vector2(randf_range(6, 24), randf_range(4, 14))
		debris.position = Vector2(vs.x * 0.5 + randf_range(-120, 120), vs.y * 0.5 + randf_range(-90, 90))
		root.add_child(debris)
	await _wait(0.5)

	player.position = door_pos
	player.velocity = Vector2.ZERO
	camera.global_position = player.position
	camera.reset_smoothing()
	await _wait(0.6)

	var blood := Label.new()
	blood.text = "快跑！"
	blood.add_theme_font_size_override("font_size", 78)
	blood.add_theme_color_override("font_color", Color(0.82, 0.03, 0.03))
	blood.add_theme_color_override("font_outline_color", Color(0.15, 0.0, 0.0))
	blood.add_theme_constant_override("outline_size", 8)
	blood.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blood.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	blood.set_anchors_preset(Control.PRESET_FULL_RECT)
	blood.modulate.a = 0.0
	root.add_child(blood)
	var btw := create_tween()
	btw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	btw.tween_property(blood, "modulate:a", 1.0, 0.35)
	await _wait(1.5)
	var fade := create_tween()
	fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(root, "modulate:a", 0.0, 0.5)
	await _wait(0.55)

	layer.queue_free()
	get_tree().paused = false
	GameState.cutscene_active = false
	cutscene_active = false
	GameState.tyrant_intro_seen = true
	player.can_move = true
	SaveManager.save_run()
	hud.toast("暴君登场！它甩开了你，正在环视——快跑！")
	AudioManager.kick()

func _on_level_cleared() -> void:
	if clear_started or end_panel_shown:
		return
	clear_started = true
	end_panel_shown = true
	GameState.run_state = GameState.RunState.CLEARED
	_stop_study()
	player.can_move = false
	player.velocity = Vector2.ZERO
	if quiz.is_open:
		quiz.close()
	hud.set_prompt("")
	hud.toast("第 %d 层目标达成！" % GameState.level)
	if GameState.level >= GameState.MAX_LEVEL:
		GameState.game_cleared = true
	var star_run: int = GameState.evaluate_stars(GameState.level, GameState.level_time, GameState.caught_count)
	last_run_stars = star_run
	last_star_gain = GameState.award_stars(GameState.level, star_run)
	GameState.mark_level_cleared(GameState.level)
	SaveManager.save_run()
	await _fade_chasers()
	_show_clear_panel()

func _fade_chasers() -> void:
	for s in get_tree().get_nodes_in_group("students"):
		if is_instance_valid(s):
			var tw := create_tween()
			tw.tween_property(s, "modulate:a", 0.0, 1.0)
	for t in get_tree().get_nodes_in_group("tyrants"):
		if is_instance_valid(t) and t.has_method("fade_out"):
			t.fade_out()
	await get_tree().create_timer(1.1).timeout

func _format_time(seconds: float) -> String:
	var total := int(maxf(0.0, seconds))
	return "%02d:%02d" % [total / 60, total % 60]

func _show_clear_panel() -> void:
	if clear_layer != null and is_instance_valid(clear_layer):
		_pop_modal(clear_layer)
	clear_layer = CanvasLayer.new()
	_push_modal(clear_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	clear_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(center)
	clear_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 360)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "%dF 通关" % GameState.level
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var total := int(GameState.questions_answered)
	var acc := 0.0
	if total > 0:
		acc = 100.0 * float(GameState.quiz_correct) / float(total)
	var stats := Label.new()
	stats.text = "用时 %s　　答题 %d 题　正确率 %.0f%%\n被发现 %d 次　暴君击晕 %d 次\n道具 %d 件　情报 %d 处　探索 %d 间房" % [
		_format_time(GameState.level_time), total, acc,
		int(GameState.caught_count), int(GameState.tyrant_hits),
		int(GameState.items_collected), int(GameState.intel_found), int(GameState.explored_rooms),
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(stats)
	var star_txt := ""
	for i in last_run_stars:
		star_txt += "★"
	if last_run_stars == 0:
		star_txt = "☆☆☆"
	var star_row := Label.new()
	var gain_txt := ""
	if last_star_gain > 0:
		gain_txt = "  +%d" % last_star_gain
	star_row.text = "本局 %s%s　　历史最高 %d★　　★总数 %d" % [
		star_txt, gain_txt, GameState.star_best(GameState.level), GameState.stars]
	star_row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_row.modulate = Color(1.0, 0.85, 0.4)
	star_row.add_theme_font_size_override("font_size", 20)
	vbox.add_child(star_row)
	var rep: Dictionary = GameState.star_report(GameState.level, GameState.level_time, GameState.caught_count)
	var acc_v: float = float(rep["accuracy"])
	var qt: float = float(rep["quiz_time"])
	var time_ok: bool = bool(rep["time_ok"])
	var caught_ok: bool = GameState.caught_count == 0
	var acc_ok: bool = acc_v >= GameState.STAR_ACC_3
	var quiz_ok: bool = qt <= GameState.STAR_QUIZ_TIME_3
	var detail := Label.new()
	detail.text = "用时 %s %s　　被抓 %d %s\n正确率 %.0f%% %s　　净答题 %s %s\n冲星分 %.0f（门槛 ★%d · 加权 ★%d）" % [
		_format_time(GameState.level_time), "✅" if time_ok else "❌",
		int(GameState.caught_count), "✅" if caught_ok else "❌",
		acc_v, "✅" if acc_ok else "❌",
		_format_time(qt), "✅" if quiz_ok else "❌",
		float(rep["score"]), int(rep["gate"]), int(rep["weighted"]),
	]
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.modulate = Color(0.78, 0.8, 0.86)
	detail.add_theme_font_size_override("font_size", 14)
	vbox.add_child(detail)
	if GameState.level >= GameState.MAX_LEVEL:
		var end_tex: Texture2D = load("res://art/cutscene/ending_placeholder.png") if ResourceLoader.exists("res://art/cutscene/ending_placeholder.png") else null
		if end_tex != null:
			var art := TextureRect.new()
			art.texture = end_tex
			art.custom_minimum_size = Vector2(0, 160)
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			vbox.add_child(art)
		var end := Label.new()
		end.text = "全部通关 / 毕业\n（结局与制作名单占位）"
		end.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		end.modulate = Color(1.0, 0.85, 0.6)
		vbox.add_child(end)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	if GameState.level < GameState.MAX_LEVEL:
		var next := Button.new()
		next.text = "下一关（上楼）"
		next.custom_minimum_size = Vector2(150, 40)
		next.pressed.connect(_begin_ascend)
		row.add_child(next)
	var shop_btn := Button.new()
	shop_btn.text = "升级商店"
	shop_btn.custom_minimum_size = Vector2(120, 40)
	shop_btn.pressed.connect(func(): _show_shop())
	row.add_child(shop_btn)
	var menu := Button.new()
	menu.text = "回到主菜单"
	menu.custom_minimum_size = Vector2(130, 40)
	menu.pressed.connect(_leave_clear_to_menu)
	row.add_child(menu)

func _begin_ascend() -> void:
	if transitioning:
		return
	transitioning = true
	if clear_layer != null and is_instance_valid(clear_layer):
		_pop_modal(clear_layer)
		clear_layer = null
	player.can_move = false
	player.velocity = Vector2.ZERO
	hud.toast("正在前往楼梯…")
	var path: Array = map.find_path(player.position, stair_pos)
	if path.is_empty():
		path = [stair_pos]
	for point in path:
		await _ascend_step_to(point)
	await get_tree().create_timer(0.25).timeout
	await _fade_to_black(0.65)
	GameState.begin_next_level()
	_setup_level(true)
	await get_tree().create_timer(0.35).timeout
	await _fade_from_black(0.6)
	transitioning = false
	player.can_move = true
	hud.toast("第 %d 层 · %s · 目标：净答对 %.0f 题" % [GameState.level, GameState.get_phase_label(), GameState.study_goal])
	SaveManager.save_run()

func _ascend_step_to(target: Vector2) -> void:
	var detour := 0.0
	var budget := int(target.distance_to(player.position) / 7.0) * 3 + 240
	while player.position.distance_to(target) > 4.0:
		budget -= 1
		if budget <= 0:
			player.position = target
			break
		var dir := (target - player.position).normalized()
		if not _obstacle_ahead(player.position + dir * 16.0):
			detour = 0.0
			player.position = player.position.move_toward(target, 7.0)
		else:
			if detour == 0.0:
				detour = -1.0 if _obstacle_ahead(player.position + dir.orthogonal() * 16.0) else 1.0
			var side := dir.orthogonal() * detour
			if _obstacle_ahead(player.position + side * 16.0):
				detour = -detour
				side = dir.orthogonal() * detour
			if _obstacle_ahead(player.position + side * 16.0):
				player.position = player.position.move_toward(target, 7.0)
			else:
				player.position = player.position + side * 7.0
		for door in map.door_nodes:
			if is_instance_valid(door) and player.position.distance_to(door.position) < 30.0:
				door.set_open(true, true)
		await get_tree().create_timer(0.016).timeout

func _obstacle_ahead(p: Vector2) -> bool:
	for n in get_tree().get_nodes_in_group("interactables"):
		if not (n is Node2D):
			continue
		for c in n.get_children():
			if c is StaticBody2D:
				for s in c.get_children():
					if s is CollisionShape2D and s.shape is RectangleShape2D:
						var gr: Rect2 = s.get_global_transform() * s.shape.get_rect()
						if gr.has_point(p):
							return true
	for r2 in map.box_rects:
		if r2.has_point(p):
			return true
	return map.door_blocks_point(p)

func _leave_clear_to_menu() -> void:
	if transitioning:
		return
	if GameState.level < GameState.MAX_LEVEL:
		GameState.set_level(GameState.level + 1)
		GameState.warnings = 0
		GameState.emptiness = maxf(40.0, GameState.emptiness)
	else:
		GameState.game_cleared = true
	SaveManager.save_run()
	if clear_layer != null and is_instance_valid(clear_layer):
		_pop_modal(clear_layer)
		clear_layer = null
	GameState.run_state = GameState.RunState.MENU
	_show_menu()

func _fade_to_black(duration: float) -> void:
	if screen_fade == null:
		return
	screen_fade.visible = true
	screen_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var start_a: float = screen_fade.color.a
	var tw := create_tween()
	tw.tween_property(screen_fade, "color:a", 1.0, duration).from(start_a)
	await tw.finished

func _fade_from_black(duration: float) -> void:
	if screen_fade == null:
		return
	var tw := create_tween()
	tw.tween_property(screen_fade, "color:a", 0.0, duration)
	await tw.finished
	screen_fade.visible = false
	screen_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _on_game_over() -> void:
	if end_panel_shown:
		return
	end_panel_shown = true
	_stop_study()
	var reason := "空虚值归零" if GameState.emptiness <= 0.0 else "警告 %d/%d" % GameState.max_warnings
	hud.toast("失败：%s" % reason)
	_show_end_panel("失败", "%s。重开本关，保留能力，失去部分消耗品。" % reason)

func _show_end_panel(title: String, desc: String) -> void:
	var layer := CanvasLayer.new()
	_push_modal(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(center)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 200)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 32)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t)
	var d := Label.new()
	d.text = desc
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(d)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)
	var retry := Button.new()
	retry.text = "重开本关"
	retry.pressed.connect(func():
		_pop_modal(layer)
		GameState.warnings = 0
		GameState.study = 0
		GameState.emptiness = 50
		GameState.seed_value = randi()
		GameState.run_state = GameState.RunState.EXPLORING
		_setup_level()
		hud.toast("重开第 %d 关（换了一张新地图）" % GameState.level)
	)
	row.add_child(retry)
	var quit := Button.new()
	quit.text = "主菜单"
	quit.pressed.connect(func():
		_pop_modal(layer)
		GameState.run_state = GameState.RunState.MENU
		_show_menu()
	)
	row.add_child(quit)

func _nearest_tyrant(max_dist: float) -> Node2D:
	if tyrant == null or not is_instance_valid(tyrant):
		return null
	if player.position.distance_to(tyrant.position) > max_dist:
		return null
	return tyrant

func _use_item(index: int) -> void:
	if GameState.run_state != GameState.RunState.EXPLORING or _modal_open():
		return
	if index < 0:
		return
	if index >= GameState.inventory.size():
		return
	var id: String = GameState.inventory_item_id(index)
	var def: Dictionary = GameState.get_item_def(id)
	var fx: Vector2 = player.position
	match id:
		"coffee":
			player.apply_speed_buff(1.4, 8.0)
			GameState.remove_item_at(index)
			item_fx.burst("coffee", fx)
			_fx_flash(Color(1.0, 0.62, 0.25), 0.10, 0.35)
			hud.toast("咖啡下肚：移速 +40%，持续 8 秒")
		"bread":
			GameState.restore_emptiness(25.0)
			GameState.remove_item_at(index)
			item_fx.burst("bread", fx)
			hud.toast("面包下肚：空虚值 +25")
		"smoke":
			var t_smoke := _nearest_tyrant(420.0)
			if t_smoke == null:
				hud.toast("附近没有暴君，烟雾弹先留着")
				return
			t_smoke.smoke_slow(5.0)
			GameState.remove_item_at(index)
			item_fx.burst("smoke", fx, t_smoke.position)
			hud.toast("烟雾弹：暴君减速并暂时跟丢")
		"chair":
			var t_chair := _nearest_tyrant(100.0)
			if t_chair == null:
				hud.toast("太远了，折叠椅够不到暴君")
				return
			var dir: Vector2 = (t_chair.position - player.position).normalized()
			t_chair.stun_tyrant(2.0)
			t_chair.position += dir * 46.0
			GameState.remove_item_at(index)
			item_fx.burst("chair", fx, t_chair.position)
			_shake_camera(7.0, 0.28)
			_fx_flash(Color(1.0, 0.85, 0.3), 0.12, 0.3)
			hud.toast("折叠椅命中！暴君眩晕 2 秒")
		"stink":
			var t_stink := _nearest_tyrant(650.0)
			if t_stink == null:
				hud.toast("附近没有暴君，臭气弹先留着")
				return
			t_stink.lure_to(player.position + Vector2(randf_range(-70, 70), randf_range(-50, 50)), 5.0)
			GameState.remove_item_at(index)
			item_fx.burst("stink", fx, t_stink.position)
			hud.toast("臭气弹：暴君被引向错误方向！")
		"portal":
			if portal_anchor == Vector2.INF:
				portal_anchor = player.position
				item_fx.burst("portal", portal_anchor)
				hud.toast("任意门已放置。再次使用返回这里")
				return
			var back := portal_anchor
			portal_anchor = Vector2.INF
			var from_pos := player.position
			player.position = back
			GameState.remove_item_at(index)
			camera.reset_smoothing()
			camera.global_position = player.global_position
			item_fx.burst("portal", player.position, from_pos)
			hud.toast("任意门：传送回标记点")
		"shovel":
			var from_pos2 := player.position
			player.position = _random_spawn_position()
			map.noise_made.emit(player.position, 55.0)
			GameState.remove_item_at(index)
			camera.reset_smoothing()
			camera.global_position = player.global_position
			item_fx.burst("shovel", from_pos2, player.position)
			hud.toast("土锹：挖出一条捷径，但动静很大")
		"lamp":
			lamp_timer = 10.0
			GameState.remove_item_at(index)
			item_fx.burst("lamp", fx)
			_fx_flash(Color(1.0, 0.88, 0.4), 0.14, 0.4)
			hud.toast("超频台灯：学习效率翻倍 10 秒，但翻书声更大")
		"notes":
			GameState.set_ability("notes")
			GameState.remove_item_at(index)
			item_fx.burst("notes", fx)
			hud.toast("学霸笔记：本关学习效率 +10%")
		"shoes":
			GameState.set_ability("shoes")
			player.passive_speed_mult = 1.1
			player.noise_mult = 0.8
			GameState.remove_item_at(index)
			item_fx.burst("shoes", fx)
			hud.toast("软底鞋：移速 +10%，动静更小")
		"stopwatch":
			GameState.set_ability("stopwatch")
			player.dash_charge_mult = 1.2
			GameState.remove_item_at(index)
			item_fx.burst("stopwatch", fx)
			hud.toast("秒表：闪避充能速度 +20%")
		"intel":
			GameState.intel_reveal_timer = 12.0
			GameState.remove_item_at(index)
			item_fx.burst("intel", fx)
			hud.toast("巡查情报：12 秒内小地图显示巡查者位置")
		"ears":
			GameState.set_ability("ears")
			GameState.remove_item_at(index)
			item_fx.burst("ears", fx)
			hud.toast("耳塞：本关翻书声减半（土锹等杂音不受影响）")
		_:
			hud.toast("这个道具暂时用不了")

func _unhandled_input(event: InputEvent) -> void:
	if transitioning or cutscene_active or GameState.cutscene_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.physical_keycode
		if kc == KEY_R:
			_use_item(0)
			get_viewport().set_input_as_handled()
			return
		if kc == KEY_T:
			_use_item(1)
			get_viewport().set_input_as_handled()
			return
		if kc == KEY_Y:
			_use_item(2)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("study"):
		if _modal_open():
			return
		_toggle_study()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and GameState.run_state == GameState.RunState.EXPLORING:
		if _modal_open():
			return
		if studying:
			_stand_up()
		elif not quiz.visible:
			_show_pause_menu()

func _show_pause_menu() -> void:
	var layer := CanvasLayer.new()
	_push_modal(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(center)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 340)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "暂停"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(_volume_settings_box())
	for item in [
		["继续", func(): _pop_modal(layer)],
		["保存进度", func():
			var ok := SaveManager.save_run()
			hud.toast("保存成功" if ok else "保存失败")
			_pop_modal(layer)],
		["读取进度", func():
			if SaveManager.load_run():
				_setup_level()
				hud.toast("读取成功")
			else:
				hud.toast("没有存档")
			_pop_modal(layer)],
		["导入题库（开发）", func(): _pop_modal(layer); _import_bank()] if DevMode.enabled and DevMode.import_bank else [],
		["主菜单", func():
			_pop_modal(layer)
			GameState.run_state = GameState.RunState.MENU
			_show_menu()],
	]:
		if item.is_empty():
			continue
		var btn := Button.new()
		btn.text = item[0]
		btn.pressed.connect(item[1])
		vbox.add_child(btn)

func _show_shop() -> void:
	for m in modal_stack:
		if is_instance_valid(m) and m.has_meta("shop"):
			return
	var layer := CanvasLayer.new()
	layer.set_meta("shop", true)
	_push_modal(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(center)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 520)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "升级商店"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var star_label := Label.new()
	star_label.add_theme_font_size_override("font_size", 22)
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_label.modulate = Color(1.0, 0.85, 0.4)
	star_label.text = "★ %d" % GameState.stars
	vbox.add_child(star_label)
	var hint := Label.new()
	hint.text = "通关每关可得 1~3★（同关历史最高封顶 3★）；能力永久保留"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.7, 0.7, 0.8)
	hint.add_theme_font_size_override("font_size", 14)
	vbox.add_child(hint)
	for key in GameState.UPGRADE_DEFS:
		var def: Dictionary = GameState.UPGRADE_DEFS[key]
		var row := HBoxContainer.new()
		var info := Label.new()
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.custom_minimum_size = Vector2(360, 0)
		row.add_child(info)
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(120, 44)
		var refresh := func() -> void:
			var lv2 := GameState.upgrade_level(key)
			var mx2 := int(def["max"])
			info.text = "%s（%d/%d）\n%s" % [def["name"], lv2, mx2, def["desc"]]
			if lv2 >= mx2:
				buy.text = "已满级"
				buy.disabled = true
			else:
				buy.text = "购买 %d★" % int(def["cost"])
				buy.disabled = not GameState.can_buy(key)
		buy.pressed.connect(func():
			if GameState.buy_upgrade(key):
				hud.toast("已升级：%s" % def["name"])
				SaveManager.save_run()
				refresh.call()
				star_label.text = "★ %d" % GameState.stars)
		refresh.call()
		row.add_child(buy)
		vbox.add_child(row)
	var close := Button.new()
	close.text = "返回"
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func():
		SaveManager.save_run()
		_pop_modal(layer))
	vbox.add_child(close)

func _volume_settings_box() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	for row_def in [
		["主音量", AudioManager.master_volume, AudioManager.set_master_volume],
		["音乐音量", AudioManager.music_volume, AudioManager.set_music_volume],
	]:
		var row := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = row_def[0]
		lbl.custom_minimum_size = Vector2(78, 0)
		row.add_child(lbl)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.value = row_def[1]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var setter: Callable = row_def[2]
		slider.value_changed.connect(func(v: float): setter.call(v))
		row.add_child(slider)
		var val := Label.new()
		val.text = "%d%%" % int(row_def[1])
		val.custom_minimum_size = Vector2(48, 0)
		slider.value_changed.connect(func(v: float): val.text = "%d%%" % int(v))
		row.add_child(val)
		box.add_child(row)
	var mute_row := HBoxContainer.new()
	var mute_lbl := Label.new()
	mute_lbl.text = "静音"
	mute_lbl.custom_minimum_size = Vector2(78, 0)
	mute_row.add_child(mute_lbl)
	var mute_btn := Button.new()
	mute_btn.toggle_mode = true
	mute_btn.button_pressed = AudioManager.muted
	mute_btn.text = "已静音（点击恢复）" if AudioManager.muted else "声音开启（点击静音）"
	mute_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mute_btn.toggled.connect(func(on: bool):
		AudioManager.set_muted(on)
		mute_btn.text = "已静音（点击恢复）" if on else "声音开启（点击静音）")
	mute_row.add_child(mute_btn)
	box.add_child(mute_row)
	return box

func _import_bank() -> void:
	if OS.has_feature("web"):
		hud.toast("网页版请用本地文件导入面板。")
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; JSON 题库", "*.csv ; CSV 题库", "*.txt ; 文本"])
	dialog.file_selected.connect(func(path: String):
		var text := FileAccess.get_file_as_string(path)
		var result := QuestionBank.import_text(text, path.get_file())
		if result.get("ok", false):
			hud.toast("导入成功：%d 条" % result.get("added", 0))
		else:
			hud.toast("导入失败：%s" % result.get("error", "未知错误"))
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.close_requested.connect(func(): dialog.queue_free())
	dialog.add_to_group("ui_modal")
	add_child(dialog)
	dialog.popup_centered()

func _show_menu() -> void:
	if menu_layer != null and is_instance_valid(menu_layer):
		_pop_modal(menu_layer)
	menu_layer = CanvasLayer.new()
	_push_modal(menu_layer)
	_build_menu_background(menu_layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(center)
	menu_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.COL_PANEL_BORDER, UiTheme.COL_PANEL_BG, 3))
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "卷狗必须死"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.98, 0.96, 0.90))
	title.add_theme_color_override("font_outline_color", Color(0.36, 0.08, 0.22, 1.0))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "躺平世界 · 学习违法 · 内卷狗必须死"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
	sub.add_theme_font_size_override("font_size", 12)
	vbox.add_child(sub)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 9)
	vbox.add_child(buttons)
	var menu_buttons: Array[Button] = []

	var start := _menu_button("开始游戏", UiTheme.COL_GOLD, true, func(): _show_level_select())
	buttons.add_child(start)
	menu_buttons.append(start)

	if SaveManager.has_save():
		var load_btn := _menu_button("继续游戏", UiTheme.COL_GREEN, false, func():
			if SaveManager.load_run():
				_pop_modal(menu_layer)
				menu_layer = null
				_setup_level()
				hud.toast("已读取存档 · 第 %d 层" % GameState.level))
		buttons.add_child(load_btn)
		menu_buttons.append(load_btn)

	var intro_btn := _menu_button("重看开场动画", UiTheme.COL_CYAN, false, func():
		_pop_modal(menu_layer)
		menu_layer = null
		_play_intro())
	buttons.add_child(intro_btn)
	menu_buttons.append(intro_btn)

	var shop_btn := _menu_button("升级商店（★ %d）" % GameState.stars, UiTheme.COL_PURPLE, false, func(): _show_shop())
	buttons.add_child(shop_btn)
	menu_buttons.append(shop_btn)

	if DevMode.enabled and DevMode.import_bank:
		var import_btn := _menu_button("导入题库（开发）", UiTheme.COL_ORANGE, false, func(): _import_bank())
		buttons.add_child(import_btn)
		menu_buttons.append(import_btn)

	vbox.add_child(HSeparator.new())
	vbox.add_child(_volume_settings_box())

	var tip := Label.new()
	tip.text = "按 F 学习 · 通关后永久解锁下一层"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
	tip.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tip)

	# 面板淡入 + 标题弹入 + 按钮错峰出现
	panel.modulate.a = 0.0
	var pt := create_tween()
	pt.tween_property(panel, "modulate:a", 1.0, 0.22)
	title.pivot_offset = Vector2(260, 36)
	title.scale = Vector2(0.82, 0.82)
	var tt := create_tween()
	tt.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(title, "scale", Vector2.ONE, 0.45)
	for i in menu_buttons.size():
		var b: Button = menu_buttons[i]
		b.modulate.a = 0.0
		b.scale = Vector2(0.96, 0.96)
		var bt := create_tween()
		bt.tween_interval(0.05 + 0.06 * i)
		bt.tween_property(b, "modulate:a", 1.0, 0.18)
		bt.parallel().tween_property(b, "scale", Vector2.ONE, 0.18)

	_spawn_menu_lightning(menu_layer)

func _show_level_select() -> void:
	var layer := CanvasLayer.new()
	_push_modal(layer)
	_build_menu_background(layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(center)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style())
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "选择楼层"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(0.98, 0.96, 0.90))
	title.add_theme_color_override("font_outline_color", Color(0.36, 0.08, 0.22, 1.0))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var tip := Label.new()
	tip.text = "通关第 n 层永久解锁第 n+1 层"
	if DevMode.enabled and DevMode.unlock_all_levels:
		tip.text += "（开发者版全开）"
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
	tip.add_theme_font_size_override("font_size", 12)
	vbox.add_child(tip)

	var cards := HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 10)
	vbox.add_child(cards)
	var card_nodes: Array[Control] = []

	for lv in range(1, GameState.MAX_LEVEL + 1):
		var accent := UiTheme.get_button_color(lv - 1)
		var unlocked: bool = GameState.is_level_unlocked(lv)
		var best: int = GameState.star_best(lv)

		var card := Control.new()
		card.custom_minimum_size = Vector2(100, 120)
		card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cards.add_child(card)

		var card_sb := UiTheme.panel_style(accent if unlocked else Color(0.35, 0.33, 0.42), Color(0.11, 0.08, 0.19, 0.98), 2)
		card_sb.border_width_top = 7
		card_sb.shadow_size = 3
		card_sb.content_margin_left = 4
		card_sb.content_margin_right = 4
		var bg := Panel.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.add_theme_stylebox_override("panel", card_sb)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(bg)

		var card_v := VBoxContainer.new()
		card_v.set_anchors_preset(Control.PRESET_FULL_RECT)
		card_v.offset_top = 14
		card_v.offset_bottom = -12
		card_v.alignment = BoxContainer.ALIGNMENT_CENTER
		card_v.add_theme_constant_override("separation", 2)
		card_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(card_v)

		var lv_label := Label.new()
		lv_label.text = "%dF" % lv
		lv_label.add_theme_font_size_override("font_size", 24)
		lv_label.add_theme_color_override("font_color", accent if unlocked else UiTheme.COL_TEXT_DIM)
		lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_v.add_child(lv_label)

		var star_label := Label.new()
		if not unlocked:
			star_label.text = "未解锁"
			star_label.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
		elif best <= 0:
			star_label.text = "待通关"
			star_label.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
		else:
			star_label.text = "★".repeat(best)
			star_label.add_theme_color_override("font_color", UiTheme.COL_GOLD)
		star_label.add_theme_font_size_override("font_size", 12)
		star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		star_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_v.add_child(star_label)

		if unlocked:
			var hit := Button.new()
			hit.flat = true
			hit.text = ""
			hit.set_anchors_preset(Control.PRESET_FULL_RECT)
			hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			hit.pressed.connect(_on_level_card_pressed.bind(lv))
			hit.mouse_entered.connect(func():
				card.pivot_offset = card.size * 0.5
				var tw := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				tw.tween_property(card, "scale", Vector2(1.07, 1.07), 0.14))
			hit.mouse_exited.connect(func():
				var tw := card.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tw.tween_property(card, "scale", Vector2.ONE, 0.12))
			card.add_child(hit)
		else:
			card.modulate = Color(0.72, 0.70, 0.80, 0.85)
		card_nodes.append(card)

	vbox.add_child(HSeparator.new())
	var back := _menu_button("返回", UiTheme.COL_CYAN, false, func(): _pop_modal(layer))
	vbox.add_child(back)

	panel.modulate.a = 0.0
	var pt := create_tween()
	pt.tween_property(panel, "modulate:a", 1.0, 0.22)
	for i in card_nodes.size():
		var c: Control = card_nodes[i]
		c.modulate.a = 0.0
		c.scale = Vector2(0.88, 0.88)
		c.pivot_offset = c.custom_minimum_size * 0.5
		var ct := create_tween()
		ct.tween_interval(0.04 * i)
		ct.tween_property(c, "modulate:a", 1.0, 0.16)
		ct.parallel().tween_property(c, "scale", Vector2.ONE, 0.16)

	_spawn_menu_lightning(layer)

func _on_level_card_pressed(lv: int) -> void:
	AudioManager.kick()
	_close_all_modals()
	menu_layer = null
	_start_level(lv)
	if not bool(GameState.story_flags.get("dlg_tutorial", false)):
		GameState.story_flags["dlg_tutorial"] = true
		var ui := show_dialogue(DialogueDb.tutorial())
		if ui != null:
			ui.finished.connect(func(): _maybe_show_level_dialogue(lv), CONNECT_ONE_SHOT)
			return
	_maybe_show_level_dialogue(lv)

func show_dialogue(data: DialogueData, pause_game := true) -> Control:
	if data == null or data.lines.is_empty():
		return null
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_push_modal(layer)
	var ui: Control = load("res://scripts/dialogue_ui.gd").new()
	layer.add_child(ui)
	if pause_game:
		_dialogue_prev_paused = get_tree().paused
		get_tree().paused = true
	ui.finished.connect(func():
		if pause_game:
			get_tree().paused = _dialogue_prev_paused
		_pop_modal(layer)
	)
	ui.start(data)
	return ui

func _maybe_show_level_dialogue(level: int) -> void:
	var key := "dlg_lv_%d" % level
	if bool(GameState.story_flags.get(key, false)):
		return
	var data := DialogueDb.level_tip(level)
	if data == null:
		return
	GameState.story_flags[key] = true
	show_dialogue(data)

func _build_menu_background(layer: CanvasLayer) -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)

	var vs: Vector2 = get_viewport().get_visible_rect().size
	
	# 校园怪谈诡异色系：灰绿、暗紫、昏黄
	var horror_colors = [
		UiTheme.COL_ACCENT,   # 灰绿
		UiTheme.COL_PURPLE,   # 暗紫
		UiTheme.COL_ORANGE,   # 昏黄
		UiTheme.COL_GREEN,    # 病态绿
		UiTheme.COL_BLUE,     # 暗冷蓝
	]
	
	# 诡异的漂浮雾气
	for i in 7:
		var blob := ColorRect.new()
		var col = horror_colors[i % horror_colors.size()]
		blob.color = Color(col, 0.075)  # 淡但可辨，营造诡异气氛
		blob.size = Vector2(randf_range(150, 350), randf_range(100, 220))
		blob.position = Vector2(randf_range(-80, vs.x), randf_range(-80, vs.y))
		blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(blob)
		var start := blob.position
		var tw := blob.create_tween().set_loops()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(blob, "position", start + Vector2(randf_range(-30, 30), randf_range(-20, 20)), randf_range(5, 9))
		tw.tween_property(blob, "position", start, randf_range(5, 9))

	# 偶发的诡异粒子（像素雪/尘埃）
	for i in 25:
		var px := ColorRect.new()
		var col = horror_colors[i % horror_colors.size()]
		col.a = randf_range(0.2, 0.6)  # 很淡的粒子
		px.color = col
		px.size = Vector2.ONE * randf_range(2, 5)
		px.position = Vector2(randf_range(0, vs.x), randf_range(0, vs.y))
		px.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(px)
		var start := px.position
		var dur := randf_range(6, 14)
		var tw := px.create_tween().set_loops()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.tween_property(px, "position", start + Vector2(randf_range(-24, 24), -randf_range(100, 280)), dur)
		tw.tween_property(px, "position", start, 0.01)

	# 电视雪花效果（诡异感）
	var y := 0
	while y < int(vs.y):
		var line := ColorRect.new()
		line.color = Color(0.0, 0.0, 0.0, 0.08)
		line.position = Vector2(0, y)
		line.size = Vector2(vs.x, 1)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(line)
		y += 8

func _spawn_menu_lightning(parent: Node) -> void:
	var fx := Control.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fx)
	if parent is Node:
		parent.set_meta("lightning_fx", fx)
	_spawn_random_lightning(fx, get_viewport().get_visible_rect().size)

func _spawn_random_lightning(layer: Node, viewport_size: Vector2) -> void:
	var lightning_loop = func() -> void:
		while is_instance_valid(layer):
			await get_tree().create_timer(randf_range(1.2, 3.0)).timeout
			if not is_instance_valid(layer):
				return
			_draw_branching_lightning(layer, viewport_size)

	create_tween().tween_callback(lightning_loop)

func _draw_branching_lightning(layer: Node, viewport_size: Vector2) -> void:
	if not is_instance_valid(layer):
		return
	var made: Array[Node] = []
	# 闪电起点（顶部随机）
	var start_x = randf_range(viewport_size.x * 0.15, viewport_size.x * 0.85)
	var start_y = -50.0
	var end_y = randf_range(viewport_size.y * 0.45, viewport_size.y * 0.95)
	
	# 全屏白闪（只做轻微曝光，不洗白 UI）
	var flash := ColorRect.new()
	flash.color = Color(0.80, 0.90, 1.0, 0.11)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	made.append(flash)
	
	# 绘制主闪电路径（曲折）
	var segments: Array[Vector2] = []
	_generate_lightning_path(Vector2(start_x, start_y), Vector2(start_x + randf_range(-70, 70), end_y), segments, 0, 7)
	
	# 画主闪电
	for i in range(segments.size() - 1):
		# 外光晕
		var glow := Line2D.new()
		glow.add_point(segments[i])
		glow.add_point(segments[i + 1])
		glow.width = 14.0
		glow.default_color = Color(0.42, 0.60, 1.0, 0.16)
		layer.add_child(glow)
		made.append(glow)

		var line := Line2D.new()
		line.add_point(segments[i])
		line.add_point(segments[i + 1])
		line.width = 4.5
		line.default_color = Color(0.78, 0.90, 1.0, 0.96)
		layer.add_child(line)
		made.append(line)

		# 纯白内核
		var core := Line2D.new()
		core.add_point(segments[i])
		core.add_point(segments[i + 1])
		core.width = 2.2
		core.default_color = Color(1.0, 1.0, 1.0, 1.0)
		layer.add_child(core)
		made.append(core)
	
	# 随机分叉（4-6条，每条再带小分叉）
	var branch_count = randi_range(4, 6)
	for b in range(branch_count):
		var branch_start_idx = randi_range(0, maxi(0, segments.size() - 2))
		var branch_start = segments[branch_start_idx]
		var branch_angle = randf_range(-0.85, 0.85)
		var branch_direction = (segments[branch_start_idx + 1] - branch_start).normalized()
		var rotated = branch_direction.rotated(branch_angle)
		var branch_end = branch_start + rotated * randf_range(60.0, 200.0)
		
		var branch_segments: Array[Vector2] = []
		_generate_lightning_path(branch_start, branch_end, branch_segments, 0, 3)
		
		for i in range(branch_segments.size() - 1):
			var line := Line2D.new()
			line.add_point(branch_segments[i])
			line.add_point(branch_segments[i + 1])
			line.width = 2.2
			line.default_color = Color(0.72, 0.86, 1.0, 0.75)
			layer.add_child(line)
			made.append(line)

		# 二级小分叉
		if randf() < 0.6 and branch_segments.size() > 2:
			var si = randi_range(0, branch_segments.size() - 2)
			var s0 = branch_segments[si]
			var dir = (branch_segments[si + 1] - s0).normalized().rotated(randf_range(-0.9, 0.9))
			var sub_end = s0 + dir * randf_range(25.0, 70.0)
			var sub_seg: Array[Vector2] = []
			_generate_lightning_path(s0, sub_end, sub_seg, 0, 2)
			for i in range(sub_seg.size() - 1):
				var sub := Line2D.new()
				sub.add_point(sub_seg[i])
				sub.add_point(sub_seg[i + 1])
				sub.width = 1.4
				sub.default_color = Color(0.65, 0.8, 1.0, 0.55)
				layer.add_child(sub)
				made.append(sub)
	
	# 真实闪电式的多次闪烁
	flash.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.06)
	tween.tween_callback(func(): _flash_alpha(flash, 0.0))
	tween.tween_interval(0.04)
	tween.tween_callback(func(): _flash_alpha(flash, 0.75))
	tween.tween_interval(0.05)
	tween.tween_callback(func(): _flash_alpha(flash, 0.0))
	tween.tween_interval(0.06)
	tween.tween_callback(func(): _flash_alpha(flash, 0.45))
	tween.tween_interval(0.04)
	tween.tween_callback(func(): _flash_alpha(flash, 0.0))
	tween.tween_interval(0.5)
	await tween.finished
	for n in made:
		if is_instance_valid(n):
			n.queue_free()

func _flash_alpha(rect: ColorRect, a: float) -> void:
	if is_instance_valid(rect):
		rect.modulate.a = a

func _generate_lightning_path(start: Vector2, end: Vector2, segments: Array[Vector2], depth: int, max_depth: int) -> void:
	if depth > max_depth:
		segments.append(end)
		return
	
	segments.append(start)
	
	# 中点加随机偏移（曲折感）
	var mid = (start + end) * 0.5
	var offset_distance = (end - start).length() * 0.22
	var random_offset = Vector2(randf_range(-offset_distance, offset_distance), randf_range(-offset_distance * 0.45, offset_distance * 0.45))
	var mid_point = mid + random_offset
	
	_generate_lightning_path(start, mid_point, segments, depth + 1, max_depth)
	_generate_lightning_path(mid_point, end, segments, depth + 1, max_depth)

func _menu_button(label: String, accent: Color, big: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 60 if big else 50)
	b.add_theme_font_size_override("font_size", 24)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_stylebox_override("normal", UiTheme.accent_button_style(accent))
	b.add_theme_stylebox_override("hover", UiTheme.accent_button_style(accent, true))
	b.add_theme_stylebox_override("pressed", UiTheme.accent_button_style(accent.darkened(0.25), true))
	var focus_sb := StyleBoxFlat.new()
	focus_sb.draw_center = false
	focus_sb.border_color = UiTheme.COL_GOLD
	focus_sb.set_border_width_all(3)
	focus_sb.set_corner_radius_all(0)
	b.add_theme_stylebox_override("focus", focus_sb)
	b.add_theme_color_override("font_color", UiTheme.COL_TEXT)
	b.add_theme_color_override("font_hover_color", Color(0.05, 0.03, 0.10))
	b.add_theme_color_override("font_pressed_color", Color(0.05, 0.03, 0.10))
	b.pressed.connect(on_press)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func():
		b.text = "▶  " + label
		var tw := b.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(1.03, 1.03), 0.12))
	b.mouse_exited.connect(func():
		b.text = label
		var tw := b.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2.ONE, 0.12))
	return b
