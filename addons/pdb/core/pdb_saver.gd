@tool
class_name PdbSaver
extends ResourceFormatSaver
## ResourceFormatSaver for the .pdb extension.

func _get_recognized_extensions(resource: Resource) -> PackedStringArray:
	if resource is PatternDatabaseFile:
		return PackedStringArray(["pdb"])
	return PackedStringArray()

func _recognize(resource: Resource) -> bool:
	return resource is PatternDatabaseFile

func _save(resource: Resource, path: String, flags: int) -> Error:
	PdbLog.info(PdbIO._tag(), "Saving: %s" % path)

	if not resource is PatternDatabaseFile:
		PdbLog.error(PdbIO._tag(), "Not a PatternDatabaseFile")
		return ERR_INVALID_PARAMETER

	var db := resource as PatternDatabaseFile

	if db.incompatible:
		PdbLog.error(PdbIO._tag(), "Refusing to save: format is newer than this addon supports.")
		return ERR_UNAVAILABLE

	db.format_version = PdbMigrations.CURRENT_FORMAT_VERSION

	var temp_path := PdbIO._unique_temp_path("tres")
	var old_path := resource.resource_path
	resource.resource_path = temp_path

	var err := ResourceSaver.save(resource, temp_path)
	resource.resource_path = old_path

	if err != OK:
		PdbLog.error(PdbIO._tag(), "Failed to serialize temp file: %d" % err)
		_cleanup(temp_path)
		return err

	var src := FileAccess.open(temp_path, FileAccess.READ)
	if not src:
		PdbLog.error(PdbIO._tag(), "Cannot read temp file")
		_cleanup(temp_path)
		return ERR_FILE_CANT_READ

	var data := src.get_as_text()
	src.close()

	var dst := FileAccess.open(path, FileAccess.WRITE)
	if not dst:
		PdbLog.error(PdbIO._tag(), "Cannot write to: %s" % path)
		_cleanup(temp_path)
		return FileAccess.get_open_error()

	dst.store_string(data)
	dst.close()

	_cleanup(temp_path)
	PdbLog.info(PdbIO._tag(), "Save complete: %s" % path)
	return OK

func _cleanup(temp_path: String) -> void:
	if FileAccess.file_exists(temp_path):
		DirAccess.remove_absolute(temp_path)
