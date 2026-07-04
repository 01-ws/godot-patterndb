@tool
class_name PdbCodegen
extends RefCounted
## Generates typed GDScript: enum classes, const classes, and model Resource classes.

static func _log(msg: String) -> void:
	PdbLog.info("Codegen", msg)

const _RESERVED := {
	"if":true,"elif":true,"else":true,"for":true,"while":true,"match":true,"break":true,
	"continue":true,"pass":true,"return":true,"class":true,"class_name":true,"extends":true,
	"is":true,"in":true,"as":true,"self":true,"super":true,"signal":true,"func":true,
	"static":true,"const":true,"enum":true,"var":true,"breakpoint":true,"preload":true,
	"await":true,"assert":true,"void":true,"yield":true,"tool":true,"namespace":true,
	"trait":true,"and":true,"or":true,"not":true,"true":true,"false":true,"null":true,
	"PI":true,"TAU":true,"INF":true,"NAN":true,
}

static func is_reserved_word(name: String) -> bool:
	return _RESERVED.has(name)

static func _safe_class_name(desired: String, fallback: String) -> String:
	var n := desired.strip_edges()
	if n == "" or not n.is_valid_identifier() or _RESERVED.has(n) or ClassDB.class_exists(n):
		return fallback
	return n

static func generate_enum_file(db: PatternDatabaseFile, class_name_override: String = "enums") -> String:
	_log("Generating enum file: %s" % class_name_override)

	var lines: PackedStringArray = []

	lines.append("class_name %s" % _safe_class_name(class_name_override, "enums"))
	lines.append("extends RefCounted")
	lines.append("")

	var enums: Array[PdbEnum] = []
	for key in db.patterns:
		var pattern = db.patterns[key]
		if pattern is PdbEnum:
			enums.append(pattern)

	enums.sort_custom(func(a, b): return str(a.id) < str(b.id))

	_log("Found %d enums" % enums.size())

	for pdb_enum in enums:
		lines.append_array(_generate_enum_block(pdb_enum))
		lines.append("")

	return "\n".join(lines)

static func _generate_enum_block(pdb_enum: PdbEnum) -> PackedStringArray:
	var lines: PackedStringArray = []

	if pdb_enum.description != "":
		for desc_line in pdb_enum.description.split("\n"):
			lines.append("## %s" % desc_line)

	lines.append("enum %s {" % pdb_enum.id)

	var sorted_values: Array = []
	for key in pdb_enum.values:
		sorted_values.append({"name": key, "value": pdb_enum.values[key]})
	sorted_values.sort_custom(func(a, b): return a.value < b.value)

	for i in range(sorted_values.size()):
		var entry = sorted_values[i]
		var comma = "," if i < sorted_values.size() - 1 else ""
		lines.append("\t%s = %d%s" % [entry.name, entry.value, comma])

	lines.append("}")

	return lines

static func generate_model_file(definition: PdbModelDefinition, enum_class_name: String = "enums", db: PatternDatabaseFile = null) -> String:
	_log("Generating model file: %s" % definition.id)

	var lines: PackedStringArray = []

	if definition.description != "":
		for desc_line in definition.description.split("\n"):
			lines.append("## %s" % desc_line)

	lines.append("class_name %s" % definition.id)
	lines.append("extends %s" % definition.extends_type)
	lines.append("")

	var inherited := _inherited_field_names(definition, db)

	var current_group: String = ""

	for field in definition.fields:
		if inherited.has(str(field.field_name)):
			continue
		if field.export_group != current_group:
			current_group = field.export_group
			if current_group != "":
				lines.append("")
				lines.append("@export_group(\"%s\")" % current_group)

		var export_line = _generate_field_export(field, enum_class_name, db)

		if field.description != "":
			lines.append("## %s" % field.description)

		lines.append(export_line)

	if db == null or db.export_tags_metadata:
		lines.append("")
		lines.append("func get_tags() -> PackedStringArray:")
		lines.append("\treturn get_meta(&\"pdb_tags\", PackedStringArray())")
		lines.append("")
		lines.append("func has_tag(tag: StringName) -> bool:")
		lines.append("\tvar q := String(tag)")
		lines.append("\tfor t in get_tags():")
		lines.append("\t\tvar s := String(t)")
		lines.append("\t\tif s == q or s.begins_with(q + \".\"):")
		lines.append("\t\t\treturn true")
		lines.append("\treturn false")

	lines.append("")

	_log("Generated %d lines for %s" % [lines.size(), definition.id])

	return "\n".join(lines)

