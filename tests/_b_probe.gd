extends Node

## B12/B13 探针：手电光锥、敌人红眼、视差背景。
## 运行：& $G --headless --path . --quit-after 25000 res://tests/_b_probe.tscn

var failures: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func _eye_of(n: Node) -> Node:
	for c in n.get_children():
		if c.get_script() != null and String(c.get_script().resource_path).ends_with("eye_glow.gd"):
			return c
	return null


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

	# B12 手电：存在锥形贴图、朝向可旋转；普通关默认熄灭
	var torch = inst.player.torch
	_check(torch != null, "b12: player torch exists")
	if torch != null:
		_check(torch.texture != null, "b12: torch has cone texture")
		torch.set_facing(Vector2.LEFT)
		_check(absf(torch.rotation - PI) < 0.01, "b12: torch rotates with facing")
		torch.set_facing(Vector2.DOWN)
		_check(absf(torch.rotation - PI * 0.5) < 0.01, "b12: torch faces down initially")
		_check(not torch.visible and torch.energy < 0.05, "b12: torch off in normal light")

	# B13 视差：节点存在、层号 -7、跟随相机
	# B13：原来的「远景楼体剪影」视差已删除（视差位移会飘进房间变成黑条）。
	# 现在地图外的区域由 school_map 的 MAP_PAD 实心砖墙承担，不再画假剪影。
	_check(inst.get("parallax_bg") == null, "b13: fake parallax silhouettes removed")

	# B12 敌人红眼：普通关即使追击也不亮
	GameState.level = 4
	var student = get_tree().get_first_node_in_group("students")
	_check(student != null, "b12: student exists")
	if student != null:
		student.state = "chase"
		await get_tree().process_frame
		await get_tree().process_frame
		var seye = _eye_of(student)
		_check(seye != null, "b12: student has eye glow")
		if seye != null:
			_check(seye.energy < 0.05, "b12: eyes off in normal light (%.2f)" % seye.energy)

	# 触发停电：手电、雾锥、红眼一起生效
	GameState.story_flags["blackout"] = true
	if student != null:
		student.state = "search"
		student.state_timer = 5.0
		student.path = PackedVector2Array([student.position + Vector2(200.0, 0.0)])
		student.path_index = 0
	await get_tree().create_timer(0.35).timeout
	await get_tree().process_frame
	if torch != null:
		_check(torch.visible and torch.energy > 0.2, "b12: torch on during blackout (%.2f)" % torch.energy)
	if student != null:
		var seye2 = _eye_of(student)
		if seye2 != null:
			_check(seye2.energy > 0.2, "b12: chasing student eyes glow in blackout (%.2f)" % seye2.energy)
	var mat: ShaderMaterial = inst.fog.halo.material
	_check(is_equal_approx(float(mat.get_shader_parameter("cone_on")), 1.0),
		"b12: fog cone mask enabled in blackout")

	var ty = inst._spawn_tyrant(0.0, inst.player.position + Vector2(180.0, 0.0))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ty != null, "b12: tyrant spawned")
	if ty != null:
		var teye = _eye_of(ty)
		_check(teye != null, "b12: tyrant has eye glow")
		if teye != null:
			_check(teye.energy > 0.2, "b12: tyrant eyes glow in blackout (%.2f)" % teye.energy)

	# 恢复照明：手电与红眼熄灭，雾锥关闭
	GameState.story_flags.erase("blackout")
	await get_tree().create_timer(0.6).timeout
	if torch != null:
		_check(not torch.visible and torch.energy < 0.05, "b12: torch off after lights back")
	if student != null:
		var seye3 = _eye_of(student)
		if seye3 != null:
			_check(seye3.energy < 0.05, "b12: eyes off after lights back (%.2f)" % seye3.energy)
	_check(is_equal_approx(float(mat.get_shader_parameter("cone_on")), 0.0),
		"b12: fog cone mask disabled after lights back")

	# 第 4 关随机停电：把下一次间隔压到 0.05s，确认会亮一下又恢复
	GameState.level = 4
	inst._blackout_next = 0.05
	await get_tree().create_timer(0.25).timeout
	_check(inst._blackout_active and GameState.dark_vision, "b12: level 4 random blackout triggers")
	await get_tree().create_timer(1.2).timeout
	_check(not inst._blackout_active and not GameState.dark_vision, "b12: random blackout restores")

	if failures.is_empty():
		print("B_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("B_PROBE: FAILED ", failures.size())
	get_tree().quit()
