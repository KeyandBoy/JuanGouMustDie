extends Node2D

signal player_caught(by: Node2D)
signal noise_made(pos: Vector2, strength: float)
signal room_entered(index: int)
signal door_slam

const DOOR_SCRIPT := preload("res://scripts/door.gd")

const CELL := 20.0
## 安全屋从第 6 层开始启用；前五层是教学/基础层，不给喘息点。
const SAFE_ROOM_MIN_LEVEL := 6
const WALL_EXT := 1
const WALL_INT := 1
const DOOR_W := 2
const SOLID := 0
const FLOOR := 1

## 房型全集（顺序 = 地砖图集的列序，别乱改）。
const TYPE_ORDER := [
	"classroom", "lab", "library", "medical", "office",
	"storage", "broadcast", "toilet", "stair", "hall",
]
const CORRIDOR_TYPE := "corridor"
## 地板图案种类：0 棋格 / 1 砖 / 2 木地板 / 3 纯色 / 4 污渍 / 5 裂纹
const FLOOR_VARIANTS := 6

const CORRIDOR_COLOR := Color(0.88, 0.90, 0.86)
const CORRIDOR_WALL := Color(0.66, 0.69, 0.73)
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
var decor_items: Array[Dictionary] = []
var wall_rects: Array[Rect2] = []
var world_rect := Rect2()
var exit_pos := Vector2.ZERO

var corridor_rect := Rect2()
var tail_corridor_rect := Rect2()
var is_l_shape := false

## 走廊按「门到门 / 路口到路口」切段，探索按整段点亮（和房间同一套逻辑）。
var corridor_segments: Array[Rect2] = []
var corridor_explored: Array[bool] = []
## 探索状态版本号：fog / minimap 靠它判断要不要重建遮罩。
var exploration_version := 0

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

## 房型专属大件家具（贴图，见 art/furniture/README.md）：
##   sprite=贴图名、rect=世界矩形、room=房间下标、solid=是否挡路、decal=是否贴在墙上的装饰
var big_items: Array[Dictionary] = []
var big_rects: Array[Rect2] = []
var _tex_cache: Dictionary = {}

var nav_points := PackedVector2Array()
var nav_links: Array = []
var nav_is_corridor: Array[bool] = []

## 套间（里间）：在大房间里掏出来的独立小房间，只有一道 2 格开口；
## 探索/迷雾/命名都按独立房间处理，默认当宝箱房 = 隐藏奖励。
var nested_room_index := -1
var nested_rect := Rect2()
var nested_parent := -1

## 环路：同排相邻两间房之间额外开的一道 2 格通道（跑图/甩追击者用）。
var passage_rects: Array[Rect2] = []
var passage_owner: Array[int] = []
var passage_other: Array[int] = []

## 房间角色（替代「主路/支路」）：stair / hall / safe / deep / normal
## depth = 到楼梯房的距离，用来做风险梯度，不依赖「入口/出口」概念。
var room_roles: Array[String] = []
var room_depth: Array[int] = []
var safe_room_index := -1
var entry_room_index := -1
var boss_room_index := -1
var treasure_room_index := -1
var main_path_rooms: Array[int] = []

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

## 房型元数据：weight=出现权重（hall 固定占北排第一间）、w_min/w_max=房间宽度（格），
## color=地板底色、wall=墙砖底色、eff=答题效率倍率、desk=每 60 格放几张课桌的分母（0=不放）。
var type_defs: Dictionary = {
	"classroom": {"name": "普通教室", "weight": 6, "color": Color(0.93, 0.83, 0.56), "wall": Color(0.87, 0.82, 0.70), "w_min": 26, "w_max": 36, "eff": 1.0, "desk": 55.0},
	"lab":       {"name": "实验室",   "weight": 3, "color": Color(0.85, 0.90, 0.93), "wall": Color(0.79, 0.86, 0.91), "w_min": 24, "w_max": 34, "eff": 1.5, "desk": 78.0},
	"library":   {"name": "图书室",   "weight": 3, "color": Color(0.82, 0.68, 0.48), "wall": Color(0.78, 0.70, 0.58), "w_min": 22, "w_max": 30, "eff": 1.25, "desk": 72.0},
	"medical":   {"name": "医务室",   "weight": 2, "color": Color(0.85, 0.93, 0.89), "wall": Color(0.82, 0.90, 0.88), "w_min": 20, "w_max": 28, "eff": 1.3, "desk": 95.0},
	"office":    {"name": "办公室",   "weight": 3, "color": Color(0.75, 0.83, 0.87), "wall": Color(0.73, 0.80, 0.85), "w_min": 18, "w_max": 26, "eff": 1.4, "desk": 85.0},
	"storage":   {"name": "储物间",   "weight": 2, "color": Color(0.75, 0.79, 0.68), "wall": Color(0.70, 0.75, 0.68), "w_min": 15, "w_max": 20, "eff": 1.2, "desk": 110.0},
	"broadcast": {"name": "广播室",   "weight": 1, "color": Color(0.67, 0.60, 0.76), "wall": Color(0.63, 0.57, 0.72), "w_min": 15, "w_max": 20, "eff": 1.6, "desk": 120.0},
	"toilet":    {"name": "厕所",     "weight": 2, "color": Color(0.62, 0.83, 0.89), "wall": Color(0.66, 0.85, 0.91), "w_min": 13, "w_max": 17, "eff": 0.6, "desk": 999.0},
	"stair":     {"name": "楼梯间",   "weight": 1, "color": Color(0.81, 0.83, 0.86), "wall": Color(0.76, 0.79, 0.83), "w_min": 15, "w_max": 20, "eff": 0.6, "desk": 999.0},
	"hall":      {"name": "大厅楼梯", "weight": 0, "color": Color(0.95, 0.81, 0.52), "wall": Color(0.91, 0.81, 0.63), "w_min": 24, "w_max": 32, "eff": 0.8, "desk": 150.0},
}

func generate(p_seed: int, room_count: int = 0) -> void:
	level_seed = p_seed
	rng.seed = p_seed
	_reset()

	var n := rng.randi_range(6, 10)
	if room_count > 0:
		n = clampi(room_count, 6, 10)

	var cw := rng.randi_range(10, 12)
	var rd_n := rng.randi_range(18, 24)
	var rd_s := rng.randi_range(18, 24)

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
	# 保底房型：每层至少 1 间普通教室 + 1 间厕所（楼梯/大厅不让动）
	_ensure_floor_types(north_types, south_types, tail_types)

	var tw := 0
	if is_l_shape:
		tw = cw

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
			tail_h.append(rng.randi_range(16, 22))
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

	# 套间 + 环路：必须在 _build_walls 之前开凿，墙/碰撞才会跟着重算
	_carve_nested_room()
	_carve_loop_passage()

	for i in rooms.size():
		if room_types[i] == "stair":
			stair_rects.append(rooms[i])

	var hall_i := room_types.find("hall")
	if hall_i < 0:
		hall_i = 0
	exit_pos = _walkable_center(rooms[hall_i], hall_i)
	if hall_i >= 0 and hall_i < explored.size():
		explored[hall_i] = true

	_build_walls()
	_build_collision()
	_build_nav()
	_build_doors()
	_build_corridor_segments()
	_build_tiles()
	_compute_roles(true)
	_spawn_furniture()
	_build_astar()
	queue_redraw()

