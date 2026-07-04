## Standing between two factions.
class_name FactionRelation
extends Resource


@export_group("Basic")
@export var faction_a: enums.Faction
@export var faction_b: enums.Faction

@export_group("Relation")
## -100 hostile .. +100 allied.
@export var standing: int
@export var at_war: bool
## Contextual standing modifiers.
@export var modifiers: Dictionary

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
