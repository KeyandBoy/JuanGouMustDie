extends CanvasLayer

signal finished

const SCENES := [
	{
		"bg": "res://art/cutscene/intro_classroom.png",
		"text": "我以为，只是睡了一觉。",
		"dur": 1.5,
		"danger": false,
	},
	{
		"bg": "res://art/cutscene/intro_board.png",
		"text": "醒来时，躺在一间陌生的教室。\n黑板上还留着四个没干的字——",
		"dur": 2.1,
		"danger": false,
	},
	{
		"bg": "res://art/cutscene/intro_board.png",
		"text": "「内卷即死」",
		"dur": 1.4,
		"danger": true,
		"chalk": true,
		"hide_line": true,
	},
	{
		"bg": "res://art/cutscene/intro_hall.png",
		"text": "这里是 躺平世界：内卷违法，被发现就会被打死。\n可我的「学习之魂」，不允许我裸考。",
		"dur": 2.2,
		"danger": false,
		"hold_input": true,
	},
]

const TITLE_TEXT := "卷狗必须死"
const SUB_TEXT := "不学习，就死。"

var _skip := false
var _advance := false
var _done := false
var _bg: TextureRect
var _bg_dark: ColorRect
var _backdrop: ColorRect
var _line: Label
var _chalk: Label
var _font: FontFile
var _shake_amp := 0.0

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_skip = true
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
			_advance = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance = true

func _font_or_default() -> Font:
	if _font == null and ResourceLoader.exists("res://assets/fonts/zpix.ttf"):
		_font = load("res://assets/fonts/zpix.ttf")
	if _font != null:
		return _font
	return ThemeDB.fallback_font

func play() -> void:
	# 不透明遮底：开场动画期间底下还挂着主场景（地图/玩家/HUD），
	# 没有这层的话换图或首帧会直接露出第一关的游戏画面。
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.0, 0.0, 0.0, 1.0)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backdrop)
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_bg_dark = ColorRect.new()
	_bg_dark.color = Color(0.0, 0.0, 0.0, 0.55)
	_bg_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_dark)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_line = Label.new()
	_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.add_theme_font_override("font", _font_or_default())
	_line.add_theme_font_size_override("font_size", 26)
	_line.add_theme_color_override("font_color", Color(0.93, 0.93, 0.94))
	_line.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_line.add_theme_constant_override("outline_size", 6)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.modulate.a = 0.0
	root.add_child(_line)
	var hint := Label.new()
	hint.text = "回车 / 点击：继续　ESC：跳过"
	hint.add_theme_font_override("font", _font_or_default())
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78, 0.9))
	hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	hint.add_theme_constant_override("outline_size", 4)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -460
	hint.offset_top = -40
	hint.offset_right = -18
	hint.offset_bottom = -14
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
	await _hold(0.25)
	await _run_scenes()
	if not _skip:
		await _title_card()
	_finish()

func _run_scenes() -> void:
	for scene in SCENES:
		if _skip:
			return
		_clear_chalk()
		var path := String(scene["bg"])
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if tex != null:
			_bg.texture = tex
			_bg.modulate.a = 0.0
			var ft := create_tween()
			ft.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			ft.tween_property(_bg, "modulate:a", 1.0, 0.35)
			var kt := create_tween()
			kt.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			_bg.scale = Vector2.ONE
			_bg.pivot_offset = _bg.size * 0.5
			kt.tween_property(_bg, "scale", Vector2(1.07, 1.07), float(scene["dur"]) + 0.6)
		var show_line := not bool(scene.get("hide_line", false))
		if scene.get("chalk", false):
			await _chalk_write("内卷即死")
		if _skip:
			return
		_line.text = ""
		_line.add_theme_color_override("font_color", Color(0.95, 0.32, 0.3) if scene["danger"] else Color(0.93, 0.93, 0.94))
		_shake_amp = 2.6 if scene["danger"] else 0.0
		if show_line:
			var tw_in := create_tween()
			tw_in.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tw_in.tween_property(_line, "modulate:a", 1.0, 0.22)
			await _type(String(scene["text"]))
			if _skip:
				_line.text = String(scene["text"])
				return
		else:
			_line.modulate.a = 0.0
		if scene["danger"]:
			await _red_flash()
		if bool(scene.get("hold_input", false)):
			await _hold_until_advance(16.0)
		else:
			await _hold(_read_time(scene))
		if show_line:
			var tw_out := create_tween()
			tw_out.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			tw_out.tween_property(_line, "modulate:a", 0.0, 0.25)
		_shake_amp = 0.0
		await _hold(0.25)
		_clear_chalk()