func generate_tutorial() -> void:
	_reset()
	level_seed = 20261025
	rng.seed = level_seed
	is_l_shape = false
	gw = 42
	gh = 21
	grid.resize(gw * gh)
	grid.fill(SOLID)
	_room_cell.resize(gw * gh)
	_room_cell.fill(-1)
	world_rect = Rect2(0, 0, gw * CELL, gh * CELL)
	corridor_rect = Rect2(1 * CELL, 9 * CELL, 40 * CELL, 3 * CELL)
	tail_corridor_rect = Rect2()
	_carve_rect(1, 9, 41, 12)
	var defs := [
		[2, 16, 2, 8, "classroom"],
		[18, 27, 2, 8, "office"],
		[29, 40, 2, 8, "stair"],
		[2, 12, 13, 19, "toilet"],
		[14, 27, 13, 19, "storage"],
	]
	for d in defs:
		var x0: int = d[0]
		var x1: int = d[1]
		var y0: int = d[2]
		var y1: int = d[3]
		var t: String = d[4]
		_carve_rect(x0, y0, x1, y1)
		rooms.append(Rect2(x0 * CELL, y0 * CELL, (x1 - x0) * CELL, (y1 - y0) * CELL))
		room_types.append(t)
		room_names.append(String(type_defs[t]["name"]))
		explored.append(true)
		for y in range(y0, y1):
			for x in range(x0, x1):
				_room_cell[y * gw + x] = rooms.size() - 1
	for i in rooms.size():
		var r: Rect2 = rooms[i]
		var cx0 := int(r.position.x / CELL)
		var cx1 := int(r.end.x / CELL)
		var dx := cx0 + maxi(2, int((cx1 - cx0) * 0.5) - 1)
		if r.position.y < corridor_rect.position.y:
			_carve_rect(dx, 8, dx + DOOR_W, 9)
			doors.append({
				"pos": Vector2((dx + DOOR_W * 0.5) * CELL, 8.5 * CELL),
				"axis": "h", "dir": -1.0, "width": DOOR_W * CELL,
			})
			windows.append({"rect": Rect2(r.position.x + 3 * CELL, CELL + 2.0, r.size.x - 6 * CELL, 16.0), "axis": "h"})
		else:
			_carve_rect(dx, 12, dx + DOOR_W, 13)
			doors.append({
				"pos": Vector2((dx + DOOR_W * 0.5) * CELL, 12.5 * CELL),
				"axis": "h", "dir": 1.0, "width": DOOR_W * CELL,
			})
			windows.append({"rect": Rect2(r.position.x + 3 * CELL, (gh - 2) * CELL + 2.0, r.size.x - 6 * CELL, 16.0), "axis": "h"})
	stair_rects.append(rooms[2])
	exit_pos = _walkable_center(rooms[0], 0)
	_build_walls()
	_build_collision()
	_build_nav()
	_build_doors()
	_build_corridor_segments()
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
	room_roles.clear()
	room_depth.clear()
	safe_room_index = -1
	entry_room_index = -1
	boss_room_index = -1
	treasure_room_index = -1
	main_path_rooms.clear()
	desks.clear()
	decor_items.clear()
	big_items.clear()
	big_rects.clear()
	wall_rects.clear()
	doors.clear()
	windows.clear()
	stair_rects.clear()
	door_nodes.clear()
	closed_door_rects.clear()
	furniture = PackedByteArray()
	reserved = PackedByteArray()
	box_rects.clear()
	nested_room_index = -1
	nested_rect = Rect2()
	nested_parent = -1
	passage_rects.clear()
	passage_owner.clear()
	passage_other.clear()
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
	corridor_segments.clear()
	corridor_explored.clear()
	exploration_version += 1
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

## 计算房间的「纵深」并分配角色。
##
## 关键：深度必须与布局无关。这里用导航图（nav_points / nav_links）做多源 BFS，
## 而不是"房间中心到楼梯房的直线距离"——以后地图换成多走廊/环形/房间套房间/
## 多层结构时，这套算法不需要改。
##
## allow_safe=false 用于教学关：教学图小且需要确定性，不放安全屋。
func _compute_roles(allow_safe := true) -> void:
	room_roles.clear()
	room_depth.clear()
	room_roles.resize(rooms.size())
	room_roles.fill("normal")
	room_depth.resize(rooms.size())
	room_depth.fill(-1)
	safe_room_index = -1
	entry_room_index = -1
	boss_room_index = -1
	treasure_room_index = -1
	main_path_rooms.clear()
	if rooms.is_empty() or nav_points.is_empty():
		return

	# 起点：楼梯间（真正上楼的位置），没有就用大厅
	var anchor := room_types.find("stair")
	if anchor < 0:
		anchor = room_types.find("hall")
	if anchor < 0:
		anchor = 0

	# 多源 BFS：以"落在楼梯房内的所有导航点"为源
	var n := nav_points.size()
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var queue: PackedInt32Array = PackedInt32Array()
	for i in n:
		if room_index_at(nav_points[i]) == anchor:
			dist[i] = 0
			queue.append(i)
	if queue.is_empty():
		# 兜底：房内没有导航点时取最近的一个，避免整层没有深度
		var best := -1
		var bd := INF
		var ac := _walkable_center(rooms[anchor], anchor)
		for i in n:
			var d := nav_points[i].distance_to(ac)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			dist[best] = 0
			queue.append(best)

	var head := 0
	while head < queue.size():
		var pi := queue[head]
		head += 1
		for nb in nav_links[pi]:
			if nb >= 0 and nb < n and dist[nb] < 0:
				dist[nb] = dist[pi] + 1
				queue.append(nb)

	# 房间深度 = 房内导航点的最小 BFS 步数
	for i in n:
		var ri := room_index_at(nav_points[i])
		if ri < 0 or ri >= room_depth.size() or dist[i] < 0:
			continue
		if room_depth[ri] < 0 or dist[i] < room_depth[ri]:
			room_depth[ri] = dist[i]

	var maxd := 0
	for d in room_depth:
		maxd = maxi(maxd, d)
	if maxd <= 0:
		return

	for i in rooms.size():
		if room_types[i] == "stair":
			room_roles[i] = "stair"
		elif room_types[i] == "hall":
			room_roles[i] = "hall"
		elif room_depth[i] >= 0 and float(room_depth[i]) >= float(maxd) * 0.68:
			room_roles[i] = "deep"

	# E2：入口选离楼梯最远的房间，保证一局必须走完整张图
	var entry_i := -1
	var entry_d := -1
	for i in rooms.size():
		if room_roles[i] == "stair" or room_roles[i] == "hall":
			continue
		if room_depth[i] > entry_d:
			entry_d = room_depth[i]
			entry_i = i
	if entry_i >= 0:
		entry_room_index = entry_i
		if entry_i < explored.size():
			explored[entry_i] = true
		exit_pos = _walkable_center(rooms[entry_i], entry_i)

	# E3：沿导航图从入口往楼梯走下坡，记录主路房间（其余是支路）
	main_path_rooms = _trace_main_path(entry_i, n, dist)

	# E4：L4+ 的 Boss 房 = 除入口/楼梯/大厅/安全屋外最深的房间
	if GameState.level >= 4:
		var boss_i := -1
		var boss_d := -1
		for i in rooms.size():
			if room_roles[i] == "stair" or room_roles[i] == "hall" or i == entry_room_index:
				continue
			if i == nested_room_index:
				continue
			if room_depth[i] > boss_d:
				boss_d = room_depth[i]
				boss_i = i
		if boss_i >= 0:
			boss_room_index = boss_i
			room_roles[boss_i] = "boss"
			room_names[boss_i] = "Boss 房"

	if not allow_safe:
		return

	# 安全屋：从第 6 层起才启用；前五层不出现，保持基础关卡的压迫感
	if GameState.level >= SAFE_ROOM_MIN_LEVEL:
		var best := -1
		var best_score := 1.0e9
		for i in rooms.size():
			if room_roles[i] == "stair" or room_roles[i] == "hall" or i == entry_room_index or room_roles[i] == "boss":
				continue
			if i == nested_room_index:
				continue
			if room_depth[i] < 0:
				continue
			var r := float(room_depth[i]) / float(maxd)
			if r < 0.33 or r > 0.62:
				continue
			var score := absf(r - 0.47)
			if score < best_score:
				best_score = score
				best = i
		# 兜底：没有落在中段比率的房间时，取最接近 0.47 的那间，
		# 保证第 6 层起一定有安全屋（房间数少、套间占位时也能出）
		if best < 0:
			for i in rooms.size():
				if room_roles[i] == "stair" or room_roles[i] == "hall" or i == entry_room_index:
					continue
				if i == nested_room_index or room_roles[i] == "boss":
					continue
				if room_depth[i] <= 0:
					continue
				var r2 := float(room_depth[i]) / float(maxd)
				var score2 := absf(r2 - 0.47)
				if score2 < best_score:
					best_score = score2
					best = i
		if best >= 0:
			room_roles[best] = "safe"
			safe_room_index = best
			room_names[best] = "安全屋（禁止答题）"

	# 套间（里间）= 隐藏奖励：直接当宝箱房，不再按主路/深度挑
	if nested_room_index >= 0 and nested_room_index < rooms.size():
		treasure_room_index = nested_room_index
		room_roles[nested_room_index] = "treasure"
		room_names[nested_room_index] = "密室（宝箱）"
		return

	# E4：宝箱房 = 不在主路上的最深支路房
	var tre_i := -1
	var tre_d := -1
	for i in rooms.size():
		if room_roles[i] == "stair" or room_roles[i] == "hall" or i == entry_room_index or room_roles[i] == "safe" or room_roles[i] == "boss":
			continue
		if main_path_rooms.has(i):
			continue
		if room_depth[i] > tre_d:
			tre_d = room_depth[i]
			tre_i = i
	if tre_i < 0:
		for i in rooms.size():
			if room_roles[i] == "stair" or room_roles[i] == "hall" or i == entry_room_index or room_roles[i] == "safe" or room_roles[i] == "boss":
				continue
			tre_i = i
			break
	if tre_i >= 0:
		treasure_room_index = tre_i
		room_roles[tre_i] = "treasure"
		room_names[tre_i] = "宝箱房"

