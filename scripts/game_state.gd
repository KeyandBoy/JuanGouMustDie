extends Node

signal study_changed(value: float)
signal study_goal_changed(value: float)
signal emptiness_changed(value: float)
signal warnings_changed(count: int)
signal dash_changed(value: float)
signal inventory_changed
signal stars_changed
signal level_changed(value: int)
signal hot_changed(level: int)
signal state_changed(key: StringName)

const DASH_MAX := 100.0
const HOT_THRESHOLDS: Array[int] = [3, 6, 9]
const HOT_MULTIPLIERS: Array[float] = [1.0, 1.1, 1.2, 1.3]
const MAX_LEVEL := 5
const LEVEL_GOALS := {
	1: 5.0,
	2: 8.0,
	3: 11.0,
	4: 15.0,
	5: 20.0,
}
const ITEM_CAPACITY := 3
const BASE_ITEM_CAPACITY := 1
const STAR_BASE := 45.0
const STAR_PER_GOAL := 15.0
const MAX_STARS_PER_LEVEL := 3
const STAR_ACC_3 := 85.0
const STAR_ACC_2 := 60.0
const STAR_QUIZ_TIME_3 := 120.0
const STAR_QUIZ_TIME_2 := 180.0
const STAR_W_TIME := 0.4
const STAR_W_CAUGHT := 0.25
const STAR_W_ACC := 0.25
const STAR_W_QUIZ := 0.1
const STAR_SCORE_3 := 85.0
const STAR_SCORE_2 := 60.0
const UPGRADE_DEFS := {
	"capacity": {"name": "背包扩容", "desc": "可携带道具 +1 格", "cost": 3, "max": 2},
	"dash_cd": {"name": "冲刺冷却缩短", "desc": "闪避充能速度 +25%", "cost": 2, "max": 2},
	"dash_charges": {"name": "双重冲刺", "desc": "可连续冲刺两次", "cost": 3, "max": 1},
	"speed": {"name": "基础速度", "desc": "移动速度 +6%", "cost": 2, "max": 2},
	"warnings": {"name": "预警次数", "desc": "每关警告次数 +1", "cost": 2, "max": 2},
}
const ITEM_DEFS := {
	"coffee": {"name": "咖啡", "desc": "8 秒内移动加速", "color": Color(0.62, 0.38, 0.18)},
	"bread": {"name": "面包", "desc": "回复 25 空虚", "color": Color(0.90, 0.72, 0.38)},
	"smoke": {"name": "烟雾弹", "desc": "减速附近的暴君", "color": Color(0.58, 0.62, 0.68)},
	"chair": {"name": "折叠椅", "desc": "近身击退并眩晕暴君", "color": Color(0.55, 0.40, 0.26)},
	"stink": {"name": "臭气弹", "desc": "短时干扰暴君的嗅觉", "color": Color(0.48, 0.64, 0.28)},
	"portal": {"name": "任意门", "desc": "放下第一端，再放第二端传送", "color": Color(0.52, 0.40, 0.86)},
	"shovel": {"name": "土锹", "desc": "挖开一条临时捷径（动静很大）", "color": Color(0.58, 0.45, 0.30)},
	"lamp": {"name": "超频台灯", "desc": "10 秒学习效率翻倍，但翻书声更大", "color": Color(0.95, 0.86, 0.45)},
	"notes": {"name": "学霸笔记", "desc": "本关学习效率 +10%", "color": Color(0.40, 0.62, 0.92)},
	"shoes": {"name": "软底鞋", "desc": "本关移动稍快、噪音更小", "color": Color(0.42, 0.44, 0.48)},
	"stopwatch": {"name": "秒表", "desc": "本关闪避充能 +20%", "color": Color(0.72, 0.74, 0.78)},
	"intel": {"name": "巡查情报", "desc": "12 秒内显示巡查者位置与路线", "color": Color(0.86, 0.36, 0.62)},
	"ears": {"name": "耳塞", "desc": "本关学习/答题的翻书声更小", "color": Color(0.80, 0.82, 0.90)},
}

