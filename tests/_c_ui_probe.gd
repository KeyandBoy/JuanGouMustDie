extends Node

## C 组 UI 冒烟探针：通知队列 / 限时效果条 / 悬停 Tooltip / 最佳成绩 / 版本号 / 失败面板。
## 运行：& $G --headless --path . --quit-after 20000 res://tests/_c_ui_probe.tscn

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
	var hud = inst.hud

	# C1 版本号
	_check(String(ProjectSettings.get_setting("application/config/version", "")) == "0.9.0",
		"c1: version set to 0.9.0")

	# C6 通知队列：清空启动阶段可能已有的 toast，再发 5 条 -> 同屏 3 条，其余排队
	for chip in hud._toast_live:
		if is_instance_valid(chip):
			chip.queue_free()
	hud._toast_live.clear()
	hud._toast_queue.clear()
	await get_tree().process_frame
	for i in 5:
		hud.toast("测试通知 %d" % i)
	await get_tree().process_frame
	_check(hud._toast_live.size() == 3, "c6: at most 3 toasts on screen (%d)" % hud._toast_live.size())
	_check(hud._toast_live.size() + hud._toast_queue.size() >= 5,
		"c6: pending toasts kept in queue (live=%d queue=%d)" % [hud._toast_live.size(), hud._toast_queue.size()])

	# C4 限时效果条
	GameState.active_effects.clear()
	GameState.set_effect("coffee", 8.0, "咖啡")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(hud._effect_chips.size() == 1, "c4: effect chip created (%d)" % hud._effect_chips.size())
	_check(hud._effect_box.visible, "c4: effect strip visible")
	if hud._effect_chips.size() == 1:
		var chip = hud._effect_chips.values()[0]
		var bar: ProgressBar = chip.get_meta("bar")
		var sec: Label = chip.get_meta("sec")
		_check(bar != null and bar.value > 50.0, "c4: vertical bar has fill (%.0f)" % (bar.value if bar != null else -1.0))
		_check(sec != null and sec.text.ends_with("s"), "c4: seconds label (%s)" % (sec.text if sec != null else "?"))

	# C5 Tooltip：真实鼠标移到第一个背包槽，等 0.4s
	GameState.inventory.clear()
	GameState.add_item("coffee")
	hud._refresh_inventory()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not hud._slot_panels.is_empty(), "c5: inventory slot exists")
	if not hud._slot_panels.is_empty():
		var slot: Control = hud._slot_panels[0]
		var pos := slot.get_global_rect().get_center()
		var mm := InputEventMouseMotion.new()
		mm.position = pos
		mm.global_position = pos
		get_viewport().push_input(mm)
		await get_tree().create_timer(0.55).timeout
		_check(hud._tooltip.visible, "c5: tooltip visible after 0.4s hover")
		_check(hud._tooltip_label.text.contains("咖啡"), "c5: tooltip shows item name (%s)" % hud._tooltip_label.text)

	# C2 最佳成绩：只在更高分时覆盖
	GameState.level_best.clear()
	GameState.record_level_best(2, 88.0, 100.0, 90.0)
	GameState.record_level_best(2, 70.0, 40.0, 95.0)
	_check(absf(float(GameState.level_best_of(2).get("score", 0.0)) - 88.0) < 0.01,
		"c2: best score keeps higher run")
	_check(absf(float(GameState.level_best_of(2).get("time", 0.0)) - 100.0) < 0.01,
		"c2: best time comes from the same run")

	# C10 错题记录 + 失败面板文案
	GameState.wrong_questions.clear()
	GameState.record_wrong({"prompt": "1+1=?", "answer": "2"})
	_check(GameState.wrong_questions.size() == 1, "c10: wrong question recorded")
	inst._show_end_panel("失败", "测试失败")
	await get_tree().process_frame
	await get_tree().process_frame
	var found_acc := false
	var found_tip := false
	var found_wrong := false
	for lbl in _all_labels(inst):
		if lbl.text.contains("正确率"):
			found_acc = true
		if lbl.text.begins_with("贴士："):
			found_tip = true
		if lbl.text.contains("1+1=?") or lbl.text.contains("错题"):
			found_wrong = true
	_check(found_acc, "c10: failure panel shows accuracy")
	_check(found_wrong, "c10: failure panel lists wrong question")
	_check(found_tip, "c13: failure panel shows a tip")

	if failures.is_empty():
		print("C_UI_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("C_UI_PROBE: FAILED ", failures.size())
	get_tree().quit()


func _all_labels(n: Node) -> Array:
	var out: Array = []
	if n is Label:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_labels(c))
	return out
