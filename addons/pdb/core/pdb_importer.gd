@tool
class_name PdbImporter
extends RefCounted
## Imports enums, definitions, and instances from GDScript, .tres, JSON, and CSV.

static func _log(msg: String) -> void:
	PdbLog.info("Importer", msg)

static func import_enums_from_gdscript(file_path: String, db: PatternDatabaseFile) -> Dictionary:
	_log("Importing enums from: %s" % file_path)

	var results: Dictionary = {
		"success": true,
		"imported": [],
		"errors": [],
		"skipped": []
	}

	if not FileAccess.file_exists(file_path):
		results.success = false
		results.errors.append("File not found: %s" % file_path)
		return results

	var content = FileAccess.get_file_as_string(file_path)
	var lines = content.split("\n")

	var current_enum_name: String = ""
	var current_enum_values: Dictionary = {}
	var in_enum_block: bool = false
	var brace_depth: int = 0

	for line in lines:
		var stripped = line.strip_edges()
		var comment_pos = stripped.find("#")
		if comment_pos != -1:
			stripped = stripped.substr(0, comment_pos).strip_edges()
		if stripped.is_empty():
			continue

		if stripped.begins_with("enum "):
			var enum_match = stripped.substr(5).strip_edges()
			var brace_pos = enum_match.find("{")
			if brace_pos > 0:
				current_enum_name = enum_match.substr(0, brace_pos).strip_edges()
				in_enum_block = true
				brace_depth = 1
				current_enum_values = {}
				_log("Found enum: %s" % current_enum_name)

				var after_brace = enum_match.substr(brace_pos + 1).strip_edges()
				if after_brace.ends_with("}"):
					after_brace = after_brace.substr(0, after_brace.length() - 1)
					_parse_enum_line(after_brace, current_enum_values)
					_finalize_enum(current_enum_name, current_enum_values, db, results)
					in_enum_block = false
					current_enum_name = ""
				elif not after_brace.is_empty():
					_parse_enum_line(after_brace, current_enum_values)
		elif in_enum_block:
			if stripped.ends_with("}"):
				var before_brace = stripped.substr(0, stripped.length() - 1).strip_edges()
				if not before_brace.is_empty():
					_parse_enum_line(before_brace, current_enum_values)
				_finalize_enum(current_enum_name, current_enum_values, db, results)
				in_enum_block = false
				current_enum_name = ""
			elif not stripped.is_empty() and not stripped.begins_with("#"):
				_parse_enum_line(stripped, current_enum_values)

	results.success = results.errors.is_empty()
	_log("Import complete: %d enums imported" % results.imported.size())
	return results

static func _parse_enum_line(line: String, values: Dictionary) -> void:
	var entries = line.split(",")
	for entry in entries:
		entry = entry.strip_edges()
		if entry.is_empty():
			continue

		var eq_pos = entry.find("=")
		if eq_pos > 0:
			var name = entry.substr(0, eq_pos).strip_edges()
			var val_str = entry.substr(eq_pos + 1).strip_edges()
			var val = int(val_str) if val_str.is_valid_int() else values.size()
			values[name] = val
		else:
			var next_val = 0
			if not values.is_empty():
				for v in values.values():
					if v >= next_val:
						next_val = v + 1
			values[entry] = next_val

static func _finalize_enum(name: String, values: Dictionary, db: PatternDatabaseFile, results: Dictionary) -> void:
	if name.is_empty() or values.is_empty():
		return

	if db.has_pattern(name):
		results.skipped.append("%s: already exists" % name)
		_log("Skipping %s: already exists" % name)
		return

	var pdb_enum = PdbEnum.new()
	pdb_enum.id = name
	pdb_enum.values = values
	db.add_pattern(pdb_enum)
	results.imported.append(name)
	_log("Imported enum: %s (%d values)" % [name, values.size()])

