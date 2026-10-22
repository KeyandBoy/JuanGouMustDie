extends Node2D

var radius := 26.0
var count := 11
var alpha := 0.45
var speed := 1.0
var puff := 9.0
var dark := Color(0.015, 0.015, 0.02)
var t := 0.0

func _ready() -> void:
	z_as_relative = true

func _process(delta: float) -> void:
	t += delta
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2(0.0, 6.0), radius + 7.0, Color(0.0, 0.0, 0.0, alpha * 0.28))
	for i in count:
		var a: float = t * speed + float(i) * TAU / float(count)
		var r: float = radius + sin(t * 1.6 + float(i) * 1.7) * 5.0
		var pos := Vector2(cos(a), sin(a) * 0.72) * r + Vector2(0.0, -8.0 + sin(t * 2.2 + float(i)) * 3.0)
		var a_puff: float = alpha * (0.4 + 0.6 * (0.5 + 0.5 * sin(t * 2.6 + float(i) * 2.1)))
		draw_circle(pos, puff + sin(t * 2.0 + float(i)) * 3.0, Color(dark.r, dark.g, dark.b, a_puff))
	for j in 3:
		var rise: float = fmod(t * 12.0 + float(j) * 11.0, 60.0)
		var sway: float = sin(t * 1.3 + float(j) * 2.0) * 9.0
		draw_circle(Vector2(sway, -8.0 - rise), 7.0 - float(j), Color(dark.r, dark.g, dark.b, alpha * 0.5 * (1.0 - rise / 60.0)))
