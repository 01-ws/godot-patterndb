## Single-use item.
class_name Consumable
extends Item


@export_group("Effect")
@export var heal_amount: int
@export var restores_mana: int
@export var applies_status: enums.StatusEffect
## Effect duration in seconds.
@export var duration: float

@export_group("Basic")
@export var stack_size: int = 1

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
