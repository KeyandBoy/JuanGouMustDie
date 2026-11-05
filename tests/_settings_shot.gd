extends Node

## 手动截图：主菜单齿轮 + 设置面板（不进自动测试）
## 跑法：godot --path . res://tests/_settings_shot.tscn

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SNAP ", path, " ", img.get_size())

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.05, 0.06, 0.07))
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().create_timer(1.2).timeout
	await _snap("res://tests/_shot_menu_gear.png")

	SettingsUi.open(inst)
	await get_tree().create_timer(0.5).timeout
	await _snap("res://tests/_shot_settings_audio.png")

	inst.queue_free()
	get_tree().quit()
