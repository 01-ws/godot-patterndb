@tool
class_name PdbTableView
extends VBoxContainer

signal committed
signal edit_instance_requested(id: StringName)
signal buffer_changed

var _db: PatternDatabaseFile
var _def_id: StringName = &""
var _fields: Array = []
var _columns: Array = []
var _depth: int = 0
var _rows: Array = []
var _dirty := false
var _active_col: int = -1
var _selected: Dictionary = {}
var _last_title_col: int = -1
var _last_title_click_ms: int = 0

var _def_picker: OptionButton
var _depth_slider: HSlider
var _depth_label: Label
var _tree: Tree
var _tree_wrap: Control
var _header_overlay: Control
var _dividers: Array[Control] = []
var _drag_col: int = -1
var _drag_width: float = 0.0
var _dirty_label: Label
var _btn_apply: Button
var _btn_revert: Button
var _changed_cells: Array = []
var _flash_tween: Tween

const COL_ID := 0

const BTN_PICK := 0
const BTN_OPEN := 1
const BTN_CLEAR := 2
const BTN_JUMP := 3
const BTN_EDITLIST := 4
const THUMB_MAX := 32
const MODIFIED_CELL_COLOR := Color(0.95, 0.66, 0.12, 0.20)
const NEW_ROW_COLOR := Color(0.28, 0.75, 0.38, 0.18)
const FLASH_PEAK_ALPHA := 0.60

func _init() -> void:
	name = "TableView"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()

func _build_ui() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	toolbar.add_child(_label("Table:"))
	_def_picker = OptionButton.new()
	_def_picker.item_selected.connect(_on_def_selected)
	toolbar.add_child(_def_picker)

	toolbar.add_child(_sep())
	toolbar.add_child(_label("Nesting:"))
	_depth_slider = HSlider.new()
	_depth_slider.min_value = 0
	_depth_slider.max_value = 2
	_depth_slider.step = 1
	_depth_slider.tick_count = 3
	_depth_slider.ticks_on_borders = true
	_depth_slider.custom_minimum_size = Vector2(90, 0)
	_depth_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_depth_slider.value_changed.connect(_on_depth_changed)
	toolbar.add_child(_depth_slider)
	_depth_label = _label("+0")
	toolbar.add_child(_depth_label)

	toolbar.add_child(_sep())
	toolbar.add_child(_button("Add Row", _add_row))
	toolbar.add_child(_button("Duplicate", _duplicate_selected))
	toolbar.add_child(_button("Delete", _delete_selected))
	toolbar.add_child(_button("Fill Down", _fill_down))
	toolbar.add_child(_button("Edit in Form…", _edit_selected_in_form))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)

	_dirty_label = _label("")
	toolbar.add_child(_dirty_label)
	_btn_revert = _button("Revert", _revert)
	toolbar.add_child(_btn_revert)
	_btn_apply = _button("Apply", _apply)
	toolbar.add_child(_btn_apply)

	_tree = Tree.new()
	_tree.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_MULTI
	_tree.column_titles_visible = true
	_tree.item_edited.connect(_on_item_edited)
	_tree.item_activated.connect(_on_item_activated)
	_tree.multi_selected.connect(_on_multi_selected)
	_tree.button_clicked.connect(_on_button_clicked)
	_tree.column_title_clicked.connect(_on_column_title_clicked)

	_tree_wrap = Control.new()
	_tree_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tree_wrap)
	_tree_wrap.add_child(_tree)

	_header_overlay = Control.new()
	_header_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tree_wrap.add_child(_header_overlay)
	set_process(true)

	_update_dirty_label()

func setup(db: PatternDatabaseFile) -> void:
	_db = db
	_dirty = false
	_populate_def_picker()
	if _def_picker.item_count > 0:
		_def_picker.select(0)
		_set_definition(StringName(_def_picker.get_item_text(0)))
	else:
		_def_id = &""
		_fields = []
		_rows = []
		_rebuild_tree()
	_update_dirty_label()

func refresh() -> void:
	if _db == null:
		return
	_populate_def_picker()
	if _def_id != &"" and _db.get_pattern(_def_id) is PdbModelDefinition:
		if not _dirty:
			_rebuild_buffer()
			_rebuild_tree()
	else:
		setup(_db)

func has_unsaved() -> bool:
	return _dirty

func export_recovery() -> Dictionary:
	return {"def_id": _def_id, "rows": _rows.duplicate(true)}

func restore_recovery(rec: Dictionary) -> void:
	if _db == null:
		return
	var did := StringName(rec.get("def_id", &""))
	if did == &"" or not (_db.get_pattern(did) is PdbModelDefinition):
		return
	_select_def_in_picker(did)
	_def_id = did
	var def := _db.get_pattern(did) as PdbModelDefinition
	_fields = def.fields.duplicate() if def else []
	_rows = (rec.get("rows", []) as Array).duplicate(true)
	_dirty = true
	_update_dirty_label()
	_rebuild_tree()

func summarize_recovery(rec: Dictionary) -> Array:
	return recovery_summary(_db, rec)

static func recovery_summary(db: PatternDatabaseFile, rec: Dictionary) -> Array:
	var out: Array = []
	if db == null or not (rec.get("rows") is Array):
		return out
	for row in rec["rows"]:
		var rid = row.get("id", &"")
		if row.get("_deleted", false):
			if db.has_pattern(rid):
				out.append("deleted: %s" % rid)
		elif row.get("_new", false) or not db.has_pattern(rid):
			out.append("added: %s" % rid)
		else:
			var inst := db.get_pattern(rid) as PdbModelInstance
			var data_changed := inst == null or var_to_str(inst.data) != var_to_str(row.get("data", {}))
			var tags_changed := inst == null or var_to_str(inst.tags) != var_to_str(row.get("tags", PackedStringArray()))
			if data_changed or tags_changed:
				out.append("modified: %s" % rid)
	return out

