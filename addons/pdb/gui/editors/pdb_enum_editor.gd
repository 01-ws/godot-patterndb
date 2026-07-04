@tool
extends PdbPatternEditorBase

var list_container: VBoxContainer

func _log(msg: String) -> void:
	PdbLog.info("EnumEditor", msg)

func _setup_ui() -> void:
	_log("Setting up UI for: %s" % pattern.id)

	var values_label = Label.new()
	values_label.text = "Enum Values:"
	values_label.add_theme_font_size_override("font_size", 14)
	add_child(values_label)

	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	var name_input = LineEdit.new()
	name_input.placeholder_text = "NEW_VALUE_NAME"
	name_input.size_flags_horizontal = SIZE_EXPAND_FILL
	name_input.custom_minimum_size.x = 200

	name_input.text_changed.connect(func(t): 
		var formatted = t.replace(" ", "_")
		var enforce_upper := true
		if _database != null:
			enforce_upper = bool(_database.meta_data.get("enforce_upper_enums", true))
		if enforce_upper:
			formatted = formatted.to_upper()
		if name_input.text != formatted:
			name_input.text = formatted
			name_input.caret_column = formatted.length()
	)

	var add_btn = Button.new()
	add_btn.text = "Add Value"
	add_btn.pressed.connect(func():
		var key = name_input.text.strip_edges()
		if key.is_empty():
			_log("Cannot add empty key")
			return
		_log("Adding enum value: %s" % key)
		pattern.add_item(key)
		name_input.text = ""
		_rebuild_list()
		value_changed.emit()
	)

	toolbar.add_child(name_input)
	toolbar.add_child(add_btn)
	add_child(toolbar)

	add_child(HSeparator.new())

	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 4)
	add_child(list_container)

	_rebuild_list()
	_log("UI setup complete, %d values" % pattern.values.size())

func _rebuild_list() -> void:
	_log("Rebuilding list for enum: %s" % pattern.id)

	for c in list_container.get_children():
		c.queue_free()

	var pdb_enum = pattern as PdbEnum
	if not pdb_enum:
		_log("ERROR: pattern is not PdbEnum")
		return

	_log("Enum has %d values" % pdb_enum.values.size())

	var sorted_entries: Array = []
	for key in pdb_enum.values:
		sorted_entries.append({"name": key, "value": pdb_enum.values[key]})
		_log("  Found: %s = %d" % [key, pdb_enum.values[key]])
	sorted_entries.sort_custom(func(a, b): return a.value < b.value)

	for entry in sorted_entries:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var k_lbl = Label.new()
		k_lbl.text = str(entry.name)
		k_lbl.size_flags_horizontal = SIZE_EXPAND_FILL

		var v_spin = SpinBox.new()
		v_spin.value = entry.value
		v_spin.step = 1
		v_spin.allow_greater = true
		v_spin.allow_lesser = true
		v_spin.custom_minimum_size.x = 80
		var entry_name = entry.name
		v_spin.value_changed.connect(func(v):
			_log("Value changed: %s = %d" % [entry_name, int(v)])
			pdb_enum.set_item_value(entry_name, int(v))
			value_changed.emit()
		)

		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.pressed.connect(func():
			_log("Removing: %s" % entry_name)
			pdb_enum.remove_item(entry_name)
			_rebuild_list()
			value_changed.emit()
		)

		row.add_child(k_lbl)
		row.add_child(v_spin)
		row.add_child(del_btn)
		list_container.add_child(row)

	_log("List rebuilt: %d entries, container has %d children" % [sorted_entries.size(), list_container.get_child_count()])
