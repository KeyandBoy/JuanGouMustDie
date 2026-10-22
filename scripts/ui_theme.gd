class_name UiTheme
extends Object

## 全局像素风 UI 主题（批次 1）。
## 只管外观：zpix 字体、深色硬边框 StyleBox、四态按钮、面板/进度条/滑条。
## 用法：UiTheme.apply(某个 Control 根) —— 该根的全部子节点自动继承。
## 不碰任何游戏逻辑；缺字体时回退引擎默认字体。

const COL_PANEL_BG := Color(0.106, 0.118, 0.169, 0.94)
const COL_PANEL_BORDER := Color(0.227, 0.251, 0.329)
const COL_BTN_BG := Color(0.149, 0.169, 0.239)
const COL_BTN_HOVER := Color(0.212, 0.251, 0.361)
const COL_BTN_PRESSED := Color(0.071, 0.078, 0.114)
const COL_INPUT_BG := Color(0.071, 0.078, 0.114)
const COL_TEXT := Color(0.91, 0.90, 0.88)
const COL_TEXT_DIM := Color(0.62, 0.64, 0.72)
const COL_ACCENT := Color(0.482, 0.788, 0.435)
const COL_CYAN := Color(0.490, 0.878, 1.0)
const COL_GOLD := Color(1.0, 0.82, 0.33)
const COL_RED := Color(0.85, 0.25, 0.25)

static var _theme: Theme = null

static func font() -> Font:
	if ResourceLoader.exists("res://assets/fonts/zpix.ttf"):
		var f: Font = load("res://assets/fonts/zpix.ttf")
		if f != null:
			return f
	return ThemeDB.fallback_font

static func apply(root: Control) -> void:
	if _theme == null:
		_theme = _build()
	root.theme = _theme

static func _sb(bg: Color, border: Color, bw := 1, pad := 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.55
	sb.content_margin_bottom = pad * 0.55
	return sb

static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16

	# —— 面板 ——
	t.set_stylebox("panel", "PanelContainer", _sb(COL_PANEL_BG, COL_PANEL_BORDER, 1, 12))

	# —— 按钮四态 + focus ——
	var b_normal := _sb(COL_BTN_BG, COL_PANEL_BORDER, 1, 12)
	var b_hover := _sb(COL_BTN_HOVER, COL_ACCENT, 1, 12)
	var b_pressed := _sb(COL_BTN_PRESSED, COL_ACCENT, 1, 12)
	var b_disabled := _sb(Color(0.12, 0.13, 0.18), Color(0.18, 0.19, 0.25), 1, 12)
	var b_focus := StyleBoxFlat.new()
	b_focus.draw_center = false
	b_focus.border_color = COL_CYAN
	b_focus.set_border_width_all(1)
	b_focus.set_corner_radius_all(0)
	b_focus.content_margin_left = 0
	b_focus.content_margin_right = 0
	b_focus.content_margin_top = 0
	b_focus.content_margin_bottom = 0
	t.set_stylebox("normal", "Button", b_normal)
	t.set_stylebox("hover", "Button", b_hover)
	t.set_stylebox("pressed", "Button", b_pressed)
	t.set_stylebox("disabled", "Button", b_disabled)
	t.set_stylebox("focus", "Button", b_focus)
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", COL_ACCENT)
	t.set_color("font_disabled_color", "Button", COL_TEXT_DIM)

	# —— 进度条 ——
	var pb_bg := _sb(Color(0.071, 0.078, 0.114), COL_PANEL_BORDER, 1, 2)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = COL_ACCENT
	pb_fill.set_corner_radius_all(0)
	pb_fill.content_margin_left = 2
	pb_fill.content_margin_right = 2
	pb_fill.content_margin_top = 2
	pb_fill.content_margin_bottom = 2
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "ProgressBar", COL_TEXT)

	# —— 滑条 ——
	var sl_track := _sb(Color(0.071, 0.078, 0.114), COL_PANEL_BORDER, 1, 2)
	var sl_grab := StyleBoxFlat.new()
	sl_grab.bg_color = COL_TEXT
	sl_grab.set_corner_radius_all(0)
	sl_grab.content_margin_left = 3
	sl_grab.content_margin_right = 3
	sl_grab.content_margin_top = 3
	sl_grab.content_margin_bottom = 3
	var sl_grab_hi := sl_grab.duplicate()
	sl_grab_hi.bg_color = COL_ACCENT
	t.set_stylebox("slider", "HSlider", sl_track)
	t.set_stylebox("grabber_area", "HSlider", sl_grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", sl_grab_hi)

	# —— 文本输入（填空题） ——
	t.set_stylebox("normal", "LineEdit", _sb(COL_INPUT_BG, COL_PANEL_BORDER, 1, 8))
	t.set_stylebox("hover", "LineEdit", _sb(COL_INPUT_BG, COL_ACCENT, 1, 8))
	t.set_stylebox("focus", "LineEdit", _sb(COL_INPUT_BG, COL_CYAN, 1, 8))
	t.set_color("font_color", "LineEdit", COL_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", COL_TEXT_DIM)

	# —— Label ——
	t.set_color("font_color", "Label", COL_TEXT)

	return t
