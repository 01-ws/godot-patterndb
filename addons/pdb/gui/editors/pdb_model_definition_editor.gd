@tool
extends PdbPatternEditorBase

const SUPPORTED_TYPES: Array[Dictionary] = [
	{"name": "String", "type": TYPE_STRING, "hint": PROPERTY_HINT_NONE},
	{"name": "StringName", "type": TYPE_STRING_NAME, "hint": PROPERTY_HINT_NONE},
	{"name": "Int", "type": TYPE_INT, "hint": PROPERTY_HINT_NONE},
	{"name": "Float", "type": TYPE_FLOAT, "hint": PROPERTY_HINT_NONE},
	{"name": "Bool", "type": TYPE_BOOL, "hint": PROPERTY_HINT_NONE},
	{"name": "Vector2", "type": TYPE_VECTOR2, "hint": PROPERTY_HINT_NONE},
	{"name": "Vector2i", "type": TYPE_VECTOR2I, "hint": PROPERTY_HINT_NONE},
	{"name": "Vector3", "type": TYPE_VECTOR3, "hint": PROPERTY_HINT_NONE},
	{"name": "Vector3i", "type": TYPE_VECTOR3I, "hint": PROPERTY_HINT_NONE},
	{"name": "Vector4", "type": TYPE_VECTOR4, "hint": PROPERTY_HINT_NONE},
	{"name": "Rect2", "type": TYPE_RECT2, "hint": PROPERTY_HINT_NONE},
	{"name": "Color", "type": TYPE_COLOR, "hint": PROPERTY_HINT_NONE},
	{"name": "Transform2D", "type": TYPE_TRANSFORM2D, "hint": PROPERTY_HINT_NONE},
	{"name": "Transform3D", "type": TYPE_TRANSFORM3D, "hint": PROPERTY_HINT_NONE},
	{"name": "Basis", "type": TYPE_BASIS, "hint": PROPERTY_HINT_NONE},
	{"name": "Quaternion", "type": TYPE_QUATERNION, "hint": PROPERTY_HINT_NONE},
	{"name": "AABB", "type": TYPE_AABB, "hint": PROPERTY_HINT_NONE},
	{"name": "Plane", "type": TYPE_PLANE, "hint": PROPERTY_HINT_NONE},
	{"name": "NodePath", "type": TYPE_NODE_PATH, "hint": PROPERTY_HINT_NONE},
	{"name": "Dictionary", "type": TYPE_DICTIONARY, "hint": PROPERTY_HINT_NONE},
	{"name": "Array", "type": TYPE_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "PackedStringArray", "type": TYPE_PACKED_STRING_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "PackedInt32Array", "type": TYPE_PACKED_INT32_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "PackedInt64Array", "type": TYPE_PACKED_INT64_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "PackedFloat32Array", "type": TYPE_PACKED_FLOAT32_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "PackedFloat64Array", "type": TYPE_PACKED_FLOAT64_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "PackedVector2Array", "type": TYPE_PACKED_VECTOR2_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "PackedVector3Array", "type": TYPE_PACKED_VECTOR3_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "PackedColorArray", "type": TYPE_PACKED_COLOR_ARRAY, "hint": PROPERTY_HINT_NONE},
	{"name": "Resource", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE},
	{"name": "Texture2D", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "Texture2D"},
	{"name": "PackedScene", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "PackedScene"},
	{"name": "Enum (PDB)", "type": TYPE_INT, "hint": PROPERTY_HINT_ENUM, "is_pdb_enum": true},
	{"name": "Enum Map (PDB)", "type": TYPE_DICTIONARY, "hint": PROPERTY_HINT_NONE, "is_enum_map": true},
	{"name": "Typed Array", "type": TYPE_ARRAY, "hint": PROPERTY_HINT_ARRAY_TYPE, "needs_element_type": true},
]

var field_list_container: VBoxContainer
var field_count_label: Label
var add_field_dialog: ConfirmationDialog

var field_name_input: LineEdit
var field_type_option: OptionButton
var field_hint_string_input: LineEdit
var field_hint_string_label: Label
var field_group_input: LineEdit
var field_description_input: TextEdit
var field_required_check: CheckBox
var field_enum_picker: OptionButton
var field_element_type_input: LineEdit
var _icon_picker: PdbIconPicker = null

var enum_row: HBoxContainer
var hint_row: HBoxContainer
var element_row: HBoxContainer

