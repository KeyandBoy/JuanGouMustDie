extends CharacterBody2D

signal hit_player

const GUARD_TEX := [
	preload("res://art/sprites/64/20_guard_front.png"),
	preload("res://art/sprites/64/21_guard_back.png"),
	preload("res://art/sprites/64/22_guard_left.png"),
	preload("res://art/sprites/64/23_guard_right.png"),
	preload("res://art/sprites/64/30_guard_chase.png"),
	preload("res://art/sprites/64/31_guard_search.png"),
	preload("res://art/sprites/64/32_guard_stun.png"),
]

var map: Node2D
var player: Node2D
const CHASE_SPEED_MULT := 0.8
const ATTACK_RECOVER := 3.0

var level := 4
var sprite: Sprite2D
var tex_front: Texture2D
var tex_chase: Texture2D
var use_generated := false
var speed := 148.0
var idle_timer := 8.0
var attack_cd := 0.0
var recover_timer := 0.0
var slow_timer := 0.0
var slow_factor := 1.0
var stun_timer := 0.0
var aura_radius := 200.0
var facing := Vector2.DOWN
var bob_time := 0.0
var tutorial_driven := false
var path := PackedVector2Array()
var path_index := 0
var repath_timer := 0.0
var door_pause := 0.0
var pending_door: Node2D = null
var lure_pos := Vector2.INF
var lure_timer := 0.0
var footstep: AudioStreamPlayer2D
var heartbeat: AudioStreamPlayer2D
var roar_player: AudioStreamPlayer2D
var heart_timer := 0.0
var step_timer := 0.0
var fading := false
var smoke_back: Node2D
var smoke_front: Node2D
var smoke_script := preload("res://scripts/smoke_aura.gd")
var _sprite_base := Color(0.14, 0.05, 0.06, 1.0)

func _ready() -> void:
	add_to_group("tyrants")
	collision_layer = 2
	collision_mask = 1
	var ty_shape := CollisionShape2D.new()
	var ty_circle := CircleShape2D.new()
	ty_circle.radius = 16.0
	ty_shape.shape = ty_circle
	add_child(ty_shape)
	smoke_back = smoke_script.new()
	smoke_back.alpha = 0.5
	smoke_back.radius = 18.0
	smoke_back.puff = 7.0
	smoke_back.z_index = 1
	add_child(smoke_back)
	sprite = Sprite2D.new()
	tex_front = _load_art("res://art/sprites/tyrant/tyrant_front.png")
	tex_chase = _load_art("res://art/sprites/tyrant/tyrant_chase.png")
	use_generated = tex_front != null and tex_chase != null
	if use_generated:
		sprite.texture = tex_front
		var th := float(tex_front.get_height())
		sprite.scale = Vector2(0.24, 0.24)
		sprite.centered = true
		sprite.offset = Vector2(0.0, -th * 0.5)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.modulate = Color(1, 1, 1, 1)
		sprite.position = Vector2(0.0, 0.0)
	else:
		sprite.texture = GUARD_TEX[4]
		sprite.scale = Vector2(1.35, 1.55)
		sprite.position = Vector2(0.0, -8.0)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.modulate = _sprite_base
	sprite.z_index = 2
	add_child(sprite)
	smoke_front = smoke_script.new()
	smoke_front.alpha = 0.36
	smoke_front.radius = 12.0
	smoke_front.puff = 5.0
	smoke_front.speed = 1.5
	smoke_front.z_index = 3
	add_child(smoke_front)
	footstep = AudioStreamPlayer2D.new()
	footstep.max_distance = 1500.0
	footstep.attenuation = 1.6
	footstep.volume_db = 2.0
	var stream: AudioStream = load("res://assets/sfx/tyrant_step.wav")
	if stream != null:
		footstep.stream = stream
	add_child(footstep)
	heartbeat = AudioStreamPlayer2D.new()
	heartbeat.max_distance = 900.0
	heartbeat.attenuation = 1.2
	heartbeat.volume_db = -6.0
	var hb: AudioStream = load("res://assets/sfx/heartbeat.wav")
	if hb != null:
		heartbeat.stream = hb
	add_child(heartbeat)
	roar_player = AudioStreamPlayer2D.new()
	roar_player.max_distance = 2200.0
	roar_player.attenuation = 0.9
	roar_player.volume_db = 1.0
	var rr: AudioStream = load("res://assets/sfx/tyrant_roar.wav")
	if rr != null:
		roar_player.stream = rr
	add_child(roar_player)

func setup(p_map: Node2D, p_player: Node2D, p_level: int = 4) -> void:
	map = p_map
	player = p_player
	level = p_level
	speed = (148.0 if level <= 4 else 158.0) * CHASE_SPEED_MULT

