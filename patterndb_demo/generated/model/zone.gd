## A playable area of the map.
class_name Zone
extends Resource


@export_group("Basic")
@export var name: String
@export var biome: enums.Biome

@export_group("Difficulty")
@export var min_level: int = 1
@export var max_level: int = 10

@export_group("Content")
@export var merchants: Array[StringName] = []

@export_group("Presentation")
@export var ambient_color: Color

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
