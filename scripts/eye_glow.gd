class_name EyeGlow
extends PointLight2D

## B12：敌人红眼。挂在敌人节点下的一盏很小的红色点光。
##
## - 暴君：常亮（fading 时关掉）
## - 普通学生：只有 chase / search / stalk 才亮，平时不吓人
## - 白天（第 1 关且没停电）整体压暗到几乎不可见
##
## 纯代码生成径向贴图，不拷任何素材。

const TEX_SIZE := 64
const BASE := 1.15

var energy_base := BASE
var always_on := false
var dot_scale := 0.20


func _ready() -> void:
	texture = _make_dot()
	color = Color(1.0, 0.16, 0.12)
	texture_scale = dot_scale
	blend_mode = Light2D.BLEND_MODE_ADD
	shadow_enabled = false
	energy = 0.0


func _process(_delta: float) -> void:
	energy = energy_base * _factor()


func _factor() -> float:
	if not GameState.dark_vision:
		return 0.0
	var parent := get_parent()
	if parent == null:
		return 0.0
	var fading = parent.get("fading")
	if fading != null and bool(fading):
		return 0.0
	if not always_on and parent.get("state") != null:
		var st := String(parent.get("state"))
		if st == "chase":
			return 1.0
		if st == "search" or st == "stalk":
			return 0.65
		return 0.0
	# 呼吸闪烁，红眼不至于像两颗常亮 LED
	return 0.82 + 0.18 * sin(Time.get_ticks_msec() * 0.006)


func _make_dot() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := TEX_SIZE * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var d := Vector2(float(x) + 0.5 - c, float(y) + 0.5 - c).length() / c
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