func _populate_def_picker() -> void:
	var current := _def_id
	_def_picker.clear()
	if _db == null:
		return
	for d in _db.get_all_definitions():
		_def_picker.add_item(str(d.id))
	for i in _def_picker.item_count:
		if StringName(_def_picker.get_item_text(i)) == current:
			_def_picker.select(i)
			break

func _on_def_selected(index: int) -> void:
	var target := StringName(_def_picker.get_item_text(index))
	if target == _def_id:
		return
	_select_def_in_picker(_def_id)
	_guard_then(func():
		_select_def_in_picker(target)
		_set_definition(target)
	, str(target))
func _set_definition(def_id: StringName) -> void:
	_def_id = def_id
	var def := _db.get_pattern(def_id) as PdbModelDefinition
	_fields = def.fields.duplicate() if def else []
	_rebuild_buffer()
	_rebuild_tree()
	_dirty = false
	_update_dirty_label()

func _rebuild_buffer() -> void:
	_rows.clear()
	if _db == null or _def_id == &"":
		return
	for inst in _db.get_instances_of_definition(_def_id):
		_rows.append({
			"id": inst.id,
			"data": (inst.data as Dictionary).duplicate(true),
			"tags": PackedStringArray(inst.tags),
			"_new": false,
			"_deleted": false,
		})

func _row_of(item: TreeItem) -> Dictionary:
	var ri = item.get_metadata(COL_ID)
	if ri == null or ri < 0 or ri >= _rows.size():
		return {}
	return _rows[ri]

func _rebuild_tree() -> void:
	_tree.clear()
	_selected.clear()
	_changed_cells.clear()
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_active_col = -1
	_rebuild_columns()
	_tree.columns = _columns.size()
	for col in _columns.size():
		_tree.set_column_title(col, _col_title(col))
		_tree.set_column_expand(col, false)
		_tree.set_column_custom_minimum_width(col, _col_min_width(col))
		_tree.set_column_clip_content(col, true)

	var root := _tree.create_item()
	for ri in _rows.size():
		if _rows[ri].get("_deleted", false):
			continue
		_make_item(root, ri)
	_rebuild_dividers()

func _make_item(root: TreeItem, ri: int) -> void:
	var row: Dictionary = _rows[ri]
	var item := _tree.create_item(root)
	item.set_metadata(COL_ID, ri)
	for col in _columns.size():
		_render_column(item, col, row)

func _rebuild_columns() -> void:
	_columns.clear()
	_columns.append({"kind": "id"})
	for field in _fields:
		if _depth >= 1 and field.field_type == TYPE_DICTIONARY:
			var paths := _dict_leaf_paths(field, _depth)
			if paths.is_empty():
				_columns.append({"kind": "field", "field": field})
			else:
				for p in paths:
					var title := str(field.field_name)
					for k in p:
						title += " ▸ " + str(k)
					_columns.append({"kind": "leaf", "field": field, "path": p, "title": title})
		else:
			_columns.append({"kind": "field", "field": field})
	_columns.append({"kind": "tags"})

func _col_title(col: int) -> String:
	var desc: Dictionary = _columns[col]
	match desc.get("kind"):
		"id":
			return "id"
		"tags":
			return "tags"
		"leaf":
			return desc.get("title", "")
		_:
			return str(desc["field"].field_name)

func _col_value(col: int, row: Dictionary) -> Variant:
	var desc: Dictionary = _columns[col]
	match desc.get("kind"):
		"id":
			return row["id"]
		"tags":
			return row["tags"]
		"field":
			return row["data"].get(desc["field"].field_name)
		"leaf":
			var v = row["data"].get(desc["field"].field_name)
			for k in desc["path"]:
				if v is Dictionary and v.has(k):
					v = v[k]
				else:
					return null
			return v
	return null

func _col_set(col: int, row: Dictionary, value: Variant) -> bool:
	var desc: Dictionary = _columns[col]
	match desc.get("kind"):
		"field":
			row["data"][desc["field"].field_name] = value
			return true
		"leaf":
			var container = row["data"].get(desc["field"].field_name)
			if not (container is Dictionary):
				return false
			var d: Dictionary = container
			for i in range(desc["path"].size() - 1):
				var seg = desc["path"][i]
				if not (d.get(seg) is Dictionary):
					return false
				d = d[seg]
			var last = desc["path"][desc["path"].size() - 1]
			if not d.has(last):
				return false
			d[last] = value
			return true
	return false

func _col_field(col: int) -> PdbFieldDefinition:
	if col >= 0 and col < _columns.size():
		return _columns[col].get("field")
	return null

func _render_column(item: TreeItem, col: int, row: Dictionary) -> void:
	var desc: Dictionary = _columns[col]
	match desc.get("kind"):
		"id":
			item.set_text(col, str(row["id"]))
			item.set_editable(col, row.get("_new", false))
		"tags":
			item.set_text(col, ", ".join(row["tags"]))
			item.set_editable(col, true)
		"leaf":
			_render_leaf(item, col, _col_value(col, row))
		_:
			_render_cell(item, col, desc["field"], row["data"].get(desc["field"].field_name))
	_apply_change_highlight(item, col, row)