enum RunState { MENU, EXPLORING, QUIZ, CAUGHT, GAMEOVER, CLEARED, CUTSCENE }

var run_state: RunState = RunState.MENU:
	set(v):
		run_state = v
		state_changed.emit(&"run_state")

var grade_id: String = "junior":
	set(v):
		grade_id = v
		state_changed.emit(&"grade")

var subjects: Array[String] = ["math"]:
	set(v):
		subjects = v
		state_changed.emit(&"subjects")

var level: int = 1
var study_goal: float = 5.0
var study: float = 0.0:
	set(v):
		study = clampf(v, 0.0, maxf(0.01, study_goal))
		study_changed.emit(study)
var answer_efficiency: float = 1.0

var emptiness: float = 50.0:
	set(v):
		emptiness = clampf(v, 0.0, 100.0)
		emptiness_changed.emit(emptiness)

var max_warnings: int = 3
var warnings: int = 0:
	set(v):
		warnings = clampi(v, 0, max_warnings)
		warnings_changed.emit(warnings)

var correct_streak: int = 0
var dash_energy: float = 0.0:
	set(v):
		dash_energy = clampf(v, 0.0, dash_max_value())
		dash_changed.emit(dash_energy)
var questions_answered: int = 0
var quiz_correct: int = 0
var caught_stun_time: float = 2.0
var phase: String = "morning"
var abilities: Dictionary = {}
var items: Dictionary = {}
var seed_value: int = 0
var stars: int = 0
var level_stars: Dictionary = {}
var upgrades: Dictionary = {}
var max_cleared_level := 1

var inventory: Array[String] = []
var tyrant_intro_seen := false
var tyrant_active := false
var cutscene_active := false
var game_cleared := false
var intel_reveal_timer := 0.0
var exam_hint := false

var level_time := 0.0
var quiz_time := 0.0
var caught_count := 0
var tyrant_hits := 0
var items_collected := 0
var intel_found := 0
var explored_rooms := 0

func _ready() -> void:
	randomize()
	seed_value = randi()
	set_level(1)

func set_level(p_level: int) -> void:
	level = clampi(p_level, 1, MAX_LEVEL)
	study_goal = float(LEVEL_GOALS.get(level, 5.0))
	study = clampf(study, 0.0, study_goal)
	level_changed.emit(level)
	study_goal_changed.emit(study_goal)

func start_run(p_grade: String = "junior", p_subjects: Array[String] = ["math"]) -> void:
	grade_id = p_grade
	subjects = p_subjects
	set_level(1)
	study = 0.0
	emptiness = 50.0
	warnings = 0
	dash_energy = 0.0
	correct_streak = 0
	questions_answered = 0
	quiz_correct = 0
	seed_value = randi()
	inventory.clear()
	abilities.clear()
	items.clear()
	tyrant_intro_seen = false
	tyrant_active = false
	cutscene_active = false
	game_cleared = false
	intel_reveal_timer = 0.0
	exam_hint = false
	_reset_level_stats()
	_sync_hot()
	inventory_changed.emit()
	run_state = RunState.EXPLORING

func _reset_level_stats() -> void:
	level_time = 0.0
	quiz_time = 0.0
	caught_count = 0
	tyrant_hits = 0
	items_collected = 0
	intel_found = 0
	explored_rooms = 0

func begin_next_level() -> void:
	if level >= MAX_LEVEL:
		return
	set_level(level + 1)
	study = 0.0
	warnings = 0
	dash_energy = 0.0
	correct_streak = 0
	questions_answered = 0
	quiz_correct = 0
	inventory.clear()
	abilities.clear()
	items.clear()
	tyrant_active = false
	cutscene_active = false
	intel_reveal_timer = 0.0
	exam_hint = false
	_reset_level_stats()
	_sync_hot()
	inventory_changed.emit()
	run_state = RunState.EXPLORING

