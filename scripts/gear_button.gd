class_name GearButton
extends Control

## 纯代码绘制的齿轮图标按钮（不依赖美术素材，任何分辨率都清晰）。
## 用法：var g := GearButton.new(); g.pressed.connect(...)

signal pressed

const TEETH := 8

var hovered := false
var _pressed := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tooltip_text = "设置"
	mouse_entered.connect(func():
		hovered = true
		queue_redraw())
	mouse_exited.connect(func():
		hovered = false
		queue_redraw())

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			queue_redraw()
		else:
			if _pressed:
				_pressed = false
				queue_redraw()
				pressed.emit()
			accept_event()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 3.0
	var col: Color = UiTheme.COL_GOLD if (hovered or _pressed) else UiTheme.COL_TEXT_DIM
	# 外圈齿
	for i in TEETH:
		var a := TAU * float(i) / float(TEETH)
		var d := Vector2(cos(a), sin(a))
		var p := c + d * r * 0.80
		draw_set_transform(p, a, Vector2.ONE)
		draw_rect(Rect2(-2.5, -5.0, 5.0, 10.0), col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 环与轴心
	draw_arc(c, r * 0.52, 0.0, TAU, 20, col, 2.5, true)
	draw_circle(c, r * 0.16, col)
