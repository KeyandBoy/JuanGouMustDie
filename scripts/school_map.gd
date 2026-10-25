extends Node2D

signal player_caught(by: Node2D)
signal noise_made(pos: Vector2, strength: float)
signal room_entered(index: int)
signal door_slam

const DOOR_SCRIPT := preload("res://scripts/door.gd")

const CELL := 20.0
const WALL_EXT := 1
const WALL_INT := 1
const DOOR_W := 2
const SOLID := 0
const FLOOR := 1

const CORRIDOR_COLOR := Color(0.88, 0.90, 0.86)
const WALL_COLOR := Color(0.70, 0.73, 0.78)
const WALL_EDGE_COLOR := Color(0.27, 0.30, 0.35)
const WALL_TOP_COLOR := Color(0.94, 0.96, 0.98)
const DOOR_COLOR := Color(0.62, 0.41, 0.22)
const WINDOW_COLOR := Color(0.52, 0.80, 0.93)

var rng := RandomNumberGenerator.new()
var level_seed := 0
var rooms: Array[Rect2] = []
var room_types: Array[String] = []
var room_names: Array[String] = []
var explored: Array[bool] = []
var desks: Array[Dictionary] = []
var wall_rects: Array[Rect2] = []
var world_rect := Rect2()
var exit_pos := Vector2.ZERO

var corridor_rect := Rect2()
var tail_corridor_rect := Rect2()
var is_l_shape := false

var grid := PackedByteArray()
var gw := 0
var gh := 0
var doors: Array[Dictionary] = []
var windows: Array[Dictionary] = []
var stair_rects: Array[Rect2] = []
var door_nodes: Array[Node2D] = []
var closed_door_rects: Array[Rect2] = []
var furniture := PackedByteArray()
var reserved := PackedByteArray()
var box_rects: Array[Rect2] = []

var nav_points := PackedVector2Array()
var nav_links: Array = []
var nav_is_corridor: Array[bool] = []

var _astar := AStarGrid2D.new()
var _astar_dirty := true
var _astar_built := false
var _room_cell := PackedInt32Array()
var _floor_layer: TileMapLayer
var _wall_layer: TileMapLayer

class WallShadow:
	extends Node2D
	var rects: Array[Rect2] = []

	func _draw() -> void:
		for r in rects:
			draw_rect(Rect2(r.position + Vector2(3.0, 4.0), r.size), Color(0.0, 0.0, 0.0, 0.13))

var type_defs: Dictionary = {
	"classroom": {"name": "普通教室", "weight": 6, "color": Color(0.96, 0.86, 0.57), "w_min": 12, "w_max": 16, "eff": 1.0},
	"office": {"name": "办公室", "weight": 2, "color": Color(0.80, 0.90, 0.74), "w_min": 9, "w_max": 12, "eff": 1.4},
	"storage": {"name": "储物间", "weight": 2, "color": Color(0.89, 0.78, 0.60), "w_min": 8, "w_max": 10, "eff": 1.2},
	"toilet": {"name": "厕所", "weight": 2, "color": Color(0.68, 0.89, 0.91), "w_min": 9, "w_max": 12, "eff": 0.6},
	"stair": {"name": "楼梯间", "weight": 1, "color": Color(0.86, 0.88, 0.91), "w_min": 9, "w_max": 11, "eff": 0.6},
	"hall": {"name": "大厅楼梯", "weight": 0, "color": Color(0.97, 0.82, 0.47), "w_min": 16, "w_max": 21, "eff": 0.8},
}

