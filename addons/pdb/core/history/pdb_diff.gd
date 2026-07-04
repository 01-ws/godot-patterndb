@tool
class_name PdbDiff
extends RefCounted
## Structural diff/patch over canonical states; apply(diff(a,b)) on a yields b.

const HEADER_KEYS := ["tags", "description", "definition_id", "extends_type", "icon_name"]

static func diff(old_state: Dictionary, new_state: Dictionary) -> Array:
	var ops: Array = []
	for id in new_state:
		if not old_state.has(id):
			ops.append({"op": "add", "path": id, "after": _dup(new_state[id])})
	for id in old_state:
		if not new_state.has(id):
			ops.append({"op": "remove", "path": id, "before": _dup(old_state[id])})
	for id in new_state:
		if old_state.has(id):
			_diff_pattern(id, old_state[id], new_state[id], ops)
	return ops

static func _diff_pattern(id: String, o: Dictionary, n: Dictionary, ops: Array) -> void:
	if o.get("kind", "") != n.get("kind", ""):
		ops.append({"op": "remove", "path": id, "before": _dup(o)})
		ops.append({"op": "add", "path": id, "after": _dup(n)})
		return
	for key in HEADER_KEYS:
		if o.has(key) or n.has(key):
			if o.get(key) != n.get(key):
				ops.append({"op": "set", "path": "%s/%s" % [id, key], "before": o.get(key), "after": n.get(key)})
	for section in ["data", "values"]:
		if o.has(section) or n.has(section):
			_diff_dict("%s/%s" % [id, section], o.get(section, {}), n.get(section, {}), ops)
	if o.has("fields") or n.has("fields"):
		_diff_fields(id, o.get("fields", []), n.get("fields", []), ops)

static func _diff_dict(prefix: String, od: Dictionary, nd: Dictionary, ops: Array) -> void:
	for k in nd:
		if not od.has(k):
			ops.append({"op": "add", "path": "%s/%s" % [prefix, k], "after": _dup(nd[k])})
		elif od[k] != nd[k]:
			ops.append({"op": "set", "path": "%s/%s" % [prefix, k], "before": _dup(od[k]), "after": _dup(nd[k])})
	for k in od:
		if not nd.has(k):
			ops.append({"op": "remove", "path": "%s/%s" % [prefix, k], "before": _dup(od[k])})

static func _diff_fields(id: String, of: Array, nf: Array, ops: Array) -> void:
	var oi := {}
	var ni := {}
	for f in of:
		oi[String(f["name"])] = f
	for f in nf:
		ni[String(f["name"])] = f
	for name in ni:
		if not oi.has(name):
			ops.append({"op": "add", "path": "%s/fields/%s" % [id, name], "after": _dup(ni[name])})
		elif oi[name] != ni[name]:
			ops.append({"op": "set", "path": "%s/fields/%s" % [id, name], "before": _dup(oi[name]), "after": _dup(ni[name])})
	for name in oi:
		if not ni.has(name):
			ops.append({"op": "remove", "path": "%s/fields/%s" % [id, name], "before": _dup(oi[name])})
	var o_common: Array = []
	var n_common: Array = []
	for f in of:
		if ni.has(String(f["name"])):
			o_common.append(String(f["name"]))
	for f in nf:
		if oi.has(String(f["name"])):
			n_common.append(String(f["name"]))
	if o_common != n_common:
		var order: Array = []
		for f in nf:
			order.append(String(f["name"]))
		ops.append({"op": "reorder", "path": "%s/fields" % id, "before": o_common, "after": order})

static func apply_ops(state: Dictionary, ops: Array) -> void:
	for op in ops:
		apply_op(state, op)

static func apply_op(state: Dictionary, op: Dictionary) -> void:
	var kind: String = op["op"]
	var segs := String(op["path"]).split("/")
	var id: String = segs[0]

	if segs.size() == 1:
		if kind == "remove":
			state.erase(id)
		else:
			state[id] = _dup(op.get("after"))
		return

	if not state.has(id):
		return
	var p: Dictionary = state[id]

	if segs.size() == 2:
		var key: String = segs[1]
		if key == "fields" and kind == "reorder":
			_apply_reorder(p, op.get("after", []))
		elif kind == "remove":
			p.erase(key)
		else:
			p[key] = _dup(op.get("after"))
		return

	var section: String = segs[1]
	var key2: String = segs[2]
	if section == "fields":
		_apply_field_op(p, kind, key2, op)
	else:
		if not p.has(section):
			p[section] = {}
		if kind == "remove":
			p[section].erase(key2)
		else:
			p[section][key2] = _dup(op.get("after"))

static func _apply_field_op(p: Dictionary, kind: String, name: String, op: Dictionary) -> void:
	if not p.has("fields"):
		p["fields"] = []
	var fields: Array = p["fields"]
	var idx := -1
	for i in fields.size():
		if String(fields[i]["name"]) == name:
			idx = i
			break
	if kind == "remove":
		if idx >= 0:
			fields.remove_at(idx)
	else:
		if idx >= 0:
			fields[idx] = _dup(op.get("after"))
		else:
			fields.append(_dup(op.get("after")))

