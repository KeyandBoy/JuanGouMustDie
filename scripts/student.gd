extends CharacterBody2D

const JUAN_TEX := [
	preload("res://art/sprites/64/05_npc_front.png"),
	preload("res://art/sprites/64/06_npc_back.png"),
	preload("res://art/sprites/64/07_npc_left.png"),
	preload("res://art/sprites/64/08_npc_right.png"),
	preload("res://art/sprites/64/09_npc_chase.png"),
	preload("res://art/sprites/64/10_npc_search.png"),
	preload("res://art/sprites/64/11_npc_stun.png"),
]
const STUDENT_TEX := [
	preload("res://art/sprites/64/12_student_front.png"),
	preload("res://art/sprites/64/13_student_back.png"),
	preload("res://art/sprites/64/14_student_left.png"),
	preload("res://art/sprites/64/15_student_right.png"),
	preload("res://art/sprites/64/24_student_chase.png"),
	preload("res://art/sprites/64/25_student_search.png"),
	preload("res://art/sprites/64/26_student_stun.png"),
]
const TEACHER_TEX := [
	preload("res://art/sprites/64/16_teacher_front.png"),
	preload("res://art/sprites/64/17_teacher_back.png"),
	preload("res://art/sprites/64/18_teacher_left.png"),
	preload("res://art/sprites/64/19_teacher_right.png"),
	preload("res://art/sprites/64/27_teacher_chase.png"),
	preload("res://art/sprites/64/28_teacher_search.png"),
	preload("res://art/sprites/64/29_teacher_stun.png"),
]
const GUARD_TEX := [
	preload("res://art/sprites/64/20_guard_front.png"),
	preload("res://art/sprites/64/21_guard_back.png"),
	preload("res://art/sprites/64/22_guard_left.png"),
	preload("res://art/sprites/64/23_guard_right.png"),
	preload("res://art/sprites/64/30_guard_chase.png"),
	preload("res://art/sprites/64/31_guard_search.png"),
	preload("res://art/sprites/64/32_guard_stun.png"),
]
const VISUAL_SCALE := 0.7

var role := "juan"
var sprite: Sprite2D
var bob_time := 0.0
var map
var player
var alert_level := 0.0
var temp_buff := 0.0
var temp_buff_timer := 0.0
var max_alert := 100.0
var vision_range := 160.0
var vision_angle := 60.0
## 抓人判定：以守卫为圆心、360° 的独立判定圈，半径远小于视锥半径。
## 与朝向/视锥角度无关，但要求中间没有墙体遮挡（不能隔墙抓人）。
var catch_radius := 30.0
var hear_range := 260.0
var speed := 80.0
var chase_speed := 140.0
var facing := Vector2.DOWN
var state := "patrol"
var stun_timer := 0.0
var catch_cooldown := 0.0
var door_pause := 0.0
var pending_door: Node2D = null
var self_noise_pos := Vector2(INF, INF)

var path := PackedVector2Array()
var path_index := 0
var repath_timer := 0.0
var idle_timer := 0.0
var state_timer := 0.0
var last_seen := Vector2.ZERO
var can_see := false