func add_study(amount: float) -> void:
	if run_state == RunState.CLEARED or run_state == RunState.GAMEOVER:
		return
	study += amount
	if study >= study_goal:
		run_state = RunState.CLEARED

func damage_emptiness(amount: float) -> void:
	emptiness -= amount
	if emptiness <= 0.0:
		run_state = RunState.GAMEOVER

func restore_emptiness(amount: float) -> void:
	emptiness += amount

func add_warning(count: int = 1) -> void:
	warnings += count
	if warnings >= max_warnings:
		run_state = RunState.GAMEOVER

func clear_warnings() -> void:
	warnings = 0

func on_correct_answer(efficiency: float = -1.0) -> void:
	quiz_correct += 1
	questions_answered += 1
	correct_streak += 1
	var gain := answer_efficiency if efficiency < 0.0 else efficiency
	add_study(maxf(0.1, gain * hot_multiplier()))
	if correct_streak % 3 == 0:
		restore_emptiness(10.0)
	_sync_hot()

func on_wrong_answer() -> void:
	correct_streak = 0
	questions_answered += 1
	study = maxf(0.0, study - 1.0)
	damage_emptiness(2.0)
	_sync_hot()

func hot_level() -> int:
	var lvl := 0
	for i in HOT_THRESHOLDS.size():
		if correct_streak >= HOT_THRESHOLDS[i]:
			lvl = i + 1
	return lvl

func hot_multiplier() -> float:
	return HOT_MULTIPLIERS[hot_level()]

func break_hot() -> void:
	correct_streak = 0
	_sync_hot()

func _sync_hot() -> void:
	hot_changed.emit(hot_level())

func add_item(item_id: String) -> bool:
	if not ITEM_DEFS.has(item_id):
		return false
	if inventory.size() >= item_capacity():
		return false
	inventory.append(item_id)
	items_collected += 1
	inventory_changed.emit()
	return true

func item_capacity() -> int:
	return mini(ITEM_CAPACITY, BASE_ITEM_CAPACITY + int(upgrades.get("capacity", 0)))

func passive_speed_bonus() -> float:
	return float(upgrades.get("speed", 0)) * 0.06

func dash_charge_bonus() -> float:
	return float(upgrades.get("dash_cd", 0)) * 0.25

func dash_segments() -> int:
	return 1 + int(upgrades.get("dash_charges", 0))

func dash_max_value() -> float:
	return DASH_MAX * float(dash_segments())

func star_base_time(p_level: int) -> float:
	return STAR_BASE + STAR_PER_GOAL * float(LEVEL_GOALS.get(p_level, 5.0))

func star_accuracy() -> float:
	if questions_answered <= 0:
		return 0.0
	return 100.0 * float(quiz_correct) / float(questions_answered)

func star_gate(p_level: int, clear_time: float, caught: int, acc: float, p_quiz_time: float) -> int:
	if caught == 0 and acc >= STAR_ACC_3 and p_quiz_time <= STAR_QUIZ_TIME_3:
		return MAX_STARS_PER_LEVEL
	if caught <= 1 and acc >= STAR_ACC_2 and p_quiz_time <= STAR_QUIZ_TIME_2:
		return 2
	return 1

func star_score(p_level: int, clear_time: float, caught: int, acc: float, p_quiz_time: float) -> float:
	var base := star_base_time(p_level)
	var time_part := clampf(100.0 * base / maxf(clear_time, 0.1), 0.0, 100.0)
	var caught_part := clampf(100.0 - 50.0 * float(caught), 0.0, 100.0)
	var quiz_part := clampf(100.0 * 90.0 / maxf(p_quiz_time, 1.0), 0.0, 100.0)
	return time_part * STAR_W_TIME + caught_part * STAR_W_CAUGHT + acc * STAR_W_ACC + quiz_part * STAR_W_QUIZ