func _apply_change_highlight(item: TreeItem, col: int, row: Dictionary) -> void:
	if _db == null or not _col_changed(col, row):
		return
	var base: Color = _new_row_color() if row.get("_new", false) else _modified_color()
	item.set_custom_bg_color(col, base)
	_changed_cells.append({"item": item, "col": col, "base": base})

func _modified_color() -> Color:
	if _db != null and _db.meta_data.has("hl_modified"):
		return _db.meta_data["hl_modified"]
	return MODIFIED_CELL_COLOR

func _new_row_color() -> Color:
	if _db != null and _db.meta_data.has("hl_new"):
		return _db.meta_data["hl_new"]
	return NEW_ROW_COLOR

func _flash_peak() -> float:
	if _db != null and _db.meta_data.has("hl_flash_alpha"):
		return clampf(float(_db.meta_data["hl_flash_alpha"]), 0.0, 1.0)
	return FLASH_PEAK_ALPHA

func _col_changed(col: int, row: Dictionary) -> bool:
	if row.get("_new", false):
		return true
	if _db == null:
		return false
	if _columns[col].get("kind") == "id":
		return false
	var inst := _db.get_pattern(row["id"]) as PdbModelInstance
	if inst == null:
		return true
	var original := {"id": inst.id, "tags": PackedStringArray(inst.tags), "data": inst.data}
	return var_to_str(_col_value(col, row)) != var_to_str(_col_value(col, original))

func _refresh_cell_highlight(item: TreeItem, col: int, row: Dictionary) -> void:
	if not is_instance_valid(item) or col < 0 or col >= _columns.size():
		return
	for i in range(_changed_cells.size() - 1, -1, -1):
		var e = _changed_cells[i]
		if e["item"] == item and e["col"] == col:
			_changed_cells.remove_at(i)
	if _db != null and _col_changed(col, row):
		var base: Color = _new_row_color() if row.get("_new", false) else _modified_color()
		item.set_custom_bg_color(col, base)
		_changed_cells.append({"item": item, "col": col, "base": base})
	else:
		item.clear_custom_bg_color(col)

func flash_changes(cycles := 3) -> void:
	if _changed_cells.is_empty() or not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	for i in cycles:
		_flash_tween.tween_method(_set_flash_level, 0.0, 1.0, 0.22)
		_flash_tween.tween_method(_set_flash_level, 1.0, 0.0, 0.32)
	_flash_tween.tween_callback(_set_flash_level.bind(0.0))

func _set_flash_level(t: float) -> void:
	for entry in _changed_cells:
		var item = entry["item"]
		if not is_instance_valid(item):
			continue
		var base: Color = entry["base"]
		var lit := base
		lit.a = lerpf(base.a, _flash_peak(), t)
		item.set_custom_bg_color(entry["col"], lit)

func _render_leaf(item: TreeItem, col: int, value: Variant) -> void:
	item.set_metadata(col, {"kind": "leaf"})
	if value is bool:
		item.set_cell_mode(col, TreeItem.CELL_MODE_CHECK)
		item.set_editable(col, true)
		item.set_checked(col, value)
		item.set_text(col, "")
	else:
		item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
		item.set_editable(col, true)
		item.set_text(col, _leaf_display(value))

func _dict_leaf_paths(field: PdbFieldDefinition, max_depth: int) -> Array:
	var freq: Dictionary = {}
	var path_of: Dictionary = {}
	for row in _rows:
		if row.get("_deleted", false):
			continue
		var v = row["data"].get(field.field_name)
		if v is Dictionary:
			_collect_leaf_paths(v, [], max_depth, freq, path_of)
	var keys: Array = path_of.keys()
	keys.sort_custom(func(a, b):
		if int(freq[a]) != int(freq[b]):
			return int(freq[a]) > int(freq[b])
		return str(a) < str(b)
	)
	var out: Array = []
	for k in keys:
		out.append(path_of[k])
	return out

func _collect_leaf_paths(d: Dictionary, prefix: Array, remaining: int, freq: Dictionary, path_of: Dictionary) -> void:
	for k in d.keys():
		var path: Array = prefix.duplicate()
		path.append(k)
		var val = d[k]
		if val is Dictionary and remaining > 1:
			_collect_leaf_paths(val, path, remaining - 1, freq, path_of)
		else:
			var key := ""
			for seg in path:
				key += "/" + str(seg)
			freq[key] = int(freq.get(key, 0)) + 1
			path_of[key] = path

func _on_depth_changed(value: float) -> void:
	_depth = int(value)
	if _depth_label:
		_depth_label.text = "+%d" % _depth
	if _db != null and _def_id != &"":
		_rebuild_tree()

