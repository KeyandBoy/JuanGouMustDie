class_name UiTheme
extends Object

## 全局像素风 UI 主题（校园怪谈荒诞微恐怖版）。
## 昏暗灰绿 + 诡异配色 + 病态气氛，老旧校舍感。
## 用法：UiTheme.apply(某个 Control 根) —— 该根的全部子节点自动继承。
## 不碰任何游戏逻辑；缺字体时回退引擎默认字体。

const COL_BG := Color(0.12, 0.15, 0.13)  # 昏暗灰绿背景
const COL_PANEL_BG := Color(0.16, 0.20, 0.18, 0.96)  # 病态灰绿面板
const COL_PANEL_BORDER := Color(0.38, 0.48, 0.42)  # 诡异灰绿边框
const COL_BTN_BG := Color(0.22, 0.32, 0.28)  # 暗沉蓝绿按钮
const COL_BTN_HOVER := Color(0.32, 0.44, 0.38)  # 悬停时灰绿变亮
const COL_BTN_PRESSED := Color(0.13, 0.19, 0.16)  # 按下时压暗
const COL_INPUT_BG := Color(0.18, 0.22, 0.20)  # 昏暗输入框
const COL_TEXT := Color(0.88, 0.88, 0.82)  # 苍白偏黄的文字
const COL_TEXT_DIM := Color(0.58, 0.60, 0.54)  # 昏暗文字
const COL_ACCENT := Color(0.60, 0.78, 0.68)  # 诡异灰绿强调
const COL_CYAN := Color(0.45, 0.70, 0.65)  # 诡异青绿焦点
const COL_GOLD := Color(0.72, 0.65, 0.42)  # 生锈金属色
const COL_RED := Color(0.68, 0.28, 0.28)  # 暗红（血迹感）
const COL_GREEN := Color(0.42, 0.62, 0.48)  # 病态绿
const COL_BLUE := Color(0.32, 0.52, 0.58)  # 暗冷蓝
const COL_PURPLE := Color(0.50, 0.40, 0.58)  # 暗紫（诡异感）
const COL_ORANGE := Color(0.62, 0.42, 0.22)  # 昏黄（坏灯泡）

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
