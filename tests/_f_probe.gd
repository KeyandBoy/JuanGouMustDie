extends Node

## F 组探针：F8 按楼层缩放、F1 低频决策常量。
## 运行：& $G --headless --path . --quit-after 20000 res://tests/_f_probe.tscn

var failures: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	inst._start_level(1)
	await get_tree().process_frame
	await get_tree().process_frame

	var student = get_tree().get_first_node_in_group("students")
	_check(student != null, "f: student spawned")
	if student == null:
		_finish()
		return

	# F8：第 1 关不缩放（这里只验证「楼层系数」，角色自身的差异另外乘）
	var st: Dictionary = student._role_stats()
	var vm := float(st.get("vision", 1.0))
	var sm := float(st.get("speed", 1.0))
	_check(absf(student.vision_range - 160.0 * vm) < 0.01,
		"f8: level 1 vision = 160×%.2f (%.1f)" % [vm, student.vision_range])
	_check(absf(student.speed - 80.0 * sm) < 0.01,
		"f8: level 1 speed = 80×%.2f (%.1f)" % [sm, student.speed])

	# F8：第 3 关 +8% 视野/层、+5% 移速/层（都再乘角色差异）
	var old_level: int = GameState.level
	GameState.level = 3
	student._apply_level_scale()
	_check(absf(student.vision_range - 185.6 * vm) < 0.1,
		"f8: level 3 vision = 185.6×%.2f (%.1f)" % [vm, student.vision_range])
	_check(absf(student.speed - 88.0 * sm) < 0.1,
		"f8: level 3 speed = 88×%.2f (%.1f)" % [sm, student.speed])
	_check(absf(student.chase_speed - 154.0 * sm) < 0.1,
		"f8: level 3 chase = 154×%.2f (%.1f)" % [sm, student.chase_speed])

	# 教学关不缩放（回到 1.0 楼层系数）
	GameState.tutorial_active = true
	student._apply_level_scale()
	_check(absf(student.vision_range - 160.0 * vm) < 0.01 and absf(student.speed - 80.0 * sm) < 0.01,
		"f8: tutorial stays unscaled (%.1f / %.1f)" % [student.vision_range, student.speed])
	GameState.tutorial_active = false
	GameState.level = old_level

	# F1：0.3s 决策 tick
	_check(absf(student.THINK_INTERVAL - 0.3) < 0.001, "f1: think interval = 0.3s")
	_check(student.think_timer <= student.THINK_INTERVAL + 0.01, "f1: think timer within interval")

	_finish()


func _finish() -> void:
	if failures.is_empty():
		print("F_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("F_PROBE: FAILED ", failures.size())
	get_tree().quit()