func _render_cell(item: TreeItem, col: int, field: PdbFieldDefinition, value: Variant) -> void:
	item.set_editable(col, true)
	match _cell_kind(field):
		"bool":
			item.set_cell_mode(col, TreeItem.CELL_MODE_CHECK)
			item.set_checked(col, bool(value))
			item.set_text(col, "")
		"enum":
			var names: Array = []
			var vals: Array = []
			var en := _db.get_pattern(field.hint_string) as PdbEnum
			if en:
				for k in en.values:
					names.append(str(k))
					vals.append(int(en.values[k]))
			item.set_cell_mode(col, TreeItem.CELL_MODE_RANGE)
			item.set_text(col, ",".join(names))
			item.set_range(col, max(0, vals.find(int(value if value != null else 0))))
			item.set_metadata(col, {"kind": "enum", "vals": vals})
		"ref":
			var ids: Array = ["<none>"]
			var idvals: Array = [&""]
			for inst in _db.get_instances_including_subtypes(StringName(field.hint_string)):
				ids.append(str(inst.id))
				idvals.append(inst.id)
			item.set_cell_mode(col, TreeItem.CELL_MODE_RANGE)
			item.set_text(col, ",".join(ids))
			var cur := StringName(str(value)) if value != null else &""
			item.set_range(col, max(0, idvals.find(cur)))
			item.set_metadata(col, {"kind": "ref", "ids": idvals})
			var ref_jump := _editor_icon("Forward")
			if ref_jump != null:
				item.add_button(col, ref_jump, BTN_JUMP, false, "Edit the referenced table")
		"reflist":
			item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
			item.set_editable(col, false)
			item.set_text(col, _id_list_text(value))
			item.set_metadata(col, {"kind": "reflist"})
			var edit_icon := _editor_icon("Edit")
			if edit_icon != null:
				item.add_button(col, edit_icon, BTN_EDITLIST, false, "Edit list (add / remove)")
			var list_jump := _editor_icon("Forward")
			if list_jump != null:
				item.add_button(col, list_jump, BTN_JUMP, false, "Edit the referenced table")
		"dict":
			item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
			item.set_editable(col, false)
			item.set_text(col, _compact_dict(value if value is Dictionary else {}))
			item.set_metadata(col, {"kind": "dict"})
			item.set_tooltip_text(col, "Raise Nesting (+1/+2) or Edit in Form to change these")
		"asset":
			_render_asset_cell(item, col, field, value)
		_:
			item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
			item.set_text(col, _value_to_text(value, field))
			item.set_metadata(col, {"kind": "text"})

func _on_item_activated() -> void:
	var item := _tree.get_selected()
	if item == null:
		return
	var col := _tree.get_selected_column()
	if col < 0 or col >= _columns.size():
		return
	var field := _col_field(col)
	if field == null:
		return
	if _cell_kind(field) == "reflist":
		var ri = item.get_metadata(COL_ID)
		if ri != null:
			_open_ref_list_editor(int(ri), field)

func _on_item_edited() -> void:
	var item := _tree.get_edited()
	var col := _tree.get_edited_column()
	if item == null:
		return
	_active_col = col
	var ri = item.get_metadata(COL_ID)
	if ri == null:
		return
	var row: Dictionary = _rows[ri]
	var desc: Dictionary = _columns[col]
	match desc.get("kind"):
		"id":
			if row.get("_new", false):
				row["id"] = StringName(item.get_text(col).strip_edges())
				_mark_dirty()
		"tags":
			row["tags"] = _parse_tags(item.get_text(col))
			_mark_dirty()
		"leaf":
			var old_val = _col_value(col, row)
			var nv_leaf
			if item.get_cell_mode(col) == TreeItem.CELL_MODE_CHECK:
				nv_leaf = item.is_checked(col)
			else:
				nv_leaf = _parse_leaf(item.get_text(col), old_val)
			if _col_set(col, row, nv_leaf):
				_mark_dirty()
			else:
				_render_column(item, col, row)
		_:
			var field: PdbFieldDefinition = desc["field"]
			var new_value = _read_cell(item, col, field)
			if new_value == null and _cell_kind(field) == "text" and item.get_text(col).strip_edges() != "":
				_flash("Could not parse value for '%s'" % field.field_name)
				_render_cell(item, col, field, row["data"].get(field.field_name))
				return
			row["data"][field.field_name] = new_value
			_mark_dirty()
	call_deferred("_refresh_cell_highlight", item, col, row)

func _read_cell(item: TreeItem, col: int, field: PdbFieldDefinition) -> Variant:
	match _cell_kind(field):
		"bool":
			return item.is_checked(col)
		"enum":
			var meta = item.get_metadata(col)
			var idx := int(item.get_range(col))
			var vals: Array = meta.get("vals", []) if meta is Dictionary else []
			return vals[idx] if idx >= 0 and idx < vals.size() else 0
		"ref":
			var meta2 = item.get_metadata(col)
			var idx2 := int(item.get_range(col))
			var ids: Array = meta2.get("ids", []) if meta2 is Dictionary else []
			return ids[idx2] if idx2 >= 0 and idx2 < ids.size() else &""
		"asset":
			return item.get_text(col)
		"reflist":
			return _parse_id_list(item.get_text(col))
		"dict":
			return null
		_:
			return _text_to_value(item.get_text(col), field)

func _add_row() -> void:
	if _db == null or _def_id == &"":
		return
	var def := _db.get_pattern(_def_id) as PdbModelDefinition
	var data: Dictionary = {}
	if def:
		for f in def.fields:
			data[f.field_name] = f.get_default()
	_rows.append({
		"id": _unique_new_id(),
		"data": data,
		"tags": PackedStringArray(),
		"_new": true,
		"_deleted": false,
	})
	_mark_dirty()
	_rebuild_tree()

func _duplicate_selected() -> void:
	var items := _selected_items()
	if items.is_empty():
		return
	for item in items:
		var row := _row_of(item)
		if row.is_empty():
			continue
		_rows.append({
			"id": _unique_new_id(),
			"data": (row["data"] as Dictionary).duplicate(true),
			"tags": PackedStringArray(row["tags"]),
			"_new": true,
			"_deleted": false,
		})
	_mark_dirty()
	_rebuild_tree()

func _delete_selected() -> void:
	var items := _selected_items()
	if items.is_empty():
		return
	for item in items:
		var ri = item.get_metadata(COL_ID)
		if ri != null:
			_rows[ri]["_deleted"] = true
	_mark_dirty()
	_rebuild_tree()