var editing_field_index: int = -1
var database_ref: PatternDatabaseFile
var _pending_flash_field: StringName = &""
var _drop_gap: ColorRect = null
var _drop_gap_at: int = -1

func _log(msg: String) -> void:
	PdbLog.info("ModelDefEditor", msg)

func set_database(db: PatternDatabaseFile) -> void:
	database_ref = db
	_log("Database reference set")

func _setup_ui() -> void:
	var definition = pattern as PdbModelDefinition
	if not definition:
		_log("ERROR: Pattern is not PdbModelDefinition")
		return

	_log("Setting up UI for: %s" % definition.id)

	var meta_section = VBoxContainer.new()
	meta_section.add_theme_constant_override("separation", 8)

	var extends_row = HBoxContainer.new()
	extends_row.add_theme_constant_override("separation", 10)
	var extends_label = Label.new()
	extends_label.text = "Extends:"
	extends_label.custom_minimum_size.x = 100
	var extends_input = LineEdit.new()
	extends_input.text = definition.extends_type
	extends_input.size_flags_horizontal = SIZE_EXPAND_FILL
	extends_input.text_changed.connect(func(t):
		_log("Extends changed: %s" % t)
		definition.extends_type = t
		definition.emit_changed()
		value_changed.emit()
	)
	extends_row.add_child(extends_label)
	extends_row.add_child(extends_input)
	meta_section.add_child(extends_row)

	var icon_row = HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 10)
	var icon_label = Label.new()
	icon_label.text = "List Icon:"
	icon_label.custom_minimum_size.x = 100
	var icon_btn = Button.new()
	icon_btn.size_flags_horizontal = SIZE_EXPAND_FILL
	icon_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	icon_btn.expand_icon = true
	icon_btn.tooltip_text = "Browse the built-in Godot icons"
	_update_icon_button(icon_btn, definition)
	icon_btn.pressed.connect(func():
		_ensure_icon_picker(definition, icon_btn).popup_for_selection()
	)
	var clear_icon_btn = Button.new()
	clear_icon_btn.text = "Clear"
	clear_icon_btn.focus_mode = Control.FOCUS_NONE
	clear_icon_btn.pressed.connect(func():
		definition.icon_name = ""
		definition.emit_changed()
		value_changed.emit()
		_update_icon_button(icon_btn, definition)
	)
	icon_row.add_child(icon_label)
	icon_row.add_child(icon_btn)
	icon_row.add_child(clear_icon_btn)
	meta_section.add_child(icon_row)

	add_child(meta_section)
	add_child(HSeparator.new())

	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)

	field_count_label = Label.new()
	field_count_label.text = "Fields (%d)" % definition.fields.size()
	field_count_label.add_theme_font_size_override("font_size", 14)
	field_count_label.size_flags_horizontal = SIZE_EXPAND_FILL

	var add_btn = Button.new()
	add_btn.text = "+ Add Field"
	add_btn.pressed.connect(_show_add_field_dialog)

	toolbar.add_child(field_count_label)
	toolbar.add_child(add_btn)
	add_child(toolbar)

	add_child(HSeparator.new())

	field_list_container = VBoxContainer.new()
	field_list_container.size_flags_horizontal = SIZE_EXPAND_FILL
	field_list_container.add_theme_constant_override("separation", 4)
	add_child(field_list_container)

	_setup_add_field_dialog()
	_rebuild_field_list()

	_log("UI setup complete, %d fields" % definition.fields.size())

