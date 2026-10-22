extends Node2D

var map: Node2D
var axis := "h"
var dir := -1.0
var width := 40.0
var is_open := false
var auto_opened := false
var anim := 0.0
var body: StaticBody2D
var shape: CollisionShape2D

func _ready() -> void:
	add_to_group("doors")

func setup(p_map: Node2D, p_pos: Vector2, p_axis: String, p_dir: float, p_width: float) -> void:
	map = p_map
	position = p_pos
	axis = p_axis
	dir = p_dir
	width = p_width
	body = StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	shape = CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(width, 20.0) if axis == "h" else Vector2(20.0, width)
	shape.shape = rs
	body.add_child(shape)
	add_child(body)
	set_open(false)

func door_rect_world() -> Rect2:
	var r := Rect2(-width * 0.5, -10.0, width, 20.0) if axis == "h" else Rect2(-10.0, -width * 0.5, 20.0, width)
	r.position += position
	return r

func is_closed() -> bool:
	return not is_open

func blocks_point(p: Vector2) -> bool:
	return not is_open and door_rect_world().has_point(p)

func set_open(v: bool, auto := false, opener_pos: Variant = null) -> void:
	if shape == null:
		return
	if v and opener_pos != null and opener_pos is Vector2:
		_face_away(opener_pos)
	is_open = v
	if v:
		auto_opened = auto
	else:
		auto_opened = false
	shape.disabled = v
	if map != null and map.has_method("refresh_door_blockers"):
		map.refresh_door_blockers()
	queue_redraw()

func _face_away(p: Vector2) -> void:
	var off: float = (position.y - p.y) if axis == "h" else (position.x - p.x)
	if absf(off) > 1.0:
		dir = 1.0 if off > 0.0 else -1.0

func toggle_from_player() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if is_open:
		if player != null and door_rect_world().grow(6.0).has_point(player.position):
			return false
	var will_open := not is_open
	if will_open and player != null:
		_face_away(player.position)
	set_open(will_open, false)
	if player != null:
		_try_slam()
	return true

func _try_slam() -> void:
	var r := width * 0.5 + 12.0
	var hit := false
	for n in get_tree().get_nodes_in_group("students"):
		if not (n is Node2D):
			continue
		var off: Vector2 = n.position - position
		if off.length() > r:
			continue
		var perp: float = off.y if axis == "h" else off.x
		if perp * dir < -4.0:
			continue
		var st = n.get("stun_timer")
		if st != null and float(st) > 0.0:
			continue
		if n.has_method("stun"):
			n.stun(3.0)
			hit = true
	for n in get_tree().get_nodes_in_group("tyrants"):
		if not (n is Node2D):
			continue
		if n.position.distance_to(position) > width * 0.5 + 40.0:
			continue
		if n.has_method("on_barricade"):
			n.on_barricade()
			hit = true
			var pl := get_tree().get_first_node_in_group("player")
			if pl != null and pl.has_method("apply_speed_buff"):
				pl.apply_speed_buff(1.25, 2.0)
	if hit and map != null:
		map.noise_made.emit(position, 22.0)
		if map.has_signal("door_slam"):
			map.door_slam.emit()

func _process(delta: float) -> void:
	var target := 1.0 if is_open else 0.0
	if not is_equal_approx(anim, target):
		anim = move_toward(anim, target, delta / 0.15)
		queue_redraw()
	if auto_opened and is_open:
		var busy := false
		for group in ["player", "students", "tyrants"]:
			for n in get_tree().get_nodes_in_group(group):
				if position.distance_to(n.position) < width + 30.0:
					busy = true
					break
			if busy:
				break
		if not busy:
			set_open(false)

func _draw() -> void:
	var hinge: Vector2
	var closed_end: Vector2
	var open_end: Vector2
	var start_angle := 0.0
	var end_angle := 0.0
	if axis == "h":
		hinge = Vector2(-width * 0.5, 0.0)
		closed_end = hinge + Vector2(width, 0.0)
		open_end = hinge + Vector2(0.0, dir * width)
		start_angle = 0.0
		end_angle = PI * 0.5 * dir
	else:
		hinge = Vector2(0.0, -width * 0.5)
		closed_end = hinge + Vector2(0.0, width)
		open_end = hinge + Vector2(dir * width, 0.0)
		start_angle = PI * 0.5
		end_angle = PI * 0.5 - PI * 0.5 * dir

	draw_arc(hinge, width, minf(start_angle, end_angle), maxf(start_angle, end_angle), 14, Color(0.45, 0.30, 0.16, 0.45), 1.4, true)
	var leaf_end := closed_end.lerp(open_end, anim)
	draw_line(hinge, leaf_end, Color(0.30, 0.18, 0.09, 0.55), 4.0)
	draw_line(hinge, leaf_end, Color(0.65, 0.43, 0.23), 2.5)
	draw_circle(leaf_end.lerp(hinge, 0.12), 2.0, Color(0.96, 0.82, 0.42))