static func _apply_reorder(p: Dictionary, order: Array) -> void:
	if not p.has("fields"):
		return
	var by_name := {}
	for f in p["fields"]:
		by_name[String(f["name"])] = f
	var out: Array = []
	for nm in order:
		if by_name.has(nm):
			out.append(by_name[nm])
	for f in p["fields"]:
		if not (String(f["name"]) in order):
			out.append(f)
	p["fields"] = out

static func affected_ids(ops: Array) -> Array:
	var seen := {}
	for op in ops:
		seen[String(op["path"]).split("/")[0]] = true
	return seen.keys()

static func list_label(ops: Array) -> String:
	if ops.is_empty():
		return ""
	var affected := affected_ids(ops)
	if affected.size() > 1:
		return "%s  +%d more" % [String(affected[0]), affected.size() - 1]
	var id: String = String(affected[0]) if not affected.is_empty() else String(ops[0].get("path")).split("/")[0]
	for op in ops:
		if String(op["path"]) == id:
			if op["op"] == "add":
				return "＋ %s" % id
			if op["op"] == "remove":
				return "－ %s" % id
	var keys: Array = []
	for op in ops:
		var segs := String(op["path"]).split("/")
		var leaf := String(segs[segs.size() - 1])
		if leaf != id and not keys.has(leaf):
			keys.append(leaf)
	if keys.size() == 1:
		return "%s  (%s)" % [id, keys[0]]
	if keys.is_empty():
		return id
	return "%s  (%d fields)" % [id, keys.size()]

static func summarize(ops: Array) -> String:
	if ops.is_empty():
		return "no changes"
	if ops.size() == 1:
		return describe_op(ops[0])
	var affected := affected_ids(ops)
	if affected.size() == 1:
		var parts: Array = []
		for op in ops:
			parts.append(describe_op(op))
		var shown := parts.slice(0, 3)
		var joined := ", ".join(PackedStringArray(shown))
		if parts.size() > 3:
			joined += " (+%d more)" % (parts.size() - 3)
		return "%s: %s" % [affected[0], joined]
	return "%d objects changed" % affected.size()

static func describe_op(op: Dictionary, full := false) -> String:
	var kind: String = op["op"]
	var segs := String(op["path"]).split("/")

	if segs.size() == 1:
		var pid: String = segs[0]
		if kind == "add":
			return "added %s %s" % [_kind_of(op.get("after")), pid]
		if kind == "remove":
			return "removed %s %s" % [_kind_of(op.get("before")), pid]
		return "changed %s" % pid

	if kind == "reorder":
		return "reordered fields on %s" % segs[0]

	var leaf: String = segs[segs.size() - 1]
	var is_field := segs.size() >= 3 and segs[1] == "fields"

	if kind == "add":
		if is_field:
			return "added field %s" % leaf
		return "set %s = %s" % [leaf, _fmt(op.get("after"), full)]
	if kind == "remove":
		if is_field:
			return "removed field %s" % leaf
		return "cleared %s" % leaf

	var b = op.get("before")
	var a = op.get("after")
	if (b is int or b is float) and (a is int or a is float):
		var verb := "changed"
		if a > b:
			verb = "incremented"
		elif a < b:
			verb = "decreased"
		return "%s %s %s→%s" % [leaf, verb, _fmt(b, full), _fmt(a, full)]
	if full and ((b is String and b.length() > 40) or (a is String and a.length() > 40)):
		return "%s changed:\n        − %s\n        + %s" % [leaf, _fmt(b, true), _fmt(a, true)]
	return "%s changed %s→%s" % [leaf, _fmt(b, full), _fmt(a, full)]

static func _kind_of(pattern_canonical) -> String:
	if pattern_canonical is Dictionary:
		return String(pattern_canonical.get("kind", "object"))
	return "object"

static func _fmt(v, full := false) -> String:
	if v == null:
		return "∅"
	if v is String:
		var s: String = v if (full or v.length() <= 24) else v.substr(0, 21) + "…"
		return "\"%s\"" % s
	if v is StringName:
		return "&\"%s\"" % String(v)
	if v is float:
		return str(snappedf(v, 0.001))
	return str(v)

static func _dup(v):
	return v.duplicate(true) if (v is Dictionary or v is Array) else v

static func render_ops(ops: Array) -> String:
	if ops.is_empty():
		return "No changes."
	var by_id := {}
	var order: Array = []
	for op in ops:
		var id := String(op["path"]).split("/")[0]
		if not by_id.has(id):
			by_id[id] = []
			order.append(id)
		by_id[id].append(op)
	var lines: Array = []
	for id in order:
		var group: Array = by_id[id]
		var whole_add := false
		var whole_remove := false
		for op in group:
			if String(op["path"]) == id:
				if op["op"] == "add":
					whole_add = true
				elif op["op"] == "remove":
					whole_remove = true
		if whole_add:
			lines.append("+ %s  (%s)" % [id, _kind_of(_after_of(group, id))])
		elif whole_remove:
			lines.append("− %s  (%s)" % [id, _kind_of(_before_of(group, id))])
		else:
			lines.append("~ %s" % id)
			for op in group:
				lines.append("      " + describe_op(op, true))
	return "\n".join(PackedStringArray(lines))

static func _after_of(group: Array, id: String):
	for op in group:
		if String(op["path"]) == id:
			return op.get("after")
	return null

static func _before_of(group: Array, id: String):
	for op in group:
		if String(op["path"]) == id:
			return op.get("before")
	return null
