extends Node2D

const SMOKE_SHADER := preload("res://shaders/fog_smoke.gdshader")
const MASK_SHADER := preload("res://shaders/fog_mask_soft.gdshader")

const CELL := 20.0

var map: Node2D
var player: Node2D
var halo: ColorRect

## 探索三态（按「整间房 / 整段走廊」为单位）：
##   未探索        → 很暗（但仍能看出地面/家具轮廓，不是一块死黑）
##   已探索、人不在 → 压暗（像记忆里的房间）
##   当前所在      → 不遮
## 三态之间不是硬切：整张图按「每格 1 像素」烘一张遮罩纹理，
## 再用模糊着色器 + 线性过滤把边界糊成柔和光晕（所以不会出现方块边）。
const MASK_COLOR := Color(0.035, 0.042, 0.058)
const UNEXPLORED_ALPHA := 0.86
const DIM_ALPHA := 0.46

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
var _mask: Sprite2D
## zone -> 该区域的遮罩 alpha（0=当前区域，DIM=已探索，UNEXPLORED=未探索），测试会读它
var _zone_alpha: Dictionary = {}

var ambient: ColorRect
var ambient_density := 0.0
var ambient_target := 0.0
var flicker: ColorRect
var flicker_timer := 0.0
var tutorial_mode := false

func _ready() -> void:
	z_index = 50
	_mask = Sprite2D.new()
	_mask.name = "ExploreMask"
	_mask.centered = false
	_mask.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mmat := ShaderMaterial.new()
	mmat.shader = MASK_SHADER
	_mask.material = mmat
	add_child(_mask)

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
	_zone_alpha.clear()
	if _mask != null:
		_mask.texture = null
		_mask.visible = false

## 某个区域当前的遮罩 alpha（测试用）：0=当前区域，0.46=已探索，0.86=未探索，-1=未知区域。
func zone_alpha(zone: String) -> float:
	if _zone_alpha.has(zone):
		return float(_zone_alpha[zone])
	return -1.0

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
	_rebuild_mask()

## 把「每格的三态 alpha」烘成一张小纹理，再放大铺满地图（模糊交给着色器）。
func _rebuild_mask() -> void:
	if map == null or _mask == null:
		return
	var gw := int(map.gw)
	var gh := int(map.gh)
	if gw <= 0 or gh <= 0:
		return
	var img := Image.create(gw, gh, false, Image.FORMAT_RGBA8)
	img.fill(_col(UNEXPLORED_ALPHA))
	_zone_alpha.clear()

	for i in map.rooms.size():
		var zone := "r%d" % i
		var a := DIM_ALPHA if bool(map.explored[i]) else UNEXPLORED_ALPHA
		if zone == _zone:
			a = 0.0
		_zone_alpha[zone] = a
		_fill_cells(img, map.rooms[i], a)

	var segs: Array = map.corridor_segments
	var cex: Array = map.corridor_explored
	for i in segs.size():
		var zone := "c%d" % i
		var seen: bool = i < cex.size() and bool(cex[i])
		var a := DIM_ALPHA if seen else UNEXPLORED_ALPHA
		if zone == _zone:
			a = 0.0
		_zone_alpha[zone] = a
		_fill_cells(img, segs[i], a)

	# 环路门洞：单独一档，站在里面只亮门洞本身，不泄露两边房间
	var prects: Array = map.passage_rects
	for i in prects.size():
		var zone := "p%d" % i
		var seen: bool = bool(map.passage_seen(i))
		var a := DIM_ALPHA if seen else UNEXPLORED_ALPHA
		if zone == _zone:
			a = 0.0
		_zone_alpha[zone] = a
		_fill_cells(img, prects[i], a)

	_mask.texture = ImageTexture.create_from_image(img)
	_mask.centered = false
	_mask.position = map.world_rect.position
	_mask.scale = Vector2(CELL, CELL)
	_mask.visible = true

func _col(alpha: float) -> Color:
	return Color(MASK_COLOR.r, MASK_COLOR.g, MASK_COLOR.b, alpha)

## 把世界矩形换成「格」再整块填充（fill_rect 走 C++，比逐像素快很多）。
func _fill_cells(img: Image, r: Rect2, alpha: float) -> void:
	var x0 := int(round(r.position.x / CELL))
	var y0 := int(round(r.position.y / CELL))
	var w := int(round(r.size.x / CELL))
	var h := int(round(r.size.y / CELL))
	if w <= 0 or h <= 0:
		return
	x0 = clampi(x0, 0, img.get_width() - 1)
	y0 = clampi(y0, 0, img.get_height() - 1)
	w = mini(w, img.get_width() - x0)
	h = mini(h, img.get_height() - y0)
	if w <= 0 or h <= 0:
		return
	img.fill_rect(Rect2i(x0, y0, w, h), _col(alpha))

func _hide_masks() -> void:
	if _mask != null:
		_mask.visible = false

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
