class_name ItemFx
extends Node2D

## 道具释放特效（全部代码绘制）：使用道具时在世界坐标播放
## 图标弹出 + 每道具专属粒子/光环，另附持续光环（咖啡残影 / 台灯光圈）。
## main.gd 里实例化一次，调用 burst(id, pos, target) 触发。

var player: Node2D = null

var _parts: Array[Dictionary] = []
var _auras: Array[Dictionary] = []

func _ready() -> void:
	z_index = 6
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func clear() -> void:
	_parts.clear()
	_auras.clear()
	queue_redraw()

func burst(id: String, pos: Vector2, target := Vector2.INF) -> void:
	_spawn_icon(id, pos)
	match id:
		"coffee":
			_ring(pos, Color(1.0, 0.62, 0.25), 70.0)
			_sparks(pos, 7, Color(1.0, 0.68, 0.3), 95.0)
			_aura("coffee", 8.0)
		"bread":
			_stars(pos + Vector2(0, -6), 6, Color(0.55, 0.95, 0.5))
			_puffs(pos, 4, Color(0.8, 0.95, 0.6), 14.0, 0.5)
		"smoke":
			_puffs(pos, 8, Color(0.6, 0.64, 0.72), 24.0, 0.95)
			_ring(pos, Color(0.75, 0.78, 0.85), 76.0)
		"chair":
			var at := target if target != Vector2.INF else pos
			_sparks(at, 10, Color(1.0, 0.85, 0.2), 130.0)
			_stars(at, 4, Color(1.0, 1.0, 0.75))
			_ring(at, Color(1.0, 0.7, 0.15), 55.0)
		"stink":
			_gas(pos, 6, Color(0.5, 0.75, 0.3))
			_ring(pos, Color(0.55, 0.8, 0.3), 78.0)
		"portal":
			_ring(pos, Color(0.7, 0.5, 1.0), 62.0)
			_sparks(pos, 6, Color(0.8, 0.6, 1.0), 70.0)
			if target != Vector2.INF:
				_ring(target, Color(0.7, 0.5, 1.0), 62.0, 0.1)
				_sparks(target, 6, Color(0.8, 0.6, 1.0), 70.0, 0.1)
		"shovel":
			_clods(pos, 8, Color(0.55, 0.42, 0.28))
			_puffs(pos, 5, Color(0.6, 0.5, 0.35), 16.0, 0.6)
			if target != Vector2.INF:
				_ring(target, Color(0.7, 0.58, 0.4), 56.0, 0.28)
				_puffs(target, 6, Color(0.6, 0.5, 0.35), 16.0, 0.6, 0.28)
		"lamp":
			_stars(pos, 7, Color(1.0, 0.9, 0.45))
			_ring(pos, Color(1.0, 0.85, 0.35), 66.0)
			_aura("lamp", 10.0)
		"notes":
			_stars(pos, 5, Color(0.55, 0.75, 1.0))
			_puffs(pos + Vector2(0, -8), 5, Color(0.85, 0.9, 1.0), 10.0, 0.7)
		"shoes":
			_puffs(pos + Vector2(0, 8), 5, Color(0.75, 0.78, 0.82), 12.0, 0.5)
			_sparks(pos + Vector2(0, 6), 4, Color(0.9, 0.92, 1.0), 60.0)
		"stopwatch":
			_ring(pos, Color(0.6, 0.9, 1.0), 58.0)
			_ring(pos, Color(0.6, 0.9, 1.0), 86.0, 0.14)
			_waves(pos, 3, Color(0.7, 0.95, 1.0), 0.07, 0.62)
		"intel":
			_waves(pos, 4, Color(1.0, 0.5, 0.8), 0.08, 0.7)
			_ring(pos, Color(1.0, 0.5, 0.8), 92.0)
		"ears":
			_waves(pos, 2, Color(0.72, 0.76, 0.92), 0.1, 0.6)
			_ring(pos, Color(0.8, 0.82, 0.95), 46.0)
	queue_redraw()

