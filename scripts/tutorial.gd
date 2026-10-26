extends Node2D

signal finished(skipped: bool)

const TOTAL_STEPS := 7
const CONE_DIST := 210.0
const CONE_HALF := 32.0

var main: Node
var map: Node2D
var player: Node2D
var hud: CanvasLayer
var step := 0
var marker := Vector2.INF
var pulse := 0.0
var _done := false

var tyrant: Node2D
var tyrant_dir := 1.0
var spot_timer := 0.0

var coffee: Node2D
var classroom_door: Node2D
var quiz_baseline := 0
var coffee_stage := 0
var _broadcast_player: AudioStreamPlayer
var _broadcast_tween: Tween

func setup(p_main: Node) -> void:
	main = p_main
	map = main.map
	player = main.player
	hud = main.hud
	z_index = 1
	classroom_door = map.door_nodes[0] if not map.door_nodes.is_empty() else null
	quiz_baseline = GameState.quiz_correct
	main.quiz.answered.connect(_on_quiz_answered)
	_enter_step()

func _process(delta: float) -> void:
	pulse += delta
	queue_redraw()
	if _done or main == null or player == null:
		return
	match step:
		0:
			if player.position.distance_to(marker) < 26.0:
				_complete_step()
		1:
			pass
		2:
			if coffee_stage == 0:
				if coffee == null or not is_instance_valid(coffee):
					_complete_step()
			elif GameState.inventory_find("coffee") < 0:
				_complete_step()
		3:
			if classroom_door != null and is_instance_valid(classroom_door) and classroom_door.is_open:
				_complete_step()
		4:
			if player.is_dodging():
				_complete_step()
		5:
			_update_tyrant(delta)
			if player.position.distance_to(marker) < 26.0:
				_cleanup_tyrant()
				_say([{"speaker": "广播", "text": "很好。追击者不会追进楼梯间。"}], func():
					_complete_step())
		6:
			if player.position.distance_to(marker) < 26.0:
				_finish_sequence()

func _draw() -> void:
	if marker != Vector2.INF:
		var r := 18.0 + sin(pulse * 5.0) * 4.0
		draw_circle(marker, r + 7.0, Color(1.0, 0.85, 0.3, 0.12))
		draw_arc(marker, r, 0.0, TAU, 28, Color(1.0, 0.82, 0.25, 0.9), 2.5, true)
		draw_line(marker + Vector2(0.0, -34.0), marker + Vector2(0.0, -18.0), Color(1.0, 0.86, 0.32, 0.95), 3.0)
		draw_line(marker + Vector2(-5.0, -24.0), marker + Vector2(0.0, -18.0), Color(1.0, 0.86, 0.32, 0.95), 3.0)
		draw_line(marker + Vector2(5.0, -24.0), marker + Vector2(0.0, -18.0), Color(1.0, 0.86, 0.32, 0.95), 3.0)
	if tyrant != null and is_instance_valid(tyrant) and step == 5:
		var base := Vector2(tyrant_dir, 0.0).angle()
		var pts := PackedVector2Array([tyrant.position])
		for i in 13:
			var a := base - deg_to_rad(CONE_HALF) + deg_to_rad(CONE_HALF * 2.0) * float(i) / 12.0
			pts.append(tyrant.position + Vector2(cos(a), sin(a)) * CONE_DIST)
		draw_colored_polygon(pts, Color(0.95, 0.25, 0.2, 0.16))

