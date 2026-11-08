extends Node2D

## 宝箱怪（Mimic）预览：4 个变体，4 帧呼吸循环。

const COUNT := 4

var sprites: Array[Sprite2D] = []
var t := 0.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.12))
	var vs := get_viewport().get_visible_rect().size
	var cell := Vector2(vs.x / float(COUNT), vs.y)
	var font := UiTheme.font()
	for i in COUNT:
		var idx := i + 1
		var tex: Texture2D = load("res://art/sprites/monsters/mimic_%02d_walk_front.png" % idx)
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.hframes = 4
		s.vframes = 1
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var frame_w := float(tex.get_width()) / 4.0
		var sc: float = minf((cell.x - 20.0) / frame_w, (cell.y - 40.0) / float(tex.get_height()))
		s.scale = Vector2(sc, sc)
		s.position = Vector2(cell.x * (i + 0.5), cell.y * 0.55)
		add_child(s)
		sprites.append(s)

		var l := Label.new()
		l.text = "mimic_%02d" % idx
		l.position = Vector2(cell.x * i + 12.0, 10.0)
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 16)
		l.modulate = Color(1.0, 0.86, 0.4)
		add_child(l)

func _process(delta: float) -> void:
	t += delta
	var f := int(t * 4.0) % 4
	for s in sprites:
		s.frame = f
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()
