## A weapon that fires projectiles (3rd inheritance level).
class_name RangedWeapon
extends Weapon


@export_group("Ranged")
@export var range: float = 20.0
@export var projectile_speed: float = 30.0
## Cone spread in degrees.
@export var spread_degrees: float = 2.0
## Consumed ammunition (item reference).
@export var ammo_item: StringName

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
