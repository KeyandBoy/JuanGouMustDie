extends Node

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()
	GameState.seed_value = 4242
	GameState.run_state = GameState.RunState.EXPLORING
	inst._setup_level()

	var ok_plan: bool = inst.map.is_connected_plan()
	var bad := 0
	var rooms_seen := {}
	for f in 900:
		await get_tree().physics_frame
		for s in get_tree().get_nodes_in_group("students"):
			if not inst.map.is_walkable(s.position):
				bad += 1
				if bad <= 6:
					print("OUTSIDE frame=", f, " pos=", s.position, " state=", s.state)
			var ri: int = inst.map.room_index_at(s.position)
			if ri >= 0:
				rooms_seen[ri] = true
	print("PLAN_CONNECTED=", ok_plan)
	print("BAD_FRAMES=", bad, " ROOMS_VISITED=", rooms_seen.keys())
	for s in get_tree().get_nodes_in_group("students"):
		print("  final pos=", s.position.round(), " state=", s.state)
	get_tree().quit(0 if ok_plan and bad == 0 and rooms_seen.size() > 0 else 1)