func generate(p_seed: int, room_count: int = 0) -> void:
	level_seed = p_seed
	rng.seed = p_seed
	_reset()

	var n := rng.randi_range(6, 10)
	if room_count > 0:
		n = clampi(room_count, 6, 10)

	var cw := rng.randi_range(6, 8)
	var rd_n := rng.randi_range(12, 15)
	var rd_s := rng.randi_range(12, 15)

	is_l_shape = n >= 7 and rng.randf() < 0.35
	var n_tail := 0
	var n_rest := n
	if is_l_shape:
		n_tail = 2 if n <= 8 else 3
		n_rest = n - n_tail

	var n_north := int(n_rest / 2)
	if n_rest % 2 == 1 and rng.randi() % 2 == 0:
		n_north += 1
	var n_south := n_rest - n_north

	var north_types: Array[String] = []
	for i in n_north:
		north_types.append(_pick_type())
	north_types[0] = "hall"
	var south_types: Array[String] = []
	for i in n_south:
		south_types.append(_pick_type())
	var tail_types: Array[String] = []
	for i in n_tail:
		tail_types.append(_pick_type())
	_ensure_stair(north_types, south_types, tail_types)

	var tw := 0
	if is_l_shape:
		tw = rng.randi_range(12, 14)

	var min_n := 2 * WALL_EXT + (n_north - 1) * WALL_INT + _width_sum(north_types, true)
	var min_s := 2 * WALL_EXT + (n_south - 1) * WALL_INT + _width_sum(south_types, true)
	if is_l_shape:
		min_s += cw + 2 * WALL_INT + tw + WALL_EXT
	var L := maxi(min_n, min_s)
	var cap_n := 2 * WALL_EXT + (n_north - 1) * WALL_INT + _width_sum(north_types, false)
	var slack := maxi(0, cap_n - L)
	if slack > 0:
		L += rng.randi_range(0, mini(6, slack))
	L = maxi(L, maxi(min_n, min_s))

	var south_span := L
	var south_right := WALL_EXT
	var tail_corr0 := 0
	var tail_corr1 := 0
	var tail_x_wall := 0
	var tail_x0 := 0
	if is_l_shape:
		tail_corr1 = L - WALL_EXT
		tail_corr0 = tail_corr1 - cw
		tail_x_wall = tail_corr0 - WALL_INT
		tail_x0 = tail_x_wall - tw
		south_span = tail_x0
		south_right = WALL_INT

	var north_w := _fill_widths(north_types, L, WALL_EXT, WALL_EXT)
	var south_w := _fill_widths(south_types, south_span, WALL_EXT, south_right)

	var y_n_start := WALL_EXT
	var y_n_wall := y_n_start + rd_n
	var c_top := y_n_wall + WALL_INT
	var c_bottom := c_top + cw
	var y_s_start := c_bottom + WALL_INT
	var y_s_end := y_s_start + rd_s
	var y_end := y_s_end + WALL_EXT

	var tail_h: Array[int] = []
	var tail_end := y_s_start
	if is_l_shape:
		for i in n_tail:
			tail_h.append(rng.randi_range(11, 14))
		for i in n_tail:
			tail_end += tail_h[i]
			if i < n_tail - 1:
				tail_end += WALL_INT

	gw = L
	if is_l_shape:
		gh = maxi(y_end, tail_end + WALL_EXT)
	else:
		gh = y_end
	grid.resize(gw * gh)
	grid.fill(SOLID)
	_room_cell.resize(gw * gh)
	_room_cell.fill(-1)
	world_rect = Rect2(0, 0, gw * CELL, gh * CELL)

	corridor_rect = Rect2(WALL_EXT * CELL, c_top * CELL, (L - 2 * WALL_EXT) * CELL, cw * CELL)
	if is_l_shape:
		tail_corridor_rect = Rect2(tail_corr0 * CELL, c_bottom * CELL, cw * CELL, (tail_end - c_bottom) * CELL)

	_carve_rect(WALL_EXT, c_top, L - WALL_EXT, c_bottom)
	if is_l_shape:
		_carve_rect(tail_corr0, c_bottom, tail_corr1, tail_end)

	var cells: Array[Rect2i] = []
	var x := WALL_EXT
	for i in n_north:
		cells.append(Rect2i(x, y_n_start, north_w[i], rd_n))
		x += north_w[i] + WALL_INT
	x = WALL_EXT
	for i in n_south:
		cells.append(Rect2i(x, y_s_start, south_w[i], rd_s))
		x += south_w[i] + WALL_INT
	if is_l_shape:
		var y := y_s_start
		for i in n_tail:
			cells.append(Rect2i(tail_x0, y, tw, tail_h[i]))
			y += tail_h[i] + WALL_INT

	for i in cells.size():
		var cr: Rect2i = cells[i]
		_carve_rect(cr.position.x, cr.position.y, cr.end.x, cr.end.y)
		rooms.append(Rect2(cr.position.x * CELL, cr.position.y * CELL, cr.size.x * CELL, cr.size.y * CELL))
		var t := ""
		if i < n_north:
			t = north_types[i]
		elif i < n_north + n_south:
			t = south_types[i - n_north]
		else:
			t = tail_types[i - n_north - n_south]
		room_types.append(t)
		room_names.append(String(type_defs[t]["name"]))
		explored.append(false)
		for yy in range(cr.position.y, cr.end.y):
			for xx in range(cr.position.x, cr.end.x):
				if xx >= 0 and yy >= 0 and xx < gw and yy < gh:
					_room_cell[yy * gw + xx] = i

	for i in cells.size():
		var cr: Rect2i = cells[i]
		if i < n_north:
			var dx := rng.randi_range(cr.position.x + 2, cr.end.x - DOOR_W - 1)
			_carve_rect(dx, y_n_wall, dx + DOOR_W, y_n_wall + WALL_INT)
			doors.append({
				"pos": Vector2((dx + DOOR_W * 0.5) * CELL, (y_n_wall + 0.5) * CELL),
				"axis": "h", "dir": -1.0, "width": DOOR_W * CELL,
			})
			windows.append({"rect": Rect2((cr.position.x + 2) * CELL, 2.0, (cr.size.x - 4) * CELL, 16.0), "axis": "h"})
		elif i < n_north + n_south:
			var dx := rng.randi_range(cr.position.x + 2, cr.end.x - DOOR_W - 1)
			_carve_rect(dx, c_bottom, dx + DOOR_W, c_bottom + WALL_INT)
			doors.append({
				"pos": Vector2((dx + DOOR_W * 0.5) * CELL, (c_bottom + 0.5) * CELL),
				"axis": "h", "dir": 1.0, "width": DOOR_W * CELL,
			})
			windows.append({"rect": Rect2((cr.position.x + 2) * CELL, (y_end - WALL_EXT) * CELL + 2.0, (cr.size.x - 4) * CELL, 16.0), "axis": "h"})
		else:
			var dy := rng.randi_range(cr.position.y + 2, cr.end.y - DOOR_W - 1)
			_carve_rect(tail_x_wall, dy, tail_x_wall + WALL_INT, dy + DOOR_W)
			doors.append({
				"pos": Vector2((tail_x_wall + 0.5) * CELL, (dy + DOOR_W * 0.5) * CELL),
				"axis": "v", "dir": -1.0, "width": DOOR_W * CELL,
			})
			var wy0 := maxi(cr.position.y + 2, y_s_end + WALL_EXT)
			var wy1 := cr.end.y - 1
			if wy1 > wy0 + 2:
				windows.append({"rect": Rect2((tail_x0 - WALL_EXT) * CELL + 2.0, wy0 * CELL, 16.0, (wy1 - wy0) * CELL), "axis": "v"})

	for i in rooms.size():
		if room_types[i] == "stair":
			stair_rects.append(rooms[i])

	var hall_i := room_types.find("hall")
	if hall_i < 0:
		hall_i = 0
	exit_pos = _walkable_center(rooms[hall_i])
	if hall_i >= 0 and hall_i < explored.size():
		explored[hall_i] = true

	_build_walls()
	_build_collision()
	_build_nav()
	_build_doors()
	_build_tiles()
	_spawn_furniture()
	_build_astar()
	queue_redraw()

