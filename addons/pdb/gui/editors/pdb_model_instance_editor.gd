@tool
extends PdbPatternEditorBase

var database_ref: PatternDatabaseFile
var fields_container: VBoxContainer
var definition_picker: OptionButton
var no_definition_label: Label
var validation_label: Label
var _preview_dialog: AcceptDialog = null
var _preview_rect: TextureRect = null

func _log(msg: String) -> void:
	PdbLog.info("InstanceEditor", msg)

func set_database(db: PatternDatabaseFile) -> void:
	database_ref = db
	var instance = pattern as PdbModelInstance
	if instance:
		instance.set_database(db)
	_log("Database reference set")

func _setup_ui() -> void:
	var instance = pattern as PdbModelInstance
	if not instance:
		_log("ERROR: Pattern is not PdbModelInstance")
		return

	_log("Setting up UI for: %s (def: %s)" % [instance.id, instance.definition_id])

	var def_row = HBoxContainer.new()
	def_row.add_theme_constant_override("separation", 10)
	var def_label = Label.new()
	def_label.text = "Definition:"
	def_label.custom_minimum_size.x = 100

	definition_picker = OptionButton.new()
	definition_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	_populate_definition_picker()
	definition_picker.item_selected.connect(_on_definition_selected)

	var validate_btn = Button.new()
	validate_btn.text = "Validate"
	validate_btn.pressed.connect(_validate_instance)

	def_row.add_child(def_label)
	def_row.add_child(definition_picker)
	def_row.add_child(validate_btn)
	add_child(def_row)

	validation_label = Label.new()
	validation_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	validation_label.add_theme_font_size_override("font_size", 11)
	add_child(validation_label)

	add_child(HSeparator.new())

	no_definition_label = Label.new()
	no_definition_label.text = "Select a definition to edit fields"
	no_definition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_definition_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(no_definition_label)

	fields_container = VBoxContainer.new()
	fields_container.size_flags_horizontal = SIZE_EXPAND_FILL
	fields_container.add_theme_constant_override("separation", 8)
	add_child(fields_container)

	_select_current_definition()
	_rebuild_fields()

	_log("UI setup complete")

func _validate_instance() -> void:
	var instance = pattern as PdbModelInstance
	if not instance or not database_ref:
		return

	var issues = PdbValidator.validate_instance(instance, database_ref)

	if issues.is_empty():
		validation_label.text = "✓ Valid"
		validation_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
	else:
		var error_count = 0
		var warn_count = 0
		for issue in issues:
			if issue.severity == PdbValidator.Severity.ERROR:
				error_count += 1
			elif issue.severity == PdbValidator.Severity.WARNING:
				warn_count += 1

		if error_count > 0:
			validation_label.text = "✗ %d error(s), %d warning(s)" % [error_count, warn_count]
			validation_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		else:
			validation_label.text = "⚠ %d warning(s)" % warn_count
			validation_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))

func _populate_definition_picker() -> void:
	definition_picker.clear()
	definition_picker.add_item("(None)", 0)

	if not database_ref:
		_log("No database reference, cannot populate definitions")
		return

	var definitions: Array = []
	for key in database_ref.patterns:
		var p = database_ref.patterns[key]
		if p is PdbModelDefinition:
			definitions.append(p)

	definitions.sort_custom(func(a, b): return str(a.id) < str(b.id))

	for def in definitions:
		definition_picker.add_item(str(def.id))

	_log("Populated definition picker: %d definitions" % definitions.size())

func _select_current_definition() -> void:
	var instance = pattern as PdbModelInstance
	if not instance or instance.definition_id == &"":
		definition_picker.selected = 0
		return

	for i in range(definition_picker.item_count):
		if definition_picker.get_item_text(i) == str(instance.definition_id):
			definition_picker.selected = i
			_log("Selected definition: %s" % instance.definition_id)
			return

	_log("Definition not found: %s" % instance.definition_id)
	definition_picker.selected = 0

func _on_definition_selected(index: int) -> void:
	var instance = pattern as PdbModelInstance
	if not instance:
		return

	if index == 0:
		_log("Definition cleared")
		instance.definition_id = &""
		instance._definition_cache = null
	else:
		var def_id = definition_picker.get_item_text(index)
		_log("Definition selected: %s" % def_id)
		instance.definition_id = def_id
		instance._definition_cache = null
		instance._initialize_from_definition()

	instance.emit_changed()
	_rebuild_fields()
	validation_label.text = ""
	value_changed.emit()

