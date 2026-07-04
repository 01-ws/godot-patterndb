## A playable or party character.
class_name Character
extends Resource


@export_group("Basic")
@export var name: String
@export var char_class: enums.CharacterClass

@export_group("Loadout")
@export var starting_weapon: StringName
@export var starting_abilities: Array[StringName] = []

@export_group("Progression")
@export var skills: Array[StringName] = []

@export_group("Stats")
## Named base stats (nested dict; try the Table nesting slider).
@export var stats: Dictionary

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
