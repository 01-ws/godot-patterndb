@tool
class_name PdbIconPicker
extends AcceptDialog

signal icon_chosen(icon_name: String)

const COLUMNS := 10
const MAX_SHOWN := 600

var _search: LineEdit
var _grid: GridContainer
var _count_label: Label
var _all: Array = []

func _init() -> void:
	title = "Pick a list icon"
	ok_button_text = "Close"
	size = Vector2i(620, 560)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)

	_search = LineEdit.new()
	_search.placeholder_text = "Search icons\u2026"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	vb.add_child(_search)

	_count_label = Label.new()
	_count_label.modulate = Color(1, 1, 1, 0.55)
	vb.add_child(_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)
	vb.add_child(scroll)

	add_child(vb)

func popup_for_selection() -> void:
	_ensure_loaded()
	if not Engine.is_editor_hint() and theme == null:
		var pt := _picker_theme()
		if pt != null:
			theme = pt
	_search.text = ""
	_rebuild("")
	popup_centered()
	_search.grab_focus()

func _ensure_loaded() -> void:
	if not _all.is_empty():
		return
	var theme := _picker_theme()
	if theme == null:
		return
	var names := theme.get_icon_list("EditorIcons")
	var arr := Array(names)
	arr.sort()
	for raw in arr:
		var nm := str(raw)
		_all.append({"name": nm, "tex": theme.get_icon(nm, "EditorIcons")})

func _picker_theme() -> Theme:
	var n: Node = self
	while n != null:
		if n is Control and (n as Control).theme != null:
			return (n as Control).theme
		if n is Window and (n as Window).theme != null:
			return (n as Window).theme
		n = n.get_parent()
	if Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface").get_editor_theme() as Theme
	return null

func _on_search_changed(text: String) -> void:
	_rebuild(text)

func _rebuild(filter: String) -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()

	var q := filter.strip_edges().to_lower()
	var shown := 0
	var total := 0
	for entry in _all:
		var nm: String = entry["name"]
		if q != "" and not nm.to_lower().contains(q):
			continue
		total += 1
		if shown >= MAX_SHOWN:
			continue
		var b := Button.new()
		b.icon = entry["tex"]
		b.tooltip_text = nm
		b.custom_minimum_size = Vector2(44, 44)
		b.expand_icon = true
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func():
			icon_chosen.emit(nm)
			hide()
		)
		_grid.add_child(b)
		shown += 1

	if total > MAX_SHOWN:
		_count_label.text = "Showing %d of %d \u2014 type to narrow" % [MAX_SHOWN, total]
	elif total == 0:
		_count_label.text = "No icons match"
	else:
		_count_label.text = "%d icon%s" % [total, "" if total == 1 else "s"]
