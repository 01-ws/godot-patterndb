## An unlockable achievement.
class_name Achievement
extends Resource


@export_group("Basic")
@export var title: String
@export var description: String
@export var points: int = 10
@export var hidden: bool

@export_group("Rewards")
@export var reward_item: StringName

@export_group("Unlock")
@export var required_quest: StringName

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
