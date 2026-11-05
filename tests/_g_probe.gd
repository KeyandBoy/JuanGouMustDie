extends Node

## G 组探针：G5 稀有度/掉落、G11 残页换提示符、答题提示按钮。
## 运行：& $G --headless --path . --quit-after 25000 res://tests/_g_probe.tscn

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

	# G5：四档权重、道具映射、掉落合法
	var total := 0
	for r in GameState.RARITY_DEFS:
		total += int(GameState.RARITY_DEFS[r]["weight"])
	_check(total == 100, "g5: rarity weights sum to 100 (%d)" % total)
	for i in 40:
		var id: String = GameState.pick_loot()
		_check(GameState.ITEM_DEFS.has(id), "g5: loot id exists (%s)" % id)
		_check(GameState.RARITY_DEFS.has(GameState.item_rarity(id)), "g5: item has rarity (%s)" % id)
	_check(GameState.item_rarity("portal") == "legendary", "g5: portal is legendary")
	_check(GameState.item_rarity("coffee") == "common", "g5: coffee is common")

	# G11：4 张残页不换，第 5 张换 1 个提示符
	GameState.residual_pages = 0
	GameState.hint_tokens = 0
	_check(GameState.add_residual_page(4) == 0 and GameState.hint_tokens == 0, "g11: 4 pages no hint")
	_check(GameState.add_residual_page(1) == 1, "g11: 5th page converts to hint")
	_check(GameState.residual_pages == 0 and GameState.hint_tokens == 1,
		"g11: pages reset, token +1 (pages=%d tokens=%d)" % [GameState.residual_pages, GameState.hint_tokens])

	# G11：答题界面的提示符按钮排除一个错误项
	var q := {
		"prompt": "1 + 1 = ?",
		"type": "choice",
		"options": ["1", "2", "3", "4"],
		"answer": "2",
		"subject": "math",
		"grade": "junior",
	}
	inst.quiz.open(q)
	await get_tree().process_frame
	_check(inst.quiz.hint_btn.visible, "g11: hint button visible with token")
	_check(inst.quiz._option_buttons.size() == 4, "g11: four option buttons")
	inst.quiz._use_hint()
	await get_tree().process_frame
	_check(GameState.hint_tokens == 0, "g11: hint token consumed")
	var disabled := 0
	var has_removed := false
	for b in inst.quiz._option_buttons:
		if b.disabled:
			disabled += 1
			if b.text.contains("已排除"):
				has_removed = true
	_check(disabled >= 1 and has_removed, "g11: one wrong option removed")
	_check(not inst.quiz.hint_btn.visible, "g11: hint button hides at 0 tokens")
	inst.quiz.close()

	if failures.is_empty():
		print("G_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("G_PROBE: FAILED ", failures.size())
	get_tree().quit()