func _rebuild_fields() -> void:
	_log("Rebuilding fields")

	for child in fields_container.get_children():
		child.queue_free()

	var instance = pattern as PdbModelInstance
	if not instance:
		return

	var definition = instance.get_definition()

	no_definition_label.visible = definition == null
	fields_container.visible = definition != null

	if not definition:
		_log("No definition, fields hidden")
		return

	_log("Building fields for definition: %s (%d fields)" % [definition.id, definition.fields.size()])

	var current_group: String = ""

	for field in definition.fields:
		if field.export_group != current_group:
			current_group = field.export_group
			if current_group != "":
				var group_header = _create_group_header(current_group)
				fields_container.add_child(group_header)

		var field_row = _create_field_editor(field, instance)
		fields_container.add_child(field_row)

	_log("Fields rebuilt: %d rows added" % fields_container.get_child_count())

func _create_group_header(group_name: String) -> Control:
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)

	var sep1 = HSeparator.new()
	sep1.size_flags_horizontal = SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = group_name
	label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))

	var sep2 = HSeparator.new()
	sep2.size_flags_horizontal = SIZE_EXPAND_FILL

	header.add_child(sep1)
	header.add_child(label)
	header.add_child(sep2)

	return header

func _create_field_editor(field: PdbFieldDefinition, instance: PdbModelInstance) -> Control:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label_box = VBoxContainer.new()
	label_box.custom_minimum_size.x = 150
	label_box.add_theme_constant_override("separation", 0)

	var label = Label.new()
	label.text = str(field.field_name).capitalize()
	if field.required:
		label.text += " *"
	label.tooltip_text = field.description if field.description != "" else str(field.field_name)
	label_box.add_child(label)

	var badge = _field_type_badge(field)
	if badge.link:
		var link = LinkButton.new()
		link.text = badge.text
		link.tooltip_text = "Go to %s" % badge.target
		link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		link.add_theme_font_size_override("font_size", 10)
		link.add_theme_color_override("font_color", Color(0.45, 0.62, 0.9))
		var nav_target: StringName = badge.target
		link.pressed.connect(func(): request_navigate.emit(nav_target))
		label_box.add_child(link)
	else:
		var type_label = Label.new()
		type_label.text = badge.text
		type_label.clip_text = true
		type_label.add_theme_font_size_override("font_size", 10)
		type_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		label_box.add_child(type_label)

	var current_value = instance.get_value(field.field_name)
	if current_value == null:
		current_value = field.get_default()

	var field_name = field.field_name
	var editor = _create_editor_for_field(field, current_value, func(new_val):
		_log("Field changed: %s = %s" % [field_name, new_val])
		instance.set_value(field_name, new_val)
		value_changed.emit()
	)
	editor.size_flags_horizontal = SIZE_EXPAND_FILL

	row.add_child(label_box)
	row.add_child(editor)

	return row

func _create_editor_for_field(field: PdbFieldDefinition, value: Variant, callback: Callable) -> Control:
	if field.is_enum_field():
		return _create_enum_editor(field, value, callback)

	if field.is_resource_field():
		if _is_pdb_definition(field.get_resource_type()):
			return _create_reference_picker(field, value, callback)
		return _create_resource_editor(field, value, callback)

	if field.is_array_field():
		return _create_array_editor(field, value, callback)

	if _is_enum_map_field(field):
		return _create_enum_map_editor(field, value, callback)

	return _create_typed_editor(field.field_type, field.hint, field.hint_string, value, callback)

