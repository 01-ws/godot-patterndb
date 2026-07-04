## Base item every pickup inherits from.
class_name Item
extends Resource


@export_group("Basic")
## Display name.
@export var name: String
@export var description: String
@export var rarity: enums.ItemRarity

@export_group("Economy")
## Base vendor value in gold.
@export var value: int

@export_group("Basic")
@export var weight: float = 1.0
@export var is_unique: bool

@export_group("Presentation")
## Engine resource reference (stored as a res:// path).
@export var icon: Texture2D
@export var tint: Color

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
