@tool
class_name PdbHistoryView
extends Control

signal database_mutated

var _controller: PdbHistoryController
var _list: ItemList
var _detail: RichTextLabel
var _filter: OptionButton
var _branch_select: OptionButton
var _undo_btn: Button
var _redo_btn: Button
var _restore_btn: Button
var _branch_btn: Button
var _export_btn: Button
var _filter_id: String = ""
var _selected_hash: String = ""
var _built := false

func setup(controller: PdbHistoryController) -> void:
	_controller = controller
	if not _built:
		_build_ui()
	refresh()

func _build_ui() -> void:
	_built = true
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var tb := HBoxContainer.new()
	_undo_btn = _mk_button("↶ Undo", _on_undo)
	_redo_btn = _mk_button("Redo ↷", _on_redo)
	var blabel := Label.new()
	blabel.text = "  Branch:"
	_branch_select = OptionButton.new()
	_branch_select.item_selected.connect(_on_branch_switch)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	var flabel := Label.new()
	flabel.text = "Filter:"
	_filter = OptionButton.new()
	_filter.item_selected.connect(_on_filter)
	var refresh_btn := _mk_button("⟳", refresh)
	tb.add_child(_undo_btn)
	tb.add_child(_redo_btn)
	tb.add_child(blabel)
	tb.add_child(_branch_select)
	tb.add_child(spacer)
	tb.add_child(flabel)
	tb.add_child(_filter)
	tb.add_child(refresh_btn)
	root.add_child(tb)

	var split := HSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	split.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_child(split)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(300, 0)
	_list.item_selected.connect(_on_item_selected)
	split.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.size_flags_vertical = SIZE_EXPAND_FILL
	split.add_child(right)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = false
	_detail.selection_enabled = true
	_detail.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(_detail)

	var actions := HBoxContainer.new()
	_restore_btn = _mk_button("Restore here", _on_restore)
	_branch_btn = _mk_button("Branch here", _on_branch)
	_export_btn = _mk_button("Export .pdb ↧", _on_export)
	actions.add_child(_restore_btn)
	actions.add_child(_branch_btn)
	actions.add_child(_export_btn)
	right.add_child(actions)

func _mk_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b

func refresh() -> void:
	if not _built:
		return
	if not (_controller and _controller.history):
		_list.clear()
		_detail.text = "No history for this database yet.\n(Save the database to begin tracking.)"
		_update_buttons()
		return
	_rebuild_filter()
	_rebuild_branches()
	_rebuild_list()
	_update_detail()
	_update_buttons()

func _rebuild_branches() -> void:
	_branch_select.clear()
	var names: Array = _controller.list_branches()
	if names.is_empty():
		_branch_select.add_item("main")
		_branch_select.disabled = true
		return
	_branch_select.disabled = names.size() <= 1
	var cur := _controller.current_branch()
	var sel := 0
	for i in names.size():
		_branch_select.add_item(String(names[i]))
		if String(names[i]) == cur:
			sel = i
	_branch_select.select(sel)

func _rebuild_filter() -> void:
	var prev := _filter_id
	_filter.clear()
	_filter.add_item("All objects")
	_filter.set_item_metadata(0, "")
	var ids := {}
	for h in _controller.history.commits:
		for a in _controller.history.commits[h].get("affected", []):
			ids[String(a)] = true
	var keys := ids.keys()
	keys.sort()
	var sel := 0
	for i in keys.size():
		_filter.add_item(keys[i])
		_filter.set_item_metadata(i + 1, keys[i])
		if keys[i] == prev:
			sel = i + 1
	_filter.select(sel)
	_filter_id = String(_filter.get_item_metadata(sel))