func _field_type_badge(field: PdbFieldDefinition) -> Dictionary:
	if field.is_enum_field():
		return {"text": "enum \u00b7 %s" % field.hint_string, "target": StringName(field.hint_string), "link": true}

	if field.is_resource_field():
		var rt := field.get_resource_type()
		if _is_pdb_definition(rt):
			return {"text": "definition \u00b7 %s" % rt, "target": StringName(rt), "link": true}
		return {"text": "resource \u00b7 %s" % (rt if rt != "" else "Resource"), "target": &"", "link": false}

	if field.is_array_field():
		var et := field.get_array_element_type()
		if et != "" and _is_pdb_definition(et):
			return {"text": "definition \u00b7 %s" % et, "target": StringName(et), "link": true}
		if et != "" and _is_pdb_enum_name(et):
			return {"text": "enum \u00b7 %s" % et, "target": StringName(et), "link": true}
		if et != "":
			return {"text": "array \u00b7 %s" % et, "target": &"", "link": false}
		return {"text": "array", "target": &"", "link": false}

	if _is_enum_map_field(field):
		return {"text": "enum map \u00b7 %s" % field.hint_string, "target": StringName(field.hint_string), "link": true}

	return {"text": type_string(field.field_type), "target": &"", "link": false}

func _is_pdb_enum_name(type_name: String) -> bool:
	if not database_ref or type_name.is_empty():
		return false
	return database_ref.get_pattern(type_name) is PdbEnum

func _is_enum_map_field(field: PdbFieldDefinition) -> bool:
	return field.field_type == TYPE_DICTIONARY and _is_pdb_enum_name(field.hint_string)

func _is_pdb_definition(type_name: String) -> bool:
	if not database_ref or type_name.is_empty():
		return false
	var pattern = database_ref.get_pattern(type_name)
	return pattern is PdbModelDefinition

func _get_instances_of_definition(def_id: String) -> Array[PdbModelInstance]:
	if not database_ref:
		return []
	return database_ref.get_instances_including_subtypes(StringName(def_id))

func _create_reference_picker(field: PdbFieldDefinition, value: Variant, callback: Callable) -> Control:
	if value is Dictionary:
		return _create_resource_editor(field, value, callback)

	var picker := OptionButton.new()
	picker.size_flags_horizontal = SIZE_EXPAND_FILL
	picker.add_item("(none)")
	picker.set_item_metadata(0, &"")

	var current := str(value) if value != null else ""
	var selected := 0
	var idx := 1
	for inst in _get_instances_of_definition(field.get_resource_type()):
		picker.add_item(str(inst.id))
		picker.set_item_metadata(idx, inst.id)
		if str(inst.id) == current:
			selected = idx
		idx += 1

	if current != "" and selected == 0:
		picker.add_item("(unresolved) %s" % current)
		picker.set_item_metadata(idx, StringName(current))
		selected = idx

	picker.select(selected)
	picker.item_selected.connect(func(i): callback.call(picker.get_item_metadata(i)))
	return picker

func _create_enum_editor(field: PdbFieldDefinition, value: Variant, callback: Callable) -> Control:
	var opt = OptionButton.new()

	var pdb_enum: PdbEnum = null
	if database_ref:
		var enum_pattern = database_ref.get_pattern(field.hint_string)
		if enum_pattern is PdbEnum:
			pdb_enum = enum_pattern

	if pdb_enum:
		var sorted_entries: Array = []
		for key in pdb_enum.values:
			sorted_entries.append({"name": key, "value": pdb_enum.values[key]})
		sorted_entries.sort_custom(func(a, b): return a.value < b.value)

		for entry in sorted_entries:
			opt.add_item(str(entry.name), entry.value)

		var current_idx = 0
		for i in range(opt.item_count):
			if opt.get_item_id(i) == int(value):
				current_idx = i
				break
		opt.selected = current_idx
	else:
		var enum_values = field.get_enum_values()
		for i in enum_values.size():
			opt.add_item(enum_values[i], i)
		opt.selected = int(value) if value != null else 0

	opt.item_selected.connect(func(idx):
		callback.call(opt.get_item_id(idx))
	)

	return opt

