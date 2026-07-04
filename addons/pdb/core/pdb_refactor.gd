@tool
class_name PdbRefactor
extends RefCounted
## Renames a pattern and repoints every reference at it (targeted rewrites only).

static func rename_pattern(db: PatternDatabaseFile, old_id: StringName, new_id: StringName) -> int:
	if db == null:
		return -1
	if new_id == old_id or String(new_id).is_empty():
		return -1
	if not PdbPattern.is_valid_identifier(new_id):
		return -1
	if not db.patterns.has(old_id):
		return -1
	if db.patterns.has(new_id):
		return -1

	var pattern = db.patterns[old_id]
	pattern.id = new_id
	pattern.resource_name = new_id

	db.patterns.erase(old_id)
	db.patterns[new_id] = pattern

	return _rewrite_references(db, old_id, new_id)

static func _rewrite_references(db: PatternDatabaseFile, old_id: StringName, new_id: StringName) -> int:
	var count := 0
	var old_str := String(old_id)
	var new_str := String(new_id)

	for key in db.patterns:
		var p = db.patterns[key]

		if p is PdbModelDefinition:
			if p.extends_type == old_str:
				p.extends_type = new_str
				count += 1
			for field in p.fields:
				if (field.is_enum_field() or field.is_resource_field()) and field.hint_string == old_str:
					field.hint_string = new_str
					count += 1
				elif field.is_array_field() and field.hint == PROPERTY_HINT_ARRAY_TYPE and field.hint_string == old_str:
					field.hint_string = new_str
					count += 1
				elif field.field_type == TYPE_DICTIONARY and field.hint_string == old_str:
					field.hint_string = new_str
					count += 1

		elif p is PdbModelInstance:
			if p.definition_id == old_id:
				p.definition_id = new_id
				p._definition_cache = null
				count += 1
			count += _rewrite_instance_ref_values(db, p, old_id, new_id)

	return count

static func _rewrite_instance_ref_values(db: PatternDatabaseFile, instance: PdbModelInstance, old_id: StringName, new_id: StringName) -> int:
	var count := 0
	instance.set_database(db)
	var definition = instance.get_definition()
	if not definition:
		return 0
	for field in definition.fields:
		if field.is_resource_field() and db.get_pattern(field.hint_string) is PdbModelDefinition:
			var val = instance.data.get(field.field_name)
			if val != null and StringName(str(val)) == old_id:
				instance.data[field.field_name] = new_id
				count += 1
		elif field.is_array_field() and db.get_pattern(field.get_array_element_type()) is PdbModelDefinition:
			var arr = instance.data.get(field.field_name)
			if arr is Array:
				for i in arr.size():
					if arr[i] != null and StringName(str(arr[i])) == old_id:
						arr[i] = new_id
						count += 1
	return count
