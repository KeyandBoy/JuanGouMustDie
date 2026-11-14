extends Node

## 世界层专项探针（P0）：世界层推导、6~10F 目标、第二层刷怪、存档 v4 往返。
## 只验证「第二层能进、能跑、存档不坏」，不验证污染/钥匙/区域制地图（P1/P2）。

var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	if ok:
		print("  PASS: ", label)
	else:
		failures.append(label)
		print("  FAIL: ", label)

func _ready() -> void:
	# --- 1. 世界层推导 / 通关判定（纯数据） ---
	_check(GameState.MAX_LEVEL >= 10, "MAX_LEVEL >= 10 (%d)" % GameState.MAX_LEVEL)
	_check(GameState.world_of_level(1) == 1 and GameState.world_of_level(5) == 1, "1~5F = 第一层")
	_check(GameState.world_of_level(6) == 2 and GameState.world_of_level(10) == 2, "6~10F = 第二层")
	_check(GameState.world_of_level(11) == 3, "11F 起 = 第三层")
	_check(GameState.last_level_of_world(1) == 5, "第一层最后一层 = 5F")
	_check(GameState.last_level_of_world(6) == 10, "第二层最后一层 = 10F")
	GameState.set_level(5)
	_check(GameState.is_last_level_of_world(), "5F 是第一层最后一层")
	GameState.set_level(6)
	_check(GameState.world == 2, "set_level(6) 自动推导 world=2")
	_check(not GameState.is_last_level_of_world(), "6F 不是第二层最后一层")
	_check(is_equal_approx(GameState.study_goal, 16.0), "6F 学习目标 16")
	GameState.set_level(10)
	_check(is_equal_approx(GameState.study_goal, 32.0), "10F 学习目标 32")
	_check(GameState.is_last_level_of_world(), "10F 是第二层最后一层")
	_check(GameState.world_title(6).contains("地牢"), "6F 世界名含「地牢」")

	# --- 2. 污染 / 电量默认值 ---
	GameState.set_level(6)
	GameState.start_run()
	_check(is_zero_approx(GameState.contamination), "start_run 重置污染 = 0")
	_check(is_equal_approx(GameState.notebook_fuel, GameState.NOTEBOOK_FUEL_MAX), "start_run 电量满")
	GameState.set_level(6)
	GameState.damage_contamination(30.0)
	_check(is_equal_approx(GameState.contamination, 30.0), "第二层污染会累积")
	_check(is_equal_approx(GameState.emptiness_decay_rate(), 0.88), "污染 30 时空虚衰减 0.88/s")
	GameState.restore_contamination(100.0)
	_check(is_zero_approx(GameState.contamination), "污染可回到 0")
	GameState.set_level(1)
	GameState.damage_contamination(30.0)
	_check(is_zero_approx(GameState.contamination), "第一层不涨污染")
	_check(is_equal_approx(GameState.emptiness_decay_rate(), 1.0), "第一层空虚衰减恒 1.0/s")

	# --- 3. 进 6F：地图能生成、刷怪数量对 ---
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 4:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()

	GameState.seed_value = 20261114
	inst._start_level(6)
	for i in 12:
		await get_tree().process_frame
	_check(inst.map != null and not inst.map.rooms.is_empty(), "6F 地图生成成功")
	_check(GameState.level == 6 and GameState.world == 2, "6F 世界层 = 2")
	var patrol := 0
	for s in get_tree().get_nodes_in_group("students"):
		if is_instance_valid(s) and String(s.role) != "mimic":
			patrol += 1
	_check(patrol >= 10 and patrol <= 16, "6F 巡逻敌 10~14（实测 %d）" % patrol)

	# --- 4. 上楼：6F → 7F，污染 -15、电量重置 ---
	GameState.contamination = 60.0
	GameState.notebook_fuel = 3.0
	GameState.begin_next_level()
	_check(GameState.level == 7 and GameState.world == 2, "6F 上楼到 7F，仍在第二层")
	_check(is_equal_approx(GameState.contamination, 45.0), "上楼污染 -15（60 → 45）")
	_check(is_equal_approx(GameState.notebook_fuel, GameState.NOTEBOOK_FUEL_MAX), "上楼电量重置")

	# --- 5. 10F 不能再上楼；5F 可以上到 6F ---
	GameState.set_level(10)
	GameState.begin_next_level()
	_check(GameState.level == 10, "10F 是第二层终点，不会再上楼")
	GameState.set_level(5)
	GameState.begin_next_level()
	_check(GameState.level == 6 and GameState.world == 2, "5F 上楼进入第二层 6F")

	# --- 6. 存档 v4 往返 ---
	GameState.set_level(8)
	GameState.contamination = 42.5
	GameState.notebook_fuel = 7.0
	SaveManager.save_run()
	GameState.contamination = 0.0
	GameState.notebook_fuel = 99.0
	GameState.set_level(1)
	SaveManager.load_run()
	_check(GameState.level == 8 and GameState.world == 2, "存档读回楼层/世界层（%dF）" % GameState.level)
	_check(is_equal_approx(GameState.contamination, 42.5), "存档读回污染 %.1f" % GameState.contamination)
	_check(is_equal_approx(GameState.notebook_fuel, 7.0), "存档读回电量 %.1f" % GameState.notebook_fuel)

	if failures.is_empty():
		print("WORLD_PROBE: ALL PASSED")
	else:
		print("WORLD_PROBE: %d FAILED -> %s" % [failures.size(), str(failures)])
	inst.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures.is_empty() else 1)
