@tool
class_name PdbMigrations
extends RefCounted
## .pdb format migrations. An unimplemented step marks the file incompatible and blocks saving.

const CURRENT_FORMAT_VERSION := 1

static func reconcile(db: PatternDatabaseFile) -> Dictionary:
	if db == null:
		return {"status": "ok", "from": 0, "to": CURRENT_FORMAT_VERSION, "notes": []}

	var from_v := db.format_version
	if from_v <= 0:
		from_v = 1

	if from_v > CURRENT_FORMAT_VERSION:
		db.incompatible = true
		return {"status": "newer", "from": from_v, "to": CURRENT_FORMAT_VERSION, "notes": []}

	var notes: Array = []
	var v := from_v
	while v < CURRENT_FORMAT_VERSION:
		var note := _apply_step(db, v)
		if note == "":
			push_error("[PDB] No migration step from format v%d to v%d — add a branch in PdbMigrations._apply_step." % [v, v + 1])
			db.incompatible = true
			return {"status": "error", "from": from_v, "to": CURRENT_FORMAT_VERSION, "notes": notes}
		notes.append(note)
		v += 1

	db.incompatible = false
	db.format_version = CURRENT_FORMAT_VERSION
	var status := "migrated" if not notes.is_empty() else "ok"
	return {"status": status, "from": from_v, "to": CURRENT_FORMAT_VERSION, "notes": notes}

static func is_newer(db: PatternDatabaseFile) -> bool:
	return db != null and db.format_version > CURRENT_FORMAT_VERSION

static func _apply_step(db: PatternDatabaseFile, from_v: int) -> String:
	# One branch per version bump. An empty return means "unimplemented" and is
	# treated as a hard error by reconcile(); a bump with no data change must
	# still return a note.
	match from_v:
		_:
			return ""
