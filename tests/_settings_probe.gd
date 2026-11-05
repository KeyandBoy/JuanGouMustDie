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

func _click(ctrl: Control) -> void:
	var pos := ctrl.get_global_rect().get_center()
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	get_viewport().push_input(mm)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev)

func _find_layer_with_settings(layer: CanvasLayer) -> Node:
	for c in layer.get_children():
		if c is SettingsUi:
			return c
	return null

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	print("VIEWPORT size=", get_viewport().get_visible_rect().size)
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
	print("PROBE: open settings via real mouse click on HUD gear")
	if gear != null:
		_click(gear)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(get_tree().paused, "settings: pauses the tree")
	_check(inst.modal_stack.size() == 1, "settings: pushed one modal (%d)" % inst.modal_stack.size())
	var ui: Node = null
	if inst.modal_stack.size() > 0:
		ui = _find_layer_with_settings(inst.modal_stack[0])
	_check(ui != null, "settings: panel instanced from HUD gear click")
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
	await get_tree().process_frame
	var mgear := _find_gear(inst.menu_layer)
	_check(mgear != null, "menu: gear exists")
	if mgear != null:
		var mg: Control = mgear
		_check(mg.get_global_rect().position.x > 800.0 and mg.get_global_rect().position.y > 500.0,
			"menu: gear sits bottom-right (%s)" % mg.get_global_rect())
		_click(mgear)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(inst.modal_stack.size() == 2, "menu: gear click pushed settings (%d)" % inst.modal_stack.size())
		var mui: Node = null
		if inst.modal_stack.size() > 1:
			mui = _find_layer_with_settings(inst.modal_stack[1])
		_check(mui != null, "menu: gear click opens settings panel")
		if mui != null:
			mui.close()
		await get_tree().process_frame

	if failures.is_empty():
		print("SETTINGS_PROBE: ALL PASSED")
	else:
		for f in failures:
			print("FAIL: ", f)
		print("SETTINGS_PROBE: FAILED ", failures.size())
	get_tree().quit()