func _setup_add_field_dialog() -> void:
	add_field_dialog = ConfirmationDialog.new()
	add_field_dialog.title = "Add Field"
	add_field_dialog.size = Vector2i(450, 420)

	var dialog_content = VBoxContainer.new()
	dialog_content.custom_minimum_size = Vector2(400, 350)

	var name_row = HBoxContainer.new()
	var name_label = Label.new()
	name_label.text = "Field Name:"
	name_label.custom_minimum_size.x = 100
	field_name_input = LineEdit.new()
	field_name_input.placeholder_text = "field_name"
	field_name_input.size_flags_horizontal = SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	name_row.add_child(field_name_input)
	dialog_content.add_child(name_row)

	var type_row = HBoxContainer.new()
	var type_label = Label.new()
	type_label.text = "Type:"
	type_label.custom_minimum_size.x = 100
	field_type_option = OptionButton.new()
	field_type_option.size_flags_horizontal = SIZE_EXPAND_FILL
	for i in SUPPORTED_TYPES.size():
		field_type_option.add_item(SUPPORTED_TYPES[i].name, i)
	field_type_option.item_selected.connect(_on_type_selected)
	type_row.add_child(type_label)
	type_row.add_child(field_type_option)
	dialog_content.add_child(type_row)

	enum_row = HBoxContainer.new()
	enum_row.visible = false
	var enum_label = Label.new()
	enum_label.text = "Enum:"
	enum_label.custom_minimum_size.x = 100
	field_enum_picker = OptionButton.new()
	field_enum_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	enum_row.add_child(enum_label)
	enum_row.add_child(field_enum_picker)
	dialog_content.add_child(enum_row)

	element_row = HBoxContainer.new()
	element_row.visible = false
	var element_label = Label.new()
	element_label.text = "Element Type:"
	element_label.custom_minimum_size.x = 100
	field_element_type_input = LineEdit.new()
	field_element_type_input.placeholder_text = "Resource"
	field_element_type_input.size_flags_horizontal = SIZE_EXPAND_FILL
	element_row.add_child(element_label)
	element_row.add_child(field_element_type_input)
	dialog_content.add_child(element_row)

	hint_row = HBoxContainer.new()
	hint_row.visible = false
	field_hint_string_label = Label.new()
	field_hint_string_label.text = "Resource Type:"
	field_hint_string_label.custom_minimum_size.x = 100
	field_hint_string_input = LineEdit.new()
	field_hint_string_input.placeholder_text = "Resource"
	field_hint_string_input.size_flags_horizontal = SIZE_EXPAND_FILL
	hint_row.add_child(field_hint_string_label)
	hint_row.add_child(field_hint_string_input)
	dialog_content.add_child(hint_row)

	var group_row = HBoxContainer.new()
	var group_label = Label.new()
	group_label.text = "Export Group:"
	group_label.custom_minimum_size.x = 100
	field_group_input = LineEdit.new()
	field_group_input.placeholder_text = "(optional)"
	field_group_input.size_flags_horizontal = SIZE_EXPAND_FILL
	group_row.add_child(group_label)
	group_row.add_child(field_group_input)
	dialog_content.add_child(group_row)

	var desc_label = Label.new()
	desc_label.text = "Description:"
	dialog_content.add_child(desc_label)

	field_description_input = TextEdit.new()
	field_description_input.custom_minimum_size.y = 60
	field_description_input.size_flags_horizontal = SIZE_EXPAND_FILL
	dialog_content.add_child(field_description_input)

	field_required_check = CheckBox.new()
	field_required_check.text = "Required"
	dialog_content.add_child(field_required_check)

	add_field_dialog.add_child(dialog_content)
	add_field_dialog.confirmed.connect(_on_add_field_confirmed)
	add_child(add_field_dialog)

func _show_add_field_dialog() -> void:
	editing_field_index = -1
	add_field_dialog.title = "Add Field"

	field_name_input.text = ""
	field_type_option.selected = 0
	field_hint_string_input.text = ""
	field_group_input.text = ""
	field_description_input.text = ""
	field_required_check.button_pressed = false
	field_element_type_input.text = ""

	_populate_enum_picker()
	_on_type_selected(0)

	_log("Opening add field dialog")
	add_field_dialog.popup_centered()
	field_name_input.grab_focus()

func _show_edit_field_dialog(index: int) -> void:
	var definition = pattern as PdbModelDefinition
	if not definition or index < 0 or index >= definition.fields.size():
		return

	editing_field_index = index
	var field = definition.fields[index]

	add_field_dialog.title = "Edit Field"

	field_name_input.text = field.field_name
	field_group_input.text = field.export_group
	field_description_input.text = field.description
	field_required_check.button_pressed = field.required

	var type_index = _find_type_index(field)
	field_type_option.selected = type_index
	_on_type_selected(type_index)

	if field.is_enum_field():
		_populate_enum_picker()
		for i in field_enum_picker.item_count:
			if field_enum_picker.get_item_text(i) == field.hint_string:
				field_enum_picker.selected = i
				break
	elif _field_is_enum_map(field):
		_populate_enum_picker()
		for i in field_enum_picker.item_count:
			if field_enum_picker.get_item_text(i) == field.hint_string:
				field_enum_picker.selected = i
				break
	elif field.is_resource_field():
		field_hint_string_input.text = field.hint_string
	elif field.is_array_field() and field.hint == PROPERTY_HINT_ARRAY_TYPE:
		field_element_type_input.text = field.hint_string

	_log("Opening edit field dialog for: %s" % field.field_name)
	add_field_dialog.popup_centered()
	field_name_input.grab_focus()

