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
var _toast_box: VBoxContainer
var _toast_queue: Array[String] = []
var _toast_live: Array[Control] = []
var _effect_box: HBoxContainer
var _effect_chips: Dictionary = {}
var _tooltip: PanelContainer
var _tooltip_label: Label
var _hover_ctl: Control
var _hover_text: Callable
var _hover_t := 0.0
const TOOLTIP_DELAY := 0.4
const TOAST_MAX := 3
const TOAST_LIFE := 2.6
var _panel_tween: Tween
var _panel_cooldown := 0.0
var _warning_pips: Array[Panel] = []
var _hot_pips: Array[Panel] = []
var _num_root: Control
var _num_pool: Array[Label] = []
var _stars_shown := 0.0
var _stars_init := false
var _stars_force_snap := false
var _sanity_vignette: TextureRect
var _fly_layer: Control
var _slot_panels: Array[PanelContainer] = []
var _slot_items: Array[String] = []
var _fly_count := 0
const NUM_POOL_SIZE := 18
const SANITY_WARN := 35.0

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.apply(root)
	add_child(root)

	# 低理智红晕：径向渐变（中心透明→边缘暗红），比整屏纯色更像"视野收缩"
	_sanity_vignette = TextureRect.new()
	_sanity_vignette.texture = _make_vignette_texture()
	_sanity_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sanity_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_sanity_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sanity_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sanity_vignette.modulate = Color(1, 1, 1, 0)
	root.add_child(_sanity_vignette)
	root.move_child(_sanity_vignette, 0)

	dev_label = Label.new()
	dev_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	dev_label.offset_left = -260
	dev_label.offset_top = -94
	dev_label.offset_right = -12
	dev_label.offset_bottom = -74
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

	# 净答对（绿）——第二重要：中等高度
	study_label = Label.new()
	study_label.add_theme_font_size_override("font_size", 13)
	study_label.text = "净答对 0.0/5"
	vbox.add_child(study_label)
	study_bar = ProgressBar.new()
	study_bar.min_value = 0
	study_bar.max_value = 5
	study_bar.custom_minimum_size = Vector2(238, 12)
	study_bar.add_theme_stylebox_override("background", _bar_bg())
	study_bar.add_theme_stylebox_override("fill", _fill(UiTheme.COL_ACCENT))
	vbox.add_child(study_bar)

	# 空虚 / 理智（红）——最重的一条，比其它两条高
	emptiness_bar = ProgressBar.new()
	emptiness_bar.min_value = 0
	emptiness_bar.max_value = 100
	emptiness_bar.custom_minimum_size = Vector2(238, 18)
	emptiness_bar.add_theme_stylebox_override("background", _bar_bg())
	emptiness_bar.add_theme_stylebox_override("fill", _fill(UiTheme.COL_RED))
	vbox.add_child(emptiness_bar)

	# 闪避（青）——辅助信息，压成细条
	dash_bar = ProgressBar.new()
	dash_bar.min_value = 0
	dash_bar.max_value = 100
	dash_bar.custom_minimum_size = Vector2(238, 7)
	dash_bar.add_theme_stylebox_override("background", _bar_bg())
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

	# C4：限时道具效果条（图标 + 竖向剩余条 + 秒数）
	_effect_box = HBoxContainer.new()
	_effect_box.add_theme_constant_override("separation", 4)
	_effect_box.visible = false
	_effect_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_box.add_child(_effect_box)
	bottom_box.move_child(_effect_box, 0)

	prompt_chip = PanelContainer.new()
	prompt_chip.add_theme_stylebox_override("normal", _chip_bg())
	bottom_box.add_child(prompt_chip)
	prompt_label = Label.new()
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_chip.add_child(prompt_label)
	prompt_chip.visible = false

	# C6：通知队列。最多同屏 3 条，从下往上堆叠；和底部交互提示分开，互不覆盖。
	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_toast_box.offset_left = 16.0
	_toast_box.offset_top = -300.0
	_toast_box.offset_right = 640.0
	_toast_box.offset_bottom = -118.0
	_toast_box.alignment = BoxContainer.ALIGNMENT_END
	_toast_box.add_theme_constant_override("separation", 4)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast_box)

	# C5：悬停 0.4s 后显示的道具 Tooltip（跟随鼠标，自动贴边）
	_tooltip = PanelContainer.new()
	_tooltip.add_theme_stylebox_override("normal", UiTheme.panel_style(UiTheme.COL_PANEL_BORDER, Color(0.07, 0.09, 0.08, 0.97), 2))
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	_tooltip.z_index = 200
	root.add_child(_tooltip)
	_tooltip_label = Label.new()
	_tooltip_label.add_theme_font_size_override("font_size", 13)
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_label.custom_minimum_size = Vector2(170, 0)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_child(_tooltip_label)

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
	skip_button.offset_left = -196.0
	skip_button.offset_top = -56.0
	skip_button.offset_right = -76.0
	skip_button.offset_bottom = -20.0
	skip_button.text = "跳过教学"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.add_theme_font_size_override("font_size", 13)
	skip_button.visible = false
	skip_button.pressed.connect(func(): skip_pressed.emit())
	root.add_child(skip_button)

	# —— 右下角：圆形设置按钮（iOS 设置图标那种）——
	# 游戏内随时可开设置；打开时 SettingsUi 会暂停游戏。
	var gear := GearButton.new()
	gear.name = "SettingsGear"
	gear.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	gear.offset_left = -68.0
	gear.offset_top = -68.0
	gear.offset_right = -16.0
	gear.offset_bottom = -16.0
	gear.pressed.connect(func():
		var main_node := get_parent()
		if main_node != null and main_node.has_method("_push_modal"):
			SettingsUi.open(main_node))
	root.add_child(gear)

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
	_build_number_pool(root)
	_build_fly_layer(root)

