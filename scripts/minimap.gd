extends Control

const SIZE := Vector2(200.0, 140.0)
const PAD := 7.0

var map
var player
var _discovered := {}

func _ready() -> void:
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func setup(p_map: Node2D, p_player: Node2D) -> void:
	map = p_map
	player = p_player

func reset_discovered() -> void:
	_discovered.clear()

func _process(_delta: float) -> void:
	if map != null and player != null:
		for d in map.desks:
			if float(d.get("efficiency", 1.0)) < 1.4:
				continue
			var pos: Vector2 = d["pos"]
			if player.position.distance_to(pos) <= 90.0:
				_discovered[pos] = true
	queue_redraw()

func _draw() -> void:
	if map == null or player == null:
		return
	if map.world_rect.size.x <= 0.0 or map.world_rect.size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.063, 0.086, 0.90))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.227, 0.251, 0.329, 0.95), false, 1.5)
	draw_rect(Rect2(Vector2(PAD - 3.0, PAD - 3.0), size - Vector2(PAD * 2.0, PAD * 2.0) + Vector2(6.0, 6.0)), Color(0.071, 0.078, 0.114, 0.8))

	var avail := size - Vector2(PAD * 2.0, PAD * 2.0)
	var sc: float = minf(avail.x / map.world_rect.size.x, avail.y / map.world_rect.size.y)
	var off := Vector2(
		(size.x - map.world_rect.size.x * sc) * 0.5,
		(size.y - map.world_rect.size.y * sc) * 0.5
	)

	var seen_any := false
	for i in map.rooms.size():
		if not map.explored[i]:
			continue
		seen_any = true
		var r: Rect2 = map.rooms[i]
		var rr := Rect2(off + (r.position - map.world_rect.position) * sc, r.size * sc)
		var t: String = map.room_types[i]
		var col := Color(0.46, 0.76, 0.42)
		if t == "toilet":
			col = Color(0.44, 0.72, 0.74)
		elif t == "office":
			col = Color(0.58, 0.80, 0.44)
		elif t == "hall":
			col = Color(0.70, 0.84, 0.40)
		draw_rect(rr, col)
		draw_rect(rr, Color(0.13, 0.28, 0.14), false, 1.0)

	var c0 := Rect2(off + (map.corridor_rect.position - map.world_rect.position) * sc, map.corridor_rect.size * sc)
	draw_rect(c0, Color(0.92, 0.95, 0.89))
	if map.is_l_shape and map.tail_corridor_rect.size.y > 0.0:
		var c1 := Rect2(off + (map.tail_corridor_rect.position - map.world_rect.position) * sc, map.tail_corridor_rect.size * sc)
		draw_rect(c1, Color(0.92, 0.95, 0.89))
	if seen_any:
		for r in map.closed_door_rects:
			var known := false
			for i in map.rooms.size():
				if map.explored[i] and map.rooms[i].grow(20.0).has_point(r.get_center()):
					known = true
					break
			if not known:
				continue
			var dr := Rect2(off + (r.position - map.world_rect.position) * sc, r.size * sc)
			draw_rect(dr, Color(0.30, 0.20, 0.09, 0.95))

	if GameState.intel_reveal_timer > 0.0:
		for group in ["students", "tyrants"]:
			for s in get_tree().get_nodes_in_group(group):
				if not (s is Node2D):
					continue
				var sp: Vector2 = off + (s.position - map.world_rect.position) * sc
				var path = s.get("path")
				if path is PackedVector2Array:
					for j in range(path.size() - 1):
						var a: Vector2 = off + (path[j] - map.world_rect.position) * sc
						var b: Vector2 = off + (path[j + 1] - map.world_rect.position) * sc
						draw_line(a, b, Color(0.95, 0.35, 0.35, 0.55), 1.0)
				draw_circle(sp, 3.5, Color(0.95, 0.20, 0.20))

	for dpos in _discovered.keys():
		var hp: Vector2 = off + (Vector2(dpos) - map.world_rect.position) * sc
		draw_circle(hp, 3.0, Color(0.98, 0.82, 0.25))

	var p: Vector2 = off + (player.position - map.world_rect.position) * sc
	draw_circle(p + Vector2(0.0, 1.0), 5.0, Color(0.0, 0.0, 0.0, 0.25))
	draw_circle(p, 4.5, Color(0.10, 0.44, 0.96))
	draw_circle(p, 4.5, Color(1.0, 1.0, 1.0, 0.9), false, 1.0)
	draw_circle(p, 1.6, Color(1.0, 1.0, 1.0))
