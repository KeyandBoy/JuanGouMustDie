extends SceneTree

## 出图后处理：读 tools/_gen/<name>.png -> 可选洋红抠图 -> 裁边 -> 缩放 -> 落盘
## 清单由 tools/gen_art.ps1 写到 tools/_gen/_manifest.json；清单缺失时用内置兜底。
## 运行： godot --headless --path . --script res://tools/post_art.gd

const RAW := "res://tools/_gen"
const MANIFEST := "res://tools/_gen/_manifest.json"

func _init() -> void:
	var entries := _load_manifest()
	if entries.is_empty():
		print("ERR empty manifest")
		quit(1)
		return
	var done := 0
	for e in entries:
		done += _process_one(e)
	print("POST_ART done files=", done, "/", entries.size())
	quit(0)

func _load_manifest() -> Array:
	if FileAccess.file_exists(MANIFEST):
		var txt := FileAccess.get_file_as_string(MANIFEST)
		var parsed = JSON.parse_string(txt)
		if parsed is Array and not parsed.is_empty():
			print("[manifest] ", MANIFEST, " entries=", parsed.size())
			return parsed
		print("WARN manifest unreadable, falling back to builtin list")
	return _builtin_manifest()

func _builtin_manifest() -> Array:
	return [
		{"name": "tyrant_front", "out": "res://art/sprites/tyrant/tyrant_front.png", "key": true, "resize_h": 192},
		{"name": "tyrant_chase", "out": "res://art/sprites/tyrant/tyrant_chase.png", "key": true, "resize_h": 192},
		{"name": "intro_classroom", "out": "res://art/cutscene/intro_classroom.png", "key": false},
		{"name": "intro_board", "out": "res://art/cutscene/intro_board.png", "key": false},
		{"name": "intro_hall", "out": "res://art/cutscene/intro_hall.png", "key": false},
		{"name": "tyrant_p1", "out": "res://art/cutscene/tyrant_p1.png", "key": false},
		{"name": "tyrant_p2", "out": "res://art/cutscene/tyrant_p2.png", "key": false},
		{"name": "tyrant_p3", "out": "res://art/cutscene/tyrant_p3.png", "key": false},
		{"name": "tyrant_p4", "out": "res://art/cutscene/tyrant_p4.png", "key": false},
		{"name": "ending_placeholder", "out": "res://art/cutscene/ending_placeholder.png", "key": false},
	]

func _process_one(e: Dictionary) -> int:
	var name := String(e.get("name", ""))
	var out := String(e.get("out", ""))
	if name == "" or out == "":
		print("  skip bad entry: ", e)
		return 0
	var src := RAW + "/" + name + ".png"
	if not FileAccess.file_exists(src):
		print("  skip (no raw png) ", name)
		return 0
	var img := Image.load_from_file(ProjectSettings.globalize_path(src))
	if img == null:
		print("  ERR load ", src)
		return 0
	img.convert(Image.FORMAT_RGBA8)
	if bool(e.get("key", false)):
		_key_magenta(img)
		img = _trim_to_subject(img)
		img = _fit_height(img, int(e.get("resize_h", 192)))
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := img.save_png(out)
	if err != OK:
		print("  ERR save ", out, " err=", err)
		return 0
	print("  ", name, " -> ", out, " (", img.get_width(), "x", img.get_height(), ")")
	return 1

## 洋红抠图。判据用亮度不变的比值 g/min(r,b)，因为生成图背景有渐晕，
## 固定阈值/欧氏距离会漏掉暗部洋红。
##   ratio < 0.50 全透明；0.50~0.68 羽化；否则保留
func _key_magenta(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var ratio_solid := 0.50
	var ratio_feather := 0.68
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var m := minf(c.r, c.b)
			if m < 0.05:
				continue
			var ratio := c.g / m
			if ratio < ratio_solid:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, 0.0))
			elif ratio < ratio_feather:
				var t := (ratio - ratio_solid) / (ratio_feather - ratio_solid)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * t))

## 按「确定是主体」的像素求包围盒。不能按 alpha>0 求：
## 羽化残留在画面四角仍有 alpha，包围盒会等于整图。
func _trim_to_subject(img: Image) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var m := minf(c.r, c.b)
			if m >= 0.05 and c.g / m < 0.68:
				continue
			if x < minx:
				minx = x
			if x > maxx:
				maxx = x
			if y < miny:
				miny = y
			if y > maxy:
				maxy = y
	if maxx < 0:
		return img
	return img.get_region(Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1))

## 等比缩到目标高度。注意必须 duplicate()+resize()，
## 用 Image.create + blit_rect 是裁剪不是缩放。
func _fit_height(img: Image, target: int) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	if h <= target:
		return img
	var nw := int(round(float(w) * float(target) / float(h)))
	var out := img.duplicate()
	out.resize(nw, target, Image.INTERPOLATE_LANCZOS)
	return out
