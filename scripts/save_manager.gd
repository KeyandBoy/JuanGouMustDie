extends Node

const SAVE_PATH := "user://save_juangou.json"
const SAVE_BAK_PATH := "user://save_juangou.bak.json"
const SAVE_TMP_PATH := "user://save_juangou.tmp.json"
const SAVE_KEY := "juangou_save"
const SETTINGS_PATH := "user://settings.cfg"
const SAVE_VERSION := 3
var _intro_seen := false

func save_run() -> bool:
	return _write(_collect())

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
		"version": SAVE_VERSION,
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
		"story_flags": GameState.story_flags,
		"play_time": GameState.play_time,
	}

func _migrate(d: Dictionary) -> Dictionary:
	var version := int(d.get("version", 1))
	if version < 2:
		if not (d.get("story_flags") is Dictionary):
			d["story_flags"] = {}
		if not d.has("play_time"):
			d["play_time"] = 0.0
	if version < 3:
		var raw = d.get("inventory", [])
		var slots: Array = []
		if raw is Array:
			for entry in raw:
				if entry is Dictionary:
					var eid := String(entry.get("id", ""))
					if eid != "":
						slots.append({"id": eid, "count": maxi(1, int(entry.get("count", 1)))})
				else:
					var sid := String(entry)
					if sid != "":
						slots.append({"id": sid, "count": 1})
		d["inventory"] = slots
		d["version"] = 3
	return d

func _apply(d: Dictionary) -> bool:
	d = _migrate(d.duplicate(true))
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
	var raw_inv = d.get("inventory", [])
	if raw_inv is Array:
		for entry in raw_inv:
			if entry is Dictionary:
				var iid := String(entry.get("id", ""))
				if GameState.ITEM_DEFS.has(iid):
					GameState.inventory.append({"id": iid, "count": maxi(1, int(entry.get("count", 1)))})
			else:
				var sid := String(entry)
				if GameState.ITEM_DEFS.has(sid):
					GameState.inventory.append({"id": sid, "count": 1})
	GameState.story_flags.clear()
	var raw_flags = d.get("story_flags", {})
	if raw_flags is Dictionary:
		for k in raw_flags:
			GameState.story_flags[String(k)] = raw_flags[k]
	GameState.play_time = maxf(0.0, float(d.get("play_time", 0.0)))
	GameState.tyrant_active = false
	GameState.cutscene_active = false
	GameState.run_state = GameState.RunState.EXPLORING
	GameState.inventory_changed.emit()
	return true

func _write(data: Dictionary) -> bool:
	var text := JSON.stringify(data)
	if OS.has_feature("web"):
		return _web_set(text)
	var file := FileAccess.open(SAVE_TMP_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	if FileAccess.file_exists(SAVE_PATH) and _read_file(SAVE_PATH) is Dictionary:
		DirAccess.copy_absolute(SAVE_PATH, SAVE_BAK_PATH)
	if DirAccess.rename_absolute(SAVE_TMP_PATH, SAVE_PATH) == OK:
		return true
	DirAccess.remove_absolute(SAVE_PATH)
	if DirAccess.rename_absolute(SAVE_TMP_PATH, SAVE_PATH) == OK:
		return true
	var fallback := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if fallback == null:
		return false
	fallback.store_string(text)
	fallback.close()
	return true

func _parse_save_text(text: String):
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	if json.data is Dictionary:
		return json.data
	return null

func _read_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return _parse_save_text(file.get_as_text())

func _read():
	if OS.has_feature("web"):
		var data = _parse_save_text(_web_get())
		if data is Dictionary:
			return data
		return _parse_save_text(_web_get(SAVE_KEY + "_bak"))
	var data = _read_file(SAVE_PATH)
	if data is Dictionary and (data.has("level") or data.has("grade")):
		return data
	var bak = _read_file(SAVE_BAK_PATH)
	if bak is Dictionary and (bak.has("level") or bak.has("grade")):
		return bak
	return null

func _web_set(text: String) -> bool:
	if not OS.has_feature("web"): return false
	JavaScriptBridge.eval("try{(function(){var k='%s';var old=localStorage.getItem(k);if(old!==null)localStorage.setItem(k+'_bak',old);localStorage.setItem(k,'%s');})();}catch(e){}" % [SAVE_KEY, _escape_js(text)])
	return true

func _web_get(key: String = SAVE_KEY) -> String:
	if not OS.has_feature("web"): return ""
	var r = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('%s')||'';}catch(e){return '';}})()" % key)
	return String(r)

func _escape_js(s: String) -> String:
	return s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
