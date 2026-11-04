extends Node

## 背景音乐曲库：唯一真相源是 res://assets/music/catalog.json。
## 这里只保留一份「兜底表」——曲库文件缺失/解析失败时仍能出声，
## 但正常情况下一律以 JSON 为准（改歌只改 JSON，再跑 tools/music_catalog.py 导出文档）。
const CATALOG_PATH := "res://assets/music/catalog.json"
const TRACK_PATHS := {
	"happy": "res://assets/music/happy_loop.mp3",
	"tension": "res://assets/music/chase_pursuit.mp3",
	"chase": "res://assets/music/chase_electro.ogg",
	"absurd": "res://assets/music/goofy_attitude.mp3",
	"tyrant": "res://assets/music/tyrant_dread.wav",
	"tyrant_l5": "res://assets/music/tyrant_dread_l5.wav",
}
const FADE := 0.8
const BASE_MUSIC_DB := -16.0
const CHECK_INTERVAL := 0.25

var current_key := ""
var master_volume := 100.0
var music_volume := 100.0
var muted := false

var _player: AudioStreamPlayer
var _timer := 0.0
var _tween: Tween
var _cache: Dictionary = {}
var _tracks: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_catalog()
	_player = AudioStreamPlayer.new()
	add_child(_player)
	master_volume = float(SaveManager.get_setting("master", 100.0))
	music_volume = float(SaveManager.get_setting("music", 100.0))
	muted = bool(SaveManager.get_setting("muted", false))
	apply_volumes()

## 读曲库。解析失败就静默回退到 TRACK_PATHS，不影响游戏出声。
func _load_catalog() -> void:
	_tracks.clear()
	if not FileAccess.file_exists(CATALOG_PATH):
		return
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("music catalog 解析失败，回退到内置表")
		return
	var list = data.get("tracks", [])
	if list is Array:
		_tracks = list

## 把 AudioManager 的槽位名解析成实际文件路径。
## 规则：status=active、声明了该 slot、level_scope 覆盖当前楼层；
## 多条命中时按曲库顺序取第一条（想换优先级就调 JSON 里的顺序）。
func catalog_slot_path(slot: String) -> String:
	var level: int = int(GameState.level)
	for entry in _tracks:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		if String(d.get("status", "")) != "active":
			continue
		var slots = d.get("slots", [])
		if not (slots is Array) or not slots.has(slot):
			continue
		var scope = d.get("level_scope", ["all"])
		if scope is Array and not scope.has("all") and not scope.has(level):
			continue
		var path := String(d.get("file", ""))
		if not path.is_empty():
			return path
	return String(TRACK_PATHS.get(slot, ""))

func _music_db() -> float:
	if music_volume <= 0.5:
		return -80.0
	return clampf(BASE_MUSIC_DB + (music_volume - 100.0) * 0.2, -60.0, 6.0)

func apply_volumes() -> void:
	var db := -80.0
	if master_volume > 0.5:
		db = linear_to_db(master_volume / 100.0)
	AudioServer.set_bus_volume_db(0, db)
	AudioServer.set_bus_mute(0, muted or master_volume <= 0.5)
	if _player != null:
		_player.volume_db = _music_db()

func set_muted(v: bool) -> void:
	muted = v
	SaveManager.set_setting("muted", muted)
	apply_volumes()

func set_master_volume(v: float) -> void:
	master_volume = clampf(v, 0.0, 100.0)
	SaveManager.set_setting("master", master_volume)
	apply_volumes()

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 100.0)
	SaveManager.set_setting("music", music_volume)
	apply_volumes()

func _process(delta: float) -> void:
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_refresh()

func _refresh() -> void:
	var key := _desired_key()
	if key != current_key:
		_play(key)

func _desired_key() -> String:
	if GameState.run_state == GameState.RunState.GAMEOVER:
		return ""
	if GameState.run_state == GameState.RunState.MENU:
		return "happy"
	if GameState.cutscene_active:
		return ""
	if GameState.tyrant_active:
		return "tyrant_l5" if GameState.level >= 5 else "tyrant"
	if GameState.run_state == GameState.RunState.QUIZ:
		return "absurd"
	if GameState.run_state == GameState.RunState.CLEARED:
		return "happy"
	var w: int = GameState.warnings
	if w >= 2 or _any_chasing():
		return "chase"
	if w == 1:
		return "tension"
	return "happy"

func _any_chasing() -> bool:
	if GameState.run_state != GameState.RunState.EXPLORING:
		return false
	for s in get_tree().get_nodes_in_group("students"):
		if String(s.get("state")) == "chase":
			return true
	return false

func _play(key: String) -> void:
	current_key = key
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if key == "":
		if _player.playing:
			_tween = create_tween()
			_tween.tween_property(_player, "volume_db", -40.0, FADE)
			_tween.tween_callback(_player.stop)
		return
	var stream: AudioStream = _stream_for(key)
	if stream == null:
		return
	if _player.stream == stream and _player.playing:
		return
	if _player.playing:
		_tween = create_tween()
		_tween.tween_property(_player, "volume_db", -40.0, FADE * 0.5)
		_tween.tween_callback(_start.bind(stream))
		_tween.tween_property(_player, "volume_db", _music_db(), FADE * 0.5)
	else:
		_start(stream)

func _start(stream: AudioStream) -> void:
	_player.stop()
	_player.stream = stream
	if "loop" in stream:
		stream.set("loop", true)
	_player.volume_db = -40.0
	_player.play()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", _music_db(), FADE)

func is_playing() -> bool:
	return _player != null and _player.playing

func _stream_for(key: String) -> AudioStream:
	var path: String = catalog_slot_path(key)
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as AudioStream
	var stream: AudioStream = load(path)
	if stream != null:
		_cache[path] = stream
	return stream

func kick() -> void:
	if not OS.has_feature("web"):
		return
	if current_key.is_empty() or not _player.stream:
		return
	_player.stop()
	_player.volume_db = _music_db()
	_player.play()
