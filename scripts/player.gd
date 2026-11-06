extends CharacterBody2D

signal interacted

const ShadowScript := preload("res://scripts/shadow.gd")
const TorchScript := preload("res://scripts/torch_light.gd")

const TEX_FRONT := preload("res://art/sprites/64/01_player_front.png")
const TEX_BACK := preload("res://art/sprites/64/02_player_back.png")
const TEX_LEFT := preload("res://art/sprites/64/03_player_left.png")
const TEX_RIGHT := preload("res://art/sprites/64/04_player_right.png")

# 走路循环：每个方向一条横向条带，64x64 x 8 帧（AI 逐帧生成，解剖结构正确）
# 冲刺直接复用走路帧、提高播放速度；不再使用旧版剪切派生的 4 帧跑条带（会撕裂出第三条腿）。
const WALK_FRAMES := 8
const TEX_WALK_FRONT := preload("res://art/sprites/64/anim/player_walk_front.png")
const TEX_WALK_BACK := preload("res://art/sprites/64/anim/player_walk_back.png")
const TEX_WALK_LEFT := preload("res://art/sprites/64/anim/player_walk_left.png")
const TEX_WALK_RIGHT := preload("res://art/sprites/64/anim/player_walk_right.png")

const WALK_FPS := 11.0
const RUN_FPS := 18.0
const VISUAL_SCALE := 0.7

var speed_walk := 160.0
var speed_sprint := 260.0
var speed_dash := 300.0
var can_move := true
var stun_timer := 0.0
var face_dir := Vector2.DOWN
var bob_time := 0.0
var anim_time := 0.0
var sprite: Sprite2D
var torch: PointLight2D
var dashing := false
var speed_buff_timer := 0.0
var speed_buff_mult := 1.0
var passive_speed_mult := 1.0
var noise_mult := 1.0
var dash_charge_mult := 1.0
var dash_drain_from := 0.0

const DASH_CHARGE_RATE := 100.0 / 15.0
const DASH_DRAIN_RATE := 100.0 / 3.0

func _ready() -> void:
	add_to_group("player")
	# B4：统一椭圆影子，位置按贴图内容底部稍往下，避免被脚完全盖住
	var shadow = ShadowScript.new()
	shadow.setup(Vector2(14.0, 5.0), Vector2(0.0, 21.5), 0.40)
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.texture = TEX_WALK_FRONT
	sprite.hframes = WALK_FRAMES
	sprite.frame = 0
	sprite.scale = Vector2(VISUAL_SCALE, VISUAL_SCALE)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.z_index = 1
	add_child(sprite)
	# B12：手电光锥。挂在角色脚下略前，随 face_dir 旋转
	torch = TorchScript.new()
	torch.position = Vector2(0.0, -2.0)
	add_child(torch)
	torch.set_facing(face_dir)


func _physics_process(delta: float) -> void:
	if stun_timer > 0.0:
		stun_timer -= delta
		dashing = false
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not can_move or GameState.run_state != GameState.RunState.EXPLORING:
		dashing = false
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_update_dash(delta)
	if speed_buff_timer > 0.0:
		speed_buff_timer = maxf(0.0, speed_buff_timer - delta)
		if speed_buff_timer <= 0.0:
			speed_buff_mult = 1.0
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var spd := speed_dash if dashing else speed_walk * speed_buff_mult * passive_speed_mult
	if dashing:
		spd = speed_dash
	velocity = dir * spd
	if dashing and dir.length() > 0.1:
		GameState.damage_emptiness(delta * 1.5)
	move_and_slide()

func _update_dash(delta: float) -> void:
	if dashing:
		var floor_e := maxf(0.0, dash_drain_from - GameState.DASH_MAX)
		var next := GameState.dash_energy - DASH_DRAIN_RATE * delta
		if next <= floor_e:
			GameState.dash_energy = floor_e
			dashing = false
		else:
			GameState.dash_energy = next
		return
	var before := GameState.dash_energy
	var max_e := GameState.dash_max_value()
	if before < max_e:
		GameState.dash_energy = minf(max_e, before + DASH_CHARGE_RATE * dash_charge_mult * delta)
	var just_full := before < max_e and GameState.dash_energy >= max_e
	if Input.is_action_just_pressed("sprint") or (just_full and Input.is_action_pressed("sprint")):
		_start_dash()

func _start_dash() -> void:
	if dashing or GameState.dash_energy < GameState.DASH_MAX:
		return
	dash_drain_from = GameState.dash_energy
	dashing = true

func is_dashing() -> bool:
	return dashing

func is_dodging() -> bool:
	return dashing and stun_timer <= 0.0

func stun(t: float) -> void:
	stun_timer = t
	dashing = false

func apply_speed_buff(mult: float, duration: float) -> void:
	speed_buff_mult = mult
	speed_buff_timer = duration

func clear_item_buffs() -> void:
	speed_buff_mult = 1.0
	speed_buff_timer = 0.0
	noise_mult = 1.0
	passive_speed_mult = 1.0
	dash_charge_mult = 1.0

func _process(delta: float) -> void:
	if torch != null:
		torch.set_active(GameState.dark_vision)
	if sprite == null:
		return
	if stun_timer > 0.0:
		sprite.modulate = Color(0.65, 0.65, 0.75)
		sprite.rotation = sin(Time.get_ticks_msec() * 0.02) * 0.12
		sprite.position.y = 0.0
		anim_time = 0.0
		_apply_frame(false)
		return
	sprite.rotation = 0.0
	sprite.modulate = Color.WHITE
	if dashing:
		sprite.modulate = Color(0.55, 0.92, 1.0, 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.06))
	var moving := velocity.length() > 5.0
	if moving:
		face_dir = _dominant_dir(velocity)
		if torch != null:
			torch.set_facing(face_dir)
		anim_time += delta * (RUN_FPS if dashing else WALK_FPS)
	else:
		anim_time = 0.0
	_apply_frame(moving and dashing)
	sprite.position.y = 0.0

# 按当前朝向贴帧：所有状态共用走路循环（冲刺只是播放更快）
func _apply_frame(_running: bool) -> void:
	var tex: Texture2D = _walk_texture_for(face_dir)
	if sprite.texture != tex:
		sprite.texture = tex
		sprite.hframes = WALK_FRAMES
		sprite.vframes = 1
	var f := int(anim_time) % WALK_FRAMES
	if f < 0:
		f = 0
	sprite.frame = f

func _walk_texture_for(dir: Vector2) -> Texture2D:
	if absf(dir.x) >= absf(dir.y):
		return TEX_WALK_RIGHT if dir.x > 0.0 else TEX_WALK_LEFT
	return TEX_WALK_FRONT if dir.y > 0.0 else TEX_WALK_BACK

func _dominant_dir(v: Vector2) -> Vector2:
	if absf(v.x) >= absf(v.y):
		return Vector2.RIGHT if v.x > 0.0 else Vector2.LEFT
	return Vector2.DOWN if v.y > 0.0 else Vector2.UP

func _texture_for(dir: Vector2) -> Texture2D:
	if absf(dir.x) >= absf(dir.y):
		return TEX_RIGHT if dir.x > 0.0 else TEX_LEFT
	return TEX_FRONT if dir.y > 0.0 else TEX_BACK

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interacted.emit()
