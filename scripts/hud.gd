extends CanvasLayer

signal skip_pressed

var study_bar: ProgressBar
var study_label: Label
var emptiness_bar: ProgressBar
var dash_bar: ProgressBar
var floor_label: Label
var phase_label: Label
var stars_label: Label
var prompt_label: Label
var prompt_chip: PanelContainer
var hot_chip: PanelContainer
var hot_label: Label
var inventory_box: HBoxContainer
var task_panel: PanelContainer
var task_label: Label
var skip_button: Button
var tutorial_mode := false
var tutorial_stars := 0
var dev_label: Label
var status_panel: PanelContainer
var panel_side := "left"
var reserve_top_right := false
var toast_timer := 0.0
var _panel_tween: Tween
var _panel_cooldown := 0.0
var _warning_pips: Array[Panel] = []
var _hot_pips: Array[Panel] = []

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(root)
	add_child(root)

	dev_label = Label.new()
	dev_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dev_label.offset_left = -260
	dev_label.offset_top = -30
	dev_label.offset_right = -10
	dev_label.offset_bottom = -8
	dev_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dev_label.add_theme_font_size_override("font_size", 12)
	dev_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 0.8))
	dev_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dev_label.visible = DevMode.enabled
	dev_label.text = DevMode.status_text()
	root.add_child(dev_label)

	# —— 左上信息卡：chip 行 + 三条状态条 ——
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 8
	panel.offset_top = 8
	panel.custom_minimum_size = Vector2(262, 0)
	panel.self_modulate = Color(1, 1, 1, 0.94)
	root.add_child(panel)
	status_panel = panel

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# chip 行：楼层+时段 | ★ | 警告方块
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 8)
	vbox.add_child(chip_row)
	floor_label = _chip(chip_row)
	floor_label.text = "1F"
	phase_label = Label.new()
	phase_label.add_theme_font_size_override("font_size", 12)
	phase_label.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_row.add_child(phase_label)
	stars_label = _chip(chip_row)
	stars_label.modulate = UiTheme.COL_GOLD
	stars_label.text = "★ 0"
	var pip_gap := Control.new()
	pip_gap.custom_minimum_size = Vector2(6, 0)
	chip_row.add_child(pip_gap)
	var warn_cap := Label.new()
	warn_cap.text = "警告"
	warn_cap.add_theme_font_size_override("font_size", 12)
	warn_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_row.add_child(warn_cap)
	for i in 5:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(11, 11)
		_style_pip(pip, false)
		chip_row.add_child(pip)
		_warning_pips.append(pip)

	# 火热槽：连对 3/6/9 依次点亮；不热时整行隐藏
	hot_chip = PanelContainer.new()
	hot_chip.add_theme_stylebox_override("normal", _chip_bg())
	vbox.add_child(hot_chip)
	var hot_row := HBoxContainer.new()
	hot_row.add_theme_constant_override("separation", 6)
	hot_chip.add_child(hot_row)
	hot_label = Label.new()
	hot_label.add_theme_font_size_override("font_size", 13)
	hot_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.3))
	hot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hot_row.add_child(hot_label)
	var hot_gap := Control.new()
	hot_gap.custom_minimum_size = Vector2(4, 0)
	hot_row.add_child(hot_gap)
	for i in 3:
		var hp := Panel.new()
		hp.custom_minimum_size = Vector2(11, 11)
		_style_hot_pip(hp, false)
		hot_row.add_child(hp)
		_hot_pips.append(hp)
	hot_chip.visible = false

	# 净答对（绿）
	study_label = Label.new()
	study_label.add_theme_font_size_override("font_size", 13)
	study_label.text = "净答对 0.0/5"
	vbox.add_child(study_label)
	study_bar = ProgressBar.new()
	study_bar.min_value = 0
	study_bar.max_value = 5
	study_bar.custom_minimum_size = Vector2(238, 14)
	study_bar.add_theme_stylebox_override("fill", _fill(UiTheme.COL_ACCENT))
	vbox.add_child(study_bar)

	# 空虚（红）
	emptiness_bar = ProgressBar.new()
	emptiness_bar.min_value = 0
	emptiness_bar.max_value = 100
	emptiness_bar.custom_minimum_size = Vector2(238, 14)
	emptiness_bar.add_theme_stylebox_override("fill", _fill(UiTheme.COL_RED))
	vbox.add_child(emptiness_bar)

	# 闪避（青）
	dash_bar = ProgressBar.new()
	dash_bar.min_value = 0
	dash_bar.max_value = 100
	dash_bar.custom_minimum_size = Vector2(238, 14)
	dash_bar.add_theme_stylebox_override("fill", _fill(UiTheme.COL_CYAN))
	vbox.add_child(dash_bar)

	# —— 左下：背包槽位卡 + 提示 chip ——
	var bottom_box := VBoxContainer.new()
	bottom_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom_box.offset_left = 16
	bottom_box.offset_top = -110
	bottom_box.offset_right = 780
	bottom_box.offset_bottom = -12
	bottom_box.add_theme_constant_override("separation", 6)
	root.add_child(bottom_box)

	inventory_box = HBoxContainer.new()
	inventory_box.add_theme_constant_override("separation", 6)
	bottom_box.add_child(inventory_box)

	prompt_chip = PanelContainer.new()
	prompt_chip.add_theme_stylebox_override("normal", _chip_bg())
	bottom_box.add_child(prompt_chip)
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_chip.add_child(prompt_label)
	prompt_chip.visible = false

	task_panel = PanelContainer.new()
	task_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	task_panel.offset_left = -280.0
	task_panel.offset_right = 280.0
	task_panel.offset_top = -206.0
	task_panel.offset_bottom = -170.0
	task_panel.add_theme_stylebox_override("normal", UiTheme.panel_style(UiTheme.COL_GOLD, UiTheme.COL_PANEL_BG, 2))
	task_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	task_panel.visible = false
	root.add_child(task_panel)
	task_label = Label.new()
	task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	task_label.add_theme_font_size_override("font_size", 15)
	task_label.add_theme_color_override("font_color", UiTheme.COL_GOLD)
	task_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	task_panel.add_child(task_label)

	skip_button = Button.new()
	skip_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skip_button.offset_left = -132.0
	skip_button.offset_top = -56.0
	skip_button.offset_right = -12.0
	skip_button.offset_bottom = -20.0
	skip_button.text = "跳过教学"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.add_theme_font_size_override("font_size", 13)
	skip_button.visible = false
	skip_button.pressed.connect(func(): skip_pressed.emit())
	root.add_child(skip_button)

	_refresh_study()
	_refresh_floor()
	_refresh_inventory()
	_refresh_stars()
	_refresh_warnings(GameState.warnings)
	_refresh_hot(GameState.hot_level())
	emptiness_bar.value = GameState.emptiness
	dash_bar.max_value = GameState.dash_max_value()
	dash_bar.value = GameState.dash_energy

	GameState.study_changed.connect(func(_v): _refresh_study())
	GameState.study_goal_changed.connect(func(_v): _refresh_study())
	GameState.level_changed.connect(func(_v): _refresh_floor())
	GameState.emptiness_changed.connect(func(v): emptiness_bar.value = v)
	GameState.warnings_changed.connect(_refresh_warnings)
	GameState.dash_changed.connect(func(v):
		dash_bar.max_value = GameState.dash_max_value()
		dash_bar.value = v)
	GameState.inventory_changed.connect(_refresh_inventory)
	GameState.stars_changed.connect(_refresh_stars)
	GameState.hot_changed.connect(_refresh_hot)
	get_viewport().size_changed.connect(func(): _set_panel_side(panel_side, false))