## 拾取图标飞入背包的专用层（在飘字层之上）
func _build_fly_layer(host: Control) -> void:
	_fly_layer = Control.new()
	_fly_layer.name = "FlyLayer"
	_fly_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_fly_layer)

## 飘字池：一次答对/答错/被抓都能在角色头顶飘一个数字。
## 复用 Label，避免每次 new/tween/free 造成抖动。
## 必须挂在 root（已 apply UiTheme）下：网页端没有系统字体回退，
## 挂到 CanvasLayer 上会解析到引擎默认字体，中文直接变方块。
func _build_number_pool(host: Control) -> void:
	_num_root = Control.new()
	_num_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_num_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(_num_root)
	for i in NUM_POOL_SIZE:
		var l := Label.new()
		l.visible = false
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.92))
		l.add_theme_constant_override("outline_size", 5)
		_num_root.add_child(l)
		_num_pool.append(l)

## 径向渐变贴图：中心全透明，靠边缘逐渐变暗红
func _make_vignette_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0.50, 0.02, 0.02, 0.0))
	g.set_color(1, Color(0.50, 0.02, 0.02, 1.0))
	g.add_point(0.58, Color(0.50, 0.02, 0.02, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex

func _number_color(kind: String) -> Color:
	match kind:
		"loss", "warn":
			return Color(0.96, 0.34, 0.28)
		"crit":
			return Color(1.0, 0.83, 0.30)
		"info":
			return Color(0.74, 0.86, 0.96)
		_:
			return Color(0.62, 0.96, 0.68)

## world_pos 用世界坐标（传 player.global_position 即可），内部转屏幕坐标。
func pop_number(world_pos: Vector2, text: String, kind: String = "gain") -> void:
	if _num_root == null or _num_pool.is_empty():
		return
	var l: Label = _num_pool.pop_front()
	_num_pool.push_back(l)
	var screen: Vector2 = get_viewport().get_canvas_transform() * world_pos
	var box := Vector2(240.0, 30.0)
	l.text = text
	l.size = box
	l.pivot_offset = box * 0.5
	l.position = screen - Vector2(box.x * 0.5, 46.0) + Vector2(randf_range(-9.0, 9.0), 0.0)
	l.modulate = _number_color(kind)
	l.add_theme_font_size_override("font_size", 26 if kind == "crit" else 18)
	l.scale = Vector2(1.5, 1.5) if kind == "crit" else Vector2(1.0, 1.0)
	l.visible = true
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 44.0, 0.72).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.34).set_delay(0.38)
	tw.tween_callback(func(): l.visible = false)

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


