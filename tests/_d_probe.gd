extends Node

## D 组音频探针：总线、环境层、压迫层、脚步接口。
## 运行：& $G --headless --path . --quit-after 20000 res://tests/_d_probe.tscn

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

	# D4 五条总线
	for bus in ["Master", "Music", "SFX", "UI", "Ambience"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "d4: bus exists (%s)" % bus)

	# D5 环境音：L1 无、L2+ 有，且文件真实存在
	var old_level: int = GameState.level
	GameState.level = 1
	_check(AudioManager.desired_ambience_path() == "", "d5: no ambience on level 1")
	GameState.level = 2
	_check(AudioManager.desired_ambience_path().ends_with("broadcast_noise.mp3"),
		"d5: level 2 uses broadcast noise (%s)" % AudioManager.desired_ambience_path())
	GameState.tutorial_active = true
	_check(AudioManager.desired_ambience_path() == "", "d5: tutorial disables ambience")
	GameState.tutorial_active = false
	GameState.level = old_level

	# D6 压迫层：只在暴君 active 时出现
	var old_tyrant: bool = GameState.tyrant_active
	GameState.tyrant_active = false
	_check(AudioManager.desired_pressure_path() == "", "d6: no pressure layer without tyrant")
	GameState.tyrant_active = true
	_check(AudioManager.desired_pressure_path().ends_with("amb_tyrant_drone.ogg"),
		"d6: tyrant uses drone layer (%s)" % AudioManager.desired_pressure_path())
	GameState.tyrant_active = old_tyrant

	# D8 脚步：素材已就位，三种材质都能出声；材质按房间类型映射
	for mat in ["tile", "wood", "carpet"]:
		var sample := "res://assets/sfx/step/step_%s_1.ogg" % mat
		_check(ResourceLoader.exists(sample), "d8: sample exists (%s)" % mat)
		_check(AudioManager.play_footstep(mat, Vector2.ZERO),
			"d8: footstep plays (%s)" % mat)
	var wood_i := -1
	var tile_i := -1
	for i in inst.map.rooms.size():
		var t := String(inst.map.room_types[i])
		if wood_i < 0 and (t == "classroom" or t == "office"):
			wood_i = i
		if tile_i < 0 and t == "hall":
			tile_i = i
	_check(wood_i >= 0 and inst._floor_material_at(inst.map.rooms[wood_i].get_center()) == "wood",
		"d8: classroom maps to wood")
	if tile_i >= 0:
		_check(inst._floor_material_at(inst.map.rooms[tile_i].get_center()) == "tile",
			"d8: hall maps to tile")

	# D7 UI 三音文件存在
	_check(ResourceLoader.exists(AudioManager.UI_HOVER), "d7: hover sample exists")
	_check(ResourceLoader.exists(AudioManager.UI_CLICK), "d7: click sample exists")
	_check(ResourceLoader.exists(AudioManager.UI_CONFIRM), "d7: confirm sample exists")

	if failures.is_empty():
		print("D_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("D_PROBE: FAILED ", failures.size())
	get_tree().quit()
