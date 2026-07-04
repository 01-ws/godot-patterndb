@tool
class_name PdbHistoryController
extends RefCounted
## Binds history capture to editor edits; auto-capture is bounded on large databases.

var history: PdbHistory = null
var store: PdbHistoryStore = null
var db: PatternDatabaseFile = null
var db_key: String = ""
var db_path: String = ""
var enabled: bool = false

const AUTO_CAPTURE_MAX_PATTERNS := 4000
var auto_capture_suspended: bool = false

func bind(database: PatternDatabaseFile, path: String) -> void:
	enabled = false
	history = null
	store = null
	db = database
	db_key = ""
	db_path = path
	if database == null or path == "" or path.begins_with("uid://"):
		return

	var base_dir := path.get_base_dir()
	db_key = _db_key(path, database)
	store = PdbHistoryStore.new(base_dir, db_key)

	var loaded := store.load()
	if loaded != null:
		history = loaded
		store.reconcile(history, db)
	else:
		history = PdbHistory.new()
		history.init_from_state(PdbCanonical.to_canonical_db(db))
	enabled = true

func capture() -> String:
	if not enabled or history == null or db == null:
		return ""
	if db.patterns.size() > AUTO_CAPTURE_MAX_PATTERNS:
		if not auto_capture_suspended:
			auto_capture_suspended = true
			push_warning("[PDB] History auto-capture suspended for a large database (%d patterns); saves still persist existing history." % db.patterns.size())
		return ""
	auto_capture_suspended = false
	return history.commit(PdbCanonical.to_canonical_db(db))

func persist() -> void:
	if not enabled or history == null or store == null:
		return
	store.save(history)

func restore(commit_hash: String) -> Dictionary:
	if not enabled or history == null or db == null:
		return {}
	var state := history.jump_to(commit_hash)
	if state.is_empty():
		return {}
	return PdbApply.sync_db(db, state)

func undo() -> Dictionary:
	if not enabled or history == null or db == null:
		return {}
	var state := history.undo()
	if state.is_empty():
		return {}
	return PdbApply.sync_db(db, state)

func redo() -> Dictionary:
	if not enabled or history == null or db == null:
		return {}
	var state := history.redo()
	if state.is_empty():
		return {}
	return PdbApply.sync_db(db, state)

func can_undo() -> bool:
	return enabled and history != null and history.can_undo()

func can_redo() -> bool:
	return enabled and history != null and history.can_redo()

func list_branches() -> Array:
	if not enabled or history == null:
		return []
	var names := history.branches.keys()
	names.sort()
	return names

func current_branch() -> String:
	return history.current_branch if (enabled and history != null) else ""

func switch_branch(name: String) -> Dictionary:
	if not enabled or history == null or not history.branches.has(name):
		return {}
	var state := history.jump_to(String(history.branches[name]))
	if state.is_empty():
		return {}
	history.current_branch = name
	return PdbApply.sync_db(db, state)

func export_snapshot(commit_hash: String, label := "") -> String:
	if not enabled or history == null or db_path == "":
		return ""
	if not history.commits.has(commit_hash):
		return ""
	var state := history.reconstruct(commit_hash)
	var snap_db := PdbCanonical.from_canonical_db(state)
	var out := _next_snapshot_path()
	snap_db.resource_path = out
	if PdbSaver.new()._save(snap_db, out, 0) != OK:
		return ""
	history.create_snapshot(commit_hash, label if label != "" else out.get_file())
	return out

func _next_snapshot_path() -> String:
	var base := db_path.get_basename()
	var i := 1
	while FileAccess.file_exists("%s.%d.pdb" % [base, i]):
		i += 1
	return "%s.%d.pdb" % [base, i]

func _db_key(path: String, db: PatternDatabaseFile) -> String:
	# Identity comes from the database's stable db_uid when it has one, so a new
	# database reusing a previous file's name/path gets its own history. Files
	# without a uid (created before this field existed) fall back to the path so
	# their existing history is preserved.
	var seed := db.db_uid if (db and db.db_uid != "") else path
	var suffix := PdbObjectStore.hash_string(seed).substr(0, 12)
	return "%s-%s" % [_sanitize(path.get_file()), suffix]

func _sanitize(s: String) -> String:
	var safe := ""
	for i in s.length():
		var c := s[i]
		var ok := (c >= "0" and c <= "9") or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_" or c == "-"
		safe += c if ok else "_"
	return safe
