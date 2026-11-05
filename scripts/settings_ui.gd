class_name SettingsUi
extends Control

## 通用设置面板：左侧分类 + 右侧内容。
##
## 设计目标（为以后加东西留位置）：
##   1. 分类是数据驱动的 —— 加一个 SECTION 条目就多一页，不用改布局代码；
##   2. 每个分类的 builder 都是独立函数，互不影响；
##   3. 所有值都走 SaveManager.setting，改完即存，不需要"应用"按钮。
##
## 目前有：声音 / 画面 / 操作 / 关于。
## 以后可以往 SECTION 里加：语言、无障碍（震屏/闪烁强度）、按键重绑定、难度。

const SECTION_IDS := ["audio", "video", "controls", "about"]
const SECTION_TITLES := {
	"audio": "声音",
	"video": "画面",
	"controls": "操作",
	"about": "关于",
}

var main_ref: Node
var layer_ref: CanvasLayer

var _content: VBoxContainer
var _tab_buttons: Dictionary = {}
var _current := "audio"

static func open(main: Node) -> void:
	if main == null or not is_instance_valid(main):
		return
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	main._push_modal(layer)
	var ui := SettingsUi.new()
	ui.main_ref = main
	ui.layer_ref = layer
	layer.add_child(ui)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiTheme.apply(self)
	_build()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 470)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.COL_PANEL_BORDER, UiTheme.COL_PANEL_BG, 2))
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)

	# —— 标题栏 ——
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	outer.add_child(head)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "关闭 (ESC)"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# —— 主体：左分类 / 右内容 ——
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(body)

	var tabs := VBoxContainer.new()
	tabs.custom_minimum_size = Vector2(132, 0)
	tabs.add_theme_constant_override("separation", 6)
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for id in SECTION_IDS:
		var b := Button.new()
		b.text = String(SECTION_TITLES[id])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _show_section(id))
		tabs.add_child(b)
		_tab_buttons[id] = b
	if _tab_buttons.has(_current):
		_tab_buttons[_current].button_pressed = true

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)
	scroll.add_child(_content)

	_show_section(_current)

func _show_section(id: String) -> void:
	_current = id
	if _tab_buttons.has(id):
		_tab_buttons[id].button_pressed = true
	for c in _content.get_children():
		c.queue_free()
	match id:
		"audio":
			_build_audio()
		"video":
			_build_video()
		"controls":
			_build_controls()
		"about":
			_build_about()

# ---------------------------------------------------------------- 声音

func _build_audio() -> void:
	_content.add_child(_section_note("音量改动立即生效并自动保存。"))
	_add_slider_row("主音量", AudioManager.master_volume, AudioManager.set_master_volume)
	_add_slider_row("音乐音量", AudioManager.music_volume, AudioManager.set_music_volume)
	_add_slider_row("音效音量", AudioManager.sfx_volume, AudioManager.set_sfx_volume)

	var mute := CheckButton.new()
	mute.text = "静音"
	mute.button_pressed = AudioManager.muted
	mute.focus_mode = Control.FOCUS_NONE
	mute.toggled.connect(func(on: bool):
		AudioManager.set_muted(on)
		_play_ui_click())
	_content.add_child(mute)

	_content.add_child(HSeparator.new())
	_content.add_child(_section_note("以后可以在这里放：语音音量、动态范围、低通滤波（被追时闷音）。"))

func _add_slider_row(label_text: String, value: float, setter: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(96, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var val := Label.new()
	val.text = "%d%%" % int(value)
	val.custom_minimum_size = Vector2(52, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	slider.value_changed.connect(func(v: float):
		setter.call(v)
		val.text = "%d%%" % int(v))
	slider.drag_ended.connect(func(_changed: bool): _play_ui_click())
	_content.add_child(row)

# ---------------------------------------------------------------- 画面

func _build_video() -> void:
	var fullscreen := CheckButton.new()
	fullscreen.text = "全屏"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.focus_mode = Control.FOCUS_NONE
	fullscreen.toggled.connect(func(on: bool):
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
		SaveManager.set_setting("fullscreen", on))
	_content.add_child(fullscreen)

	_content.add_child(HSeparator.new())
	_content.add_child(_section_note("震屏强度：对晕动症友好，也方便录制视频。"))
	var shake_row := HBoxContainer.new()
	shake_row.add_theme_constant_override("separation", 8)
	var shake_lbl := Label.new()
	shake_lbl.text = "震屏"
	shake_lbl.custom_minimum_size = Vector2(96, 0)
	shake_row.add_child(shake_lbl)
	var group := ButtonGroup.new()
	var presets := [["关闭", 0.0], ["减弱", 50.0], ["正常", 100.0]]
	var current := float(SaveManager.get_setting("shake", 100.0))
	for p in presets:
		var b := Button.new()
		b.text = String(p[0])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = is_equal_approx(current, float(p[1]))
		var v: float = p[1]
		b.pressed.connect(func():
			SaveManager.set_setting("shake", v)
			_play_ui_click())
		shake_row.add_child(b)
	_content.add_child(shake_row)

	_content.add_child(HSeparator.new())
	_content.add_child(_section_note("以后可以在这里放：亮度/伽马、像素缩放、画面亮度闪烁强度（无障碍）。"))

# ---------------------------------------------------------------- 操作

func _build_controls() -> void:
	_content.add_child(_section_note("目前键位固定；以后可在这里做重绑定。"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for pair in [
		["移动", "WASD / 方向键"],
		["冲刺", "Shift"],
		["学习 / 继续答题", "F"],
		["起身 / 取消", "ESC"],
		["道具 1 / 2 / 3", "R / T / Y"],
		["暂停", "ESC"],
		["交互", "F 或 E"],
	]:
		var k := Label.new()
		k.text = String(pair[0])
		k.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
		grid.add_child(k)
		var v := Label.new()
		v.text = String(pair[1])
		grid.add_child(v)
	_content.add_child(grid)

# ---------------------------------------------------------------- 关于

func _build_about() -> void:
	for line in [
		"《卷狗必须死》",
		"校园怪谈 · 潜行 · 答题",
		"",
		"引擎：Godot 4.7.2",
		"字体：方舟像素字体 Ark Pixel（OFL-1.1）",
		"",
		"感谢所有参与测试的同学。",
	]:
		var l := Label.new()
		l.text = String(line)
		l.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM if line == "" else UiTheme.COL_TEXT)
		_content.add_child(l)

# ---------------------------------------------------------------- 工具

func _section_note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
	return l

func _play_ui_click() -> void:
	if AudioManager.has_method("play_ui"):
		AudioManager.play_ui("click")

func close() -> void:
	if main_ref != null and is_instance_valid(main_ref) and layer_ref != null:
		main_ref._pop_modal(layer_ref)
	else:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
