## An active skill an actor can use.
class_name Ability
extends Resource


@export_group("Basic")
## Display name.
@export var name: String
## Tooltip text.
@export var description: String

@export_group("Combat")
## Element used for resist checks.
@export var damage_type: enums.DamageType
## Base magnitude.
@export var power: float = 10.0
@export var mana_cost: int = 0
@export var cooldown: float = 1.0
## 0 = single target.
@export var aoe_radius: float

@export_group("Requirements")
@export var required_class: enums.CharacterClass

@export_group("Combat")
@export var applies_status: enums.StatusEffect
## Per-stat scaling coefficients (nested dict).
@export var scaling: Dictionary

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
