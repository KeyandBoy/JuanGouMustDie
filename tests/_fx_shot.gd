extends Node

## 手动截图探针：验证 S1 反馈层的观感（不进四套自动测试）。
## 跑法：godot --path . res://tests/_fx_shot.tscn

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
	await get_tree().process_frame
	await get_tree().process_frame
	if inst.has_method("_start_level"):
		inst._start_level(1)
	await get_tree().create_timer(0.6).timeout

	# 答对：绿闪 + 飘字 + 连对暴击字
	GameState.correct_streak = 5
	inst._on_answered(true)
	await get_tree().create_timer(0.16).timeout
	await _snap("res://tests/_fx_shot_correct.png")

	await get_tree().create_timer(0.9).timeout

	# 答错：红闪 + 震屏 + 负向飘字
	GameState.correct_streak = 0
	inst._on_answered(false)
	await get_tree().create_timer(0.10).timeout
	await _snap("res://tests/_fx_shot_wrong.png")

	await get_tree().create_timer(1.0).timeout

	# 低理智红晕
	GameState.emptiness = 8.0
	GameState.emptiness_changed.emit(8.0)
	await get_tree().create_timer(0.8).timeout
	await _snap("res://tests/_fx_shot_lowsanity.png")

	inst.queue_free()
	get_tree().quit()
