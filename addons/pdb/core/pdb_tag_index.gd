@tool
class_name PdbTagIndex
extends RefCounted
## Hierarchical tag index (dot.paths roll up).

var _registered: Dictionary = {}
var _path_to_ids: Dictionary = {}

static func build(db: PatternDatabaseFile) -> PdbTagIndex:
	var idx := PdbTagIndex.new()
	if db == null:
		return idx
	for key in db.patterns:
		var p = db.patterns[key]
		if not p is PdbPattern:
			continue
		for raw in p.tags:
			var path := str(raw)
			if path == "":
				continue
			idx._register_path(path)
			if not idx._path_to_ids.has(path):
				idx._path_to_ids[path] = []
			idx._path_to_ids[path].append(p.id)
	return idx

func _register_path(path: String) -> void:
	var parts := path.split(".")
	var cur := ""
	var parent: PdbTag = null
	for part in parts:
		cur = part if cur == "" else cur + "." + part
		if not _registered.has(cur):
			var tag := PdbTag.create(part)
			if parent:
				parent.add_child(tag)
			_registered[cur] = tag
		parent = _registered[cur]

func get_tag(path: String) -> PdbTag:
	return _registered.get(path)

func all_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	for k in _path_to_ids.keys():
		out.append(k)
	out.sort()
	return out

func count(path: String) -> int:
	var arr: Array = _path_to_ids.get(path, [])
	return arr.size()

func ids_with_tag(path: String, exact: bool = true) -> Array:
	if exact:
		var arr: Array = _path_to_ids.get(path, [])
		return arr.duplicate()
	var result: Array = []
	var target: PdbTag = _registered.get(path)
	if target == null:
		return result
	var paths: Array = [target.get_full_path()]
	for child in target.get_all_children():
		paths.append(child.get_full_path())
	for pth in paths:
		for id in _path_to_ids.get(pth, []):
			if not id in result:
				result.append(id)
	return result
