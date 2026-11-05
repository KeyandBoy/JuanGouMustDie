extends Node2D

## B13：校园远景 2 层视差。
##
## 不引入美术素材，全部程序绘制：
##   1. 近层：窗外树影 / 树枝（跟随相机 16% 位移），只出现在窗户外侧与窗下地面；
##   2. 远层：更远处的楼体剪影（跟随相机 7% 位移），压在黑场边缘。
##
## 两层都画在 z=-7（地板上方、墙体与实体下方），不会挡角色、不参与碰撞。
## 相机不动时不重绘，移动超过 0.5px 才 queue_redraw（约 12Hz）。

const NEAR_PARALLAX := 0.16
const FAR_PARALLAX := 0.07
const REDRAW_INTERVAL := 0.08

var map: Node2D
var camera: Camera2D
var _cam_pos := Vector2(INF, INF)
var _t := 0.0


func setup(p_map: Node2D, p_camera: Camera2D) -> void:
	map = p_map
	camera = p_camera
	z_index = -7
	z_as_relative = false
	queue_redraw()


func _process(delta: float) -> void:
	if map == null or camera == null or not is_instance_valid(camera):
		return
	_t += delta
	if _t < REDRAW_INTERVAL:
		return
	_t = 0.0
	if camera.global_position.distance_to(_cam_pos) > 0.5:
		_cam_pos = camera.global_position
		queue_redraw()


func _draw() -> void:
	if map == null:
		return
	var near_off := -_cam_pos * NEAR_PARALLAX
	var far_off := -_cam_pos * FAR_PARALLAX
	var idx := 0
	for w in map.windows:
		var r: Rect2 = w["rect"]
		var axis := String(w.get("axis", "h"))
		var outward := _outward(w, r, axis)
		_far_building(r, outward, far_off, idx)
		_tree_canopy(r, outward, near_off, idx)
		_branch_shadow(r, outward, near_off, idx)
		idx += 1


func _outward(w: Dictionary, r: Rect2, axis: String) -> Vector2:
	var world: Rect2 = map.world_rect
	if axis == "h":
		return Vector2.UP if r.position.y < world.position.y + 40.0 else Vector2.DOWN
	return Vector2.LEFT if r.position.x < world.position.x + 40.0 else Vector2.RIGHT


## 远层：窗外压黑的一栋楼轮廓，比树影更暗、位移更小。
func _far_building(r: Rect2, outward: Vector2, off: Vector2, idx: int) -> void:
	var c := r.get_center() + outward * 70.0 + off * 0.6
	var w := maxf(r.size.x, r.size.y) * 1.6
	var h := 60.0
	var rect := Rect2(c - Vector2(w * 0.5, h), Vector2(w, h))
	draw_rect(rect, Color(0.075, 0.085, 0.10, 0.85))
	# 几扇没亮的窗格
	for k in 4:
		var px := rect.position.x + 8.0 + float(k) * (w - 16.0) / 4.0
		if px + 8.0 > rect.end.x:
			break
		draw_rect(Rect2(px, rect.position.y + 10.0 + float(idx % 3) * 8.0, 7.0, 10.0), Color(0.12, 0.14, 0.16, 0.7))


## 近层：窗外树冠剪影（几个错落的圆/椭圆），随相机移动最明显。
func _tree_canopy(r: Rect2, outward: Vector2, off: Vector2, idx: int) -> void:
	var base := r.get_center() + outward * 26.0
	var side := Vector2(-outward.y, outward.x)
	var span := maxf(r.size.x, r.size.y) * 0.55
	for k in 6:
		var t := float(k) / 5.0 - 0.5
		var jitter := sin(float(idx) * 3.7 + float(k) * 2.1) * 7.0
		var p := base + side * (t * span) + outward * (10.0 + float(k % 2) * 9.0) + off + Vector2(0, jitter)
		var rad := 11.0 + float((idx + k) % 3) * 3.0
		draw_circle(p, rad, Color(0.055, 0.085, 0.065, 0.92))
	# 一根斜枝，打破圆形排列
	var a := base + side * (-span * 0.4) + outward * 8.0 + off
	var b := base + side * (span * 0.35) + outward * 22.0 + off
	draw_line(a, b, Color(0.045, 0.07, 0.055, 0.9), 2.0)


## 窗下地面的枝影：更淡、更长，视觉上把窗和地面连起来。
func _branch_shadow(r: Rect2, outward: Vector2, off: Vector2, idx: int) -> void:
	var inward := -outward
	var side := Vector2(-outward.y, outward.x)
	var base := r.get_center() + inward * 12.0 + off
	var span := maxf(r.size.x, r.size.y) * 0.42
	var col := Color(0.03, 0.05, 0.035, 0.16)
	for k in 3:
		var t := float(k) / 2.0 - 0.5
		var a := base + side * (t * span)
		var b := a + inward * (26.0 + float(k) * 7.0) + side * (6.0 - float(k) * 5.0)
		draw_line(a, b, col, 3.0 - float(k) * 0.6)
		var leaf := b + side * (4.0 - float(k) * 3.0)
		draw_circle(leaf, 3.5, col)
