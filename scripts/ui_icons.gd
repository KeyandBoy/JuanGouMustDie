class_name UiIcons
extends Object

## UI 图标加载器：存在才 load，缺图返回 null 由调用方回退文字/色块。
## 图标由 tools/gen_art.ps1 + tools/manifests/ui_icons.json 生成到 art/ui/icons/。

static var _cache: Dictionary = {}

static func item(id: String) -> Texture2D:
	return _load("res://art/ui/icons/%s.png" % id)

static func lock() -> Texture2D:
	return _load("res://art/ui/icons/lock.png")

static func star() -> Texture2D:
	return _load("res://art/ui/icons/star.png")

static func speaker() -> Texture2D:
	return _load("res://art/ui/icons/speaker.png")

static func music() -> Texture2D:
	return _load("res://art/ui/icons/music.png")

static func _load(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_cache[path] = tex
	return tex
