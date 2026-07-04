@tool
class_name PdbModelDefinition
extends PdbPattern

@export var fields: Array[PdbFieldDefinition] = []

@export var extends_type: String = "Resource"

@export var icon_name: String = "Object"

signal field_added(field: PdbFieldDefinition)
signal field_removed(index: int)
signal field_moved(from_index: int, to_index: int)
signal fields_changed

func add_field(field: PdbFieldDefinition) -> void:
	if not field:
		return
	if not PdbPattern.is_valid_identifier(field.field_name):
		PdbLog.warn("ModelDef", "Invalid field name (empty or containing '/' '\\').")
		return
	if has_field(field.field_name):
		PdbLog.warn("ModelDef", "Field '%s' already exists" % field.field_name)
		return
	fields.append(field)
	field_added.emit(field)
	fields_changed.emit()
	emit_changed()

func insert_field(index: int, field: PdbFieldDefinition) -> void:
	if not field:
		return
	if not PdbPattern.is_valid_identifier(field.field_name):
		PdbLog.warn("ModelDef", "Invalid field name (empty or containing '/' '\\').")
		return
	if has_field(field.field_name):
		PdbLog.warn("ModelDef", "Field '%s' already exists" % field.field_name)
		return
	index = clampi(index, 0, fields.size())
	fields.insert(index, field)
	field_added.emit(field)
	fields_changed.emit()
	emit_changed()

func remove_field(index: int) -> void:
	if index < 0 or index >= fields.size():
		return
	fields.remove_at(index)
	field_removed.emit(index)
	fields_changed.emit()
	emit_changed()

func remove_field_by_name(field_name: StringName) -> void:
	for i in range(fields.size()):
		if fields[i].field_name == field_name:
			remove_field(i)
			return

func move_field(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= fields.size():
		return
	if to_index < 0 or to_index >= fields.size():
		return
	if from_index == to_index:
		return
	var field = fields[from_index]
	fields.remove_at(from_index)
	fields.insert(to_index, field)
	field_moved.emit(from_index, to_index)
	fields_changed.emit()
	emit_changed()

func get_field(field_name: StringName) -> PdbFieldDefinition:
	for field in fields:
		if field.field_name == field_name:
			return field
	return null

func get_field_at(index: int) -> PdbFieldDefinition:
	if index < 0 or index >= fields.size():
		return null
	return fields[index]

func has_field(field_name: StringName) -> bool:
	for field in fields:
		if field.field_name == field_name:
			return true
	return false

func get_field_count() -> int:
	return fields.size()

func get_field_names() -> PackedStringArray:
	var names = PackedStringArray()
	for field in fields:
		names.append(field.field_name)
	return names

func get_fields_in_group(group_name: String) -> Array[PdbFieldDefinition]:
	var result: Array[PdbFieldDefinition] = []
	for field in fields:
		if field.export_group == group_name:
			result.append(field)
	return result

func get_export_groups() -> PackedStringArray:
	var groups = PackedStringArray()
	var seen: Dictionary = {}
	for field in fields:
		if field.export_group != "" and not seen.has(field.export_group):
			groups.append(field.export_group)
			seen[field.export_group] = true
	return groups

func create_default_data() -> Dictionary:
	var data: Dictionary = {}
	for field in fields:
		data[field.field_name] = field.get_default()
	return data

func validate_data(data: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	for field in fields:
		if not data.has(field.field_name):
			if field.required:
				errors.append("Missing required field: %s" % field.field_name)
			continue
		if not field.validate_value(data[field.field_name]):
			errors.append("Invalid value for field: %s" % field.field_name)
	return errors

func get_property_list_for_instance() -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	var current_group: String = ""

	for field in fields:
		if field.export_group != current_group:
			current_group = field.export_group
			if current_group != "":
				props.append({
					"name": current_group,
					"type": TYPE_NIL,
					"usage": PROPERTY_USAGE_GROUP
				})
		props.append(field.get_property_info())

	return props

func duplicate_definition() -> PdbModelDefinition:
	var copy = PdbModelDefinition.new()
	copy.id = id
	copy.tags = tags.duplicate()
	copy.description = description
	copy.extends_type = extends_type
	copy.icon_name = icon_name
	for field in fields:
		copy.fields.append(field.duplicate_field())
	return copy

func get_enum_field_names() -> PackedStringArray:
	var names = PackedStringArray()
	for field in fields:
		if field.is_enum_field():
			names.append(field.field_name)
	return names

func get_resource_field_names() -> PackedStringArray:
	var names = PackedStringArray()
	for field in fields:
		if field.is_resource_field():
			names.append(field.field_name)
	return names

func _to_string() -> String:
	return "<PdbModelDefinition:%s (%d fields)>" % [id, fields.size()]
