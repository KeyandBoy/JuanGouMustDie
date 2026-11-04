extends Node

## 音频总管。
## · BGM：曲库 res://assets/music/catalog.json 是唯一真相源（改歌只改 JSON）。
## · 播放：双轨交叉淡入（D1），避免切歌时出现音量谷。
## · 总线：Master / Music / SFX / UI / Ambience（D4），音量统一走 AudioServer。
## · 音效：固定池 + 同名限流（D2），不再每次 new 节点。
## 曲库文件缺失 / 解析失败时回退到内置 TRACK_PATHS，不影响出声。

const CATALOG_PATH := "res://assets/music/catalog.json"
const TRACK_PATHS := {
	"happy": "res://assets/music/happy_loop.mp3",
	"tension": "res://assets/music/chase_pursuit.mp3",
	"chase": "res://assets/music/chase_electro.ogg",
	"absurd": "res://assets/music/goofy_attitude.mp3",
	"tyrant": "res://assets/music/tyrant_dread.wav",
	"tyrant_l5": "res://assets/music/tyrant_dread_l5.wav",
}

## 总线名（对应根目录 default_bus_layout.tres）
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"
const BUS_AMBIENCE := "Ambience"

## 交叉淡入时长：循环铺底用 1.5s；一次性短句（胜利/失败）用 0.25s，
## 否则 11 秒的胜利曲会被淡入吃掉一大截。
const BGM_FADE := 1.5
const STING_FADE := 0.25
const SILENCE_DB := -80.0
const BASE_MUSIC_DB := -16.0
const CHECK_INTERVAL := 0.25

## 音效池（D2）：12 个普通播放器 + 8 个 2D 播放器，同名最多同时 3 个。
const SFX_POOL_SIZE := 12
const SFX_2D_POOL_SIZE := 8
const SFX_MAX_SAME := 3

var current_key := ""
var master_volume := 100.0
var music_volume := 100.0
var sfx_volume := 100.0
var muted := false

var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _timer := 0.0
var _tween: Tween
var _cache: Dictionary = {}
var _tracks: Array = []

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx2d_players: Array[AudioStreamPlayer2D] = []
var _sfx_cursor := 0
var _sfx2d_cursor := 0
var _sfx_counts: Dictionary = {}
var _sfx_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_catalog()
	_build_music_players()
	_build_sfx_pool()
	master_volume = float(SaveManager.get_setting("master", 100.0))
	music_volume = float(SaveManager.get_setting("music", 100.0))
	sfx_volume = float(SaveManager.get_setting("sfx", 100.0))
	muted = bool(SaveManager.get_setting("muted", false))
	apply_volumes()

func _build_music_players() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_MUSIC
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.volume_db = SILENCE_DB
		add_child(p)
		_players.append(p)

func _build_sfx_pool() -> void:
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_SFX
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.volume_db = 0.0
		add_child(p)
		p.finished.connect(_on_sfx_finished.bind(p))
		_sfx_players.append(p)
	for i in SFX_2D_POOL_SIZE:
		var q := AudioStreamPlayer2D.new()
		q.bus = BUS_SFX
		q.process_mode = Node.PROCESS_MODE_ALWAYS
		q.max_distance = 900.0
		add_child(q)
		q.finished.connect(_on_sfx_finished.bind(q))
		_sfx2d_players.append(q)

# ---------------------------------------------------------------- 曲库

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

## 把槽位名解析成实际文件路径。
## 规则：status=active、声明了该 slot、level_scope 覆盖当前楼层；
## 多条命中时按曲库顺序取第一条（想换优先级就调 JSON 里的顺序）。
func catalog_slot_path(slot: String) -> String:
	var d := _entry_for_slot(slot)
	if not d.is_empty():
		return String(d.get("file", ""))
	return String(TRACK_PATHS.get(slot, ""))

## 该槽位是否循环播放（曲库里 loop 字段，缺省 true）。
func catalog_slot_loop(slot: String) -> bool:
	var d := _entry_for_slot(slot)
	if d.is_empty():
		return true
	return bool(d.get("loop", true))

func _entry_for_slot(slot: String) -> Dictionary:
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
		if String(d.get("file", "")).is_empty():
			continue
		return d
	return {}

# ---------------------------------------------------------------- 音量

func _bus_db(percent: float, trim_db := 0.0) -> float:
	if percent <= 0.5:
		return SILENCE_DB
	return clampf(linear_to_db(percent / 100.0) + trim_db, SILENCE_DB, 6.0)

func _music_bus_db() -> float:
	if music_volume <= 0.5:
		return SILENCE_DB
	# 沿用旧曲线听感（100% 时 -16dB），避免老存档一进来突然变响
	return clampf(BASE_MUSIC_DB + (music_volume - 100.0) * 0.2, SILENCE_DB, 6.0)

func _set_bus_db(bus_name: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

func apply_volumes() -> void:
	var master_idx := AudioServer.get_bus_index(BUS_MASTER)
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, _bus_db(master_volume))
		AudioServer.set_bus_mute(master_idx, muted or master_volume <= 0.5)
	_set_bus_db(BUS_MUSIC, _music_bus_db())
	_set_bus_db(BUS_SFX, _bus_db(sfx_volume))
	_set_bus_db(BUS_UI, _bus_db(sfx_volume))

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

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 100.0)
	SaveManager.set_setting("sfx", sfx_volume)
	apply_volumes()