func star_report(p_level: int, clear_time: float, caught: int, p_questions: int = -1, p_correct: int = -1, p_quiz_time: float = -1.0) -> Dictionary:
	var acc := star_accuracy() if p_questions < 0 else 100.0 * float(p_correct) / float(maxi(1, p_questions))
	var qt := quiz_time if p_quiz_time < 0.0 else p_quiz_time
	var gate := star_gate(p_level, clear_time, caught, acc, qt)
	var score := star_score(p_level, clear_time, caught, acc, qt)
	var weighted := MAX_STARS_PER_LEVEL if score >= STAR_SCORE_3 else (2 if score >= STAR_SCORE_2 else 1)
	return {
		"accuracy": acc,
		"quiz_time": qt,
		"gate": gate,
		"score": score,
		"weighted": weighted,
		"stars": mini(gate, weighted),
		"time_ok": clear_time <= star_base_time(p_level),
	}

func evaluate_stars(p_level: int, clear_time: float, caught: int, p_questions: int = -1, p_correct: int = -1, p_quiz_time: float = -1.0) -> int:
	return int(star_report(p_level, clear_time, caught, p_questions, p_correct, p_quiz_time)["stars"])

func is_level_unlocked(p_level: int) -> bool:
	if DevMode.enabled and DevMode.unlock_all_levels:
		return true
	return p_level <= max_cleared_level

func mark_level_cleared(p_level: int) -> void:
	max_cleared_level = maxi(max_cleared_level, mini(p_level + 1, MAX_LEVEL))

func star_best(p_level: int) -> int:
	return int(level_stars.get(p_level, 0))

func award_stars(p_level: int, gained: int) -> int:
	var s := clampi(gained, 0, MAX_STARS_PER_LEVEL)
	var best := star_best(p_level)
	if s <= best:
		return 0
	var gain := s - best
	level_stars[p_level] = s
	stars += gain
	stars_changed.emit()
	return gain

func total_stars_earned() -> int:
	var total := 0
	for k in level_stars:
		total += int(level_stars[k])
	return total

func upgrade_level(key: String) -> int:
	return int(upgrades.get(key, 0))

func upgrade_max(key: String) -> int:
	return int(UPGRADE_DEFS.get(key, {}).get("max", 0))

func upgrade_cost(key: String) -> int:
	return int(UPGRADE_DEFS.get(key, {}).get("cost", 0))

func can_buy(key: String) -> bool:
	if not UPGRADE_DEFS.has(key):
		return false
	if upgrade_level(key) >= upgrade_max(key):
		return false
	return stars >= upgrade_cost(key)

func buy_upgrade(key: String) -> bool:
	if not can_buy(key):
		return false
	stars -= upgrade_cost(key)
	upgrades[key] = upgrade_level(key) + 1
	_recompute_derived()
	return true

func _recompute_derived() -> void:
	max_warnings = 3 + upgrade_level("warnings")
	warnings = clampi(warnings, 0, max_warnings)
	inventory_changed.emit()

func remove_item_at(index: int) -> String:
	if index < 0 or index >= inventory.size():
		return ""
	var item_id: String = inventory[index]
	inventory.remove_at(index)
	inventory_changed.emit()
	return item_id

func get_item_def(item_id: String) -> Dictionary:
	return ITEM_DEFS.get(item_id, {})

func set_ability(key: String, value: int = 1) -> void:
	abilities[key] = value

func ability(key: String) -> int:
	return int(abilities.get(key, 0))

func get_phase_label() -> String:
	match phase:
		"morning": return "上午"
		"noon": return "中午"
		"afternoon": return "下午"
		"evening": return "傍晚"
	return "白天"

func get_random_phase() -> void:
	var phases: Array[String] = ["morning", "noon", "afternoon", "evening"]
	phase = phases.pick_random()
