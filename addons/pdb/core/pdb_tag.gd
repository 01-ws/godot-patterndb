@tool
class_name PdbTag
extends RefCounted

var tag_name: String
var parent: PdbTag = null
var children: Array[PdbTag] = []

static func create(name: String) -> PdbTag:
	var t := PdbTag.new()
	t.tag_name = name
	return t

func add_child(child: PdbTag) -> void:
	if not child in children:
		children.append(child)
		child.parent = self

func get_full_path() -> String:
	if parent:
		return parent.get_full_path() + "." + tag_name
	return tag_name

func get_all_children() -> Array[PdbTag]:
	var result: Array[PdbTag] = []
	for child in children:
		result.append(child)
		result.append_array(child.get_all_children())
	return result

func matches(other: PdbTag, exact: bool = true) -> bool:
	if exact:
		return get_full_path() == other.get_full_path()
	var current := other
	while current:
		if current == self:
			return true
		current = current.parent
	current = self
	while current:
		if current == other:
			return true
		current = current.parent
	return false
