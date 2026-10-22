extends Node2D

var player: Node2D
var map: Node2D
var kind := "desk"
var efficiency := 1.0
var room_index := -1
var occupied := false
var prompt_text := ""

func _ready() -> void:
	add_to_group("interactables")

func setup_desk(pos: Vector2, eff: float, room: int) -> void:
	kind = "desk"
	efficiency = eff
	room_index = room
	position = pos
	prompt_text = "按 F 学习（效率 %.1f）" % eff

func get_prompt() -> String:
	return prompt_text

func interact(player_node: Node2D) -> void:
	if kind == "desk":
		player_node.set_meta("studying_at", self)
		player_node.set_meta("study_efficiency", efficiency)

func _draw() -> void:
	if kind != "desk":
		return
	draw_rect(Rect2(-19.0, -7.0, 38.0, 18.0), Color(0.0, 0.0, 0.0, 0.12))
	draw_rect(Rect2(-7.0, 1.0, 14.0, 9.0), Color(0.26, 0.47, 0.74))
	draw_rect(Rect2(-7.0, 1.0, 14.0, 9.0), Color(0.15, 0.29, 0.49), false, 1.5)
	draw_rect(Rect2(-5.0, 3.0, 10.0, 4.0), Color(0.42, 0.62, 0.86))
	draw_rect(Rect2(-20.0, -10.0, 40.0, 15.0), Color(0.79, 0.56, 0.31))
	draw_rect(Rect2(-18.0, -8.0, 36.0, 11.0), Color(0.88, 0.65, 0.38))
	draw_rect(Rect2(-20.0, -10.0, 40.0, 15.0), Color(0.43, 0.28, 0.15), false, 2.0)
	draw_rect(Rect2(-14.0, -7.0, 12.0, 8.0), Color(0.97, 0.96, 0.92))
	draw_rect(Rect2(-14.0, -7.0, 12.0, 8.0), Color(0.75, 0.72, 0.66), false, 1.0)
	draw_rect(Rect2(2.0, -7.0, 8.0, 8.0), Color(0.28, 0.60, 0.40))
	draw_rect(Rect2(2.0, -7.0, 8.0, 8.0), Color(0.16, 0.38, 0.25), false, 1.0)
