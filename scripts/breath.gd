class_name Breath
extends Node

## 状态呼吸声（A10）：只负责判断「现在该怎么呼吸」。
##
## 分工（重要）：
##   - 本节点只算状态 + 节拍 + 预留音轨槽，不加载素材、不播放；
##   - 音频窗口按 `state_changed` / 每帧读 `stream_slot` 接真实素材，
##     素材路径用 STREAM_SLOTS，找不到素材时静音即可，逻辑不受影响。
##
## 触发来源（由 main.gd 每帧汇总后调用）：
##   set_sources(chased, uneasy, dark)
##   notify_hurt(sec)   —— 被抓/受伤后的一段时间强制喘
##
## 优先级：panic（被追/刚受伤） > blind（停电看不见） > tense（附近有人搜寻） > calm。
## 这样「停电里被追」是 panic，「受伤躲柜子里」也能靠 hurt_timer 维持喘气。

signal state_changed(state: int)

enum State { CALM, TENSE, PANIC, BLIND }

const STATE_NAMES := ["calm", "tense", "panic", "blind"]

## 每分钟呼吸次数：只给音频窗口做 pitch / 播放间隔参考。
const RATE_PER_MIN := {
	State.CALM: 14,
	State.TENSE: 22,
	State.PANIC: 34,
	State.BLIND: 26,
}

## 预留音轨槽。素材由音频窗口补齐；缺失时状态仍然正确，只是没有声音。
const STREAM_SLOTS := {
	State.CALM: "",
	State.TENSE: "res://assets/sfx/breath/breath_tense.ogg",
	State.PANIC: "res://assets/sfx/breath/breath_panic.ogg",
	State.BLIND: "res://assets/sfx/breath/breath_blind.ogg",
}

## 受伤后强制 panic 的默认时长（秒）
const HURT_PANIC_SEC := 10.0
## 状态切换的稳定时间，避免「刚好擦过视野」把呼吸抖成机关枪
const SETTLE_SEC := 0.18

var state: int = State.CALM
var rate_per_min: int = RATE_PER_MIN[State.CALM]
var stream_slot := ""

var _chased := false
var _uneasy := false
var _dark := false
var _hurt_left := 0.0
var _pending_state: int = State.CALM
var _pending_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)


## main.gd 每帧汇总三个来源。任一为 true 即参与优先级竞争。
func set_sources(chased: bool, uneasy: bool, dark: bool) -> void:
	_chased = chased
	_uneasy = uneasy
	_dark = dark


## 受伤/被抓：接下来 sec 秒内至少 panic（值会被更长的覆盖）。
func notify_hurt(sec := HURT_PANIC_SEC) -> void:
	_hurt_left = maxf(_hurt_left, sec)


func clear() -> void:
	_chased = false
	_uneasy = false
	_dark = false
	_hurt_left = 0.0
	_pending_time = 0.0
	_apply_state(State.CALM)


func is_active() -> bool:
	return state != State.CALM


func state_name() -> String:
	return STATE_NAMES[state]


func status_text() -> String:
	return "呼吸:%s %d/min" % [state_name(), rate_per_min]


## 音频窗口可以直接用它当「该循环哪条」的 key；空串 = 静音。
func stream_slot_for(s: int) -> String:
	return String(STREAM_SLOTS.get(s, ""))


func _process(delta: float) -> void:
	if _hurt_left > 0.0:
		_hurt_left = maxf(0.0, _hurt_left - delta)
	var target := _target_state()
	if target == state:
		_pending_time = 0.0
		return
	if target == _pending_state:
		_pending_time += delta
	else:
		_pending_state = target
		_pending_time = 0.0
	# 变紧张快一点，放松慢一点，听感更自然
	var need := SETTLE_SEC * 2.0 if target == State.CALM else SETTLE_SEC
	if _pending_time >= need:
		_apply_state(target)


func _target_state() -> int:
	if _hurt_left > 0.0 or _chased:
		return State.PANIC
	if _dark:
		return State.BLIND
	if _uneasy:
		return State.TENSE
	return State.CALM


func _apply_state(s: int) -> void:
	_pending_time = 0.0
	_pending_state = s
	if s == state:
		return
	state = s
	rate_per_min = int(RATE_PER_MIN.get(s, 14))
	stream_slot = stream_slot_for(s)
	state_changed.emit(state)