func _hold_until_advance(max_sec: float) -> void:
	var t := 0.0
	while t < max_sec:
		if _skip:
			return
		if _advance:
			_advance = false
			return
		await get_tree().create_timer(0.03).timeout
		t += 0.03

func _read_time(scene: Dictionary) -> float:
	var text := String(scene.get("text", ""))
	var by_length := float(text.length()) * 0.18 + 1.0
	return maxf(float(scene.get("dur", 1.4)), by_length)

func _clear_chalk() -> void:
	if _chalk == null or not is_instance_valid(_chalk):
		_chalk = null
		return
	var c := _chalk
	_chalk = null
	if _skip:
		c.queue_free()
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(c, "modulate:a", 0.0, 0.22)
	tw.tween_callback(c.queue_free)

func _chalk_write(text: String) -> void:
	var chalk := Label.new()
	chalk.add_theme_font_override("font", _font_or_default())
	chalk.add_theme_font_size_override("font_size", 62)
	chalk.add_theme_color_override("font_color", Color(0.88, 0.88, 0.84, 0.92))
	chalk.add_theme_color_override("font_outline_color", Color(0.3, 0.3, 0.28, 0.55))
	chalk.add_theme_constant_override("outline_size", 3)
	chalk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chalk.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chalk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chalk.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	chalk.offset_top = -vs.y * 0.18
	chalk.offset_bottom = -vs.y * 0.18
	chalk.modulate.a = 0.0
	_chalk = chalk
	add_child(chalk)
	var i := 0
	while i < text.length():
		if _skip:
			chalk.text = text
			break
		if _advance:
			_advance = false
			chalk.text = text
			break
		i += 1
		chalk.text = text.substr(0, i)
		var t := create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_property(chalk, "modulate:a", 0.35, 0.02)
		t.tween_property(chalk, "modulate:a", 1.0, 0.08)
		await get_tree().create_timer(0.11).timeout
	chalk.text = text
	chalk.modulate.a = 1.0
	await _hold(0.05)

func _red_flash() -> void:
	var flash := ColorRect.new()
	flash.color = Color(0.75, 0.05, 0.05, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.tween_property(flash, "color:a", 0.35, 0.08)
	t.tween_property(flash, "color:a", 0.0, 0.45)
	t.tween_callback(flash.queue_free)
	_shake_amp = 9.0
	await _hold(0.1)
	_shake_amp = 3.0

func _type(text: String) -> void:
	var i := 0
	while i < text.length():
		if _skip:
			_line.text = text
			return
		if _advance:
			_advance = false
			_line.text = text
			return
		i += 1
		_line.text = text.substr(0, i)
		await get_tree().create_timer(0.032).timeout

func _title_card() -> void:
	_clear_chalk()
	_bg_dark.color = Color(0.0, 0.0, 0.0, 0.92)
	_line.text = ""
	_line.modulate.a = 0.0
	_line.pivot_offset = _line.size * 0.5
	_line.scale = Vector2(1.7, 1.7)
	_line.add_theme_font_size_override("font_size", 64)
	_line.add_theme_color_override("font_color", Color(0.85, 0.08, 0.08))
	_line.text = TITLE_TEXT
	var t1 := create_tween()
	t1.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t1.tween_property(_line, "modulate:a", 1.0, 0.18)
	t1.parallel().tween_property(_line, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await _hold(0.9)
	if _skip:
		return
	_line.add_theme_font_size_override("font_size", 22)
	_line.add_theme_color_override("font_color", Color(0.78, 0.78, 0.8))
	_line.text = SUB_TEXT
	await _hold(1.4)

func _hold(sec: float) -> void:
	var t := 0.0
	while t < sec:
		if _skip:
			return
		if _advance:
			_advance = false
			return
		await get_tree().create_timer(0.03).timeout
		t += 0.03
		if _shake_amp > 0.0 and _line != null:
			_line.position = Vector2(randf_range(-_shake_amp, _shake_amp), randf_range(-_shake_amp, _shake_amp))
	if _line != null:
		_line.position = Vector2.ZERO

func _finish() -> void:
	if _done:
		return
	_done = true
	_chalk = null
	if _line != null:
		_line.position = Vector2.ZERO
	var fade := ColorRect.new()
	fade.color = Color(0, 0, 0, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(fade, "color:a", 1.0, 0.45)
	await tw.finished
	finished.emit()