# ---------------------------------------------------------------- BGM

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
		return "gameover"
	if GameState.run_state == GameState.RunState.MENU:
		return "happy"
	if GameState.cutscene_active:
		return "cutscene"
	if GameState.tyrant_active:
		return "tyrant_l5" if GameState.level >= 5 else "tyrant"
	if GameState.run_state == GameState.RunState.QUIZ:
		return "absurd"
	if GameState.run_state == GameState.RunState.CLEARED:
		return "cleared"
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

## 双轨交叉淡入（D1）：新曲从静音升到 0dB，旧曲同时降到静音后停止。
func _play(key: String) -> void:
	if key == current_key:
		return
	current_key = key
	if key == "":
		_fade_out_all(BGM_FADE)
		return
	var stream: AudioStream = _stream_for(key)
	if stream == null:
		return
	var loop := catalog_slot_loop(key)
	var fade := BGM_FADE if loop else STING_FADE
	if _players[_active].stream == stream and _players[_active].playing:
		return
	_crossfade_to(stream, loop, fade)

func _crossfade_to(stream: AudioStream, loop: bool, fade: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var old := _players[_active]
	_active = 1 - _active
	var p := _players[_active]
	p.stop()
	p.stream = stream
	if "loop" in stream:
		stream.set("loop", loop)
	p.volume_db = SILENCE_DB
	p.play()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(p, "volume_db", 0.0, fade)
	if old.playing:
		_tween.tween_property(old, "volume_db", SILENCE_DB, fade)
		_tween.chain().tween_callback(old.stop)

func _fade_out_all(fade: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	for p in _players:
		if p.playing:
			_tween.tween_property(p, "volume_db", SILENCE_DB, fade)
	_tween.chain().tween_callback(func() -> void:
		for p in _players:
			p.stop()
	)

func is_playing() -> bool:
	for p in _players:
		if p.playing and p.volume_db > -70.0:
			return true
	return false

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

## Web 端浏览器要求用户手势后才能出声：点击「开始游戏」时调一次。
func kick() -> void:
	if not OS.has_feature("web"):
		return
	if current_key.is_empty():
		return
	var p := _players[_active]
	if p.stream == null:
		return
	p.stop()
	p.volume_db = 0.0
	p.play()

# ---------------------------------------------------------------- 音效池（D2）

## 播放一次性音效（广播/UI/挥击等都走这里）。
## 同一个文件最多同时 3 个，防止同帧叠成噪音墙。
func play_sfx(path: String, volume_db := 0.0, pitch := 1.0) -> bool:
	if path.is_empty() or int(_sfx_counts.get(path, 0)) >= SFX_MAX_SAME:
		return false
	var stream := _sfx_stream(path)
	if stream == null:
		return false
	var p := _next_sfx_player()
	_claim(p, path)
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
	return true

## 带位置的音效（暴君挥击、破墙、脚步等），走 2D 播放器池。
func play_sfx_2d(path: String, world_pos: Vector2, max_distance := 900.0, volume_db := 0.0) -> bool:
	if path.is_empty() or int(_sfx_counts.get(path, 0)) >= SFX_MAX_SAME:
		return false
	var stream := _sfx_stream(path)
	if stream == null:
		return false
	var p := _next_sfx2d_player()
	_claim(p, path)
	p.stream = stream
	p.global_position = world_pos
	p.max_distance = max_distance
	p.volume_db = volume_db
	p.pitch_scale = 1.0
	p.play()
	return true

func _next_sfx_player() -> AudioStreamPlayer:
	for i in _sfx_players.size():
		var idx := (_sfx_cursor + i) % _sfx_players.size()
		if not _sfx_players[idx].playing:
			_sfx_cursor = (idx + 1) % _sfx_players.size()
			return _sfx_players[idx]
	var steal := _sfx_cursor
	_sfx_cursor = (_sfx_cursor + 1) % _sfx_players.size()
	return _sfx_players[steal]

func _next_sfx2d_player() -> AudioStreamPlayer2D:
	for i in _sfx2d_players.size():
		var idx := (_sfx2d_cursor + i) % _sfx2d_players.size()
		if not _sfx2d_players[idx].playing:
			_sfx2d_cursor = (idx + 1) % _sfx2d_players.size()
			return _sfx2d_players[idx]
	var steal := _sfx2d_cursor
	_sfx2d_cursor = (_sfx2d_cursor + 1) % _sfx2d_players.size()
	return _sfx2d_players[steal]

func _claim(p: Node, path: String) -> void:
	var old := String(p.get_meta("sfx_path", ""))
	if not old.is_empty():
		_release_sfx(old)
	p.set_meta("sfx_path", path)
	_sfx_counts[path] = int(_sfx_counts.get(path, 0)) + 1

func _release_sfx(path: String) -> void:
	var n := int(_sfx_counts.get(path, 0)) - 1
	if n <= 0:
		_sfx_counts.erase(path)
	else:
		_sfx_counts[path] = n

func _on_sfx_finished(p: Node) -> void:
	var path := String(p.get_meta("sfx_path", ""))
	if not path.is_empty():
		_release_sfx(path)

func _sfx_stream(path: String) -> AudioStream:
	if _sfx_cache.has(path):
		return _sfx_cache[path] as AudioStream
	var stream: AudioStream = load(path)
	if stream != null:
		_sfx_cache[path] = stream
	return stream

## 当前某个音效正在响的数量（调试 / 自测用）。
func sfx_active_count(path: String) -> int:
	return int(_sfx_counts.get(path, 0))
