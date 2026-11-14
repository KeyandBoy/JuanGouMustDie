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

## UI 三音（D7）：悬停 / 点击 / 确认，统一走 UI 总线。
const UI_HOVER := "res://assets/sfx/ui/ui_hover.ogg"
const UI_CLICK := "res://assets/sfx/ui/ui_click.ogg"
const UI_CONFIRM := "res://assets/sfx/ui/ui_confirm.ogg"
const UI_POOL_SIZE := 4
const UI_HOVER_DB := -14.0
const UI_CLICK_DB := -8.0
const UI_CONFIRM_DB := -7.0

## D5 环境音：按楼层垫一条低音量循环底噪（先用已入库的广播杂讯）。
const AMBIENCE_PATH := "res://assets/sfx/ambient/broadcast_noise.mp3"
const AMBIENCE_DB := -27.0
const AMBIENCE_FADE := 2.0
## D6 压迫层：暴君在场时把 Horror Drone 垫在 BGM 下面（不是分轨，只做压迫感）。
const PRESSURE_PATH := "res://assets/music/amb_tyrant_drone.ogg"
const PRESSURE_DB := -19.0
const PRESSURE_FADE := 1.8
## D8 脚步材质：素材已就位（Kenney Impact Sounds, CC0），
## 每种材质 5 条变体随机取，缺文件仍静音兜底。
## stone = 第二层石砌地面（规格 4.5）。
const STEP_MATERIALS: Array[String] = ["tile", "wood", "carpet", "stone"]
const STEP_PATH_FMT := "res://assets/sfx/step/step_%s_%d.ogg"

# ---------------------------------------------------------------- 第二层（地牢）
## 规格：.opencode/plan/第二层世界_音频规格.md
## 第二层专属槽位 → 缺素材时借用的第一层槽位。
## 这样 6~10F 现在选进去也有声音，补上曲子后自动切回。
const DUNGEON_FALLBACK := {
	"dungeon_calm": "cutscene",
	"dungeon_alert": "tension",
	"dungeon_chase": "chase",
	"dungeon_quiz": "absurd",
	"dungeon_safe": "cutscene",
	"dungeon_clear": "cleared",
	"dungeon_gameover": "gameover",
	"pyramid": "tyrant",
}

const BUS_DUNGEON_REVERB := "DungeonReverb"
const LOWPASS_OPEN_HZ := 20000.0
const LOWPASS_FLOOR_HZ := 2000.0
const TINNITUS_DB_LOUD := -18.0
const WHISPER_DB_LOUD := -24.0
const CONTAM_MIX_SPEED := 3.0        # 污染参数 0.35s 左右收敛，避免突变
const DUCK_DB := -8.0                # 被抓特效时 BGM 压低（规格 5.2）
const DUCK_HOLD := 0.6
const DUCK_RECOVER := 0.4

const TINNITUS_PATH := "res://assets/sfx/dungeon/tinnitus_loop.ogg"
const WHISPER_PATH := "res://assets/sfx/dungeon/whisper_loop.ogg"
const HALLUC_STEP_PATHS: Array[String] = [
	"res://assets/sfx/step/step_tile_1.ogg",
	"res://assets/sfx/step/step_tile_2.ogg",
	"res://assets/sfx/step/step_tile_3.ogg",
	"res://assets/sfx/step/step_wood_1.ogg",
	"res://assets/sfx/step/step_wood_2.ogg",
]
const HALLUC_DOOR_PATH := "res://assets/sfx/dungeon/door_far.ogg"
const WHISPER_HIT_PATH := "res://assets/sfx/dungeon/whisper_hit.ogg"

## 幻听（规格第 7 节）
const HALLUC_CONTAM_MIN := 50.0
const HALLUC_INTERVAL_MIN := 8.0
const HALLUC_INTERVAL_MAX := 15.0
const HALLUC_MAX_ACTIVE := 2
const HALLUC_DIST_MIN := 200.0
const HALLUC_DIST_MAX := 400.0

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

## D5 / D6：环境层与压迫层各一条独立播放器，和 BGM 双轨分开。
var _ambience: AudioStreamPlayer
var _pressure: AudioStreamPlayer
var _ambience_key := ""
var _pressure_key := ""
var _ambience_tween: Tween
var _pressure_tween: Tween
var _file_exists: Dictionary = {}

