## A hostile actor.
class_name Enemy
extends Resource


@export_group("Basic")
@export var name: String

@export_group("Stats")
@export var level: int = 1
@export var health: int = 10

@export_group("Basic")
@export var faction: enums.Faction

@export_group("AI")
@export var behavior: enums.AIBehavior

@export_group("Basic")
@export var is_boss: bool

@export_group("Combat")
@export var abilities: Array[StringName] = []

@export_group("Rewards")
@export var loot_table: StringName

@export_group("Presentation")
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
