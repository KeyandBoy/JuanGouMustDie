extends Node

## 反馈管线探针（S1：A1/A3/C7/G10）
## 验证：飘字池、答对/答错的色闪与数字、连对暴击字号、Fx 静态函数不崩。
## 跑法：godot --headless --path . --quit-after 8000 res://tests/_fx_probe.tscn

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _visible_numbers(hud) -> Array[Label]:
	var out: Array[Label] = []
	if hud == null or hud._num_root == null:
		return out
	for c in hud._num_root.get_children():
		if c is Label and c.visible:
			out.append(c)
	return out

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "main.tscn loads")
	if scene == null:
		_finish()
		return
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	inst._start_level(1)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(inst.hud != null, "hud exists")
	_check(inst.hud._num_pool.size() == inst.hud.NUM_POOL_SIZE,
		"number pool built (%d)" % inst.hud._num_pool.size())

	# 池里的 Label 必须解析到 UiTheme 字体（网页端无系统字体回退）
	var odd := 0
	for l in inst.hud._num_pool:
		if l.get_theme_font("font") != UiTheme.font():
			odd += 1
	_check(odd == 0, "pool labels use UiTheme font (odd=%d)" % odd)

	# --- 房间角色（S2）：纵深 + 安全屋 ---
	_check(inst.map.room_roles.size() == inst.map.rooms.size(),
		"map: room_roles aligned (%d/%d)" % [inst.map.room_roles.size(), inst.map.rooms.size()])
	_check(inst.map.room_roles.has("deep"), "map: has a deep room")
	var safe_i: int = inst.map.safe_room_index
	_check(safe_i == -1, "map: no safe room in levels 1-5 (idx=%d)" % safe_i)
	# 模拟第 6 层：安全屋机制仍要可用
	var old_level: int = GameState.level
	GameState.level = 6
	inst.map._compute_roles(true)
	var safe6: int = inst.map.safe_room_index
	_check(safe6 >= 0, "map: safe room returns from level 6 (idx=%d)" % safe6)
	if safe6 >= 0:
		_check(not inst.map.study_allowed_at(inst.map.rooms[safe6].get_center()),
			"map: safe room blocks study")
	GameState.level = old_level
	inst.map._compute_roles(true)

	# --- 答对：色闪层 + 绿色飘字 ---
	var before := 0
	for c in inst.get_children():
		if c is CanvasLayer and c.layer == inst.L_FX:
			before += 1
	inst._on_answered(true)
	await get_tree().process_frame
	var after := 0
	for c in inst.get_children():
		if c is CanvasLayer and c.layer == inst.L_FX:
			after += 1
	_check(after > before, "correct answer spawns flash layer (%d -> %d)" % [before, after])
	var nums := _visible_numbers(inst.hud)
	_check(nums.size() >= 1, "correct answer pops a number (%d)" % nums.size())
	var got_gain := false
	for l in nums:
		if String(l.text).begins_with("+"):
			got_gain = true
	_check(got_gain, "correct number shows gain")

	# --- 答错：红闪 + 负向飘字 ---
	inst._on_answered(false)
	await get_tree().process_frame
	var got_loss := false
	for l in _visible_numbers(inst.hud):
		if String(l.text).find("-1") >= 0:
			got_loss = true
	_check(got_loss, "wrong answer pops a loss number")

	# --- 连对暴击字：字号必须比普通大 ---
	inst.hud.pop_number(inst.player.global_position + Vector2(0, -60), "连对 ×1.2", "crit")
	await get_tree().process_frame
	var crit_size := 0
	for l in _visible_numbers(inst.hud):
		if String(l.text).find("连对") >= 0:
			crit_size = l.get_theme_font_size("font_size")
	_check(crit_size >= 24, "crit number uses bigger font (%d)" % crit_size)

	# --- Fx 静态封装不能崩 ---
	var ok_fx := true
	if inst.player != null and inst.player.sprite != null:
		Fx.sprite_flash(inst.player.sprite)
	else:
		ok_fx = false
	_check(ok_fx, "fx: pixel player sprite available for flash")

	Fx.shake(inst, 1)
	await get_tree().process_frame
	_check(inst.camera != null, "fx: camera exists for shake")

	Fx.hitstop(2)
	await get_tree().create_timer(0.25, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "fx: hitstop restores time_scale (%.2f)" % Engine.time_scale)
	Engine.time_scale = 1.0

	# --- A9：击杀慢放 API 必须能把 time_scale 还回来 ---
	_check(inst.breath != null, "breath: node exists on main")
	Fx.slowmo(0.3, 0.1)
	_check(Engine.time_scale < 0.5, "fx: slowmo drops time_scale (%.2f)" % Engine.time_scale)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "fx: slowmo restores time_scale (%.2f)" % Engine.time_scale)
	Engine.time_scale = 1.0

	# --- A4：震屏取更大者、不叠加 ---
	var shake_before: float = inst._shake_amp
	Fx.shake(inst, 1)
	var after_light: float = inst._shake_amp
	Fx.shake(inst, 0)
	_check(is_equal_approx(inst._shake_amp, after_light),
		"fx: weaker shake does not interrupt stronger (%.1f)" % inst._shake_amp)
	Fx.shake(inst, 3)
	_check(inst._shake_amp > after_light, "fx: stronger shake wins (%.1f -> %.1f)" % [after_light, inst._shake_amp])
	_check(shake_before >= 0.0, "fx: shake state readable")
	await get_tree().create_timer(0.9, true, false, true).timeout

	# --- A8：拾取图标飞入背包 ---
	var fly_before: int = inst.hud.active_fly_count()
	inst.hud.fly_item("coffee", inst.player.global_position + Vector2(0, -18))
	await get_tree().process_frame
	_check(inst.hud.active_fly_count() == fly_before + 1,
		"a8: pickup spawns a flying icon (%d -> %d)" % [fly_before, inst.hud.active_fly_count()])
	await get_tree().create_timer(1.0, true, false, true).timeout
	_check(inst.hud.active_fly_count() == fly_before,
		"a8: flying icon cleans up (%d)" % inst.hud.active_fly_count())

	# --- A10：呼吸状态优先级 panic > blind > tense > calm ---
	var b = preload("res://scripts/breath.gd").new()
	add_child(b)
	b.set_sources(false, true, false)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(b.state == 1, "breath: uneasy -> tense (%s)" % b.state_name())
	b.set_sources(false, false, true)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(b.state == 3, "breath: dark -> blind (%s)" % b.state_name())
	b.set_sources(true, false, true)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(b.state == 2, "breath: chased beats dark -> panic (%s)" % b.state_name())
	b.set_sources(false, false, false)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_check(b.state == 0, "breath: relax -> calm (%s)" % b.state_name())
	b.notify_hurt(0.5)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_check(b.state == 2, "breath: hurt -> panic (%s)" % b.state_name())
	_check(not b.stream_slot_for(2).is_empty(), "breath: panic has a reserved stream slot")
	b.queue_free()

	# --- 飘字必须自动隐藏（不残留） ---
	await get_tree().create_timer(1.4, true, false, true).timeout
	var left := _visible_numbers(inst.hud)
	_check(left.size() == 0, "numbers auto-hide after tween (%d left)" % left.size())

	inst.queue_free()
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("FX_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("FX_PROBE: %d FAILURES" % failures.size())
	Engine.time_scale = 1.0
	get_tree().quit()