## E3：从入口房间的导航点出发，每次走 dist-1 的邻居，直到楼梯（dist=0）。
func _trace_main_path(start_room: int, n: int, dist: PackedInt32Array) -> Array[int]:
	var out: Array[int] = []
	if start_room < 0 or n <= 0:
		return out
	var cur := -1
	var cur_d := -1
	for pi in n:
		if room_index_at(nav_points[pi]) == start_room and dist[pi] > cur_d:
			cur_d = dist[pi]
			cur = pi
	var guard := 0
	while cur >= 0 and guard < n + 4:
		guard += 1
		var ri := room_index_at(nav_points[cur])
		if ri >= 0 and not out.has(ri):
			out.append(ri)
		if dist[cur] <= 0:
			break
		var next := -1
		for nb in nav_links[cur]:
			if nb >= 0 and nb < n and dist[nb] == dist[cur] - 1:
				next = nb
				break
		cur = next
	return out

## 房间出入口数量。现在每个房间只有 1 个门，所以都是 1；
## 以后做"房间互通门 / 环形地图"时，这个函数直接可用（>=2 表示可绕圈）。
func room_door_count(i: int) -> int:
	if i < 0 or i >= rooms.size():
		return 0
	var near := rooms[i].grow(CELL * 1.5)
	var count := 0
	for d in doors:
		var p: Vector2 = d["pos"]
		if near.has_point(p) and not rooms[i].has_point(p):
			count += 1
	return count

func room_role_at(pos: Vector2) -> String:
	var i := room_index_at(pos)
	if i < 0 or i >= room_roles.size():
		return ""
	return room_roles[i]

## E3：该房间是否在入口→楼梯的主路上。
func is_main_path(i: int) -> bool:
	return main_path_rooms.has(i)

func is_safe_room_at(pos: Vector2) -> bool:
	return safe_room_index >= 0 and room_index_at(pos) == safe_room_index

## 安全屋不能做题：给学生一个"喘息点"，但代价是不能刷题
func study_allowed_at(pos: Vector2) -> bool:
	return not is_safe_room_at(pos)

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

## 保底房型：每层至少各 1 间。hall / stair 是骨架，不许被顶掉。
func _ensure_floor_types(north: Array[String], south: Array[String], tail: Array[String]) -> void:
	_ensure_one_of(north, south, tail, "classroom")
	_ensure_one_of(north, south, tail, "toilet")

func _ensure_one_of(north: Array[String], south: Array[String], tail: Array[String], want: String) -> void:
	var groups: Array = [north, south, tail]
	for g in groups:
		if g.has(want):
			return
	var slots: Array = []
	for g in groups:
		for j in g.size():
			var cur: String = String(g[j])
			if cur != "hall" and cur != "stair":
				slots.append([g, j])
	if slots.is_empty():
		return
	var s: Array = slots[rng.randi_range(0, slots.size() - 1)]
	s[0][s[1]] = want

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

## 套间（里间）：挑一间够大的南北向房间，在里面掏一个独立小房间，
## 只留一道 2 格宽的开口；里间会作为独立房间追加到 rooms/doors 末尾
## （两个数组必须等长且同序，_build_nav 按索引取 doors[i]）。
func _carve_nested_room() -> void:
	if rooms.size() < 7:
		return
	if rng.randf() > 0.65:
		return
	var best := -1
	var best_area := 0
	for i in rooms.size():
		var t: String = room_types[i]
		if t == "hall" or t == "stair":
			continue
		if i >= doors.size() or String(doors[i].get("axis", "h")) != "h":
			continue
		var rr: Rect2 = rooms[i]
		var cw0 := int(round(rr.size.x / CELL))
		var ch0 := int(round(rr.size.y / CELL))
		if cw0 < 22 or ch0 < 16:
			continue
		var area := cw0 * ch0
		if area > best_area:
			best_area = area
			best = i
	if best < 0:
		return

	var r: Rect2 = rooms[best]
	var rx := int(round(r.position.x / CELL))
	var ry := int(round(r.position.y / CELL))
	var cw := int(round(r.size.x / CELL))
	var ch := int(round(r.size.y / CELL))
	var wi := clampi(int(round(cw / 3.0)), 8, 14)
	var hi := clampi(int(round(ch / 2.0)), 6, 11)
	wi = mini(wi, cw - 4)
	hi = mini(hi, ch - 5)
	if wi < 7 or hi < 5:
		return

	var ix := rx + int((cw - wi) / 2)
	var door_dir := float(doors[best].get("dir", -1.0))
	# 门在房间下墙（dir=-1）→ 里间贴上部；门在上墙（dir=1）→ 里间贴下部
	var iy := ry + 1
	var open_below := true
	if door_dir > 0.0:
		iy = ry + ch - 1 - hi
		open_below = false
	if ix - 1 < 0 or iy - 1 < 0 or ix + wi >= gw or iy + hi >= gh:
		return

	# 先把里间连外墙一起填实心，再掏里间地板 + 开口
	for y in range(iy - 1, iy + hi + 1):
		for x in range(ix - 1, ix + wi + 1):
			grid[y * gw + x] = SOLID
			_room_cell[y * gw + x] = -1
	for y in range(iy, iy + hi):
		for x in range(ix, ix + wi):
			grid[y * gw + x] = FLOOR
	var ox := ix + 1 + rng.randi_range(0, maxi(0, wi - 3))
	var oy := iy + hi if open_below else iy - 1
	for k in DOOR_W:
		grid[oy * gw + ox + k] = FLOOR
		_room_cell[oy * gw + ox + k] = -1

	var idx := rooms.size()
	var inner := Rect2(ix * CELL, iy * CELL, wi * CELL, hi * CELL)
	rooms.append(inner)
	var itype := _pick_nested_type()
	room_types.append(itype)
	room_names.append(String(type_defs[itype]["name"]))
	explored.append(false)
	for y in range(iy, iy + hi):
		for x in range(ix, ix + wi):
			_room_cell[y * gw + x] = idx
	nested_room_index = idx
	nested_rect = inner
	nested_parent = best
	doors.append({
		"pos": Vector2((ox + DOOR_W * 0.5) * CELL, (oy + 0.5) * CELL),
		"axis": "h",
		"dir": -1.0 if open_below else 1.0,
		"width": DOOR_W * CELL,
	})

func _pick_nested_type() -> String:
	var pool: Array[String] = ["storage", "library", "office", "lab", "medical", "broadcast", "classroom"]
	return pool[rng.randi_range(0, pool.size() - 1)]

