extends Area2D

signal picked(item_id: String)
signal full(item_id: String)

var item_id := "coffee"
var color := Color.WHITE
var icon_tex: Texture2D = null
var bob := 0.0
var _used := false

func _ready() -> void:
	add_to_group("pickups")
	monitoring = true
	monitorable = true
	collision_layer = 0
	collision_mask = 1
	z_index = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)

func setup(id: String, p_color: Color) -> void:
	item_id = id
	color = p_color
	icon_tex = UiIcons.item(id)

func _process(delta: float) -> void:
	bob += delta * 3.0
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if _used or not body.is_in_group("player"):
		return
	_used = true
	if GameState.add_item(item_id):
		picked.emit(item_id)
		queue_free()
	else:
		full.emit(item_id)
		_used = false

func _draw() -> void:
	var off := Vector2(0.0, sin(bob) * 2.0)
	var hostile := item_id == "smoke" or item_id == "chair" or item_id == "stink"
	var glow := Color(1.0, 0.38, 0.28) if hostile else color
	var pulse := 0.5 + 0.5 * sin(bob * 2.0)
	draw_circle(off + Vector2(0, 10), 8.0, Color(0, 0, 0, 0.28))
	draw_arc(off, 13.5 + pulse * 1.5, 0.0, TAU, 24, Color(0, 0, 0, 0.4), 3.2, true)
	draw_arc(off, 13.5 + pulse * 1.5, 0.0, TAU, 24, Color(glow, 0.4 + 0.3 * pulse), 1.6, true)
	if icon_tex != null:
		var s := 24.0 / maxf(icon_tex.get_width(), icon_tex.get_height())
		var sz := icon_tex.get_size() * s
		draw_texture_rect(icon_tex, Rect2(off - sz * 0.5, sz), false)
	else:
		draw_circle(off, 10.0, color)
		draw_circle(off, 10.0, Color(1, 1, 1, 0.55), false, 1.5)
		draw_circle(off, 4.0, Color(1, 1, 1, 0.8))
	# 顶部小星光
	var tw := 0.5 + 0.5 * sin(bob * 3.0 + 1.2)
	var sp := off + Vector2(7, -15)
	var l := 2.5 + 1.5 * tw
	draw_line(sp + Vector2(-l, 0), sp + Vector2(l, 0), Color(1, 1, 0.85, 0.35 + 0.45 * tw), 1.3, true)
	draw_line(sp + Vector2(0, -l), sp + Vector2(0, l), Color(1, 1, 0.85, 0.35 + 0.45 * tw), 1.3, true)