## 第二层：低通 / 混响 / 耳鸣耳语 / duck / 幻听
var _lowpass_idx := -1
var _reverb_bus := -1
var _reverb_effect: AudioEffectReverb
var _tinnitus: AudioStreamPlayer
var _whisper: AudioStreamPlayer
var _accent_ready := false
var _mix_ratio := 0.0
var _target_ratio := 0.0
var _duck_db := 0.0
var _duck_tween: Tween
var _zone_preset := "room"
var _halluc_timer := 9.0
var _halluc_active: Array[float] = []

## UI 音效（D7）
var ui_sounds_enabled := true
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_cursor := 0
var _ui_prev_hover: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_catalog()
	_build_music_players()
	_build_ambient_players()
	_build_sfx_pool()
	_ensure_dungeon_buses()
	_build_accent_players()
	master_volume = float(SaveManager.get_setting("master", 100.0))
	music_volume = float(SaveManager.get_setting("music", 100.0))
	sfx_volume = float(SaveManager.get_setting("sfx", 100.0))
	muted = bool(SaveManager.get_setting("muted", false))
	apply_volumes()
	_target_ratio = GameState.contamination_ratio() if GameState.world == 2 else 0.0
	_mix_ratio = _target_ratio
	GameState.contamination_changed.connect(_on_contamination_changed)
	_apply_world_routing()
	_apply_contamination_mix()

func _build_music_players() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = BUS_MUSIC
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		p.volume_db = SILENCE_DB
		add_child(p)
		_players.append(p)

func _build_ambient_players() -> void:
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = BUS_AMBIENCE
	_ambience.process_mode = Node.PROCESS_MODE_ALWAYS
	_ambience.volume_db = SILENCE_DB
	add_child(_ambience)
	_pressure = AudioStreamPlayer.new()
	_pressure.bus = BUS_MUSIC
	_pressure.process_mode = Node.PROCESS_MODE_ALWAYS
	_pressure.volume_db = SILENCE_DB
	add_child(_pressure)

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
	for i in UI_POOL_SIZE:
		var u := AudioStreamPlayer.new()
		u.bus = BUS_UI
		u.process_mode = Node.PROCESS_MODE_ALWAYS
		u.volume_db = 0.0
		add_child(u)
		_ui_players.append(u)

# ---------------------------------------------------------------- 第二层总线 / 重音层

## 第二层总线：Music 上加一只低通（第一层禁用），再建一条 DungeonReverb
## 辅助总线给走廊/房间/安全屋混响用。
## 为什么运行时建而不是写进 .tres：总线布局是工程级资源，运行时加能保证
## 第一层完全不受影响，也方便 headless 探针直接断言。
func _ensure_dungeon_buses() -> void:
	var music_idx := AudioServer.get_bus_index(BUS_MUSIC)
	if music_idx >= 0:
		for i in AudioServer.get_bus_effect_count(music_idx):
			if AudioServer.get_bus_effect(music_idx, i) is AudioEffectLowPassFilter:
				_lowpass_idx = i
				break
		if _lowpass_idx < 0:
			AudioServer.add_bus_effect(music_idx, AudioEffectLowPassFilter.new())
			_lowpass_idx = AudioServer.get_bus_effect_count(music_idx) - 1
		AudioServer.set_bus_effect_enabled(music_idx, _lowpass_idx, false)
	_reverb_bus = AudioServer.get_bus_index(BUS_DUNGEON_REVERB)
	if _reverb_bus < 0:
		AudioServer.add_bus()
		_reverb_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_reverb_bus, BUS_DUNGEON_REVERB)
		AudioServer.set_bus_send(_reverb_bus, BUS_MASTER)
		var rv := AudioEffectReverb.new()
		AudioServer.add_bus_effect(_reverb_bus, rv)
		_reverb_effect = rv
	else:
		for i in AudioServer.get_bus_effect_count(_reverb_bus):
			var e := AudioServer.get_bus_effect(_reverb_bus, i)
			if e is AudioEffectReverb:
				_reverb_effect = e
				break
	set_reverb_preset(_zone_preset, true)