func _chip(parent: Control) -> Label:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("normal", _chip_bg())
	parent.add_child(wrap)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	wrap.add_child(lbl)
	return lbl

func _chip_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.071, 0.078, 0.114, 0.82)
	sb.border_color = UiTheme.COL_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb

func _fill(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb

func _style_pip(pip: Panel, filled: bool) -> void:
	var sb := StyleBoxFlat.new()
	if filled:
		sb.bg_color = UiTheme.COL_RED
		sb.border_color = Color(0.55, 0.15, 0.15)
	else:
		sb.bg_color = Color(0.071, 0.078, 0.114, 0.6)
		sb.border_color = UiTheme.COL_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	pip.add_theme_stylebox_override("panel", sb)

func _style_hot_pip(pip: Panel, filled: bool) -> void:
	var sb := StyleBoxFlat.new()
	if filled:
		sb.bg_color = Color(0.95, 0.45, 0.12)
		sb.border_color = Color(0.55, 0.25, 0.08)
	else:
		sb.bg_color = Color(0.071, 0.078, 0.114, 0.6)
		sb.border_color = UiTheme.COL_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
	pip.add_theme_stylebox_override("panel", sb)

func _refresh_hot(level: int) -> void:
	if hot_chip == null:
		return
	hot_chip.visible = level > 0
	var names := ["", "I", "II", "III"]
	var mults := [1.0, 1.1, 1.2, 1.3]
	if level > 0 and level < names.size():
		hot_label.text = "火热 %s ×%.1f" % [names[level], mults[level]]
	for i in _hot_pips.size():
		if is_instance_valid(_hot_pips[i]):
			_style_hot_pip(_hot_pips[i], i < level)

func _refresh_warnings(count: int) -> void:
	var mx := GameState.max_warnings
	for i in _warning_pips.size():
		if not is_instance_valid(_warning_pips[i]):
			continue
		_warning_pips[i].visible = i < mx
		_style_pip(_warning_pips[i], i < count and i < mx)

func _refresh_study() -> void:
	study_bar.max_value = maxf(0.01, GameState.study_goal)
	study_bar.value = GameState.study
	study_label.text = "净答对 %.1f/%.0f" % [GameState.study, GameState.study_goal]

func _refresh_floor() -> void:
	floor_label.text = "教学" if tutorial_mode else "%dF" % GameState.level

func _refresh_stars() -> void:
	stars_label.text = "★ %d" % (tutorial_stars if tutorial_mode else GameState.stars)

func set_tutorial_mode(on: bool) -> void:
	tutorial_mode = on
	tutorial_stars = 3 if on else 0
	if task_panel != null:
		task_panel.visible = on
	if skip_button != null:
		skip_button.visible = on
	_refresh_floor()
	_refresh_stars()

func set_task(text: String) -> void:
	if task_label != null:
		task_label.text = text

func _refresh_inventory() -> void:
	for c in inventory_box.get_children():
		c.queue_free()
	var cap := GameState.item_capacity()
	var head := Label.new()
	head.text = "背包"
	head.add_theme_font_size_override("font_size", 13)
	head.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inventory_box.add_child(head)
	for i in range(GameState.ITEM_CAPACITY):
		var slot := PanelContainer.new()
		slot.add_theme_stylebox_override("normal", _chip_bg())
		inventory_box.add_child(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		slot.add_child(row)
		var keycap := PanelContainer.new()
		var kb := StyleBoxFlat.new()
		kb.bg_color = UiTheme.COL_BTN_HOVER if i < cap else Color(0.13, 0.14, 0.19)
		kb.border_color = UiTheme.COL_PANEL_BORDER
		kb.set_border_width_all(1)
		kb.set_corner_radius_all(0)
		kb.content_margin_left = 5
		kb.content_margin_right = 5
		kb.content_margin_top = 1
		kb.content_margin_bottom = 1
		keycap.add_theme_stylebox_override("normal", kb)
		row.add_child(keycap)
		var klbl := Label.new()
		klbl.text = _slot_key(i)
		klbl.add_theme_font_size_override("font_size", 12)
		keycap.add_child(klbl)
		if i >= cap:
			var lock_tex := UiIcons.lock()
			if lock_tex != null:
				var lock_rect := TextureRect.new()
				lock_rect.custom_minimum_size = Vector2(14, 14)
				lock_rect.texture = lock_tex
				lock_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				lock_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				lock_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(lock_rect)
			else:
				var lock_lbl := Label.new()
				lock_lbl.text = "🔒"
				lock_lbl.add_theme_font_size_override("font_size", 12)
				row.add_child(lock_lbl)
			continue
		if i < GameState.inventory.size():
			var item_id: String = GameState.inventory_item_id(i)
			var def: Dictionary = GameState.get_item_def(item_id)
			var icon := UiIcons.item(item_id)
			if icon != null:
				var tex_rect := TextureRect.new()
				tex_rect.custom_minimum_size = Vector2(16, 16)
				tex_rect.texture = icon
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				row.add_child(tex_rect)
			else:
				var swatch := ColorRect.new()
				swatch.custom_minimum_size = Vector2(16, 16)
				swatch.color = def.get("color", Color.GRAY)
				row.add_child(swatch)
			var name_lbl := Label.new()
			name_lbl.text = String(def.get("name", item_id))
			name_lbl.add_theme_font_size_override("font_size", 13)
			row.add_child(name_lbl)
		else:
			var empty_lbl := Label.new()
			empty_lbl.text = "空"
			empty_lbl.add_theme_font_size_override("font_size", 13)
			empty_lbl.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
			row.add_child(empty_lbl)

func _slot_key(i: int) -> String:
	match i:
		0: return "R"
		1: return "T"
		2: return "Y"
	return "?"

func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_chip.visible = text != ""

func toast(text: String) -> void:
	prompt_label.text = text
	prompt_chip.visible = true
	toast_timer = 2.5

func _process(delta: float) -> void:
	phase_label.text = GameState.get_phase_label()
	if dev_label != null:
		dev_label.text = DevMode.status_text()
		dev_label.visible = DevMode.enabled
	_update_panel_side(delta)
	if toast_timer > 0:
		toast_timer -= delta
		if toast_timer <= 0:
			prompt_label.text = ""
			prompt_chip.visible = false

func _panel_rect() -> Rect2:
	if status_panel == null or not is_instance_valid(status_panel):
		return Rect2()
	return Rect2(status_panel.position, status_panel.size)

func _side_for_point(p: Vector2) -> String:
	var r := _panel_rect().grow(26.0)
	if r.has_point(p):
		return "right" if panel_side == "left" else "left"
	return panel_side

func _set_panel_side(side: String, animate := true) -> void:
	if status_panel == null or not is_instance_valid(status_panel):
		return
	panel_side = side
	var size := status_panel.size
	if size.x < 10.0:
		size = Vector2(262.0, 150.0)
	var vw := get_viewport().get_visible_rect().size.x
	var target := Vector2(8.0, 8.0)
	if side == "right":
		target = Vector2(vw - size.x - 12.0, 156.0 if reserve_top_right else 8.0)
	if _panel_tween != null and _panel_tween.is_valid():
		_panel_tween.kill()
	if not animate:
		status_panel.position = target
		return
	_panel_tween = create_tween()
	_panel_tween.tween_property(status_panel, "position", target, 0.16)

func _update_panel_side(delta: float) -> void:
	_panel_cooldown = maxf(0.0, _panel_cooldown - delta)
	var pl := get_tree().get_first_node_in_group("player")
	if not (pl is Node2D) or status_panel == null or not is_instance_valid(status_panel):
		return
	var p: Vector2 = (pl as Node2D).get_global_transform_with_canvas().origin
	if _panel_cooldown > 0.0:
		return
	var want := _side_for_point(p)
	if want != panel_side:
		_set_panel_side(want)
		_panel_cooldown = 0.4
