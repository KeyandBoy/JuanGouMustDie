extends Node

## 开发者版开关中心。
##
## 规则（很重要，别绕开）：
##   1. 任何"只在开发者版出现"的行为，都必须在这里加一个字段；
##   2. 正式版 = 导出 release 后 OS.is_debug_build() 为 false，这里全部自动关闭，
##      不需要手动记得关；
##   3. 新增字段后在 开发记录.md「开发者版 / 正式版差异清单」登记一行。
##
## 开发时：F1 切换视锥/寻路显示（仅 debug build 生效）。

var enabled := false
var show_vision_cones := false
var show_paths := false
var show_room_heat := false
var import_bank := true
var unlock_all_levels := true

const CATCH_RADIUS_PRESETS := [22.0, 26.0, 30.0, 36.0, 44.0]
var catch_radius_idx := 2

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = OS.is_debug_build()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F1:
		show_vision_cones = not show_vision_cones
		show_paths = show_vision_cones
		get_viewport().set_input_as_handled()
		print("[DevMode] vision cones=", show_vision_cones)
	elif event.keycode == KEY_F2:
		show_room_heat = not show_room_heat
		get_viewport().set_input_as_handled()
		print("[DevMode] room heat=", show_room_heat)
	elif event.keycode == KEY_F3:
		catch_radius_idx = (catch_radius_idx + 1) % CATCH_RADIUS_PRESETS.size()
		apply_catch_radius()
		get_viewport().set_input_as_handled()
		print("[DevMode] catch radius=", CATCH_RADIUS_PRESETS[catch_radius_idx])

func catch_radius() -> float:
	return CATCH_RADIUS_PRESETS[catch_radius_idx]

## 把当前档位的抓人半径同步到场景里所有守卫
func apply_catch_radius() -> void:
	if not enabled:
		return
	for s in get_tree().get_nodes_in_group("students"):
		if is_instance_valid(s):
			s.catch_radius = catch_radius()

func status_text() -> String:
	var parts := PackedStringArray()
	if show_vision_cones:
		parts.append("视锥+抓人圈 r=%d" % int(catch_radius()))
	if show_room_heat:
		parts.append("房间热度")
	if parts.is_empty():
		return "DEV"
	return "DEV · " + ", ".join(parts)
