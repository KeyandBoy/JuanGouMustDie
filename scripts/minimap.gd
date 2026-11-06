extends Control

const SIZE := Vector2(184.0, 126.0)
const PAD := 6.0

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
	if map == null or player == null:
		return
	# 已发现的储物箱 / 掉落道具 / 高效答题点
	for br in map.box_rects:
		var bp: Vector2 = (br as Rect2).get_center()
		if player.position.distance_to(bp) <= 110.0:
			_discovered[bp] = true
	for n in get_tree().get_nodes_in_group("pickups"):
		if n is Node2D:
			var np: Vector2 = (n as Node2D).position
			if player.position.distance_to(np) <= 150.0:
				_discovered[np] = true
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
	var content: Rect2 = map.content_rect()
	if content.size.x <= 0.0 or content.size.y <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.055, 0.063, 0.086, 0.90))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.227, 0.251, 0.329, 0.95), false, 1.5)
	draw_rect(Rect2(Vector2(PAD - 3.0, PAD - 3.0), size - Vector2(PAD * 2.0, PAD * 2.0) + Vector2(6.0, 6.0)), Color(0.071, 0.078, 0.114, 0.8))

	var avail := size - Vector2(PAD * 2.0, PAD * 2.0)
	var sc: float = minf(avail.x / content.size.x, avail.y / content.size.y)
	var off := Vector2(
		(size.x - content.size.x * sc) * 0.5,
		(size.y - content.size.y * sc) * 0.5
	)

	# 已探索的走廊段（未探索的一律不画）
	for i in map.corridor_segments.size():
		if i >= map.corridor_explored.size() or not map.corridor_explored[i]:
			continue
		var s: Rect2 = map.corridor_segments[i]
		var sr := Rect2(off + (s.position - content.position) * sc, s.size * sc)
		draw_rect(sr, Color(0.86, 0.89, 0.84))

	# 走过的环路门洞（没走过就跟墙一样不画）
	for i in map.passage_rects.size():
		if i < map.passage_owner.size() and not map.passage_seen(i):
			continue
		var ps: Rect2 = map.passage_rects[i]
		var psr := Rect2(off + (ps.position - content.position) * sc, ps.size * sc)
		draw_rect(psr, Color(0.86, 0.89, 0.84))

	# 已探索的房间：按房型着色
	var seen_any := false
	for i in map.rooms.size():
		if not map.explored[i]:
			continue
		seen_any = true
		var r: Rect2 = map.rooms[i]
		var rr := Rect2(off + (r.position - content.position) * sc, r.size * sc)
		var col := Color(0.46, 0.76, 0.42)
		var t: String = String(map.room_types[i])
		if map.type_defs.has(t):
			var base: Color = map.type_defs[t]["color"]
			col = Color(base.r * 0.75 + 0.15, base.g * 0.75 + 0.18, base.b * 0.75 + 0.14)
		draw_rect(rr, col)
		draw_rect(rr, Color(0.13, 0.28, 0.14), false, 1.0)
		# 楼梯标记
		if t == "stair":
			var c := rr.get_center()
			var a := minf(rr.size.x, rr.size.y) * 0.30
			draw_line(c + Vector2(-a, a * 0.6), c + Vector2(-a * 0.1, -a * 0.6), Color(1.0, 0.92, 0.55), 2.0)
			draw_line(c + Vector2(-a * 0.1, a * 0.6), c + Vector2(a * 0.8, -a * 0.6), Color(1.0, 0.92, 0.55), 2.0)
			draw_line(c + Vector2(-a, a * 0.6), c + Vector2(a * 0.8, a * 0.6), Color(1.0, 0.92, 0.55), 2.0)

	if seen_any:
		for r in map.closed_door_rects:
			var known := false
			for i in map.rooms.size():
				if map.explored[i] and map.rooms[i].grow(20.0).has_point(r.get_center()):
					known = true
					break
			if not known:
				continue
			var dr := Rect2(off + (r.position - content.position) * sc, r.size * sc)
			draw_rect(dr, Color(0.30, 0.20, 0.09, 0.95))

	# 敌人只在「巡查情报」生效时显示
	if GameState.intel_reveal_timer > 0.0:
		for group in ["students", "tyrants"]:
			for s in get_tree().get_nodes_in_group(group):
				if not (s is Node2D):
					continue
				var sp: Vector2 = off + (s.position - content.position) * sc
				var path = s.get("path")
				if path is PackedVector2Array:
					for j in range(path.size() - 1):
						var a: Vector2 = off + (path[j] - content.position) * sc
						var b: Vector2 = off + (path[j + 1] - content.position) * sc
						draw_line(a, b, Color(0.95, 0.35, 0.35, 0.55), 1.0)
				draw_circle(sp, 3.5, Color(0.95, 0.20, 0.20))

	for dpos in _discovered.keys():
		var hp: Vector2 = off + (Vector2(dpos) - content.position) * sc
		draw_rect(Rect2(hp - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(0.98, 0.82, 0.25))

	# 玩家：位置 + 朝向
	var p: Vector2 = off + (player.position - content.position) * sc
	var fd = player.get("face_dir")
	if fd is Vector2 and (fd as Vector2).length_squared() > 0.001:
		var v: Vector2 = (fd as Vector2).normalized()
		draw_line(p, p + v * 7.0, Color(0.35, 0.72, 1.0, 0.9), 2.0)
	draw_circle(p + Vector2(0.0, 1.0), 5.0, Color(0.0, 0.0, 0.0, 0.25))
	draw_circle(p, 4.5, Color(0.10, 0.44, 0.96))
	draw_circle(p, 4.5, Color(1.0, 1.0, 1.0, 0.9), false, 1.0)
	draw_circle(p, 1.6, Color(1.0, 1.0, 1.0))