func _aura(id: String, dur: float) -> void:
	for a in _auras:
		if String(a["id"]) == id:
			a["left"] = dur
			return
	_auras.append({"id": id, "left": dur, "acc": 0.0, "ph": 0.0})

func _spawn(part: Dictionary) -> void:
	if not part.has("t"):
		part["t"] = 0.0
	if not part.has("delay"):
		part["delay"] = 0.0
	_parts.append(part)

func _spawn_icon(id: String, pos: Vector2) -> void:
	var tex := UiIcons.item(id)
	_spawn({"k": "icon", "p": pos + Vector2(0, -14), "c": Color.WHITE, "dur": 0.6, "tex": tex})

func _ring(pos: Vector2, col: Color, r1: float, delay := 0.0) -> void:
	_spawn({"k": "ring", "p": pos, "c": col, "r0": 6.0, "r1": r1, "dur": 0.55, "delay": delay})

func _sparks(pos: Vector2, n: int, col: Color, spd: float, delay := 0.0) -> void:
	for i in n:
		var ang := TAU * float(i) / float(n) + randf_range(-0.2, 0.2)
		_spawn({
			"k": "spark", "p": pos, "d": Vector2(cos(ang), sin(ang)),
			"c": col, "spd": spd, "dur": 0.4 + randf() * 0.18, "delay": delay,
		})

func _puffs(pos: Vector2, n: int, col: Color, r_max: float, dur: float, delay := 0.0) -> void:
	for i in n:
		_spawn({
			"k": "puff",
			"p": pos + Vector2(randf_range(-8, 8), randf_range(-6, 6)),
			"c": col, "r0": 4.0, "r1": r_max * randf_range(0.7, 1.1),
			"drift": Vector2(randf_range(-6, 6), randf_range(-16, -6)),
			"dur": dur * randf_range(0.8, 1.15), "delay": delay + randf() * 0.1,
		})

func _gas(pos: Vector2, n: int, col: Color) -> void:
	for i in n:
		var ang := TAU * float(i) / float(n)
		_spawn({
			"k": "gas", "p": pos, "d": Vector2(cos(ang), sin(ang)),
			"c": col, "r0": 7.0, "r1": 15.0, "dur": 0.9, "phase": randf() * TAU,
		})

func _clods(pos: Vector2, n: int, col: Color) -> void:
	for i in n:
		var ang := TAU * float(i) / float(n) + randf_range(-0.25, 0.25)
		_spawn({
			"k": "clod", "p": pos, "d": Vector2(cos(ang), sin(ang)),
			"c": col, "spd": randf_range(55.0, 95.0),
			"dur": randf_range(0.45, 0.7), "delay": randf() * 0.12,
		})

func _stars(pos: Vector2, n: int, col: Color) -> void:
	for i in n:
		_spawn({
			"k": "star",
			"p": pos + Vector2(randf_range(-16, 16), randf_range(-10, 10)),
			"c": col, "size": randf_range(4.0, 7.0),
			"dur": randf_range(0.5, 0.75), "delay": randf() * 0.18,
		})

func _waves(pos: Vector2, n: int, col: Color, stagger: float, dur: float) -> void:
	for i in n:
		_spawn({
			"k": "wave", "p": pos, "c": col,
			"r0": 10.0, "r1": 40.0 + float(i) * 14.0,
			"dur": dur, "delay": float(i) * stagger,
		})

