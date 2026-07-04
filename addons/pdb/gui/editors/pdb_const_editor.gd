@tool
extends PdbPatternEditorBase

var list_container: VBoxContainer

func _log(msg: String) -> void:
	PdbLog.info("ConstEditor", msg)

func _setup_ui() -> void:
	_log("Setting up UI for: %s" % pattern.id)

	var values_label = Label.new()
	values_label.text = "Constants:"
	values_label.add_theme_font_size_override("font_size", 14)
	add_child(values_label)

	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	var name_input = LineEdit.new()
	name_input.placeholder_text = "CONST_NAME"
	name_input.size_flags_horizontal = SIZE_EXPAND_FILL
	name_input.custom_minimum_size.x = 150

	name_input.text_changed.connect(func(t): 
		var formatted = t.to_upper().replace(" ", "_")
		if name_input.text != formatted:
			name_input.text = formatted
			name_input.caret_column = formatted.length()
	)

	var type_btn = OptionButton.new()
	type_btn.add_item("String", 0)
	type_btn.add_item("StringName", 1)
	type_btn.add_item("Float", 2)
	type_btn.add_item("Int", 3)
	type_btn.add_item("Bool", 4)
	type_btn.add_item("Vector2", 5)
	type_btn.add_item("Rect2", 6)
	type_btn.add_item("Color", 7)

	var add_btn = Button.new()
	add_btn.text = "Add Const"
	add_btn.pressed.connect(func():
		var key = name_input.text.strip_edges()
		if key.is_empty():
			_log("Cannot add empty key")
			return

		var val
		match type_btn.selected:
			0: val = ""
			1: val = StringName("")
			2: val = 0.0
			3: val = 0
			4: val = false
			5: val = Vector2.ZERO
			6: val = Rect2()
			7: val = Color.WHITE

		_log("Adding const: %s = %s" % [key, val])
		pattern.set_const(key, val)
		name_input.text = ""
		_rebuild_list()
		value_changed.emit()
	)

	toolbar.add_child(name_input)
	toolbar.add_child(type_btn)
	toolbar.add_child(add_btn)
	add_child(toolbar)

	add_child(HSeparator.new())

	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 4)
	add_child(list_container)

	_rebuild_list()
	_log("UI setup complete, %d consts" % pattern.data.size())

func _rebuild_list() -> void:
	_log("Rebuilding list for: %s" % pattern.id)

	for c in list_container.get_children():
		c.queue_free()

	var dict = pattern.data as Dictionary
	if dict == null:
		_log("ERROR: pattern.data is null")
		return

	var keys = dict.keys()
	keys.sort()

	_log("Const has %d entries" % keys.size())

	for key in keys:
		_log("  Creating row for: %s = %s" % [key, dict[key]])

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var k_lbl = Label.new()
		k_lbl.text = str(key)
		k_lbl.custom_minimum_size.x = 150

		var current_key = key
		var val_editor = _create_value_editor(dict[key], func(v): 
			_log("Value changed: %s = %s" % [current_key, v])
			pattern.data[current_key] = v
			pattern.emit_changed()
			value_changed.emit()
		)
		val_editor.size_flags_horizontal = SIZE_EXPAND_FILL

		var del_btn = Button.new()
		del_btn.text = "X"
		del_btn.pressed.connect(func():
			_log("Removing: %s" % current_key)
			pattern.data.erase(current_key)
			pattern.emit_changed()
			_rebuild_list()
			value_changed.emit()
		)

		row.add_child(k_lbl)
		row.add_child(val_editor)
		row.add_child(del_btn)
		list_container.add_child(row)

	_log("List rebuilt: %d entries, container has %d children" % [keys.size(), list_container.get_child_count()])
