extends Node2D

const SMOKE_SHADER := preload("res://shaders/fog_smoke.gdshader")

var map: Node2D
var player: Node2D
var halo: ColorRect

var forget_after := 30.0
var forget_ramp := 5.0
var forget_clear_time := 1.5
var forget_max_alpha := 0.55
var forget_color := Color(0.42, 0.44, 0.47)

const HALO_BY_LEVEL := {
	1: Vector2(160.0, 300.0),
	2: Vector2(145.0, 275.0),
	3: Vector2(130.0, 250.0),
	4: Vector2(115.0, 225.0),
	5: Vector2(100.0, 200.0),
}

var halo_clear := 160.0
var halo_fade := 300.0
var _halo_level := -1

var _forget: Array[float] = []
var _away: Array[float] = []
var _inside := -1
var _smoke: Array[ColorRect] = []
var ambient: ColorRect
var ambient_density := 0.0
var ambient_target := 0.0
var flicker: ColorRect
var flicker_timer := 0.0

func _ready() -> void:
	z_index = 50
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	halo = ColorRect.new()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/fog.gdshader")
	halo.material = mat
	halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(halo)

	var ambient_layer := CanvasLayer.new()
	ambient_layer.layer = 4
	add_child(ambient_layer)
	ambient = ColorRect.new()
	var amat := ShaderMaterial.new()
	amat.shader = SMOKE_SHADER
	amat.set_shader_parameter("seed", 47.0)
	amat.set_shader_parameter("density", 0.0)
	amat.set_shader_parameter("wisp", 0.75)
	amat.set_shader_parameter("fog_color", Color(0.10, 0.10, 0.12, 1.0))
	ambient.material = amat
	ambient.set_anchors_preset(Control.PRESET_FULL_RECT)
	ambient.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ambient.visible = false
	ambient_layer.add_child(ambient)

	flicker = ColorRect.new()
	flicker.color = Color(0.0, 0.0, 0.02, 0.0)
	flicker.set_anchors_preset(Control.PRESET_FULL_RECT)
	flicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ambient_layer.add_child(flicker)

func setup(p_map: Node2D, p_player: Node2D) -> void:
	map = p_map
	player = p_player
	reset_forget()

func reset_forget() -> void:
	_forget.clear()
	_away.clear()
	_inside = -1
	if map != null:
		for i in map.rooms.size():
			_forget.append(0.0)
			_away.append(0.0)
	_rebuild_smoke()

func forget_amount(index: int) -> float:
	if index < 0 or index >= _forget.size():
		return 0.0
	return _forget[index]

func set_tyrant_active(active: bool, level: int) -> void:
	ambient_target = 0.0
	if active:
		ambient_target = 0.44 if level >= 5 else 0.32
	if ambient != null:
		ambient.visible = active or ambient_density > 0.01

func _process(delta: float) -> void:
	_update_forget(delta)
	_apply_halo()
	_update_ambient(delta)
	_update_flicker(delta)
	if player == null or not is_instance_valid(player):
		if halo != null:
			halo.visible = false
		return
	if halo != null:
		halo.visible = true
		var mat := halo.material as ShaderMaterial
		var vs: Vector2 = get_viewport().get_visible_rect().size
		mat.set_shader_parameter("resolution", vs)
		mat.set_shader_parameter("center", player.get_global_transform_with_canvas().origin / vs)

func _update_forget(delta: float) -> void:
	if map == null or player == null or not is_instance_valid(player):
		return
	if _forget.size() != map.rooms.size():
		reset_forget()
	_inside = map.room_index_at(player.position)
	var enabled: bool = GameState.level >= 2
	for i in map.rooms.size():
		if not enabled or not _is_forgettable(i):
			_away[i] = 0.0
			_forget[i] = maxf(0.0, _forget[i] - delta / forget_clear_time)
			continue
		if i == _inside:
			_away[i] = 0.0
			_forget[i] = maxf(0.0, _forget[i] - delta / forget_clear_time)
		elif map.explored[i]:
			_away[i] += delta
			_forget[i] = clampf((_away[i] - forget_after) / forget_ramp, 0.0, 1.0)
		else:
			_away[i] = 0.0
			_forget[i] = 0.0
	_update_smoke()

func _rebuild_smoke() -> void:
	for node in _smoke:
		node.queue_free()
	_smoke.clear()
	if map == null:
		return
	for i in map.rooms.size():
		var r: Rect2 = map.rooms[i]
		var rect := ColorRect.new()
		rect.position = r.position
		rect.size = r.size
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = SMOKE_SHADER
		mat.set_shader_parameter("seed", float(i) * 13.7 + 2.0)
		mat.set_shader_parameter("room_size", r.size)
		rect.material = mat
		rect.visible = false
		add_child(rect)
		_smoke.append(rect)

func _update_smoke() -> void:
	if map == null or _smoke.size() != map.rooms.size():
		return
	for i in map.rooms.size():
		var rect := _smoke[i]
		var mat := rect.material as ShaderMaterial
		if not map.explored[i]:
			rect.visible = true
			mat.set_shader_parameter("solid", 1.0)
			mat.set_shader_parameter("density", 1.0)
			mat.set_shader_parameter("wisp", 0.0)
			mat.set_shader_parameter("fog_color", Color(0.02, 0.02, 0.03, 1.0))
		elif i < _forget.size() and _forget[i] > 0.02:
			rect.visible = true
			mat.set_shader_parameter("solid", 0.0)
			mat.set_shader_parameter("density", forget_max_alpha * 1.2 * _forget[i])
			mat.set_shader_parameter("wisp", 0.65)
			mat.set_shader_parameter("fog_color", Color(0.47, 0.48, 0.5, 1.0))
		else:
			rect.visible = false

func _update_flicker(delta: float) -> void:
	if flicker == null:
		return
	if GameState.level < 5:
		flicker.color.a = 0.0
		return
	flicker_timer -= delta
	if flicker_timer <= 0.0:
		flicker_timer = randf_range(0.05, 0.5)
		flicker.color.a = 0.0 if randf() < 0.45 else randf_range(0.2, 0.5)
	else:
		flicker.color.a = move_toward(flicker.color.a, 0.0, delta * 1.6)

func _update_ambient(delta: float) -> void:
	if ambient == null:
		return
	var spd := 0.35 if ambient_target > ambient_density else 0.22
	ambient_density = move_toward(ambient_density, ambient_target, spd * delta)
	if ambient_density <= 0.005 and ambient_target <= 0.0:
		ambient_density = 0.0
		ambient.visible = false
		return
	ambient.visible = true
	var mat := ambient.material as ShaderMaterial
	var vs: Vector2 = get_viewport().get_visible_rect().size
	mat.set_shader_parameter("room_size", vs)
	mat.set_shader_parameter("density", ambient_density)

func _apply_halo() -> void:
	var lv: int = clampi(GameState.level, 1, 5)
	if lv == _halo_level:
		return
	_halo_level = lv
	var r: Vector2 = HALO_BY_LEVEL[lv]
	halo_clear = r.x
	halo_fade = r.y
	if halo != null:
		var mat := halo.material as ShaderMaterial
		mat.set_shader_parameter("clear_radius", halo_clear)
		mat.set_shader_parameter("fade_radius", halo_fade)

func _is_forgettable(index: int) -> bool:
	if index < 0 or index >= map.room_types.size():
		return false
	var t: String = String(map.room_types[index])
	return t != "hall" and t != "stair" and t != "corridor"