func _reset() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	rooms.clear()
	room_types.clear()
	room_names.clear()
	explored.clear()
	desks.clear()
	wall_rects.clear()
	doors.clear()
	windows.clear()
	stair_rects.clear()
	door_nodes.clear()
	closed_door_rects.clear()
	furniture = PackedByteArray()
	reserved = PackedByteArray()
	box_rects.clear()
	nav_points = PackedVector2Array()
	nav_links.clear()
	nav_is_corridor.clear()
	_room_cell = PackedInt32Array()
	_floor_layer = null
	_wall_layer = null
	_astar_dirty = true
	_astar_built = false
	grid = PackedByteArray()
	gw = 0
	gh = 0
	world_rect = Rect2()
	corridor_rect = Rect2()
	tail_corridor_rect = Rect2()
	exit_pos = Vector2.ZERO
	is_l_shape = false

func _pick_type() -> String:
	var total := 0
	for k in type_defs:
		total += int(type_defs[k]["weight"])
	var roll := rng.randi_range(1, maxi(1, total))
	var acc := 0
	for k in type_defs:
		var w := int(type_defs[k]["weight"])
		if w <= 0:
			continue
		acc += w
		if roll <= acc:
			return k
	return "classroom"

func _ensure_stair(north: Array[String], south: Array[String], tail: Array[String]) -> void:
	if north.has("stair") or south.has("stair") or tail.has("stair"):
		return
	var groups: Array = []
	for g in [north, south, tail]:
		if g.size() > 0:
			groups.append(g)
	if groups.is_empty():
		return
	var g: Array = groups[rng.randi_range(0, groups.size() - 1)]
	var idx := rng.randi_range(0, g.size() - 1)
	if g[idx] == "hall":
		idx = (idx + 1) % g.size()
	g[idx] = "stair"

func _width_sum(types: Array[String], use_min: bool) -> int:
	var s := 0
	for t in types:
		var d: Dictionary = type_defs[t]
		s += int(d["w_min"]) if use_min else int(d["w_max"])
	return s

func _fill_widths(types: Array[String], span: int, left_w: int, right_w: int) -> Array[int]:
	var out: Array[int] = []
	var k := types.size()
	if k == 0:
		return out
	var avail := span - left_w - right_w - (k - 1) * WALL_INT
	var used := 0
	for t in types:
		var mn := int(type_defs[t]["w_min"])
		out.append(mn)
		used += mn
	var extra := avail - used
	var guard := 0
	while extra > 0 and guard < k * 40:
		var j := guard % k
		var mx := int(type_defs[types[j]]["w_max"])
		if out[j] < mx:
			out[j] += 1
			extra -= 1
		guard += 1
	if extra > 0:
		out[k - 1] += extra
	return out

