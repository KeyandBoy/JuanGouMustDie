extends Node

## B12 停电视觉样张：打开第 4 关的停电状态，把画面存到 user://blackout_shot.png。
## 运行（不要加 --headless）：
##   & $G --path . res://tests/_b_shot.tscn

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	inst._start_level(4)
	await get_tree().process_frame
	# 站到走廊中央，方便看手电切开暗雾
	if inst.map != null:
		inst.player.position = inst.map.corridor_rect.get_center()
	await get_tree().create_timer(0.4).timeout
	GameState.story_flags["blackout"] = true
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("user://blackout_shot.png")
		print("B_SHOT: saved user://blackout_shot.png")
	else:
		print("B_SHOT: no image")
	get_tree().quit()