## 环路：同排相邻两间房之间多开一道 2 格通道（不新增房间，只多一条逃生路线）。
func _carve_loop_passage() -> void:
	if rooms.size() < 8:
		return
	if rng.randf() > 0.5:
		return
	var pairs: Array = []
	for i in rooms.size():
		if room_types[i] == "hall" or i == nested_room_index:
			continue
		for j in range(i + 1, rooms.size()):
			if room_types[j] == "hall" or j == nested_room_index:
				continue
			var a: Rect2 = rooms[i]
			var b: Rect2 = rooms[j]
			if absf(a.position.y - b.position.y) > 1.0 or absf(a.size.y - b.size.y) > 1.0:
				continue
			var gap := b.position.x - a.end.x
			if gap < CELL - 1.0 or gap > CELL + 1.0:
				continue
			if a.size.x < CELL * 12.0 or b.size.x < CELL * 12.0:
				continue
			pairs.append([i, j])
	if pairs.is_empty():
		return
	var pair: Array = pairs[rng.randi_range(0, pairs.size() - 1)]
	var ia := int(pair[0])
	var ib := int(pair[1])
	var ra: Rect2 = rooms[ia]
	var wall_x := int(round(ra.end.x / CELL))
	var y0 := int(round(ra.position.y / CELL)) + 2
	var y1 := int(round(ra.end.y / CELL)) - 3
	if y1 - y0 < 4:
		return
	var gy := rng.randi_range(y0, y1)
	for k in DOOR_W + 2:
		var cy := gy - 1 + k
		if wall_x < 0 or cy < 0 or wall_x >= gw or cy >= gh:
			return
		if grid[cy * gw + wall_x] == FLOOR:
			return
	for k in DOOR_W:
		var cy2 := gy + k
		grid[cy2 * gw + wall_x] = FLOOR
		# 门洞地面跟着 A 房的地板图案走，不像走廊
		_room_cell[cy2 * gw + wall_x] = ia
	passage_rects.append(Rect2(wall_x * CELL, gy * CELL, CELL, DOOR_W * CELL))
	passage_owner.append(ia)
	passage_other.append(ib)

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
	var c := int(CELL)
	var slots := TYPE_ORDER.size() + 1  # +走廊
	var cols := maxi(slots * FLOOR_VARIANTS, slots * 16) + 1  # +1 列纯黑实心砖
	var solid_col := cols - 1
	var img := Image.create(cols * c, c * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.13, 0.16))

	# 第 0 行：地板（每个房型 FLOOR_VARIANTS 种图案）
	for i in TYPE_ORDER.size():
		var base: Color = type_defs[TYPE_ORDER[i]]["color"]
		var pat := _floor_pat(TYPE_ORDER[i])
		for v in FLOOR_VARIANTS:
			_paint_floor_tile(img, i * FLOOR_VARIANTS + v, 0, base, v, level_seed + i * 977 + v * 31)
	for v in FLOOR_VARIANTS:
		_paint_floor_tile(img, TYPE_ORDER.size() * FLOOR_VARIANTS + v, 0, CORRIDOR_COLOR, v, level_seed + 4242 + v * 31)
	# 走廊没被选中的图案位也填上走廊色，避免取到黑格
	for cx in range(TYPE_ORDER.size() * FLOOR_VARIANTS + FLOOR_VARIANTS, cols):
		img.fill_rect(Rect2i(cx * c, 0, c, c), CORRIDOR_COLOR)

	# 第 1 行：墙砖（每个房型 16 种邻接遮罩）
	for i in slots:
		var wb: Color = type_defs[TYPE_ORDER[i]]["wall"] if i < TYPE_ORDER.size() else CORRIDOR_WALL
		for mask in 16:
			_paint_wall_tile(img, i * 16 + mask, 1, wb, mask)

	var ts := TileSet.new()
	ts.tile_size = Vector2i(c, c)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(c, c)
	for row in 2:
		for cx in range(cols):
			src.create_tile(Vector2i(cx, row))
	ts.add_source(src, 0)

	var holder := Node2D.new()
	holder.name = "Tiles"
	holder.z_index = -8
	add_child(holder)

	_floor_layer = TileMapLayer.new()
	_floor_layer.name = "FloorLayer"
	_floor_layer.tile_set = ts
	_floor_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor_layer.z_index = 0
	holder.add_child(_floor_layer)

	var shadow := WallShadow.new()
	shadow.name = "WallShadow"
	shadow.rects = wall_rects
	shadow.z_index = 1
	holder.add_child(shadow)
	shadow.queue_redraw()

	_wall_layer = TileMapLayer.new()
	_wall_layer.name = "WallLayer"
	_wall_layer.tile_set = ts
	_wall_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_wall_layer.z_index = 2
	holder.add_child(_wall_layer)

	var type_index := {}
	for i in TYPE_ORDER.size():
		type_index[TYPE_ORDER[i]] = i
	var corridor_slot := TYPE_ORDER.size()
	for y in gh:
		for x in gw:
			var i := y * gw + x
			var cell := Vector2i(x, y)
			if grid[i] != FLOOR:
				_wall_layer.set_cell(cell, 0, Vector2i(solid_col, 1))
				continue
			var ri := _room_cell[i]
			var slot := corridor_slot
			if ri >= 0:
				slot = int(type_index[room_types[ri]])
			var pat := _floor_pat(TYPE_ORDER[slot] if slot < TYPE_ORDER.size() else CORRIDOR_TYPE)
			var h := (x * 73856093) ^ (y * 19349663) ^ (level_seed * 83492791) ^ (slot * 668265263)
			h = h & 0x7fffffff
			var v: int = int(pat[h % pat.size()])
			_floor_layer.set_cell(cell, 0, Vector2i(slot * FLOOR_VARIANTS + v, 0))
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
				var wslot := _wall_slot_at(x, y, type_index, corridor_slot)
				_wall_layer.set_cell(Vector2i(x, y), 0, Vector2i(wslot * 16 + mask, 1))

## 每种房型允许的地板图案（见 FLOOR_VARIANTS 注释）。
func _floor_pat(t: String) -> Array:
	match t:
		"classroom", "library":
			return [2, 2, 3, 4, 5]
		"lab", "medical", "office", "toilet":
			return [0, 0, 1, 3, 4]
		"storage", "broadcast":
			return [1, 3, 4, 5]
		"stair":
			return [1, 3, 5]
		"hall":
			return [0, 2, 3, 4]
	return [0, 1, 3, 4]

func _paint_floor_tile(img: Image, col: int, row: int, base: Color, variant: int, seed_v: int) -> void:
	var c := int(CELL)
	var ox := col * c
	var oy := row * c
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	match variant:
		0:  # 棋格瓷砖
			var alt := base.darkened(0.07)
			for gy in 2:
				for gx in 2:
					var shade: Color = base if (gx + gy) % 2 == 0 else alt
					img.fill_rect(Rect2i(ox + gx * c / 2, oy + gy * c / 2, c / 2, c / 2), shade)
			img.fill_rect(Rect2i(ox, oy + c / 2 - 1, c, 2), base.darkened(0.20))
			img.fill_rect(Rect2i(ox + c / 2 - 1, oy, 2, c), base.darkened(0.20))
		1:  # 砖墙/小方砖
			img.fill_rect(Rect2i(ox, oy, c, c), base)
			var mortar := base.darkened(0.24)
			var bh := c / 4
			for k in range(1, 4):
				img.fill_rect(Rect2i(ox, oy + k * bh - 1, c, 2), mortar)
			for k in 4:
				var off := 0 if k % 2 == 0 else c / 2
				for b in 2:
					var sx := ox + off + b * (c / 2)
					if sx > ox and sx < ox + c:
						img.fill_rect(Rect2i(sx, oy + k * bh, 1, bh), mortar)
		2:  # 木地板
			var ph := c / 4
			for k in 4:
				var shade: Color = base.lightened(0.05) if k % 2 == 0 else base.darkened(0.05)
				img.fill_rect(Rect2i(ox, oy + k * ph, c, ph), shade)
			for k in range(1, 4):
				img.fill_rect(Rect2i(ox, oy + k * ph - 1, c, 1), base.darkened(0.30))
			for k in 2:
				var sx := ox + int(r.randi_range(4, c - 5))
				var sy := oy + (k * 2 + (1 if k == 1 else 0)) * ph
				if sy + ph * 2 <= oy + c:
					img.fill_rect(Rect2i(sx, sy, 1, ph * 2), base.darkened(0.26))
		3:  # 纯色 + 细噪点
			img.fill_rect(Rect2i(ox, oy, c, c), base)
			for n in 14:
				var px := int(r.randi_range(0, c - 1))
				var py := int(r.randi_range(0, c - 1))
				img.set_pixel(ox + px, oy + py, base.darkened(0.11))
		4:  # 污渍/水渍
			img.fill_rect(Rect2i(ox, oy, c, c), base)
			var cx := r.randf_range(5.0, float(c) - 5.0)
			var cy := r.randf_range(5.0, float(c) - 5.0)
			var rx := r.randf_range(3.5, 8.0)
			var ry := rx * r.randf_range(0.5, 0.9)
			for y in c:
				for x in c:
					var dx := (float(x) - cx) / rx
					var dy := (float(y) - cy) / ry
					if dx * dx + dy * dy <= 1.0:
						img.set_pixel(ox + x, oy + y, base.darkened(0.17))
		5:  # 裂纹
			img.fill_rect(Rect2i(ox, oy, c, c), base)
			var px := r.randf_range(3.0, float(c) - 3.0)
			var crack := base.darkened(0.36)
			for y in c:
				px = clampf(px + r.randf_range(-2.2, 2.2), 1.0, float(c) - 2.0)
				if y > 3 and r.randf() < 0.18:
					continue
				img.set_pixel(ox + int(px), oy + y, crack)

