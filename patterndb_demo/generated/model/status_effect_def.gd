## Data for a buff/debuff.
class_name StatusEffectDef
extends Resource


@export_group("Basic")
@export var name: String
@export var effect: enums.StatusEffect

@export_group("Combat")
@export var tick_damage: float
@export var duration: float = 3.0
@export var stacks: bool
## Flat stat modifiers while active.
@export var modifiers: Dictionary

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