func _ready() -> void:
	add_to_group("students")
	sprite = Sprite2D.new()
	sprite.texture = _textures()[0]
	sprite.scale = Vector2(VISUAL_SCALE, VISUAL_SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 1
	add_child(sprite)

func set_role(p_role: String) -> void:
	role = p_role if p_role in ["juan", "student", "teacher", "guard"] else "juan"
	if sprite != null:
		sprite.texture = _textures()[0]

func _textures() -> Array:
	match role:
		"student":
			return STUDENT_TEX
		"teacher":
			return TEACHER_TEX
		"guard":
			return GUARD_TEX
	return JUAN_TEX

func setup(p_map: Node2D, p_player: Node2D) -> void:
	map = p_map
	player = p_player
	last_seen = position

func _physics_process(delta: float) -> void:
	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if temp_buff_timer > 0.0:
		temp_buff_timer -= delta
		if temp_buff_timer <= 0.0 and temp_buff > 0.0:
			var m := 1.0 + temp_buff
			speed = 80.0 / m
			chase_speed = 140.0 / m
			vision_range = 160.0 / m
			hear_range = 260.0 / m
			temp_buff = 0.0
	if door_pause > 0.0:
		door_pause -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		if door_pause <= 0.0:
			_open_pending_door()
		return
	if catch_cooldown > 0.0:
		catch_cooldown -= delta
	if map == null or player == null or (GameState.run_state != GameState.RunState.EXPLORING and GameState.run_state != GameState.RunState.QUIZ):
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player: Vector2 = player.position - position
	var dist: float = to_player.length()
	can_see = _can_see_player(to_player, dist)
	if can_see:
		alert_level = minf(max_alert, alert_level + delta * (55.0 + (1.0 - clampf(dist / vision_range, 0.0, 1.0)) * 75.0))
		facing = to_player.normalized()
		last_seen = player.position
		if GameState.run_state == GameState.RunState.QUIZ:
			if state != "chase":
				state = "chase"
				repath_timer = 0.0
				state_timer = 4.0
		elif GameState.warnings >= 1:
			if state != "stalk":
				state = "stalk"
				repath_timer = 0.0
				state_timer = 4.0
		elif state == "chase" or state == "stalk":
			state = "patrol"
			path = PackedVector2Array()
			path_index = 0
			idle_timer = 0.0
	else:
		alert_level = maxf(0.0, alert_level - delta * 35.0)

	if GameState.run_state == GameState.RunState.QUIZ and catch_cooldown <= 0.0 and not _player_dodging() and _in_catch_range():
		_catch()
		move_and_slide()
		return

	match state:
		"patrol":
			_patrol(delta)
		"chase":
			_chase(delta)
		"search":
			_search(delta)
		"stalk":
			_stalk(delta)
	if _try_door_ahead():
		move_and_slide()
		return
	move_and_slide()

func _in_catch_range() -> bool:
	if map == null or player == null:
		return false
	if position.distance_to(player.position) > catch_radius:
		return false
	return map.vision_clear(position, player.position)

func _can_see_player(to_player: Vector2, dist: float) -> bool:
	var stun = player.get("stun_timer")
	if stun != null and float(stun) > 0.0:
		return false
	if dist > vision_range:
		return false
	if dist > 1.0:
		var dir := to_player / dist
		if absf(rad_to_deg(facing.angle_to(dir))) > vision_angle * 0.5:
			return false
	return map.vision_clear(position, player.position)

func _player_dodging() -> bool:
	if player == null:
		return false
	var d = player.get("dashing")
	return d != null and bool(d)

func _try_door_ahead() -> bool:
	if map == null or velocity.length() < 5.0:
		return false
	var best: Node2D = null
	var bd := 30.0
	for d in map.door_nodes:
		if not d.is_closed():
			continue
		var to_door: Vector2 = d.position - position
		var dist := to_door.length()
		if dist > bd or dist < 1.0:
			continue
		if facing.dot(to_door / dist) < 0.35:
			continue
		bd = dist
		best = d
	if best == null:
		return false
	pending_door = best
	door_pause = 0.3
	velocity = Vector2.ZERO
	return true

func _open_pending_door() -> void:
	if pending_door == null or not is_instance_valid(pending_door):
		pending_door = null
		return
	pending_door.set_open(true, true, position)
	var door_pos: Vector2 = pending_door.position
	pending_door = null
	if map != null:
		self_noise_pos = door_pos
		map.noise_made.emit(door_pos, 18.0)
		self_noise_pos = Vector2(INF, INF)

func _catch() -> void:
	catch_cooldown = 4.0
	alert_level = max_alert * 0.3
	state = "patrol"
	path = PackedVector2Array()
	path_index = 0
	map.player_caught.emit(self)

func _patrol(delta: float) -> void:
	if idle_timer > 0.0:
		idle_timer -= delta
		velocity = velocity.move_toward(Vector2.ZERO, delta * 340.0)
		return
	if _at_path_end():
		_choose_patrol_target()
		idle_timer = randf_range(0.3, 1.6)
		return
	_follow_path(speed)

func _choose_patrol_target() -> void:
	var enter_room := randf() < 0.45
	var target_pos: Vector2 = map.random_room_center(false) if enter_room else map.random_nav_point(true)
	if target_pos.distance_to(position) < 40.0:
		target_pos = map.random_room_center(false)
	_set_path(target_pos)

func _chase(delta: float) -> void:
	if not can_see:
		state = "search"
		state_timer = 3.2
		_set_path(last_seen)
		return
	repath_timer -= delta
	if repath_timer <= 0.0:
		repath_timer = 0.35
		_set_path(player.position)
	_follow_path(chase_speed)

func _search(delta: float) -> void:
	state_timer -= delta
	if can_see:
		if GameState.run_state == GameState.RunState.QUIZ:
			state = "chase"
		elif GameState.warnings >= 1:
			state = "stalk"
		return
	if _at_path_end() or state_timer <= 0.0:
		state = "patrol"
		idle_timer = 0.0
		path = PackedVector2Array()
		return
	_follow_path(speed * 0.9)

func _stalk(delta: float) -> void:
	var mark: int = GameState.warnings
	var keep := 100.0
	if mark >= 2:
		keep = 60.0
	elif mark >= 1:
		keep = 80.0
	if can_see:
		var dist := position.distance_to(player.position)
		facing = (player.position - position).normalized()
		last_seen = player.position
		state_timer = 4.0
		if mark >= 1:
			state_timer += 2.0
		if mark >= 2:
			state_timer += 2.0
		if dist <= keep:
			velocity = Vector2.ZERO
			return
		repath_timer -= delta
		if repath_timer <= 0.0:
			repath_timer = 0.6
			_set_path(player.position)
		_follow_path(speed * 0.7)
		return
	state_timer -= delta
	if _at_path_end() or state_timer <= 0.0:
		state = "patrol"
		idle_timer = 0.0
		path = PackedVector2Array()
		return
	_follow_path(speed * 0.85)

func investigate(target: Vector2, dur: float, buff: float = 0.0) -> void:
	if stun_timer > 0.0 or state == "chase":
		return
	state = "search"
	state_timer = dur
	last_seen = target
	_set_path(target)
	if buff > 0.0:
		_apply_temp_buff(buff)

func _apply_temp_buff(buff: float) -> void:
	if temp_buff > 0.0:
		temp_buff_timer = 40.0
		return
	temp_buff = buff
	var m := 1.0 + buff
	speed = 80.0 * m
	chase_speed = 140.0 * m
	vision_range = 160.0 * m
	hear_range = 260.0 * m
	temp_buff_timer = 40.0

func _set_path(target: Vector2) -> void:
	if map == null:
		return
	path = map.find_path(position, target)
	path_index = 0

func _at_path_end() -> bool:
	return path_index >= path.size()

func _follow_path(spd: float) -> void:
	if path.is_empty():
		velocity = Vector2.ZERO
		return
	while path_index < path.size() and position.distance_to(path[path_index]) < 14.0:
		path_index += 1
	if path_index >= path.size():
		velocity = Vector2.ZERO
		return
	var dir: Vector2 = (path[path_index] - position).normalized()
	velocity = dir * spd
	facing = dir

func hear_noise(pos: Vector2, strength: float) -> void:
	if pos == self_noise_pos:
		return
	var dist := position.distance_to(pos)
	if dist > hear_range:
		return
	if map != null and not map.sound_clear(pos, position):
		return
	alert_level = minf(max_alert, alert_level + strength * (1.0 - dist / hear_range))
	if state != "chase":
		state = "search"
		state_timer = 3.0
		last_seen = pos
		_set_path(pos)

func stun(t: float) -> void:
	stun_timer = t
	alert_level = 0.0
	state = "patrol"
	path = PackedVector2Array()
	path_index = 0

func _draw() -> void:
	if map != null and stun_timer <= 0.0:
		if DevMode.show_vision_cones:
			_draw_vision_cone()
			_draw_catch_circle()
		elif _should_show_watch_hint():
			_draw_watch_hint()
	var ratio := alert_level / max_alert
	if GameState.warnings >= 1 and ratio > 0.01:
		var bar_w := 36.0
		draw_rect(Rect2(-bar_w * 0.5, -26, bar_w, 6), Color(0.2, 0.2, 0.2))
		var c := Color(0.2, 0.8, 0.3) if ratio < 0.5 else Color(0.95, 0.75, 0.15) if ratio < 0.85 else Color(0.95, 0.25, 0.2)
		draw_rect(Rect2(-bar_w * 0.5, -26, bar_w * ratio, 6), c)
		if ratio > 0.7:
			draw_circle(Vector2(0, -36), 6.0, Color(0.95, 0.25, 0.2))

## 开发者版：完整视锥（含墙体遮挡），F1 切换。
func _draw_vision_cone() -> void:
	var fill := Color(0.55, 0.80, 1.0, 0.12)
	var edge := Color(0.60, 0.85, 1.0, 0.34)
	if state == "chase":
		fill = Color(0.95, 0.27, 0.20, 0.20)
		edge = Color(0.95, 0.32, 0.22, 0.50)
	elif state == "search":
		fill = Color(0.95, 0.76, 0.20, 0.18)
		edge = Color(0.95, 0.78, 0.25, 0.45)
	elif state == "stalk":
		fill = Color(0.80, 0.55, 0.95, 0.16)
		edge = Color(0.82, 0.58, 0.95, 0.44)
	var pts: PackedVector2Array = map.cast_vision(position, facing, deg_to_rad(vision_angle * 0.5), vision_range)
	if pts.size() >= 3:
		var local := PackedVector2Array()
		for p in pts:
			local.append(p - position)
		local.append(Vector2.ZERO)
		draw_colored_polygon(local, fill)
		draw_polyline(local, edge, 1.0)

## 开发者版：抓人判定圈（360°，半径远小于视锥）
func _draw_catch_circle() -> void:
	var col := Color(1.0, 0.35, 0.95, 0.45)
	if _in_catch_range():
		col = Color(1.0, 0.15, 0.25, 0.85)
	draw_arc(Vector2.ZERO, catch_radius, 0.0, TAU, 48, col, 1.5)

## 正式版：被盯上时只给一小截模糊弧，不暴露真实范围/角度。
func _should_show_watch_hint() -> bool:
	if not can_see:
		return false
	if GameState.warnings >= 1:
		return true
	return alert_level >= max_alert * 0.7

func _draw_watch_hint() -> void:
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	var col := Color(1.0, 0.58, 0.34, lerpf(0.30, 0.58, pulse))
	if state == "chase":
		col = Color(1.0, 0.24, 0.18, lerpf(0.45, 0.80, pulse))
	var dir := facing.angle()
	var half := deg_to_rad(38.0)
	draw_arc(Vector2.ZERO, 26.0, dir - half, dir + half, 24, col, 2.0)

func _process(delta: float) -> void:
	_update_visual(delta)
	queue_redraw()

func _update_visual(delta: float) -> void:
	if sprite == null:
		return
	var tex_list := _textures()
	if stun_timer > 0.0:
		sprite.texture = tex_list[6]
		sprite.flip_h = false
		sprite.modulate = Color(0.7, 0.7, 0.8)
		sprite.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.12
		sprite.position.y = 0.0
		return
	sprite.rotation = 0.0
	sprite.modulate = Color.WHITE
	if state == "chase":
		sprite.texture = tex_list[4]
		sprite.flip_h = facing.x < -0.01
	elif state == "search" or state == "stalk":
		sprite.texture = tex_list[5]
		sprite.flip_h = facing.x < -0.01
	else:
		sprite.flip_h = false
		if absf(facing.x) >= absf(facing.y):
			sprite.texture = tex_list[3] if facing.x > 0.0 else tex_list[2]
		else:
			sprite.texture = tex_list[0] if facing.y > 0.0 else tex_list[1]
	var moving := velocity.length() > 5.0
	if moving:
		bob_time += delta * 10.0
	else:
		bob_time = 0.0
	sprite.position.y = -absf(sin(bob_time)) * 1.5
