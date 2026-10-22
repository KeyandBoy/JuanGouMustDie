extends Node

const SAVE_PATH := "user://save_juangou.json"
const SAVE_KEY := "juangou_save"
const SETTINGS_PATH := "user://settings.cfg"
var _intro_seen := false

func save_run() -> bool:
	var data := {
		"grade": GameState.grade_id,
		"subjects": GameState.subjects,
		"level": GameState.level,
		"study": GameState.study,
		"emptiness": GameState.emptiness,
		"warnings": GameState.warnings,
		"stars": GameState.stars,
		"level_stars": GameState.level_stars,
		"max_cleared_level": GameState.max_cleared_level,
		"upgrades": GameState.upgrades,
		"items": GameState.items,
		"abilities": GameState.abilities,
		"questions_answered": GameState.questions_answered,
		"quiz_correct": GameState.quiz_correct,
		"tyrant_intro_seen": GameState.tyrant_intro_seen,
		"inventory": GameState.inventory,
		"game_cleared": GameState.game_cleared,
		"explored_rooms": GameState.explored_rooms,
		"intel_found": GameState.intel_found,
	}
	return _write(data)

func load_run() -> bool:
	var data = _read()
	if data == null or not (data is Dictionary):
		return false
	return _apply(data)

func has_save() -> bool:
	return _read() != null

func has_seen_intro() -> bool:
	if OS.has_feature("web"):
		return _intro_seen
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return false
	return bool(cfg.get_value("story", "intro_seen", false))

func mark_intro_seen() -> void:
	_intro_seen = true
	if OS.has_feature("web"):
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("story", "intro_seen", true)
	cfg.save(SETTINGS_PATH)

var _web_settings: Dictionary = {}

func get_setting(key: String, def: Variant) -> Variant:
	if OS.has_feature("web"):
		return _web_settings.get(key, def)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return def
	return cfg.get_value("audio", key, def)

func set_setting(key: String, value: Variant) -> void:
	if OS.has_feature("web"):
		_web_settings[key] = value
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", key, value)
	cfg.save(SETTINGS_PATH)

func save_json_string() -> String:
	var data := _collect()
	return JSON.stringify(data)

func load_json_string(text: String) -> bool:
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		return false
	return _apply(data)

func _collect() -> Dictionary:
	return {
		"grade": GameState.grade_id,
		"subjects": GameState.subjects,
		"level": GameState.level,
		"study": GameState.study,
		"emptiness": GameState.emptiness,
		"warnings": GameState.warnings,
		"stars": GameState.stars,
		"level_stars": GameState.level_stars,
		"max_cleared_level": GameState.max_cleared_level,
		"upgrades": GameState.upgrades,
		"items": GameState.items,
		"abilities": GameState.abilities,
		"questions_answered": GameState.questions_answered,
		"quiz_correct": GameState.quiz_correct,
		"tyrant_intro_seen": GameState.tyrant_intro_seen,
		"inventory": GameState.inventory,
		"game_cleared": GameState.game_cleared,
		"explored_rooms": GameState.explored_rooms,
		"intel_found": GameState.intel_found,
	}

func _apply(d: Dictionary) -> bool:
	GameState.grade_id = d.get("grade", "junior")
	var typed: Array[String] = []
	for s in d.get("subjects", ["math"]): typed.append(String(s))
	GameState.subjects = typed
	GameState.set_level(int(d.get("level", 1)))
	GameState.study = float(d.get("study", 0.0))
	GameState.emptiness = float(d.get("emptiness", 50.0))
	GameState.warnings = int(d.get("warnings", 0))
	GameState.stars = int(d.get("stars", 0))
	var star_map := {}
	var raw_stars = d.get("level_stars", {})
	if raw_stars is Dictionary:
		for k in raw_stars:
			star_map[int(String(k))] = int(raw_stars[k])
	GameState.level_stars = star_map
	if d.has("max_cleared_level"):
		GameState.max_cleared_level = clampi(int(d.get("max_cleared_level", 1)), 1, GameState.MAX_LEVEL)
	else:
		var derived := 1
		for k in star_map:
			if int(star_map[k]) > 0:
				derived = maxi(derived, mini(int(k) + 1, GameState.MAX_LEVEL))
		GameState.max_cleared_level = derived
	var up_map := {}
	var raw_up = d.get("upgrades", {})
	if raw_up is Dictionary:
		for k in raw_up:
			var key := String(k)
			if GameState.UPGRADE_DEFS.has(key):
				up_map[key] = int(raw_up[k])
	GameState.upgrades = up_map
	GameState._recompute_derived()
	GameState.items = d.get("items", {})
	GameState.abilities = d.get("abilities", {})
	GameState.questions_answered = int(d.get("questions_answered", 0))
	GameState.quiz_correct = int(d.get("quiz_correct", 0))
	GameState.tyrant_intro_seen = bool(d.get("tyrant_intro_seen", false))
	GameState.game_cleared = bool(d.get("game_cleared", false))
	GameState.explored_rooms = int(d.get("explored_rooms", 0))
	GameState.intel_found = int(d.get("intel_found", 0))
	GameState.inventory.clear()
	for item in d.get("inventory", []):
		if GameState.ITEM_DEFS.has(String(item)):
			GameState.inventory.append(String(item))
	GameState.tyrant_active = false
	GameState.cutscene_active = false
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.inventory_changed.emit()
	return true

func _write(data: Dictionary) -> bool:
	var text := JSON.stringify(data)
	if OS.has_feature("web"):
		return _web_set(text)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	return true

func _read():
	if OS.has_feature("web"):
		var text := _web_get()
		if text.is_empty(): return null
		return JSON.parse_string(text)
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return null
	return JSON.parse_string(file.get_as_text())

func _web_set(text: String) -> bool:
	if not OS.has_feature("web"): return false
	JavaScriptBridge.eval("try{localStorage.setItem('%s', '%s');}catch(e){}" % [SAVE_KEY, _escape_js(text)])
	return true

func _web_get() -> String:
	if not OS.has_feature("web"): return ""
	var r = JavaScriptBridge.eval("try{return localStorage.getItem('%s')||'';}catch(e){return '';}" % SAVE_KEY)
	return String(r)

func _escape_js(s: String) -> String:
	return s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