func _fill_down() -> void:
	var items := _selected_items()
	if items.size() < 2 or _active_col < 0:
		_flash("Select a column cell, then multiple rows, to fill down")
		return
	var col := _active_col
	var desc: Dictionary = _columns[col]
	if desc.get("kind") == "id":
		return
	var top_row := _row_of(items[0])
	if top_row.is_empty():
		return
	var src = _col_value(col, top_row)
	for i in range(1, items.size()):
		var row := _row_of(items[i])
		if row.is_empty():
			continue
		match desc.get("kind"):
			"tags":
				row["tags"] = PackedStringArray(src)
			"leaf":
				_col_set(col, row, src)
			_:
				row["data"][desc["field"].field_name] = src
	_mark_dirty()
	_rebuild_tree()

func _edit_selected_in_form() -> void:
	var items := _selected_items()
	if items.is_empty():
		return
	var row := _row_of(items[0])
	if row.is_empty() or row.get("_new", false):
		_flash("Apply first to edit a new row in the form")
		return
	edit_instance_requested.emit(row["id"])

func _apply() -> void:
	if _db == null or _def_id == &"":
		return
	var report := _commit_rows(_db, _def_id, _rows)
	if not report.errors.is_empty():
		_flash(report.errors[0])
		return
	_dirty = false
	_rebuild_buffer()
	_rebuild_tree()
	_update_dirty_label()
	committed.emit()
	buffer_changed.emit()

func _revert() -> void:
	_rebuild_buffer()
	_rebuild_tree()
	_dirty = false
	_update_dirty_label()
	buffer_changed.emit()

func apply_buffer() -> void:
	_apply()

func revert_buffer() -> void:
	_revert()

static func _commit_rows(db: PatternDatabaseFile, def_id: StringName, rows: Array) -> Dictionary:
	var report := {"added": 0, "updated": 0, "deleted": 0, "errors": []}
	var seen: Dictionary = {}
	for row in rows:
		if row.get("_deleted", false):
			continue
		var rid: StringName = row["id"]
		if not PdbPattern.is_valid_identifier(rid):
			report.errors.append("Invalid id: '%s'" % rid)
			return report
		if seen.has(rid):
			report.errors.append("Duplicate id in table: '%s'" % rid)
			return report
		seen[rid] = true
		if row.get("_new", false) and db.has_pattern(rid):
			report.errors.append("Id already exists: '%s'" % rid)
			return report

	for row in rows:
		var rid: StringName = row["id"]
		if row.get("_deleted", false):
			if not row.get("_new", false) and db.has_pattern(rid):
				db.remove_pattern(rid)
				report.deleted += 1
			continue
		var inst := db.get_pattern(rid) as PdbModelInstance
		if inst == null:
			inst = PdbModelInstance.new()
			inst.id = rid
			inst.definition_id = def_id
			inst.set_database(db)
			db.add_pattern(inst)
			report.added += 1
		else:
			report.updated += 1
		inst.data = (row["data"] as Dictionary).duplicate(true)
		inst.tags = PackedStringArray(row["tags"])
	return report

func _cell_kind(field: PdbFieldDefinition) -> String:
	if field.field_type == TYPE_BOOL:
		return "bool"
	if field.field_type == TYPE_INT and field.hint == PROPERTY_HINT_ENUM:
		return "enum"
	if field.is_resource_field():
		if _db != null and _db.get_pattern(field.hint_string) is PdbModelDefinition:
			return "ref"
		return "asset"
	if field.is_array_field():
		var elem := field.get_array_element_type()
		if elem != "" and _db != null and _db.get_pattern(StringName(elem)) is PdbModelDefinition:
			return "reflist"
	if field.field_type == TYPE_DICTIONARY:
		return "dict"
	return "text"

func _render_asset_cell(item: TreeItem, col: int, field: PdbFieldDefinition, value: Variant) -> void:
	item.set_cell_mode(col, TreeItem.CELL_MODE_STRING)
	item.set_metadata(col, {"kind": "asset"})
	var path := ""
	if value is String:
		path = value
	elif value is Resource:
		path = value.resource_path
	item.set_tooltip_text(col, path)

	var tex := _resolve_texture(value, field)
	if tex != null:
		item.set_icon(col, tex)
		item.set_icon_max_width(col, THUMB_MAX)

	var pick_icon := _editor_icon("Folder")
	if pick_icon == null:
		item.set_editable(col, true)
		item.set_text(col, path)
		return

	item.set_editable(col, false)
	item.set_text(col, path.get_file() if path != "" else "<none>")
	item.add_button(col, pick_icon, BTN_PICK, false, "Pick / change resource")
	if path != "" and _is_scene_field(field):
		var open_icon := _editor_icon("PackedScene")
		if open_icon != null:
			item.add_button(col, open_icon, BTN_OPEN, false, "Open scene")
	if path != "":
		var clear_icon := _editor_icon("Remove")
		if clear_icon != null:
			item.add_button(col, clear_icon, BTN_CLEAR, false, "Clear")

func _on_button_clicked(item: TreeItem, column: int, id: int, _mouse_button_index: int) -> void:
	var ri = item.get_metadata(COL_ID)
	if ri == null:
		return
	var field := _col_field(column)
	if field == null:
		return
	match id:
		BTN_PICK:
			_open_asset_picker(int(ri), field)
		BTN_OPEN:
			var p = _rows[ri]["data"].get(field.field_name)
			if p is String and p != "":
				var ei = _editor_singleton()
				if ei:
					ei.open_scene_from_path(p)
		BTN_CLEAR:
			_rows[ri]["data"][field.field_name] = ""
			_mark_dirty()
			_rebuild_tree()
		BTN_JUMP:
			_handle_jump(item, column, field)
		BTN_EDITLIST:
			_open_ref_list_editor(int(ri), field)

