## One line in a branching conversation.
class_name DialogueNode
extends Resource


@export_group("Basic")
## Speaker id (StringName field).
@export var speaker: StringName
@export var text: String
@export var mood: enums.StatusEffect

@export_group("Flow")
## Reply text -> next node id (nested dict).
@export var responses: Dictionary
## Self-referential dialogue tree.
@export var next_nodes: Array[StringName] = []

@export_group("Presentation")
@export var portrait: Texture2D

func get_tags() -> PackedStringArray:
	return get_meta(&"pdb_tags", PackedStringArray())

func has_tag(tag: StringName) -> bool:
	var q := String(tag)
	for t in get_tags():
		var s := String(t)
		if s == q or s.begins_with(q + "."):
			return true
	return false
