## A journal quest.
class_name Quest
extends Resource


@export_group("Basic")
@export var name: String
@export var quest_type: enums.QuestType

@export_group("Flow")
@export var giver: StringName
## Self-referential quest chain.
@export var prerequisite: StringName

@export_group("Rewards")
@export var reward_item: StringName
@export var reward_gold: int

@export_group("Flow")
@export var objectives: PackedStringArray
## Objective id -> completed bool.
@export var stage_flags: Dictionary
@export var turn_in_biome: enums.Biome

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
