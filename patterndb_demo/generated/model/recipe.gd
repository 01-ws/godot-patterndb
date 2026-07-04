## A crafting recipe.
class_name Recipe
extends Resource


@export_group("Basic")
@export var name: String

@export_group("Craft")
@export var result: StringName
@export var ingredients: Array[StringName] = []
## Ingredient id -> count (nested dict).
@export var quantities: Dictionary
@export var station: enums.MerchantType
@export var craft_time: float = 2.0

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
