@tool
extends VBoxContainer

class_name PdbEditorFactory

signal value_changed
signal request_rename(new_id: StringName)
signal request_delete(pattern: Resource)
signal request_navigate(target_id: StringName)
signal tags_changed

static var _registry: Dictionary = {}

var _database: PatternDatabaseFile

static func register_editor(resource_script: Script, editor_script: Script) -> void:
	_registry[resource_script] = editor_script

static func clear_registry() -> void:
	_registry.clear()

static func get_editor_for(resource: Resource) -> Script:
	var res_script = resource.get_script()
	if not res_script:
		return null

	if _registry.has(res_script):
		return _registry[res_script]

	for registered_base in _registry:
		if _script_inherits_from(res_script, registered_base):
			return _registry[registered_base]

	return null

static func _script_inherits_from(child: Script, parent: Script) -> bool:
	var current = child
	while current:
		if current == parent:
			return true
		current = current.get_base_script()
	return false

func set_database(db: PatternDatabaseFile) -> void:
	_database = db

func load_pattern(pattern: Resource) -> void:
	for child in get_children():
		child.queue_free()

	_build_header(pattern)

	var editor_script = PdbEditorFactory.get_editor_for(pattern)
	var content: Control

	if editor_script:
		content = editor_script.new()
		content.pattern = pattern

		if content.has_method("set_database") and _database:
			content.set_database(_database)

		if content.has_signal("value_changed"):
			content.value_changed.connect(func(): value_changed.emit())

		if content.has_signal("request_navigate"):
			content.request_navigate.connect(func(id): request_navigate.emit(id))

		if content.has_method("_setup_ui"):
			content._setup_ui()
	else:
		content = Label.new()
		content.text = "No registered editor for this pattern type.\nType: %s" % pattern.get_class()

	content.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(content)

	_build_footer(pattern)

func _build_header(pattern: Resource) -> void:
	var header_vbox = VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 8)

	var id_row = HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 10)

	var id_label = Label.new()
	id_label.text = "ID / Key:"
	id_label.custom_minimum_size.x = 100

	var id_input = LineEdit.new()
	id_input.text = pattern.id
	id_input.size_flags_horizontal = SIZE_EXPAND_FILL
	id_input.custom_minimum_size.x = 200

	var update_btn = Button.new()
	update_btn.text = "Update ID"
	update_btn.disabled = true
	update_btn.focus_mode = Control.FOCUS_NONE

	id_input.text_changed.connect(func(new_text):
		var clean = new_text.strip_edges()
		update_btn.disabled = (clean == str(pattern.id) or clean.is_empty())
	)

	id_input.text_submitted.connect(func(new_text):
		if not update_btn.disabled:
			request_rename.emit(new_text.strip_edges())
	)

	update_btn.pressed.connect(func():
		request_rename.emit(id_input.text.strip_edges())
	)

	id_row.add_child(id_label)
	id_row.add_child(id_input)
	id_row.add_child(update_btn)
	header_vbox.add_child(id_row)

	var tags_row = HBoxContainer.new()
	tags_row.add_theme_constant_override("separation", 10)
	var tags_label = Label.new()
	tags_label.text = "Tags:"
	tags_label.custom_minimum_size.x = 100
	tags_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var tags_box = VBoxContainer.new()
	tags_box.size_flags_horizontal = SIZE_EXPAND_FILL
	var chips = HFlowContainer.new()
	tags_box.add_child(chips)
	var add_input = LineEdit.new()
	add_input.placeholder_text = "add tag \u2014 dot.paths nest (e.g. element.fire)"
	add_input.size_flags_horizontal = SIZE_EXPAND_FILL
	tags_box.add_child(add_input)
	tags_row.add_child(tags_label)
	tags_row.add_child(tags_box)
	header_vbox.add_child(tags_row)

	_populate_tag_chips(chips, pattern)
	add_input.text_submitted.connect(func(t: String):
		var clean := t.strip_edges()
		if clean != "":
			pattern.add_tag(clean)
			pattern.emit_changed()
			value_changed.emit()
			tags_changed.emit()
			add_input.text = ""
			_populate_tag_chips(chips, pattern)
	)

	var desc_row = HBoxContainer.new()
	desc_row.add_theme_constant_override("separation", 10)
	var desc_label = Label.new()
	desc_label.text = "Description:"
	desc_label.custom_minimum_size.x = 100
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var desc_input = TextEdit.new()
	desc_input.text = pattern.description
	desc_input.placeholder_text = "(optional)"
	desc_input.size_flags_horizontal = SIZE_EXPAND_FILL
	desc_input.custom_minimum_size.y = 60
	desc_input.scroll_fit_content_height = true
	desc_input.text_changed.connect(func():
		pattern.description = desc_input.text
		pattern.emit_changed()
		value_changed.emit()
	)
	desc_row.add_child(desc_label)
	desc_row.add_child(desc_input)
	header_vbox.add_child(desc_row)

	add_child(header_vbox)
	add_child(HSeparator.new())

func _populate_tag_chips(chips: HFlowContainer, pattern: Resource) -> void:
	for c in chips.get_children():
		chips.remove_child(c)
		c.queue_free()
	if pattern.tags.is_empty():
		var none := Label.new()
		none.text = "(no tags)"
		none.modulate = Color(1, 1, 1, 0.4)
		chips.add_child(none)
		return
	for tag in pattern.tags:
		var this_tag := str(tag)
		var chip := Button.new()
		chip.text = "%s  \u2715" % this_tag
		chip.tooltip_text = "Remove tag \"%s\"" % this_tag
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(func():
			pattern.remove_tag(this_tag)
			pattern.emit_changed()
			value_changed.emit()
			tags_changed.emit()
			_populate_tag_chips(chips, pattern)
		)
		chips.add_child(chip)

func _build_footer(pattern: Resource) -> void:
	add_child(HSeparator.new())
	var footer_hbox = HBoxContainer.new()
	footer_hbox.alignment = BoxContainer.ALIGNMENT_END

	var del_label = Label.new()
	del_label.text = "Actions:"
	del_label.modulate = Color(1, 1, 1, 0.5)

	var del_btn = Button.new()
	del_btn.text = "Delete Pattern"
	del_btn.modulate = Color(1, 0.4, 0.4) 
	del_btn.pressed.connect(func():
		request_delete.emit(pattern)
	)

	footer_hbox.add_child(del_label)
	footer_hbox.add_child(del_btn)
	add_child(footer_hbox)