func _physics_process(delta: float) -> void:
	if tutorial_driven:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if slow_timer > 0.0:
		slow_timer -= delta
		if slow_timer <= 0.0:
			slow_factor = 1.0
	if attack_cd > 0.0:
		attack_cd -= delta
	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if GameState.cutscene_active or (GameState.run_state != GameState.RunState.EXPLORING and GameState.run_state != GameState.RunState.QUIZ):
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if idle_timer > 0.0:
		idle_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if recover_timer > 0.0:
		recover_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if map == null or player == null:
		return
	if door_pause > 0.0:
		door_pause -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		if door_pause <= 0.0:
			_open_pending_door()
		return

	var target := player.position
	if lure_timer > 0.0:
		lure_timer -= delta
		target = lure_pos
	var dist := position.distance_to(player.position)
	if lure_timer <= 0.0 and dist < 30.0 and attack_cd <= 0.0 and not _player_dodging():
		_attack()
		move_and_slide()
		return

	repath_timer -= delta
	if repath_timer <= 0.0:
		repath_timer = 0.45
		path = map.find_path(position, target)
		path_index = 0
	_follow_path(speed * slow_factor)
	_update_footsteps(delta)
	_update_heartbeat(delta)
	if _try_door_ahead():
		move_and_slide()
		return
	move_and_slide()

func _attack() -> void:
	attack_cd = 3.5
	recover_timer = ATTACK_RECOVER
	slow_timer = 0.0
	slow_factor = 1.0
	if player.has_method("stun"):
		player.stun(1.5)
	player.velocity = Vector2.ZERO
	var swipe: AudioStream = load("res://assets/sfx/tyrant_swipe.wav")
	if swipe != null:
		var p := AudioStreamPlayer2D.new()
		p.stream = swipe
		p.max_distance = 900.0
		add_child(p)
		p.play()
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(p):
				p.queue_free()
		)
	hit_player.emit()

func _player_dodging() -> bool:
	if player == null:
		return false
	var d = player.get("dashing")
	return d != null and bool(d)

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

func _try_door_ahead() -> bool:
	if map == null or velocity.length() < 5.0:
		return false
	var best: Node2D = null
	var bd := 34.0
	for d in map.door_nodes:
		if not d.is_closed():
			continue
		var to_door: Vector2 = d.position - position
		var dist := to_door.length()
		if dist > bd or dist < 1.0:
			continue
		if facing.dot(to_door / dist) < 0.3:
			continue
		bd = dist
		best = d
	if best == null:
		return false
	pending_door = best
	door_pause = 0.35
	velocity = Vector2.ZERO
	return true

func _open_pending_door() -> void:
	if pending_door == null or not is_instance_valid(pending_door):
		pending_door = null
		return
	pending_door.set_open(true, true, position)
	pending_door = null

func _update_footsteps(delta: float) -> void:
	if footstep == null or footstep.stream == null:
		return
	step_timer -= delta
	if step_timer > 0.0:
		return
	var cadence := 0.62 if level <= 4 else 0.48
	step_timer = cadence * (1.0 / maxf(0.25, slow_factor))
	footstep.pitch_scale = 0.92 if level <= 4 else 1.02
	footstep.play()

func _update_heartbeat(delta: float) -> void:
	if heartbeat == null or heartbeat.stream == null or player == null:
		return
	var dist: float = position.distance_to(player.position)
	if dist > 460.0:
		heart_timer = 0.0
		return
	heart_timer -= delta
	if heart_timer > 0.0:
		return
	heart_timer = clampf(dist / 460.0, 0.35, 1.0) * 1.1
	heartbeat.play()

func _process(delta: float) -> void:
	if sprite == null or fading:
		return
	var moving := velocity.length() > 5.0
	if use_generated:
		if stun_timer > 0.0:
			sprite.texture = tex_front
			sprite.modulate = Color(0.62, 0.55, 0.55, 0.85)
		elif moving:
			bob_time += delta * 7.0
			sprite.texture = tex_chase
			sprite.modulate = Color(1, 1, 1, 1)
		else:
			sprite.texture = tex_front
			sprite.modulate = Color(1, 1, 1, 1)
		sprite.flip_h = velocity.x < -1.0
		sprite.position.y = -absf(sin(bob_time)) * 3.0
		return
	var _moving := velocity.length() > 5.0
	if stun_timer > 0.0:
		sprite.texture = GUARD_TEX[6]
		sprite.modulate = Color(0.55, 0.45, 0.45, 0.8)
		return
	sprite.modulate = _sprite_base
	if _moving:
		bob_time += delta * 7.0
		sprite.texture = GUARD_TEX[4]
	else:
		sprite.texture = GUARD_TEX[0]
	sprite.flip_h = velocity.x < -1.0
	sprite.position.y = -8.0 - absf(sin(bob_time)) * 3.0

func aura_factor() -> float:
	if player == null:
		return 1.0
	return 0.7 if position.distance_to(player.position) <= aura_radius else 1.0

func on_barricade() -> void:
	slow_timer = 3.0
	slow_factor = 0.6
	recover_timer = maxf(recover_timer, 0.3)

func smoke_slow(dur: float = 3.5) -> void:
	slow_timer = maxf(slow_timer, dur)
	slow_factor = 0.5

func stun_tyrant(t: float) -> void:
	stun_timer = maxf(stun_timer, t)
	path = PackedVector2Array()
	path_index = 0

func lure_to(pos: Vector2, dur: float = 5.0) -> void:
	lure_pos = pos
	lure_timer = dur
	path = PackedVector2Array()
	path_index = 0

func roar() -> void:
	if roar_player != null and roar_player.stream != null:
		roar_player.play()

func _load_art(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var t = load(path)
	return t if t is Texture2D else null

func fade_out() -> void:
	fading = true
	velocity = Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 1.0)