func _create_enum_map_editor(field: PdbFieldDefinition, value: Variant, callback: Callable) -> Control:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL

	var pdb_enum: PdbEnum = null
	if database_ref:
		var enum_pattern = database_ref.get_pattern(field.hint_string)
		if enum_pattern is PdbEnum:
			pdb_enum = enum_pattern

	if pdb_enum == null:
		var warn := Label.new()
		warn.text = "Unknown key enum: %s" % field.hint_string
		warn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.4))
		vbox.add_child(warn)
		return vbox

	var working: Dictionary = {}
	if value is Dictionary:
		working = (value as Dictionary).duplicate()

	var sorted_keys: Array = []
	for key in pdb_enum.values:
		sorted_keys.append({"name": str(key), "value": pdb_enum.values[key]})
	sorted_keys.sort_custom(func(a, b): return a.value < b.value)

	for entry in sorted_keys:
		var key_name: String = entry.name
		var row := HBoxContainer.new()
		row.size_flags_horizontal = SIZE_EXPAND_FILL

		var lbl := Label.new()
		lbl.text = key_name
		lbl.custom_minimum_size = Vector2(120, 0)
		row.add_child(lbl)

		var sb := SpinBox.new()
		sb.step = 0.01
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.size_flags_horizontal = SIZE_EXPAND_FILL
		sb.value = float(working.get(key_name, 0.0))
		sb.value_changed.connect(func(v: float):
			working[key_name] = v
			callback.call(working.duplicate())
		)
		row.add_child(sb)
		vbox.add_child(row)

	return vbox

func _create_resource_editor(field: PdbFieldDefinition, value: Variant, callback: Callable) -> Control:
	if not Engine.is_editor_hint():
		var label = Label.new()
		label.text = str(value) if value else "(null)"
		return label

	if value is Dictionary and value.has("__embedded__"):
		var emb := Label.new()
		var tname: String = field.hint_string if field.hint_string != "" else "Resource"
		emb.text = "(embedded %s)" % tname
		emb.tooltip_text = "Inline sub-resource stored in this record; preserved on export."
		emb.add_theme_color_override("font_color", Color(0.6, 0.78, 0.62))
		return emb

	var path: String = ""
	if value is String or value is StringName:
		path = str(value)

	if path != "" and not _resolves_in_project(path):
		var box2 := HBoxContainer.new()
		box2.size_flags_horizontal = SIZE_EXPAND_FILL
		var badge := Label.new()
		badge.text = "[external]"
		badge.tooltip_text = "Referenced resource is not in this project. The path is preserved verbatim and re-emitted natively on export."
		badge.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
		box2.add_child(badge)
		var ext_edit := LineEdit.new()
		ext_edit.text = path
		ext_edit.size_flags_horizontal = SIZE_EXPAND_FILL
		ext_edit.tooltip_text = "External resource path"
		ext_edit.text_changed.connect(func(t: String):
			callback.call(t)
		)
		box2.add_child(ext_edit)
		return box2

	var box := HBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	var current: Resource = null
	if path != "":
		current = load(path)

	if Engine.is_editor_hint():
		var picker = ClassDB.instantiate("EditorResourcePicker")
		picker.base_type = field.hint_string if field.hint_string != "" else "Resource"
		picker.edited_resource = current
		picker.size_flags_horizontal = SIZE_EXPAND_FILL
		box.add_child(picker)

		var preview_btn := Button.new()
		preview_btn.text = "Preview"
		preview_btn.tooltip_text = "Open the image at full size in a window"
		preview_btn.disabled = not (current is Texture2D)
		preview_btn.pressed.connect(func():
			if picker.edited_resource is Texture2D:
				_open_texture_preview(picker.edited_resource as Texture2D)
		)
		box.add_child(preview_btn)

		picker.resource_changed.connect(func(res: Resource):
			callback.call(res.resource_path if res else "")
			preview_btn.disabled = not (res is Texture2D)
		)
		return box

	var le := LineEdit.new()
	le.text = path
	le.placeholder_text = "res:// path to a resource"
	le.size_flags_horizontal = SIZE_EXPAND_FILL
	le.text_changed.connect(func(t: String): callback.call(t))
	box.add_child(le)

	var preview_btn2 := Button.new()
	preview_btn2.text = "Preview"
	preview_btn2.disabled = not (current is Texture2D)
	preview_btn2.pressed.connect(func():
		var r = load(le.text) if le.text != "" else null
		if r is Texture2D:
			_open_texture_preview(r as Texture2D)
	)
	box.add_child(preview_btn2)
	return box

func _resolves_in_project(path: String) -> bool:
	if not path.begins_with("res://"):
		return false
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

func _load_resource_ref(value: Variant) -> Resource:
	if value is Resource:
		return value
	if (value is String or value is StringName) and str(value) != "" and ResourceLoader.exists(str(value)):
		return load(str(value))
	return null

