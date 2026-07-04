@tool
class_name PdbExporter
extends RefCounted
## Exports instances and whole databases to .tres and type-exact JSON.

static func _log(msg: String) -> void:
	PdbLog.info("Exporter", msg)

static func export_instances_to_tres(db: PatternDatabaseFile, output_dir: String, script_dir: String = "res://data/generated") -> Dictionary:
	_log("Exporting instances to .tres: %s" % output_dir)

	var results: Dictionary = {
		"success": true,
		"files": [],
		"errors": [],
		"skipped": []
	}

	if not DirAccess.dir_exists_absolute(output_dir):
		var err = DirAccess.make_dir_recursive_absolute(output_dir)
		if err != OK:
			results.success = false
			results.errors.append("Failed to create directory: %s" % output_dir)
			return results

	var instances = db.get_all_instances()
	_log("Found %d instances to export" % instances.size())

	var used_names: Dictionary = {}
	var made_dirs: Dictionary = {}
	for instance in instances:
		instance.set_database(db)
		var definition = instance.get_definition()
		if not (definition is PdbModelDefinition):
			definition = db.get_pattern(instance.definition_id)
		if not (definition is PdbModelDefinition):
			results.skipped.append("%s: no definition '%s'" % [instance.id, instance.definition_id])
			_log("Skipping %s: no definition" % instance.id)
			continue

		var tres_content: String
		if instance.source_tres != null and not instance.source_tres.is_empty():
			tres_content = _emit_from_source(instance, definition)
		else:
			tres_content = _generate_tres_content(instance, definition, script_dir, db)

		var sub := _pluralize(str(definition.id).to_snake_case())
		var dest_dir := output_dir.path_join(sub)
		if not made_dirs.has(dest_dir):
			if not DirAccess.dir_exists_absolute(dest_dir):
				DirAccess.make_dir_recursive_absolute(dest_dir)
			made_dirs[dest_dir] = true

		var base_name := str(instance.id).to_snake_case()
		var key := "%s/%s" % [sub, base_name]
		var file_name := base_name
		var n := 2
		while used_names.has("%s/%s" % [sub, file_name]):
			file_name = "%s_%d" % [base_name, n]
			n += 1
		used_names["%s/%s" % [sub, file_name]] = true
		var file_path = dest_dir.path_join(file_name + ".tres")

		var err = _write_file(file_path, tres_content)
		if err == OK:
			results.files.append(file_path)
			_log("Exported: %s" % file_path)
		else:
			results.errors.append("Failed to write: %s" % file_path)

	results.success = results.errors.is_empty()
	return results

static func _pluralize(snake: String) -> String:
	if snake == "":
		return "items"
	var vowels := "aeiou"
	if snake.ends_with("y") and snake.length() >= 2 and not vowels.contains(snake[snake.length() - 2]):
		return snake.substr(0, snake.length() - 1) + "ies"
	if snake.ends_with("s") or snake.ends_with("x") or snake.ends_with("z") or snake.ends_with("ch") or snake.ends_with("sh"):
		return snake + "es"
	return snake + "s"

static func _emit_from_source(instance: PdbModelInstance, definition: PdbModelDefinition) -> String:
	var doc: Dictionary = instance.source_tres.duplicate(true)
	for field in definition.fields:
		var fname := str(field.field_name)
		if not doc.props.has(fname):
			continue
		var pv = doc.props[fname]
		if typeof(pv) == TYPE_DICTIONARY and pv.has("__raw__") and instance.data.has(field.field_name):
			var original = str_to_var(pv["__raw__"])
			var current = instance.data[field.field_name]
			if current != original:
				doc.props[fname] = {"__raw__": var_to_str(current)}
	return PdbImporter.emit_tres_document(doc)

