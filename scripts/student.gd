extends CharacterBody2D

const ShadowScript := preload("res://scripts/shadow.gd")
const EyeGlowScript := preload("res://scripts/eye_glow.gd")

# 角色贴图：由 tools/chargen_compose.py 从 CharGen(LPC) 素材合成
# 每个角色 4 方向行走条带（64x64 x 8 帧），顺序：front / back / left / right
const ROLE_TEX := {
	"juan": [
		preload("res://art/sprites/lpc/juan_walk_front.png"),
		preload("res://art/sprites/lpc/juan_walk_back.png"),
		preload("res://art/sprites/lpc/juan_walk_left.png"),
		preload("res://art/sprites/lpc/juan_walk_right.png"),
	],
	"student": [
		preload("res://art/sprites/lpc/student_walk_front.png"),
		preload("res://art/sprites/lpc/student_walk_back.png"),
		preload("res://art/sprites/lpc/student_walk_left.png"),
		preload("res://art/sprites/lpc/student_walk_right.png"),
	],
	"teacher": [
		preload("res://art/sprites/lpc/teacher_walk_front.png"),
		preload("res://art/sprites/lpc/teacher_walk_back.png"),
		preload("res://art/sprites/lpc/teacher_walk_left.png"),
		preload("res://art/sprites/lpc/teacher_walk_right.png"),
	],
	"guard": [
		preload("res://art/sprites/lpc/guard_walk_front.png"),
		preload("res://art/sprites/lpc/guard_walk_back.png"),
		preload("res://art/sprites/lpc/guard_walk_left.png"),
		preload("res://art/sprites/lpc/guard_walk_right.png"),
	],
	# 怪物（tools/monster_dirs.py 从单张正面图生成 4 方向 × 4 帧）
	"skeleton": [
		preload("res://art/sprites/monsters/skeleton_walk_front.png"),
		preload("res://art/sprites/monsters/skeleton_walk_back.png"),
		preload("res://art/sprites/monsters/skeleton_walk_left.png"),
		preload("res://art/sprites/monsters/skeleton_walk_right.png"),
	],
	"zombie": [
		preload("res://art/sprites/monsters/zombie_walk_front.png"),
		preload("res://art/sprites/monsters/zombie_walk_back.png"),
		preload("res://art/sprites/monsters/zombie_walk_left.png"),
		preload("res://art/sprites/monsters/zombie_walk_right.png"),
	],
	"puppet": [
		preload("res://art/sprites/monsters/puppet_walk_front.png"),
		preload("res://art/sprites/monsters/puppet_walk_back.png"),
		preload("res://art/sprites/monsters/puppet_walk_left.png"),
		preload("res://art/sprites/monsters/puppet_walk_right.png"),
	],
	"minotaur": [
		preload("res://art/sprites/monsters/minotaur_walk_front.png"),
		preload("res://art/sprites/monsters/minotaur_walk_back.png"),
		preload("res://art/sprites/monsters/minotaur_walk_left.png"),
		preload("res://art/sprites/monsters/minotaur_walk_right.png"),
	],
	# 20 只随机怪物（运行时按 monster_variant 载入，不 preload）
	"grotesque": [],
	# 15 只史莱姆（5 色 × 人形/混合/团状，运行时按 slime_variant 载入）
	"slime": [],
}
const MONSTER_PACK_COUNT := 20
const SLIME_COUNT := 15
## 每个角色的条带帧数（学生 8 帧，怪物 4 帧）
const ROLE_FRAMES := {
	"skeleton": 4, "zombie": 4, "puppet": 4, "minotaur": 4, "grotesque": 4, "slime": 4,
}
## 每个角色的绘制缩放（怪物体型差异）
const ROLE_SCALE := {
	"skeleton": 0.72, "zombie": 0.86, "puppet": 0.74, "minotaur": 0.95, "grotesque": 0.62, "slime": 1.35,
}
## 每个角色相对基础值的速度 / 视野 / 抓人半径倍率
const ROLE_STATS := {
	"skeleton": {"speed": 1.10, "vision": 1.00, "catch": 1.0},
	"zombie":   {"speed": 0.82, "vision": 1.10, "catch": 1.2},
	"puppet":   {"speed": 0.95, "vision": 1.20, "catch": 1.0},
	"minotaur": {"speed": 0.86, "vision": 1.25, "catch": 1.35},
	"grotesque": {"speed": 0.92, "vision": 1.10, "catch": 1.1},
	"slime":    {"speed": 0.75, "vision": 0.95, "catch": 0.9},
}
const WALK_FRAMES := 8
const WALK_FPS := 9.5
const VISUAL_SCALE := 0.78

