extends Node
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.15, 0.15, 0.2))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_menu.png")
	print("MENU_SHOT_SAVED")
	get_tree().quit()