## 耳鸣 / 耳语两个循环层（规格 5.1）。
## 耳鸣走 SFX 总线：低通只压 Music，不能让 8kHz 的耳鸣也被滤掉。
func _build_accent_players() -> void:
	_tinnitus = AudioStreamPlayer.new()
	_tinnitus.bus = BUS_SFX
	_tinnitus.process_mode = Node.PROCESS_MODE_ALWAYS
	_tinnitus.volume_db = SILENCE_DB
	add_child(_tinnitus)
	_whisper = AudioStreamPlayer.new()
	_whisper.bus = BUS_AMBIENCE
	_whisper.process_mode = Node.PROCESS_MODE_ALWAYS
	_whisper.volume_db = SILENCE_DB
	add_child(_whisper)
	_accent_ready = true


## 第一层：低通关、总线 send 回 Master；第二层：低通开、Music/SFX/Ambience 送混响。
func _apply_world_routing() -> void:
	var dungeon: bool = GameState.world == 2
	var music_idx := AudioServer.get_bus_index(BUS_MUSIC)
	if music_idx >= 0 and _lowpass_idx >= 0:
		AudioServer.set_bus_effect_enabled(music_idx, _lowpass_idx, dungeon)
	if _reverb_bus < 0:
		return
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_send(idx, BUS_DUNGEON_REVERB if dungeon else BUS_MASTER)


## 混响预设（规格第 6 节）：走廊长、房间短、安全屋干。
func set_reverb_preset(preset: String, immediate := false) -> void:
	var presets := {
		"corridor": {"room": 0.85, "wet": 0.45, "dry": 0.75},
		"room": {"room": 0.50, "wet": 0.25, "dry": 0.90},
		"safe": {"room": 0.25, "wet": 0.10, "dry": 0.97},
	}
	if not presets.has(preset):
		preset = "room"
	_zone_preset = preset
	if _reverb_effect == null:
		return
	var d: Dictionary = presets[preset]
	if immediate:
		_reverb_effect.room_size = float(d["room"])
		_reverb_effect.wet = float(d["wet"])
		_reverb_effect.dry = float(d["dry"])
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_reverb_effect, "room_size", float(d["room"]), 0.4)
	tw.tween_property(_reverb_effect, "wet", float(d["wet"]), 0.4)
	tw.tween_property(_reverb_effect, "dry", float(d["dry"]), 0.4)


func current_zone_preset() -> String:
	return _zone_preset

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

## C1/C8：当前正在播的曲子信息，给标题画面/菜单做“曲名条”。
func current_track_title() -> String:
	var d := _entry_for_slot(_resolve_slot(current_key))
	if d.is_empty():
		return ""
	return String(d.get("title", ""))

func current_track_author() -> String:
	var d := _entry_for_slot(_resolve_slot(current_key))
	if d.is_empty():
		return ""
	var lic = d.get("license", {})
	if lic is Dictionary:
		return String(lic.get("author", ""))
	return ""

func current_track_credit() -> String:
	var title := current_track_title()
	if title.is_empty():
		return ""
	var author := current_track_author()
	if author.is_empty():
		return "♪ " + title
	return "♪ %s — %s" % [title, author]

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
		if scope is Array and not scope.has("all"):
			# JSON 里的数字一律解析成 float，这里按 int 再比一次，
			# 否则 level_scope: [5] 永远匹配不到第 5 层。
			var in_scope := false
			for s in scope:
				if int(s) == level:
					in_scope = true
					break
			if not in_scope:
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
	_set_bus_db(BUS_AMBIENCE, _bus_db(sfx_volume, -4.0))
	_apply_music_volume()


## 音乐总线音量 = 滑条曲线 + 临时 duck 偏移（被抓/答题压低时用）。
func _apply_music_volume() -> void:
	_set_bus_db(BUS_MUSIC, _music_bus_db() + _duck_db)


## 规格 5.2：被抓特效期间 BGM −8dB，hold 之后 0.4s 恢复。
func duck_music(db := DUCK_DB, hold := DUCK_HOLD) -> void:
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_db = db
	_apply_music_volume()
	_duck_tween = create_tween()
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_method(_set_duck_db, db, 0.0, DUCK_RECOVER)


func _set_duck_db(v: float) -> void:
	_duck_db = v
	_apply_music_volume()

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
	_ui_hover_tick()
	_tick_contamination(delta)
	_tick_hallucination(delta)
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	_refresh()

