extends Node

## 宝箱怪实机截图：伪装（玩家在 92px 外）→ 靠近后醒来。

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.2, 0.25, 0.3))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 3:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()
	GameState.seed_value = 20261108
	inst._start_level(4)
	for i in 8:
		await get_tree().process_frame

	var mimic = null
	for s in get_tree().get_nodes_in_group("students"):
		if String(s.get("role")) == "mimic":
			mimic = s
			break
	print("MIMIC found=", mimic != null)
	if mimic == null:
		get_tree().quit(1)
		return

	inst.player.position = mimic.position + Vector2(0.0, 130.0)
	inst.camera.reset_smoothing()
	inst.camera.global_position = mimic.position
	await get_tree().create_timer(0.45).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_mimic_guard.png")
	print("MIMIC disguised state=", mimic.state)

	inst.player.position = mimic.position + Vector2(0.0, 70.0)
	await get_tree().create_timer(0.55).timeout
	img = get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_mimic_awake.png")
	print("MIMIC awake state=", mimic.state, " alert=", mimic.alert_level)
	get_tree().quit(0)
