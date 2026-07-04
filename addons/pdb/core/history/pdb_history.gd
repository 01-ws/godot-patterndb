@tool
class_name PdbHistory
extends RefCounted
## Content-addressed, branchable commit tree.

var commits := {}
var checkpoints := {}
var head := ""
var branches := {}
var current_branch := "main"
var baseline := {}
var snapshots := {}

var checkpoint_interval := 25
var _forward := {}
var _seq := 0

func init_from_state(state: Dictionary) -> String:
	commits.clear()
	checkpoints.clear()
	branches.clear()
	snapshots.clear()
	_forward.clear()
	var root := _make_commit("", [], "initial state", [])
	var h := _hash_commit(root)
	root["hash"] = h
	commits[h] = root
	checkpoints[h] = _dup(state)
	head = h
	branches = {"main": h}
	current_branch = "main"
	baseline = _dup(state)
	return h

func commit(new_state: Dictionary, override_summary := "", kind := "edit") -> String:
	var ops := PdbDiff.diff(baseline, new_state)
	if ops.is_empty():
		return ""
	var summary := override_summary if override_summary != "" else PdbDiff.summarize(ops)
	var c := _make_commit(head, ops, summary, PdbDiff.affected_ids(ops), kind)
	var h := _hash_commit(c)
	c["hash"] = h
	commits[h] = c
	var prev := head
	head = h
	branches[current_branch] = h
	_forward[prev] = h
	baseline = _dup(new_state)
	if _depth(h) % checkpoint_interval == 0:
		checkpoints[h] = _dup(new_state)
	return h

func commit_external(new_state: Dictionary) -> String:
	return commit(new_state, "external edit detected", "external")

func can_undo() -> bool:
	return commits.has(head) and String(commits[head].get("parent", "")) != ""

func can_redo() -> bool:
	return not children_of(head).is_empty()

func undo() -> Dictionary:
	if not can_undo():
		return {}
	return jump_to(String(commits[head]["parent"]))

func redo() -> Dictionary:
	var child := String(_forward.get(head, ""))
	if child == "" or not commits.has(child):
		var kids := children_of(head)
		if kids.is_empty():
			return {}
		child = kids[0]
	return jump_to(child)

func jump_to(target: String) -> Dictionary:
	if not commits.has(target):
		return {}
	var state := reconstruct(target)
	if String(commits[head].get("parent", "")) == target:
		_forward[target] = head
	head = target
	baseline = _dup(state)
	for name in branches:
		if branches[name] == target:
			current_branch = name
			break
	return state

func reconstruct(target: String) -> Dictionary:
	var lineage := _lineage(target)
	if lineage.is_empty():
		return {}
	var start_i := -1
	for i in range(lineage.size() - 1, -1, -1):
		if checkpoints.has(lineage[i]):
			start_i = i
			break
	if start_i == -1 or not (checkpoints[lineage[start_i]] is Dictionary):
		push_warning("[PDB] History: no checkpoint on lineage for %s; skipping reconstruct." % target)
		return {}
	var state: Dictionary = _dup(checkpoints[lineage[start_i]])
	for j in range(start_i + 1, lineage.size()):
		PdbDiff.apply_ops(state, commits[lineage[j]]["ops"])
	return state

func _lineage(target: String) -> Array:
	var chain: Array = []
	var cur := target
	while cur != "" and commits.has(cur):
		chain.push_front(cur)
		cur = String(commits[cur].get("parent", ""))
	return chain

func children_of(h: String) -> Array:
	var out: Array = []
	for k in commits:
		if String(commits[k].get("parent", "")) == h:
			out.append(k)
	return out

func create_branch(name: String) -> void:
	branches[name] = head
	current_branch = name

func create_snapshot(commit: String, label := "") -> String:
	var idx := 1
	while snapshots.has(str(idx)):
		idx += 1
	snapshots[str(idx)] = {"commit": commit, "label": label}
	return str(idx)
func delta(from_commit: String, to_commit: String) -> Array:
	return PdbDiff.diff(reconstruct(from_commit), reconstruct(to_commit))
func _depth(h: String) -> int:
	return _lineage(h).size() - 1

func _make_commit(parent: String, ops: Array, summary: String, affected: Array, kind := "edit") -> Dictionary:
	_seq += 1
	return {
		"parent": parent,
		"ops": ops,
		"summary": summary,
		"affected": affected,
		"kind": kind,
		"ts": Time.get_unix_time_from_system(),
		"nonce": _seq,
	}

func commit_payload(c: Dictionary) -> Dictionary:
	return {
		"parent": c["parent"], "ops": c["ops"], "summary": c["summary"],
		"affected": c["affected"], "kind": c.get("kind", "edit"),
		"ts": c["ts"], "nonce": c["nonce"],
	}

func _hash_commit(c: Dictionary) -> String:
	return PdbCanonical.sha256(PdbCanonical.serialize(commit_payload(c)))

func _dup(v):
	return v.duplicate(true) if (v is Dictionary or v is Array) else v