func _open_texture_preview(tex: Texture2D) -> void:
	if tex == null:
		return
	if _preview_dialog == null:
		_preview_dialog = AcceptDialog.new()
		_preview_dialog.title = "Preview"
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 10)
		margin.add_theme_constant_override("margin_right", 10)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_bottom", 10)
		_preview_rect = TextureRect.new()
		_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		margin.add_child(_preview_rect)
		_preview_dialog.add_child(margin)
		add_child(_preview_dialog)

	_preview_rect.texture = tex
	_preview_dialog.title = "Preview  (%d \u00d7 %d)" % [tex.get_width(), tex.get_height()]

	var img_size := Vector2(maxf(tex.get_width(), 1.0), maxf(tex.get_height(), 1.0))
	var avail := get_viewport().get_visible_rect().size * 0.85
	var show_size := img_size
	if img_size.x > avail.x or img_size.y > avail.y:
		var s := minf(avail.x / img_size.x, avail.y / img_size.y)
		show_size = img_size * s
	_preview_rect.custom_minimum_size = show_size
	_preview_dialog.size = Vector2i(show_size) + Vector2i(40, 70)
	_preview_dialog.popup_centered()

func _create_array_editor(field: PdbFieldDefinition, value: Variant, callback: Callable) -> Control:
	var container = VBoxContainer.new()

	var arr: Array = value if value is Array else []

	var toolbar = HBoxContainer.new()
	var count_label = Label.new()
	count_label.text = "%d items" % arr.size()
	count_label.size_flags_horizontal = SIZE_EXPAND_FILL

	var add_btn = Button.new()
	add_btn.text = "+ Add"

	toolbar.add_child(count_label)
	toolbar.add_child(add_btn)
	container.add_child(toolbar)

	var list_container = VBoxContainer.new()
	container.add_child(list_container)

	var element_type = field.get_array_element_type()
	var element_code = _element_type_code(element_type)

	var refresh_box := {}
	refresh_box["fn"] = func():
		for child in list_container.get_children():
			child.queue_free()
		count_label.text = "%d items" % arr.size()

		for i in range(arr.size()):
			var item_row = HBoxContainer.new()

			var idx_label = Label.new()
			idx_label.text = "[%d]" % i
			idx_label.custom_minimum_size.x = 30

			var item_editor: Control
			var item_idx = i
			if element_type != "" and ClassDB.class_exists(element_type):
				if Engine.is_editor_hint():
					var picker = ClassDB.instantiate("EditorResourcePicker")
					picker.base_type = element_type
					picker.edited_resource = _load_resource_ref(arr[item_idx])
					picker.resource_changed.connect(func(res):
						arr[item_idx] = res.resource_path if res else ""
						callback.call(arr)
					)
					item_editor = picker
				else:
					item_editor = Label.new()
					item_editor.text = str(arr[item_idx])
			elif element_type != "" and _is_pdb_definition(element_type):
				var ref_pick = OptionButton.new()
				ref_pick.add_item("(None)", 0)
				var valid_ids: Array = []
				for inst in _get_instances_of_definition(element_type):
					ref_pick.add_item(str(inst.id))
					valid_ids.append(inst.id)
				var cur_ref := StringName(str(arr[item_idx])) if arr[item_idx] != null else &""
				var found := valid_ids.find(cur_ref)
				ref_pick.select(found + 1 if found >= 0 else 0)
				ref_pick.item_selected.connect(func(choice):
					arr[item_idx] = valid_ids[choice - 1] if choice > 0 else &""
					callback.call(arr)
				)
				item_editor = ref_pick
			elif element_code != TYPE_NIL:
				item_editor = _create_typed_editor(element_code, PROPERTY_HINT_NONE, "", arr[item_idx], func(v):
					arr[item_idx] = v
					callback.call(arr)
				)
			else:
				item_editor = LineEdit.new()
				item_editor.text = str(arr[item_idx]) if arr[item_idx] != null else ""
				item_editor.text_changed.connect(func(t):
					arr[item_idx] = t
					callback.call(arr)
				)
			item_editor.size_flags_horizontal = SIZE_EXPAND_FILL

			var del_btn = Button.new()
			del_btn.text = "X"
			del_btn.pressed.connect(func():
				if item_idx >= 0 and item_idx < arr.size():
					arr.remove_at(item_idx)
					callback.call(arr)
					refresh_box["fn"].call()
			)

			item_row.add_child(idx_label)
			item_row.add_child(item_editor)
			item_row.add_child(del_btn)
			list_container.add_child(item_row)

	add_btn.pressed.connect(func():
		if element_type != "" and ClassDB.class_exists(element_type):
			arr.append(null)
		elif element_type != "" and _is_pdb_definition(element_type):
			arr.append(&"")
		elif element_code != TYPE_NIL:
			arr.append(_element_default(element_code))
		else:
			arr.append("")
		callback.call(arr)
		refresh_box["fn"].call()
	)

	refresh_box["fn"].call()

	return container

