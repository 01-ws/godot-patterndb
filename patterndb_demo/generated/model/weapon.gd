## A wieldable weapon.
class_name Weapon
extends Item


@export_group("Combat")
@export var weapon_type: enums.WeaponType
@export var damage_type: enums.DamageType
@export var base_damage: float = 5.0
@export var attack_speed: float = 1.0
@export var two_handed: bool

@export_group("Effects")
## Cross-instance reference to an Ability.
@export var granted_ability: StringName

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
