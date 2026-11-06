extends Node2D

const SMOKE_SHADER := preload("res://shaders/fog_smoke.gdshader")

var map: Node2D
var player: Node2D
var halo: ColorRect

## 探索三态遮罩（按「整间房 / 整段走廊」为单位，不是按半径）：
##   未探索        → 纯黑（只留门框和墙）
##   已探索、人不在 → 压暗（轮廓和家具还在，像记忆里的房间）
##   当前所在      → 不遮，整间均匀亮
const MASK_BLACK := Color(0.010, 0.012, 0.018, 1.0)
const MASK_DIM := Color(0.024, 0.028, 0.040, 1.0)
const DIM_ALPHA := 0.58

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
var _halo_dark := false

var _expl_version := -1
var _zone := "__none__"
var _ov_nodes: Array[ColorRect] = []
var _ov_zones: Array[String] = []
var _ov_black: Array[bool] = []

var ambient: ColorRect
var ambient_density := 0.0
var ambient_target := 0.0
var flicker: ColorRect
var flicker_timer := 0.0
var tutorial_mode := false

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

## 重建探索遮罩（旧名字保留，main.gd 换层时会调）。
func reset_forget() -> void:
	_expl_version = -1
	_zone = "__none__"
	for n in _ov_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_ov_nodes.clear()
	_ov_zones.clear()
	_ov_black.clear()

func set_tyrant_active(active: bool, level: int) -> void:
	ambient_target = 0.0
	if active:
		ambient_target = 0.44 if level >= 5 else 0.32
	if ambient != null:
		ambient.visible = active or ambient_density > 0.01

func _process(delta: float) -> void:
	if tutorial_mode:
		if halo != null:
			halo.visible = false
		if ambient != null:
			ambient.visible = false
		_hide_masks()
		return
	_refresh_masks()
	_apply_halo()
	_update_ambient(delta)
	_update_flicker(delta)
	if player == null or not is_instance_valid(player):
		if halo != null:
			halo.visible = false
		return
	# 手电光晕只在「停电 / 低能见度」事件里开；平时整间均匀亮，不做主角周围光晕
	var dark: bool = GameState.dark_vision
	if halo != null:
		halo.visible = dark
		var mat := halo.material as ShaderMaterial
		if not dark:
			mat.set_shader_parameter("cone_on", 0.0)
		else:
			var vs: Vector2 = get_viewport().get_visible_rect().size
			mat.set_shader_parameter("resolution", vs)
			mat.set_shader_parameter("center", player.get_global_transform_with_canvas().origin / vs)
			mat.set_shader_parameter("cone_on", 1.0)
			var fd = player.get("face_dir")
			if fd is Vector2:
				var v: Vector2 = fd
				if v.length_squared() > 0.001:
					mat.set_shader_parameter("cone_dir", v.normalized())
			mat.set_shader_parameter("cone_length", 260.0)
			mat.set_shader_parameter("cone_half_angle", 0.42)

func _refresh_masks() -> void:
	if map == null or not is_instance_valid(map):
		return
	var ver := int(map.get("exploration_version"))
	var zn := ""
	if player != null and is_instance_valid(player) and map.has_method("current_zone_at"):
		zn = map.current_zone_at(player.position)
		if zn == "":
			zn = _nearest_zone(map, player.position)
	if ver == _expl_version and zn == _zone:
		return
	_expl_version = ver
	_zone = zn
	_rebuild_masks()

func _rebuild_masks() -> void:
	for n in _ov_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_ov_nodes.clear()
	_ov_zones.clear()
	_ov_black.clear()
	if map == null:
		return
	var rooms: Array = map.rooms
	for i in rooms.size():
		_add_mask(rooms[i], "r%d" % i, not bool(map.explored[i]))
	var segs: Array = map.corridor_segments
	var cex: Array = map.corridor_explored
	for i in segs.size():
		var seen: bool = i < cex.size() and bool(cex[i])
		_add_mask(segs[i], "c%d" % i, not seen)

func _add_mask(rect: Rect2, zone: String, black: bool) -> void:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.color = MASK_BLACK if black else Color(MASK_DIM.r, MASK_DIM.g, MASK_DIM.b, DIM_ALPHA)
	r.visible = zone != _zone
	add_child(r)
	_ov_nodes.append(r)
	_ov_zones.append(zone)
	_ov_black.append(black)

func _hide_masks() -> void:
	for n in _ov_nodes:
		if is_instance_valid(n):
			n.visible = false

## 没落在任何矩形里（门缝、墙体缺口）时，取边缘最近的那块，避免闪黑。
func _nearest_zone(p_map: Node2D, pos: Vector2) -> String:
	var best := ""
	var bd := INF
	for i in p_map.rooms.size():
		var d := _rect_dist(p_map.rooms[i], pos)
		if d < bd:
			bd = d
			best = "r%d" % i
	for i in p_map.corridor_segments.size():
		var d := _rect_dist(p_map.corridor_segments[i], pos)
		if d < bd:
			bd = d
			best = "c%d" % i
	return best

func _rect_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dy := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)

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
	var dark: bool = GameState.dark_vision
	if lv == _halo_level and dark == _halo_dark and _halo_level >= 0:
		return
	_halo_level = lv
	_halo_dark = dark
	var r: Vector2 = HALO_BY_LEVEL[lv]
	var mul := 0.55 if dark else 1.0
	halo_clear = r.x * mul
	halo_fade = r.y * (0.62 if dark else 1.0)
	if halo != null:
		var mat := halo.material as ShaderMaterial
		mat.set_shader_parameter("clear_radius", halo_clear)
		mat.set_shader_parameter("fade_radius", halo_fade)
		mat.set_shader_parameter("max_alpha", 0.985 if dark else 0.96)