func _carve_rect(x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(maxi(0, y0), mini(gh, y1)):
		for x in range(maxi(0, x0), mini(gw, x1)):
			grid[y * gw + x] = FLOOR

func _build_walls() -> void:
	var near := PackedByteArray()
	near.resize(grid.size())
	near.fill(0)
	for y in gh:
		for x in gw:
			var i := y * gw + x
			if grid[i] != SOLID:
				continue
			var adj := false
			if x > 0 and grid[i - 1] == FLOOR:
				adj = true
			elif x < gw - 1 and grid[i + 1] == FLOOR:
				adj = true
			elif y > 0 and grid[i - gw] == FLOOR:
				adj = true
			elif y < gh - 1 and grid[i + gw] == FLOOR:
				adj = true
			if adj:
				near[i] = 1

	var used := PackedByteArray()
	used.resize(grid.size())
	used.fill(0)
	for y in gh:
		for x in gw:
			var i := y * gw + x
			if near[i] == 0 or used[i] == 1:
				continue
			var w := 1
			while x + w < gw and near[i + w] == 1 and used[i + w] == 0:
				w += 1
			var h := 1
			while y + h < gh:
				var ok := true
				for xx in w:
					var j := (y + h) * gw + x + xx
					if near[j] == 0 or used[j] == 1:
						ok = false
						break
				if not ok:
					break
				h += 1
			for yy in h:
				for xx in w:
					used[(y + yy) * gw + x + xx] = 1
			wall_rects.append(Rect2(x * CELL, y * CELL, w * CELL, h * CELL))

func _build_tiles() -> void:
	var type_order := ["classroom", "office", "storage", "toilet", "stair", "hall"]
	var c := int(CELL)
	var cols := 16
	var img := Image.create(cols * c, c * 3, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.13, 0.16))
	for row in 2:
		for i in type_order.size():
			var base: Color = type_defs[type_order[i]]["color"]
			var col := base.lightened(0.05) if row == 0 else base.darkened(0.04)
			img.fill_rect(Rect2i(i * c, row * c, c, c), col)
		var cc := CORRIDOR_COLOR.lightened(0.05) if row == 0 else CORRIDOR_COLOR.darkened(0.04)
		img.fill_rect(Rect2i(type_order.size() * c, row * c, c, c), cc)
	img.fill_rect(Rect2i((type_order.size() + 1) * c, 0, c, c), Color(0.12, 0.13, 0.16))
	for mask in 16:
		var ox := mask * c
		var oy := 2 * c
		img.fill_rect(Rect2i(ox, oy, c, c), WALL_COLOR)
		if mask & 1 == 0:
			img.fill_rect(Rect2i(ox, oy, c, 1), WALL_EDGE_COLOR)
			img.fill_rect(Rect2i(ox + 1, oy + 1, c - 2, 2), WALL_TOP_COLOR)
		if mask & 2 == 0:
			img.fill_rect(Rect2i(ox + c - 1, oy, 1, c), WALL_EDGE_COLOR)
		if mask & 4 == 0:
			img.fill_rect(Rect2i(ox, oy + c - 1, c, 1), WALL_EDGE_COLOR)
		if mask & 8 == 0:
			img.fill_rect(Rect2i(ox, oy, 1, c), WALL_EDGE_COLOR)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(c, c)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(c, c)
	for row in 3:
		for cx in range(cols):
			src.create_tile(Vector2i(cx, row))
	ts.add_source(src, 0)

	var holder := Node2D.new()
	holder.name = "Tiles"
	holder.z_index = -1
	add_child(holder)

	_floor_layer = TileMapLayer.new()
	_floor_layer.name = "FloorLayer"
	_floor_layer.tile_set = ts
	_floor_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor_layer.z_index = 1
	holder.add_child(_floor_layer)

	var shadow := WallShadow.new()
	shadow.name = "WallShadow"
	shadow.rects = wall_rects
	shadow.z_index = 2
	holder.add_child(shadow)
	shadow.queue_redraw()

	_wall_layer = TileMapLayer.new()
	_wall_layer.name = "WallLayer"
	_wall_layer.tile_set = ts
	_wall_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wall_layer.z_index = 3
	holder.add_child(_wall_layer)

	var type_index := {}
	for i in type_order.size():
		type_index[type_order[i]] = i
	var corridor_col := type_order.size()
	for y in gh:
		for x in gw:
			var i := y * gw + x
			var cell := Vector2i(x, y)
			if grid[i] != FLOOR:
				_wall_layer.set_cell(cell, 0, Vector2i(corridor_col + 1, 0))
				continue
			var ri := _room_cell[i]
			if ri >= 0:
				var r: Rect2 = rooms[ri]
				var row := ((x - int(r.position.x / CELL)) / 2 + (y - int(r.position.y / CELL)) / 2) % 2
				_floor_layer.set_cell(cell, 0, Vector2i(int(type_index[room_types[ri]]), row))
			else:
				var origin: Vector2 = corridor_rect.position
				var p := Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)
				if tail_corridor_rect.size.y > 0.0 and tail_corridor_rect.has_point(p):
					origin = tail_corridor_rect.position
				var row := ((x - int(origin.x / CELL)) / 2 + (y - int(origin.y / CELL)) / 2) % 2
				_floor_layer.set_cell(cell, 0, Vector2i(corridor_col, row))
	for r in wall_rects:
		for y in range(int(r.position.y / CELL), int(r.end.y / CELL)):
			for x in range(int(r.position.x / CELL), int(r.end.x / CELL)):
				var mask := 0
				if y > 0 and grid[(y - 1) * gw + x] != FLOOR:
					mask |= 1
				if x < gw - 1 and grid[y * gw + x + 1] != FLOOR:
					mask |= 2
				if y < gh - 1 and grid[(y + 1) * gw + x] != FLOOR:
					mask |= 4
				if x > 0 and grid[y * gw + x - 1] != FLOOR:
					mask |= 8
				_wall_layer.set_cell(Vector2i(x, y), 0, Vector2i(mask, 2))

func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	add_child(body)
	for r in wall_rects:
		var shape := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = r.size
		shape.shape = rect_shape
		shape.position = r.get_center()
		body.add_child(shape)

func _build_nav() -> void:
	var door_nodes: Array[int] = []
	for i in rooms.size():
		var d: Vector2 = doors[i]["pos"]
		var di := _add_nav_point(d, true)
		var c := _walkable_center(rooms[i])
		var ci := _add_nav_point(c, false)
		_link(di, ci)
		door_nodes.append(di)

	var corr_nodes: Array[int] = []
	var cy := (corridor_rect.position.y + corridor_rect.end.y) * 0.5
	var x := corridor_rect.position.x + CELL
	while x < corridor_rect.end.x - CELL * 0.5:
		var p := Vector2(x, cy)
		if is_walkable(p):
			var idx := _add_nav_point(p, true)
			if not corr_nodes.is_empty():
				_link(corr_nodes[corr_nodes.size() - 1], idx)
			corr_nodes.append(idx)
		x += CELL * 3.0

	if is_l_shape and tail_corridor_rect.size.y > CELL:
		var tx := (tail_corridor_rect.position.x + tail_corridor_rect.end.x) * 0.5
		var ty := tail_corridor_rect.position.y + CELL
		var prev := -1
		var first := -1
		while ty < tail_corridor_rect.end.y - CELL * 0.5:
			var p := Vector2(tx, ty)
			if is_walkable(p):
				var idx := _add_nav_point(p, true)
				if first < 0:
					first = idx
				if prev >= 0:
					_link(prev, idx)
				prev = idx
			ty += CELL * 3.0
		if first >= 0:
			var best := -1
			var bd := INF
			for ci in corr_nodes:
				var d := nav_points[first].distance_to(nav_points[ci])
				if d < bd and line_clear(nav_points[first], nav_points[ci]):
					bd = d
					best = ci
			if best < 0 and not corr_nodes.is_empty():
				best = corr_nodes[corr_nodes.size() - 1]
			if best >= 0:
				_link(first, best)

	for di in door_nodes:
		var j := _nearest_nav(nav_points[di], true, di)
		if j >= 0:
			_link(di, j)

func _add_nav_point(p: Vector2, is_corr: bool) -> int:
	nav_points.append(p)
	nav_links.append([])
	nav_is_corridor.append(is_corr)
	return nav_points.size() - 1

