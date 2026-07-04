@tool
class_name PdbValidator
extends RefCounted
## Database and instance validation, plus reference lookup.

enum Severity {
	INFO,
	WARNING,
	ERROR
}

class ValidationIssue:
	var severity: Severity
	var pattern_id: StringName
	var field_name: StringName
	var message: String

	func _init(p_severity: Severity, p_pattern: StringName, p_field: StringName, p_message: String) -> void:
		severity = p_severity
		pattern_id = p_pattern
		field_name = p_field
		message = p_message

	func _to_string() -> String:
		var sev_str = "INFO" if severity == Severity.INFO else ("WARN" if severity == Severity.WARNING else "ERROR")
		if field_name != &"":
			return "[%s] %s.%s: %s" % [sev_str, pattern_id, field_name, message]
		return "[%s] %s: %s" % [sev_str, pattern_id, message]

static func _log(msg: String) -> void:
	PdbLog.info("Validator", msg)

static func validate_database(db: PatternDatabaseFile) -> Array[ValidationIssue]:
	_log("Validating entire database")
	var issues: Array[ValidationIssue] = []

	issues.append_array(_validate_enums(db))
	issues.append_array(_validate_definitions(db))
	issues.append_array(_validate_instances(db))
	issues.append_array(_validate_references(db))

	var error_count = 0
	var warn_count = 0
	for issue in issues:
		if issue.severity == Severity.ERROR:
			error_count += 1
		elif issue.severity == Severity.WARNING:
			warn_count += 1

	_log("Validation complete: %d errors, %d warnings" % [error_count, warn_count])
	return issues

static func _validate_enums(db: PatternDatabaseFile) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []

	for key in db.patterns:
		var pattern = db.patterns[key]
		if not pattern is PdbEnum:
			continue

		var pdb_enum = pattern as PdbEnum

		if pdb_enum.values.is_empty():
			issues.append(ValidationIssue.new(
				Severity.WARNING,
				pdb_enum.id,
				&"",
				"Enum has no values"
			))

		var seen_values: Dictionary = {}
		for name in pdb_enum.values:
			var val = pdb_enum.values[name]
			if seen_values.has(val):
				issues.append(ValidationIssue.new(
					Severity.WARNING,
					pdb_enum.id,
					&"",
					"Duplicate value %d for '%s' and '%s'" % [val, seen_values[val], name]
				))
			seen_values[val] = name

	return issues

static func _validate_definitions(db: PatternDatabaseFile) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []

	for key in db.patterns:
		var pattern = db.patterns[key]
		if not pattern is PdbModelDefinition:
			continue

		var definition = pattern as PdbModelDefinition

		if definition.fields.is_empty():
			issues.append(ValidationIssue.new(
				Severity.INFO,
				definition.id,
				&"",
				"Definition has no fields"
			))

		var seen_names: Dictionary = {}
		for field in definition.fields:
			if seen_names.has(field.field_name):
				issues.append(ValidationIssue.new(
					Severity.ERROR,
					definition.id,
					field.field_name,
					"Duplicate field name"
				))
			seen_names[field.field_name] = true

			if field.is_enum_field():
				var enum_name = field.hint_string
				if not db.has_pattern(enum_name):
					issues.append(ValidationIssue.new(
						Severity.ERROR,
						definition.id,
						field.field_name,
						"References unknown enum: %s" % enum_name
					))
				elif not db.get_pattern(enum_name) is PdbEnum:
					issues.append(ValidationIssue.new(
						Severity.ERROR,
						definition.id,
						field.field_name,
						"'%s' is not an enum" % enum_name
					))

	return issues

static func _validate_instances(db: PatternDatabaseFile) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []

	for key in db.patterns:
		var pattern = db.patterns[key]
		if not pattern is PdbModelInstance:
			continue
		issues.append_array(_validate_single_instance(pattern as PdbModelInstance, db, true))

	return issues

static func _validate_single_instance(instance: PdbModelInstance, db: PatternDatabaseFile, include_orphans: bool) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []
	instance.set_database(db)

	if instance.id == &"":
		issues.append(ValidationIssue.new(Severity.ERROR, instance.id, &"", "Instance ID cannot be empty"))

	if instance.definition_id == &"":
		issues.append(ValidationIssue.new(Severity.ERROR, instance.id, &"", "No definition assigned"))
		return issues

	var definition = instance.get_definition()
	if not definition:
		issues.append(ValidationIssue.new(Severity.ERROR, instance.id, &"", "Definition '%s' not found" % instance.definition_id))
		return issues

	for field in definition.fields:
		var value = instance.get_value(field.field_name)

		if value == null and field.required:
			issues.append(ValidationIssue.new(Severity.ERROR, instance.id, field.field_name, "Required field is missing"))
			continue

		if value != null and not _type_matches(value, field, db):
			issues.append(ValidationIssue.new(
				Severity.WARNING,
				instance.id,
				field.field_name,
				"Type mismatch: expected %s, got %s" % [type_string(field.field_type), type_string(typeof(value))]
			))

		if field.is_enum_field() and value != null:
			var pdb_enum = db.get_pattern(field.hint_string) as PdbEnum
			if pdb_enum:
				var found = false
				for v in pdb_enum.values.values():
					if v == int(value):
						found = true
						break
				if not found:
					issues.append(ValidationIssue.new(
						Severity.WARNING,
						instance.id,
						field.field_name,
						"Enum value %d not found in %s" % [value, field.hint_string]
					))

	if include_orphans:
		for data_key in instance.data:
			if not definition.has_field(data_key):
				issues.append(ValidationIssue.new(
					Severity.INFO,
					instance.id,
					data_key,
					"Field not in definition (orphaned data)"
				))

	return issues