func _rebuild_list() -> void:
	_list.clear()
	var hist := _controller.history
	for h in _ordered_commits():
		var c: Dictionary = hist.commits[h]
		if _filter_id != "" and not (_filter_id in c.get("affected", [])):
			continue
		var mark := "● " if h == hist.head else "    "
		var kind := String(c.get("kind", "edit"))
		var badge := "  ⟂" if kind == "external" else ""
		var ops: Array = c.get("ops", [])
		var label := PdbDiff.list_label(ops)
		if label == "":
			label = String(c.get("summary", "change"))
		var text := "%s%s%s    · %s" % [mark, label, badge, _rel_time(c.get("ts", 0))]
		var idx := _list.add_item(text)
		_list.set_item_metadata(idx, h)
		if h == hist.head and _selected_hash == "":
			_selected_hash = h
		if h == _selected_hash:
			_list.select(idx)

func _ordered_commits() -> Array:
	var hist := _controller.history
	var arr: Array = hist.commits.keys()
	arr.sort_custom(func(a, b): return float(hist.commits[a].get("ts", 0)) > float(hist.commits[b].get("ts", 0)))
	return arr

func _update_detail() -> void:
	var hist := _controller.history
	if _selected_hash == "" or not hist.commits.has(_selected_hash):
		_detail.text = ""
		return
	var c: Dictionary = hist.commits[_selected_hash]
	var out := "%s\n%s\n\n" % [c.get("summary", "(change)"), _rel_time(c.get("ts", 0))]
	if _selected_hash == hist.head:
		out += "● Current position.\n\nThis change:\n" + PdbDiff.render_ops(c.get("ops", []))
	else:
		out += "Δ from current position  (restoring will apply this):\n"
		out += PdbDiff.render_ops(hist.delta(hist.head, _selected_hash))
		out += "\n\n— this commit alone —\n" + PdbDiff.render_ops(c.get("ops", []))
	_detail.text = out

func _update_buttons() -> void:
	var have := _controller != null
	_undo_btn.disabled = not (have and _controller.can_undo())
	_redo_btn.disabled = not (have and _controller.can_redo())
	var at_head := have and _controller.history and _selected_hash == _controller.history.head
	_restore_btn.disabled = at_head or _selected_hash == "" or not have
	_branch_btn.disabled = _selected_hash == "" or not have

func _on_item_selected(idx: int) -> void:
	_selected_hash = String(_list.get_item_metadata(idx))
	_update_detail()
	_update_buttons()

func _on_filter(idx: int) -> void:
	_filter_id = String(_filter.get_item_metadata(idx))
	_rebuild_list()
	_update_detail()

func _on_restore() -> void:
	if _selected_hash == "":
		return
	_controller.restore(_selected_hash)
	refresh()
	database_mutated.emit()

func _on_branch() -> void:
	if _selected_hash == "":
		return
	_controller.restore(_selected_hash)
	if _controller.history:
		_controller.history.create_branch("branch-%d" % _controller.history.branches.size())
	refresh()
	database_mutated.emit()

func _on_undo() -> void:
	_controller.undo()
	_selected_hash = _controller.history.head if _controller.history else ""
	refresh()
	database_mutated.emit()

func _on_redo() -> void:
	_controller.redo()
	_selected_hash = _controller.history.head if _controller.history else ""
	refresh()
	database_mutated.emit()

func _on_branch_switch(idx: int) -> void:
	var name := _branch_select.get_item_text(idx)
	if _controller.switch_branch(name).is_empty():
		return
	_selected_hash = _controller.history.head if _controller.history else ""
	refresh()
	database_mutated.emit()

func _on_export() -> void:
	if _selected_hash == "":
		return
	var path := _controller.export_snapshot(_selected_hash)
	if path != "":
		_detail.text = "✓ Exported snapshot to:\n%s\n\n%s" % [path, _detail.text]
	else:
		_detail.text = "✗ Snapshot export failed (unsaved database?).\n\n%s" % _detail.text
	_rebuild_list()

func _rel_time(ts) -> String:
	var d := Time.get_unix_time_from_system() - float(ts)
	if d < 60:
		return "just now"
	if d < 3600:
		return "%dm ago" % int(d / 60.0)
	if d < 86400:
		return "%dh ago" % int(d / 3600.0)
	return "%dd ago" % int(d / 86400.0)