var role := "juan"
var sprite: Sprite2D
var shadow
var eye: PointLight2D
## grotesque 角色用：1..20 选一只随机怪物
var monster_variant := 1
var _pack_tex := {}
## slime 角色用：1..15 选一只史莱姆
var slime_variant := 1
var _slime_tex := {}
var bob_time := 0.0
var anim_time := 0.0
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
var think_timer := 0.0
var level_speed_mult := 1.0
var level_vision_mult := 1.0
const THINK_INTERVAL := 0.3

func _ready() -> void:
	add_to_group("students")
	# B4：和学生贴图同一套椭圆影子
	shadow = ShadowScript.new()
	shadow.setup(Vector2(14.0, 5.0), Vector2(0.0, 23.5), 0.38)
	add_child(shadow)
	# B12：追击 / 搜寻 / 潜行时眼睛亮红；平时不亮
	eye = EyeGlowScript.new()
	eye.position = Vector2(0.0, -12.0)
	eye.dot_scale = 0.22
	add_child(eye)
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 1
	add_child(sprite)
	_apply_role_visuals()

func set_role(p_role: String) -> void:
	if p_role in ROLE_TEX:
		role = p_role
	else:
		role = "student"
	_apply_role_visuals()

## 角色外观：贴图 / 缩放 / 影子大小与落点 / 红眼高度，都按角色重新算一次。
func _apply_role_visuals() -> void:
	if sprite == null:
		return
	var s := _scale()
	sprite.texture = _textures()[0]
	sprite.scale = Vector2(s, s)
	var k := s / VISUAL_SCALE
	if shadow != null:
		var feet := (sprite.texture.get_height() * 0.5 - 2.0) * s
		shadow.setup(Vector2(14.0 * k, 5.0 * k), Vector2(0.0, feet), 0.38)
	if eye != null:
		eye.position = Vector2(0.0, -12.0 * k)

func _frames() -> int:
	return int(ROLE_FRAMES.get(role, WALK_FRAMES))

func _scale() -> float:
	return float(ROLE_SCALE.get(role, VISUAL_SCALE))

func _role_stats() -> Dictionary:
	return ROLE_STATS.get(role, {})

func _textures() -> Array:
	if role == "grotesque":
		return _grotesque_textures()
	if role == "slime":
		return _slime_textures()
	return ROLE_TEX.get(role, ROLE_TEX["juan"])

## 20 只随机怪物：按 monster_variant 惰性载入（每只 4 方向条带）。
func _grotesque_textures() -> Array:
	var idx := clampi(monster_variant, 1, MONSTER_PACK_COUNT)
	if _pack_tex.has(idx):
		return _pack_tex[idx]
	var arr: Array = []
	for d in ["front", "back", "left", "right"]:
		arr.append(load("res://art/sprites/monsters/pack_%02d_walk_%s.png" % [idx, d]))
	_pack_tex[idx] = arr
	return arr

## 15 只史莱姆：5 色 × 3 形态，按 slime_variant 惰性载入。
func _slime_textures() -> Array:
	var idx := clampi(slime_variant, 1, SLIME_COUNT)
	if _slime_tex.has(idx):
		return _slime_tex[idx]
	var arr: Array = []
	for d in ["front", "back", "left", "right"]:
		arr.append(load("res://art/sprites/monsters/slime_%02d_walk_%s.png" % [idx, d]))
	_slime_tex[idx] = arr
	return arr