func _element_type_code(element_type: String) -> int:
	match element_type:
		"int": return TYPE_INT
		"float": return TYPE_FLOAT
		"bool": return TYPE_BOOL
		"String": return TYPE_STRING
		"StringName": return TYPE_STRING_NAME
		"Vector2": return TYPE_VECTOR2
		"Vector2i": return TYPE_VECTOR2I
		"Vector3": return TYPE_VECTOR3
		"Color": return TYPE_COLOR
		_: return TYPE_NIL

func _element_default(type_code: int) -> Variant:
	match type_code:
		TYPE_INT: return 0
		TYPE_FLOAT: return 0.0
		TYPE_BOOL: return false
		TYPE_STRING: return ""
		TYPE_STRING_NAME: return &""
		TYPE_VECTOR2: return Vector2.ZERO
		TYPE_VECTOR2I: return Vector2i.ZERO
		TYPE_VECTOR3: return Vector3.ZERO
		TYPE_COLOR: return Color.WHITE
		_: return null

func _create_typed_editor(type: int, hint: int, hint_string: String, value: Variant, callback: Callable) -> Control:
	match type:
		TYPE_BOOL:
			var cb = CheckBox.new()
			cb.button_pressed = value if value != null else false
			cb.toggled.connect(callback)
			return cb

		TYPE_INT:
			var sb = SpinBox.new()
			sb.step = 1
			sb.value = value if value != null else 0
			sb.allow_greater = true
			sb.allow_lesser = true
			sb.value_changed.connect(func(v): callback.call(int(v)))
			return sb

		TYPE_FLOAT:
			var sb = SpinBox.new()
			sb.step = 0.01
			sb.value = value if value != null else 0.0
			sb.allow_greater = true
			sb.allow_lesser = true
			sb.value_changed.connect(callback)
			return sb

		TYPE_STRING, TYPE_STRING_NAME:
			var le = LineEdit.new()
			le.text = str(value) if value != null else ""
			le.text_changed.connect(func(t):
				if type == TYPE_STRING_NAME:
					callback.call(StringName(t))
				else:
					callback.call(t)
			)
			return le

		TYPE_VECTOR2:
			var box = HBoxContainer.new()
			var vec = value if value is Vector2 else Vector2.ZERO
			var x = SpinBox.new()
			x.prefix = "x"
			x.value = vec.x
			x.step = 0.01
			x.allow_greater = true
			x.allow_lesser = true
			var y = SpinBox.new()
			y.prefix = "y"
			y.value = vec.y
			y.step = 0.01
			y.allow_greater = true
			y.allow_lesser = true
			var update_vec = func(_v): callback.call(Vector2(x.value, y.value))
			x.value_changed.connect(update_vec)
			y.value_changed.connect(update_vec)
			box.add_child(x)
			box.add_child(y)
			return box

		TYPE_VECTOR2I:
			var box = HBoxContainer.new()
			var vec = value if value is Vector2i else Vector2i.ZERO
			var x = SpinBox.new()
			x.prefix = "x"
			x.value = vec.x
			x.step = 1
			x.allow_greater = true
			x.allow_lesser = true
			var y = SpinBox.new()
			y.prefix = "y"
			y.value = vec.y
			y.step = 1
			y.allow_greater = true
			y.allow_lesser = true
			var update_vec = func(_v): callback.call(Vector2i(int(x.value), int(y.value)))
			x.value_changed.connect(update_vec)
			y.value_changed.connect(update_vec)
			box.add_child(x)
			box.add_child(y)
			return box

		TYPE_VECTOR3:
			var box = HBoxContainer.new()
			var vec = value if value is Vector3 else Vector3.ZERO
			var x = SpinBox.new()
			x.prefix = "x"
			x.value = vec.x
			x.step = 0.01
			x.allow_greater = true
			x.allow_lesser = true
			var y = SpinBox.new()
			y.prefix = "y"
			y.value = vec.y
			y.step = 0.01
			y.allow_greater = true
			y.allow_lesser = true
			var z = SpinBox.new()
			z.prefix = "z"
			z.value = vec.z
			z.step = 0.01
			z.allow_greater = true
			z.allow_lesser = true
			var update_vec = func(_v): callback.call(Vector3(x.value, y.value, z.value))
			x.value_changed.connect(update_vec)
			y.value_changed.connect(update_vec)
			z.value_changed.connect(update_vec)
			box.add_child(x)
			box.add_child(y)
			box.add_child(z)
			return box

		TYPE_VECTOR3I:
			var box = HBoxContainer.new()
			var vec = value if value is Vector3i else Vector3i.ZERO
			var x = SpinBox.new()
			x.prefix = "x"
			x.value = vec.x
			x.step = 1
			x.allow_greater = true
			x.allow_lesser = true
			var y = SpinBox.new()
			y.prefix = "y"
			y.value = vec.y
			y.step = 1
			y.allow_greater = true
			y.allow_lesser = true
			var z = SpinBox.new()
			z.prefix = "z"
			z.value = vec.z
			z.step = 1
			z.allow_greater = true
			z.allow_lesser = true
			var update_vec = func(_v): callback.call(Vector3i(int(x.value), int(y.value), int(z.value)))
			x.value_changed.connect(update_vec)
			y.value_changed.connect(update_vec)
			z.value_changed.connect(update_vec)
			box.add_child(x)
			box.add_child(y)
			box.add_child(z)
			return box

		TYPE_RECT2:
			var box = GridContainer.new()
			box.columns = 2
			var rect = value if value is Rect2 else Rect2()
			var x = SpinBox.new()
			x.prefix = "x"
			x.value = rect.position.x
			x.step = 0.01
			x.allow_greater = true
			x.allow_lesser = true
			var y = SpinBox.new()
			y.prefix = "y"
			y.value = rect.position.y
			y.step = 0.01
			y.allow_greater = true
			y.allow_lesser = true
			var w = SpinBox.new()
			w.prefix = "w"
			w.value = rect.size.x
			w.step = 0.01
			w.allow_greater = true
			w.allow_lesser = true
			var h = SpinBox.new()
			h.prefix = "h"
			h.value = rect.size.y
			h.step = 0.01
			h.allow_greater = true
			h.allow_lesser = true
			var update_rect = func(_v): callback.call(Rect2(x.value, y.value, w.value, h.value))
			for s in [x, y, w, h]:
				s.value_changed.connect(update_rect)
				box.add_child(s)
			return box

		TYPE_COLOR:
			var cp = ColorPickerButton.new()
			cp.color = value if value is Color else Color.WHITE
			cp.color_changed.connect(callback)
			return cp

		TYPE_NODE_PATH:
			var le = LineEdit.new()
			le.text = str(value) if value != null else ""
			le.text_changed.connect(func(t): callback.call(NodePath(t)))
			return le

		TYPE_DICTIONARY:
			return _create_dictionary_editor(value, callback)

		TYPE_PACKED_STRING_ARRAY:
			var container = VBoxContainer.new()
			var arr: PackedStringArray = value if value is PackedStringArray else PackedStringArray()

			var toolbar = HBoxContainer.new()
			var count_label = Label.new()
			count_label.text = "%d items" % arr.size()
			count_label.size_flags_horizontal = SIZE_EXPAND_FILL
			var add_btn = Button.new()
			add_btn.text = "+ Add"
			toolbar.add_child(count_label)
			toolbar.add_child(add_btn)
			container.add_child(toolbar)

			var list_container = VBoxContainer.new()
			container.add_child(list_container)

			var refresh_box := {}
			refresh_box["fn"] = func():
				for child in list_container.get_children():
					child.queue_free()
				count_label.text = "%d items" % arr.size()
				for i in range(arr.size()):
					var item_row = HBoxContainer.new()
					var item_idx = i
					var le = LineEdit.new()
					le.text = arr[item_idx]
					le.size_flags_horizontal = SIZE_EXPAND_FILL
					le.text_changed.connect(func(t):
						arr[item_idx] = t
						callback.call(arr)
					)
					var del_btn = Button.new()
					del_btn.text = "X"
					del_btn.pressed.connect(func():
						if item_idx >= 0 and item_idx < arr.size():
							arr.remove_at(item_idx)
							callback.call(arr)
							refresh_box["fn"].call()
					)
					item_row.add_child(le)
					item_row.add_child(del_btn)
					list_container.add_child(item_row)

			add_btn.pressed.connect(func():
				arr.append("")
				callback.call(arr)
				refresh_box["fn"].call()
			)

			refresh_box["fn"].call()
			return container

	return _create_variant_text_editor(type, value, callback)

