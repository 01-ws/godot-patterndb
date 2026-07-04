@tool
class_name PatternDB
extends RefCounted
## Static entry points: load, bind, create, and save .pdb databases.

static func load_pdb(path: String = "") -> PatternDatabaseFile:
	if path.is_empty():
		PdbLog.error("PatternDB", "load_pdb requires a path, e.g. res://your_database.pdb")
		return null

	if not FileAccess.file_exists(path):
		PdbLog.error("PatternDB", "No PDB file found at %s" % path)
		return null

	var db := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as PatternDatabaseFile

	if db == null:
		var loader = PdbLoader.new()
		var res = loader._load(path, path, false, ResourceLoader.CACHE_MODE_IGNORE)
		if res is PatternDatabaseFile:
			db = res

	if db == null:
		PdbLog.error("PatternDB", "Failed to load PDB at %s" % path)
		return null

	PdbMigrations.reconcile(db)
	bind_database(db)
	return db

static func bind_database(db: PatternDatabaseFile) -> void:
	if db == null:
		return
	for key in db.patterns:
		var p = db.patterns[key]
		if p is PdbModelInstance:
			p.set_database(db)

static func create() -> PatternDatabaseFile:
	var db := PatternDatabaseFile.new()
	db.ensure_uid()
	return db

static func save_pdb(db: PatternDatabaseFile, path: String) -> Error:
	if not db:
		return ERR_INVALID_PARAMETER
	db.resource_path = path
	var saver := PdbSaver.new()
	return saver._save(db, path, 0)