static func import_from_json(file_path: String, db: PatternDatabaseFile) -> Dictionary:
	_log("Importing from JSON: %s" % file_path)

	var results: Dictionary = {
		"success": true,
		"imported": {
			"enums": 0,
			"consts": 0,
			"definitions": 0,
			"instances": 0
		},
		"errors": [],
		"skipped": []
	}

	if not FileAccess.file_exists(file_path):
		results.success = false
		results.errors.append("File not found: %s" % file_path)
		return results

	var content = FileAccess.get_file_as_string(file_path)
	var json = JSON.new()
	var parse_result = json.parse(content)

	if parse_result != OK:
		results.success = false
		results.errors.append("JSON parse error: %s" % json.get_error_message())
		return results

	var data = json.data

	if data.has("enums"):
		for enum_id in data.enums:
			if not PdbPattern.is_valid_identifier(enum_id):
				results.errors.append("enum %s: invalid identifier" % enum_id)
				continue
			if db.has_pattern(enum_id):
				results.skipped.append("enum %s: already exists" % enum_id)
				continue
			var enum_data = data.enums[enum_id]
			var pdb_enum = PdbEnum.new()
			pdb_enum.id = enum_id
			pdb_enum.tags = PackedStringArray(enum_data.get("tags", []))
			pdb_enum.description = enum_data.get("description", "")
			var raw_values = enum_data.get("values", {})
			var coerced_values: Dictionary = {}
			for vk in raw_values:
				if not PdbPattern.is_valid_identifier(vk):
					continue
				coerced_values[vk] = int(raw_values[vk])
			pdb_enum.values = coerced_values
			db.add_pattern(pdb_enum)
			results.imported.enums += 1

	if data.has("consts"):
		for const_id in data.consts:
			if not PdbPattern.is_valid_identifier(const_id):
				results.errors.append("const %s: invalid identifier" % const_id)
				continue
			if db.has_pattern(const_id):
				results.skipped.append("const %s: already exists" % const_id)
				continue
			var const_data = data.consts[const_id]
			var pdb_const = PdbConst.new()
			pdb_const.id = const_id
			pdb_const.tags = PackedStringArray(const_data.get("tags", []))
			pdb_const.description = const_data.get("description", "")
			var data_dict = const_data.get("data", {})
			for k in data_dict:
				if not PdbPattern.is_valid_identifier(k):
					continue
				pdb_const.data[k] = _json_to_value(data_dict[k])
			db.add_pattern(pdb_const)
			results.imported.consts += 1

	if data.has("definitions"):
		for def_id in data.definitions:
			if not PdbPattern.is_valid_identifier(def_id):
				results.errors.append("definition %s: invalid identifier" % def_id)
				continue
			if db.has_pattern(def_id):
				results.skipped.append("definition %s: already exists" % def_id)
				continue
			var def_data = data.definitions[def_id]
			var pdb_def = PdbModelDefinition.new()
			pdb_def.id = def_id
			pdb_def.tags = PackedStringArray(def_data.get("tags", []))
			pdb_def.description = def_data.get("description", "")
			pdb_def.extends_type = def_data.get("extends_type", "Resource")
			pdb_def.icon_name = def_data.get("icon_name", "Object")

			var fields_data = def_data.get("fields", [])
			for field_data in fields_data:
				var field = PdbFieldDefinition.new()
				field.field_name = field_data.get("name", "")
				if not PdbPattern.is_valid_identifier(field.field_name):
					continue
				field.field_type = int(field_data.get("type", TYPE_STRING))
				field.hint = int(field_data.get("hint", PROPERTY_HINT_NONE))
				field.hint_string = field_data.get("hint_string", "")
				field.export_group = field_data.get("export_group", "")
				field.description = field_data.get("description", "")
				field.required = field_data.get("required", false)
				field.default_value = _json_to_value(field_data.get("default_value"))
				field.default_value = _coerce_to_field(field.default_value, field)
				pdb_def.fields.append(field)

			db.add_pattern(pdb_def)
			results.imported.definitions += 1

	if data.has("instances"):
		for inst_id in data.instances:
			if not PdbPattern.is_valid_identifier(inst_id):
				results.errors.append("instance %s: invalid identifier" % inst_id)
				continue
			if db.has_pattern(inst_id):
				results.skipped.append("instance %s: already exists" % inst_id)
				continue
			var inst_data = data.instances[inst_id]
			var pdb_inst = PdbModelInstance.new()
			pdb_inst.id = inst_id
			pdb_inst.definition_id = inst_data.get("definition_id", "")
			pdb_inst.tags = PackedStringArray(inst_data.get("tags", []))
			pdb_inst.description = inst_data.get("description", "")
			pdb_inst.set_database(db)
			if inst_data.has("source_tres"):
				pdb_inst.source_tres = inst_data["source_tres"]

			var inst_def := db.get_pattern(pdb_inst.definition_id) as PdbModelDefinition

			var data_dict = inst_data.get("data", {})
			for k in data_dict:
				if not PdbPattern.is_valid_identifier(k):
					continue
				var decoded = _json_to_value(data_dict[k])
				if inst_def:
					var field := inst_def.get_field(k)
					if field:
						decoded = _coerce_to_field(decoded, field)
				var key: StringName = k
				pdb_inst.data[key] = decoded

			db.add_pattern(pdb_inst)
			results.imported.instances += 1

	results.success = results.errors.is_empty()
	_log("Import complete: %d enums, %d consts, %d definitions, %d instances" % [
		results.imported.enums,
		results.imported.consts,
		results.imported.definitions,
		results.imported.instances
	])
	return results