func _create_variant_text_editor(type: int, value: Variant, callback: Callable) -> Control:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var le = LineEdit.new()
	le.text = var_to_str(value) if value != null else ""
	le.size_flags_horizontal = SIZE_EXPAND_FILL
	le.tooltip_text = "Native value syntax, e.g. %s" % type_string(type)

	var hint = Label.new()
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	hint.text = type_string(type)

	var default_color := le.get_theme_color("font_color")
	le.text_changed.connect(func(t):
		var parsed = str_to_var(t)
		var ok := parsed != null and (
			typeof(parsed) == type
			or (type == TYPE_INT and typeof(parsed) == TYPE_FLOAT)
			or (type == TYPE_FLOAT and typeof(parsed) == TYPE_INT)
		)
		if t.strip_edges().is_empty():
			ok = false
		if ok:
			le.add_theme_color_override("font_color", default_color)
			if type == TYPE_INT:
				callback.call(int(parsed))
			elif type == TYPE_FLOAT:
				callback.call(float(parsed))
			else:
				callback.call(parsed)
		else:
			le.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	)

	box.add_child(le)
	box.add_child(hint)
	return box

func _create_dictionary_editor(value: Variant, callback: Callable) -> Control:
	var dict: Dictionary = (value as Dictionary).duplicate(true) if value is Dictionary else {}

	var container = VBoxContainer.new()
	container.add_theme_constant_override("separation", 4)

	var toolbar = HBoxContainer.new()
	var count_label = Label.new()
	count_label.size_flags_horizontal = SIZE_EXPAND_FILL
	var key_input = LineEdit.new()
	key_input.placeholder_text = "key"
	key_input.custom_minimum_size.x = 120
	var type_btn = OptionButton.new()
	var type_choices := [
		["String", TYPE_STRING], ["Int", TYPE_INT], ["Float", TYPE_FLOAT],
		["Bool", TYPE_BOOL], ["Vector2", TYPE_VECTOR2], ["Color", TYPE_COLOR],
	]
	for i in type_choices.size():
		type_btn.add_item(type_choices[i][0], i)
	var add_btn = Button.new()
	add_btn.text = "+ Add"
	toolbar.add_child(count_label)
	toolbar.add_child(key_input)
	toolbar.add_child(type_btn)
	toolbar.add_child(add_btn)
	container.add_child(toolbar)

	var rows = VBoxContainer.new()
	container.add_child(rows)

	var refresh_box := {}
	refresh_box["fn"] = func():
		for c in rows.get_children():
			c.queue_free()
		count_label.text = "%d entries" % dict.size()
		var keys = dict.keys()
		keys.sort()
		for k in keys:
			var row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var k_lbl = Label.new()
			k_lbl.text = str(k)
			k_lbl.custom_minimum_size.x = 120
			var current_key = k
			var v_editor = _create_typed_editor(typeof(dict[k]), PROPERTY_HINT_NONE, "", dict[k], func(v):
				dict[current_key] = v
				callback.call(dict)
			)
			v_editor.size_flags_horizontal = SIZE_EXPAND_FILL
			var del = Button.new()
			del.text = "X"
			del.pressed.connect(func():
				dict.erase(current_key)
				callback.call(dict)
				refresh_box["fn"].call()
			)
			row.add_child(k_lbl)
			row.add_child(v_editor)
			row.add_child(del)
			rows.add_child(row)

	add_btn.pressed.connect(func():
		var key = key_input.text.strip_edges()
		if key.is_empty() or dict.has(key):
			return
		dict[key] = _element_default(type_choices[type_btn.selected][1])
		key_input.text = ""
		callback.call(dict)
		refresh_box["fn"].call()
	)

	refresh_box["fn"].call()
	return container
