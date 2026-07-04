@tool
class_name PatternDatabaseFile
extends Resource
## The .pdb resource: patterns, format version, and export settings.

@export var version: int = 1

@export var format_version: int = 0

var incompatible: bool = false

@export var patterns: Dictionary = {}

@export var meta_data: Dictionary = {}

@export var export_tags_metadata: bool = true

@export var db_uid: String = ""

static func generate_uid() -> String:
	return "%x%x%x" % [Time.get_ticks_usec(), randi(), randi()]

func ensure_uid() -> String:
	if db_uid == "":
		db_uid = generate_uid()
	return db_uid

func add_pattern(pattern: PdbPattern) -> void:
	if not pattern or not PdbPattern.is_valid_identifier(pattern.id):
		PdbLog.error("DB", "Cannot add pattern with invalid id (empty or containing '/' '\\').")
		return
	patterns[pattern.id] = pattern
	emit_changed()

func get_pattern(id: StringName) -> PdbPattern:
	return patterns.get(id)

func remove_pattern(id: StringName) -> void:
	patterns.erase(id)
	emit_changed()

func has_pattern(id: StringName) -> bool:
	return patterns.has(id)

func get_patterns_of_type(type: Script) -> Array:
	var result: Array = []
	for key in patterns:
		var p = patterns[key]
		if p.get_script() == type:
			result.append(p)
	return result

func get_all_enums() -> Array[PdbEnum]:
	var result: Array[PdbEnum] = []
	for key in patterns:
		var p = patterns[key]
		if p is PdbEnum:
			result.append(p)
	return result

func get_all_consts() -> Array[PdbConst]:
	var result: Array[PdbConst] = []
	for key in patterns:
		var p = patterns[key]
		if p is PdbConst:
			result.append(p)
	return result

func get_all_definitions() -> Array[PdbModelDefinition]:
	var result: Array[PdbModelDefinition] = []
	for key in patterns:
		var p = patterns[key]
		if p is PdbModelDefinition:
			result.append(p)
	return result

func get_all_instances() -> Array[PdbModelInstance]:
	var result: Array[PdbModelInstance] = []
	for key in patterns:
		var p = patterns[key]
		if p is PdbModelInstance:
			result.append(p)
	return result

func get_instances_of_definition(definition_id: StringName) -> Array[PdbModelInstance]:
	var result: Array[PdbModelInstance] = []
	for key in patterns:
		var p = patterns[key]
		if p is PdbModelInstance and p.definition_id == definition_id:
			result.append(p)
	return result

func get_instances_including_subtypes(definition_id: StringName) -> Array[PdbModelInstance]:
	var valid := definition_and_subtypes(definition_id)
	var result: Array[PdbModelInstance] = []
	for key in patterns:
		var p = patterns[key]
		if p is PdbModelInstance and valid.has(p.definition_id):
			result.append(p)
	return result

func definition_and_subtypes(definition_id: StringName) -> Dictionary:
	var out := {definition_id: true}
	var changed := true
	while changed:
		changed = false
		for key in patterns:
			var p = patterns[key]
			if p is PdbModelDefinition and not out.has(p.id):
				if out.has(StringName(p.extends_type)):
					out[p.id] = true
					changed = true
	return out

func size() -> int:
	return patterns.size()

func clear() -> void:
	patterns.clear()
	emit_changed()
