class_name ItemDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""
@export var color: Color = Color.WHITE
@export var stack_max: int = 1
@export var kind: String = "consumable"

static func from_dict(item_id: String, data: Dictionary) -> ItemDef:
	var def := ItemDef.new()
	def.id = item_id
	def.display_name = String(data.get("name", item_id))
	def.description = String(data.get("desc", ""))
	def.color = data.get("color", Color.WHITE)
	def.stack_max = maxi(1, int(data.get("stack_max", 1)))
	def.kind = String(data.get("kind", "consumable"))
	return def
