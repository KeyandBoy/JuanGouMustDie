extends Node
func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.15, 0.15, 0.2))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	if inst.menu_layer != null and inst.menu_layer.has_meta("lightning_fx"):
		var fx = inst.menu_layer.get_meta("lightning_fx")
		inst._draw_branching_lightning(fx, get_viewport().get_visible_rect().size)
		await get_tree().create_timer(0.08).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tests/shot_menu.png")
	print("MENU_SHOT_SAVED")
	get_tree().quit()
