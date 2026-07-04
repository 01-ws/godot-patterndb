## Wearable protection.
class_name Armor
extends Item


@export_group("Basic")
@export var slot: enums.EquipSlot
@export var material: enums.ArmorMaterial

@export_group("Defense")
@export var armor_value: int
## Element -> reduction fraction (nested dict).
@export var resistances: Dictionary

@export_group("Sets")
## Other Armor instances in the same set.
@export var set_pieces: Array[StringName] = []

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