func _find_type_index(field: PdbFieldDefinition) -> int:
	for i in SUPPORTED_TYPES.size():
		var t = SUPPORTED_TYPES[i]
		if t.type != field.field_type:
			continue
		if t.has("is_pdb_enum") and field.hint == PROPERTY_HINT_ENUM:
			return i
		if t.has("is_enum_map") and field.field_type == TYPE_DICTIONARY and field.hint_string != "":
			return i
		if t.has("needs_element_type") and field.hint == PROPERTY_HINT_ARRAY_TYPE:
			return i
		if t.has("hint_string") and field.hint_string == t.hint_string:
			return i
	for i in SUPPORTED_TYPES.size():
		var t = SUPPORTED_TYPES[i]
		if t.type != field.field_type:
			continue
		if t.has("is_pdb_enum") or t.has("needs_element_type") or t.has("hint_string") or t.has("is_enum_map"):
			continue
		if field.hint == t.hint:
			return i
	return 0

func _populate_enum_picker() -> void:
	field_enum_picker.clear()
	if database_ref:
		for key in database_ref.patterns:
			var p = database_ref.patterns[key]
			if p is PdbEnum:
				field_enum_picker.add_item(str(p.id))
		_log("Populated enum picker: %d enums" % field_enum_picker.item_count)

func _ensure_icon_picker(definition, icon_btn: Button) -> PdbIconPicker:
	if _icon_picker == null:
		_icon_picker = PdbIconPicker.new()
		add_child(_icon_picker)
		_icon_picker.icon_chosen.connect(func(chosen: String):
			definition.icon_name = chosen
			definition.emit_changed()
			value_changed.emit()
			_update_icon_button(icon_btn, definition)
		)
	return _icon_picker

func _update_icon_button(icon_btn: Button, definition) -> void:
	var nm: String = definition.icon_name
	if nm == "":
		icon_btn.icon = null
		icon_btn.text = "  (no icon) \u2014 choose\u2026"
		return
	icon_btn.text = "  " + nm
	if has_theme_icon(nm, "EditorIcons"):
		icon_btn.icon = get_theme_icon(nm, "EditorIcons")
	else:
		icon_btn.icon = null

func _on_type_selected(index: int) -> void:
	var type_info = SUPPORTED_TYPES[index]

	var wants_enum: bool = type_info.has("is_pdb_enum") or type_info.has("is_enum_map")
	enum_row.visible = wants_enum
	if wants_enum:
		_populate_enum_picker()
	hint_row.visible = type_info.hint == PROPERTY_HINT_RESOURCE_TYPE and not type_info.has("hint_string")
	element_row.visible = type_info.has("needs_element_type")

func _on_add_field_confirmed() -> void:
	var definition = pattern as PdbModelDefinition
	if not definition:
		return

	var field_name = field_name_input.text.strip_edges()
	if field_name.is_empty():
		_log("Cannot add field with empty name")
		return

	var type_index = field_type_option.selected
	var type_info = SUPPORTED_TYPES[type_index]

	var field: PdbFieldDefinition
	var old_field_name: StringName = &""
	var old_field_type: int = TYPE_NIL

	if editing_field_index >= 0:
		field = definition.fields[editing_field_index]
		old_field_name = field.field_name
		old_field_type = field.field_type
		_log("Editing field: %s" % field.field_name)
		if String(old_field_name) != field_name and definition.has_field(field_name):
			_log("Cannot rename field to '%s': name already exists" % field_name)
			return
	else:
		if definition.has_field(field_name):
			_log("Field already exists: %s" % field_name)
			return
		field = PdbFieldDefinition.new()
		_log("Creating new field: %s" % field_name)

	field.field_name = field_name
	field.field_type = type_info.type
	field.hint = type_info.hint
	field.export_group = field_group_input.text.strip_edges()
	field.description = field_description_input.text
	field.required = field_required_check.button_pressed

	if type_info.has("is_pdb_enum"):
		if field_enum_picker.selected >= 0:
			field.hint_string = field_enum_picker.get_item_text(field_enum_picker.selected)
		field.hint = PROPERTY_HINT_ENUM
	elif type_info.has("is_enum_map"):
		if field_enum_picker.selected >= 0:
			field.hint_string = field_enum_picker.get_item_text(field_enum_picker.selected)
		field.field_type = TYPE_DICTIONARY
		field.hint = PROPERTY_HINT_NONE
	elif type_info.has("needs_element_type"):
		field.hint_string = field_element_type_input.text.strip_edges()
		if field.hint_string.is_empty():
			field.hint_string = "Resource"
	elif type_info.has("hint_string"):
		field.hint_string = type_info.hint_string
	elif type_info.hint == PROPERTY_HINT_RESOURCE_TYPE:
		field.hint_string = field_hint_string_input.text.strip_edges()
		if field.hint_string.is_empty():
			field.hint_string = "Resource"
	else:
		field.hint_string = ""

	if editing_field_index < 0:
		definition.add_field(field)
		_log("Field added: %s (%s)" % [field.field_name, type_info.name])
	else:
		_migrate_instances_for_field_change(definition, old_field_name, field)
		definition.emit_changed()
		_log("Field updated: %s (%s)" % [field.field_name, type_info.name])

	_rebuild_field_list()
	value_changed.emit()