func _refresh() -> void:
	_apply_world_routing()
	var key := _desired_key()
	if key != current_key:
		_play(key)
	_refresh_ambience()
	_refresh_pressure()


## D5：环境音只在该楼层探索/答题时存在；教学关、菜单、过场都关掉。
func desired_ambience_path() -> String:
	if GameState.tutorial_active:
		return ""
	if GameState.run_state != GameState.RunState.EXPLORING and GameState.run_state != GameState.RunState.QUIZ:
		return ""
	if GameState.level < 2:
		return ""
	return AMBIENCE_PATH if _exists(AMBIENCE_PATH) else ""


## D6：暴君在场时垫压迫层；真正的追逐鼓点层仍等分轨素材。
func desired_pressure_path() -> String:
	if not GameState.tyrant_active or GameState.cutscene_active:
		return ""
	if GameState.run_state == GameState.RunState.MENU:
		return ""
	return PRESSURE_PATH if _exists(PRESSURE_PATH) else ""


func _refresh_ambience() -> void:
	var path := desired_ambience_path()
	if path == _ambience_key:
		return
	_ambience_key = path
	if path.is_empty():
		_fade_out_player(_ambience, _ambience_tween, AMBIENCE_FADE)
		return
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	var stream := _sfx_stream(path)
	if stream == null:
		_ambience_key = ""
		return
	if "loop" in stream:
		stream.set("loop", true)
	_ambience.stream = stream
	_ambience.volume_db = SILENCE_DB
	_ambience.play()
	var tw := create_tween()
	_ambience_tween = tw
	tw.tween_property(_ambience, "volume_db", AMBIENCE_DB, AMBIENCE_FADE)


func _refresh_pressure() -> void:
	var path := desired_pressure_path()
	if path == _pressure_key:
		return
	_pressure_key = path
	if path.is_empty():
		_fade_out_player(_pressure, _pressure_tween, PRESSURE_FADE)
		return
	if _pressure_tween != null and _pressure_tween.is_valid():
		_pressure_tween.kill()
	var stream := _sfx_stream(path)
	if stream == null:
		_pressure_key = ""
		return
	if "loop" in stream:
		stream.set("loop", true)
	_pressure.stream = stream
	_pressure.volume_db = SILENCE_DB
	_pressure.play()
	var tw := create_tween()
	_pressure_tween = tw
	tw.tween_property(_pressure, "volume_db", PRESSURE_DB, PRESSURE_FADE)


func _fade_out_player(p: AudioStreamPlayer, tw: Tween, dur: float) -> void:
	if p == null or not p.playing:
		return
	if tw != null and tw.is_valid():
		tw.kill()
	var t := create_tween()
	t.tween_property(p, "volume_db", SILENCE_DB, dur)
	t.tween_callback(p.stop)

# ---------------------------------------------------------------- 污染驱动的混音

func _on_contamination_changed(value: float) -> void:
	_target_ratio = 0.0 if GameState.world != 2 else clampf(value / 100.0, 0.0, 1.0)


## 规格 5.1：污染越高，Music 低通越低、耳鸣越响；≥75 再起耳语层。
## 参数按 0.35s 左右插值，避免跨档时突变。
func _tick_contamination(delta: float) -> void:
	if GameState.world != 2:
		_target_ratio = 0.0
	_mix_ratio = lerpf(_mix_ratio, _target_ratio, clampf(delta * CONTAM_MIX_SPEED, 0.0, 1.0))
	_apply_contamination_mix()


func _apply_contamination_mix() -> void:
	var music_idx := AudioServer.get_bus_index(BUS_MUSIC)
	if music_idx >= 0 and _lowpass_idx >= 0:
		var fx := AudioServer.get_bus_effect(music_idx, _lowpass_idx)
		if fx is AudioEffectLowPassFilter:
			(fx as AudioEffectLowPassFilter).cutoff_hz = lerpf(LOWPASS_OPEN_HZ, LOWPASS_FLOOR_HZ, _mix_ratio)
	if not _accent_ready:
		return
	_update_accent(_tinnitus, TINNITUS_PATH, lerpf(SILENCE_DB, TINNITUS_DB_LOUD, _mix_ratio), _mix_ratio > 0.01)
	var whisper_ratio := clampf((_mix_ratio - 0.75) / 0.25, 0.0, 1.0)
	_update_accent(_whisper, WHISPER_PATH, lerpf(SILENCE_DB, WHISPER_DB_LOUD, whisper_ratio), whisper_ratio > 0.01)


