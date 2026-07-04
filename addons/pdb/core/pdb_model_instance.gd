@tool
class_name PdbModelInstance
extends PdbPattern

@export var definition_id: StringName = &""

@export var data: Dictionary = {}

@export var source_tres: Dictionary = {}

var _definition_cache: PdbModelDefinition = null
var _database_ref: WeakRef = null

signal data_changed(field_name: StringName, old_value: Variant, new_value: Variant)

func set_database(db: PatternDatabaseFile) -> void:
	_database_ref = weakref(db)
	_definition_cache = null

func get_database() -> PatternDatabaseFile:
	if _database_ref:
		return _database_ref.get_ref()
	return null

func get_definition() -> PdbModelDefinition:
	if _definition_cache:
		return _definition_cache

	var db = get_database()
	if db and definition_id != &"":
		var def = db.get_pattern(definition_id)
		if def is PdbModelDefinition:
			_definition_cache = def
			return _definition_cache

	return null

func set_definition(def: PdbModelDefinition) -> void:
	if def:
		definition_id = def.id
		_definition_cache = def
		_initialize_from_definition()
	else:
		definition_id = &""
		_definition_cache = null

func _initialize_from_definition() -> void:
	var def = get_definition()
	if not def:
		return

	for field in def.fields:
		if not data.has(field.field_name):
			data[field.field_name] = field.get_default()

func get_value(field_name: StringName) -> Variant:
	return data.get(field_name)

func get_resource(field_name: StringName) -> Resource:
	var v = data.get(field_name)
	if v is Resource:
		return v
	if (v is String or v is StringName) and str(v) != "" and ResourceLoader.exists(str(v)):
		return load(str(v))
	return null

func set_value(field_name: StringName, value: Variant) -> void:
	if not PdbPattern.is_valid_identifier(field_name):
		PdbLog.error("Instance", "Invalid field name (empty or containing '/' '\\').")
		return
	var old_value = data.get(field_name)
	data[field_name] = value
	data_changed.emit(field_name, old_value, value)
	emit_changed()

func has_value(field_name: StringName) -> bool:
	return data.has(field_name)

func clear_value(field_name: StringName) -> void:
	var def = get_definition()
	if def:
		var field = def.get_field(field_name)
		if field:
			set_value(field_name, field.get_default())
			return
	data.erase(field_name)
	emit_changed()

func _get(property: StringName) -> Variant:
	if data.has(property):
		return data[property]
	return null

func _set(property: StringName, value: Variant) -> bool:
	var def = get_definition()
	if def and def.has_field(property):
		set_value(property, value)
		return true
	return false

func _get_property_list() -> Array[Dictionary]:
	var def = get_definition()
	if def:
		return def.get_property_list_for_instance()
	return []

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []

	if id == &"":
		errors.append("Instance ID cannot be empty")

	if definition_id == &"":
		errors.append("No definition assigned")
		return errors

	var def = get_definition()
	if not def:
		errors.append("Definition '%s' not found in database" % definition_id)
		return errors

	var data_errors = def.validate_data(data)
	errors.append_array(data_errors)

	return errors

func is_valid() -> bool:
	return validate().is_empty()

func reset_to_defaults() -> void:
	var def = get_definition()
	if def:
		data = def.create_default_data()
		emit_changed()

func duplicate_instance() -> PdbModelInstance:
	var copy = PdbModelInstance.new()
	copy.id = id
	copy.tags = tags.duplicate()
	copy.description = description
	copy.definition_id = definition_id
	copy.data = data.duplicate(true)
	copy.source_tres = source_tres.duplicate(true)
	return copy

func to_dictionary() -> Dictionary:
	var result: Dictionary = {
		"id": id,
		"definition_id": definition_id,
		"tags": Array(tags),
		"description": description,
		"data": data.duplicate(true)
	}
	return result

static func from_dictionary(dict: Dictionary, db: PatternDatabaseFile = null) -> PdbModelInstance:
	var instance = PdbModelInstance.new()
	instance.id = dict.get("id", &"")
	instance.definition_id = dict.get("definition_id", &"")
	instance.tags = PackedStringArray(dict.get("tags", []))
	instance.description = dict.get("description", "")
	instance.data = dict.get("data", {}).duplicate(true)
	if db:
		instance.set_database(db)
	return instance

func get_field_value_as_string(field_name: StringName) -> String:
	var value = get_value(field_name)
	if value == null:
		return "<null>"

	var def = get_definition()
	if def:
		var field = def.get_field(field_name)
		if field and field.is_enum_field():
			var db = get_database()
			if db:
				var pdb_enum = db.get_pattern(field.hint_string)
				if pdb_enum is PdbEnum:
					var label: StringName = pdb_enum.get_name_for_value(int(value))
					if label != &"":
						return str(label)

	return str(value)

func _to_string() -> String:
	return "<PdbModelInstance:%s (def:%s)>" % [id, definition_id]