func _migrate_instances_for_field_change(definition: PdbModelDefinition, old_name: StringName, field: PdbFieldDefinition) -> void:
	if not database_ref:
		return
	var name_changed := old_name != &"" and old_name != field.field_name
	for inst in database_ref.get_instances_of_definition(definition.id):
		if not inst.data.has(old_name) and not inst.data.has(field.field_name):
			continue
		var value = inst.data.get(old_name, inst.data.get(field.field_name))
		if name_changed and inst.data.has(old_name):
			inst.data.erase(old_name)
		inst.data[field.field_name] = _coerce_to_field_type(value, field)
		inst.emit_changed()

func _coerce_to_field_type(value: Variant, field: PdbFieldDefinition) -> Variant:
	if value == null:
		return field.get_default()
	if typeof(value) == field.field_type:
		return value
	match field.field_type:
		TYPE_INT:
			return int(value) if (value is float or value is int or value is bool) else field.get_default()
		TYPE_FLOAT:
			return float(value) if (value is float or value is int or value is bool) else field.get_default()
		TYPE_BOOL:
			return bool(value) if (value is float or value is int or value is bool) else field.get_default()
		TYPE_STRING:
			return str(value)
		TYPE_STRING_NAME:
			return StringName(str(value))
		_:
			return field.get_default()

func _rebuild_field_list() -> void:
	_log("Rebuilding field list for: %s" % pattern.id)

	for child in field_list_container.get_children():
		child.queue_free()

	var definition = pattern as PdbModelDefinition
	if not definition:
		_log("ERROR: pattern is not PdbModelDefinition")
		return

	field_count_label.text = "Fields (%d)" % definition.fields.size()
	_log("Definition has %d fields" % definition.fields.size())

	var current_group: String = ""

	for i in range(definition.fields.size()):
		var field = definition.fields[i]
		_log("  Creating row for field: %s (type: %d)" % [field.field_name, field.field_type])

		if field.export_group != current_group:
			current_group = field.export_group
			if current_group != "":
				var group_header = _create_group_header(current_group)
				field_list_container.add_child(group_header)

		var row = _create_field_row(i, field)
		field_list_container.add_child(row)

	_log("Field list rebuilt: %d children in container" % field_list_container.get_child_count())

	if _pending_flash_field != &"":
		_flash_field_row(_pending_flash_field)
		_pending_flash_field = &""

func _flash_field_row(field_name: StringName) -> void:
	for child in field_list_container.get_children():
		if child.has_meta("pdb_field") and StringName(child.get_meta("pdb_field")) == field_name:
			var row := child as Control
			row.modulate = Color(0.55, 0.8, 1.2)
			var t := create_tween()
			t.tween_property(row, "modulate", Color(1, 1, 1, 1), 0.45) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			return

