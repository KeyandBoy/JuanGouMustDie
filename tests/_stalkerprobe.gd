extends Node

func _ready() -> void:
	var failures: Array[String] = []
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()
	GameState.seed_value = 4242
	GameState.warnings = 0
	inst._start_level()
	for i in 6:
		await get_tree().process_frame

	var hall_i: int = inst.map.room_types.find("hall")
	_check(hall_i >= 0 and inst.map.explored[hall_i], "fog: hall lit at start", failures)
	var dark_i := -1
	for i in inst.map.rooms.size():
		if i != hall_i and not inst.map.explored[i]:
			dark_i = i
			break
	_check(dark_i >= 0, "fog: other rooms start dark", failures)
	if dark_i >= 0:
		inst.player.position = inst.map.rooms[dark_i].get_center()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(inst.map.explored[dark_i], "fog: entering reveals room", failures)

	inst.fog.forget_after = 0.15
	inst.fog.forget_ramp = 0.05
	inst.fog.forget_clear_time = 0.05
	var forget_i := -1
	for i in inst.map.rooms.size():
		var t := String(inst.map.room_types[i])
		if t != "hall" and t != "stair" and t != "corridor":
			forget_i = i
			break
	_check(forget_i >= 0, "forget: normal room found", failures)
	if forget_i >= 0:
		inst.player.position = inst.map.rooms[forget_i].get_center()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(inst.map.explored[forget_i], "forget: target room explored", failures)
		var corridor_spot: Vector2 = inst.map.corridor_rect.get_center()
		inst.player.position = corridor_spot
		inst.camera.reset_smoothing()
		inst.camera.global_position = corridor_spot
		GameState.level = 1
		await get_tree().create_timer(0.4).timeout
		_check(inst.fog.forget_amount(forget_i) < 0.01, "forget: level 1 never fogs (%.2f)" % inst.fog.forget_amount(forget_i), failures)
		GameState.level = 2
		await get_tree().create_timer(0.4).timeout
		_check(inst.fog.forget_amount(forget_i) > 0.9, "forget: level 2 room fogs after leaving (%.2f)" % inst.fog.forget_amount(forget_i), failures)
		inst.player.position = inst.map.rooms[forget_i].get_center()
		await get_tree().create_timer(0.3).timeout
		_check(inst.fog.forget_amount(forget_i) < 0.05, "forget: re-entry clears fog (%.2f)" % inst.fog.forget_amount(forget_i), failures)
	GameState.level = 1
	inst.fog.forget_after = 30.0
	inst.fog.forget_ramp = 5.0
	inst.fog.forget_clear_time = 1.5

	var qdesk: Dictionary = inst.map.desks[0]
	var dpos: Vector2 = qdesk["pos"]
	var study_spot := Vector2.ZERO
	for off: Vector2 in [Vector2(0.0, 30.0), Vector2(0.0, -30.0), Vector2(30.0, 0.0), Vector2(-30.0, 0.0), Vector2(0.0, 40.0), Vector2(40.0, 0.0)]:
		if inst.map.is_walkable(dpos + off):
			study_spot = dpos + off
			break
	inst.player.position = study_spot
	inst.camera.reset_smoothing()
	inst.camera.global_position = inst.player.position
	await get_tree().create_timer(0.1).timeout

	var students: Array = get_tree().get_nodes_in_group("students")
	var watcher: Node2D = null
	for offs: Vector2 in [Vector2(70.0, 0.0), Vector2(-70.0, 0.0), Vector2(0.0, 70.0), Vector2(0.0, -70.0), Vector2(70.0, 70.0), Vector2(-70.0, 70.0), Vector2(70.0, -70.0), Vector2(-70.0, -70.0)]:
		var sp: Vector2 = study_spot + offs
		if not inst.map.is_walkable(sp):
			continue
		if not inst.map.vision_clear(sp, study_spot):
			continue
		watcher = students[0]
		watcher.position = sp
		watcher.facing = (study_spot - sp).normalized()
		watcher.state = "patrol"
		watcher.path = PackedVector2Array()
		break
	_check(watcher != null and inst.map.vision_clear(watcher.position, study_spot), "watcher placed with clear LOS", failures)

	var saw_stalk := false
	for f in 600:
		await get_tree().physics_frame
		for s in students:
			if s.state == "stalk":
				saw_stalk = true
	_check(GameState.warnings == 0, "EXPLORING stare never catches (warnings=%d)" % GameState.warnings, failures)
	_check(not saw_stalk, "warnings 0: stare never enters stalk", failures)

	inst._toggle_study()
	_check(inst.quiz.is_open, "study starts with quiz open", failures)
	var caught := false
	for f in 1800:
		await get_tree().physics_frame
		if GameState.warnings >= 1:
			caught = true
			break
	_check(caught, "caught while studying within 30s (warnings=%d)" % GameState.warnings, failures)
	_check(not inst.quiz.is_open, "quiz closed on catch", failures)
	_check(not inst.studying, "study session interrupted", failures)
	_check(inst.player.position.distance_to(study_spot) < 1.0, "no teleport after quiz catch (pos=%s)" % inst.player.position, failures)
	_check(GameState.run_state == GameState.RunState.EXPLORING, "run_state back to EXPLORING", failures)

	var saw_search := false
	for f in 1100:
		await get_tree().physics_frame
		for s in students:
			if s.state == "search":
				saw_search = true
	_check(saw_search, "mark drift: investigator search after warning", failures)

	if watcher != null and is_instance_valid(watcher):
		var wspot := Vector2.ZERO
		var got_wspot := false
		for offs2: Vector2 in [Vector2(70.0, 0.0), Vector2(-70.0, 0.0), Vector2(0.0, 70.0), Vector2(0.0, -70.0), Vector2(70.0, 70.0), Vector2(-70.0, 70.0), Vector2(70.0, -70.0), Vector2(-70.0, -70.0)]:
			var sp2: Vector2 = study_spot + offs2
			if not inst.map.is_walkable(sp2):
				continue
			if not inst.map.vision_clear(sp2, study_spot):
				continue
			wspot = sp2
			got_wspot = true
			break
		if got_wspot:
			watcher.position = wspot
			watcher.facing = (study_spot - wspot).normalized()
			watcher.state = "patrol"
			watcher.path = PackedVector2Array()
			var saw_stalk2 := false
			for f2 in 600:
				await get_tree().physics_frame
				if watcher.state == "stalk":
					saw_stalk2 = true
					break
			_check(saw_stalk2, "warnings>=1: stare enters stalk", failures)

		var pair_study := Vector2.ZERO
		var pair_watch := Vector2.INF
		for dx in range(-24, 25, 2):
			for dy in range(-24, 25, 2):
				var a: Vector2 = dpos + Vector2(dx, dy)
				if not inst.map.is_walkable(a):
					continue
				for d2: Vector2 in [Vector2(0.0, -24.0), Vector2(0.0, 24.0), Vector2(-24.0, 0.0), Vector2(24.0, 0.0), Vector2(0.0, -18.0), Vector2(0.0, 18.0), Vector2(-18.0, 0.0), Vector2(18.0, 0.0), Vector2(0.0, -16.0), Vector2(0.0, 16.0), Vector2(-16.0, 0.0), Vector2(16.0, 0.0)]:
					var b: Vector2 = a + d2
					var dd: float = a.distance_to(b)
					if dd >= 26.0 or dd < 10.0:
						continue
					if not inst.map.is_walkable(b):
						continue
					if inst.map.vision_clear(a, b):
						continue
					pair_study = a
					pair_watch = b
					break
				if pair_watch != Vector2.INF:
					break
			if pair_watch != Vector2.INF:
				break
		_check(pair_watch != Vector2.INF, "blocked pair found (studying across furniture)", failures)

		var clear_watch := Vector2.INF
		if pair_watch != Vector2.INF:
			for d3: Vector2 in [Vector2(24.0, 0.0), Vector2(-24.0, 0.0), Vector2(0.0, 24.0), Vector2(0.0, -24.0), Vector2(20.0, 12.0), Vector2(-20.0, 12.0), Vector2(20.0, -12.0), Vector2(-20.0, -12.0)]:
				var c: Vector2 = pair_study + d3
				if pair_study.distance_to(c) >= 26.0:
					continue
				if not inst.map.is_walkable(c):
					continue
				if not inst.map.vision_clear(pair_study, c):
					continue
				clear_watch = c
				break
			_check(clear_watch != Vector2.INF, "clear pair found (unblocked LOS)", failures)

			inst.player.position = pair_study
			inst.camera.reset_smoothing()
			inst.camera.global_position = inst.player.position
			inst.study_hunt_timer = 99999.0
			for s in students:
				if s != watcher and is_instance_valid(s):
					s.stun(5.0)
					s.position = inst.map.exit_pos
			inst._toggle_study()
			_check(inst.quiz.is_open, "study opens at blocked spot", failures)
			var w_before: int = GameState.warnings
			var blocked_catch := false
			var saw_clear := false
			var saved_speed: float = watcher.speed
			var saved_chase: float = watcher.chase_speed
			# 先摆位再进循环，否则第一次物理步用的是旧位置（可能刚好有视线）
			watcher.position = pair_watch
			watcher.velocity = Vector2.ZERO
			watcher.path = PackedVector2Array()
			watcher.speed = 0.0
			watcher.chase_speed = 0.0
			watcher.facing = (inst.player.position - watcher.position).normalized()
			watcher.can_see = false
			for f3 in 300:
				await get_tree().physics_frame
				inst.study_hunt_timer = 99999.0
				watcher.position = pair_watch
				watcher.velocity = Vector2.ZERO
				watcher.path = PackedVector2Array()
				watcher.speed = 0.0
				watcher.chase_speed = 0.0
				watcher.facing = (inst.player.position - watcher.position).normalized()
				watcher.alert_level = watcher.max_alert
				for s in students:
					if s != watcher and is_instance_valid(s):
						s.stun(2.0)
				if watcher.can_see:
					saw_clear = true
				if GameState.warnings > w_before:
					blocked_catch = true
					break
			watcher.speed = saved_speed
			watcher.chase_speed = saved_chase
			_check(not saw_clear, "blocked LOS: watcher never gains sight through furniture", failures)
			_check(not blocked_catch, "blocked LOS: no catch in 300 frames (warnings=%d)" % GameState.warnings, failures)
			_check(inst.quiz.is_open, "blocked LOS: quiz still open", failures)

			if not blocked_catch and clear_watch != Vector2.INF:
				var cleared_catch := false
				for f4 in 600:
					await get_tree().physics_frame
					inst.study_hunt_timer = 99999.0
					watcher.position = clear_watch
					watcher.velocity = Vector2.ZERO
					watcher.path = PackedVector2Array()
					watcher.speed = 0.0
					watcher.chase_speed = 0.0
					watcher.facing = (inst.player.position - watcher.position).normalized()
					watcher.alert_level = watcher.max_alert
					for s in students:
						if s != watcher and is_instance_valid(s):
							s.stun(2.0)
					if GameState.warnings >= w_before + 1:
						cleared_catch = true
						break
				watcher.speed = saved_speed
				watcher.chase_speed = saved_chase
				_check(cleared_catch, "clear LOS: catch happens once unblocked (warnings=%d)" % GameState.warnings, failures)

	if failures.is_empty():
		print("STALKER_PROBE: ALL PASSED")
	else:
		print("STALKER_PROBE: %d FAILURES" % failures.size())
		for f in failures:
			print("  FAIL: ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)

func _check(cond: bool, label: String, failures: Array[String]) -> void:
	if cond:
		print("  PASS: ", label)
	else:
		failures.append(label)
		print("  FAIL: ", label)
