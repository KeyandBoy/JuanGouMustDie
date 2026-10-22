extends Area2D

signal picked(item_id: String)
signal full(item_id: String)

var item_id := "coffee"
var color := Color.WHITE
var bob := 0.0
var _used := false

func _ready() -> void:
	add_to_group("pickups")
	monitoring = true
	monitorable = true
	collision_layer = 0
	collision_mask = 1
	z_index = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)

func setup(id: String, p_color: Color) -> void:
	item_id = id
	color = p_color

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
	draw_circle(off + Vector2(0, 2), 10.0, Color(0, 0, 0, 0.18))
	draw_circle(off, 10.0, color)
	draw_circle(off, 10.0, Color(1, 1, 1, 0.55), false, 1.5)
	draw_circle(off, 4.0, Color(1, 1, 1, 0.8))
	draw_line(off + Vector2(-6, -6), off + Vector2(6, -6), Color(1, 1, 1, 0.55), 1.5)
