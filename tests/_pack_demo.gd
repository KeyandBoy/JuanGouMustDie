extends Node2D

## 第二批怪物（grotesque 20 变体）预览：5 列 × 4 行，4 帧循环。

const COUNT := 20

var sprites: Array[Sprite2D] = []
var t := 0.0

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.08, 0.09, 0.12))
	var vs := get_viewport().get_visible_rect().size
	var cols := 5
	var rows := 4
	var cell := Vector2(vs.x / float(cols), vs.y / float(rows))
	var font := UiTheme.font()
	for i in COUNT:
		var idx := i + 1
		var tex: Texture2D = load("res://art/sprites/monsters/pack_%02d_walk_front.png" % idx)
		if tex == null:
			continue
		var s := Sprite2D.new()
		s.texture = tex
		s.hframes = 4
		s.vframes = 1
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var frame_w := float(tex.get_width()) / 4.0
		var sc: float = minf((cell.x - 20.0) / frame_w, (cell.y - 30.0) / float(tex.get_height()))
		s.scale = Vector2(sc, sc)
		s.position = Vector2(cell.x * (i % cols + 0.5), cell.y * (i / cols + 0.5) + 8.0)
		add_child(s)
		sprites.append(s)

		var l := Label.new()
		l.text = "pack_%02d" % idx
		l.position = Vector2(cell.x * (i % cols) + 10.0, cell.y * (i / cols) + 4.0)
		l.add_theme_font_override("font", font)
		l.add_theme_font_size_override("font_size", 14)
		l.modulate = Color(1.0, 0.86, 0.4)
		add_child(l)

func _process(delta: float) -> void:
	t += delta
	var f := int(t * 6.0) % 4
	for s in sprites:
		s.frame = f
	if Input.is_key_pressed(KEY_ESCAPE):
		get_tree().quit()