func _show_drop_gap(field_index: int) -> void:
	if _drop_gap_at == field_index and is_instance_valid(_drop_gap) and _drop_gap.get_parent() != null:
		return
	var first_time := false
	if not is_instance_valid(_drop_gap):
		_drop_gap = ColorRect.new()
		_drop_gap.color = Color(0.4, 0.65, 1.0, 0.5)
		_drop_gap.custom_minimum_size = Vector2(0, 0)
		_drop_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		first_time = true
	if _drop_gap.get_parent() == field_list_container:
		field_list_container.remove_child(_drop_gap)
	var pos := -1
	for child in field_list_container.get_children():
		if child.has_meta("pdb_index") and int(child.get_meta("pdb_index")) == field_index:
			pos = child.get_index()
			break
	if pos == -1:
		_drop_gap_at = -1
		return
	field_list_container.add_child(_drop_gap)
	field_list_container.move_child(_drop_gap, pos)
	_drop_gap_at = field_index
	if first_time:
		var t := _drop_gap.create_tween()
		t.tween_property(_drop_gap, "custom_minimum_size:y", 10.0, 0.12) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _clear_drop_gap() -> void:
	if is_instance_valid(_drop_gap):
		_drop_gap.queue_free()
	_drop_gap = null
	_drop_gap_at = -1

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_gap()

func _create_group_header(group_name: String) -> Control:
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)

	var sep1 = HSeparator.new()
	sep1.size_flags_horizontal = SIZE_EXPAND_FILL

	var label = Label.new()
	label.text = group_name
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	var sep2 = HSeparator.new()
	sep2.size_flags_horizontal = SIZE_EXPAND_FILL

	header.add_child(sep1)
	header.add_child(label)
	header.add_child(sep2)

	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.set_drag_forwarding(
		func(_at: Vector2) -> Variant: return null,
		_group_drag_can.bind(group_name),
		_group_drag_drop.bind(group_name)
	)

	return header

func _create_field_row(index: int, field: PdbFieldDefinition) -> Control:
	var panel = PanelContainer.new()
	panel.set_meta("pdb_field", field.field_name)
	panel.set_meta("pdb_index", index)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var handle = Label.new()
	handle.text = "\u2261"
	handle.tooltip_text = "Drag to reorder"
	handle.custom_minimum_size = Vector2(24, 0)
	handle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	handle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	handle.size_flags_vertical = SIZE_EXPAND_FILL
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
	handle.add_theme_font_size_override("font_size", 18)
	handle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	handle.set_drag_forwarding(
		_field_drag_get.bind(handle, index, str(field.field_name)),
		func(_at: Vector2, _data: Variant) -> bool: return false,
		func(_at: Vector2, _data: Variant) -> void: pass
	)
	row.add_child(handle)

	var move_container = VBoxContainer.new()
	move_container.alignment = BoxContainer.ALIGNMENT_CENTER

	var up_btn = Button.new()
	up_btn.text = "▲"
	up_btn.custom_minimum_size = Vector2(24, 20)
	up_btn.disabled = index == 0
	var idx_up = index
	up_btn.pressed.connect(func(): _move_field(idx_up, idx_up - 1))

	var down_btn = Button.new()
	down_btn.text = "▼"
	down_btn.custom_minimum_size = Vector2(24, 20)
	down_btn.disabled = index >= (pattern as PdbModelDefinition).fields.size() - 1
	var idx_down = index
	down_btn.pressed.connect(func(): _move_field(idx_down, idx_down + 1))

	move_container.add_child(up_btn)
	move_container.add_child(down_btn)
	row.add_child(move_container)

	var info_container = VBoxContainer.new()
	info_container.size_flags_horizontal = SIZE_EXPAND_FILL
	info_container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label = Label.new()
	name_label.text = str(field.field_name)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if field.required:
		name_label.text += " *"

	var type_label = Label.new()
	type_label.text = _get_field_type_display(field)
	type_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	type_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	type_label.add_theme_font_size_override("font_size", 12)

	info_container.add_child(name_label)
	info_container.add_child(type_label)
	row.add_child(info_container)

	var edit_btn = Button.new()
	edit_btn.text = "Edit"
	var idx_edit = index
	edit_btn.pressed.connect(func(): _show_edit_field_dialog(idx_edit))
	row.add_child(edit_btn)

	var del_btn = Button.new()
	del_btn.text = "X"
	del_btn.modulate = Color(1, 0.5, 0.5)
	var idx_del = index
	del_btn.pressed.connect(func(): _remove_field(idx_del))
	row.add_child(del_btn)

	panel.add_child(row)
	panel.set_drag_forwarding(
		func(_at: Vector2) -> Variant: return null,
		_field_drag_can.bind(index),
		_field_drag_drop.bind(index)
	)
	return panel