static func _json_to_value(json_val: Variant) -> Variant:
	if json_val == null:
		return null

	if json_val is Dictionary and json_val.has("_type"):
		match json_val._type:
			"int":
				return int(json_val.value)
			"float":
				return float(json_val.value)
			"Vector2":
				return Vector2(json_val.x, json_val.y)
			"Vector2i":
				return Vector2i(json_val.x, json_val.y)
			"Vector3":
				return Vector3(json_val.x, json_val.y, json_val.z)
			"Vector3i":
				return Vector3i(json_val.x, json_val.y, json_val.z)
			"Rect2":
				return Rect2(json_val.x, json_val.y, json_val.w, json_val.h)
			"Color":
				return Color(json_val.r, json_val.g, json_val.b, json_val.a)
			"StringName":
				var sn: StringName = str(json_val.value)
				return sn
			"Resource":
				if json_val.has("path"):
					return str(json_val.path)
				return ""
			"Dictionary":
				var out: Dictionary = {}
				for entry in json_val.get("entries", []):
					if entry is Array and entry.size() == 2:
						out[_json_to_value(entry[0])] = _json_to_value(entry[1])
				return out
			"PackedStringArray":
				return PackedStringArray(json_val.get("value", []))
			"PackedInt32Array":
				return PackedInt32Array(json_val.get("value", []))
			"PackedInt64Array":
				return PackedInt64Array(json_val.get("value", []))
			"PackedFloat32Array":
				return PackedFloat32Array(json_val.get("value", []))
			"PackedFloat64Array":
				return PackedFloat64Array(json_val.get("value", []))
			"PackedByteArray":
				return PackedByteArray(json_val.get("value", []))
			"PackedVector2Array":
				var pv := PackedVector2Array()
				for v in json_val.get("value", []):
					pv.append(Vector2(v.get("x", 0), v.get("y", 0)))
				return pv
			"var":
				return str_to_var(str(json_val.get("value", "")))

	if json_val is Array:
		var arr = []
		for item in json_val:
			arr.append(_json_to_value(item))
		return arr

	if json_val is Dictionary:
		var out2: Dictionary = {}
		for k in json_val:
			out2[k] = _json_to_value(json_val[k])
		return out2

	if json_val is int or json_val is float:
		return float(json_val)

	return json_val