static func _inherited_field_names(definition: PdbModelDefinition, db: PatternDatabaseFile) -> Dictionary:
	var out: Dictionary = {}
	if db == null:
		return out
	var parent: String = definition.extends_type
	var guard := 0
	while parent != "" and parent != "Resource" and parent != "RefCounted" and parent != "Object" and guard < 32:
		guard += 1
		var p = db.get_pattern(parent)
		if not (p is PdbModelDefinition):
			break
		for f in p.fields:
			out[str(f.field_name)] = true
		parent = p.extends_type
	return out

static func _generate_field_export(field: PdbFieldDefinition, enum_class_name: String, db: PatternDatabaseFile = null) -> String:
	var type_str = _get_type_string(field, enum_class_name, db)
	var default_str = _get_default_string(field, enum_class_name, db)

	if default_str != "":
		return "@export var %s: %s = %s" % [field.field_name, type_str, default_str]
	else:
		return "@export var %s: %s" % [field.field_name, type_str]

static func _is_cross_instance_ref(field: PdbFieldDefinition, db: PatternDatabaseFile) -> bool:
	return db != null and field.is_resource_field() and db.get_pattern(field.hint_string) is PdbModelDefinition

static func _get_type_string(field: PdbFieldDefinition, enum_class_name: String, db: PatternDatabaseFile = null) -> String:
	if field.is_enum_field():
		return "%s.%s" % [enum_class_name, field.hint_string]

	if field.is_resource_field():
		if _is_cross_instance_ref(field, db):
			return "StringName"
		return field.hint_string if field.hint_string != "" else "Resource"

	if field.is_array_field():
		var element_type = field.get_array_element_type()
		if element_type != "":
			if db != null and db.get_pattern(element_type) is PdbModelDefinition:
				return "Array[StringName]"
			return "Array[%s]" % element_type
		return "Array"

	match field.field_type:
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "String"
		TYPE_STRING_NAME:
			return "StringName"
		TYPE_VECTOR2:
			return "Vector2"
		TYPE_VECTOR2I:
			return "Vector2i"
		TYPE_VECTOR3:
			return "Vector3"
		TYPE_VECTOR3I:
			return "Vector3i"
		TYPE_VECTOR4:
			return "Vector4"
		TYPE_VECTOR4I:
			return "Vector4i"
		TYPE_RECT2:
			return "Rect2"
		TYPE_RECT2I:
			return "Rect2i"
		TYPE_COLOR:
			return "Color"
		TYPE_TRANSFORM2D:
			return "Transform2D"
		TYPE_TRANSFORM3D:
			return "Transform3D"
		TYPE_BASIS:
			return "Basis"
		TYPE_QUATERNION:
			return "Quaternion"
		TYPE_AABB:
			return "AABB"
		TYPE_PLANE:
			return "Plane"
		TYPE_PROJECTION:
			return "Projection"
		TYPE_DICTIONARY:
			return "Dictionary"
		TYPE_NODE_PATH:
			return "NodePath"
		TYPE_OBJECT:
			return "Resource"
		TYPE_PACKED_BYTE_ARRAY:
			return "PackedByteArray"
		TYPE_PACKED_INT32_ARRAY:
			return "PackedInt32Array"
		TYPE_PACKED_INT64_ARRAY:
			return "PackedInt64Array"
		TYPE_PACKED_FLOAT32_ARRAY:
			return "PackedFloat32Array"
		TYPE_PACKED_FLOAT64_ARRAY:
			return "PackedFloat64Array"
		TYPE_PACKED_STRING_ARRAY:
			return "PackedStringArray"
		TYPE_PACKED_VECTOR2_ARRAY:
			return "PackedVector2Array"
		TYPE_PACKED_VECTOR3_ARRAY:
			return "PackedVector3Array"
		TYPE_PACKED_COLOR_ARRAY:
			return "PackedColorArray"
		TYPE_PACKED_VECTOR4_ARRAY:
			return "PackedVector4Array"
		_:
			return "Variant"

static func _enum_entry_for_value(pdb_enum: PdbEnum, value: int) -> String:
	for key in pdb_enum.values:
		if int(pdb_enum.values[key]) == value:
			return str(key)
	return ""

static func _lowest_enum_entry(pdb_enum: PdbEnum) -> String:
	var best := ""
	var best_val := 0
	for key in pdb_enum.values:
		var v := int(pdb_enum.values[key])
		if best == "" or v < best_val:
			best = str(key)
			best_val = v
	return best

