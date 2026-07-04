@tool
class_name PdbQuery
extends RefCounted
## Read-only query helper over a database, with a cached tag index.

var _db: PatternDatabaseFile
var _index: PdbTagIndex = null

func _init(database: PatternDatabaseFile = null) -> void:
	_db = database

func refresh() -> void:
	_index = null

func _tag_index() -> PdbTagIndex:
	if _index == null:
		_index = PdbTagIndex.build(_db)
	return _index

func pattern(id) -> PdbPattern:
	if _db == null:
		return null
	return _db.get_pattern(id)

func instance(id) -> PdbModelInstance:
	return pattern(id) as PdbModelInstance

func value(id, field_name: String) -> Variant:
	var inst := instance(id)
	if inst == null:
		return null
	return inst.get_value(field_name)

func resource(id, field_name: String) -> Resource:
	var inst := instance(id)
	if inst == null:
		return null
	return inst.get_resource(field_name)

func ids() -> Array:
	if _db == null:
		return []
	return _db.patterns.keys()

func instances_of(definition_name) -> Array:
	if _db == null:
		return []
	return _db.get_instances_of_definition(definition_name)

func all_tags() -> PackedStringArray:
	return _tag_index().all_paths()

func count_with_tag(tag: String, exact: bool = true) -> int:
	return _tag_index().ids_with_tag(tag, exact).size()

func with_tag(tag: String, exact: bool = true) -> Array:
	return _resolve(_tag_index().ids_with_tag(tag, exact))

func with_all_tags(tags: Array, exact: bool = true) -> Array:
	if tags.is_empty():
		return []
	var result: Array = with_tag(str(tags[0]), exact)
	for i in range(1, tags.size()):
		var t := str(tags[i])
		result = result.filter(func(p): return _carries(p, t, exact))
	return result

func with_any_tags(tags: Array, exact: bool = true) -> Array:
	var seen: Dictionary = {}
	var result: Array = []
	for t in tags:
		for p in with_tag(str(t), exact):
			if not seen.has(p.id):
				seen[p.id] = true
				result.append(p)
	return result

func _resolve(id_list: Array) -> Array:
	var out: Array = []
	for id in id_list:
		var p := pattern(id)
		if p != null:
			out.append(p)
	return out

func _carries(p: PdbPattern, tag: String, exact: bool) -> bool:
	if exact:
		return tag in p.tags
	for raw in p.tags:
		var t := str(raw)
		if t == tag or t.begins_with(tag + "."):
			return true
	return false
