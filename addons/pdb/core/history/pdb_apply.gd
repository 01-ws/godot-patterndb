@tool
class_name PdbApply
extends RefCounted
## Applies diff operations to a canonical state.

static func sync_db(db: PatternDatabaseFile, target_state: Dictionary) -> Dictionary:
	var current := PdbCanonical.to_canonical_db(db)
	var added: Array = []
	var changed: Array = []
	var removed: Array = []

	for id in current:
		if not target_state.has(id):
			db.patterns.erase(StringName(id))
			removed.append(id)

	for id in target_state:
		if not current.has(id):
			db.patterns[StringName(id)] = PdbCanonical.from_canonical(target_state[id])
			added.append(id)
		elif current[id] != target_state[id]:
			db.patterns[StringName(id)] = PdbCanonical.from_canonical(target_state[id])
			changed.append(id)

	for key in db.patterns:
		var p = db.patterns[key]
		if p is PdbModelInstance:
			p.set_database(db)

	return {"added": added, "changed": changed, "removed": removed}