static func _get_default_string(field: PdbFieldDefinition, enum_class_name: String, db: PatternDatabaseFile = null) -> String:
	var value = field.default_value

	if value == null:
		if field.is_resource_field():
			return ""
		if field.is_array_field():
			return "[]"
		return ""

	if field.is_enum_field():
		var ival = int(value)
		if db != null:
			var e = db.get_pattern(field.hint_string)
			if e is PdbEnum:
				var entry = _enum_entry_for_value(e, ival)
				if entry != "":
					return "%s.%s.%s" % [enum_class_name, field.hint_string, entry]
				var fallback := _lowest_enum_entry(e)
				if fallback != "":
					return "%s.%s.%s" % [enum_class_name, field.hint_string, fallback]
		return str(ival)

	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var s = str(value)
			if not ("." in s or "e" in s or "E" in s):
				s += ".0"
			return s
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
		TYPE_VECTOR4:
			return "Vector4(%s, %s, %s, %s)" % [value.x, value.y, value.z, value.w]
		TYPE_VECTOR4I:
			return "Vector4i(%d, %d, %d, %d)" % [value.x, value.y, value.z, value.w]
		TYPE_RECT2:
			return "Rect2(%s, %s, %s, %s)" % [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_RECT2I:
			return "Rect2i(%d, %d, %d, %d)" % [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_COLOR:
			if value == Color.WHITE:
				return "Color.WHITE"
			if value == Color.BLACK:
				return "Color.BLACK"
			if value == Color.RED:
				return "Color.RED"
			if value == Color.GREEN:
				return "Color.GREEN"
			if value == Color.BLUE:
				return "Color.BLUE"
			if value == Color.TRANSPARENT:
				return "Color.TRANSPARENT"
			return "Color(%s, %s, %s, %s)" % [value.r, value.g, value.b, value.a]
		TYPE_TRANSFORM2D:
			return "Transform2D.IDENTITY" if value == Transform2D.IDENTITY else "Transform2D()"
		TYPE_TRANSFORM3D:
			return "Transform3D.IDENTITY" if value == Transform3D.IDENTITY else "Transform3D()"
		TYPE_BASIS:
			return "Basis.IDENTITY" if value == Basis.IDENTITY else "Basis()"
		TYPE_QUATERNION:
			return "Quaternion.IDENTITY" if value == Quaternion.IDENTITY else "Quaternion()"
		TYPE_AABB:
			return "AABB()"
		TYPE_PLANE:
			return "Plane()"
		TYPE_PROJECTION:
			return "Projection.IDENTITY" if value == Projection.IDENTITY else "Projection()"
		TYPE_DICTIONARY:
			return "{}"
		TYPE_ARRAY:
			return "[]"
		TYPE_NODE_PATH:
			return "NodePath()"
		_:
			return ""

static func generate_const_file(db: PatternDatabaseFile, class_name_override: String = "consts") -> String:
	_log("Generating const file: %s" % class_name_override)

	var lines: PackedStringArray = []

	lines.append("class_name %s" % _safe_class_name(class_name_override, "consts"))
	lines.append("extends RefCounted")
	lines.append("")

	var consts: Array[PdbConst] = []
	for key in db.patterns:
		var pattern = db.patterns[key]
		if pattern is PdbConst:
			consts.append(pattern)

	consts.sort_custom(func(a, b): return str(a.id) < str(b.id))

	_log("Found %d const groups" % consts.size())

	for pdb_const in consts:
		lines.append_array(_generate_const_block(pdb_const))
		lines.append("")

	return "\n".join(lines)

static func _generate_const_block(pdb_const: PdbConst) -> PackedStringArray:
	var lines: PackedStringArray = []

	if pdb_const.description != "":
		for desc_line in pdb_const.description.split("\n"):
			lines.append("## %s" % desc_line)

	lines.append("class %s:" % pdb_const.id)

	for key in pdb_const.data:
		var value = pdb_const.data[key]
		var value_str = _value_to_gdscript(value)
		lines.append("\tconst %s = %s" % [key, value_str])

	if pdb_const.data.is_empty():
		lines.append("\tpass")

	return lines

static func _value_to_gdscript(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING:
			return "\"%s\"" % value.replace("\"", "\\\"")
		TYPE_STRING_NAME:
			return "&\"%s\"" % value
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var s := str(value)
			if not ("." in s or "e" in s or "E" in s):
				s += ".0"
			return s
		TYPE_VECTOR2:
			return "Vector2(%s, %s)" % [value.x, value.y]
		TYPE_VECTOR3:
			return "Vector3(%s, %s, %s)" % [value.x, value.y, value.z]
		TYPE_COLOR:
			return "Color(%s, %s, %s, %s)" % [value.r, value.g, value.b, value.a]
		TYPE_RECT2:
			return "Rect2(%s, %s, %s, %s)" % [value.position.x, value.position.y, value.size.x, value.size.y]
		_:
			return var_to_str(value)

static func export_all(db: PatternDatabaseFile, output_dir: String, enum_class: String = "enums", const_class: String = "consts", model_subdir: String = "model") -> Dictionary:
	_log("Starting export to: %s" % output_dir)
	var enum_class_raw := enum_class.strip_edges()
	var const_class_raw := const_class.strip_edges()
	enum_class = _safe_class_name(enum_class, "enums")
	const_class = _safe_class_name(const_class, "consts")

	var results: Dictionary = {
		"success": true,
		"files": [],
		"errors": [],
		"notes": []
	}
	if enum_class_raw != "" and enum_class_raw != enum_class:
		results.notes.append("Enum class name '%s' is not a usable identifier; used '%s' instead." % [enum_class_raw, enum_class])
	if const_class_raw != "" and const_class_raw != const_class:
		results.notes.append("Const class name '%s' is not a usable identifier; used '%s' instead." % [const_class_raw, const_class])

	if not DirAccess.dir_exists_absolute(output_dir):
		_log("Creating output directory: %s" % output_dir)
		var err = DirAccess.make_dir_recursive_absolute(output_dir)
		if err != OK:
			results.success = false
			results.errors.append("Failed to create output directory: %s (error %d)" % [output_dir, err])
			_log("ERROR: Failed to create directory: %d" % err)
			return results

	var has_enums = false
	var has_consts = false
	var model_definitions: Array[PdbModelDefinition] = []

	for key in db.patterns:
		var pattern = db.patterns[key]
		if pattern is PdbEnum:
			has_enums = true
		elif pattern is PdbConst:
			has_consts = true
		elif pattern is PdbModelDefinition:
			model_definitions.append(pattern)

	_log("Export targets: enums=%s, consts=%s, models=%d" % [has_enums, has_consts, model_definitions.size()])

	var reserved := {enum_class: "the enum class", const_class: "the const class"}
	for key in db.patterns:
		var p = db.patterns[key]
		if (p is PdbEnum or p is PdbConst) and is_reserved_word(String(p.id)):
			results.success = false
			results.errors.append("'%s' is a reserved GDScript keyword and cannot be a class name; rename it." % String(p.id))
	for definition in model_definitions:
		var cn := String(definition.id)
		if reserved.has(cn):
			results.success = false
			results.errors.append("Definition '%s' collides with %s name; rename the definition or change the export class name." % [cn, reserved[cn]])
		elif is_reserved_word(cn):
			results.success = false
			results.errors.append("Definition '%s' is a reserved GDScript keyword; rename the definition." % cn)
		elif ClassDB.class_exists(cn):
			results.success = false
			results.errors.append("Definition '%s' collides with a built-in Godot class; rename the definition." % cn)
	if not results.success:
		_log("Export aborted: class-name collisions")
		return results

	if has_enums:
		var enum_code = generate_enum_file(db, enum_class)
		var enum_path = output_dir.path_join("enums.gd")
		_log("Writing enum file: %s" % enum_path)
		var err = _write_file(enum_path, enum_code)
		if err == OK:
			results.files.append(enum_path)
			_log("Enum file written successfully")
		else:
			results.errors.append("Failed to write enum file: %s (error %d)" % [enum_path, err])
			_log("ERROR: Failed to write enum file: %d" % err)

	if has_consts:
		var const_code = generate_const_file(db, const_class)
		var const_path = output_dir.path_join("const.gd")
		_log("Writing const file: %s" % const_path)
		var err = _write_file(const_path, const_code)
		if err == OK:
			results.files.append(const_path)
			_log("Const file written successfully")
		else:
			results.errors.append("Failed to write const file: %s (error %d)" % [const_path, err])
			_log("ERROR: Failed to write const file: %d" % err)

	var model_dir := output_dir.path_join(model_subdir) if model_subdir != "" else output_dir
	if not model_definitions.is_empty() and not DirAccess.dir_exists_absolute(model_dir):
		DirAccess.make_dir_recursive_absolute(model_dir)
	for definition in model_definitions:
		var model_code = generate_model_file(definition, enum_class, db)
		var model_path = model_dir.path_join(str(definition.id).to_snake_case() + ".gd")
		_log("Writing model file: %s" % model_path)
		var err = _write_file(model_path, model_code)
		if err == OK:
			results.files.append(model_path)
			_log("Model file written successfully")
		else:
			results.errors.append("Failed to write model file: %s (error %d)" % [model_path, err])
			_log("ERROR: Failed to write model file: %d" % err)

	results.success = results.errors.is_empty()
	_log("Export complete: success=%s, files=%d, errors=%d" % [results.success, results.files.size(), results.errors.size()])

	return results

static func _write_file(path: String, content: String) -> Error:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if not file:
		var err = FileAccess.get_open_error()
		_log("ERROR: Cannot open file for writing: %s (error %d)" % [path, err])
		return err
	file.store_string(content)
	file.close()
	return OK
