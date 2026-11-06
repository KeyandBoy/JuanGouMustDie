class_name TorchLight
extends PointLight2D

## B12：玩家手电光锥。
##
## 纯代码生成一张「顶点在中心、向 +X 展开」的锥形贴图，节点旋转跟着朝向走。
## 不依赖任何美术素材；不参与碰撞，也不改 CanvasModulate。
## 没有开 2D 光照的旧场景（教学关）里只是多一层很淡的暖光，不会破坏画面。

const HALF_ANGLE := 0.42  # 约 24°
const LENGTH := 128.0
const TEX_SIZE := 256

var energy_base := 0.72
var active := false
var _fade: Tween


func _ready() -> void:
	texture = _make_cone()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	color = Color(1.0, 0.90, 0.72)
	energy = 0.0
	visible = false
	texture_scale = 1.05
	blend_mode = Light2D.BLEND_MODE_ADD
	shadow_enabled = false


## B12：只有停电/低可视度时才点亮；普通关保持熄灭。
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if on:
		visible = true
		_fade = create_tween()
		_fade.tween_property(self, "energy", energy_base, 0.2)
	else:
		_fade = create_tween()
		_fade.tween_property(self, "energy", 0.0, 0.3)
		_fade.tween_callback(func() -> void: visible = false)


func set_facing(dir: Vector2) -> void:
	if dir.length_squared() < 0.001:
		return
	rotation = dir.angle()


func _process(_delta: float) -> void:
	if not active:
		return
	if _fade != null and _fade.is_valid():
		return
	# 轻微呼吸，避免光锥像贴纸一样死板
	energy = energy_base * (0.94 + 0.06 * sin(Time.get_ticks_msec() * 0.004))


func _make_cone() -> ImageTexture:
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	var c := TEX_SIZE * 0.5
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var dx := float(x) + 0.5 - c
			var dy := float(y) + 0.5 - c
			var dist := sqrt(dx * dx + dy * dy)
			var a := 0.0
			if dx > 0.0 and dist <= LENGTH:
				var ang := absf(atan2(dy, dx))
				if ang < HALF_ANGLE:
					var ang_fall := 1.0 - smoothstep(HALF_ANGLE * 0.55, HALF_ANGLE, ang)
					var dist_fall := pow(1.0 - dist / LENGTH, 1.35)
					a = ang_fall * dist_fall
			# 底部一圈小光晕，光锥起点不突兀
			if dist < 26.0:
				a = maxf(a, (1.0 - dist / 26.0) * 0.35)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
