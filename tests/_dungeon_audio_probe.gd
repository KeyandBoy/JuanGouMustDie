extends Node

## 第二层（地牢 6~10F）音频探针。
## 规格：.opencode/plan/第二层世界_音频规格.md
## 跑法：& $G --headless --path . --quit-after 25000 res://tests/_dungeon_audio_probe.tscn

var failures: Array[String] = []
var notes: Array[String] = []


func _check(ok: bool, msg: String) -> void:
	if not ok:
		failures.append(msg)


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://scenes/main.tscn")
	var inst = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	inst._start_level(1)
	await get_tree().process_frame
	await get_tree().process_frame

	var am = get_node("/root/AudioManager")
	var old_world: int = GameState.world
	var old_level: int = GameState.level
	var old_state: int = GameState.run_state
	var old_contam: float = GameState.contamination
	var old_tyrant: bool = GameState.tyrant_active
	var old_safe: bool = GameState.in_safe_room

	# ---------- 1. 曲库条目 ----------
	## 已接入的六首：必须 active；其中 calm/alert/chase/quiz 是同一 80 BPM 系列。
	## clear / gameover 仍是 missing（短句素材后面补）。
	var active_ids := ["dungeon_calm", "dungeon_alert", "dungeon_chase", "dungeon_quiz", "pyramid", "dungeon_safe"]
	var bpm80_ids := ["dungeon_calm", "dungeon_alert", "dungeon_chase", "dungeon_quiz"]
	var want := ["dungeon_calm", "dungeon_alert", "dungeon_chase", "dungeon_quiz",
		"pyramid", "dungeon_safe", "dungeon_clear", "dungeon_gameover"]
	var tracks: Array = am.get("_tracks")
	var by_id := {}
	for t in tracks:
		if t is Dictionary:
			by_id[String(t.get("id", ""))] = t
	for id in want:
		_check(by_id.has(id), "catalog: missing entry %s" % id)
		if by_id.has(id):
			var d: Dictionary = by_id[id]
			var scope = d.get("level_scope", [])
			var scope_ok := false
			if scope is Array:
				for s in scope:
					if int(s) == 6:
						scope_ok = true
				_check(scope_ok and scope.size() == 5, "catalog: %s level_scope 6~10 (%s)" % [id, scope])
			else:
				_check(false, "catalog: %s level_scope 不是数组" % id)
			var status := String(d.get("status", ""))
			if active_ids.has(id):
				_check(status == "active", "catalog: %s 已接入应为 active (%s)" % [id, status])
				_check(not String(d.get("file", "")).is_empty(), "catalog: %s 有文件" % id)
				_check(ResourceLoader.exists(String(d.get("file", ""))), "catalog: %s 文件存在" % id)
				_check(String(d.get("file", "")).begins_with("res://assets/music/"),
					"catalog: %s 放在 assets/music" % id)
				if bpm80_ids.has(id):
					_check(int(d.get("bpm", 0)) == 80, "catalog: %s 标了 80 BPM (%s)" % [id, d.get("bpm")])
				_check(float(d.get("duration_sec", 0.0)) > 5.0, "catalog: %s 标了时长" % id)
				_check(d.get("license") is Dictionary, "catalog: %s 有 license 块" % id)
			else:
				_check(status == "missing", "catalog: %s 先标 missing (%s)" % [id, status])
			var inten = d.get("intensity")
			_check((inten is int or inten is float) and float(inten) >= 1.0 and float(inten) <= 5.0,
				"catalog: %s intensity 1~5 (%s)" % [id, inten])
	# 同 BPM 同长度（规格 3：chase 要能和 calm 叠）
	var calm: Dictionary = by_id.get("dungeon_calm", {})
	var chase: Dictionary = by_id.get("dungeon_chase", {})
	_check(int(calm.get("bpm", 0)) == int(chase.get("bpm", -1)), "catalog: calm/chase 同 BPM")
	var d_calm := float(calm.get("duration_sec", 0.0))
	var d_chase := float(chase.get("duration_sec", 0.0))
	_check(absf(d_calm - d_chase) < 0.05 and d_calm > 10.0,
		"catalog: calm/chase 同长度 (%s vs %s)" % [d_calm, d_chase])

	# ---------- 2. 总线与效果 ----------
	_check(AudioServer.get_bus_index(am.BUS_DUNGEON_REVERB) >= 0, "bus: DungeonReverb 存在")
	var music_idx := AudioServer.get_bus_index(am.BUS_MUSIC)
	var lp_idx := int(am.get("_lowpass_idx"))
	_check(lp_idx >= 0, "bus: Music 上有低通")
	_check(AudioServer.get_bus_effect(music_idx, lp_idx) is AudioEffectLowPassFilter,
		"bus: 低通类型正确")
	var rv_idx := int(am.get("_reverb_bus"))
	_check(rv_idx >= 0, "bus: 混响辅助总线可用")
	_check(AudioServer.get_bus_effect(rv_idx, 0) is AudioEffectReverb, "bus: 混响效果存在")

	# ---------- 3. 世界路由 ----------
	GameState.world = 1
	am._apply_world_routing()
	_check(not AudioServer.is_bus_effect_enabled(music_idx, lp_idx),
		"route: 第一层低通关")
	_check(String(AudioServer.get_bus_send(music_idx)) != String(am.BUS_DUNGEON_REVERB),
		"route: 第一层 Music 不送混响")

	GameState.world = 2
	am._apply_world_routing()
	_check(AudioServer.is_bus_effect_enabled(music_idx, lp_idx),
		"route: 第二层低通开")
	_check(String(AudioServer.get_bus_send(music_idx)) == String(am.BUS_DUNGEON_REVERB),
		"route: 第二层 Music 送混响")

	# ---------- 4. 污染混音 ----------
	var cutoff_low := 0.0
	var cutoff_high := 0.0
	GameState.contamination = 0.0
	for i in 30:
		am._tick_contamination(0.05)
	cutoff_high = (AudioServer.get_bus_effect(music_idx, lp_idx) as AudioEffectLowPassFilter).cutoff_hz
	GameState.contamination = 100.0
	for i in 30:
		am._tick_contamination(0.05)
	cutoff_low = (AudioServer.get_bus_effect(music_idx, lp_idx) as AudioEffectLowPassFilter).cutoff_hz
	_check(cutoff_high > cutoff_low + 5000.0,
		"contam: 污染 0→100 低通明显下降 (%.0f → %.0f)" % [cutoff_high, cutoff_low])
	_check(absf(float(am.contamination_mix_ratio()) - 1.0) < 0.02, "contam: mix ratio 收敛到 1")

	# ---------- 5. 状态机 ----------
	GameState.world = 2
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.tyrant_active = false
	GameState.in_safe_room = false
	GameState.contamination = 0.0
	_check(am._desired_key() == "dungeon_calm", "key: 平时 = dungeon_calm (%s)" % am._desired_key())
	GameState.contamination = 60.0
	_check(am._desired_key() == "dungeon_alert", "key: 污染≥50 = dungeon_alert (%s)" % am._desired_key())
	GameState.in_safe_room = true
	_check(am._desired_key() == "dungeon_safe", "key: 安全屋 = dungeon_safe (%s)" % am._desired_key())
	GameState.in_safe_room = false
	GameState.run_state = GameState.RunState.QUIZ
	_check(am._desired_key() == "dungeon_quiz", "key: 答题 = dungeon_quiz (%s)" % am._desired_key())
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.tyrant_active = true
	_check(am._desired_key() == "pyramid", "key: 三角头/暴君 = pyramid (%s)" % am._desired_key())
	GameState.tyrant_active = false
	GameState.run_state = GameState.RunState.CLEARED
	_check(am._desired_key() == "dungeon_clear", "key: 通关 = dungeon_clear (%s)" % am._desired_key())
	GameState.run_state = GameState.RunState.GAMEOVER
	_check(am._desired_key() == "dungeon_gameover", "key: 失败 = dungeon_gameover (%s)" % am._desired_key())
	GameState.run_state = GameState.RunState.EXPLORING

	# 第一层不受影响
	GameState.world = 1
	GameState.contamination = 100.0
	GameState.run_state = GameState.RunState.EXPLORING
	_check(am._desired_key() == "happy", "key: 第一层仍是 happy (%s)" % am._desired_key())

	# ---------- 6. 缺素材回退 ----------
	# 已接入的槽位不再回退；仍缺素材的 clear / gameover 继续借第一层短句。
	# 曲库条目带 level_scope 6~10，不设楼层 catalog_slot_path 会误判成缺素材。
	GameState.world = 2
	GameState.level = 6
	_check(not am.catalog_slot_path("dungeon_calm").is_empty(), "fallback: dungeon_calm 已有文件")
	_check(am._resolve_slot("dungeon_calm") == "dungeon_calm", "fallback: dungeon_calm 不再回退")
	_check(am._resolve_slot("pyramid") == "pyramid", "fallback: pyramid 不再回退")
	_check(am.catalog_slot_path("dungeon_clear").is_empty(), "fallback: dungeon_clear 仍缺")
	_check(am._resolve_slot("dungeon_clear") == "cleared", "fallback: dungeon_clear → cleared")
	_check(am._resolve_slot("dungeon_gameover") == "gameover", "fallback: dungeon_gameover → gameover")

	# ---------- 7. duck ----------
	var base_db := AudioServer.get_bus_volume_db(music_idx)
	am.duck_music(-8.0, 0.05)
	await get_tree().process_frame
	var ducked := AudioServer.get_bus_volume_db(music_idx)
	_check(ducked < base_db - 5.0, "duck: 立即压低 (%.1f → %.1f)" % [base_db, ducked])
	await get_tree().create_timer(0.8).timeout
	var restored := AudioServer.get_bus_volume_db(music_idx)
	_check(absf(restored - base_db) < 0.6, "duck: 0.8s 后恢复 (%.1f)" % restored)

	# ---------- 8. 幻听 ----------
	GameState.world = 2
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.in_safe_room = false
	GameState.contamination = 30.0
	am.set("_halluc_timer", 0.0)
	var before := int((am.get("_halluc_active") as Array).size())
	for i in 5:
		am._tick_hallucination(0.1)
	_check((am.get("_halluc_active") as Array).size() == before, "halluc: 污染<50 不触发")

	GameState.contamination = 80.0
	var played: bool = am._play_hallucination()
	_check(played, "halluc: 污染≥50 能出声")
	var count1 := int((am.get("_halluc_active") as Array).size())
	am._play_hallucination()
	am._play_hallucination()
	var count3 := int((am.get("_halluc_active") as Array).size())
	_check(count3 <= 2, "halluc: 同时最多 2 个 (%d)" % count3)

	GameState.in_safe_room = true
	var safe_before := int((am.get("_halluc_active") as Array).size())
	am.set("_halluc_timer", 0.0)
	am._tick_hallucination(0.1)
	_check((am.get("_halluc_active") as Array).size() == safe_before, "halluc: 安全屋不触发")
	GameState.in_safe_room = false

	# ---------- 9. stone 脚步 ----------
	_check(am.STEP_MATERIALS.has("stone"), "step: stone 已登记")
	var stone_ok: bool = am.play_footstep("stone", Vector2.ZERO)
	notes.append("stone 采样%s" % ("已就位" if stone_ok else "尚未就位（静音兜底，不崩）"))

	# ---------- 10. 混响预设 ----------
	am.set_reverb_preset("corridor", true)
	var corridor_room: float = (am.get("_reverb_effect") as AudioEffectReverb).room_size
	am.set_reverb_preset("safe", true)
	var safe_room: float = (am.get("_reverb_effect") as AudioEffectReverb).room_size
	_check(corridor_room > safe_room, "reverb: corridor 比 safe 更长")
	_check(am.current_zone_preset() == "safe", "reverb: 当前预设可读")
	am.set_reverb_preset("room", true)

	# ---------- 11. P0 素材就位 ----------
	var assets := [
		"res://assets/music/dungeon_calm.ogg",
		"res://assets/music/dungeon_chase.ogg",
		"res://assets/music/dungeon_alert.ogg",
		"res://assets/music/dungeon_quiz.ogg",
		"res://assets/music/dungeon_safe.ogg",
		"res://assets/music/pyramid.ogg",
		"res://assets/sfx/dungeon/tinnitus_loop.ogg",
		"res://assets/sfx/dungeon/whisper_loop.ogg",
		"res://assets/sfx/dungeon/whisper_hit.ogg",
		"res://assets/sfx/dungeon/door_far.ogg",
		"res://assets/sfx/pyramid/blade_drag_loop.ogg",
	]
	for p in assets:
		_check(ResourceLoader.exists(p), "asset: %s 已就位" % p)
		_check(am._exists(p), "asset: %s 可被 AudioManager 看见" % p)
	_check(am.BLADE_DRAG_PATH == "res://assets/sfx/pyramid/blade_drag_loop.ogg", "asset: 拖刀路径常量")
	_check(am.play_blade_drag(Vector2.ZERO, -30.0), "asset: 拖刀循环能播")

	# ---------- 12. 被抓 4 连 ----------
	var kinds := ["face_slam", "dragged", "vhs_tear", "freeze"]
	for k in kinds:
		var path := String(am.CAUGHT_PATHS.get(k, ""))
		_check(ResourceLoader.exists(path), "caught: %s 文件存在 (%s)" % [k, path])
		_check(am.play_caught(k) or am.play_caught(k),
			"caught: %s 能播（同名限流 3，重试一次）" % k)
		await get_tree().process_frame
	# 每种时长 0.7~0.9s（规格 8）；素材缺失也不该崩
	for k in kinds:
		var stream: AudioStream = load(String(am.CAUGHT_PATHS.get(k, "")))
		if stream != null:
			var len_s: float = stream.get_length()
			_check(len_s >= 0.6 and len_s <= 1.0, "caught: %s 时长 %.2fs 落在 0.6~1.0" % [k, len_s])
	# 来源推断：学生=脸部扑屏，暴君=被拖走，杂项=定格帧
	var dummy := Node2D.new()
	dummy.name = "FakePyramid"
	add_child(dummy)
	dummy.add_to_group("tyrants")
	_check(am.caught_kind_for(dummy) == "vhs_tear", "caught: 三角头 → vhs_tear (%s)" % am.caught_kind_for(dummy))
	dummy.name = "Tyrant"
	_check(am.caught_kind_for(dummy) == "dragged", "caught: 暴君 → dragged (%s)" % am.caught_kind_for(dummy))
	dummy.remove_from_group("tyrants")
	_check(am.caught_kind_for(dummy) == "freeze", "caught: 其它 → freeze (%s)" % am.caught_kind_for(dummy))
	dummy.queue_free()
	_check(am.caught_kind_for(null) == "freeze", "caught: 空来源 → freeze")

	# 还原
	GameState.world = old_world
	GameState.level = old_level
	GameState.run_state = old_state
	GameState.contamination = old_contam
	GameState.tyrant_active = old_tyrant
	GameState.in_safe_room = old_safe

	for n in notes:
		print("NOTE: ", n)
	if failures.is_empty():
		print("DUNGEON_AUDIO_PROBE: ALL PASSED")
		get_tree().quit(0)
	else:
		for f in failures:
			print("FAIL: ", f)
		print("DUNGEON_AUDIO_PROBE: FAILED ", failures.size())
		get_tree().quit(1)