func _update_accent(p: AudioStreamPlayer, path: String, db: float, active: bool) -> void:
	if p == null:
		return
	if not active:
		if p.playing:
			p.stop()
		return
	if p.stream == null:
		var s := _sfx_stream(path)
		if s == null:
			return
		if "loop" in s:
			s.set("loop", true)
		p.stream = s
	if not p.playing:
		p.play()
	p.volume_db = db


func contamination_mix_ratio() -> float:
	return _mix_ratio

# ---------------------------------------------------------------- 幻听（规格第 7 节）

## 污染 ≥50 时每 8~15s 在玩家身后放一声；同时最多 2 个；安全屋与菜单不播。
func _tick_hallucination(delta: float) -> void:
	for i in range(_halluc_active.size() - 1, -1, -1):
		_halluc_active[i] -= delta
		if _halluc_active[i] <= 0.0:
			_halluc_active.remove_at(i)
	if GameState.world != 2 or GameState.run_state != GameState.RunState.EXPLORING:
		return
	if GameState.contamination < HALLUC_CONTAM_MIN:
		return
	if bool(GameState.get("in_safe_room")):
		return
	if _halluc_active.size() >= HALLUC_MAX_ACTIVE:
		return
	_halluc_timer -= delta
	if _halluc_timer > 0.0:
		return
	_halluc_timer = randf_range(HALLUC_INTERVAL_MIN, HALLUC_INTERVAL_MAX)
	_play_hallucination()


func _play_hallucination() -> bool:
	if _halluc_active.size() >= HALLUC_MAX_ACTIVE:
		return false
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player):
		return false
	var facing := Vector2.DOWN
	var fd = player.get("face_dir")
	if fd is Vector2 and (fd as Vector2).length() > 0.1:
		facing = fd
	# 「身后」= 朝向反方向 ±45°
	var dir := (-facing).normalized().rotated(deg_to_rad(randf_range(-45.0, 45.0)))
	var pos: Vector2 = player.global_position + dir * randf_range(HALLUC_DIST_MIN, HALLUC_DIST_MAX)
	var path := ""
	var r := randf()
	if r < 0.25 and _exists(HALLUC_DOOR_PATH):
		path = HALLUC_DOOR_PATH
	elif r < 0.40 and _exists(WHISPER_HIT_PATH):
		path = WHISPER_HIT_PATH
	else:
		path = HALLUC_STEP_PATHS[randi_range(0, HALLUC_STEP_PATHS.size() - 1)]
	if not play_sfx_2d(path, pos, 900.0, -8.0):
		return false
	_halluc_active.append(1.4)
	return true

func _desired_key() -> String:
	if GameState.run_state == GameState.RunState.MENU:
		return "happy"
	if GameState.run_state == GameState.RunState.GAMEOVER:
		return "dungeon_gameover" if GameState.world == 2 else "gameover"
	if GameState.cutscene_active:
		return "cutscene"
	if GameState.run_state == GameState.RunState.CLEARED:
		return "dungeon_clear" if GameState.world == 2 else "cleared"
	if GameState.world == 2:
		return _desired_key_dungeon()
	if GameState.tyrant_active:
		return "tyrant_l5" if GameState.level >= 5 else "tyrant"
	if GameState.run_state == GameState.RunState.QUIZ:
		return "absurd"
	var w: int = GameState.warnings
	if w >= 2 or _any_chasing():
		return "chase"
	if w == 1:
		return "tension"
	return "happy"


## 第二层状态机（规格第 3 节）：地牢不用警告值，改用污染 + 安全屋 + 三角头。
func _desired_key_dungeon() -> String:
	if GameState.tyrant_active:
		return "pyramid"
	if GameState.run_state == GameState.RunState.QUIZ:
		return "dungeon_quiz"
	if bool(GameState.get("in_safe_room")):
		return "dungeon_safe"
	if _any_chasing():
		return "dungeon_chase"
	if GameState.contamination >= HALLUC_CONTAM_MIN:
		return "dungeon_alert"
	return "dungeon_calm"


