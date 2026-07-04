@tool
class_name PdbObjectStore
extends RefCounted
## Content-addressed blob store for history objects.

const DIR_NAME := ".patterndb"

var root: String
var store: String

func _init(base_dir: String, db_key: String) -> void:
	root = base_dir
	store = base_dir.path_join(DIR_NAME).path_join(db_key)

func ensure_initialized() -> Error:
	for sub in ["", "objects"]:
		var p := store if sub == "" else store.path_join(sub)
		if not DirAccess.dir_exists_absolute(p):
			var e := DirAccess.make_dir_recursive_absolute(p)
			if e != OK:
				return e
	return OK

func put_object(content: String) -> String:
	var h := hash_string(content)
	var path := _object_path(h)
	if FileAccess.file_exists(path):
		return h
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(content)
	f.close()
	return h

func has_object(h: String) -> bool:
	return FileAccess.file_exists(_object_path(h))

func get_object(h: String) -> String:
	var path := _object_path(h)
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func verify_object(h: String) -> bool:
	if not has_object(h):
		return false
	return hash_string(get_object(h)) == h

func _object_path(h: String) -> String:
	return store.path_join("objects").path_join(h.substr(0, 2)).path_join(h.substr(2))

func write_ref(ref: String, value: String) -> Error:
	var p := store.path_join(ref)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_CREATE
	f.store_string(value)
	f.close()
	return OK

func read_ref(ref: String) -> String:
	var p := store.path_join(ref)
	if not FileAccess.file_exists(p):
		return ""
	return FileAccess.get_file_as_string(p).strip_edges()

static func hash_string(content: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(content.to_utf8_buffer())
	return ctx.finish().hex_encode()
