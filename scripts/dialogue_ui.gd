extends Control

signal finished

var data: DialogueData
var index := -1
var typing := false

var _tween: Tween
var _name_label: Label
var _text_label: Label
var _hint: Label
var _left: TextureRect
var _right: TextureRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	UiTheme.apply(self)
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)

func _fit_viewport() -> void:
	var vs := get_viewport_rect().size
	position = Vector2.ZERO
	size = vs

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.32)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 28.0
	panel.offset_right = -28.0
	panel.offset_top = -178.0
	panel.offset_bottom = -24.0
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.COL_PANEL_BORDER, UiTheme.COL_PANEL_BG, 2))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)

	_left = TextureRect.new()
	_left.custom_minimum_size = Vector2(44, 44)
	_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_left.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(_left)

	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", UiTheme.COL_ACCENT)
	_name_label.add_theme_font_size_override("font_size", 17)
	head.add_child(_name_label)

	_right = TextureRect.new()
	_right.custom_minimum_size = Vector2(44, 44)
	_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_right.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	head.add_child(_right)

	_text_label = Label.new()
	_text_label.name = "Text"
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 16)
	_text_label.add_theme_color_override("font_color", UiTheme.COL_TEXT)
	_text_label.custom_minimum_size = Vector2(0, 64)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_text_label)

	_hint = Label.new()
	_hint.text = "空格 / 点击 继续"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", UiTheme.COL_TEXT_DIM)
	_hint.visible = false
	vb.add_child(_hint)

func start(p_data: DialogueData) -> void:
	data = p_data
	index = -1
	visible = true
	_next()

func advance() -> void:
	if not visible:
		return
	if typing:
		_finish_typing()
		return
	_next()

func _next() -> void:
	if data == null:
		_close()
		return
	index += 1
	if index >= data.lines.size():
		_close()
		return
	var line: DialogueLine = data.lines[index]
	_name_label.text = line.speaker
	_text_label.text = ""
	_hint.visible = false
	if line.portrait == null:
		_left.texture = null
		_right.texture = null
	elif line.on_left:
		_left.texture = line.portrait
		_right.texture = null
	else:
		_left.texture = null
		_right.texture = line.portrait
	if line.flag != "":
		GameState.story_flags[line.flag] = true
	typing = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var text := line.text
	for i in text.length():
		_tween.tween_callback(_append_char.bind(text[i])).set_delay(maxf(0.004, line.seconds_per_char))
	_tween.tween_callback(_finish_typing)

func _append_char(ch: String) -> void:
	_text_label.text += ch

func _finish_typing() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if data != null and index >= 0 and index < data.lines.size():
		_text_label.text = data.lines[index].text
	typing = false
	_hint.visible = true

func _close() -> void:
	visible = false
	typing = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE or event.keycode == KEY_F:
			go = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		go = true
	if go:
		get_viewport().set_input_as_handled()
		advance()