static func _coerce_to_field(value: Variant, field: PdbFieldDefinition) -> Variant:
	if field == null or value == null:
		return value
	match field.field_type:
		TYPE_INT:
			return int(value)
		TYPE_FLOAT:
			return float(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			var sn: StringName = str(value)
			return sn
		TYPE_ARRAY:
			if value is Array:
				var elem := field.get_array_element_type()
				var out: Array = []
				for it in value:
					out.append(_coerce_array_element(it, elem))
				return out
			return value
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray(value) if value is Array else value
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array(value) if value is Array else value
		TYPE_PACKED_INT64_ARRAY:
			return PackedInt64Array(value) if value is Array else value
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array(value) if value is Array else value
		TYPE_PACKED_FLOAT64_ARRAY:
			return PackedFloat64Array(value) if value is Array else value
		TYPE_PACKED_BYTE_ARRAY:
			return PackedByteArray(value) if value is Array else value
		_:
			return value

static func _coerce_array_element(value: Variant, element_type: String) -> Variant:
	if value == null:
		return value
	match element_type:
		"int":
			return int(value)
		"float":
			return float(value)
		"bool":
			return bool(value)
		"String":
			return str(value)
		"StringName":
			var sn: StringName = str(value)
			return sn
		_:
			return value

static func scan_resource_class(script_path: String, class_map: Dictionary = {}, _seen: Array = []) -> Dictionary:
	_log("Scanning resource class: %s" % script_path)

	var result: Dictionary = {
		"class_name": "",
		"extends": "Resource",
		"fields": [],
		"errors": []
	}

	if not FileAccess.file_exists(script_path):
		result.errors.append("File not found")
		return result

	var content = FileAccess.get_file_as_string(script_path)
	var lines = content.split("\n")

	var local_enums: Dictionary = {}
	for line in lines:
		var s: String = line.strip_edges()
		if s.begins_with("class_name "):
			result.class_name = s.substr(11).strip_edges()
		elif s.begins_with("extends "):
			result.extends = s.substr(8).strip_edges().replace("\"", "")
		elif s.begins_with("enum "):
			var er: String = s.substr(5).strip_edges()
			var br := er.find("{")
			var en: String = (er.substr(0, br) if br != -1 else er).strip_edges()
			if en != "":
				local_enums[en] = true

	var current_group: String = ""
	for line in lines:
		var s: String = line.strip_edges()
		if s.begins_with("@export_group(") or s.begins_with("@export_subgroup(") or s.begins_with("@export_category("):
			var a := s.find("\"")
			if a != -1:
				var b := s.find("\"", a + 1)
				if b != -1:
					current_group = s.substr(a + 1, b - a - 1)
		elif s.begins_with("@export"):
			var vp := s.find(" var ")
			if vp != -1:
				var field_info = _parse_export_line(s.substr(vp + 5), current_group, class_map, local_enums)
				if not field_info.is_empty():
					result.fields.append(field_info)

	var parent: String = result.extends
	if parent != "" and parent != "Resource" and parent != "RefCounted" and parent != "Object" and parent != "Node":
		var parent_path := _resolve_class_script(parent, script_path, class_map)
		if parent_path != "" and not (parent_path in _seen):
			_seen.append(script_path)
			var parent_scan := scan_resource_class(parent_path, class_map, _seen)
			var own_names: Dictionary = {}
			for f in result.fields:
				own_names[f.name] = true
			for pf in parent_scan.fields:
				if not own_names.has(pf.name):
					result.fields.append(pf)

	_log("Scanned: %s, %d fields" % [result.class_name, result.fields.size()])
	return result

static func _resolve_class_script(cls: String, from_path: String, class_map: Dictionary) -> String:
	if cls.ends_with(".gd") or cls.find("/") != -1:
		var base := cls.get_file()
		for p in class_map.values():
			if String(p).get_file() == base:
				return p
		return _search_dir_for_file(base, from_path.get_base_dir())
	if class_map.has(cls):
		var mapped: String = class_map[cls]
		return mapped
	return _search_dir_for_class(cls, from_path.get_base_dir())

static func _search_dir_for_file(file_name: String, dir_path: String) -> String:
	var d := DirAccess.open(dir_path)
	if d == null:
		return ""
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not n.begins_with("."):
			var full := dir_path.path_join(n)
			if d.current_is_dir():
				var found := _search_dir_for_file(file_name, full)
				if found != "":
					d.list_dir_end()
					return found
			elif n == file_name:
				d.list_dir_end()
				return full
		n = d.get_next()
	d.list_dir_end()
	return ""

static func _search_dir_for_class(cls: String, dir_path: String) -> String:
	var d := DirAccess.open(dir_path)
	if d == null:
		return ""
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not fname.begins_with(".") and not d.current_is_dir() and fname.get_extension() == "gd":
			var full := dir_path.path_join(fname)
			if _class_name_of(full) == cls:
				d.list_dir_end()
				return full
		fname = d.get_next()
	d.list_dir_end()
	return ""

static func _class_name_of(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var content := FileAccess.get_file_as_string(path)
	for line in content.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("class_name "):
			return s.substr(11).strip_edges()
	return ""

static func _build_class_map_for_dir(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var gd: Array = []
	var js: Array = []
	var tr: Array = []
	_collect_importable(dir_path, true, gd, js, tr)
	for f in gd:
		var cn := _class_name_of(f)
		if cn != "":
			out[cn] = f
	return out

static func _infer_type_from_default(default_part: String) -> int:
	var d := default_part.strip_edges()
	if d == "true" or d == "false":
		return TYPE_BOOL
	if d.begins_with("&\""):
		return TYPE_STRING_NAME
	if d.begins_with("\"") or d.begins_with("^\""):
		return TYPE_STRING
	if d.is_valid_int():
		return TYPE_INT
	if d.is_valid_float():
		return TYPE_FLOAT
	if d.begins_with("[") or d.begins_with("Array["):
		return TYPE_ARRAY
	if d.begins_with("{"):
		return TYPE_DICTIONARY
	if d.begins_with("Vector2("):
		return TYPE_VECTOR2
	if d.begins_with("Vector3("):
		return TYPE_VECTOR3
	if d.begins_with("Color("):
		return TYPE_COLOR
	return TYPE_STRING

static func _parse_export_line(line: String, current_group: String, class_map: Dictionary = {}, local_enums: Dictionary = {}) -> Dictionary:
	var decl := line
	var hc := decl.find("#")
	if hc != -1:
		decl = decl.substr(0, hc)
	decl = decl.strip_edges()
	if decl == "":
		return {}

	var field_name := ""
	var type_part := ""
	var default_part := ""

	var walrus := decl.find(":=")
	if walrus != -1:
		field_name = decl.substr(0, walrus).strip_edges()
		default_part = decl.substr(walrus + 2).strip_edges()
	else:
		var cp := decl.find(":")
		var eqp := decl.find("=")
		if cp != -1 and (eqp == -1 or cp < eqp):
			field_name = decl.substr(0, cp).strip_edges()
			var rest := decl.substr(cp + 1).strip_edges()
			var stop := rest.length()
			var a1 := rest.find(":")
			var a2 := rest.find("=")
			if a1 != -1 and a1 < stop:
				stop = a1
			if a2 != -1 and a2 < stop:
				stop = a2
			type_part = rest.substr(0, stop).strip_edges()
			if a2 != -1:
				default_part = rest.substr(a2 + 1).strip_edges()
		elif eqp != -1:
			field_name = decl.substr(0, eqp).strip_edges()
			default_part = decl.substr(eqp + 1).strip_edges()
		else:
			field_name = decl.strip_edges()

	if field_name == "":
		return {}

	var field_type = TYPE_STRING
	var hint = PROPERTY_HINT_NONE
	var hint_string = ""

	if type_part.begins_with("Array["):
		field_type = TYPE_ARRAY
		hint = PROPERTY_HINT_ARRAY_TYPE
		var end_bracket := type_part.find("]")
		if end_bracket > 6:
			hint_string = type_part.substr(6, end_bracket - 6)
	elif type_part == "":
		field_type = _infer_type_from_default(default_part)
	elif "." in type_part:
		field_type = TYPE_INT
		hint = PROPERTY_HINT_ENUM
		hint_string = type_part.get_slice(".", type_part.get_slice_count(".") - 1)
	else:
		match type_part:
			"String": field_type = TYPE_STRING
			"StringName": field_type = TYPE_STRING_NAME
			"int": field_type = TYPE_INT
			"float": field_type = TYPE_FLOAT
			"bool": field_type = TYPE_BOOL
			"Vector2": field_type = TYPE_VECTOR2
			"Vector2i": field_type = TYPE_VECTOR2I
			"Vector3": field_type = TYPE_VECTOR3
			"Vector3i": field_type = TYPE_VECTOR3I
			"Vector4": field_type = TYPE_VECTOR4
			"Vector4i": field_type = TYPE_VECTOR4I
			"Rect2": field_type = TYPE_RECT2
			"Rect2i": field_type = TYPE_RECT2I
			"Transform2D": field_type = TYPE_TRANSFORM2D
			"Transform3D": field_type = TYPE_TRANSFORM3D
			"Quaternion": field_type = TYPE_QUATERNION
			"Basis": field_type = TYPE_BASIS
			"AABB": field_type = TYPE_AABB
			"Plane": field_type = TYPE_PLANE
			"Projection": field_type = TYPE_PROJECTION
			"Color": field_type = TYPE_COLOR
			"NodePath": field_type = TYPE_NODE_PATH
			"RID": field_type = TYPE_RID
			"Dictionary": field_type = TYPE_DICTIONARY
			"Array": field_type = TYPE_ARRAY
			"PackedByteArray": field_type = TYPE_PACKED_BYTE_ARRAY
			"PackedInt32Array": field_type = TYPE_PACKED_INT32_ARRAY
			"PackedInt64Array": field_type = TYPE_PACKED_INT64_ARRAY
			"PackedFloat32Array": field_type = TYPE_PACKED_FLOAT32_ARRAY
			"PackedFloat64Array": field_type = TYPE_PACKED_FLOAT64_ARRAY
			"PackedStringArray": field_type = TYPE_PACKED_STRING_ARRAY
			"PackedVector2Array": field_type = TYPE_PACKED_VECTOR2_ARRAY
			"PackedVector3Array": field_type = TYPE_PACKED_VECTOR3_ARRAY
			"PackedColorArray": field_type = TYPE_PACKED_COLOR_ARRAY
			_:
				if local_enums.has(type_part):
					field_type = TYPE_INT
					hint = PROPERTY_HINT_ENUM
					hint_string = type_part
				elif class_map.has(type_part) or ClassDB.class_exists(type_part):
					field_type = TYPE_OBJECT
					hint = PROPERTY_HINT_RESOURCE_TYPE
					hint_string = type_part

	return {
		"name": field_name,
		"type": field_type,
		"hint": hint,
		"hint_string": hint_string,
		"export_group": current_group
	}

static func import_definition_from_script(script_path: String, db: PatternDatabaseFile, class_map: Dictionary = {}) -> Dictionary:
	_log("Importing definition from script: %s" % script_path)

	var results: Dictionary = {
		"success": true,
		"definition_id": "",
		"errors": []
	}

	if class_map.is_empty():
		class_map = _build_class_map_for_dir(script_path.get_base_dir())

	var scan_result = scan_resource_class(script_path, class_map)

	if not scan_result.errors.is_empty():
		results.success = false
		results.errors = scan_result.errors
		return results

	if scan_result.class_name.is_empty():
		results.success = false
		results.errors.append("No class_name found in script")
		return results

	if db.has_pattern(scan_result.class_name):
		results.success = false
		results.errors.append("Definition '%s' already exists" % scan_result.class_name)
		return results

	var pdb_def = PdbModelDefinition.new()
	pdb_def.id = scan_result.class_name
	pdb_def.extends_type = scan_result.extends

	for field_info in scan_result.fields:
		var field = PdbFieldDefinition.new()
		field.field_name = field_info.name
		field.field_type = field_info.type
		field.hint = field_info.hint
		field.hint_string = field_info.hint_string
		field.export_group = field_info.export_group
		pdb_def.fields.append(field)

	db.add_pattern(pdb_def)
	results.definition_id = scan_result.class_name
	_log("Imported definition: %s (%d fields)" % [pdb_def.id, pdb_def.fields.size()])

	return results

static func import_consts_from_gdscript(file_path: String, db: PatternDatabaseFile) -> Dictionary:
	var results: Dictionary = {
		"success": true,
		"imported": {"consts": 0},
		"skipped": [],
		"errors": [],
	}
	if not FileAccess.file_exists(file_path):
		results.success = false
		results.errors.append("File not found: %s" % file_path)
		return results

	var content = FileAccess.get_file_as_string(file_path)
	var lines = content.split("\n")

	var groups: Dictionary = {}
	var order: Array = []
	var current := ""
	for raw in lines:
		var line = raw.strip_edges()
		if line.begins_with("class ") and not line.begins_with("class_name"):
			var after = line.substr(6)
			var cut = after.length()
			var colon = after.find(":")
			var ext = after.find(" extends")
			if colon != -1:
				cut = min(cut, colon)
			if ext != -1:
				cut = min(cut, ext)
			current = after.substr(0, cut).strip_edges()
			if current != "" and not groups.has(current):
				groups[current] = {}
				order.append(current)
		elif line.begins_with("const ") and current != "":
			var body = line.substr(6)
			var eq = body.find("=")
			if eq == -1:
				continue
			var cname = body.substr(0, eq).split(":")[0].strip_edges()
			var rhs = body.substr(eq + 1).strip_edges()
			if not PdbPattern.is_valid_identifier(cname):
				continue
			groups[current][cname] = str_to_var(rhs)

	for gid in order:
		var data = groups[gid]
		if data.is_empty():
			continue
		if not PdbPattern.is_valid_identifier(gid):
			results.errors.append("const group '%s': invalid identifier" % gid)
			continue
		if db.has_pattern(gid):
			results.skipped.append("const group '%s' already exists" % gid)
			continue
		var c := PdbConst.new()
		c.id = gid
		c.data = data
		db.add_pattern(c)
		results.imported.consts += 1
	return results

static func import_folder(dir_path: String, db: PatternDatabaseFile, recursive := true) -> Dictionary:
	var agg := {
		"success": true,
		"imported": {"enums": 0, "consts": 0, "definitions": 0, "instances": 0},
		"skipped": [],
		"errors": [],
		"files": 0,
	}
	var gd_files: Array = []
	var json_files: Array = []
	var tres_files: Array = []
	_collect_importable(dir_path, recursive, gd_files, json_files, tres_files)

	var class_map: Dictionary = {}
	for cf in gd_files:
		var cn := _class_name_of(cf)
		if cn != "":
			class_map[cn] = cf

	for f in gd_files:
		agg.files += 1
		_merge_import(agg, import_enums_from_gdscript(f, db), f)
		_merge_import(agg, import_consts_from_gdscript(f, db), f)
		var scan = scan_resource_class(f, class_map)
		if scan.errors.is_empty() and not str(scan.class_name).is_empty() and not scan.fields.is_empty():
			var d := import_definition_from_script(f, db, class_map)
			if d.get("success", false):
				agg.imported.definitions += 1
			else:
				_merge_import(agg, d, f)

	for f in json_files:
		agg.files += 1
		_merge_import(agg, import_from_json(f, db), f)

	for f in tres_files:
		agg.files += 1
		_merge_import(agg, import_instance_from_tres(f, db), f)

	agg.success = agg.errors.is_empty()
	return agg

static func import_instance_from_tres(path: String, db: PatternDatabaseFile) -> Dictionary:
	var results := {"success": true, "imported": {"instances": 0}, "skipped": [], "errors": []}
	if not FileAccess.file_exists(path):
		results.errors.append("%s: file not found" % path.get_file())
		results.success = false
		return results

	var head := FileAccess.open(path, FileAccess.READ)
	if head != null:
		var magic := head.get_buffer(4)
		head.close()
		if magic.size() >= 4 and magic[0] == 0x52 and magic[1] == 0x53 and magic[2] == 0x52 and magic[3] == 0x43:
			results.skipped.append("%s: binary resource not supported — re-save it as a text .tres to import." % path.get_file())
			return results

	var content := FileAccess.get_file_as_string(path)
	if content == "":
		results.errors.append("%s: empty or unreadable" % path.get_file())
		results.success = false
		return results

	var doc := parse_tres_document(content)
	var cls: String = doc.script_class
	if cls == "":
		results.skipped.append("%s: no script_class in header" % path.get_file())
		return results

	var def: PdbModelDefinition = null
	var by_id = db.get_pattern(cls)
	if by_id is PdbModelDefinition:
		def = by_id
	else:
		for p in db.patterns.values():
			if p is PdbModelDefinition and str(p.id).to_lower() == cls.to_lower():
				def = p
				break
	if def == null:
		results.skipped.append("%s: no definition '%s'" % [path.get_file(), cls])
		return results

	var inst_id := path.get_file().get_basename()
	if doc.props.has("resource_name"):
		var rn = doc.props["resource_name"]
		if typeof(rn) == TYPE_DICTIONARY and rn.has("__raw__"):
			var parsed = str_to_var(rn["__raw__"])
			if parsed is String and PdbPattern.is_valid_identifier(parsed):
				inst_id = parsed
	if not PdbPattern.is_valid_identifier(inst_id):
		results.errors.append("%s: no valid instance id (filename or resource_name)" % path.get_file())
		return results
	if db.has_pattern(inst_id):
		results.skipped.append("instance %s already exists" % inst_id)
		return results

	var inst := PdbModelInstance.new()
	inst.id = inst_id
	inst.definition_id = def.id
	inst.set_database(db)
	inst.source_tres = doc

	if doc.props.has("metadata/pdb_tags"):
		var raw_tags = doc.props["metadata/pdb_tags"]
		if raw_tags is Dictionary and raw_tags.has("__raw__"):
			var parsed_tags = str_to_var(raw_tags["__raw__"])
			if parsed_tags is PackedStringArray:
				inst.tags = parsed_tags
			elif parsed_tags is Array:
				inst.tags = PackedStringArray(parsed_tags)
	if doc.props.has("metadata/pdb_description"):
		var raw_desc = doc.props["metadata/pdb_description"]
		if raw_desc is Dictionary and raw_desc.has("__raw__"):
			var parsed_desc = str_to_var(raw_desc["__raw__"])
			if parsed_desc is String:
				inst.description = parsed_desc

	var ext_paths: Dictionary = {}
	for e in doc.ext:
		ext_paths[e.id] = e.path
	for field in def.fields:
		var fname := str(field.field_name)
		if doc.props.has(fname):
			inst.data[field.field_name] = _flatten_value(doc.props[fname], ext_paths)
	db.add_pattern(inst)
	results.imported.instances += 1
	return results

static func parse_tres_document(content: String) -> Dictionary:
	var doc := {"resource_type": "", "script_class": "", "load_steps": "", "fmt": "", "ext": [], "subs": [], "props": {}}
	var lines := content.split("\n")
	var section := ""
	var cur_sub: Dictionary = {}
	var i := 0
	while i < lines.size():
		var s: String = lines[i].strip_edges()
		i += 1
		if s == "":
			continue
		if s.begins_with("["):
			if s.begins_with("[gd_resource"):
				doc.resource_type = _tres_attr(s, "type")
				doc.script_class = _tres_attr(s, "script_class")
				doc.load_steps = _tres_attr(s, "load_steps")
				doc.fmt = _tres_attr_num(s, "format")
				section = ""
			elif s.begins_with("[ext_resource"):
				doc.ext.append({"type": _tres_attr(s, "type"), "uid": _tres_attr(s, "uid"), "path": _tres_attr(s, "path"), "id": _tres_attr(s, "id")})
				section = ""
			elif s.begins_with("[sub_resource"):
				cur_sub = {"type": _tres_attr(s, "type"), "id": _tres_attr(s, "id"), "props": {}}
				doc.subs.append(cur_sub)
				section = "sub"
			elif s.begins_with("[resource]"):
				section = "res"
			continue
		var eq := s.find("=")
		if eq == -1:
			continue
		var key := s.substr(0, eq).strip_edges()
		var val := s.substr(eq + 1).strip_edges()
		while _tres_unbalanced(val) and i < lines.size():
			val += "\n" + lines[i]
			i += 1
		var pv = _parse_tres_value(val)
		if section == "sub" and not cur_sub.is_empty():
			cur_sub.props[key] = pv
		elif section == "res":
			doc.props[key] = pv
	return doc

static func emit_tres_document(doc: Dictionary) -> String:
	var out: PackedStringArray = []
	var rtype: String = doc.get("resource_type", "")
	if rtype == "":
		rtype = "Resource"
	var hdr := "[gd_resource type=\"%s\"" % rtype
	if str(doc.get("script_class", "")) != "":
		hdr += " script_class=\"%s\"" % doc.script_class
	var steps: int = doc.ext.size() + doc.subs.size() + 1
	if steps > 1:
		hdr += " load_steps=%d" % steps
	var fmt: String = doc.get("fmt", "")
	if fmt == "":
		fmt = "3"
	hdr += " format=%s]" % fmt
	out.append(hdr)
	out.append("")
	for e in doc.ext:
		var line := "[ext_resource type=\"%s\" " % e.type
		if str(e.get("uid", "")) != "":
			line += "uid=\"%s\" " % e.uid
		line += "path=\"%s\" id=\"%s\"]" % [e.path, e.id]
		out.append(line)
	if not doc.ext.is_empty():
		out.append("")
	for sr in doc.subs:
		out.append("[sub_resource type=\"%s\" id=\"%s\"]" % [sr.type, sr.id])
		for k in sr.props:
			out.append("%s = %s" % [k, _emit_tres_value(sr.props[k])])
		out.append("")
	out.append("[resource]")
	for k in doc.props:
		out.append("%s = %s" % [k, _emit_tres_value(doc.props[k])])
	return "\n".join(out) + "\n"
static func _parse_tres_value(text: String) -> Variant:
	text = text.strip_edges()
	if text.begins_with("Array[") and text.ends_with("])"):
		var tclose := text.find("]")
		var etype := text.substr(6, tclose - 6)
		var rest := text.substr(tclose + 1)
		var inner := rest.substr(2, rest.length() - 4).strip_edges()
		var items: Array = []
		if inner != "":
			for part in _split_top_level(inner):
				items.append(_parse_tres_value(part))
		return {"__array__": etype, "items": items}
	if text.begins_with("[") and text.ends_with("]"):
		var inner2 := text.substr(1, text.length() - 2).strip_edges()
		var items2: Array = []
		if inner2 != "":
			for part in _split_top_level(inner2):
				items2.append(_parse_tres_value(part))
		return {"__array__": "", "items": items2}
	if text.begins_with("ExtResource(\"") and text.ends_with("\")"):
		return {"__ref__": "ext", "id": _tres_between(text, "ExtResource(\"", "\")")}
	if text.begins_with("SubResource(\"") and text.ends_with("\")"):
		return {"__ref__": "sub", "id": _tres_between(text, "SubResource(\"", "\")")}
	return {"__raw__": text}

static func _emit_tres_value(v: Variant) -> String:
	if typeof(v) == TYPE_DICTIONARY:
		if v.has("__raw__"):
			return v["__raw__"]
		if v.has("__ref__"):
			if v["__ref__"] == "ext":
				return "ExtResource(\"%s\")" % v["id"]
			return "SubResource(\"%s\")" % v["id"]
		if v.has("__array__"):
			var parts: PackedStringArray = []
			for item in v["items"]:
				parts.append(_emit_tres_value(item))
			var joined := ", ".join(parts)
			if str(v["__array__"]) != "":
				return "Array[%s]([%s])" % [v["__array__"], joined]
			return "[%s]" % joined
	return "null"

static func _flatten_value(v: Variant, ext_paths: Dictionary) -> Variant:
	if typeof(v) != TYPE_DICTIONARY:
		return v
	if v.has("__raw__"):
		var parsed = str_to_var(v["__raw__"])
		if parsed == null and str(v["__raw__"]) != "null":
			return v["__raw__"]
		return parsed
	if v.has("__ref__"):
		if v["__ref__"] == "ext":
			return ext_paths.get(v["id"], "")
		return {"__embedded__": true}
	if v.has("__array__"):
		var arr: Array = []
		for item in v["items"]:
			arr.append(_flatten_value(item, ext_paths))
		return arr
	return null

static func _split_top_level(s: String) -> Array:
	var out: Array = []
	var depth := 0
	var in_q := false
	var cur := ""
	for i in s.length():
		var ch := s[i]
		if in_q:
			cur += ch
			if ch == "\"":
				in_q = false
		elif ch == "\"":
			in_q = true
			cur += ch
		elif ch == "(" or ch == "[":
			depth += 1
			cur += ch
		elif ch == ")" or ch == "]":
			depth -= 1
			cur += ch
		elif ch == "," and depth == 0:
			out.append(cur.strip_edges())
			cur = ""
		else:
			cur += ch
	if cur.strip_edges() != "":
		out.append(cur.strip_edges())
	return out

static func _tres_unbalanced(s: String) -> bool:
	return (s.count("(") + s.count("[")) > (s.count(")") + s.count("]"))

static func _tres_between(text: String, pre: String, post: String) -> String:
	var a := text.find(pre)
	if a == -1:
		return ""
	a += pre.length()
	var b := text.rfind(post)
	if b == -1 or b < a:
		return text.substr(a)
	return text.substr(a, b - a)

static func _tres_attr(line: String, name: String) -> String:
	var key := " " + name + "=\""
	var i := line.find(key)
	if i == -1:
		return ""
	i += key.length()
	var j := line.find("\"", i)
	if j == -1:
		return ""
	return line.substr(i, j - i)

static func _tres_attr_num(line: String, name: String) -> String:
	var key := " " + name + "="
	var i := line.find(key)
	if i == -1:
		return ""
	i += key.length()
	var j := i
	while j < line.length() and line[j] != " " and line[j] != "]":
		j += 1
	return line.substr(i, j - i)

static func _collect_importable(dir_path: String, recursive: bool, gd: Array, json: Array, tres: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := dir_path.path_join(name)
			if dir.current_is_dir():
				if recursive and name != "addons":
					_collect_importable(full, recursive, gd, json, tres)
			else:
				match name.get_extension().to_lower():
					"gd":
						gd.append(full)
					"json":
						json.append(full)
					"tres", "res":
						tres.append(full)
		name = dir.get_next()
	dir.list_dir_end()

static func _merge_import(agg: Dictionary, r: Dictionary, source_path: String) -> void:
	if r.has("imported") and r.imported is Dictionary:
		for k in r.imported:
			agg.imported[k] = agg.imported.get(k, 0) + int(r.imported[k])
	if r.has("skipped"):
		for s in r.skipped:
			agg.skipped.append("%s: %s" % [source_path.get_file(), s])
	if r.has("errors"):
		for e in r.errors:
			agg.errors.append("%s: %s" % [source_path.get_file(), e])