func _paint_wall_tile(img: Image, col: int, row: int, base: Color, mask: int) -> void:
	var c := int(CELL)
	var ox := col * c
	var oy := row * c
	img.fill_rect(Rect2i(ox, oy, c, c), base)
	var mortar := base.darkened(0.17)
	var bh := c / 4
	for k in range(1, 4):
		img.fill_rect(Rect2i(ox, oy + k * bh - 1, c, 1), mortar)
	for k in 4:
		var off := 0 if k % 2 == 0 else c / 2
		var sx := ox + off + c / 2
		if sx < ox + c:
			img.fill_rect(Rect2i(sx, oy + k * bh, 1, bh), mortar)
	if mask & 1 == 0:
		img.fill_rect(Rect2i(ox, oy, c, 1), WALL_EDGE_COLOR)
		img.fill_rect(Rect2i(ox + 1, oy + 1, c - 2, 2), WALL_TOP_COLOR)
	if mask & 2 == 0:
		img.fill_rect(Rect2i(ox + c - 1, oy, 1, c), WALL_EDGE_COLOR)
	if mask & 4 == 0:
		img.fill_rect(Rect2i(ox, oy + c - 1, c, 1), WALL_EDGE_COLOR)
	if mask & 8 == 0:
		img.fill_rect(Rect2i(ox, oy, 1, c), WALL_EDGE_COLOR)

## 墙格属于哪一侧：优先取相邻地板所属房型，否则用走廊色。
func _wall_slot_at(x: int, y: int, tindex: Dictionary, corr_slot: int) -> int:
	var offs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for o in offs:
		var nx: int = x + o.x
		var ny: int = y + o.y
		if nx < 0 or ny < 0 or nx >= gw or ny >= gh:
			continue
		var i := ny * gw + nx
		if grid[i] != FLOOR:
			continue
		var ri := _room_cell[i]
		if ri >= 0 and tindex.has(room_types[ri]):
			return int(tindex[room_types[ri]])
		return corr_slot
	return corr_slot

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
		var c := _walkable_center(rooms[i], i)
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

	# 大件优先占位（挡路的先定），课桌/箱子再绕开它们
	big_items.clear()
	big_rects.clear()
	_spawn_big_items()

	for i in rooms.size():
		var t := room_types[i]
		var eff: float = type_defs[t]["eff"]
		var role: String = room_roles[i] if i < room_roles.size() else "normal"
		# 风险梯度：越深收益越高、大厅更安全、安全屋不摆课桌
		match role:
			"deep":
				eff *= 1.35
			"hall":
				eff *= 0.8
			"safe":
				eff = 0.0
		var count := 0
		if role != "safe":
			# 课桌按房间面积配（分母越小越密），大教室自然摆得更多
			var dens: float = float(type_defs[t].get("desk", 999.0))
			var room_rect: Rect2 = rooms[i]
			var area_cells := int(room_rect.size.x / CELL) * int(room_rect.size.y / CELL)
			count = clampi(int(float(area_cells) / dens), 0, 14)
			if t == "toilet":
				count = 1
			if count == 0 and dens < 900.0:
				count = 1
		if role == "safe":
			count = 0
		for j in count:
			var rect := _pick_desk_rect(i, t == "hall")
			if rect.size.x <= 0.0:
				break
			_mark_furniture(rect)
			desks.append({"pos": rect.get_center(), "rect": rect, "room": i, "efficiency": eff, "occupied": false})
		if t == "storage":
			for j in rng.randi_range(3, 6):
				var br := _pick_box_rect(i)
				if br.size.x <= 0.0:
					break
				_mark_furniture(br)
				box_rects.append(br)
	_build_box_collision()
	_spawn_decor()

## 房型专属大件（贴图家具）：靠墙摆放，solid 的挡路并参与碰撞。
## 房间不够大就自动少放；摆放位置用确定性 rng，失败会重试几次。
func _spawn_big_items() -> void:
	for i in rooms.size():
		var t := String(room_types[i])
		var role: String = room_roles[i] if i < room_roles.size() else "normal"
		if role == "safe" or t == "stair":
			continue
		var r: Rect2 = rooms[i]
		var cells_w := int(round(r.size.x / CELL))
		var cells_h := int(round(r.size.y / CELL))
		for def in _big_plan(t):
			var wc := int(def.get("w", 2))
			var hc := int(def.get("h", 2))
			if bool(def.get("decal", false)):
				hc = 1
			if cells_w < wc + 2 or cells_h < hc + 2:
				continue
			var count := int(def.get("count", 1))
			for k in count:
				for attempt in 8:
					if _place_big(i, def):
						break

## 每种房型的大件清单：sprite=贴图名、w/h=占格数、side=靠哪面墙(n/s/w/e/c=居中)、
## count=数量、decal=贴墙装饰(不挡路)、floor=贴地件(地毯，画在最底层)。
## 贴图真实图案（见 art/furniture/README.md）：
##   shelf_*=书架、cab_*=双门衣柜/柜、locker=木梯、stool_*=小木桌、desk_office2=素面木桌、
##   chair_*=桌子、desk_small=小桌、crate_stack=点唱机/机器、wardrobe=布帘隔间、
##   plant_*/barrel/canister/box_*=盆栽、poster_c=风景画、poster_d/fence/clock=空画框、
##   rug_*=地毯、bed_*=病床、bed_head=床头板。
func _big_plan(t: String) -> Array:
	match t:
		"classroom":
			return [
				{"sprite": "shelf_tall", "w": 2, "h": 3, "side": "w", "count": 1},
				{"sprite": "shelf_wide", "w": 3, "h": 2, "side": "s", "count": 1},
				{"sprite": "stool_b", "w": 1, "h": 1, "side": "n", "count": 1},
				{"sprite": "poster_c", "w": 2, "h": 1, "side": "n", "decal": true, "solid": false},
			]
		"lab":
			return [
				{"sprite": "desk_office2", "w": 3, "h": 2, "side": "n", "count": 1},
				{"sprite": "desk_small", "w": 2, "h": 1, "side": "s", "count": 2},
				{"sprite": "locker", "w": 2, "h": 3, "side": "e", "count": 1},
				{"sprite": "crate_stack", "w": 1, "h": 2, "side": "w", "count": 1},
				{"sprite": "plant_pot", "w": 1, "h": 1, "side": "w", "count": 1},
				{"sprite": "poster_c", "w": 2, "h": 1, "side": "s", "decal": true, "solid": false},
			]
		"library":
			return [
				{"sprite": "shelf_tall", "w": 2, "h": 3, "side": "w", "count": 1},
				{"sprite": "shelf_tall", "w": 2, "h": 3, "side": "e", "count": 1},
				{"sprite": "shelf_wide", "w": 3, "h": 2, "side": "n", "count": 1},
				{"sprite": "stool_a", "w": 1, "h": 1, "side": "s", "count": 2},
				{"sprite": "rug_b", "w": 4, "h": 3, "side": "c", "floor": true, "solid": false},
				{"sprite": "poster_d", "w": 1, "h": 2, "side": "s", "decal": true, "solid": false},
			]
		"medical":
			return [
				{"sprite": "bed_a", "w": 2, "h": 2, "side": "w", "count": 1},
				{"sprite": "bed_b", "w": 2, "h": 2, "side": "e", "count": 1},
				{"sprite": "bed_head", "w": 1, "h": 2, "side": "n", "count": 2},
				{"sprite": "wardrobe", "w": 2, "h": 2, "side": "s", "count": 1},
				{"sprite": "cab_mid", "w": 2, "h": 2, "side": "s", "count": 1},
				{"sprite": "plant_pot2", "w": 1, "h": 1, "side": "n", "count": 1},
				{"sprite": "fence", "w": 1, "h": 1, "side": "n", "decal": true, "solid": false},
			]
		"office":
			return [
				{"sprite": "desk_office2", "w": 3, "h": 3, "side": "w", "count": 1},
				{"sprite": "chair_a", "w": 2, "h": 2, "side": "e", "count": 1},
				{"sprite": "cab_tall", "w": 2, "h": 3, "side": "n", "count": 1},
				{"sprite": "chair_b", "w": 2, "h": 2, "side": "s", "count": 1},
				{"sprite": "poster_c", "w": 2, "h": 1, "side": "s", "decal": true, "solid": false},
			]
		"storage":
			return [
				{"sprite": "cab_mid", "w": 2, "h": 2, "side": "w", "count": 1},
				{"sprite": "cab_short", "w": 2, "h": 2, "side": "e", "count": 1},
				{"sprite": "locker", "w": 2, "h": 3, "side": "n", "count": 1},
				{"sprite": "shelf_tall", "w": 2, "h": 3, "side": "s", "count": 1},
				{"sprite": "stool_a", "w": 1, "h": 1, "side": "s", "count": 2},
				{"sprite": "rug_d", "w": 3, "h": 2, "side": "c", "floor": true, "solid": false},
				{"sprite": "fence", "w": 1, "h": 1, "side": "n", "decal": true, "solid": false},
			]
		"broadcast":
			return [
				{"sprite": "crate_stack", "w": 1, "h": 2, "side": "n", "count": 1},
				{"sprite": "desk_office2", "w": 3, "h": 2, "side": "s", "count": 1},
				{"sprite": "wardrobe2", "w": 2, "h": 2, "side": "e", "count": 1},
				{"sprite": "shelf_tall", "w": 2, "h": 3, "side": "w", "count": 1},
				{"sprite": "clock", "w": 1, "h": 1, "side": "s", "decal": true, "solid": false},
			]
		"toilet":
			return [
				{"sprite": "cab_mid", "w": 2, "h": 2, "side": "w", "count": 1},
				{"sprite": "cab_short", "w": 2, "h": 2, "side": "e", "count": 1},
				{"sprite": "stool_b", "w": 1, "h": 1, "side": "n", "count": 1},
				{"sprite": "poster_d", "w": 1, "h": 1, "side": "s", "decal": true, "solid": false},
			]
		"hall":
			return [
				{"sprite": "plant_pot", "w": 1, "h": 1, "side": "e", "count": 2},
				{"sprite": "plant_pot2", "w": 1, "h": 1, "side": "w", "count": 1},
				{"sprite": "poster_d", "w": 1, "h": 2, "side": "s", "decal": true, "solid": false},
				{"sprite": "rug_a", "w": 4, "h": 3, "side": "c", "floor": true, "solid": false},
			]
	return []

