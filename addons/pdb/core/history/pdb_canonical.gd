@tool
class_name PdbCanonical
extends RefCounted
## Canonical (de)serialization and deterministic hashing for history.

static func to_canonical(pattern: PdbPattern) -> Dictionary:
	var base := {
		"id": String(pattern.id),
		"tags": Array(pattern.tags),
		"description": pattern.description,
	}
	if pattern is PdbEnum:
		base["kind"] = "enum"
		base["values"] = _canon_value(pattern.values)
	elif pattern is PdbConst:
		base["kind"] = "const"
		base["data"] = _canon_value(pattern.data)
	elif pattern is PdbModelDefinition:
		base["kind"] = "definition"
		base["extends_type"] = pattern.extends_type
		base["icon_name"] = pattern.icon_name
		var fields: Array = []
		for f in pattern.fields:
			fields.append(_field_to_canonical(f))
		base["fields"] = fields
	elif pattern is PdbModelInstance:
		base["kind"] = "instance"
		base["definition_id"] = String(pattern.definition_id)
		base["data"] = _canon_value(pattern.data)
	return base

static func _field_to_canonical(f: PdbFieldDefinition) -> Dictionary:
	return {
		"name": String(f.field_name),
		"type": int(f.field_type),
		"hint": int(f.hint),
		"hint_string": f.hint_string,
		"export_group": f.export_group,
		"description": f.description,
		"required": f.required,
		"default": f.default_value,
	}

static func to_canonical_db(db: PatternDatabaseFile) -> Dictionary:
	var out := {}
	for key in db.patterns:
		out[String(key)] = to_canonical(db.patterns[key])
	return out

static func from_canonical(dict: Dictionary) -> PdbPattern:
	var pattern: PdbPattern = null
	match String(dict.get("kind", "")):
		"enum":
			var e := PdbEnum.new()
			e.values = _canon_value(dict.get("values", {}))
			pattern = e
		"const":
			var c := PdbConst.new()
			c.data = _canon_value(dict.get("data", {}))
			pattern = c
		"definition":
			var d := PdbModelDefinition.new()
			d.extends_type = dict.get("extends_type", "Resource")
			d.icon_name = dict.get("icon_name", "Object")
			for fd in dict.get("fields", []):
				d.fields.append(_field_from_canonical(fd))
			pattern = d
		"instance":
			var i := PdbModelInstance.new()
			i.definition_id = StringName(dict.get("definition_id", ""))
			i.data = _canon_value(dict.get("data", {}))
			pattern = i
		_:
			return null
	pattern.id = StringName(dict.get("id", ""))
	pattern.tags = PackedStringArray(dict.get("tags", []))
	pattern.description = dict.get("description", "")
	pattern.resource_name = String(pattern.id)
	return pattern

static func _field_from_canonical(fd: Dictionary) -> PdbFieldDefinition:
	var f := PdbFieldDefinition.new()
	f.field_name = StringName(fd.get("name", ""))
	f.field_type = fd.get("type", TYPE_STRING)
	f.hint = fd.get("hint", PROPERTY_HINT_NONE)
	f.hint_string = fd.get("hint_string", "")
	f.export_group = fd.get("export_group", "")
	f.description = fd.get("description", "")
	f.required = fd.get("required", false)
	f.default_value = fd.get("default", null)
	return f

static func from_canonical_db(state: Dictionary) -> PatternDatabaseFile:
	var db := PatternDatabaseFile.new()
	for id in state:
		var p := from_canonical(state[id])
		if p:
			db.patterns[StringName(id)] = p
	for key in db.patterns:
		var p = db.patterns[key]
		if p is PdbModelInstance:
			p.set_database(db)
	return db

static func serialize(canonical: Variant) -> String:
	return var_to_str(normalize(canonical))

static func deserialize(text: String) -> Variant:
	return str_to_var(text)

static func hash_of(canonical: Variant) -> String:
	return sha256(serialize(canonical))

static func sha256(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

static func normalize(v: Variant) -> Variant:
	if v is Dictionary:
		var keys: Array = (v as Dictionary).keys()
		keys.sort()
		var out := {}
		for k in keys:
			out[k] = normalize(v[k])
		return out
	if v is Array:
		var out: Array = []
		for e in v:
			out.append(normalize(e))
		return out
	return v

static func _canon_value(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[String(k)] = _canon_value(v[k])
		return out
	if v is Array:
		var out: Array = []
		for e in v:
			out.append(_canon_value(e))
		return out
	return v