## 曲库条目缺失时借用回退槽位（第二层专用，第一层不受影响）。
func _resolve_slot(key: String) -> String:
	if not catalog_slot_path(key).is_empty():
		return key
	var fb := String(DUNGEON_FALLBACK.get(key, ""))
	return fb if not fb.is_empty() else key

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
	var real_key := _resolve_slot(key)
	var stream: AudioStream = _stream_for(real_key)
	if stream == null:
		# 别把空曲占住 current_key，否则素材补上后这一局都不会再试
		current_key = ""
		return
	var loop := catalog_slot_loop(real_key)
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
	if path.is_empty() or not _exists(path):
		return null
	if _sfx_cache.has(path):
		return _sfx_cache[path] as AudioStream
	var stream: AudioStream = load(path)
	if stream != null:
		_sfx_cache[path] = stream
	return stream

## D8：脚步材质。约定文件：assets/sfx/step/step_<material>_<1..3>.ogg
## 缺文件直接返回 false（静音），不会每次都报错。
func play_footstep(material: String, world_pos: Vector2, running := false) -> bool:
	var m: String = material if STEP_MATERIALS.has(material) else "tile"
	var candidates: Array[String] = []
	for i in range(1, 6):
		candidates.append(STEP_PATH_FMT % [m, i])
	candidates.append("res://assets/sfx/step/step_%s.ogg" % m)
	candidates.append("res://assets/sfx/step/step_%s_1.wav" % m)
	var pool: Array[String] = []
	for c in candidates:
		if _exists(c):
			pool.append(c)
	if pool.is_empty():
		return false
	var path: String = pool[randi_range(0, pool.size() - 1)]
	var vol := -9.0 if running else -13.0
	return play_sfx_2d(path, world_pos, 520.0, vol)


func _exists(path: String) -> bool:
	if not _file_exists.has(path):
		_file_exists[path] = ResourceLoader.exists(path)
	return bool(_file_exists[path])


## 当前某个音效正在响的数量（调试 / 自测用）。
func sfx_active_count(path: String) -> int:
	return int(_sfx_counts.get(path, 0))

# ---------------------------------------------------------------- UI 三音（D7）

## 鼠标停到按钮上就响一声「悬停」。轮询比给每个 Button 连信号可靠：
## 菜单里的按钮是运行时动态建的，连信号会漏，轮询不会。
func _ui_hover_tick() -> void:
	if not ui_sounds_enabled:
		return
	if _ui_prev_hover != null and not is_instance_valid(_ui_prev_hover):
		_ui_prev_hover = null
	var btn := _button_under_mouse()
	if btn == _ui_prev_hover:
		return
	_ui_prev_hover = btn
	if btn != null:
		play_ui(UI_HOVER, UI_HOVER_DB)

func _input(event: InputEvent) -> void:
	if not ui_sounds_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _button_under_mouse() != null:
			play_ui(UI_CLICK, UI_CLICK_DB)
	elif event.is_action_pressed("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
		if focused is BaseButton and not (focused as BaseButton).disabled:
			play_ui(UI_CONFIRM, UI_CONFIRM_DB)

## 返回鼠标正下方的可用按钮；被遮罩挡住或 disabled 都不算。
func _button_under_mouse() -> BaseButton:
	var vp := get_viewport()
	if vp == null:
		return null
	var c: Control = vp.gui_get_hovered_control()
	var guard := 0
	while c != null and guard < 8:
		if c is BaseButton:
			var b := c as BaseButton
			return null if b.disabled else b
		# 按钮内部的 Label/Icon 也要能算到按钮头上
		c = c.get_parent_control()
		guard += 1
	return null

## 播放 UI 音效（走 UI 总线，音量跟「音效音量」滑条）。
func play_ui(path: String, volume_db := UI_CLICK_DB) -> bool:
	if not ui_sounds_enabled or path.is_empty():
		return false
	var stream := _sfx_stream(path)
	if stream == null:
		return false
	var p := _ui_players[_ui_cursor]
	_ui_cursor = (_ui_cursor + 1) % _ui_players.size()
	p.stop()
	p.stream = stream
	p.volume_db = volume_db
	p.play()
	return true