## C3：进度条统一的暗底，让彩色填充的“重量”更明确。
func _bar_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.07, 0.88)
	sb.border_color = Color(0.20, 0.24, 0.22, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(0)
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
	var target := float(tutorial_stars if tutorial_mode else GameState.stars)
	if not _stars_init or _stars_force_snap or absf(target - _stars_shown) > 4.0:
		# 首次进入 / 大跳变（读档、切教学）直接对齐，避免数字从 0 滚过一整屏
		_stars_init = true
		_stars_force_snap = false
		_stars_shown = target
		stars_label.text = "★ %d" % int(target)
		return
	if is_equal_approx(target, _stars_shown):
		stars_label.text = "★ %d" % int(target)
		return
	var from := _stars_shown
	_stars_shown = target
	var tw := create_tween()
	tw.tween_method(func(v: float): stars_label.text = "★ %d" % int(round(v)), from, target, 0.4)
	if target > from:
		stars_label.modulate = Color(1.0, 0.94, 0.55)
		var tw2 := create_tween()
		tw2.tween_property(stars_label, "modulate", Color(1, 1, 1, 1), 0.5)

func set_tutorial_mode(on: bool) -> void:
	tutorial_mode = on
	tutorial_stars = 3 if on else 0
	_stars_force_snap = true
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
	_slot_panels.clear()
	_slot_items.clear()
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
		_slot_panels.append(slot)
		_slot_items.append("")
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
			_ignore_mouse_recursive(slot)
			bind_tooltip(slot, func() -> String: return "未解锁\n升级背包容量后可用")
			continue
		if i < GameState.inventory.size():
			var item_id: String = GameState.inventory_item_id(i)
			_slot_items[i] = item_id
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
			if GameState.item_rarity(item_id) != "common":
				name_lbl.add_theme_color_override("font_color", GameState.rarity_def(GameState.item_rarity(item_id))["color"])
			row.add_child(name_lbl)
		else:
			var empty_lbl := Label.new()
			empty_lbl.text = "空"
			empty_lbl.add_theme_font_size_override("font_size", 13)
			empty_lbl.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
			row.add_child(empty_lbl)

		# C5：悬停 0.4 秒后显示名称/描述；空格和未解锁格也给一句说明
		_ignore_mouse_recursive(slot)
		var tip_text := ""
		if _slot_items[i] != "":
			var d_tip: Dictionary = GameState.get_item_def(_slot_items[i])
			var rar := GameState.item_rarity(_slot_items[i])
			var rdef: Dictionary = GameState.rarity_def(rar)
			tip_text = "[%s] %s\n%s" % [String(rdef.get("name", "普通")), String(d_tip.get("name", _slot_items[i])), String(d_tip.get("desc", ""))]
		else:
			tip_text = "空格\n使用道具后自动填入"
		bind_tooltip(slot, func() -> String: return tip_text)

## A8 拾取反馈：图标从地面飞到它所在的背包槽，落位时槽位闪一下。
func fly_item(item_id: String, world_pos: Vector2) -> void:
	if _fly_layer == null:
		return
	var start: Vector2 = get_viewport().get_canvas_transform() * world_pos
	var icon := UiIcons.item(item_id)
	var node: Control
	if icon != null:
		var tr := TextureRect.new()
		tr.texture = icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		node = tr
	else:
		var cr := ColorRect.new()
		cr.color = GameState.get_item_def(item_id).get("color", Color(0.85, 0.85, 0.7))
		node = cr
	var box := Vector2(22.0, 22.0)
	node.size = box
	node.pivot_offset = box * 0.5
	node.position = start - box * 0.5
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fly_layer.add_child(node)
	_fly_count += 1
	# 背包槽是刚重建的，布局要等一帧才有效；先飞起来，再取真实槽位中心
	await get_tree().process_frame
	if not is_instance_valid(node):
		_fly_count -= 1
		return
	var target := _slot_center_for(item_id)
	var tw := create_tween()
	tw.tween_property(node, "position", target - box * 0.5, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(node, "scale", Vector2(0.55, 0.55), 0.4)
	tw.parallel().tween_property(node, "modulate:a", 0.3, 0.2).set_delay(0.2)
	tw.tween_callback(func() -> void:
		_fly_count -= 1
		node.queue_free()
		_flash_slot(item_id))

func _slot_center_for(item_id: String) -> Vector2:
	# 从后往前找：新拾取的同名道具总是追加在背包末尾
	for i in range(_slot_items.size() - 1, -1, -1):
		if _slot_items[i] == item_id and i < _slot_panels.size():
			return _slot_panels[i].get_global_rect().get_center()
	if not _slot_panels.is_empty():
		return _slot_panels[0].get_global_rect().get_center()
	return get_viewport().get_visible_rect().size * 0.5

func _flash_slot(item_id: String) -> void:
	for i in range(_slot_items.size() - 1, -1, -1):
		if _slot_items[i] != item_id or i >= _slot_panels.size():
			continue
		var slot := _slot_panels[i]
		if not is_instance_valid(slot):
			return
		slot.modulate = Color(1.6, 1.45, 0.6, 1.0)
		var tw := create_tween()
		tw.tween_property(slot, "modulate", Color(1, 1, 1, 1), 0.35)
		return

func active_fly_count() -> int:
	return _fly_count

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
	if text.is_empty():
		return
	# 连续重复的同一句不排队（比如连按空格提示“这一格没有道具”）
	if not _toast_queue.is_empty() and _toast_queue[-1] == text:
		return
	for chip in _toast_live:
		if is_instance_valid(chip) and String(chip.get_meta("text", "")) == text:
			return
	_toast_queue.append(text)
	# 兼容旧断言/旧调用：prompt_label 仍保存最后一条通知文本，但通知本身走独立队列
	prompt_label.text = text
	_pump_toasts()


func _pump_toasts() -> void:
	while _toast_live.size() < TOAST_MAX and not _toast_queue.is_empty():
		var text: String = _toast_queue.pop_front()
		_spawn_toast(text)


func _spawn_toast(text: String) -> void:
	if _toast_box == null or not is_instance_valid(_toast_box):
		return
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("normal", _chip_bg())
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.set_meta("text", text)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(lbl)
	chip.modulate.a = 0.0
	_toast_box.add_child(chip)
	_toast_live.append(chip)
	var tin := create_tween()
	tin.tween_property(chip, "modulate:a", 1.0, 0.16)
	# ignore_time_scale：顿帧/慢放时通知也照常计时
	get_tree().create_timer(TOAST_LIFE, true, false, true).timeout.connect(
		func() -> void: _expire_toast(chip))


func _expire_toast(chip: Control) -> void:
	if not is_instance_valid(chip):
		return
	_toast_live.erase(chip)
	var tout := create_tween()
	tout.tween_property(chip, "modulate:a", 0.0, 0.22)
	tout.tween_callback(chip.queue_free)
	_pump_toasts()


# ---------------------------------------------------------------- C4 效果条

func _sync_effects() -> void:
	if _effect_box == null or not is_instance_valid(_effect_box):
		return
	var ids: Array = GameState.active_effects.keys()
	for key in _effect_chips.keys():
		if not GameState.active_effects.has(key):
			var dead = _effect_chips[key]
			if is_instance_valid(dead):
				dead.queue_free()
			_effect_chips.erase(key)
	for key in ids:
		if not _effect_chips.has(key):
			_effect_chips[key] = _make_effect_chip(String(key))
	for key in ids:
		var chip = _effect_chips.get(key)
		if chip == null or not is_instance_valid(chip):
			continue
		var e: Dictionary = GameState.active_effects[key]
		var ratio := clampf(float(e.get("time", 0.0)) / maxf(0.01, float(e.get("max", 1.0))), 0.0, 1.0)
		var bar: ProgressBar = chip.get_meta("bar")
		var sec: Label = chip.get_meta("sec")
		if bar != null and is_instance_valid(bar):
			bar.value = ratio * 100.0
		if sec != null and is_instance_valid(sec):
			sec.text = "%ds" % maxi(0, ceili(float(e.get("time", 0.0))))
	_effect_box.visible = not ids.is_empty()


func _make_effect_chip(effect_id: String) -> Control:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("normal", _chip_bg())
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var icon := UiIcons.item(effect_id)
	if icon != null:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(14, 14)
		tr.texture = icon
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr)
	var lbl := Label.new()
	var e: Dictionary = GameState.active_effects.get(effect_id, {})
	lbl.text = String(e.get("label", effect_id))
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(4, 16)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	bar.add_theme_stylebox_override("background", _chip_bg())
	bar.add_theme_stylebox_override("fill", _fill(UiTheme.COL_GOLD))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var sec := Label.new()
	sec.add_theme_font_size_override("font_size", 11)
	sec.add_theme_color_override("font_color", UiTheme.COL_GOLD)
	sec.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sec)
	chip.set_meta("bar", bar)
	chip.set_meta("sec", sec)
	_effect_box.add_child(chip)
	return chip


