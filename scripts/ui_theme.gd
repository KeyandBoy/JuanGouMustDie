class_name UiTheme
extends Object

## 全局像素风 UI 主题（霓虹像素版）。
## 深色底 + 高饱和描边 + 硬阴影，按钮/面板统一走这里。
## 用法：UiTheme.apply(某个 Control 根) —— 该根的全部子节点自动继承。
## 不碰任何游戏逻辑；缺字体时回退引擎默认字体。

const COL_BG := Color(0.05, 0.03, 0.10)  # 深夜紫黑
const COL_PANEL_BG := Color(0.10, 0.07, 0.18, 0.97)  # 深紫面板
const COL_PANEL_BORDER := Color(0.32, 0.92, 1.0)  # 霓虹青描边
const COL_BTN_BG := Color(0.14, 0.10, 0.24, 0.98)  # 深紫按钮
const COL_BTN_HOVER := Color(0.23, 0.16, 0.38)  # 悬停提亮
const COL_BTN_PRESSED := Color(0.09, 0.06, 0.16)  # 按下压暗
const COL_INPUT_BG := Color(0.08, 0.06, 0.14)  # 输入框
const COL_TEXT := Color(0.97, 0.95, 0.90)  # 暖白
const COL_TEXT_DIM := Color(0.72, 0.70, 0.86)  # 淡紫
const COL_ACCENT := Color(1.0, 0.30, 0.66)  # 荧光粉
const COL_CYAN := Color(0.30, 0.95, 1.0)  # 霓虹青
const COL_GOLD := Color(1.0, 0.84, 0.30)  # 金色
const COL_RED := Color(1.0, 0.30, 0.34)  # 鲜红
const COL_GREEN := Color(0.45, 1.0, 0.55)  # 荧光绿
const COL_BLUE := Color(0.36, 0.66, 1.0)  # 亮蓝
const COL_PURPLE := Color(0.76, 0.48, 1.0)  # 亮紫
const COL_ORANGE := Color(1.0, 0.62, 0.16)  # 鲜橙

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

static func get_button_color(index: int = 0) -> Color:
	var colors = [COL_RED, COL_ORANGE, COL_GOLD, COL_GREEN, COL_CYAN, COL_PURPLE, COL_ACCENT]
	return colors[index % colors.size()]

## 面板/卡片通用硬阴影像素框
static func panel_style(accent: Color = COL_PANEL_BORDER, fill: Color = COL_PANEL_BG, bw := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = accent
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(4, 4)
	return sb

## 菜单按钮：深底 + 彩色左边条；悬停时按钮自身用强调色填充
static func accent_button_style(accent: Color, filled := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = accent if filled else COL_BTN_BG
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.border_width_left = 7
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 14
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(3, 3)
	return sb

static func _sb(bg: Color, border: Color, bw := 2, pad := 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	return sb

static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 16

	t.set_stylebox("panel", "PanelContainer", panel_style())

	var b_normal := _sb(COL_BTN_BG, Color(0.55, 0.40, 0.85), 2, 12)
	var b_hover := _sb(COL_BTN_HOVER, COL_CYAN, 2, 12)
	var b_pressed := _sb(COL_BTN_PRESSED, COL_ACCENT, 2, 12)
	var b_disabled := _sb(Color(0.13, 0.12, 0.16), Color(0.35, 0.33, 0.42), 2, 12)
	b_normal.shadow_color = Color(0, 0, 0, 0.5)
	b_normal.shadow_size = 3
	b_normal.shadow_offset = Vector2(3, 3)
	var b_focus := StyleBoxFlat.new()
	b_focus.draw_center = false
	b_focus.border_color = COL_GOLD
	b_focus.set_border_width_all(3)
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
	t.set_color("font_hover_color", "Button", COL_CYAN)
	t.set_color("font_pressed_color", "Button", COL_TEXT)
	t.set_color("font_disabled_color", "Button", COL_TEXT_DIM)

	var pb_bg := _sb(COL_INPUT_BG, COL_PANEL_BORDER, 2, 2)
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

	var sl_track := _sb(COL_INPUT_BG, COL_PANEL_BORDER, 2, 2)
	var sl_grab := StyleBoxFlat.new()
	sl_grab.bg_color = COL_CYAN
	sl_grab.set_corner_radius_all(0)
	sl_grab.content_margin_left = 4
	sl_grab.content_margin_right = 4
	sl_grab.content_margin_top = 4
	sl_grab.content_margin_bottom = 4
	var sl_grab_hi := sl_grab.duplicate()
	sl_grab_hi.bg_color = COL_GOLD
	t.set_stylebox("slider", "HSlider", sl_track)
	t.set_stylebox("grabber_area", "HSlider", sl_grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", sl_grab_hi)

	t.set_stylebox("normal", "LineEdit", _sb(COL_INPUT_BG, COL_PANEL_BORDER, 2, 8))
	t.set_stylebox("hover", "LineEdit", _sb(COL_INPUT_BG, COL_ACCENT, 2, 8))
	t.set_stylebox("focus", "LineEdit", _sb(COL_INPUT_BG, COL_CYAN, 2, 8))
	t.set_color("font_color", "LineEdit", COL_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", COL_TEXT_DIM)

	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("font_color", "RichTextLabel", COL_TEXT)

	return t
