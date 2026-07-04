## A node in a branching skill tree.
class_name SkillNode
extends Resource


@export_group("Basic")
@export var name: String
@export var category: enums.SkillCategory
@export var cost: int = 1

@export_group("Tree")
## Self-referential: nodes required first.
@export var prerequisites: Array[StringName] = []

@export_group("Grants")
@export var grants_ability: StringName

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
