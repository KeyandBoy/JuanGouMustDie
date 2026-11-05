class_name GearButton
extends Control

## 圆形设置按钮（类似 iOS 设置图标）：深色圆盘 + 齿轮，纯代码绘制，不依赖美术素材。
## 用法：var g := GearButton.new(); g.pressed.connect(...)
##
## 尺寸固定 52x52，放在右下角；hover 时圆盘提亮、齿轮转金，按下缩到 92%。

signal pressed

const TEETH := 8
const DEFAULT_SIZE := 52.0

var hovered := false
var _down := false
var _hover_t := 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(DEFAULT_SIZE, DEFAULT_SIZE)
	size = Vector2(DEFAULT_SIZE, DEFAULT_SIZE)
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "设置"
	mouse_entered.connect(func():
		hovered = true
		_tween_hover(1.0))
	mouse_exited.connect(func():
		hovered = false
		_tween_hover(0.0))

func _tween_hover(to: float) -> void:
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "_hover_t", to, 0.12)
	tw.tween_callback(queue_redraw)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			scale = Vector2(0.92, 0.92)
			queue_redraw()
		else:
			scale = Vector2.ONE
			queue_redraw()
			if _down:
				_down = false
				accept_event()
				pressed.emit()
	elif event is InputEventMouseMotion and _down:
		pass

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 1.0

	# 投影：让圆盘从背景里浮起来
	draw_circle(c + Vector2(0.0, 2.0), r - 1.0, Color(0.0, 0.0, 0.0, 0.28))

	# 圆盘（iOS 设置图标那种实心圆底）
	var plate := Color(0.10, 0.12, 0.13, 0.82).lerp(Color(0.22, 0.26, 0.24, 0.96), _hover_t)
	draw_circle(c, r - 2.0, plate)

	# 圆环描边
	var ring := Color(UiTheme.COL_TEXT_DIM, 0.55).lerp(UiTheme.COL_GOLD, _hover_t)
	draw_arc(c, r - 2.5, 0.0, TAU, 40, ring, 1.6, true)

	# 齿轮本体
	var gear_col: Color = UiTheme.COL_TEXT_DIM.lerp(UiTheme.COL_GOLD, _hover_t)
	if _down:
		gear_col = gear_col.darkened(0.15)
	var r_out := r * 0.56
	var r_in := r * 0.42
	var hole := plate
	draw_colored_polygon(_gear_polygon(c, r_out, r_in, TEETH), gear_col)
	draw_circle(c, r * 0.17, hole)

func _gear_polygon(c: Vector2, r_out: float, r_in: float, teeth: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var step := TAU / float(teeth)
	var half := step * 0.26
	for i in teeth:
		var a0 := step * float(i)
		# 齿顶：三点小圆弧
		pts.append(c + Vector2(cos(a0 - half), sin(a0 - half)) * r_out)
		pts.append(c + Vector2(cos(a0), sin(a0)) * (r_out + 0.6))
		pts.append(c + Vector2(cos(a0 + half), sin(a0 + half)) * r_out)
		# 齿谷
		pts.append(c + Vector2(cos(a0 + half + step * 0.10), sin(a0 + half + step * 0.10)) * r_in)
		pts.append(c + Vector2(cos(a0 + step - half - step * 0.10), sin(a0 + step - half - step * 0.10)) * r_in)
	return pts
