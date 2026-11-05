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

	# B12 手电：存在锥形贴图，朝向可旋转
	var torch = inst.player.torch
	_check(torch != null, "b12: player torch exists")
	if torch != null:
		_check(torch.texture != null, "b12: torch has cone texture")
		torch.set_facing(Vector2.LEFT)
		_check(absf(torch.rotation - PI) < 0.01, "b12: torch rotates with facing")
		torch.set_facing(Vector2.DOWN)
		_check(absf(torch.rotation - PI * 0.5) < 0.01, "b12: torch faces down initially")

	# B13 视差：节点存在、层号 -7、跟随相机
	_check(inst.parallax_bg != null, "b13: parallax node exists")
	if inst.parallax_bg != null:
		_check(inst.parallax_bg.z_index == -7, "b13: parallax z=-7")
		await get_tree().create_timer(0.2).timeout
		_check(inst.parallax_bg._cam_pos != Vector2.INF, "b13: parallax tracks camera")

	# B12 敌人红眼：L2+ 且追击时亮
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
			_check(seye.energy > 0.2, "b12: chasing student eyes glow (%.2f)" % seye.energy)

	var ty = inst._spawn_tyrant(0.0, inst.player.position + Vector2(180.0, 0.0))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ty != null, "b12: tyrant spawned")
	if ty != null:
		var teye = _eye_of(ty)
		_check(teye != null, "b12: tyrant has eye glow")
		if teye != null:
			_check(teye.energy > 0.2, "b12: tyrant eyes glow (%.2f)" % teye.energy)

	if failures.is_empty():
		print("B_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("B_PROBE: FAILED ", failures.size())
	get_tree().quit()
