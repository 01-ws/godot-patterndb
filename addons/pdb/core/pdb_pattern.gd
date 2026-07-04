@tool
class_name PdbPattern
extends Resource
## Base pattern: id, tags, description.

@export var id: StringName

@export var tags: PackedStringArray = []

@export var description: String = ""

func has_tag(tag: String) -> bool:
	return tag in tags

func add_tag(tag: String) -> void:
	var clean := tag.strip_edges()
	if clean != "" and not (clean in tags):
		tags.append(clean)

func remove_tag(tag: String) -> void:
	var i := tags.find(tag)
	if i != -1:
		tags.remove_at(i)

func _to_string() -> String:
	return "<PdbPattern:%s>" % id

static func is_valid_identifier(name) -> bool:
	return String(name).is_valid_identifier()
