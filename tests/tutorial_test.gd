extends Node

var failures := 0

func _check(ok: bool, msg: String) -> void:
	if ok:
		print("  PASS: ", msg)
	else:
		failures += 1
		print("  FAIL: ", msg)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _find_script(node: Node, file: String) -> Control:
	for c in node.get_children():
		var s = c.get_script()
		if s != null and String(s.resource_path).ends_with(file):
			return c
		var r := _find_script(c, file)
		if r != null:
			return r
	return null

func _dialogue(inst) -> Control:
	for m in get_tree().get_nodes_in_group("ui_modal"):
		var d := _find_script(m, "dialogue_ui.gd")
		if d != null:
			return d
	return null

func _dismiss_all(inst) -> void:
	var guard := 0
	while guard < 60:
		guard += 1
		var ui := _dialogue(inst)
		if ui == null:
			if not get_tree().paused:
				break
			await get_tree().create_timer(0.05).timeout
			continue
		ui.advance()
		await get_tree().create_timer(0.05).timeout
	await get_tree().process_frame

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await _frames(3)
	inst._start_tutorial()
	await _frames(2)
	_check(GameState.tutorial_active, "tutorial: active flag")
	_check(inst.map.rooms.size() == 5, "tutorial: fixed 5 rooms (%d)" % inst.map.rooms.size())
	_check(inst.map.room_types.size() > 0 and String(inst.map.room_types[0]) == "classroom", "tutorial: first room is classroom")
	_check(inst.map.stair_rects.size() == 1, "tutorial: one stair room")
	_check(inst.map.is_connected_plan(), "tutorial: plan connected")
	_check(inst.hud.tutorial_mode and inst.hud.floor_label.text == "教学", "tutorial: hud shows 教学")
	_check(inst.hud.stars_label.text == "★ 3", "tutorial: fake 3 stars shown (%s)" % inst.hud.stars_label.text)
	_check(inst.tutorial != null and inst.tutorial.step == 0, "tutorial: starts at step 0")
	await _dismiss_all(inst)

	var marker: Vector2 = inst.tutorial.marker
	_check(marker != Vector2.INF and inst.map.is_walkable(marker), "tutorial: step0 marker walkable")
	inst.player.position = marker
	await _frames(3)
	await _dismiss_all(inst)
	_check(inst.tutorial.step == 1, "tutorial: walk step completes (%d)" % inst.tutorial.step)

	inst.player.position = inst.tutorial.marker
	await _frames(2)
	inst._toggle_study()
	await _frames(2)
	for i in 3:
		if inst.quiz.is_open:
			var opts: Array = inst.quiz.current_question.get("options", [])
			var ans := String(inst.quiz.current_question.get("answer", ""))
			var idx := opts.find(ans)
			if idx < 0:
				idx = 0
			inst.quiz._submit_choice(idx)
		await _frames(2)
	await _dismiss_all(inst)
	_check(inst.tutorial.step == 2, "tutorial: 3 answers complete study step (%d)" % inst.tutorial.step)
	_check(GameState.quiz_correct >= 3, "tutorial: correct answers counted (%d)" % GameState.quiz_correct)

	var coffee = inst.tutorial.coffee
	_check(coffee != null and is_instance_valid(coffee), "tutorial: coffee spawned")
	if coffee != null and is_instance_valid(coffee):
		inst.player.position = coffee.position
		await _phys(5)
		await _frames(2)
	_check(GameState.inventory_find("coffee") >= 0, "tutorial: coffee picked up")
	inst._use_item(0)
	await _frames(3)
	await _dismiss_all(inst)
	_check(inst.tutorial.step == 3, "tutorial: item step completes (%d)" % inst.tutorial.step)

	if inst.tutorial.classroom_door != null:
		inst.player.position = inst.tutorial.classroom_door.position + Vector2(0, 24)
		await _frames(2)
		inst._on_player_interact()
	await _frames(3)
	await _dismiss_all(inst)
	_check(inst.tutorial.step == 4, "tutorial: door step completes (%d)" % inst.tutorial.step)

	GameState.dash_energy = GameState.DASH_MAX
	inst.player._start_dash()
	await _frames(3)
	await _dismiss_all(inst)
	_check(inst.tutorial.step == 5, "tutorial: dash step completes (%d)" % inst.tutorial.step)

	_check(inst.tutorial.tyrant != null and is_instance_valid(inst.tutorial.tyrant), "tutorial: tyrant spawned")
	_check(inst.tutorial.tyrant != null and inst.tutorial.tyrant.tutorial_driven, "tutorial: tyrant is tutorial-driven")
	var warning_before := GameState.warnings
	if inst.tutorial.tyrant != null:
		inst.player.position = inst.tutorial.tyrant.position + Vector2(-120, 0)
		await get_tree().create_timer(1.1).timeout
	_check(GameState.warnings > warning_before, "tutorial: being seen raises warning (%d -> %d)" % [warning_before, GameState.warnings])
	inst.player.position = inst.tutorial.marker
	await _frames(3)
	await _dismiss_all(inst)
	_check(inst.tutorial.step == 6, "tutorial: stealth step completes (%d)" % inst.tutorial.step)

	inst.player.position = inst.tutorial.marker
	await _frames(3)
	await _dismiss_all(inst)
	_check(not GameState.tutorial_active, "tutorial: finished clears active flag")
	_check(bool(GameState.story_flags.get("tutorial_done", false)), "tutorial: story flag set")
	var outro_found := false
	for c in inst.get_children():
		if c is CanvasLayer and c.layer == 60:
			outro_found = true
	_check(outro_found, "tutorial: outro cutscene started")

	print("TUTORIAL_TEST: ", "ALL PASSED" if failures == 0 else "%d FAILURES" % failures)
	get_tree().quit(0 if failures == 0 else 1)