func _handle_jump(item: TreeItem, column: int, field: PdbFieldDefinition) -> void:
	if _db == null:
		return
	var kind := _cell_kind(field)
	var target_def := &""
	var focus_id := &""
	if kind == "ref":
		target_def = StringName(field.hint_string)
		var v = _read_cell(item, column, field)
		focus_id = StringName(str(v)) if v != null else &""
	elif kind == "reflist":
		target_def = StringName(field.get_array_element_type())
		var ri = item.get_metadata(COL_ID)
		var arr = _rows[ri]["data"].get(field.field_name) if ri != null else null
		if arr is Array and not (arr as Array).is_empty():
			focus_id = StringName(str(arr[0]))
	if target_def == &"" or not (_db.get_pattern(target_def) is PdbModelDefinition):
		return
	_jump_to(target_def, focus_id)

func _jump_to(def_id: StringName, focus_id: StringName) -> void:
	_guard_then(func():
		_select_def_in_picker(def_id)
		_set_definition(def_id)
		if focus_id != &"":
			_select_row_by_id(focus_id)
	, str(def_id))

func _guard_then(proceed: Callable, target_desc: String) -> void:
	if not _dirty:
		proceed.call()
		return
	_flash_apply_revert()
	var d := ConfirmationDialog.new()
	d.title = "Unsaved table changes"
	d.dialog_text = "Commit or revert your changes to '%s' before editing '%s'." % [str(_def_id), target_desc]
	d.ok_button_text = "Apply"
	d.add_button("Revert", true, "revert")
	add_child(d)
	d.popup_centered()
	d.confirmed.connect(func():
		d.queue_free()
		_apply()
		proceed.call()
	)
	d.custom_action.connect(func(action):
		if action == "revert":
			d.queue_free()
			_revert()
			proceed.call()
	)
	d.canceled.connect(func(): d.queue_free())

func _flash_apply_revert() -> void:
	if not is_inside_tree():
		return
	for b in [_btn_apply, _btn_revert]:
		if b == null:
			continue
		var tw := create_tween()
		tw.set_loops(3)
		tw.tween_property(b, "modulate", Color(1, 0.85, 0.2), 0.12)
		tw.tween_property(b, "modulate", Color(1, 1, 1), 0.12)

func _select_def_in_picker(def_id: StringName) -> void:
	for i in _def_picker.item_count:
		if StringName(_def_picker.get_item_text(i)) == def_id:
			_def_picker.select(i)
			return

func _select_row_by_id(id: StringName) -> void:
	var it := _tree.get_root()
	if it == null:
		return
	it = it.get_first_child()
	while it != null:
		if _row_of(it).get("id") == id:
			it.select(COL_ID)
			_tree.scroll_to_item(it)
			return
		it = it.get_next()

func _open_asset_picker(ri: int, field: PdbFieldDefinition) -> void:
	if not Engine.is_editor_hint():
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_RESOURCES
	for f in _asset_filters(field):
		fd.add_filter(f[0], f[1])
	fd.file_selected.connect(func(path):
		if ri >= 0 and ri < _rows.size():
			_rows[ri]["data"][field.field_name] = path
			_mark_dirty()
			_rebuild_tree()
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))

func _asset_filters(field: PdbFieldDefinition) -> Array:
	var t := field.hint_string
	if _class_is(t, "Texture2D"):
		return [["*.png,*.svg,*.jpg,*.jpeg,*.webp,*.bmp,*.tres,*.res", "Textures"]]
	if _class_is(t, "PackedScene"):
		return [["*.tscn,*.scn", "Scenes"]]
	if _class_is(t, "AudioStream"):
		return [["*.ogg,*.wav,*.mp3,*.tres,*.res", "Audio"]]
	if _class_is(t, "Mesh"):
		return [["*.obj,*.mesh,*.tres,*.res", "Meshes"]]
	return [["*.tres,*.res", "Resources"]]

func _open_ref_list_editor(ri: int, field: PdbFieldDefinition) -> void:
	if _db == null or ri < 0 or ri >= _rows.size():
		return
	var target_def := StringName(field.get_array_element_type())
	if not (_db.get_pattern(target_def) is PdbModelDefinition):
		return

	var all_ids: Array = []
	for inst in _db.get_instances_including_subtypes(target_def):
		all_ids.append(inst.id)

	var selected: Array = []
	var cur = _rows[ri]["data"].get(field.field_name)
	if cur is Array:
		for e in cur:
			var sid := StringName(str(e))
			if all_ids.has(sid) and not selected.has(sid):
				selected.append(sid)

	var dlg := ConfirmationDialog.new()
	dlg.title = "%s — %s" % [str(_rows[ri]["id"]), str(field.field_name)]
	dlg.ok_button_text = "Apply"
	dlg.min_size = Vector2i(560, 440)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var filter := LineEdit.new()
	filter.placeholder_text = "Filter available %s…" % target_def
	root.add_child(filter)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var avail := ItemList.new()
	avail.select_mode = ItemList.SELECT_MULTI
	avail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(_titled_column("Available", avail))
	var mid := VBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var btn_add := Button.new()
	btn_add.text = "→"
	var btn_rem := Button.new()
	btn_rem.text = "←"
	mid.add_child(btn_add)
	mid.add_child(btn_rem)
	cols.add_child(mid)
	var sel := ItemList.new()
	sel.select_mode = ItemList.SELECT_MULTI
	sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(_titled_column("Selected", sel))
	dlg.add_child(root)

	var refresh := func():
		var f := filter.text.strip_edges().to_lower()
		avail.clear()
		for aid in all_ids:
			if selected.has(aid):
				continue
			if f != "" and not str(aid).to_lower().contains(f):
				continue
			avail.add_item(str(aid))
		sel.clear()
		for s in selected:
			sel.add_item(str(s))
	var do_add := func():
		for idx in avail.get_selected_items():
			var aid := StringName(avail.get_item_text(idx))
			if not selected.has(aid):
				selected.append(aid)
		refresh.call()
	var do_rem := func():
		var drop: Array = []
		for idx in sel.get_selected_items():
			drop.append(StringName(sel.get_item_text(idx)))
		for d in drop:
			selected.erase(d)
		refresh.call()

	btn_add.pressed.connect(do_add)
	btn_rem.pressed.connect(do_rem)
	filter.text_changed.connect(func(_t): refresh.call())
	avail.item_activated.connect(func(_i): do_add.call())
	sel.item_activated.connect(func(_i): do_rem.call())
	dlg.confirmed.connect(func():
		_rows[ri]["data"][field.field_name] = selected.duplicate()
		_mark_dirty()
		_rebuild_tree()
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())

	add_child(dlg)
	refresh.call()
	dlg.popup_centered()