# ---------------------------------------------------------------- C5 Tooltip

func bind_tooltip(ctl: Control, text_provider: Callable) -> void:
	if ctl == null or not is_instance_valid(ctl):
		return
	ctl.mouse_filter = Control.MOUSE_FILTER_STOP
	ctl.mouse_entered.connect(func() -> void: _begin_hover(ctl, text_provider))
	ctl.mouse_exited.connect(func() -> void: _end_hover(ctl))


func _begin_hover(ctl: Control, text_provider: Callable) -> void:
	_hover_ctl = ctl
	_hover_text = text_provider
	_hover_t = 0.0
	if _tooltip != null:
		_tooltip.visible = false


func _end_hover(ctl: Control) -> void:
	if _hover_ctl == ctl:
		_hover_ctl = null
		_hover_text = Callable()
		if _tooltip != null:
			_tooltip.visible = false


func _sync_tooltip(delta: float) -> void:
	if _tooltip == null or _tooltip_label == null:
		return
	if _hover_ctl == null or not is_instance_valid(_hover_ctl) or not _hover_ctl.is_visible_in_tree():
		_hover_ctl = null
		_tooltip.visible = false
		return
	_hover_t += delta
	if _hover_t < TOOLTIP_DELAY:
		return
	var txt := ""
	if _hover_text.is_valid():
		txt = String(_hover_text.call())
	if txt.is_empty():
		_tooltip.visible = false
		return
	_tooltip_label.text = txt
	_tooltip.visible = true
	_tooltip.reset_size()
	var vp := get_viewport().get_visible_rect().size
	var mp := get_viewport().get_mouse_position()
	var pos := mp + Vector2(16.0, 14.0)
	pos.x = clampf(pos.x, 6.0, maxf(6.0, vp.x - _tooltip.size.x - 6.0))
	pos.y = clampf(pos.y, 6.0, maxf(6.0, vp.y - _tooltip.size.y - 6.0))
	_tooltip.position = pos