func _get_field_type_display(field: PdbFieldDefinition) -> String:
	if field.is_enum_field():
		return "Enum<%s>" % field.hint_string
	if _field_is_enum_map(field):
		return "EnumMap<%s>" % field.hint_string
	if field.is_resource_field():
		return field.hint_string if field.hint_string != "" else "Resource"
	if field.is_array_field() and field.hint == PROPERTY_HINT_ARRAY_TYPE:
		return "Array[%s]" % field.hint_string
	return type_string(field.field_type)

func _field_is_enum_map(field: PdbFieldDefinition) -> bool:
	return field.field_type == TYPE_DICTIONARY and field.hint_string != ""

func _move_field(from_index: int, to_index: int) -> void:
	var definition = pattern as PdbModelDefinition
	if definition:
		_log("Moving field %d -> %d" % [from_index, to_index])
		definition.move_field(from_index, to_index)
		_rebuild_field_list()
		value_changed.emit()

func _remove_field(index: int) -> void:
	var definition = pattern as PdbModelDefinition
	if definition:
		var field_name = definition.fields[index].field_name
		_log("Removing field: %s" % field_name)
		definition.remove_field(index)
		_rebuild_field_list()
		value_changed.emit()

func _field_drag_get(at_position: Vector2, handle: Control, index: int, field_name: String) -> Variant:
	if is_instance_valid(handle):
		handle.set_drag_preview(_make_drag_ghost(field_name))
	return {"pdb_field_drag": true, "from_index": index}

func _make_drag_ghost(field_name: String) -> Control:
	var ghost := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.34, 0.55, 0.9)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.5, 0.7, 1.0, 0.9)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	ghost.add_theme_stylebox_override("panel", sb)
	ghost.modulate = Color(1, 1, 1, 0.92)
	var lbl := Label.new()
	lbl.text = "\u2261  %s" % field_name
	lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	ghost.add_child(lbl)
	return ghost

func _field_drag_can(at_position: Vector2, data: Variant, target_index: int) -> bool:
	if not (data is Dictionary and data.get("pdb_field_drag", false)):
		return false
	_show_drop_gap(target_index)
	return true

func _field_drag_drop(at_position: Vector2, data: Variant, target_index: int) -> void:
	if not (data is Dictionary and data.get("pdb_field_drag", false)):
		return
	var from_index: int = int(data.get("from_index", -1))
	_reorder_field(from_index, target_index)

func _group_drag_can(at_position: Vector2, data: Variant, group_name: String) -> bool:
	if not (data is Dictionary and data.get("pdb_field_drag", false)):
		return false
	var definition := pattern as PdbModelDefinition
	if definition != null:
		for i in range(definition.fields.size()):
			if definition.fields[i].export_group == group_name:
				_show_drop_gap(i)
				break
	return true

func _group_drag_drop(at_position: Vector2, data: Variant, group_name: String) -> void:
	if not (data is Dictionary and data.get("pdb_field_drag", false)):
		return
	var from_index: int = int(data.get("from_index", -1))
	_reorder_field_to_group(from_index, group_name)

func _reorder_field(from_index: int, target_index: int) -> void:
	var definition := pattern as PdbModelDefinition
	if definition == null:
		return
	if from_index < 0 or from_index >= definition.fields.size():
		return
	if target_index < 0 or target_index >= definition.fields.size():
		return
	if from_index == target_index:
		return
	var target_group: String = definition.fields[target_index].export_group
	definition.fields[from_index].export_group = target_group
	_pending_flash_field = definition.fields[from_index].field_name
	definition.move_field(from_index, target_index)
	_rebuild_field_list()
	value_changed.emit()

func _reorder_field_to_group(from_index: int, group_name: String) -> void:
	var definition := pattern as PdbModelDefinition
	if definition == null:
		return
	if from_index < 0 or from_index >= definition.fields.size():
		return
	var target_index := -1
	for i in range(definition.fields.size()):
		if i != from_index and definition.fields[i].export_group == group_name:
			target_index = i
			break
	definition.fields[from_index].export_group = group_name
	_pending_flash_field = definition.fields[from_index].field_name
	if target_index != -1:
		definition.move_field(from_index, target_index)
	_rebuild_field_list()
	value_changed.emit()