func _place_big(room_idx: int, def: Dictionary) -> bool:
	var r: Rect2 = rooms[room_idx]
	var wc := int(def.get("w", 2))
	var hc := int(def.get("h", 2))
	var side := String(def.get("side", "n"))
	var decal := bool(def.get("decal", false))
	var floor_item := bool(def.get("floor", false))
	var solid := bool(def.get("solid", not (decal or floor_item))) and not decal and not floor_item
	var x0 := int(round(r.position.x / CELL))
	var y0 := int(round(r.position.y / CELL))
	var cw := int(round(r.size.x / CELL))
	var ch := int(round(r.size.y / CELL))
	var rect := Rect2()
	if decal:
		# 墙饰优先放指定那面墙，被门/窗挡了就换面，实在没地方就放弃
		var sides := [side, "n", "s", "w", "e"]
		var ok := false
		for s in sides:
			rect = _decal_rect(r, String(s), wc, hc)
			if _decal_ok(rect):
				ok = true
				break
		if not ok:
			return false
	else:
		var cx := x0
		var cy := y0
		if floor_item or side == "c":
			cx = x0 + int((cw - wc) / 2.0)
			cy = y0 + int((ch - hc) / 2.0)
			# 贴地件（地毯）不挡路：只要格子是地板、没被实心家具占了就行，
			# 导航点/门的预留格可以压过去（导航点只是 AI 路点，不影响画面）。
			if not _cells_free_floor(cx, cy, wc, hc, room_idx):
				return false
		else:
			match side:
				"n":
					cy = y0
					cx = x0 + rng.randi_range(0, maxi(0, cw - wc))
				"s":
					cy = y0 + maxi(0, ch - hc)
					cx = x0 + rng.randi_range(0, maxi(0, cw - wc))
				"w":
					cx = x0
					cy = y0 + rng.randi_range(0, maxi(0, ch - hc))
				"e":
					cx = x0 + maxi(0, cw - wc)
					cy = y0 + rng.randi_range(0, maxi(0, ch - hc))
			if not _cells_free(cx, cy, wc, hc, room_idx):
				return false
		rect = Rect2(cx * CELL, cy * CELL, wc * CELL, hc * CELL)
	big_items.append({
		"sprite": String(def.get("sprite", "")),
		"rect": rect,
		"room": room_idx,
		"solid": solid,
		"decal": decal,
		"floor": floor_item,
	})
	if solid:
		big_rects.append(rect)
		_mark_furniture(rect)
	return true

## 贴墙装饰的矩形：压在墙那一侧，不占可行走格。
func _decal_rect(r: Rect2, side: String, wc: int, hc: int) -> Rect2:
	var w := wc * CELL
	match side:
		"s":
			return Rect2(r.position.x + (r.size.x - w) * 0.5, r.end.y - CELL * 0.62, w, CELL * 1.25)
		"w":
			return Rect2(r.position.x - CELL * 0.62, r.position.y + (r.size.y - hc * CELL) * 0.5, CELL * 1.25, hc * CELL)
		"e":
			return Rect2(r.end.x - CELL * 0.63, r.position.y + (r.size.y - hc * CELL) * 0.5, CELL * 1.25, hc * CELL)
	return Rect2(r.position.x + (r.size.x - w) * 0.5, r.position.y - CELL * 0.62, w, CELL * 1.25)

## 装饰不能压到门和窗。
func _decal_ok(rect: Rect2) -> bool:
	for d in doors:
		if rect.grow(CELL * 0.8).has_point(d["pos"]):
			return false
	for w in windows:
		if rect.grow(2.0).intersects(w["rect"]):
			return false
	return true

func _big_texture(name: String) -> Texture2D:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var tex: Texture2D = null
	var path := "res://art/furniture/%s.png" % name
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[name] = tex
	return tex

## 贴地件（地毯）：画在最底层，压在地板上、被所有东西盖住。
func _draw_big_floor() -> void:
	for it in big_items:
		if not bool(it.get("floor", false)):
			continue
		_draw_big_one(it, Color(0.94, 0.95, 1.0, 0.92))

## 实体大件 + 贴墙装饰。
func _draw_big() -> void:
	var tint := Color(0.90, 0.93, 1.0, 1.0)
	for it in big_items:
		if bool(it.get("floor", false)) or bool(it.get("decal", false)):
			continue
		var rect: Rect2 = it["rect"]
		draw_rect(Rect2(rect.position + Vector2(2.0, 3.0), rect.size), Color(0.0, 0.0, 0.0, 0.14))
		_draw_big_one(it, tint)
	for it in big_items:
		if bool(it.get("decal", false)):
			_draw_big_one(it, Color(0.96, 0.97, 1.0, 0.95))

func _draw_big_one(it: Dictionary, tint: Color) -> void:
	var tex := _big_texture(String(it.get("sprite", "")))
	var rect: Rect2 = it["rect"]
	if tex != null:
		draw_texture_rect(tex, rect, false, tint)
	else:
		draw_rect(rect, Color(0.62, 0.66, 0.74, 0.9))
		draw_rect(rect, Color(0.36, 0.40, 0.48), false, 1.5)

func _pick_desk_rect(room_i: int, avoid_center: bool) -> Rect2:
	var r: Rect2 = rooms[room_i]
	var x0 := int(round(r.position.x / CELL)) + 1
	var x1 := int(round(r.end.x / CELL)) - 1
	var y0 := int(round(r.position.y / CELL)) + 1
	var y1 := int(round(r.end.y / CELL)) - 1
	if x1 - x0 < 2 or y1 - y0 < 1:
		return Rect2()
	for attempt in 160:
		var cx := rng.randi_range(x0, x1 - 2)
		var cy := rng.randi_range(y0, y1 - 1)
		if not _cells_free(cx, cy, 2, 1, room_i):
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
			for br in big_rects:
				if rect.grow(CELL * 0.5).intersects(br):
					ok = false
					break
		if ok:
			return rect
	return Rect2()

func _pick_box_rect(room_i: int) -> Rect2:
	var r: Rect2 = rooms[room_i]
	var x0 := int(round(r.position.x / CELL)) + 1
	var x1 := int(round(r.end.x / CELL)) - 1
	var y0 := int(round(r.position.y / CELL)) + 1
	var y1 := int(round(r.end.y / CELL)) - 1
	if x1 - x0 < 1 or y1 - y0 < 1:
		return Rect2()
	for attempt in 60:
		var cx := rng.randi_range(x0, x1 - 1)
		var cy := rng.randi_range(y0, y1 - 1)
		if not _cells_free(cx, cy, 1, 1, room_i):
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
			for br in big_rects:
				if rect.grow(CELL * 0.25).intersects(br):
					ok = false
					break
		if ok:
			return rect
	return Rect2()

