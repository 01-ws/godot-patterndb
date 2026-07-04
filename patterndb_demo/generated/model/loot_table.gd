## Weighted drop table.
class_name LootTable
extends Resource


@export_group("Basic")
@export var name: String

@export_group("Drops")
## Item id -> weight (nested dict).
@export var entries: Dictionary
@export var guaranteed: Array[StringName] = []
@export var gold_min: int = 0
@export var gold_max: int = 0
@export var rolls: int = 1

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