func _enter_step() -> void:
	marker = Vector2.INF
	match step:
		0:
			_hud_task("任务 1/7 · 跟着黄色标记走（WASD）")
			marker = _classroom_point()
			_say([
				{"speaker": "广播", "text": "喂。"},
				{"speaker": "广播", "text": "听得到吗？"},
				{"speaker": "广播", "text": "你是谁？怎么来到这儿的？"},
				{"speaker": "广播", "text": "……麻烦了。你得离开这里才行。"},
				{"speaker": "广播", "text": "身子能动吗？"},
				{"speaker": "广播", "text": "能动就按 WASD 走两步，先到黄色标记那边。"},
			], Callable())
		1:
			_hud_task("任务 2/7 · 到课桌按 F 学习，答对 3 题")
			marker = _classroom_desk_pos()
			main.tutorial_questions.clear()
			_say([
				{"speaker": "广播", "text": "别愣着。看到课桌没？靠近，按 F 坐下学习。"},
				{"speaker": "广播", "text": "答对就涨净答对；每层最多 3 颗星，正确率、用时、警告都算。"},
				{"speaker": "广播", "text": "先练手，别紧张。"},
			], Callable())
		2:
			_spawn_coffee()
			coffee_stage = 0
			_hud_task("任务 3/7 · 捡起咖啡")
			_say([
				{"speaker": "广播", "text": "地上发亮的是道具，走过去捡。"},
				{"speaker": "广播", "text": "背包就三格：R、T、Y。按 R 用第一格，咖啡就在这格。"},
			], Callable())
		3:
			_hud_task("任务 4/7 · 按 E 开门")
			if classroom_door != null and is_instance_valid(classroom_door):
				marker = classroom_door.position
			_say([{"speaker": "广播", "text": "门不开？靠近，按 E。别拿身子硬撞。"}], Callable())
		4:
			_hud_task("任务 5/7 · 按 Shift 闪避一次")
			marker = _classroom_point()
			GameState.dash_energy = GameState.dash_max_value()
			_say([{"speaker": "广播", "text": "Shift 闪避。左上角是冲刺条，用完会慢慢回，别乱按。"}], Callable())
		5:
			_hud_task("任务 6/7 · 避开红色视野，到走廊尽头")
			_spawn_tyrant()
			marker = _corridor_end_point()
			_say([
				{"speaker": "广播", "text": "后面那东西出来了。红色扇形是它的视野，别被扫到。"},
				{"speaker": "广播", "text": "被发现会拉警报，警告 +1。正式关卡满 3 次就输；这儿不会，快跑。"},
			], Callable())
		6:
			_hud_task("任务 7/7 · 进楼梯间，离开这里")
			marker = map._walkable_center(map.stair_rects[0]) if not map.stair_rects.is_empty() else map.exit_pos
			_say([{"speaker": "广播", "text": "楼梯在那边。上去，离开这儿。"}], Callable())
		_:
			_finish_sequence()

func _complete_step() -> void:
	step += 1
	if step >= TOTAL_STEPS:
		_finish_sequence()
	else:
		_enter_step()

func _finish_sequence() -> void:
	if _done:
		return
	_say([{"speaker": "广播", "text": "行了，别回头。走吧，别迟到。"}], func():
		_finish(false))

func skip() -> void:
	_finish(true)

func _finish(skipped: bool) -> void:
	if _done:
		return
	_done = true
	marker = Vector2.INF
	_cleanup()
	finished.emit(skipped)

func _cleanup() -> void:
	_cleanup_tyrant()
	_stop_broadcast_noise(true)
	if coffee != null and is_instance_valid(coffee):
		coffee.queue_free()
	coffee = null

func _cleanup_tyrant() -> void:
	if tyrant != null and is_instance_valid(tyrant):
		tyrant.queue_free()
	tyrant = null
	spot_timer = 0.0

func _hud_task(text: String) -> void:
	if hud != null and hud.has_method("set_task"):
		hud.set_task(text)

func _say(entries: Array, cb: Callable) -> void:
	var data := DialogueDb.make("tutorial_%d" % step, entries)
	var has_broadcast := false
	for e in entries:
		if String(e.get("speaker", "")) == "广播":
			has_broadcast = true
			break
	if has_broadcast and step == 0:
		_start_broadcast_noise()
	var ui: Control = main.show_dialogue(data, true)
	if ui == null:
		_stop_broadcast_noise()
		if cb.is_valid():
			cb.call()
		return
	ui.finished.connect(func():
		_stop_broadcast_noise()
		if cb.is_valid():
			cb.call()
	, CONNECT_ONE_SHOT)

func _start_broadcast_noise() -> void:
	if _broadcast_player == null:
		var stream = load("res://assets/sfx/broadcast_noise.mp3")
		if stream == null:
			return
		_broadcast_player = AudioStreamPlayer.new()
		_broadcast_player.stream = stream
		_broadcast_player.volume_db = -12.0
		_broadcast_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_broadcast_player)
	if _broadcast_tween != null and _broadcast_tween.is_valid():
		_broadcast_tween.kill()
	_broadcast_player.volume_db = -12.0
	if not _broadcast_player.playing:
		_broadcast_player.play()

func _stop_broadcast_noise(instant := false) -> void:
	if _broadcast_player == null or not is_instance_valid(_broadcast_player):
		return
	if _broadcast_tween != null and _broadcast_tween.is_valid():
		_broadcast_tween.kill()
	if instant or not _broadcast_player.playing:
		_broadcast_player.stop()
		return
	_broadcast_tween = create_tween()
	_broadcast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_broadcast_tween.tween_property(_broadcast_player, "volume_db", -60.0, 0.45)
	_broadcast_tween.tween_callback(_broadcast_player.stop)