func _process(delta: float) -> void:
	var dirty := false
	if not _parts.is_empty():
		dirty = true
		for part in _parts:
			part["t"] = float(part["t"]) + delta
		for i in range(_parts.size() - 1, -1, -1):
			var part: Dictionary = _parts[i]
			if float(part["t"]) > float(part["dur"]) + float(part["delay"]) + 0.05:
				_parts.remove_at(i)
	for i in range(_auras.size() - 1, -1, -1):
		var a: Dictionary = _auras[i]
		a["left"] = float(a["left"]) - delta
		a["ph"] = float(a["ph"]) + delta * 4.0
		dirty = true
		if float(a["left"]) <= 0.0:
			_auras.remove_at(i)
			continue
		if player == null or not is_instance_valid(player):
			continue
		a["acc"] = float(a["acc"]) + delta
		var id := String(a["id"])
		var interval := 0.1 if id == "coffee" else 0.25
		if float(a["acc"]) < interval:
			continue
		a["acc"] = 0.0
		if id == "coffee":
			var dir := Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			if player is CharacterBody2D and (player as CharacterBody2D).velocity.length() > 8.0:
				dir = (player as CharacterBody2D).velocity.normalized()
			_spawn({
				"k": "streak", "p": player.position + Vector2(randf_range(-5, 5), randf_range(-7, 7)),
				"d": -dir, "c": Color(1.0, 0.7, 0.35), "len": 13.0, "dur": 0.32,
			})
		elif id == "lamp":
			_spawn({
				"k": "star",
				"p": player.position + Vector2(randf_range(-28, 28), randf_range(-26, 24)),
				"c": Color(1.0, 0.9, 0.45), "size": randf_range(3.5, 5.5), "dur": 0.55,
			})
	if dirty:
		queue_redraw()

func _draw() -> void:
	for a in _auras:
		if String(a["id"]) != "lamp" or player == null or not is_instance_valid(player):
			continue
		var pulse := 0.6 + 0.4 * sin(float(a["ph"]))
		draw_arc(player.position, 34.0, 0.0, TAU, 30, Color(1.0, 0.85, 0.4, 0.22 + 0.14 * pulse), 2.5, true)
		draw_arc(player.position, 30.0, 0.0, TAU, 30, Color(1.0, 0.9, 0.5, 0.10 + 0.08 * pulse), 1.2, true)
	for part in _parts:
		var te := float(part["t"]) - float(part["delay"])
		if te < 0.0:
			continue
		var u := clampf(te / float(part["dur"]), 0.0, 1.0)
		match String(part["k"]):
			"icon": _draw_icon(part, u)
			"ring": _draw_ring(part, u)
			"spark": _draw_spark(part, u)
			"puff": _draw_puff(part, u)
			"gas": _draw_gas(part, u)
			"clod": _draw_clod(part, u)
			"star": _draw_star(part, u)
			"wave": _draw_wave(part, u)
			"streak": _draw_streak(part, u)

func _draw_icon(part: Dictionary, u: float) -> void:
	var tex: Texture2D = part.get("tex")
	if tex == null:
		return
	var pop := 1.0
	if u < 0.24:
		pop = lerpf(0.35, 1.18, u / 0.24)
	elif u < 0.4:
		pop = lerpf(1.18, 1.0, (u - 0.24) / 0.16)
	var alpha := 1.0
	if u > 0.5:
		alpha = 1.0 - (u - 0.5) / 0.5
	var p: Vector2 = part["p"]
	var base := 26.0
	var s := base / maxf(tex.get_width(), tex.get_height()) * pop
	var sz := tex.get_size() * s
	draw_texture_rect(tex, Rect2(p - sz * 0.5, sz), false, Color(1, 1, 1, alpha))
	draw_arc(p, 16.0 * pop, 0.0, TAU, 24, Color(1, 1, 1, 0.35 * alpha), 1.5, true)

func _draw_ring(part: Dictionary, u: float) -> void:
	var e := 1.0 - pow(1.0 - u, 2.0)
	var r := lerpf(float(part["r0"]), float(part["r1"]), e)
	var col: Color = part["c"]
	draw_arc(part["p"], r, 0.0, TAU, 34, Color(col, col.a * (1.0 - u)), lerpf(3.5, 1.0, u), true)