static func _generate_tres_content(instance: PdbModelInstance, definition: PdbModelDefinition, script_dir: String, db: PatternDatabaseFile) -> String:
	var script_path := script_dir.path_join(str(definition.id).to_snake_case() + ".gd")

	var ext_refs: Array = []
	var ext_id_by_path: Dictionary = {}
	var next_id := 2
	for field in definition.fields:
		if not field.is_external_resource():
			continue
		var path := _resource_path_of(instance.get_value(field.field_name))
		if path == "" or ext_id_by_path.has(path):
			continue
		var rtype := field.hint_string
		if rtype == "":
			var loaded := ResourceLoader.load(path)
			rtype = loaded.get_class() if loaded != null else "Resource"
		ext_id_by_path[path] = str(next_id)
		ext_refs.append({"path": path, "type": rtype, "id": str(next_id)})
		next_id += 1

	var lines: PackedStringArray = []
	lines.append("[gd_resource type=\"Resource\" script_class=\"%s\" load_steps=%d format=3]" % [definition.id, 2 + ext_refs.size()])
	lines.append("")
	lines.append("[ext_resource type=\"Script\" path=\"%s\" id=\"1\"]" % script_path)
	for ref in ext_refs:
		var uid_str := ""
		var uid_id := ResourceLoader.get_resource_uid(ref.path)
		if uid_id != ResourceUID.INVALID_ID:
			uid_str = "uid=\"%s\" " % ResourceUID.id_to_text(uid_id)
		lines.append("[ext_resource type=\"%s\" %spath=\"%s\" id=\"%s\"]" % [ref.type, uid_str, ref.path, ref.id])
	lines.append("")
	lines.append("[resource]")
	lines.append("script = ExtResource(\"1\")")
	lines.append("resource_name = \"%s\"" % str(instance.id))
	if db != null and db.export_tags_metadata:
		if instance.tags.size() > 0:
			lines.append("metadata/pdb_tags = %s" % var_to_str(instance.tags))
		if str(instance.description) != "":
			lines.append("metadata/pdb_description = %s" % var_to_str(str(instance.description)))

	for field in definition.fields:
		var value = instance.get_value(field.field_name)
		if field.is_external_resource():
			var path := _resource_path_of(value)
			if path != "" and ext_id_by_path.has(path):
				lines.append("%s = ExtResource(\"%s\")" % [field.field_name, ext_id_by_path[path]])
			continue
		if value == null:
			value = field.get_default()
		var value_str = _value_to_tres(value, field, db)
		if value_str != "":
			lines.append("%s = %s" % [field.field_name, value_str])

	return "\n".join(lines)

static func _resource_path_of(value: Variant) -> String:
	if value is String or value is StringName:
		return str(value)
	if value is Resource:
		return value.resource_path
	return ""