func _link(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0:
		return
	if not nav_links[a].has(b):
		nav_links[a].append(b)
	if not nav_links[b].has(a):
		nav_links[b].append(a)

func _nearest_nav(p: Vector2, corridor_only: bool, exclude: int) -> int:
	var best := -1
	var bd := INF
	for i in nav_points.size():
		if i == exclude:
			continue
		if corridor_only and not nav_is_corridor[i]:
			continue
		var d := p.distance_to(nav_points[i])
		if d < bd and line_clear(p, nav_points[i]):
			bd = d
			best = i
	if best < 0:
		for i in nav_points.size():
			if i == exclude:
				continue
			if corridor_only and not nav_is_corridor[i]:
				continue
			var d := p.distance_to(nav_points[i])
			if d < bd:
				bd = d
				best = i
	return best

func _build_doors() -> void:
	for d in doors:
		var door: Node2D = DOOR_SCRIPT.new()
		add_child(door)
		door.setup(self, d["pos"], d["axis"], d["dir"], d["width"])
		door_nodes.append(door)
	refresh_door_blockers()

func refresh_door_blockers() -> void:
	closed_door_rects.clear()
	for d in door_nodes:
		if is_instance_valid(d) and d.is_closed():
			closed_door_rects.append(d.door_rect_world())

func door_blocks_point(p: Vector2) -> bool:
	for r in closed_door_rects:
		if r.has_point(p):
			return true
	return false

func _spawn_furniture() -> void:
	desks.clear()
	box_rects.clear()
	furniture.resize(grid.size())
	furniture.fill(0)
	reserved.resize(grid.size())
	reserved.fill(0)
	for p in nav_points:
		_reserve_cells(p, 1)
	for d in doors:
		_reserve_cells(d["pos"], 2)
	_reserve_cells(exit_pos, 2)

	for i in rooms.size():
		var t := room_types[i]
		var eff: float = type_defs[t]["eff"]
		var count := 0
		match t:
			"classroom":
				count = rng.randi_range(3, 5)
			"office":
				count = rng.randi_range(2, 3)
			"storage":
				count = rng.randi_range(1, 2)
			"hall":
				count = rng.randi_range(1, 2)
			"toilet":
				count = 1
		for j in count:
			var rect := _pick_desk_rect(rooms[i], t == "hall")
			if rect.size.x <= 0.0:
				break
			_mark_furniture(rect)
			desks.append({"pos": rect.get_center(), "rect": rect, "room": i, "efficiency": eff, "occupied": false})
		if t == "storage":
			for j in rng.randi_range(2, 3):
				var br := _pick_box_rect(rooms[i])
				if br.size.x <= 0.0:
					break
				_mark_furniture(br)
				box_rects.append(br)
	_build_box_collision()

func _pick_desk_rect(r: Rect2, avoid_center: bool) -> Rect2:
	var x0 := int(round(r.position.x / CELL)) + 1
	var x1 := int(round(r.end.x / CELL)) - 1
	var y0 := int(round(r.position.y / CELL)) + 1
	var y1 := int(round(r.end.y / CELL)) - 1
	if x1 - x0 < 2 or y1 - y0 < 1:
		return Rect2()
	for attempt in 70:
		var cx := rng.randi_range(x0, x1 - 2)
		var cy := rng.randi_range(y0, y1 - 1)
		if not _cells_free(cx, cy, 2, 1):
			continue
		var rect := Rect2(cx * CELL, cy * CELL, 2.0 * CELL, CELL)
		if avoid_center and rect.get_center().distance_to(exit_pos) < CELL * 3.0:
			continue
		var ok := true
		for d in desks:
			if rect.grow(CELL * 0.5).intersects(d["rect"]):
				ok = false
				break
		if ok:
			for br in box_rects:
				if rect.grow(CELL * 0.5).intersects(br):
					ok = false
					break
		if ok:
			return rect
	return Rect2()

func _pick_box_rect(r: Rect2) -> Rect2:
	var x0 := int(round(r.position.x / CELL)) + 1
	var x1 := int(round(r.end.x / CELL)) - 1
	var y0 := int(round(r.position.y / CELL)) + 1
	var y1 := int(round(r.end.y / CELL)) - 1
	if x1 - x0 < 1 or y1 - y0 < 1:
		return Rect2()
	for attempt in 60:
		var cx := rng.randi_range(x0, x1 - 1)
		var cy := rng.randi_range(y0, y1 - 1)
		if not _cells_free(cx, cy, 1, 1):
			continue
		var rect := Rect2(cx * CELL, cy * CELL, CELL, CELL)
		var ok := true
		for d in desks:
			if rect.grow(CELL * 0.5).intersects(d["rect"]):
				ok = false
				break
		if ok:
			for br in box_rects:
				if rect.grow(CELL * 0.25).intersects(br):
					ok = false
					break
		if ok:
			return rect
	return Rect2()

func _cells_free(cx: int, cy: int, w: int, h: int) -> bool:
	for y in range(cy, cy + h):
		for x in range(cx, cx + w):
			if x < 0 or y < 0 or x >= gw or y >= gh:
				return false
			var i := y * gw + x
			if grid[i] != FLOOR or reserved[i] == 1 or furniture[i] == 1:
				return false
	return true

func _mark_furniture(rect: Rect2) -> void:
	_astar_dirty = true
	var cx0 := int(round(rect.position.x / CELL))
	var cy0 := int(round(rect.position.y / CELL))
	var w := int(round(rect.size.x / CELL))
	var h := int(round(rect.size.y / CELL))
	for y in range(cy0, cy0 + h):
		for x in range(cx0, cx0 + w):
			if x >= 0 and y >= 0 and x < gw and y < gh:
				furniture[y * gw + x] = 1

func _reserve_cells(p: Vector2, radius: int) -> void:
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if x >= 0 and y >= 0 and x < gw and y < gh:
				reserved[y * gw + x] = 1

func _build_box_collision() -> void:
	if box_rects.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "Furniture"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for r in box_rects:
		var shape := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = r.size
		shape.shape = rs
		shape.position = r.get_center()
		body.add_child(shape)

func _walkable_center(r: Rect2) -> Vector2:
	var c := r.get_center()
	if is_walkable(c):
		return c
	var best := c
	var bd := INF
	for gy in range(int(r.position.y / CELL) + 1, int(r.end.y / CELL)):
		for gx in range(int(r.position.x / CELL) + 1, int(r.end.x / CELL)):
			var p := Vector2((gx + 0.5) * CELL, (gy + 0.5) * CELL)
			if not is_walkable(p):
				continue
			var d := p.distance_to(c)
			if d < bd:
				bd = d
				best = p
	return best

func is_walkable(pos: Vector2) -> bool:
	if pos.x < 0.0 or pos.y < 0.0:
		return false
	var cx := int(pos.x / CELL)
	var cy := int(pos.y / CELL)
	if cx >= gw or cy >= gh:
		return false
	var i := cy * gw + cx
	if grid[i] != FLOOR:
		return false
	return furniture.is_empty() or furniture[i] == 0

func _is_floor_cell(pos: Vector2) -> bool:
	if pos.x < 0.0 or pos.y < 0.0:
		return false
	var cx := int(pos.x / CELL)
	var cy := int(pos.y / CELL)
	if cx >= gw or cy >= gh:
		return false
	return grid[cy * gw + cx] == FLOOR

func _cell_walkable(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= gw or cy >= gh:
		return false
	var i := cy * gw + cx
	if grid[i] != FLOOR:
		return false
	return furniture.is_empty() or furniture[i] == 0

func line_clear(a: Vector2, b: Vector2) -> bool:
	if not _cell_walkable(int(a.x / CELL), int(a.y / CELL)):
		return false
	if not _cell_walkable(int(b.x / CELL), int(b.y / CELL)):
		return false
	var cx := int(a.x / CELL)
	var cy := int(a.y / CELL)
	var cx1 := int(b.x / CELL)
	var cy1 := int(b.y / CELL)
	var dx := b.x - a.x
	var dy := b.y - a.y
	var step_x := 1 if dx > 0.0 else -1
	var step_y := 1 if dy > 0.0 else -1
	var t_max_x := INF
	var t_max_y := INF
	var t_delta_x := INF
	var t_delta_y := INF
	if not is_zero_approx(dx):
		var next_x := float(cx + (1 if dx > 0.0 else 0)) * CELL
		t_max_x = absf(next_x - a.x) / absf(dx)
		t_delta_x = CELL / absf(dx)
	if not is_zero_approx(dy):
		var next_y := float(cy + (1 if dy > 0.0 else 0)) * CELL
		t_max_y = absf(next_y - a.y) / absf(dy)
		t_delta_y = CELL / absf(dy)
	var guard := 0
	while (cx != cx1 or cy != cy1) and guard < 512:
		guard += 1
		if t_max_x < t_max_y:
			cx += step_x
			t_max_x += t_delta_x
		elif t_max_y < t_max_x:
			cy += step_y
			t_max_y += t_delta_y
		else:
			cx += step_x
			cy += step_y
			t_max_x += t_delta_x
			t_max_y += t_delta_y
		if not _cell_walkable(cx, cy):
			return false
	return true

func vision_clear(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / (CELL * 0.25)) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		if not is_walkable(p):
			return false
		if door_blocks_point(p):
			return false
	return true

func sound_clear(a: Vector2, b: Vector2) -> bool:
	var d := a.distance_to(b)
	var steps := int(d / (CELL * 0.4)) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		if not _is_floor_cell(p):
			return false
		if door_blocks_point(p):
			return false
	return true

func cast_vision(origin: Vector2, dir: Vector2, half_angle: float, dist: float, rays: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(origin)
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN
	var base := dir.angle()
	var step := 5.0
	for i in rays + 1:
		var a := base - half_angle + (2.0 * half_angle) * float(i) / float(rays)
		var d := Vector2(cos(a), sin(a))
		var t := 2.0
		var last := origin
		while t <= dist:
			var p := origin + d * t
			if not is_walkable(p) or door_blocks_point(p):
				break
			last = p
			t += step
		if t > dist:
			last = origin + d * dist
		pts.append(last)
	return pts

func _nearest_visible(p: Vector2) -> int:
	var best := -1
	var bd := INF
	for i in nav_points.size():
		var d := p.distance_to(nav_points[i])
		if d < bd and line_clear(p, nav_points[i]):
			bd = d
			best = i
	if best < 0:
		for i in nav_points.size():
			var d := p.distance_to(nav_points[i])
			if d < bd:
				bd = d
				best = i
	return best

func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if nav_points.is_empty():
		return out
	if line_clear(from, to):
		out.append(to)
		return out
	var pts := _astar_path(from, to)
	if pts.is_empty():
		return _find_path_nav(from, to)
	out.append(from)
	var origin := from
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not line_clear(origin, pts[j]):
			j -= 1
		origin = pts[j]
		out.append(origin)
		i = j + 1
	if out[out.size() - 1].distance_to(to) > 1.0:
		out.append(to)
	return out

func _astar_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if gw <= 0 or gh <= 0:
		return out
	if _astar_dirty or not _astar_built:
		_build_astar()
	var a := _nearest_open_cell(_to_cell(from))
	var b := _nearest_open_cell(_to_cell(to))
	if a.x < 0 or b.x < 0:
		return out
	var ids := _astar.get_id_path(a, b)
	if ids.size() < 2:
		return out
	for id in ids:
		out.append(Vector2((id.x + 0.5) * CELL, (id.y + 0.5) * CELL))
	return out

func _to_cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL), 0, gw - 1), clampi(int(p.y / CELL), 0, gh - 1))