func _titled_column(title: String, body: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var l := Label.new()
	l.text = title
	v.add_child(l)
	v.add_child(body)
	return v

func _resolve_texture(value: Variant, field: PdbFieldDefinition) -> Texture2D:
	if value is Texture2D:
		return value
	var t := field.hint_string
	var maybe_texture := t == "" or _class_is(t, "Texture2D")
	if maybe_texture and value is String and value != "" and ResourceLoader.exists(value):
		var res = ResourceLoader.load(value)
		if res is Texture2D:
			return res as Texture2D
	return null

func _editor_singleton() -> Object:
	if Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface")
	return null

func _editor_icon(icon_name: String) -> Texture2D:
	if has_theme_icon(icon_name, "EditorIcons"):
		return get_theme_icon(icon_name, "EditorIcons")
	var ei = _editor_singleton()
	if ei:
		var theme := ei.get_editor_theme() as Theme
		if theme != null and theme.has_icon(icon_name, "EditorIcons"):
			return theme.get_icon(icon_name, "EditorIcons")
	return null

func _class_is(cls: String, base: String) -> bool:
	if cls == base:
		return true
	return ClassDB.class_exists(cls) and ClassDB.is_parent_class(cls, base)

func _is_scene_field(field: PdbFieldDefinition) -> bool:
	return _class_is(field.hint_string, "PackedScene")

func _column_min_width(field: PdbFieldDefinition) -> int:
	match _cell_kind(field):
		"bool":
			return 70
		"enum":
			return 150
		"ref":
			return 190
		"reflist":
			return 230
		"asset":
			return 210
		"dict":
			return 200
		_:
			return 160

func _col_min_width(col: int) -> int:
	var desc: Dictionary = _columns[col]
	match desc.get("kind"):
		"id":
			return 150
		"tags":
			return 220
		"leaf":
			return 110
		_:
			return _column_min_width(desc["field"])

func _rebuild_dividers() -> void:
	if _header_overlay == null:
		return
	for d in _dividers:
		d.queue_free()
	_dividers.clear()
	for c in _tree.columns:
		var div := Control.new()
		div.mouse_filter = Control.MOUSE_FILTER_STOP
		div.mouse_default_cursor_shape = Control.CURSOR_HSIZE
		div.tooltip_text = "Drag to resize · double-click to fit"
		div.gui_input.connect(_on_divider_input.bind(c))
		_header_overlay.add_child(div)
		_dividers.append(div)

func _process(_delta: float) -> void:
	if _tree == null or _header_overlay == null or _dividers.is_empty():
		return
	if not is_visible_in_tree():
		return
	var scroll_x := float(_tree.get_scroll().x)
	var h := _header_row_height()
	var x := 0.0
	for c in _tree.columns:
		x += float(_tree.get_column_width(c))
		if c >= _dividers.size():
			continue
		var d := _dividers[c]
		var handle_w := 22.0
		var px := x - scroll_x - handle_w * 0.5
		d.position = Vector2(px, 0.0)
		d.size = Vector2(handle_w, h)
		d.visible = px >= -handle_w and px <= _header_overlay.size.x

func _header_row_height() -> float:
	var font := _tree.get_theme_font("font")
	var fsize := _tree.get_theme_font_size("font_size")
	if font == null:
		return 28.0
	return font.get_height(fsize) + 12.0

func _on_divider_input(event: InputEvent, col: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			_auto_size_column(col)
			_drag_col = -1
			return
		if event.pressed:
			_drag_col = col
			_drag_width = float(_tree.get_column_width(col))
		else:
			_drag_col = -1
	elif event is InputEventMouseMotion and _drag_col == col:
		_drag_width += event.relative.x
		_tree.set_column_custom_minimum_width(col, int(maxf(40.0, _drag_width)))

func _on_column_title_clicked(column: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	var now := Time.get_ticks_msec()
	if column == _last_title_col and (now - _last_title_click_ms) <= 400:
		_last_title_col = -1
		_auto_size_column(column)
	else:
		_last_title_col = column
		_last_title_click_ms = now

func _auto_size_column(col: int) -> void:
	if col < 0 or col >= _tree.columns:
		return
	var font := _tree.get_theme_font("font")
	var fsize := _tree.get_theme_font_size("font_size")
	if font == null:
		font = ThemeDB.fallback_font
		fsize = ThemeDB.fallback_font_size
	if font == null:
		return
	var w := font.get_string_size(_tree.get_column_title(col), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var it := _tree.get_root()
	if it != null:
		it = it.get_first_child()
	while it != null:
		var tw := font.get_string_size(_cell_display_text(it, col), HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		w = maxf(w, tw)
		it = it.get_next()
	w += _column_extra_width(col)
	w = clampf(w, 60.0, 800.0)
	_tree.set_column_custom_minimum_width(col, int(ceil(w)))

func _cell_display_text(item: TreeItem, col: int) -> String:
	match item.get_cell_mode(col):
		TreeItem.CELL_MODE_CHECK:
			return ""
		TreeItem.CELL_MODE_RANGE:
			var opts := item.get_text(col).split(",")
			var sel := int(item.get_range(col))
			return opts[sel] if sel >= 0 and sel < opts.size() else ""
		_:
			return item.get_text(col)

func _column_extra_width(col: int) -> float:
	var pad := 22.0
	if col < 0 or col >= _columns.size():
		return pad
	var desc: Dictionary = _columns[col]
	match desc.get("kind"):
		"id", "tags":
			return pad + 16.0
		"leaf":
			return pad
	var field: PdbFieldDefinition = desc["field"]
	match _cell_kind(field):
		"bool":
			return 30.0
		"enum":
			return pad + 30.0
		"ref", "reflist":
			return pad + 58.0
		"asset":
			return pad + float(THUMB_MAX) + 88.0
		_:
			return pad

func _value_to_text(value: Variant, field: PdbFieldDefinition) -> String:
	if value == null:
		return ""
	if value is String:
		return value
	if value is StringName:
		return str(value)
	if value is PackedStringArray:
		return ", ".join(value)
	if value is Dictionary:
		return _compact_dict(value)
	if value is Array:
		return _id_list_text(value)
	if value is Object:
		return str(value.resource_path) if value is Resource else ""
	return var_to_str(value)

func _compact_dict(d: Dictionary) -> String:
	var parts: Array = []
	for k in d.keys():
		var v = d[k]
		var vs := ""
		if v is Dictionary:
			vs = _compact_dict(v)
		elif v is Array:
			vs = _id_list_text(v)
		else:
			vs = str(v)
		parts.append("%s: %s" % [str(k), vs])
	return ", ".join(PackedStringArray(parts))

func _id_list_text(value: Variant) -> String:
	if not (value is Array):
		return str(value)
	var parts: Array = []
	for e in value:
		parts.append(str(e))
	return ", ".join(PackedStringArray(parts))

func _parse_id_list(text: String) -> Array:
	var out: Array = []
	for part in text.split(","):
		var t := part.strip_edges()
		if t != "":
			out.append(StringName(t))
	return out

func _leaf_display(value: Variant) -> String:
	if value == null:
		return ""
	if value is Dictionary:
		return _compact_dict(value)
	if value is Array:
		return _id_list_text(value)
	if value is PackedStringArray:
		return ", ".join(value)
	return str(value)

func _parse_leaf(text: String, old_value: Variant) -> Variant:
	match typeof(old_value):
		TYPE_BOOL:
			return text.strip_edges().to_lower() in ["true", "1", "yes", "on"]
		TYPE_INT:
			return int(text.to_int())
		TYPE_FLOAT:
			return text.to_float()
		TYPE_STRING:
			return text
		TYPE_STRING_NAME:
			return StringName(text)
		_:
			var v = str_to_var(text)
			return v if v != null else old_value

func _text_to_value(text: String, field: PdbFieldDefinition) -> Variant:
	match field.field_type:
		TYPE_STRING:
			return text
		TYPE_STRING_NAME:
			return StringName(text)
		TYPE_INT:
			return int(text.to_int())
		TYPE_FLOAT:
			return text.to_float()
		TYPE_PACKED_STRING_ARRAY:
			return _parse_tags(text)
		TYPE_OBJECT:
			return text
		_:
			var t := text.strip_edges()
			if t == "":
				return field.get_default()
			return str_to_var(text)

func _parse_tags(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in text.split(","):
		var t := part.strip_edges()
		if t != "":
			out.append(t)
	return out

func _unique_new_id() -> StringName:
	var n := 1
	while true:
		var candidate := StringName("new_%s_%d" % [str(_def_id).to_snake_case(), n])
		var taken := _db != null and _db.has_pattern(candidate)
		for row in _rows:
			if not row.get("_deleted", false) and row["id"] == candidate:
				taken = true
				break
		if not taken:
			return candidate
		n += 1
	return &"new_item"

func _selected_items() -> Array[TreeItem]:
	var out: Array[TreeItem] = []
	var it := _tree.get_root()
	if it == null:
		return out
	it = it.get_first_child()
	while it != null:
		if _selected.has(it):
			out.append(it)
		it = it.get_next()
	return out

func _on_multi_selected(item: TreeItem, column: int, selected: bool) -> void:
	_active_col = column
	if selected:
		_selected[item] = true
	else:
		_selected.erase(item)

func _mark_dirty() -> void:
	_dirty = true
	_update_dirty_label()
	buffer_changed.emit()

func _update_dirty_label() -> void:
	if _dirty_label == null:
		return
	_dirty_label.text = "  ● unsaved changes  " if _dirty else ""
	if _btn_apply:
		_btn_apply.disabled = not _dirty
	if _btn_revert:
		_btn_revert.disabled = not _dirty

func _flash(msg: String) -> void:
	if _dirty_label:
		_dirty_label.text = "  %s  " % msg

func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l

func _sep() -> VSeparator:
	return VSeparator.new()

func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b
