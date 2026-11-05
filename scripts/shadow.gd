class_name CharacterShadow
extends Node2D

## B4：统一角色影子。单独节点、纯代码画椭圆，不烘进角色贴图。
##
## 用法（作为角色子节点，放在 sprite 之前即可画在脚下）：
##   var sh := ShadowScript.new()
##   sh.setup(Vector2(13, 4.5), Vector2(0, 17))
##   add_child(sh)
##
## 影子不参与碰撞、不响应鼠标；颜色透明度固定，所有角色共用同一形状。
## 由外到内叠三层椭圆（越外越透明），在没有美术笔刷的情况下模拟一点柔边，
## 避免小尺寸纯色椭圆在暗场地板上糊成一团或干脆看不见。

var radius := Vector2(13.0, 4.5)
var alpha := 0.34
var color := Color(0.0, 0.0, 0.0)

const SEGMENTS := 24
const SOFT_LAYERS := 3

func setup(p_radius: Vector2, p_offset: Vector2, p_alpha := 0.34) -> void:
	radius = p_radius
	position = p_offset
	alpha = p_alpha


func _ready() -> void:
	z_as_relative = true
	z_index = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	# 外层先画：半径更大、更透明，形成 1~2px 的柔边
	for layer in range(SOFT_LAYERS, 0, -1):
		var grow := 1.0 + float(layer - 1) * 0.14
		var layer_alpha := alpha * (0.45 if layer > 1 else 1.0) / float(layer)
		var pts := PackedVector2Array()
		for i in SEGMENTS:
			var a := TAU * float(i) / float(SEGMENTS)
			pts.append(Vector2(cos(a) * radius.x * grow, sin(a) * radius.y * grow))
		var c := color
		c.a = layer_alpha
		draw_colored_polygon(pts, c)