func _nearest_open_cell(c: Vector2i) -> Vector2i:
	if c.x < 0 or c.y < 0:
		return Vector2i(-1, -1)
	if not _astar.is_point_solid(c):
		return c
	for r in range(1, 7):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var n := c + Vector2i(dx, dy)
				if n.x < 0 or n.y < 0 or n.x >= gw or n.y >= gh:
					continue
				if _astar.is_point_solid(n):
					continue
				var d := Vector2(dx, dy).length_squared()
				if d < bd:
					bd = d
					best = n
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

func _build_astar() -> void:
	_astar.region = Rect2i(0, 0, gw, gh)
	_astar.cell_size = Vector2(CELL, CELL)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	_astar.jumping_enabled = false
	_astar.update()
	_astar.fill_solid_region(_astar.region, false)
	for y in range(gh):
		for x in range(gw):
			var i := y * gw + x
			var solid := grid[i] != FLOOR
			if not solid and not furniture.is_empty() and furniture[i] != 0:
				solid = true
			if solid:
				_astar.set_point_solid(Vector2i(x, y), true)
	_astar_dirty = false
	_astar_built = true

func rebuild_astar() -> void:
	if gw > 0 and gh > 0:
		_build_astar()

func _find_path_nav(from: Vector2, to: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var start := _nearest_visible(from)
	var goal := _nearest_visible(to)
	if start < 0 or goal < 0:
		return out
	var prev := PackedInt32Array()
	prev.resize(nav_points.size())
	prev.fill(-2)
	prev[start] = -1
	var queue: Array[int] = [start]
	var head := 0
	var found := false
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if cur == goal:
			found = true
			break
		for nxt in nav_links[cur]:
			if prev[nxt] == -2:
				prev[nxt] = cur
				queue.append(nxt)
	if not found:
		return out

	var chain: Array[int] = []
	var c := goal
	while c != -1:
		chain.append(c)
		c = prev[c]
	chain.reverse()

	out.append(from)
	var origin := from
	var i := 0
	while i < chain.size():
		var j := chain.size() - 1
		while j > i and not line_clear(origin, nav_points[chain[j]]):
			j -= 1
		origin = nav_points[chain[j]]
		out.append(origin)
		i = j + 1
	if out[out.size() - 1].distance_to(to) > 1.0:
		out.append(to)
	return out

func random_nav_point(corridor_only: bool = false) -> Vector2:
	var pool: Array[int] = []
	for i in nav_points.size():
		if corridor_only and not nav_is_corridor[i]:
			continue
		pool.append(i)
	if pool.is_empty():
		return exit_pos
	return nav_points[pool[rng.randi_range(0, pool.size() - 1)]]

func random_room_center(allow_hall: bool = true) -> Vector2:
	if rooms.is_empty():
		return exit_pos
	var idx := rng.randi_range(0, rooms.size() - 1)
	var guard := 0
	while not allow_hall and room_types[idx] == "hall" and guard < 12:
		idx = rng.randi_range(0, rooms.size() - 1)
		guard += 1
	return _walkable_center(rooms[idx])

func spawn_points(count: int, corridor_only: bool = true) -> Array[Vector2]:
	var pool: Array[int] = []
	for i in nav_points.size():
		if corridor_only and not nav_is_corridor[i]:
			continue
		pool.append(i)
	if pool.size() < count:
		for i in nav_points.size():
			if not pool.has(i):
				pool.append(i)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := pool[i]
		pool[i] = pool[j]
		pool[j] = t
	var out: Array[Vector2] = []
	for i in pool.size():
		out.append(nav_points[pool[i]])
		if out.size() >= count:
			break
	return out

func is_connected_plan() -> bool:
	if rooms.is_empty() or nav_points.is_empty():
		return false
	for i in rooms.size():
		var p := _walkable_center(rooms[i])
		var path := find_path(exit_pos, p)
		if path.is_empty():
			return false
		if path[path.size() - 1].distance_to(p) > CELL * 2.0:
			return false
	return true

func explore_room_at(pos: Vector2) -> int:
	for i in rooms.size():
		if rooms[i].has_point(pos):
			if not explored[i]:
				explored[i] = true
				room_entered.emit(i)
			return i
	return -1

func room_index_at(pos: Vector2) -> int:
	for i in rooms.size():
		if rooms[i].has_point(pos):
			return i
	return -1

func _draw() -> void:
	if gw <= 0:
		return
	for i in rooms.size():
		_room_decor(i)

	for w in windows:
		_window(w)
	for s in stair_rects:
		_stair_lines(s)
	_draw_boxes()

	var font := UiTheme.font()
	for i in rooms.size():
		var r: Rect2 = rooms[i]
		if r.size.x < 90.0:
			continue
		var lp := Vector2(r.position.x + 9.0, r.position.y + 42.0)
		draw_string_outline(font, lp, room_names[i], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 18.0, 15, 4, Color(1.0, 1.0, 1.0, 0.8))
		draw_string(font, lp, room_names[i], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 18.0, 15, Color(0.23, 0.19, 0.13, 0.92))
	var cp := corridor_rect.position + Vector2(10.0, 24.0)
	draw_string_outline(font, cp, "走廊", HORIZONTAL_ALIGNMENT_LEFT, corridor_rect.size.x - 20.0, 14, 4, Color(1.0, 1.0, 1.0, 0.65))
	draw_string(font, cp, "走廊", HORIZONTAL_ALIGNMENT_LEFT, corridor_rect.size.x - 20.0, 14, Color(0.33, 0.35, 0.32, 0.85))

func _room_decor(i: int) -> void:
	var r: Rect2 = rooms[i]
	if r.size.x < 50.0 or r.size.y < 40.0:
		return
	match room_types[i]:
		"classroom":
			_chalkboard(r)
		"office":
			_plant(Vector2(r.end.x - 18.0, r.position.y + 22.0))
			_plant(Vector2(r.end.x - 18.0, r.end.y - 18.0))
		"hall":
			var m := Rect2(exit_pos - Vector2(18.0, 11.0), Vector2(36.0, 22.0))
			if r.encloses(m):
				draw_rect(m, Color(0.82, 0.32, 0.28))
				draw_rect(m, Color(0.60, 0.18, 0.16), false, 2.0)
				draw_rect(m.grow(-3.0), Color(0.93, 0.52, 0.34), false, 1.5)

func _chalkboard(r: Rect2) -> void:
	var bw := minf(r.size.x * 0.55, 150.0)
	var bx := r.position.x + (r.size.x - bw) * 0.5
	var by := r.position.y + 5.0
	draw_rect(Rect2(bx - 4.0, by - 2.0, bw + 8.0, 18.0), Color(0.62, 0.43, 0.25))
	draw_rect(Rect2(bx - 4.0, by - 2.0, bw + 8.0, 18.0), Color(0.36, 0.23, 0.12), false, 1.5)
	draw_rect(Rect2(bx, by, bw, 12.0), Color(0.20, 0.47, 0.31))
	draw_line(Vector2(bx + 8.0, by + 4.0), Vector2(bx + bw * 0.55, by + 4.0), Color(0.86, 0.95, 0.89, 0.85), 1.5)
	draw_line(Vector2(bx + 8.0, by + 8.0), Vector2(bx + bw * 0.36, by + 8.0), Color(0.86, 0.95, 0.89, 0.6), 1.5)

func _plant(p: Vector2) -> void:
	draw_circle(p + Vector2(1.5, 4.0), 8.0, Color(0.0, 0.0, 0.0, 0.10))
	draw_rect(Rect2(p + Vector2(-6.0, 3.0), Vector2(12.0, 10.0)), Color(0.74, 0.46, 0.27))
	draw_rect(Rect2(p + Vector2(-6.0, 3.0), Vector2(12.0, 10.0)), Color(0.45, 0.27, 0.14), false, 1.5)
	draw_circle(p, 8.0, Color(0.27, 0.62, 0.34))
	draw_circle(p + Vector2(-4.0, -3.0), 5.5, Color(0.36, 0.73, 0.42))
	draw_circle(p + Vector2(4.0, -2.0), 5.0, Color(0.31, 0.67, 0.38))

func _draw_boxes() -> void:
	for r in box_rects:
		var box := r.grow(-2.0)
		draw_rect(Rect2(box.position + Vector2(1.5, 2.0), box.size), Color(0.0, 0.0, 0.0, 0.12))
		draw_rect(box, Color(0.82, 0.63, 0.38))
		draw_rect(box, Color(0.52, 0.37, 0.20), false, 1.5)
		var c := box.get_center()
		draw_line(Vector2(box.position.x, c.y), Vector2(box.end.x, c.y), Color(0.58, 0.42, 0.24), 1.0)
		draw_line(Vector2(c.x, box.position.y), Vector2(c.x, box.end.y), Color(0.92, 0.78, 0.52), 1.5)

func _window(w: Dictionary) -> void:
	var wr: Rect2 = w["rect"]
	draw_rect(wr.grow(1.0), Color(0.92, 0.95, 0.98))
	draw_rect(wr, WINDOW_COLOR)
	draw_rect(wr, Color(0.33, 0.54, 0.68), false, 1.5)
	var c := wr.get_center()
	if w["axis"] == "h":
		draw_line(Vector2(wr.position.x, c.y), Vector2(wr.end.x, c.y), Color(0.93, 0.97, 1.0), 1.5)
		draw_line(Vector2(c.x, wr.position.y), Vector2(c.x, wr.end.y), Color(0.93, 0.97, 1.0), 1.5)
	else:
		draw_line(Vector2(c.x, wr.position.y), Vector2(c.x, wr.end.y), Color(0.93, 0.97, 1.0), 1.5)
		draw_line(Vector2(wr.position.x, c.y), Vector2(wr.end.x, c.y), Color(0.93, 0.97, 1.0), 1.5)

func _stair_lines(r: Rect2) -> void:
	var n := 8
	var h := r.size.y / float(n)
	for k in n:
		if k % 2 == 0:
			draw_rect(Rect2(r.position.x + 12.0, r.position.y + h * k, r.size.x - 24.0, h), Color(1.0, 1.0, 1.0, 0.14))
	var col := Color(0.52, 0.55, 0.60)
	for k in range(1, n):
		var y := r.position.y + h * k
		draw_line(Vector2(r.position.x + 12.0, y), Vector2(r.end.x - 12.0, y), col, 1.5)
	var c := r.get_center()
	var arrow := Color(0.35, 0.42, 0.55)
	draw_line(c + Vector2(0.0, 10.0), c + Vector2(0.0, -10.0), arrow, 2.0)
	draw_line(c + Vector2(0.0, -10.0), c + Vector2(-5.0, -4.0), arrow, 2.0)
	draw_line(c + Vector2(0.0, -10.0), c + Vector2(5.0, -4.0), arrow, 2.0)

