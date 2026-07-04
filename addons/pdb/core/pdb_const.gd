@tool
class_name PdbConst
extends PdbPattern

@export var data: Dictionary = {}

func _get(property: StringName) -> Variant:
	return data.get(property)

func set_const(key: StringName, value: Variant) -> void:
	if not PdbPattern.is_valid_identifier(key):
		PdbLog.error("Const", "Invalid const key (empty or containing '/' '\\').")
		return
	data[key] = value
	emit_changed()

func get_const(key: StringName) -> Variant:
	return data.get(key)

func remove_const(key: StringName) -> void:
	data.erase(key)
	emit_changed()

func has_const(key: StringName) -> bool:
	return data.has(key)

func get_keys() -> PackedStringArray:
	var keys = PackedStringArray()
	for key in data:
		keys.append(key)
	return keys

func size() -> int:
	return data.size()