func setup(p_map: Node2D, p_player: Node2D) -> void:
	map = p_map
	player = p_player
	last_seen = position
	_apply_level_scale()

## F8：按楼层缩放感知与移速（教学关不缩放）。
func _apply_level_scale() -> void:
	if GameState.tutorial_active:
		var st0 := _role_stats()
		if not st0.is_empty():
			_apply_role_stats(st0)
		return
	var lv := maxi(1, GameState.level)
	level_vision_mult = 1.0 + 0.08 * float(lv - 1)
	level_speed_mult = 1.0 + 0.05 * float(lv - 1)
	vision_range = 160.0 * level_vision_mult
	speed = 80.0 * level_speed_mult
	chase_speed = 140.0 * level_speed_mult
	var st := _role_stats()
	if not st.is_empty():
		_apply_role_stats(st)

## 怪物相对学生的体型/性格差异：速度、视野、抓人圈。
func _apply_role_stats(st: Dictionary) -> void:
	speed *= float(st.get("speed", 1.0))
	chase_speed *= float(st.get("speed", 1.0))
	vision_range *= float(st.get("vision", 1.0))
	catch_radius *= float(st.get("catch", 1.0))

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
			speed = 80.0 * level_speed_mult / m
			chase_speed = 140.0 * level_speed_mult / m
			vision_range = 160.0 * level_vision_mult / m
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

	think_timer -= delta
	if think_timer <= 0.0:
		think_timer = THINK_INTERVAL
		_decide(THINK_INTERVAL)

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


## F1：低频决策。视野/警觉/状态切换每 0.3s 才结算一次，移动仍逐帧。
func _decide(dt: float) -> void:
	var to_player: Vector2 = player.position - position
	var dist: float = to_player.length()
	can_see = _can_see_player(to_player, dist)
	if can_see:
		alert_level = minf(max_alert, alert_level + dt * (55.0 + (1.0 - clampf(dist / vision_range, 0.0, 1.0)) * 75.0))
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
		alert_level = maxf(0.0, alert_level - dt * 35.0)

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
	speed = 80.0 * level_speed_mult * m
	chase_speed = 140.0 * level_speed_mult * m
	vision_range = 160.0 * level_vision_mult * m
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
	# 4 方向行走条带：front / back / left / right
	var dir_idx := 0
	if absf(facing.x) >= absf(facing.y):
		dir_idx = 3 if facing.x > 0.0 else 2
	else:
		dir_idx = 0 if facing.y >= 0.0 else 1
	sprite.flip_h = false
	if stun_timer > 0.0:
		sprite.texture = tex_list[dir_idx]
		sprite.hframes = _frames()
		sprite.vframes = 1
		sprite.frame = 0
		sprite.modulate = Color(0.7, 0.7, 0.8)
		sprite.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.12
		sprite.position.y = 0.0
		return
	sprite.rotation = 0.0
	# 状态着色：追击偏红、搜寻/潜行偏黄，保持和玩家同一套模型
	if state == "chase":
		sprite.modulate = Color(1.0, 0.74, 0.72)
	elif state == "search" or state == "stalk":
		sprite.modulate = Color(1.0, 0.90, 0.62)
	else:
		sprite.modulate = Color.WHITE
	sprite.texture = tex_list[dir_idx]
	sprite.hframes = _frames()
	sprite.vframes = 1
	var moving := velocity.length() > 5.0
	if moving:
		anim_time += delta * (WALK_FPS * 1.35 if state == "chase" else WALK_FPS)
		sprite.frame = int(anim_time) % _frames()
		bob_time += delta * 10.0
	else:
		anim_time = 0.0
		sprite.frame = 0
		bob_time = 0.0
	sprite.position.y = -absf(sin(bob_time)) * 1.5
