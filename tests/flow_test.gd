extends Node

var watch_inst = null
var watch_active := false
var watch_inside := false

func _process(_delta: float) -> void:
	if watch_active and not watch_inside and watch_inst != null:
		if watch_inst._obstacle_ahead(watch_inst.player.position):
			watch_inside = true

func _ready() -> void:
	var failures: Array[String] = []

	_check(GameState != null, "GameState autoload exists", failures)
	_check(QuestionBank != null, "QuestionBank autoload exists", failures)
	_check(SaveManager != null, "SaveManager autoload exists", failures)

	var math_count := QuestionBank.get_question_count("junior", "math")
	_check(math_count > 0, "junior math has questions (%d)" % math_count, failures)

	var q := QuestionBank.pick_question("junior", ["math"])
	_check(not q.is_empty(), "pick_question returns a question", failures)
	_check(q.has("prompt") and q.has("answer"), "question has prompt and answer", failures)

	var q2 := QuestionBank.pick_question("junior", ["math", "english"], {q.get("id", ""): true})
	_check(not q2.is_empty() and q2.get("id", "") != q.get("id", ""), "exclude works", failures)

	var r := QuestionBank.import_csv("grade,subject,type,prompt,opt1,opt2,opt3,opt4,answer\njunior,math,choice,2+2=?,1,2,3,4,3\njunior,math,fill,3+3=?,,,,,6\n")
	_check(r.get("ok", false) and r.get("added", 0) == 2, "CSV import adds 2 questions (got %d)" % r.get("added", 0), failures)

	var json_text := JSON.stringify({"questions": [{"grade": "primary", "subject": "math", "type": "fill", "prompt": "导入测试题", "answer": "42"}]})
	var rj := QuestionBank.import_json(json_text)
	_check(rj.get("ok", false) and rj.get("added", 0) == 1, "JSON import adds 1 question", failures)

	var conv_ok := true
	var conv_n := 0
	for i in 8:
		var cq: Dictionary = QuestionBank.pick_question("junior", ["math", "english", "physics"])
		if cq.is_empty():
			conv_ok = false
			continue
		var opts = cq.get("options", [])
		conv_n += 1
		if String(cq.get("type", "")) != "choice" or not (opts is Array) or opts.size() < 4:
			conv_ok = false
		elif not opts.has(String(cq.get("answer", ""))):
			conv_ok = false
	_check(conv_ok and conv_n == 8, "picked questions all choice with 4 options + answer included", failures)

	var total := QuestionBank.get_total_count()
	_check(total >= 200, "tiered bank has >=200 questions (%d)" % total, failures)
	var all_tiers := true
	for t in range(1, 8):
		if QuestionBank.get_tier_count(t) < 20:
			all_tiers = false
	_check(all_tiers, "all 7 tiers populated", failures)

	var prompts := {}
	var dup := 0
	var empty_prompt := 0
	var bad_struct := 0
	for t in QuestionBank.tiers:
		for cq2 in QuestionBank.tiers[t]:
			var p2 := String(cq2.get("prompt", "")).strip_edges()
			if p2 == "":
				empty_prompt += 1
			elif prompts.has(p2):
				dup += 1
			prompts[p2] = true
			var typ2 := String(cq2.get("type", ""))
			var ans2 := String(cq2.get("answer", "")).strip_edges()
			if ans2 == "":
				bad_struct += 1
			elif typ2 == "choice":
				var ch2: Array = cq2.get("options", [])
				if ch2.size() != 4 or not ch2.has(ans2):
					bad_struct += 1
	_check(empty_prompt == 0, "content: no empty prompts (%d)" % empty_prompt, failures)
	_check(dup == 0, "content: no duplicate prompts (%d)" % dup, failures)
	_check(bad_struct == 0, "content: choice questions have 4 options incl. answer (%d bad)" % bad_struct, failures)

	var idx_hist := [0, 0, 0, 0]
	var pos_checked := 0
	for t in QuestionBank.tiers:
		for cq4 in QuestionBank.tiers[t]:
			var o4: Array = cq4.get("options", [])
			var ai4 := o4.find(String(cq4.get("answer", "")))
			if o4.size() == 4 and ai4 >= 0:
				idx_hist[ai4] += 1
				pos_checked += 1
	var max_share := 0.0
	for n in idx_hist:
		max_share = maxf(max_share, float(n) / float(maxi(pos_checked, 1)))
	_check(pos_checked >= 200 and max_share <= 0.45, "answer positions balanced (%d checked, max %.0f%%)" % [pos_checked, max_share * 100.0], failures)

	var warmup_ok := true
	for i in 30:
		var wq: Dictionary = QuestionBank.pick_tiered(0)
		var wt := int(wq.get("tier", 0))
		if wt < 1 or wt > 2:
			warmup_ok = false
			break
	_check(warmup_ok, "first 3 answers only draw tiers 1-2", failures)

	var high := 0
	for i in 60:
		var hq: Dictionary = QuestionBank.pick_tiered(10)
		if int(hq.get("tier", 0)) >= 3:
			high += 1
	_check(high > 0, "later answers can draw tier 3+ (%d/60)" % high, failures)

	var repeat := false
	var seen_ids: Array[String] = []
	for i in 10:
		var rq: Dictionary = QuestionBank.pick_tiered(10)
		var rid := String(rq.get("id", ""))
		if seen_ids.has(rid):
			repeat = true
		seen_ids.append(rid)
	_check(not repeat, "recent questions are not repeated", failures)

	GameState.start_run("junior", ["math"])
	_check(GameState.run_state == GameState.RunState.EXPLORING, "start_run -> EXPLORING", failures)
	_check(is_equal_approx(GameState.emptiness, 50.0), "emptiness starts at 50", failures)
	_check(GameState.study == 0.0, "study starts at 0", failures)

	_check(is_equal_approx(GameState.study_goal, 5.0), "level 1 goal is 5 net-correct (%.1f)" % GameState.study_goal, failures)
	GameState.answer_efficiency = 1.0
	for i in 5:
		GameState.on_correct_answer()
	_check(GameState.study >= 5.0, "5 correct answers reach level 1 goal (%.1f)" % GameState.study, failures)
	_check(GameState.run_state == GameState.RunState.CLEARED, "goal reached -> CLEARED", failures)
	_check(GameState.quiz_correct == 5, "quiz_correct tracks", failures)

	GameState.set_level(4)
	_check(is_equal_approx(GameState.study_goal, 15.0), "level 4 goal is 15 (%.1f)" % GameState.study_goal, failures)
	GameState.set_level(5)
	_check(is_equal_approx(GameState.study_goal, 20.0), "level 5 goal is 20 (%.1f)" % GameState.study_goal, failures)
	GameState.set_level(1)
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.study = 3.0
	GameState.on_wrong_answer()
	_check(is_equal_approx(GameState.study, 2.0), "wrong answer removes 1 progress (%.1f)" % GameState.study, failures)
	GameState.study = 0.0
	GameState.on_wrong_answer()
	_check(GameState.study == 0.0, "wrong answer never goes below 0 (%.1f)" % GameState.study, failures)

	GameState.start_run("junior", ["math"])
	GameState.answer_efficiency = 1.0
	var hot_seen: Array[int] = []
	var on_hot := func(lv: int) -> void: hot_seen.append(lv)
	GameState.hot_changed.connect(on_hot)
	_check(GameState.hot_level() == 0, "hot: starts at 0", failures)
	_check(is_equal_approx(GameState.hot_multiplier(), 1.0), "hot: multiplier 1.0 at start", failures)
	GameState.on_correct_answer()
	GameState.on_correct_answer()
	_check(GameState.hot_level() == 0, "hot: 2 correct stays 0 (%d)" % GameState.hot_level(), failures)
	GameState.on_correct_answer()
	_check(GameState.hot_level() == 1, "hot: 3 correct -> I (%d)" % GameState.hot_level(), failures)
	_check(is_equal_approx(GameState.hot_multiplier(), 1.1), "hot: 3 correct -> x1.1 (%.2f)" % GameState.hot_multiplier(), failures)
	for i in 3:
		GameState.on_correct_answer()
	_check(GameState.hot_level() == 2, "hot: 6 correct -> II (%d)" % GameState.hot_level(), failures)
	_check(is_equal_approx(GameState.hot_multiplier(), 1.2), "hot: 6 correct -> x1.2 (%.2f)" % GameState.hot_multiplier(), failures)
	for i in 3:
		GameState.on_correct_answer()
	_check(GameState.hot_level() == 3, "hot: 9 correct -> III (%d)" % GameState.hot_level(), failures)
	_check(is_equal_approx(GameState.hot_multiplier(), 1.3), "hot: 9 correct -> x1.3 (%.2f)" % GameState.hot_multiplier(), failures)
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.study = 0.0
	GameState.on_correct_answer()
	_check(is_equal_approx(GameState.study, 1.3), "hot: III gain x1.3 (%.2f)" % GameState.study, failures)
	GameState.on_wrong_answer()
	_check(GameState.hot_level() == 0, "hot: wrong answer breaks to 0 (%d)" % GameState.hot_level(), failures)
	_check(hot_seen.has(1) and hot_seen.has(2) and hot_seen.has(3), "hot: hot_changed emits 1/2/3 (%s)" % str(hot_seen), failures)
	GameState.hot_changed.disconnect(on_hot)
	GameState.correct_streak = 5
	GameState.break_hot()
	_check(GameState.hot_level() == 0, "hot: break_hot resets streak", failures)

	GameState.inventory.clear()
	GameState.upgrades.clear()
	GameState.stars = 99
	_check(GameState.item_capacity() == 1, "base capacity is 1 (%d)" % GameState.item_capacity(), failures)
	_check(GameState.add_item("coffee"), "add_item accepts known id", failures)
	_check(not GameState.add_item("bread"), "inventory caps at base capacity", failures)
	_check(GameState.buy_upgrade("capacity"), "buy capacity upgrade", failures)
	_check(GameState.buy_upgrade("capacity"), "buy capacity upgrade 2", failures)
	_check(GameState.item_capacity() == 3, "capacity upgrades to 3 (%d)" % GameState.item_capacity(), failures)
	GameState.add_item("bread")
	GameState.add_item("smoke")
	_check(not GameState.add_item("shoes"), "inventory caps at 3", failures)
	_check(GameState.inventory.size() == 3, "inventory holds 3 (%d)" % GameState.inventory.size(), failures)
	_check(GameState.inventory_item_id(0) == "coffee" and GameState.inventory_item_count(0) == 1, "slot api reads id/count", failures)
	var slot_hits: Array[int] = []
	var on_slot := func(i: int): slot_hits.append(i)
	GameState.inventory_slot_changed.connect(on_slot)
	_check(GameState.move_inventory_slot(0, 2) and GameState.inventory_item_id(2) == "coffee", "move_inventory_slot swaps", failures)
	GameState.inventory_slot_changed.disconnect(on_slot)
	_check(slot_hits.has(0) and slot_hits.has(2), "slot_changed emits both indices (%s)" % str(slot_hits), failures)
	_check(GameState.item_def("coffee").display_name == "咖啡" and GameState.item_def("coffee").stack_max >= 1, "item_def resource resolves", failures)
	GameState.move_inventory_slot(2, 0)
	_check(GameState.remove_item_at(0) == "coffee", "remove_item_at returns id", failures)
	_check(GameState.ability("notes") == 0, "abilities default to 0", failures)
	GameState.set_ability("notes")
	_check(GameState.ability("notes") == 1, "set_ability stores", failures)
	_check(not GameState.exam_hint, "exam hint locked by default", failures)
	_check(not GameState.get_item_def("intel").is_empty(), "intel item defined", failures)
	GameState.intel_reveal_timer = 5.0
	_check(GameState.intel_reveal_timer > 0.0, "intel reveal timer settable", failures)
	GameState.intel_reveal_timer = 0.0

	GameState.warnings = 0
	GameState.emptiness = 50
	GameState.study = 0
	GameState.run_state = GameState.RunState.EXPLORING
	for i in 3:
		GameState.add_warning()
	_check(GameState.run_state == GameState.RunState.GAMEOVER, "3 warnings -> GAMEOVER", failures)

	GameState.warnings = 0
	GameState.emptiness = 1.5
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.on_wrong_answer()
	_check(GameState.run_state == GameState.RunState.GAMEOVER, "emptiness 0 -> GAMEOVER", failures)
	_check(GameState.correct_streak == 0, "wrong answer resets streak", failures)

	var ok_save := SaveManager.save_run()
	_check(ok_save, "save_run works", failures)
	var ok_load := SaveManager.load_run()
	_check(ok_load, "load_run works", failures)

	var map_script = load("res://scripts/school_map.gd")
	var probe: Node2D = map_script.new()
	add_child(probe)
	for s in [7, 21, 99, 2024, 31337]:
		probe.generate(s, 0)
		var rc: int = probe.rooms.size()
		_check(rc >= 6 and rc <= 10, "seed %d room count %d in 6..10" % [s, rc], failures)
		_check(probe.is_connected_plan(), "seed %d plan connected" % s, failures)
		_check(probe.desks.size() > 0, "seed %d has desks (%d)" % [s, probe.desks.size()], failures)
		var astar_ok := true
		for ri in probe.rooms.size():
			var target: Vector2 = probe._walkable_center(probe.rooms[ri])
			var p: PackedVector2Array = probe.find_path(probe.exit_pos, target)
			if p.is_empty() or p[p.size() - 1].distance_to(target) > 40.0:
				astar_ok = false
				break
			var origin: Vector2 = probe.exit_pos
			for pi in p.size():
				var steps: int = maxi(1, int(origin.distance_to(p[pi]) / 3.0))
				for st in range(1, steps + 1):
					if not probe.is_walkable(origin.lerp(p[pi], float(st) / float(steps))):
						astar_ok = false
						break
				if not astar_ok:
					break
				origin = p[pi]
			if not astar_ok:
				break
		_check(astar_ok, "seed %d astar path is walkable and reaches every room" % s, failures)
		var floor_cells := 0
		var floor_expected := 0
		if probe._floor_layer != null:
			floor_cells = probe._floor_layer.get_used_cells().size()
		for v in probe.grid:
			if v == probe.FLOOR:
				floor_expected += 1
		_check(probe._floor_layer != null and probe._wall_layer != null, "seed %d tilemap layers exist" % s, failures)
		_check(floor_cells == floor_expected, "seed %d tilemap covers all floor cells (%d/%d)" % [s, floor_cells, floor_expected], failures)

	probe.generate(7, 0)
	_check(probe.door_nodes.size() == probe.rooms.size(), "one door per room (%d/%d)" % [probe.door_nodes.size(), probe.rooms.size()], failures)

	var desk_grid_ok := true
	var desk_block_ok := true
	for d in probe.desks:
		var dr: Rect2 = d["rect"]
		if not is_equal_approx(dr.size.x, 40.0) or not is_equal_approx(dr.size.y, 20.0):
			desk_grid_ok = false
		if not is_equal_approx(dr.position.x, round(dr.position.x / 20.0) * 20.0) or not is_equal_approx(dr.position.y, round(dr.position.y / 20.0) * 20.0):
			desk_grid_ok = false
		for p in [dr.position + Vector2(10.0, 10.0), dr.position + Vector2(30.0, 10.0)]:
			if probe.is_walkable(p):
				desk_block_ok = false
	_check(desk_grid_ok, "desks snapped to 2x1 grid", failures)
	_check(desk_block_ok, "desk cells block walking", failures)

	var box_block_ok: bool = probe.box_rects.size() > 0
	for br in probe.box_rects:
		if probe.is_walkable(br.get_center()):
			box_block_ok = false
	_check(box_block_ok, "box cells block walking (%d)" % probe.box_rects.size(), failures)

	var door: Node2D = probe.door_nodes[0]
	var across := 34.0
	var a: Vector2 = door.position + (Vector2(0.0, -across) if door.axis == "h" else Vector2(-across, 0.0))
	var b: Vector2 = door.position + (Vector2(0.0, across) if door.axis == "h" else Vector2(across, 0.0))
	_check(not door.is_open, "doors start closed", failures)
	_check(probe.door_blocks_point(door.position), "closed door blocks point", failures)
	_check(not probe.vision_clear(a, b), "closed door blocks sight", failures)
	_check(not probe.sound_clear(a, b), "closed door blocks sound", failures)
	door.set_open(true, false)
	_check(not probe.door_blocks_point(door.position), "open door releases point", failures)
	_check(probe.vision_clear(a, b), "open door clears sight", failures)
	_check(probe.sound_clear(a, b), "open door clears sound", failures)
	door.set_open(false, false)
	probe.queue_free()

	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "main.tscn loads", failures)
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(inst.map != null and inst.map.rooms.size() > 0, "map generated (%d rooms)" % inst.map.rooms.size() if inst.map else "map null", failures)
	_check(inst.player != null, "player spawned", failures)
	_check(inst.hud != null, "hud spawned", failures)
	_check(inst.quiz != null, "quiz spawned", failures)

	inst._start_level(3)
	await get_tree().process_frame
	_check(GameState.level == 3, "level select starts level 3 (%d)" % GameState.level, failures)
	_check(is_equal_approx(inst.fog.halo_clear, 130.0), "level 3 halo shrinks (%.0f)" % inst.fog.halo_clear, failures)
	inst._start_level(1)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(GameState.level == 1, "level select returns to level 1 (%d)" % GameState.level, failures)
	_check(is_equal_approx(inst.fog.halo_clear, 160.0), "level 1 halo full (%.0f)" % inst.fog.halo_clear, failures)
	var students := get_tree().get_nodes_in_group("students")
	_check(students.size() == 7, "7 students spawned (%d)" % students.size(), failures)
	_check(inst.map.rooms.size() > 0, "map rooms after start (%d)" % inst.map.rooms.size(), failures)
	_check(inst.map.is_connected_plan(), "start-level plan connected", failures)
	_check(inst.world_modulate != null and inst.world_modulate.visible, "lighting: canvas modulate active", failures)
	_check(inst.player_light != null and inst.player_light.get_parent() == inst.player, "lighting: player light on player", failures)
	_check(inst.level_lights != null and inst.level_lights.get_child_count() >= 1, "lighting: lamps spawned (%d)" % (inst.level_lights.get_child_count() if inst.level_lights else 0), failures)
	var light_dev := DevMode.lighting
	DevMode.lighting = false
	inst._apply_lighting_visibility()
	_check(not inst.world_modulate.visible and not inst.player_light.visible, "lighting: dev toggle hides lights", failures)
	DevMode.lighting = true
	inst._apply_lighting_visibility()
	_check(inst.world_modulate.visible and inst.player_light.visible, "lighting: dev toggle restores lights", failures)
	DevMode.lighting = light_dev
	_check(inst.minimap != null, "minimap spawned", failures)

	var desk_ok := true
	for d in inst.map.desks:
		if inst.map.room_index_at(d["pos"]) != d["room"]:
			desk_ok = false
	_check(desk_ok, "desks belong to their rooms", failures)

	var away_spot := Vector2.INF
	for dx in range(30, int(inst.map.corridor_rect.size.x) - 30, 15):
		var p := Vector2(inst.map.corridor_rect.position.x + float(dx), inst.map.corridor_rect.get_center().y)
		if not inst.map.is_walkable(p):
			continue
		inst.player.position = p
		if inst._nearest_desk(60.0) != null:
			continue
		away_spot = p
		break
	_check(away_spot != Vector2.INF, "off-desk study spot found", failures)
	if away_spot != Vector2.INF:
		inst.player.position = away_spot
		inst.camera.reset_smoothing()
		inst.camera.global_position = away_spot
		GameState.warnings = 0
		inst._toggle_study()
		_check(inst.quiz.is_open, "study works anywhere (off-desk)", failures)
		_check(is_equal_approx(inst.study_efficiency, 0.5), "off-desk efficiency 0.5 (%.2f)" % inst.study_efficiency, failures)
		inst.quiz.close()
		inst._stop_study()

	GameState.warnings = 0
	GameState.emptiness = 50
	inst._on_player_caught(null)
	_check(GameState.warnings == 1, "caught adds a warning (%d)" % GameState.warnings, failures)
	_check(inst.player.position.distance_to(inst.map.exit_pos) < 1.0, "caught respawns at hall", failures)
	_check(is_equal_approx(GameState.emptiness, 44.0), "caught costs emptiness (%.1f)" % GameState.emptiness, failures)

	var qz := QuestionBank.pick_question(GameState.grade_id, GameState.subjects)
	inst.quiz.open(qz)
	await get_tree().create_timer(0.5).timeout
	_check(inst.camera.zoom.x > inst.camera_zoom_base + 0.1, "quiz zooms camera in (%.2f)" % inst.camera.zoom.x, failures)
	inst.quiz.close()
	await get_tree().create_timer(0.5).timeout
	_check(absf(inst.camera.zoom.x - inst.camera_zoom_base) < 0.05, "camera restores zoom (%.2f)" % inst.camera.zoom.x, failures)

	var d0: Node2D = inst.map.door_nodes[0]
	d0.set_open(false)
	var nsign := Vector2(0.0, -1.0) if d0.axis == "h" else Vector2(-1.0, 0.0)
	inst.player.position = d0.position + nsign * 20.0
	var ok_open: bool = d0.toggle_from_player()
	_check(ok_open and d0.is_open, "door opens via player toggle", failures)
	_check(is_equal_approx(d0.dir, 1.0), "door swings away from opener (dir=%s)" % str(d0.dir), failures)

	var n1: Node2D = students[0]
	n1.position = d0.position - nsign * 20.0
	n1.stun_timer = 0.0
	var ok_close: bool = d0.toggle_from_player()
	_check(ok_close and not d0.is_open, "door closes with NPC on line (npc does not block)", failures)
	_check(n1.stun_timer > 0.0, "close slam stuns NPC on swing side (stun=%.1f)" % n1.stun_timer, failures)

	var n2: Node2D = students[1]
	n2.position = d0.position - nsign * 20.0
	n2.stun_timer = 0.0
	d0.toggle_from_player()
	_check(d0.is_open and n2.stun_timer > 0.0, "open slam stuns NPC on swing side (stun=%.1f)" % n2.stun_timer, failures)

	inst.player.position = d0.position + nsign * 10.0
	var self_block: bool = d0.toggle_from_player()
	_check(not self_block and d0.is_open, "self-block: cannot close while standing in doorway", failures)

	for s in get_tree().get_nodes_in_group("students"):
		s.state = "patrol"
		s.path = PackedVector2Array()
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.warnings = 0
	await get_tree().create_timer(0.4).timeout
	_check(AudioManager.current_key == "happy", "audio: exploring uses happy (%s)" % AudioManager.current_key, failures)
	_check(AudioManager.is_playing(), "audio: player is playing", failures)
	AudioManager.set_muted(true)
	_check(AudioManager.muted and AudioServer.is_bus_mute(0), "audio: mute toggle mutes master bus", failures)
	AudioManager.set_muted(false)
	_check(not AudioManager.muted, "audio: unmute restores flag", failures)
	GameState.warnings = 1
	await get_tree().create_timer(0.4).timeout
	_check(AudioManager.current_key == "tension", "audio: warning 1 uses tension (%s)" % AudioManager.current_key, failures)
	GameState.warnings = 2
	await get_tree().create_timer(0.4).timeout
	_check(AudioManager.current_key == "chase", "audio: warning 2 uses chase (%s)" % AudioManager.current_key, failures)
	for s2 in get_tree().get_nodes_in_group("students"):
		s2.stun(5.0)
		s2.position = inst.map.exit_pos
	GameState.run_state = GameState.RunState.QUIZ
	await get_tree().create_timer(0.4).timeout
	_check(AudioManager.current_key == "absurd", "audio: quiz uses absurd (%s)" % AudioManager.current_key, failures)
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.warnings = 0
	inst.player.stun_timer = 0.0

	GameState.dash_energy = 100.0
	inst.player.dashing = false
	inst.player._start_dash()
	_check(inst.player.is_dodging(), "dash: starts when bar full", failures)
	inst._on_player_caught(null)
	_check(GameState.warnings == 0, "dash: immune to catch (warnings=%d)" % GameState.warnings, failures)
	await get_tree().create_timer(0.3).timeout
	_check(GameState.dash_energy < 95.0, "dash: bar drains (%.0f)" % GameState.dash_energy, failures)
	var mid_energy: float = GameState.dash_energy
	inst.player.dashing = false
	await get_tree().create_timer(0.3).timeout
	_check(GameState.dash_energy > mid_energy, "dash: bar recharges (%.0f)" % GameState.dash_energy, failures)
	GameState.dash_energy = 50.0
	inst.player.dashing = false
	inst.player._start_dash()
	_check(not inst.player.dashing, "dash: cannot start without full bar", failures)
	GameState.dash_energy = 0.0
	inst._on_player_caught(null)
	_check(GameState.warnings == 1, "dash over: catch applies again (%d)" % GameState.warnings, failures)
	GameState.warnings = 0
	inst.player.dashing = false
	GameState.dash_energy = 0.0

	inst.fog.set_tyrant_active(true, 4)
	await get_tree().create_timer(0.4).timeout
	_check(inst.fog.ambient_target > 0.0, "tyrant activates ambient fog target (%.2f)" % inst.fog.ambient_target, failures)
	_check(inst.fog.ambient_density > 0.0, "ambient fog ramps up (%.2f)" % inst.fog.ambient_density, failures)
	inst.fog.set_tyrant_active(false, 4)

	var tyrant_probe: CharacterBody2D = load("res://scripts/tyrant.gd").new()
	add_child(tyrant_probe)
	tyrant_probe.setup(inst.map, inst.player, 4)
	tyrant_probe.position = inst.player.position
	_check(is_equal_approx(tyrant_probe.aura_factor(), 0.7), "tyrant aura -30%% in range (%.2f)" % tyrant_probe.aura_factor(), failures)
	tyrant_probe.position = inst.player.position + Vector2(600, 600)
	_check(is_equal_approx(tyrant_probe.aura_factor(), 1.0), "tyrant aura recovers when far (%.2f)" % tyrant_probe.aura_factor(), failures)
	tyrant_probe.queue_free()

	GameState.stars = 0
	GameState.level_stars.clear()
	GameState.upgrades.clear()
	var base1: float = GameState.star_base_time(1)
	_check(GameState.evaluate_stars(1, base1, 0, 10, 10, 60.0) == 3, "3 stars: fast + clean + accurate", failures)
	_check(GameState.evaluate_stars(1, base1 * 1.2, 1, 10, 7, 150.0) == 2, "2 stars: ok time + 1 catch", failures)
	_check(GameState.evaluate_stars(1, base1 * 9.0, 0, 10, 6, 200.0) == 1, "1 star: quiz-time gate caps", failures)
	_check(GameState.evaluate_stars(1, base1, 0, 10, 5, 60.0) == 1, "accuracy 50%% gates to 1 star", failures)
	_check(GameState.evaluate_stars(1, base1, 0, 10, 10, 150.0) == 2, "quiz time 150s gates to 2 stars", failures)
	var rep3: Dictionary = GameState.star_report(1, base1, 0, 10, 10, 60.0)
	_check(int(rep3["stars"]) == 3 and float(rep3["score"]) >= GameState.STAR_SCORE_3, "star_report weighted >= 85 (%.1f)" % float(rep3["score"]), failures)
	_check(int(GameState.star_report(1, base1, 0, 10, 5, 60.0)["gate"]) == 1, "star_report gate caps low accuracy", failures)
	var dev_unlock: bool = DevMode.unlock_all_levels
	DevMode.unlock_all_levels = false
	GameState.max_cleared_level = 1
	_check(GameState.is_level_unlocked(1), "unlock: level 1 open", failures)
	_check(not GameState.is_level_unlocked(2), "unlock: level 2 locked", failures)
	GameState.mark_level_cleared(1)
	_check(GameState.max_cleared_level == 2 and GameState.is_level_unlocked(2), "unlock: clearing 1 opens 2 (%d)" % GameState.max_cleared_level, failures)
	GameState.mark_level_cleared(1)
	_check(GameState.max_cleared_level == 2, "unlock: replay does not over-unlock (%d)" % GameState.max_cleared_level, failures)
	GameState.max_cleared_level = 3
	_check(SaveManager.save_run(), "save: write unlock", failures)
	GameState.max_cleared_level = 1
	_check(SaveManager.load_run() and GameState.max_cleared_level == 3, "save: max_cleared_level round-trips (%d)" % GameState.max_cleared_level, failures)
	var legacy_ok: bool = SaveManager.load_json_string(JSON.stringify({"level": 1, "level_stars": {"1": 3, "2": 2}}))
	_check(legacy_ok and GameState.max_cleared_level == 3, "save: legacy stars derive unlock (%d)" % GameState.max_cleared_level, failures)
	GameState.story_flags = {"met_librarian": true, "chapter": 2}
	GameState.play_time = 123.5
	_check(SaveManager.save_run(), "save: write v2 fields", failures)
	var raw_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
	_check(int(raw_save.get("version", 0)) == SaveManager.SAVE_VERSION, "save: version stamped (%d)" % int(raw_save.get("version", 0)), failures)
	GameState.story_flags.clear()
	GameState.play_time = 0.0
	_check(SaveManager.load_run(), "save: reload v2 file", failures)
	_check(bool(GameState.story_flags.get("met_librarian", false)) and int(GameState.story_flags.get("chapter", 0)) == 2, "save: story_flags round-trip", failures)
	_check(is_equal_approx(GameState.play_time, 123.5), "save: play_time round-trip (%.1f)" % GameState.play_time, failures)
	var migrated: bool = SaveManager.load_json_string(JSON.stringify({"level": 2, "inventory": []}))
	_check(migrated and GameState.story_flags.is_empty() and GameState.play_time == 0.0, "save: unversioned file migrates to v2 defaults", failures)
	GameState.inventory.clear()
	GameState.add_item("coffee")
	GameState.add_item("bread")
	_check(SaveManager.save_run(), "save: writes slot inventory", failures)
	var raw_inv_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
	var inv_raw = raw_inv_save.get("inventory", [])
	_check(inv_raw is Array and inv_raw.size() >= 1 and inv_raw[0] is Dictionary and String(inv_raw[0].get("id", "")) == "coffee", "save: inventory stored as slot dicts", failures)
	GameState.inventory.clear()
	_check(SaveManager.load_run() and GameState.inventory_item_id(0) == "coffee" and GameState.inventory_item_count(0) == 1, "save: slot inventory round-trips", failures)
	var legacy_inv_ok: bool = SaveManager.load_json_string(JSON.stringify({"version": 2, "level": 1, "inventory": ["smoke", "notes"]}))
	_check(legacy_inv_ok and GameState.inventory_item_id(0) == "smoke" and GameState.inventory.size() == 2, "save: v2 string inventory migrates to slots", failures)
	if not OS.has_feature("web"):
		var corrupt := FileAccess.open(SaveManager.SAVE_PATH, FileAccess.WRITE)
		corrupt.store_string("{broken")
		corrupt.close()
		_check(SaveManager.load_run(), "save: corrupt main falls back to .bak", failures)
		_check(SaveManager.save_run() and SaveManager.load_run(), "save: rewrites after recovery", failures)
	GameState.story_flags.clear()
	GameState.play_time = 0.0
	GameState.level_stars.clear()
	GameState.stars = 0
	GameState.upgrades.clear()
	DevMode.unlock_all_levels = dev_unlock
	_check(GameState.award_stars(1, 3) == 3, "award_stars first clear grants 3", failures)
	_check(GameState.stars == 3, "stars balance after first clear (%d)" % GameState.stars, failures)
	_check(GameState.award_stars(1, 2) == 0, "no stars when replay is worse", failures)
	_check(GameState.award_stars(1, 3) == 0, "no stars when replay ties best", failures)
	_check(GameState.star_best(1) == 3, "level best capped at 3", failures)
	_check(GameState.total_stars_earned() == 3, "total earned 3", failures)

	GameState.stars = 21
	var bought_all := true
	var spend := 0
	for key in GameState.UPGRADE_DEFS:
		var def: Dictionary = GameState.UPGRADE_DEFS[key]
		for i in range(int(def["max"])):
			if not GameState.buy_upgrade(key):
				bought_all = false
			else:
				spend += int(def["cost"])
	_check(bought_all, "shop: can buy every upgrade at max stars", failures)
	_check(spend == 21, "shop: total cost 21 (got %d)" % spend, failures)
	_check(GameState.stars == 0, "shop: stars drained to 0 (%d)" % GameState.stars, failures)
	_check(not GameState.buy_upgrade("capacity"), "shop: cannot over-buy past max", failures)
	_check(GameState.max_warnings == 5, "warnings upgrade: max_warnings 5 (%d)" % GameState.max_warnings, failures)
	_check(GameState.item_capacity() == 3, "capacity upgrade: capacity 3", failures)
	_check(is_equal_approx(GameState.passive_speed_bonus(), 0.12), "speed upgrade: +12%% (%.2f)" % GameState.passive_speed_bonus(), failures)
	_check(is_equal_approx(GameState.dash_charge_bonus(), 0.5), "dash_cd upgrade: +50%% (%.2f)" % GameState.dash_charge_bonus(), failures)
	_check(GameState.dash_segments() == 2, "dash_charges upgrade: 2 segments", failures)
	_check(is_equal_approx(GameState.dash_max_value(), 200.0), "dash_max_value scales to 200 (%.0f)" % GameState.dash_max_value(), failures)
	GameState.stars = 0
	GameState.level_stars.clear()
	GameState.upgrades.clear()
	GameState._recompute_derived()

	# --- 抓人判定圈：360°，与视锥朝向无关，半径远小于视锥 ---
	var guard = get_tree().get_nodes_in_group("students")[0]
	for s in get_tree().get_nodes_in_group("students"):
		s.set_physics_process(false)
	guard.catch_radius = 30.0
	guard.vision_range = 160.0
	guard.vision_angle = 60.0
	var spot: Vector2 = inst.map.exit_pos
	if not inst.map.is_walkable(spot + Vector2(0.0, -20.0)):
		spot = inst.map.corridor_rect.get_center()
	inst.player.position = spot
	inst.player.stun_timer = 0.0
	guard.position = spot + Vector2(0.0, -20.0)
	guard.facing = Vector2.UP
	var to_p: Vector2 = inst.player.position - guard.position
	_check(not guard._can_see_player(to_p, to_p.length()), "catch: player behind guard is not seen", failures)
	_check(guard._in_catch_range(), "catch: 360° circle still catches from behind", failures)
	guard.position = spot + Vector2(0.0, -40.0)
	_check(not guard._in_catch_range(), "catch: beyond radius does not catch (40 > 30)", failures)
	guard.position = spot + Vector2(0.0, -20.0)
	guard.catch_radius = 10.0
	_check(not guard._in_catch_range(), "catch: radius is respected (20 > 10)", failures)
	guard.catch_radius = 30.0

	# --- 弹窗栈：层序 bug 回归（商店在菜单之上、不重入、可逐层返回） ---
	inst._close_all_modals()
	await get_tree().process_frame
	inst._show_menu()
	await get_tree().process_frame
	_check(inst.modal_stack.size() == 1, "modal: menu alone on stack (%d)" % inst.modal_stack.size(), failures)
	var menu_l: CanvasLayer = inst.modal_stack[0] if inst.modal_stack.size() > 0 else null
	inst._show_shop()
	await get_tree().process_frame
	_check(inst.modal_stack.size() == 2, "modal: shop stacks on menu (%d)" % inst.modal_stack.size(), failures)
	var shop_l: CanvasLayer = null
	for m in inst.modal_stack:
		if is_instance_valid(m) and m.has_meta("shop"):
			shop_l = m
	_check(shop_l != null, "modal: shop layer exists", failures)
	if shop_l != null and menu_l != null:
		_check(shop_l.layer > menu_l.layer, "modal: shop above opener (%d > %d)" % [shop_l.layer, menu_l.layer], failures)
		_check(shop_l.layer <= 43, "modal: shop stays below fade layer (%d <= 43)" % shop_l.layer, failures)
		_check(shop_l.layer == 41, "modal: shop uses stack depth (%d)" % shop_l.layer, failures)
	inst._show_shop()
	await get_tree().process_frame
	_check(inst.modal_stack.size() == 2, "modal: shop does not duplicate (%d)" % inst.modal_stack.size(), failures)
	if shop_l != null:
		inst._pop_modal(shop_l)
	await get_tree().process_frame
	_check(inst.modal_stack.size() == 1 and is_instance_valid(menu_l), "modal: closing shop returns to menu", failures)
	inst._close_all_modals()
	await get_tree().process_frame
	_check(not inst._modal_open(), "modal: all closed", failures)
	_check(inst.modal_stack.is_empty(), "modal: stack empty (%d)" % inst.modal_stack.size(), failures)

	# --- 字体兜底：网页端没有系统字体回退，所有中文 Label 必须解析到 zpix ---
	inst._punish_effect(inst.player)
	await get_tree().process_frame
	var fx_root: Control = null
	for c in inst.get_children():
		if c is CanvasLayer and c.layer == inst.L_FX and c.get_child_count() > 0 and c.get_child(0) is Control:
			fx_root = c.get_child(0)
	_check(fx_root != null and fx_root.theme != null, "font: punish fx root has UiTheme", failures)
	var odd_fonts := PackedStringArray()
	var label_count := 0
	for l in _collect_labels(inst, []):
		label_count += 1
		if l.get_theme_font("font") != UiTheme.font():
			odd_fonts.append(String(l.text).substr(0, 8))
	_check(odd_fonts.is_empty(), "font: %d labels all resolve to zpix (odd: %s)" % [label_count, ", ".join(odd_fonts)], failures)

	var tip2: DialogueData = DialogueDb.level_tip(2)
	_check(tip2 != null and tip2.lines.size() >= 1 and tip2.lines[0].text.length() > 0, "dialogue: level 2 tip built", failures)
	_check(DialogueDb.level_tip(6) == null, "dialogue: unknown level has no tip", failures)
	var dlg_ui: Control = load("res://scripts/dialogue_ui.gd").new()
	add_child(dlg_ui)
	var test_dlg: DialogueData = DialogueDb.make("test", [{"speaker": "测试", "text": "你好世界", "flag": "dlg_test"}])
	dlg_ui.start(test_dlg)
	_check(dlg_ui.visible and dlg_ui.typing, "dialogue: starts typing", failures)
	dlg_ui.advance()
	_check(not dlg_ui.typing and dlg_ui._text_label.text == "你好世界", "dialogue: advance completes line", failures)
	var dlg_done: Array[bool] = []
	dlg_ui.finished.connect(func(): dlg_done.append(true))
	dlg_ui.advance()
	_check(dlg_done.size() == 1 and bool(GameState.story_flags.get("dlg_test", false)), "dialogue: finishes and sets story flag", failures)
	dlg_ui.queue_free()
	var handled_dlg: Control = inst.show_dialogue(DialogueDb.make("t2", [{"speaker": "系统", "text": "自动关闭"}]), false)
	_check(handled_dlg != null and inst.get_tree().get_nodes_in_group("ui_modal").size() >= 1, "dialogue: main opens as modal", failures)
	if handled_dlg != null:
		handled_dlg.advance()
		handled_dlg.advance()
		await get_tree().process_frame
		_check(not is_instance_valid(handled_dlg) or handled_dlg.is_queued_for_deletion(), "dialogue: modal closes on finish", failures)

	var dissolve_shader: Shader = load("res://shaders/dither_dissolve.gdshader")
	_check(dissolve_shader != null and dissolve_shader.code.contains("progress"), "fx: dissolve shader loads", failures)
	var outline_shader: Shader = load("res://shaders/outline_glow.gdshader")
	_check(outline_shader != null and outline_shader.code.contains("outline_width"), "fx: outline shader loads", failures)
	var fx_node := ColorRect.new()
	add_child(fx_node)
	var dissolve_tween: Tween = DissolveFx.play(fx_node, 0.05)
	_check(fx_node.material is ShaderMaterial and dissolve_tween != null, "fx: dissolve applies material and tween", failures)
	await get_tree().create_timer(0.15).timeout
	var progress_value := float(fx_node.material.get_shader_parameter("progress")) if fx_node.material else 0.0
	_check(progress_value > 0.9, "fx: dissolve progress animates (%.2f)" % progress_value, failures)
	DissolveFx.restore(fx_node)
	_check(fx_node.material == null, "fx: dissolve restore clears material", failures)
	fx_node.queue_free()

	var drops_before := get_tree().get_nodes_in_group("pickups").size()
	inst._spawn_anti_tyrant_drops()
	await get_tree().process_frame
	var drops_after := get_tree().get_nodes_in_group("pickups").size()
	_check(drops_after >= drops_before + 2, "tyrant: spawns 2 anti-tyrant drops (%d -> %d)" % [drops_before, drops_after], failures)

	var no_icon := PackedStringArray()
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.get("icon_tex") == null:
			no_icon.append(String(p.item_id))
	_check(no_icon.is_empty(), "items: pickups carry icon textures (missing: %s)" % ", ".join(no_icon), failures)
	var missing_icons := PackedStringArray()
	for id in GameState.ITEM_DEFS:
		if UiIcons.item(String(id)) == null:
			missing_icons.append(String(id))
	_check(missing_icons.is_empty(), "items: %d item icons exist (missing: %s)" % [GameState.ITEM_DEFS.size(), ", ".join(missing_icons)], failures)
	_check(inst.item_fx != null, "items: item fx node present", failures)
	if inst.item_fx != null:
		var fx_before: int = inst.item_fx._parts.size()
		inst.item_fx.burst("coffee", inst.player.position)
		_check(inst.item_fx._parts.size() > fx_before, "items: burst spawns fx parts (%d -> %d)" % [fx_before, inst.item_fx._parts.size()], failures)
		inst.item_fx.clear()
		_check(inst.item_fx._parts.is_empty(), "items: clear() empties fx parts", failures)

	var intro_script = load("res://scripts/intro.gd")
	if intro_script != null:
		var intro = intro_script.new()
		var enter := InputEventKey.new()
		enter.keycode = KEY_ENTER
		enter.pressed = true
		intro._input(enter)
		_check(intro._advance and not intro._skip, "intro: Enter advances page (not skip)", failures)
		intro._advance = false
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		intro._input(esc)
		_check(intro._skip, "intro: ESC skips all", failures)
		_check(intro._read_time(intro.SCENES[3]) >= 5.5, "intro: long final scene hold >=5.5s", failures)
		intro.free()
	else:
		_check(false, "intro: script loads", failures)

	var tyrant_script = load("res://scripts/tyrant.gd")
	if tyrant_script != null:
		var ty_probe = tyrant_script.new()
		ty_probe.setup(null, null, 4)
		_check(is_equal_approx(ty_probe.speed, 118.4), "tyrant: level 4 speed is 80%% (%.1f)" % ty_probe.speed, failures)
		ty_probe.setup(null, null, 5)
		_check(is_equal_approx(ty_probe.speed, 126.4), "tyrant: level 5 speed is 80%% (%.1f)" % ty_probe.speed, failures)
		_check(is_equal_approx(float(ty_probe.ATTACK_RECOVER), 3.0), "tyrant: attack recovery +1s", failures)
		ty_probe.free()
	else:
		_check(false, "tyrant: script loads", failures)

	var asc_a := Vector2.ZERO
	var asc_b := Vector2.ZERO
	var asc_ok := false
	for dn in get_tree().get_nodes_in_group("interactables"):
		if not (dn is Node2D):
			continue
		var offs: Array[Vector2] = [Vector2(46.0, 0.0), Vector2(-46.0, 0.0), Vector2(0.0, 46.0), Vector2(0.0, -46.0)]
		for off in offs:
			var aa: Vector2 = dn.position + off
			var bb: Vector2 = dn.position - off
			if inst.map.is_walkable(aa) and inst.map.is_walkable(bb):
				if not inst._obstacle_ahead(aa) and not inst._obstacle_ahead(bb):
					asc_a = aa
					asc_b = bb
					asc_ok = true
					break
		if asc_ok:
			break
	_check(asc_ok, "ascend: forced detour spot found", failures)
	if asc_ok:
		_check(inst._obstacle_ahead(asc_a.lerp(asc_b, 0.5)), "ascend: obstacle probe sees desk midpoint", failures)
		inst.player.position = asc_a
		watch_inst = inst
		watch_inside = false
		watch_active = true
		await inst._ascend_step_to(asc_b)
		watch_active = false
		_check(inst.player.position.distance_to(asc_b) < 6.0, "ascend: walk reaches blocked waypoint (%.1f)" % inst.player.position.distance_to(asc_b), failures)
		_check(not watch_inside, "ascend: detours around obstacle without entering", failures)
		watch_inst = null

	if failures.is_empty():
		print("FLOW_TEST: ALL PASSED")
	else:
		print("FLOW_TEST: %d FAILURES" % failures.size())
		for f in failures:
			print("  FAIL: ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)

func _collect_labels(n: Node, out: Array) -> Array:
	if n is Label:
		out.append(n)
	for c in n.get_children():
		_collect_labels(c, out)
	return out

func _check(cond: bool, label: String, failures: Array[String]) -> void:
	if cond:
		print("  PASS: ", label)
	else:
		failures.append(label)
		print("  FAIL: ", label)