static func _type_matches(value: Variant, field: PdbFieldDefinition, db: PatternDatabaseFile = null) -> bool:
	var value_type = typeof(value)

	if db != null:
		if field.is_resource_field() and db.get_pattern(field.hint_string) is PdbModelDefinition:
			return value is String or value is StringName
		if field.is_array_field() and db.get_pattern(field.get_array_element_type()) is PdbModelDefinition:
			return value is Array

	if value_type == field.field_type:
		return true

	if field.field_type == TYPE_OBJECT and value is Object:
		return true

	if field.field_type == TYPE_INT and value_type == TYPE_FLOAT:
		return true
	if field.field_type == TYPE_FLOAT and value_type == TYPE_INT:
		return true

	return false

static func _validate_references(db: PatternDatabaseFile) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []

	for key in db.patterns:
		var pattern = db.patterns[key]
		if not pattern is PdbModelInstance:
			continue
		issues.append_array(_validate_instance_references(pattern as PdbModelInstance, db, true))

	return issues

static func _validate_instance_references(instance: PdbModelInstance, db: PatternDatabaseFile, include_resource_notes: bool) -> Array[ValidationIssue]:
	var issues: Array[ValidationIssue] = []
	instance.set_database(db)
	var definition = instance.get_definition()
	if not definition:
		return issues

	for field in definition.fields:
		if field.is_resource_field():
			var value = instance.get_value(field.field_name)
			if value == null or value is Dictionary:
				continue
			if value is String or value is StringName:
				var p := str(value)
				if p.begins_with("res://") and not ResourceLoader.exists(p):
					issues.append(ValidationIssue.new(Severity.INFO, instance.id, field.field_name, "Referenced resource not in this project: %s" % p))
			elif include_resource_notes and value is Resource and value.resource_path.is_empty():
				issues.append(ValidationIssue.new(Severity.INFO, instance.id, field.field_name, "Resource has no saved path"))
		elif field.is_array_field():
			var arr = instance.get_value(field.field_name)
			if not (arr is Array):
				continue
			for element in arr:
				if element is String or element is StringName:
					var ep := str(element)
					if ep.begins_with("res://") and not ResourceLoader.exists(ep):
						issues.append(ValidationIssue.new(Severity.INFO, instance.id, field.field_name, "Referenced resource not in this project: %s" % ep))

	return issues

static func validate_instance(instance: PdbModelInstance, db: PatternDatabaseFile) -> Array[ValidationIssue]:
	var issues := _validate_single_instance(instance, db, false)
	issues.append_array(_validate_instance_references(instance, db, false))
	return issues

static func get_references_to(pattern_id: StringName, db: PatternDatabaseFile) -> Array[Dictionary]:
	var refs: Array[Dictionary] = []

	for key in db.patterns:
		var pattern = db.patterns[key]

		if pattern is PdbModelInstance:
			if pattern.definition_id == pattern_id:
				refs.append({
					"pattern_id": pattern.id,
					"reference_type": "definition",
					"field_name": ""
				})

			var definition = pattern.get_definition()
			if definition:
				for field in definition.fields:
					if field.is_enum_field() and field.hint_string == str(pattern_id):
						refs.append({
							"pattern_id": pattern.id,
							"reference_type": "enum_field",
							"field_name": str(field.field_name)
						})
						continue
					if field.is_resource_field() and db.get_pattern(field.hint_string) is PdbModelDefinition:
						var val = pattern.data.get(field.field_name)
						if val != null and str(val) == str(pattern_id):
							refs.append({
								"pattern_id": pattern.id,
								"reference_type": "instance_ref",
								"field_name": str(field.field_name)
							})
					elif field.is_array_field() and db.get_pattern(field.get_array_element_type()) is PdbModelDefinition:
						var arr = pattern.data.get(field.field_name)
						if arr is Array:
							for element in arr:
								if element != null and str(element) == str(pattern_id):
									refs.append({
										"pattern_id": pattern.id,
										"reference_type": "instance_ref[]",
										"field_name": str(field.field_name)
									})
									break

		elif pattern is PdbModelDefinition:
			for field in pattern.fields:
				if field.is_enum_field() and field.hint_string == str(pattern_id):
					refs.append({
						"pattern_id": pattern.id,
						"reference_type": "enum_field_definition",
						"field_name": str(field.field_name)
					})
				elif field.is_resource_field() and field.hint_string == str(pattern_id):
					refs.append({
						"pattern_id": pattern.id,
						"reference_type": "ref_field_definition",
						"field_name": str(field.field_name)
					})
				elif field.is_array_field() and field.hint == PROPERTY_HINT_ARRAY_TYPE and field.hint_string == str(pattern_id):
					refs.append({
						"pattern_id": pattern.id,
						"reference_type": "ref_array_definition",
						"field_name": str(field.field_name)
					})

	return refs

static func can_delete_pattern(pattern_id: StringName, db: PatternDatabaseFile) -> Dictionary:
	var refs = get_references_to(pattern_id, db)
	return {
		"can_delete": refs.is_empty(),
		"references": refs
	}
