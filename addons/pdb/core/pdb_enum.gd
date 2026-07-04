@tool
class_name PdbEnum
extends PdbPattern

@export var values: Dictionary = {}

func get_value(key: StringName) -> int:
	return values.get(key, -1)

func _get(property: StringName) -> Variant:
	return values.get(property)

func add_item(name: StringName, value: int = -1) -> void:
	if not PdbPattern.is_valid_identifier(name):
		PdbLog.error("Enum", "Invalid enum item name (empty or containing '/' '\\').")
		return
	if value == -1:
		var max_val = -1
		for v in values.values():
			if v > max_val: max_val = v
		value = max_val + 1

	values[name] = value
	emit_changed()

func remove_item(name: StringName) -> void:
	values.erase(name)
	emit_changed()

func rename_item(old_name: StringName, new_name: StringName) -> void:
	if not values.has(old_name):
		return
	if values.has(new_name):
		return
	if not PdbPattern.is_valid_identifier(new_name):
		return
	var val = values[old_name]
	values.erase(old_name)
	values[new_name] = val
	emit_changed()

func set_item_value(name: StringName, value: int) -> void:
	if values.has(name):
		values[name] = value
		emit_changed()

func get_names() -> PackedStringArray:
	var names = PackedStringArray()
	for key in values:
		names.append(key)
	return names

func get_name_for_value(value: int) -> StringName:
	for key in values:
		if values[key] == value:
			return key
	return &""

func size() -> int:
	return values.size()