func _classroom_point() -> Vector2:
	if map.rooms.is_empty():
		return map.exit_pos
	var r: Rect2 = map.rooms[0]
	return _free_near(Vector2(r.position.x + r.size.x * 0.55, r.position.y + r.size.y * 0.55))

func _classroom_desk_pos() -> Vector2:
	var best := Vector2.INF
	var bd := INF
	for d in map.desks:
		if int(d.get("room", -1)) != 0:
			continue
		var p: Vector2 = d["pos"]
		var dist := p.distance_to(_classroom_point())
		if dist < bd:
			bd = dist
			best = p
	if best == Vector2.INF:
		return _classroom_point()
	return best

func _corridor_end_point() -> Vector2:
	var cr: Rect2 = map.corridor_rect
	var y := cr.get_center().y
	var x := cr.end.x - 190.0
	return _free_near(Vector2(x, y))

func _free_near(p: Vector2) -> Vector2:
	if map.is_walkable(p):
		return p
	for radius in range(1, 8):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var q := p + Vector2(dx * 20.0, dy * 20.0)
				if map.is_walkable(q):
					return q
	return map.exit_pos

func _spawn_coffee() -> void:
	if coffee != null and is_instance_valid(coffee):
		coffee.queue_free()
	var pos := _classroom_point() - Vector2(70.0, 0.0)
	pos = _free_near(pos)
	coffee = main.item_spawn_script.new()
	var def: Dictionary = GameState.get_item_def("coffee")
	coffee.setup("coffee", def.get("color", Color(0.62, 0.38, 0.18)))
	coffee.position = pos
	main.add_child(coffee)
	coffee.picked.connect(func(_id):
		coffee_stage = 1
		_hud_task("任务 3/7 · 按 R 喝咖啡")
		marker = Vector2.INF
	)

func _spawn_tyrant() -> void:
	_cleanup_tyrant()
	if main.tyrant_script == null:
		return
	var cr: Rect2 = map.corridor_rect
	tyrant = main.tyrant_script.new()
	tyrant.collision_layer = 4
	tyrant.collision_mask = 1
	tyrant.position = Vector2(cr.end.x - 40.0, cr.get_center().y)
	main.add_child(tyrant)
	tyrant.setup(map, player, 5)
	tyrant.tutorial_driven = true
	tyrant.idle_timer = 999.0
	tyrant_dir = -1.0

func _update_tyrant(delta: float) -> void:
	if tyrant == null or not is_instance_valid(tyrant):
		return
	var cr: Rect2 = map.corridor_rect
	tyrant.position.x += tyrant_dir * 34.0 * delta
	if tyrant.position.x > cr.end.x - 80.0:
		tyrant_dir = -1.0
	elif tyrant.position.x < cr.position.x + 80.0:
		tyrant_dir = 1.0
	tyrant.facing = Vector2(tyrant_dir, 0.0)
	var to_player: Vector2 = player.position - tyrant.position
	var seen := false
	if to_player.length() < CONE_DIST:
		var facing := Vector2(tyrant_dir, 0.0)
		if absf(facing.angle_to(to_player)) < deg_to_rad(CONE_HALF):
			if map.line_clear(tyrant.position, player.position):
				seen = true
	if seen:
		spot_timer += delta
		if spot_timer >= 0.65:
			_alert()
	else:
		spot_timer = maxf(0.0, spot_timer - delta * 2.0)

func _alert() -> void:
	spot_timer = 0.0
	GameState.add_warning(1)
	main._fx_flash(Color(0.9, 0.15, 0.12), 0.45, 0.45)
	if hud != null:
		hud.toast("被看到了！警告 +1。这儿不会出事，继续跑。")
	if GameState.warnings >= GameState.max_warnings:
		GameState.warnings = 0
		if hud != null:
			hud.toast("警告满了。正式关卡三次就输；这里重置，接着来。")
	var cr: Rect2 = map.corridor_rect
	player.position = Vector2(cr.position.x + 60.0, cr.get_center().y)
	if main.camera != null:
		main.camera.reset_smoothing()
		main.camera.global_position = player.position
	if tyrant != null and is_instance_valid(tyrant):
		tyrant.position = Vector2(cr.end.x - 40.0, cr.get_center().y)
		tyrant_dir = -1.0

func _on_quiz_answered(correct: bool) -> void:
	if _done or step != 1 or not correct:
		return
	if GameState.quiz_correct - quiz_baseline < 3:
		return
	if main.quiz != null and main.quiz.is_open:
		main.quiz.close()
	main._stand_up()
	_complete_step()
