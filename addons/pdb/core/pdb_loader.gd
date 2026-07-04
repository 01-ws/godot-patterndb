@tool
class_name PdbLoader
extends ResourceFormatLoader
## ResourceFormatLoader for the .pdb extension.

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["pdb"])

func _get_resource_type(path: String) -> String:
	if path.get_extension().to_lower() == "pdb":
		return "Resource"
	return ""

func _handles_type(type: StringName) -> bool:
	return type == &"Resource" or type == &"PatternDatabaseFile"

func _load(path: String, original_path: String, use_sub_threads: bool, cache_mode: int) -> Variant:
	PdbLog.info(PdbIO._tag(), "Loading: %s" % path)

	if not FileAccess.file_exists(path):
		PdbLog.error(PdbIO._tag(), "File not found: %s" % path)
		return ERR_FILE_NOT_FOUND

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		PdbLog.error(PdbIO._tag(), "Cannot open file: %s" % path)
		return FileAccess.get_open_error()

	var header := file.get_buffer(4)
	file.close()

	var res: Resource
	if header.size() >= 4 and header[0] == 0x52 and header[1] == 0x53 and header[2] == 0x52 and header[3] == 0x43:
		PdbLog.info(PdbIO._tag(), "Detected Godot binary format")
		res = _load_with_extension(path, "res", true)
	else:
		PdbLog.info(PdbIO._tag(), "Loading as text resource")
		res = _load_with_extension(path, "tres", false)

	if res == null:
		PdbLog.error(PdbIO._tag(), "Failed to parse resource: %s" % path)
		return ERR_FILE_CORRUPT

	var ignore_cache := (
		cache_mode == ResourceLoader.CACHE_MODE_IGNORE
		or cache_mode == ResourceLoader.CACHE_MODE_IGNORE_DEEP
	)

	if ignore_cache:
		res.resource_path = ""
	elif ResourceLoader.has_cached(path):
		res.take_over_path(path)
	else:
		res.resource_path = path

	if not ignore_cache and res is PatternDatabaseFile:
		var report := PdbMigrations.reconcile(res as PatternDatabaseFile)
		match report["status"]:
			"newer":
				PdbLog.error(PdbIO._tag(), "Format v%d newer than supported v%d (read-only): %s" % [report["from"], report["to"], path])
			"migrated":
				PdbLog.info(PdbIO._tag(), "Migrated %s: format v%d -> v%d" % [path, report["from"], report["to"]])
	return res

func _load_with_extension(path: String, ext: String, binary: bool) -> Resource:
	var temp_path := PdbIO._unique_temp_path(ext)

	var src := FileAccess.open(path, FileAccess.READ)
	if not src:
		return null

	var dst := FileAccess.open(temp_path, FileAccess.WRITE)
	if not dst:
		src.close()
		PdbLog.error(PdbIO._tag(), "Cannot create temp file: %s" % temp_path)
		return null

	if binary:
		dst.store_buffer(src.get_buffer(src.get_length()))
	else:
		dst.store_string(src.get_as_text())

	src.close()
	dst.close()

	var res := ResourceLoader.load(temp_path, "", ResourceLoader.CACHE_MODE_IGNORE)

	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)

	return res