## 让槽位内部的文字/图标不再吃鼠标事件，hover 才会落在槽位本身。
func _ignore_mouse_recursive(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse_recursive(c)

func _process(delta: float) -> void:
	phase_label.text = GameState.get_phase_label()
	_sync_effects()
	_sync_tooltip(delta)
	if dev_label != null:
		dev_label.text = DevMode.status_text()
		dev_label.visible = DevMode.enabled
	# 交互提示呼吸：让底部提示不"死板"，但只做透明度，避免和容器布局打架
	if prompt_chip != null and prompt_label != null:
		if prompt_chip.visible:
			var t := Time.get_ticks_msec() / 1000.0
			prompt_label.modulate.a = 0.80 + 0.20 * sin(t * 4.0)
		else:
			prompt_label.modulate.a = 1.0
	_update_panel_side(delta)
	# 低理智：越接近 0 越红，带 1.5s 左右的心跳呼吸
	if _sanity_vignette != null:
		var low := clampf((SANITY_WARN - GameState.emptiness) / SANITY_WARN, 0.0, 1.0)
		var t := Time.get_ticks_msec() / 1000.0
		var pulse := 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 4.2))
		_sanity_vignette.modulate.a = lerpf(_sanity_vignette.modulate.a, low * pulse, clampf(delta * 5.0, 0.0, 1.0))

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
