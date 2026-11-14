extends Node

## 难度曲线探针：打印 1F~5F 的敌人构成与感知数值，确认「每层只加一个新威胁」。
## 跑法：godot --headless --path . --quit-after 30000 res://tests/_curve_probe.tscn
## 只读，不改游戏状态；最后打印 CURVE_PROBE: DONE。

const FLOORS := [1, 2, 3, 4, 5]
const ORDER := ["student", "juan", "teacher", "guard"]

func _ready() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	for i in 3:
		await get_tree().process_frame
	if inst.menu_layer != null:
		inst.menu_layer.queue_free()

	for lv in FLOORS:
		GameState.seed_value = 9090 + lv
		inst._start_level(lv)
		for i in 8:
			await get_tree().process_frame
		var tally := {"student": 0, "juan": 0, "teacher": 0, "guard": 0, "other": 0}
		var sample := {}
		for s in get_tree().get_nodes_in_group("students"):
			var r := String(s.get("role"))
			if tally.has(r):
				tally[r] = int(tally[r]) + 1
				if not sample.has(r):
					sample[r] = s
			else:
				tally["other"] = int(tally["other"]) + 1
		var parts: Array[String] = []
		for r in ORDER:
			if int(tally[r]) > 0:
				parts.append("%s×%d" % [r, int(tally[r])])
		if int(tally["other"]) > 0:
			parts.append("monster×%d" % int(tally["other"]))
		print("CURVE %dF goal=%.0f count=%d [%s]" % [
			lv, GameState.study_goal, get_tree().get_nodes_in_group("students").size(),
			", ".join(parts),
		])
		for r in ORDER:
			if not sample.has(r):
				continue
			var s = sample[r]
			print("   %-7s vision=%.0f angle=%.0f hear=%.0f speed=%.0f chase=%.0f catch=%.0f" % [
				r, float(s.get("vision_range")), float(s.get("vision_angle")),
				float(s.get("hear_range")), float(s.get("speed")),
				float(s.get("chase_speed")), float(s.get("catch_radius")),
			])
	print("CURVE_PROBE: DONE")
	get_tree().quit(0)
