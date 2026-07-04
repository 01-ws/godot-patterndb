@tool
class_name PdbHistoryStore
extends RefCounted
## Sidecar persistence under .patterndb/<db-key>/. Never load-bearing.

const MANIFEST_FORMAT := 1
const MANIFEST_REF := "manifest.json"

var store: PdbObjectStore

func _init(base_dir: String, db_key: String) -> void:
	store = PdbObjectStore.new(base_dir, db_key)

func save(history: PdbHistory) -> Error:
	var e := store.ensure_initialized()
	if e != OK:
		return e

	for h in history.commits:
		var blob := PdbCanonical.serialize(history.commit_payload(history.commits[h]))
		var written := store.put_object(blob)
		if written != h:
			push_warning("PatternDB history: commit hash mismatch on save (%s != %s)" % [written, h])

	var checkpoints := {}
	for commit_hash in history.checkpoints:
		checkpoints[commit_hash] = store.put_object(PdbCanonical.serialize(history.checkpoints[commit_hash]))

	var manifest := {
		"format": MANIFEST_FORMAT,
		"head": history.head,
		"current_branch": history.current_branch,
		"branches": history.branches,
		"checkpoints": checkpoints,
		"snapshots": history.snapshots,
		"commits": history.commits.keys(),
	}
	return store.write_ref(MANIFEST_REF, JSON.stringify(manifest, "\t"))

func load() -> PdbHistory:
	var raw := store.read_ref(MANIFEST_REF)
	if raw == "":
		return null
	var manifest = JSON.parse_string(raw)
	if not (manifest is Dictionary):
		return null

	var history := PdbHistory.new()

	for h in manifest.get("commits", []):
		if not store.verify_object(h):
			continue
		var payload = PdbCanonical.deserialize(store.get_object(h))
		if not (payload is Dictionary):
			continue
		var commit: Dictionary = payload.duplicate(true)
		commit["hash"] = h
		history.commits[h] = commit

	var ckpts = manifest.get("checkpoints", {})
	for commit_hash in ckpts:
		var state_hash := String(ckpts[commit_hash])
		if store.verify_object(state_hash):
			var state = PdbCanonical.deserialize(store.get_object(state_hash))
			if state is Dictionary:
				history.checkpoints[commit_hash] = state

	history.head = String(manifest.get("head", ""))
	history.current_branch = String(manifest.get("current_branch", "main"))
	history.branches = manifest.get("branches", {})
	history.snapshots = manifest.get("snapshots", {})
	if history.commits.has(history.head) and _has_checkpoint_ancestor(history, history.head):
		history.baseline = history.reconstruct(history.head)
	return history

func exists() -> bool:
	return store.read_ref(MANIFEST_REF) != ""

func reconcile(history: PdbHistory, live_db: PatternDatabaseFile) -> String:
	var expected := {}
	if history.commits.has(history.head):
		expected = history.reconstruct(history.head)
	var actual := PdbCanonical.to_canonical_db(live_db)
	if expected == actual:
		return ""
	return history.commit_external(actual)

func _has_checkpoint_ancestor(history: PdbHistory, target: String) -> bool:
	var cur := target
	while cur != "" and history.commits.has(cur):
		if history.checkpoints.has(cur):
			return true
		cur = String(history.commits[cur].get("parent", ""))
	return false
