extends Node

## 设置面板冒烟探针：打开→暂停→关闭→恢复，并确认 HUD 右下角有圆形设置按钮。

var failures: Array[String] = []

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)

func _find_gear(n: Node) -> Node:
	if n is GearButton:
		return n
	for c in n.get_children():
		var g := _find_gear(c)
		if g != null:
			return g
	return null

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	print("PROBE: start_level")
	inst._start_level(1)
	await get_tree().process_frame
	print("PROBE: hud gear")
	var gear := _find_gear(inst.hud)
	_check(gear != null, "hud: settings gear exists")
	if gear != null:
		var gr: Control = gear
		_check(gr.get_anchor(SIDE_RIGHT) == 1.0 and gr.get_anchor(SIDE_BOTTOM) == 1.0,
			"hud: gear anchored bottom-right")
		_check(gr.size.x >= 44.0 and absf(gr.size.x - gr.size.y) < 1.0,
			"hud: gear is square/circular (%s)" % gr.size)
	print("PROBE: open settings via gear click")
	if gear != null:
		gear.pressed.emit()
	await get_tree().process_frame
	_check(get_tree().paused, "settings: pauses the tree")
	_check(inst.modal_stack.size() == 1, "settings: pushed one modal (%d)" % inst.modal_stack.size())
	var ui: Node = null
	if inst.modal_stack.size() > 0:
		for c in inst.modal_stack[0].get_children():
			if c is SettingsUi:
				ui = c
	_check(ui != null, "settings: panel instanced from HUD gear")
	print("PROBE: close settings")
	if ui != null:
		ui.close()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not get_tree().paused, "settings: unpauses on close")
	_check(inst.modal_stack.is_empty(), "settings: modal popped (%d)" % inst.modal_stack.size())
	print("PROBE: menu gear")
	inst._show_menu()
	await get_tree().process_frame
	_check(_find_gear(inst.menu_layer) != null, "menu: gear exists")

	if failures.is_empty():
		print("SETTINGS_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("SETTINGS_PROBE: FAILED ", failures.size())
	get_tree().quit()