func _draw_spark(part: Dictionary, u: float) -> void:
	var p: Vector2 = part["p"]
	var d: Vector2 = part["d"]
	var dist := float(part["spd"]) * float(part["dur"]) * u
	var col: Color = part["c"]
	var tail := maxf(0.0, dist - 9.0)
	draw_line(p + d * tail, p + d * dist, Color(col, col.a * (1.0 - u)), 2.5, true)

func _draw_puff(part: Dictionary, u: float) -> void:
	var p: Vector2 = part["p"] + Vector2(part["drift"]) * u
	var r := lerpf(float(part["r0"]), float(part["r1"]), 1.0 - pow(1.0 - u, 2.0))
	var col: Color = part["c"]
	draw_circle(p, r, Color(col, col.a * 0.5 * (1.0 - u)))
	draw_arc(p, r, 0.0, TAU, 20, Color(col, col.a * 0.7 * (1.0 - u)), 1.5, true)

func _draw_gas(part: Dictionary, u: float) -> void:
	var p: Vector2 = part["p"]
	var d: Vector2 = part["d"]
	var col: Color = part["c"]
	var phase := float(part["phase"])
	var base: Vector2 = p + d * 14.0 * u
	for i in 5:
		var wob := Vector2(sin(u * 5.0 + phase + float(i) * 1.3) * 4.0, cos(u * 4.0 + phase + float(i)) * 3.0)
		var off := Vector2(sin(float(i) * 2.1), cos(float(i) * 1.7)) * 7.0
		var r := lerpf(float(part["r0"]), float(part["r1"]), u) * (0.7 + 0.3 * sin(float(i) + u * 3.0))
		draw_circle(base + off + wob, maxf(2.0, r), Color(col, col.a * 0.42 * (1.0 - u)))

func _draw_clod(part: Dictionary, u: float) -> void:
	var p: Vector2 = part["p"]
	var d: Vector2 = part["d"]
	var col: Color = part["c"]
	var dist := float(part["spd"]) * float(part["dur"]) * u
	var pos := p + d * dist
	pos.y -= 18.0 * sin(PI * u)
	var alpha := 1.0 - u * u
	var sz := 4.0
	draw_rect(Rect2(pos - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(col, col.a * alpha))

func _draw_star(part: Dictionary, u: float) -> void:
	var p: Vector2 = part["p"] + Vector2(0, -14.0 * u)
	var col: Color = part["c"]
	var tw := 0.6 + 0.4 * sin(u * PI * 3.0)
	var len := float(part["size"]) * tw
	var alpha := (1.0 - u) * 0.95
	draw_line(p + Vector2(-len, 0), p + Vector2(len, 0), Color(col, col.a * alpha), 1.6, true)
	draw_line(p + Vector2(0, -len), p + Vector2(0, len), Color(col, col.a * alpha), 1.6, true)
	draw_circle(p, 1.3, Color(1, 1, 1, alpha))

func _draw_wave(part: Dictionary, u: float) -> void:
	var e := 1.0 - pow(1.0 - u, 2.0)
	var r := lerpf(float(part["r0"]), float(part["r1"]), e)
	var col: Color = part["c"]
	draw_arc(part["p"], r, -PI * 0.8, PI * 0.8, 26, Color(col, col.a * 0.75 * (1.0 - u)), 2.6, true)
	draw_arc(part["p"], r * 0.72, -PI * 0.8, PI * 0.8, 22, Color(col, col.a * 0.5 * (1.0 - u)), 1.8, true)

func _draw_streak(part: Dictionary, u: float) -> void:
	var p: Vector2 = part["p"]
	var d: Vector2 = part["d"]
	var col: Color = part["c"]
	var start := p + d * (34.0 * u)
	draw_line(start, start + d * float(part["len"]), Color(col, col.a * (1.0 - u) * 0.9), 2.0, true)
