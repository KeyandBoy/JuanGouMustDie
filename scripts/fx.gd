class_name Fx
extends RefCounted

## 统一反馈管线：一次调用 = 一层反馈，调用方按需叠加。
## 设计约定见 `参考清单_实施指南.md` 的 A1 表。
##
## 为什么要有这个类：
##   main.gd 里已经有 `_fx_flash` / `_shake_camera`，但每个动作都在手写组合，
##   导致「被抓」有 6 层反馈、「答对」只有 1 层。把常用的几层封装成静态函数后，
##   任何新动作都能用 2~4 行拿到同等强度的反馈。
##
## 用法：
##   Fx.flash(self, Color(0.55, 0.95, 0.66), 0.10, 0.26)
##   Fx.shake(self, 1)
##   Fx.hitstop(3)
##   Fx.sprite_flash(player.sprite)

## 震屏档位：0 极轻 / 1 轻 / 2 重 / 3 Boss
const SHAKE_TIERS := [
	Vector2(2.0, 0.08),
	Vector2(4.0, 0.18),
	Vector2(8.0, 0.34),
	Vector2(14.0, 0.6),
]

## 全屏色闪（复用 main.gd 的 _fx_flash）
static func flash(main: Node, col: Color, peak := 0.18, dur := 0.22) -> void:
	if main == null or not is_instance_valid(main) or not main.has_method("_fx_flash"):
		return
	main._fx_flash(col, peak, dur)

## 震屏（复用 main.gd 的 _shake_camera，避免两套实现）
static func shake(main: Node, tier := 1) -> void:
	if main == null or not is_instance_valid(main) or not main.has_method("_shake_camera"):
		return
	var cfg: Vector2 = SHAKE_TIERS[clampi(tier, 0, SHAKE_TIERS.size() - 1)]
	main._shake_camera(cfg.x, cfg.y)

## 顿帧：把引擎时间压慢几帧再恢复。
## 只在「打中/被打中/过关」用；答题不要用，会打断输入节奏。
static func hitstop(frames := 3, slow := 0.05) -> void:
	if Engine.time_scale < 1.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	Engine.time_scale = slow
	# 第 4 个参数 ignore_time_scale = true，否则计时器自己也会被慢放 20 倍
	await tree.create_timer(0.016 * float(frames), true, false, true).timeout
	Engine.time_scale = 1.0

## 角色受击/情绪闪白。modulate 可以超过 1，不改 shader 也能过曝成白色。
static func sprite_flash(item: CanvasItem, col := Color(6, 6, 6), dur := 0.12) -> void:
	if item == null or not is_instance_valid(item):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var base := item.modulate
	item.modulate = col
	var tw := tree.create_tween()
	tw.tween_property(item, "modulate", base, dur)