## B11：每房 6~10 个纯装饰（不参与碰撞），靠墙优先，避开课桌/门/导航点/房间名。
## 位置在生成期用确定性 rng 选好，存进 decor_items，_draw 只负责画。
func _spawn_decor() -> void:
	decor_items.clear()
	for i in rooms.size():
		var r: Rect2 = rooms[i]
		var t: String = room_types[i]
		if t == "stair":
			continue
		if r.size.x < 50.0 or r.size.y < 40.0:
			continue
		var target := _decor_target(t, r)
		if target <= 0:
			continue
		var x0 := int(round(r.position.x / CELL)) + 1
		var x1 := int(round(r.end.x / CELL)) - 1
		var y0 := int(round(r.position.y / CELL)) + 1
		var y1 := int(round(r.end.y / CELL)) - 1
		if x1 - x0 < 2 or y1 - y0 < 1:
			continue
		var kinds: Array[String] = _decor_kinds(t)
		var placed := 0
		var attempts := 0
		while placed < target and attempts < 320:
			attempts += 1
			var cx := rng.randi_range(x0, x1 - 1)
			var cy := rng.randi_range(y0, y1 - 1)
			var edge := cx <= x0 + 1 or cx >= x1 - 2 or cy <= y0 + 1 or cy >= y1 - 2
			if not edge:
				continue
			if not _cells_free(cx, cy, 1, 1):
				continue
			var center := Vector2((float(cx) + 0.5) * CELL, (float(cy) + 0.5) * CELL)
			# 房间名在左上角，避开一块 120x64 的标签区
			if center.x < r.position.x + 120.0 and center.y < r.position.y + 64.0:
				continue
			# 教室黑板在顶部中央，别把海报压上去
			if center.y < r.position.y + 30.0 and absf(center.x - r.get_center().x) < r.size.x * 0.32:
				continue
			var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			var jitter := Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-2.0, 2.0))
			decor_items.append({
				"kind": kind,
				"pos": center + jitter,
				"room": i,
				"flip": rng.randf() < 0.5,
			})
			placed += 1
	queue_redraw()

func _decor_target(t: String, r: Rect2) -> int:
	var base := 8
	match t:
		"classroom":
			base = 10
		"lab", "library", "medical", "office":
			base = 9
		"storage", "hall":
			base = 8
		"toilet", "broadcast":
			base = 6
	var area := r.size.x * r.size.y
	if area > 30000.0:
		base += 2
	elif area < 8000.0:
		base -= 2
	return clampi(base, 4, 12)

func _decor_kinds(t: String) -> Array[String]:
	match t:
		"classroom":
			return ["poster", "bin", "books", "paper", "chair", "chalk"]
		"lab":
			return ["poster", "bin", "paper", "puddle", "books"]
		"library":
			return ["books", "paper", "chair", "poster"]
		"medical":
			return ["paper", "bin", "poster", "puddle"]
		"office":
			return ["poster", "bin", "books", "paper"]
		"storage":
			return ["bin", "books", "paper", "chair"]
		"broadcast":
			return ["paper", "bin", "books"]
		"hall":
			return ["poster", "bin", "chair", "paper"]
		"toilet":
			return ["bin", "paper", "puddle"]
	return ["paper"]

func _draw_decor() -> void:
	for d in decor_items:
		var p: Vector2 = d["pos"]
		var flip: bool = d["flip"]
		var f := -1.0 if flip else 1.0
		match String(d["kind"]):
			"poster":
				_decor_poster(p, f)
			"bin":
				_decor_bin(p)
			"books":
				_decor_books(p, f)
			"paper":
				_decor_paper(p, f)
			"chair":
				_decor_chair(p, f)
			"puddle":
				_decor_puddle(p)
			"chalk":
				_decor_chalk(p, f)

## 粉笔灰/碎粉笔头：纯地面小件，不挡路
func _decor_chalk(p: Vector2, f: float) -> void:
	for k in 3:
		var off := Vector2(-5.0 * f + float(k) * 4.0 * f, float(k) * 1.6 - 1.0)
		var w := 4.0 - float(k) * 0.6
		draw_rect(Rect2(p + off, Vector2(w, 1.6)), Color(0.96, 0.96, 0.93, 0.9))
	draw_circle(p + Vector2(3.0 * f, 2.0), 3.0, Color(0.93, 0.93, 0.90, 0.28))

func _decor_poster(p: Vector2, f: float) -> void:
	var w := 10.0
	var h := 14.0
	var r := Rect2(p - Vector2(w * 0.5, h), Vector2(w, h))
	draw_rect(Rect2(r.position + Vector2(1.0, 1.5), r.size), Color(0.0, 0.0, 0.0, 0.12))
	draw_rect(r, Color(0.90, 0.86, 0.70))
	draw_rect(r, Color(0.35, 0.28, 0.20), false, 1.0)
	draw_rect(Rect2(r.position + Vector2(2.0, 3.0), Vector2(w - 4.0, 2.0)), Color(0.62, 0.32, 0.28))
	draw_rect(Rect2(r.position + Vector2(2.0, 7.0), Vector2(w - 4.0, 1.0)), Color(0.40, 0.38, 0.34, 0.8))
	draw_rect(Rect2(r.position + Vector2(2.0, 10.0), Vector2(w - 6.0, 1.0)), Color(0.40, 0.38, 0.34, 0.6))
	draw_circle(r.position + Vector2(w * 0.5, 1.5), 1.2, Color(0.72, 0.28, 0.24))

func _decor_bin(p: Vector2) -> void:
	var r := Rect2(p - Vector2(5.0, 12.0), Vector2(10.0, 12.0))
	draw_rect(Rect2(r.position + Vector2(1.0, 1.0), r.size), Color(0.0, 0.0, 0.0, 0.12))
	draw_rect(r, Color(0.45, 0.50, 0.48))
	draw_rect(r, Color(0.22, 0.26, 0.25), false, 1.0)
	draw_rect(Rect2(r.position + Vector2(-1.0, -2.0), Vector2(12.0, 3.0)), Color(0.55, 0.60, 0.57))
	draw_line(r.position + Vector2(3.0, 3.0), r.position + Vector2(3.0, 9.0), Color(0.75, 0.78, 0.74, 0.5), 1.0)
	draw_line(r.position + Vector2(7.0, 3.0), r.position + Vector2(7.0, 9.0), Color(0.28, 0.31, 0.29, 0.6), 1.0)

func _decor_books(p: Vector2, f: float) -> void:
	var cols := [Color(0.62, 0.30, 0.28), Color(0.28, 0.44, 0.60), Color(0.56, 0.50, 0.28)]
	for k in 3:
		var w := 12.0 - float(k) * 2.0
		var r := Rect2(p + Vector2(-w * 0.5 + f * float(k), -3.0 - float(k) * 3.0), Vector2(w, 3.0))
		draw_rect(r, cols[k])
		draw_rect(r, Color(0.18, 0.16, 0.14, 0.7), false, 1.0)

func _decor_paper(p: Vector2, f: float) -> void:
	var a := Vector2(-6.0 * f, 1.0)
	var b := Vector2(5.0 * f, -2.0)
	var c := Vector2(6.0 * f, 2.0)
	var d := Vector2(-5.0 * f, 4.0)
	var pts := PackedVector2Array([p + a, p + b, p + c, p + d])
	draw_colored_polygon(pts, Color(0.94, 0.92, 0.84, 0.95))
	draw_polyline(PackedVector2Array([p + a, p + b, p + c, p + d, p + a]), Color(0.52, 0.50, 0.44, 0.8), 1.0)
	draw_line(p + Vector2(-3.0 * f, 0.5), p + Vector2(3.0 * f, -0.5), Color(0.45, 0.42, 0.38, 0.6), 1.0)

func _decor_chair(p: Vector2, f: float) -> void:
	var seat := Rect2(p + Vector2(-6.0, -6.0), Vector2(12.0, 4.0))
	draw_rect(Rect2(seat.position + Vector2(1.0, 1.5), seat.size), Color(0.0, 0.0, 0.0, 0.12))
	draw_rect(seat, Color(0.70, 0.48, 0.28))
	draw_rect(seat, Color(0.40, 0.25, 0.14), false, 1.0)
	draw_rect(Rect2(p + Vector2(-6.0 * f, -12.0), Vector2(3.0, 7.0)), Color(0.70, 0.48, 0.28))
	draw_rect(Rect2(p + Vector2(-6.0 * f, -12.0), Vector2(3.0, 7.0)), Color(0.40, 0.25, 0.14), false, 1.0)
	draw_line(p + Vector2(-5.0, -2.0), p + Vector2(-5.0, 2.0), Color(0.36, 0.24, 0.14), 1.5)
	draw_line(p + Vector2(5.0, -2.0), p + Vector2(5.0, 2.0), Color(0.36, 0.24, 0.14), 1.5)

