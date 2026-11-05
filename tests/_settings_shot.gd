extends Node

## 手动截图：主菜单右下角齿轮 + 设置面板 + 游戏内 HUD 齿轮（不进自动测试）
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

	# 正常关闭（走 close() 才会恢复暂停状态），再关掉主菜单
	for m in inst.modal_stack.duplicate():
		for c in m.get_children():
			if c is SettingsUi:
				c.close()
	await get_tree().process_frame
	if inst.menu_layer != null and is_instance_valid(inst.menu_layer):
		inst._pop_modal(inst.menu_layer)
	await get_tree().process_frame
	inst._start_level(1)
	await get_tree().create_timer(1.0).timeout
	await _snap("res://tests/_shot_hud_gear.png")

	inst.queue_free()
	get_tree().quit()