static func _value_to_tres(value: Variant, field: PdbFieldDefinition, db: PatternDatabaseFile = null) -> String:
	if value == null:
		return ""

	if field != null and db != null:
		if field.is_resource_field() and db.get_pattern(field.hint_string) is PdbModelDefinition:
			return "&\"%s\"" % str(value)
		if field.is_array_field() and value is Array:
			var elem := field.get_array_element_type()
			if db.get_pattern(elem) is PdbModelDefinition:
				var ref_items: PackedStringArray = []
				for it in value:
					if it == null:
						continue
					ref_items.append("&\"%s\"" % str(it))
				return "[%s]" % ", ".join(ref_items)

	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			return str(value)
		TYPE_STRING:
			return "\"%s\"" % value.replace("\"", "\\\"")
		TYPE_STRING_NAME:
			return "&\"%s\"" % value
		TYPE_VECTOR2:
			return "Vector2(%s, %s)" % [value.x, value.y]
		TYPE_VECTOR2I:
			return "Vector2i(%d, %d)" % [value.x, value.y]
		TYPE_VECTOR3:
			return "Vector3(%s, %s, %s)" % [value.x, value.y, value.z]
		TYPE_VECTOR3I:
			return "Vector3i(%d, %d, %d)" % [value.x, value.y, value.z]
		TYPE_RECT2:
			return "Rect2(%s, %s, %s, %s)" % [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_COLOR:
			return "Color(%s, %s, %s, %s)" % [value.r, value.g, value.b, value.a]
		TYPE_ARRAY:
			if value.is_empty():
				return "[]"
			var items: PackedStringArray = []
			for item in value:
				items.append(_value_to_tres(item, null, db))
			return "[%s]" % ", ".join(items)
		TYPE_PACKED_STRING_ARRAY:
			if value.is_empty():
				return "PackedStringArray()"
			var items: PackedStringArray = []
			for item in value:
				items.append("\"%s\"" % item)
			return "PackedStringArray(%s)" % ", ".join(items)
		_:
			return var_to_str(value)

static func export_instances_to_json(db: PatternDatabaseFile, output_path: String) -> Dictionary:
	_log("Exporting instances to JSON: %s" % output_path)

	var results: Dictionary = {
		"success": true,
		"files": [],
		"errors": []
	}

	var export_data: Dictionary = {
		"version": db.version,
		"exported_at": Time.get_datetime_string_from_system(),
		"instances": {}
	}

	var instances = db.get_all_instances()

	for instance in instances:
		var instance_data: Dictionary = {
			"id": str(instance.id),
			"definition_id": str(instance.definition_id),
			"tags": Array(instance.tags),
			"description": instance.description,
			"data": {}
		}

		for key in instance.data:
			instance_data.data[str(key)] = _value_to_json(instance.data[key])
		if instance.source_tres != null and not instance.source_tres.is_empty():
			instance_data["source_tres"] = instance.source_tres
		export_data.instances[str(instance.id)] = instance_data

	var json_string = JSON.stringify(export_data, "\t")
	var err = _write_file(output_path, json_string)

	if err == OK:
		results.files.append(output_path)
		_log("Exported %d instances to JSON" % instances.size())
	else:
		results.success = false
		results.errors.append("Failed to write JSON: %s" % output_path)

	return results

static func _value_to_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_INT:
			return {"_type": "int", "value": value}
		TYPE_VECTOR2:
			return {"_type": "Vector2", "x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"_type": "Vector2i", "x": value.x, "y": value.y}
		TYPE_VECTOR3:
			return {"_type": "Vector3", "x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"_type": "Vector3i", "x": value.x, "y": value.y, "z": value.z}
		TYPE_RECT2:
			return {"_type": "Rect2", "x": value.position.x, "y": value.position.y, "w": value.size.x, "h": value.size.y}
		TYPE_COLOR:
			return {"_type": "Color", "r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_STRING_NAME:
			return {"_type": "StringName", "value": str(value)}
		TYPE_OBJECT:
			if value and value.resource_path:
				return {"_type": "Resource", "path": value.resource_path}
			return null
		TYPE_ARRAY:
			var arr = []
			for item in value:
				arr.append(_value_to_json(item))
			return arr
		TYPE_DICTIONARY:
			var entries := []
			for k in value:
				entries.append([_value_to_json(k), _value_to_json(value[k])])
			return {"_type": "Dictionary", "entries": entries}
		TYPE_PACKED_STRING_ARRAY:
			return {"_type": "PackedStringArray", "value": Array(value)}
		TYPE_PACKED_INT32_ARRAY:
			return {"_type": "PackedInt32Array", "value": Array(value)}
		TYPE_PACKED_INT64_ARRAY:
			return {"_type": "PackedInt64Array", "value": Array(value)}
		TYPE_PACKED_FLOAT32_ARRAY:
			return {"_type": "PackedFloat32Array", "value": Array(value)}
		TYPE_PACKED_FLOAT64_ARRAY:
			return {"_type": "PackedFloat64Array", "value": Array(value)}
		TYPE_PACKED_BYTE_ARRAY:
			return {"_type": "PackedByteArray", "value": Array(value)}
		TYPE_PACKED_VECTOR2_ARRAY:
			var vs := []
			for v in value:
				vs.append({"x": v.x, "y": v.y})
			return {"_type": "PackedVector2Array", "value": vs}
		TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_NIL:
			return value
		_:
			return {"_type": "var", "value": var_to_str(value)}

static func export_all_to_json(db: PatternDatabaseFile, output_path: String) -> Dictionary:
	_log("Exporting entire database to JSON: %s" % output_path)

	var results: Dictionary = {
		"success": true,
		"files": [],
		"errors": []
	}

	var export_data: Dictionary = {
		"version": db.version,
		"exported_at": Time.get_datetime_string_from_system(),
		"enums": {},
		"consts": {},
		"definitions": {},
		"instances": {}
	}

	for key in db.patterns:
		var pattern = db.patterns[key]

		if pattern is PdbEnum:
			export_data.enums[str(pattern.id)] = {
				"tags": Array(pattern.tags),
				"description": pattern.description,
				"values": pattern.values.duplicate()
			}
		elif pattern is PdbConst:
			var const_data: Dictionary = {}
			for k in pattern.data:
				const_data[str(k)] = _value_to_json(pattern.data[k])
			export_data.consts[str(pattern.id)] = {
				"tags": Array(pattern.tags),
				"description": pattern.description,
				"data": const_data
			}
		elif pattern is PdbModelDefinition:
			var fields_data: Array = []
			for field in pattern.fields:
				fields_data.append({
					"name": str(field.field_name),
					"type": field.field_type,
					"hint": field.hint,
					"hint_string": field.hint_string,
					"export_group": field.export_group,
					"description": field.description,
					"required": field.required,
					"default_value": _value_to_json(field.default_value)
				})
			export_data.definitions[str(pattern.id)] = {
				"tags": Array(pattern.tags),
				"description": pattern.description,
				"extends_type": pattern.extends_type,
				"icon_name": pattern.icon_name,
				"fields": fields_data
			}
		elif pattern is PdbModelInstance:
			var instance_data: Dictionary = {}
			for k in pattern.data:
				instance_data[str(k)] = _value_to_json(pattern.data[k])
			var inst_json: Dictionary = {
				"definition_id": str(pattern.definition_id),
				"tags": Array(pattern.tags),
				"description": pattern.description,
				"data": instance_data
			}
			if pattern.source_tres != null and not pattern.source_tres.is_empty():
				inst_json["source_tres"] = pattern.source_tres
			export_data.instances[str(pattern.id)] = inst_json

	var json_string = JSON.stringify(export_data, "\t")
	var err = _write_file(output_path, json_string)

	if err == OK:
		results.files.append(output_path)
		_log("Exported entire database to JSON")
	else:
		results.success = false
		results.errors.append("Failed to write JSON: %s" % output_path)

	return results

static func _write_file(path: String, content: String) -> Error:
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(content)
	file.close()
	return OK