func _decor_puddle(p: Vector2) -> void:
	draw_set_transform(p, 0.0, Vector2(1.0, 0.38))
	draw_circle(Vector2.ZERO, 7.0, Color(0.30, 0.42, 0.52, 0.22))
	draw_circle(Vector2(-1.0, -1.0), 3.0, Color(0.62, 0.80, 0.90, 0.16))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _cells_free(cx: int, cy: int, w: int, h: int, room_i := -1) -> bool:
	for y in range(cy, cy + h):
		for x in range(cx, cx + w):
			if x < 0 or y < 0 or x >= gw or y >= gh:
				return false
			var i := y * gw + x
			if grid[i] != FLOOR or reserved[i] == 1 or furniture[i] == 1:
				return false
			if room_i >= 0 and _room_cell[i] != room_i:
				return false
	return true

## 松一点的版本：只看地板和实心家具（给贴地件用，预留格可以压）。
func _cells_free_floor(cx: int, cy: int, w: int, h: int, room_i := -1) -> bool:
	for y in range(cy, cy + h):
		for x in range(cx, cx + w):
			if x < 0 or y < 0 or x >= gw or y >= gh:
				return false
			var i := y * gw + x
			if grid[i] != FLOOR or furniture[i] == 1:
				return false
			if room_i >= 0 and _room_cell[i] != room_i:
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
	var rects: Array[Rect2] = []
	rects.append_array(box_rects)
	for it in big_items:
		if bool(it.get("solid", false)):
			rects.append(it["rect"])
	if rects.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "Furniture"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for r in rects:
		var shape := CollisionShape2D.new()
		var rs := RectangleShape2D.new()
		rs.size = r.size
		shape.shape = rs
		shape.position = r.get_center()
		body.add_child(shape)

## 房间中心（可走格）。room_idx >= 0 时只在「本房间自己的格子」里找，
## 避免套间的里间抢走母房的中心点。
func _walkable_center(r: Rect2, room_idx := -1) -> Vector2:
	var c := r.get_center()
	if is_walkable(c) and (room_idx < 0 or _cell_room(c) == room_idx):
		return c
	var best := c
	var bd := INF
	for gy in range(int(r.position.y / CELL) + 1, int(r.end.y / CELL)):
		for gx in range(int(r.position.x / CELL) + 1, int(r.end.x / CELL)):
			var p := Vector2((gx + 0.5) * CELL, (gy + 0.5) * CELL)
			if not is_walkable(p):
				continue
			if room_idx >= 0 and _cell_room(p) != room_idx:
				continue
			var d := p.distance_to(c)
			if d < bd:
				bd = d
				best = p
	return best

func _cell_room(p: Vector2) -> int:
	if p.x < 0.0 or p.y < 0.0:
		return -1
	var cx := int(p.x / CELL)
	var cy := int(p.y / CELL)
	if cx >= gw or cy >= gh or _room_cell.is_empty():
		return -1
	return _room_cell[cy * gw + cx]

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
	return _walkable_center(rooms[idx], idx)

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
		var p := _walkable_center(rooms[i], i)
		var path := find_path(exit_pos, p)
		if path.is_empty():
			return false
		if path[path.size() - 1].distance_to(p) > CELL * 2.0:
			return false
	return true

## 把走廊切成「门到门 / 路口到路口」的段落，探索按整段点亮。
func _build_corridor_segments() -> void:
	corridor_segments.clear()
	corridor_explored.clear()
	if corridor_rect.size.x > CELL and corridor_rect.size.y > 0.0:
		var xs: Array[float] = []
		for d in doors:
			var p: Vector2 = d["pos"]
			if p.y >= corridor_rect.position.y - CELL and p.y <= corridor_rect.end.y + CELL:
				xs.append(p.x)
		xs.sort()
		var splits: Array[float] = [corridor_rect.position.x]
		for i in range(1, xs.size()):
			var m: float = (xs[i - 1] + xs[i]) * 0.5
			if m - splits[splits.size() - 1] > CELL * 0.8:
				splits.append(m)
		if corridor_rect.end.x - splits[splits.size() - 1] > 1.0:
			splits.append(corridor_rect.end.x)
		for i in range(splits.size() - 1):
			var w: float = splits[i + 1] - splits[i]
			if w < 4.0:
				continue
			corridor_segments.append(Rect2(splits[i], corridor_rect.position.y, w, corridor_rect.size.y))
			corridor_explored.append(false)
	if tail_corridor_rect.size.y > CELL and tail_corridor_rect.size.x > 0.0:
		var ys: Array[float] = []
		for d in doors:
			var p: Vector2 = d["pos"]
			if p.x >= tail_corridor_rect.position.x - CELL and p.x <= tail_corridor_rect.end.x + CELL:
				ys.append(p.y)
		ys.sort()
		var ysplits: Array[float] = [tail_corridor_rect.position.y]
		for i in range(1, ys.size()):
			var m: float = (ys[i - 1] + ys[i]) * 0.5
			if m - ysplits[ysplits.size() - 1] > CELL * 0.8:
				ysplits.append(m)
		if tail_corridor_rect.end.y - ysplits[ysplits.size() - 1] > 1.0:
			ysplits.append(tail_corridor_rect.end.y)
		for i in range(ysplits.size() - 1):
			var h: float = ysplits[i + 1] - ysplits[i]
			if h < 4.0:
				continue
			corridor_segments.append(Rect2(tail_corridor_rect.position.x, ysplits[i], tail_corridor_rect.size.x, h))
			corridor_explored.append(false)
	exploration_version += 1

## 走廊整段点亮：站在哪一段就把那一段永久揭开。
func explore_corridor_at(pos: Vector2) -> bool:
	for i in corridor_segments.size():
		if corridor_segments[i].has_point(pos):
			if not corridor_explored[i]:
				corridor_explored[i] = true
				exploration_version += 1
				return true
			return false
	return false

func explore_room_at(pos: Vector2) -> int:
	explore_corridor_at(pos)
	# 倒序遍历：套间的里间矩形套在母房矩形内部，必须优先命中里间
	for i in range(rooms.size() - 1, -1, -1):
		if rooms[i].has_point(pos):
			if not explored[i]:
				explored[i] = true
				exploration_version += 1
				room_entered.emit(i)
			return i
	# 环路门洞不算任何一间房（不然隔着门洞就能点亮对面）
	return -1

## 该点所在的环路门洞下标（-1 = 不在门洞里）。
func passage_index_at(pos: Vector2) -> int:
	for i in passage_rects.size():
		if passage_rects[i].has_point(pos):
			return i
	return -1

## 环路门洞两侧任意一间房探索过，这段门洞就算见过。
func passage_seen(index: int) -> bool:
	if index < 0 or index >= passage_owner.size():
		return true
	for k in [passage_owner[index], passage_other[index]]:
		var ri := int(k)
		if ri >= 0 and ri < explored.size() and explored[ri]:
			return true
	return false

## 该点所在区域是否已点亮（房间、里间、门洞或走廊段）。
func is_explored_at(pos: Vector2) -> bool:
	for i in range(rooms.size() - 1, -1, -1):
		if rooms[i].has_point(pos):
			return explored[i]
	var pi := passage_index_at(pos)
	if pi >= 0:
		return passage_seen(pi)
	for i in corridor_segments.size():
		if corridor_segments[i].has_point(pos):
			return corridor_explored[i]
	return true

## 当前所在区域的标识（用于判断「当前房间/当前段」）。
func current_zone_at(pos: Vector2) -> String:
	for i in range(rooms.size() - 1, -1, -1):
		if rooms[i].has_point(pos):
			return "r%d" % i
	var pi := passage_index_at(pos)
	if pi >= 0:
		return "p%d" % pi
	for i in corridor_segments.size():
		if corridor_segments[i].has_point(pos):
			return "c%d" % i
	return ""

func room_index_at(pos: Vector2) -> int:
	# 倒序：套间的里间矩形在母房内部，必须先命中里间
	for i in range(rooms.size() - 1, -1, -1):
		if rooms[i].has_point(pos):
			return i
	return -1

func _draw() -> void:
	if gw <= 0:
		return
	_draw_big_floor()
	for i in rooms.size():
		_room_decor(i)
	_draw_decor()
	_draw_big()

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

