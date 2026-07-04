@tool
extends Control

signal pdb_opened(pdb: PatternDatabaseFile)
signal pdb_closed

const PDB_CONST = preload("res://addons/pdb/core/pdb_const.gd")
const PDB_ENUM = preload("res://addons/pdb/core/pdb_enum.gd")
const PDB_MODEL_DEFINITION = preload("res://addons/pdb/core/pdb_model_definition.gd")
const PDB_MODEL_INSTANCE = preload("res://addons/pdb/core/pdb_model_instance.gd")
const EDITOR_FACTORY = preload("res://addons/pdb/gui/editors/pdb_editor_factory.gd")
const PDB_IO = preload("res://addons/pdb/core/pdb_io.gd")

const LOG_PREFIX = "[PDB]"

var plugin_reference
var current_pdb: PatternDatabaseFile
var current_path: String = ""
var _saver: ResourceFormatSaver

var _history_controller: PdbHistoryController
var _history_view: PdbHistoryView
var _history_btn: Button
var _table_view: PdbTableView
var _table_btn: Button
var _history_capture_timer: Timer
var _suspend_capture: bool = false
var _workspace_pattern_id: StringName = &""
var _suppress_workspace_reopen := false

var _loaded_mtime: int = 0

var is_dirty: bool = false:
	set(value):
		var changed = is_dirty != value
		is_dirty = value
		if changed:
			_log("Dirty state changed: %s" % value)
		_update_header_title()
		if value and not _suspend_capture and _history_controller and _history_controller.enabled:
			_schedule_history_capture()

@onready var label_title: Label = $VBox/Header/Margin/HBox/Logo
@onready var btn_file: MenuButton = $VBox/Header/Margin/HBox/BtnFile
@onready var nav_buttons: HBoxContainer = $VBox/Header/Margin/HBox/NavButtons
@onready var btn_data: Button = $VBox/Header/Margin/HBox/NavButtons/BtnData
@onready var btn_schema: Button = $VBox/Header/Margin/HBox/NavButtons/BtnSchema
@onready var btn_settings: Button = $VBox/Header/Margin/HBox/NavButtons/BtnSettings
@onready var views: TabContainer = $VBox/ContentArea/Views
@onready var save_confirm_dialog: ConfirmationDialog = $SaveConfirmationDialog

@onready var data_tree: Tree = $VBox/ContentArea/Views/DataView/Sidebar/Tree
@onready var btn_add_data: MenuButton = $VBox/ContentArea/Views/DataView/Sidebar/DataToolbar/BtnAddData
@onready var search_bar: LineEdit = $VBox/ContentArea/Views/DataView/Sidebar/DataToolbar/Search
@onready var workspace_panel: PanelContainer = $VBox/ContentArea/Views/DataView/Workspace

@onready var schema_list: ItemList = $VBox/ContentArea/Views/SchemaView/DefinitionList
@onready var code_preview: CodeEdit = $VBox/ContentArea/Views/SchemaView/CodePreview

@onready var status_label: Label = $VBox/Footer/Margin/HBox/Status
@onready var counts_label: Label = $VBox/Footer/Margin/HBox/Counts

var rename_dialog: ConfirmationDialog
var rename_input: LineEdit
var context_menu: PopupMenu
var export_dialog: ConfirmationDialog
var export_dir_input: LineEdit
var export_enum_class_input: LineEdit
var export_const_class_input: LineEdit

var validation_dialog: AcceptDialog
var validation_list: ItemList

var import_submenu: PopupMenu
var export_submenu: PopupMenu

var settings_dir_input: LineEdit
var settings_enum_input: LineEdit
var settings_const_input: LineEdit
var settings_model_input: LineEdit
var settings_data_input: LineEdit
var settings_json_input: LineEdit
var settings_tags_check: CheckBox
var settings_upper_check: CheckBox
var settings_hl_modified: ColorPickerButton
var settings_hl_new: ColorPickerButton
var settings_hl_flash: HSlider
var _loading_settings := false
var _pending_open_path: String = ""
var _pending_open_resource: PatternDatabaseFile = null

func _log(message: String, level: String = "INFO") -> void:
	if PdbLog.enabled:
		var timestamp = Time.get_datetime_string_from_system(false, true)
		print("%s [%s] %s: %s" % [LOG_PREFIX, timestamp, level, message])

func _log_error(message: String) -> void:
	_log(message, "ERROR")
	push_error("%s %s" % [LOG_PREFIX, message])

func _log_warning(message: String) -> void:
	_log(message, "WARN")
	push_warning("%s %s" % [LOG_PREFIX, message])

func set_saver(saver: ResourceFormatSaver) -> void:
	_saver = saver
	_log("Saver reference set: %s" % saver)

func _ready() -> void:
	_log("Main screen initializing...")

	if not _saver:
		_log("Creating fallback saver instance")
		_saver = PdbSaver.new()

	_setup_file_menu()

	for btn in nav_buttons.get_children():
		btn.pressed.connect(func(): _switch_view(btn))

	_setup_history()
	_setup_table()
	_finalize_nav()

	var _content_area := $VBox/ContentArea
	if _content_area:
		_content_area.clip_contents = true

	if label_title:
		label_title.clip_text = true
		label_title.custom_minimum_size = Vector2(96, 0)
		label_title.mouse_filter = Control.MOUSE_FILTER_PASS

	btn_add_data.get_popup().clear()
	btn_add_data.get_popup().add_item("Constant", 0)
	btn_add_data.get_popup().add_item("Enum", 1)
	btn_add_data.get_popup().add_separator()
	btn_add_data.get_popup().add_item("Model Definition", 2)
	btn_add_data.get_popup().add_item("Model Instance", 3)
	btn_add_data.get_popup().add_separator()
	btn_add_data.get_popup().add_item("Instance from Definition...", 4)
	btn_add_data.get_popup().id_pressed.connect(_on_add_data_item)

	data_tree.set_allow_rmb_select(true)
	data_tree.item_selected.connect(_on_data_item_selected)
	data_tree.item_mouse_selected.connect(_on_tree_item_mouse_selected)

	search_bar.text_changed.connect(func(txt): _refresh_data_tree(txt))

	if schema_list:
		schema_list.item_selected.connect(_on_schema_item_selected)

	_setup_extra_dialogs()
	_setup_settings_view()
	_setup_tooltips()
	_style_nav_tabs()
	_close_current_pdb()
	_switch_view($VBox/Header/Margin/HBox/NavButtons/BtnData)
	_refresh_settings_view()
	_update_status_bar()

	_install_horizontal_scroll()

	_log("Main screen ready")

func _install_horizontal_scroll() -> void:
	var vbox := $VBox
	if vbox == null or vbox.get_parent() != self:
		return
	var hscroll := ScrollContainer.new()
	hscroll.name = "PanelHScroll"
	hscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hscroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var idx := (event as InputEventMouseButton).button_index
			if idx == MOUSE_BUTTON_WHEEL_UP or idx == MOUSE_BUTTON_WHEEL_DOWN:
				hscroll.accept_event()
	)
	remove_child(vbox)
	add_child(hscroll)
	hscroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hscroll.add_child(vbox)
	vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	vbox.size_flags_vertical = SIZE_EXPAND_FILL

func _setup_file_menu() -> void:
	var popup = btn_file.get_popup()
	popup.clear()

	popup.add_item("New Database", 0)
	popup.add_item("Open Database...", 1)
	popup.add_item("Save", 2)
	popup.add_item("Save As...", 3)
	popup.add_item("Close", 4)
	popup.add_separator()

	import_submenu = PopupMenu.new()
	import_submenu.name = "ImportSubmenu"
	import_submenu.add_item("Import Enums from GDScript...", 100)
	import_submenu.add_item("Import Consts from GDScript...", 105)
	import_submenu.add_item("Import Definition from Script...", 101)
	import_submenu.add_item("Import from JSON...", 102)
	import_submenu.add_separator()
	import_submenu.add_item("Import Folder (batch)...", 103)
	import_submenu.id_pressed.connect(_on_import_option)
	popup.add_child(import_submenu)
	popup.add_submenu_item("Import", "ImportSubmenu", 104)

	export_submenu = PopupMenu.new()
	export_submenu.name = "ExportSubmenu"
	export_submenu.add_item("Export GDScript (Enums + Models)...", 200)
	export_submenu.add_item("Export Instances to .tres...", 201)
	export_submenu.add_item("Export Instances to JSON...", 202)
	export_submenu.add_item("Export Entire Database to JSON...", 203)
	export_submenu.add_separator()
	export_submenu.add_item("Export All to Configured Folder", 204)
	export_submenu.id_pressed.connect(_on_export_option)
	popup.add_child(export_submenu)
	popup.add_submenu_item("Export", "ExportSubmenu", 204)

	popup.add_separator()
	popup.add_item("Validate Database", 5)

	popup.id_pressed.connect(_on_file_menu_option)
	_update_file_menu_state()

func _update_file_menu_state() -> void:
	var popup := btn_file.get_popup()
	var has_db := current_pdb != null
	for id in [2, 3, 4, 5, 104, 204]:
		var idx := popup.get_item_index(id)
		if idx != -1:
			popup.set_item_disabled(idx, not has_db)

func _setup_extra_dialogs() -> void:
	rename_dialog = ConfirmationDialog.new()
	rename_dialog.title = "Rename Pattern"
	rename_input = LineEdit.new()
	rename_input.custom_minimum_size.x = 250
	var vbox = VBoxContainer.new()
	vbox.add_child(rename_input)
	rename_dialog.add_child(vbox)
	rename_dialog.confirmed.connect(_on_rename_confirmed)
	add_child(rename_dialog)

	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_on_context_menu_action)
	add_child(context_menu)

	export_dialog = ConfirmationDialog.new()
	export_dialog.title = "Export GDScript"
	export_dialog.size = Vector2i(500, 200)

	var export_content = VBoxContainer.new()
	export_content.custom_minimum_size = Vector2(450, 150)

	var dir_row = HBoxContainer.new()
	var dir_label = Label.new()
	dir_label.text = "Output Directory:"
	dir_label.custom_minimum_size.x = 120
	export_dir_input = LineEdit.new()
	export_dir_input.text = "res://data/generated"
	export_dir_input.size_flags_horizontal = SIZE_EXPAND_FILL
	dir_row.add_child(dir_label)
	dir_row.add_child(export_dir_input)
	export_content.add_child(dir_row)

	var enum_row = HBoxContainer.new()
	var enum_label = Label.new()
	enum_label.text = "Enum Class Name:"
	enum_label.custom_minimum_size.x = 120
	export_enum_class_input = LineEdit.new()
	export_enum_class_input.text = "enums"
	export_enum_class_input.size_flags_horizontal = SIZE_EXPAND_FILL
	enum_row.add_child(enum_label)
	enum_row.add_child(export_enum_class_input)
	export_content.add_child(enum_row)

	var const_row = HBoxContainer.new()
	var const_label = Label.new()
	const_label.text = "Const Class Name:"
	const_label.custom_minimum_size.x = 120
	export_const_class_input = LineEdit.new()
	export_const_class_input.text = "consts"
	export_const_class_input.size_flags_horizontal = SIZE_EXPAND_FILL
	const_row.add_child(const_label)
	const_row.add_child(export_const_class_input)
	export_content.add_child(const_row)

	export_dialog.add_child(export_content)
	export_dialog.confirmed.connect(_on_export_gdscript_confirmed)
	add_child(export_dialog)

	validation_dialog = AcceptDialog.new()
	validation_dialog.title = "Validation Results"
	validation_dialog.size = Vector2i(600, 400)

	var val_content = VBoxContainer.new()
	val_content.custom_minimum_size = Vector2(550, 350)

	validation_list = ItemList.new()
	validation_list.size_flags_vertical = SIZE_EXPAND_FILL
	validation_list.size_flags_horizontal = SIZE_EXPAND_FILL
	val_content.add_child(validation_list)

	validation_dialog.add_child(val_content)
	add_child(validation_dialog)

	save_confirm_dialog.confirmed.connect(_on_save_confirm_action)
	save_confirm_dialog.canceled.connect(_on_abort_open_action)
	save_confirm_dialog.add_button("Discard & Open", false, "pdb_discard_open")
	save_confirm_dialog.custom_action.connect(func(action):
		if action == "pdb_discard_open":
			save_confirm_dialog.hide()
			_on_cancel_open_action()
	)

	_log("Dialogs initialized")

func _on_file_menu_option(id: int) -> void:
	match id:
		0:
			_log("File -> New Database")
			var new_pdb = PatternDatabaseFile.new()
			new_pdb.ensure_uid()
			_set_active_pdb(new_pdb, "")
			_trigger_save_as()
		1:
			_log("File -> Open")
			_trigger_open_dialog()
		2:
			_log("File -> Save")
			_save_pdb()
		3:
			_log("File -> Save As")
			_trigger_save_as()
		4:
			_log("File -> Close")
			_close_current_pdb()
		5:
			_log("File -> Validate")
			_validate_database()

func _on_import_option(id: int) -> void:
	if not current_pdb:
		_log_warning("Cannot import: no database open")
		return

	match id:
		100:
			_log("Import -> Enums from GDScript")
			_import_enums_dialog()
		101:
			_log("Import -> Definition from Script")
			_import_definition_dialog()
		102:
			_log("Import -> From JSON")
			_import_json_dialog()
		105:
			_log("Import -> Consts from GDScript")
			_import_consts_dialog()
		103:
			_log("Import -> Folder (batch)")
			_import_folder_dialog()

func _on_export_option(id: int) -> void:
	if not current_pdb:
		_log_warning("Cannot export: no database open")
		return

	match id:
		200:
			_log("Export -> GDScript")
			export_dialog.popup_centered()
		201:
			_log("Export -> Instances to .tres")
			_export_tres_dialog()
		202:
			_log("Export -> Instances to JSON")
			_export_instances_json_dialog()
		203:
			_log("Export -> Entire Database to JSON")
			_export_full_json_dialog()
		204:
			_log("Export -> All to configured folder")
			_export_all_to_folder()

func _open_fs_dialog(mode: int, filters: Array, save_name: String, on_selected: Callable, default_dir: String = "") -> void:
	if PdbWebIo.is_web():
		_web_fs_dialog(mode, filters, save_name, on_selected)
		return
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = mode
	for f in filters:
		fd.add_filter(f[0], f[1])
	if save_name != "":
		fd.current_file = save_name
	if default_dir != "":
		var abs := ProjectSettings.globalize_path(default_dir)
		DirAccess.make_dir_recursive_absolute(abs)
		fd.current_dir = abs
	var handler := func(path):
		fd.hide()
		on_selected.call(path)
		fd.queue_free()
	fd.file_selected.connect(handler)
	fd.dir_selected.connect(handler)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))

func _web_fs_dialog(mode: int, filters: Array, save_name: String, on_selected: Callable) -> void:
	if mode == FileDialog.FILE_MODE_OPEN_FILE:
		PdbWebIo.begin_upload(PdbWebIo.filters_to_accept(filters), func(fname: String, bytes: PackedByteArray):
			if bytes.is_empty():
				return
			var tmp := "user://_pdb_import_" + fname.get_file()
			var f := FileAccess.open(tmp, FileAccess.WRITE)
			if not f:
				return
			f.store_buffer(bytes)
			f.close()
			on_selected.call(tmp)
		)
	elif mode == FileDialog.FILE_MODE_SAVE_FILE:
		var out_name := save_name if save_name != "" else "export.dat"
		var tmp := "user://_pdb_export_" + out_name
		on_selected.call(tmp)
		if FileAccess.file_exists(tmp):
			var f := FileAccess.open(tmp, FileAccess.READ)
			if f:
				var bytes := f.get_buffer(f.get_length())
				f.close()
				var mime := "application/json" if out_name.get_extension() == "json" else "application/octet-stream"
				PdbWebIo.download_bytes(bytes, out_name, mime)
	else:
		_web_note("Not available in the browser", "Folder import and multi-file .tres/.gd export need the desktop app — the browser can't hand a folder back. JSON and .pdb import/export work here.")

func _import_enums_dialog() -> void:
	_open_fs_dialog(FileDialog.FILE_MODE_OPEN_FILE, [["*.gd", "GDScript Files"]], "", func(path):
		_seal_history_before_import()
		var result = PdbImporter.import_enums_from_gdscript(path, current_pdb)
		_show_import_result("Import Enums", result)
		if result.success:
			_refresh_data_tree()
			_refresh_schema_list()
			_commit_history_after_import("Import enums")
	)

func _import_definition_dialog() -> void:
	_open_fs_dialog(FileDialog.FILE_MODE_OPEN_FILE, [["*.gd", "GDScript Files"]], "", func(path):
		_seal_history_before_import()
		var result = PdbImporter.import_definition_from_script(path, current_pdb)
		if result.success:
			_log("Imported definition: %s" % result.definition_id)
			_refresh_data_tree()
			_refresh_schema_list()
			_commit_history_after_import("Import definition")
		else:
			_log_error("Import failed: %s" % str(result.errors))
			_show_import_result("Import Definition", result)
	)

func _import_json_dialog() -> void:
	_open_fs_dialog(FileDialog.FILE_MODE_OPEN_FILE, [["*.json", "JSON Files"]], "", func(path):
		_seal_history_before_import()
		var result = PdbImporter.import_from_json(path, current_pdb)
		_show_import_result("Import JSON", result)
		if result.success:
			_refresh_data_tree()
			_refresh_schema_list()
			_commit_history_after_import("Import JSON")
	)

func _import_consts_dialog() -> void:
	_open_fs_dialog(FileDialog.FILE_MODE_OPEN_FILE, [["*.gd", "GDScript Files"]], "", func(path):
		_seal_history_before_import()
		var result = PdbImporter.import_consts_from_gdscript(path, current_pdb)
		_show_import_result("Import Consts", result)
		if result.success:
			_refresh_data_tree()
			_refresh_schema_list()
			_commit_history_after_import("Import consts")
	)

func _import_folder_dialog() -> void:
	_open_fs_dialog(FileDialog.FILE_MODE_OPEN_DIR, [], "", func(path):
		_seal_history_before_import()
		var result = PdbImporter.import_folder(path, current_pdb, true)
		_show_import_result("Import Folder", result)
		if result.imported.values().any(func(n): return n > 0):
			_refresh_data_tree()
			_refresh_schema_list()
			_commit_history_after_import("Import folder")
	)

func _show_import_result(title: String, result: Dictionary) -> void:
	validation_list.clear()
	validation_dialog.title = title

	if result.has("files"):
		validation_list.add_item("Scanned %d file(s)" % result.files)

	if result.has("imported"):
		if result.imported is Dictionary:
			for key in result.imported:
				if result.imported[key] > 0:
					validation_list.add_item("✓ Imported %d %s" % [result.imported[key], key])
		elif result.imported is Array:
			for item in result.imported:
				validation_list.add_item("✓ Imported: %s" % item)

	if result.has("skipped"):
		for item in result.skipped:
			validation_list.add_item("⊘ Skipped: %s" % item)

	if result.has("errors"):
		for err in result.errors:
			validation_list.add_item("✗ Error: %s" % err)

	if validation_list.item_count == 0:
		validation_list.add_item("No changes")

	validation_dialog.popup_centered()

func _seal_history_before_import() -> void:
	# Commit the current (pre-import) state as its own history node so a later
	# "restore before import" has a real point to return to. Without this the
	# import folds into the head commit and cannot be undone through history.
	_flush_history_capture()

func _commit_history_after_import(summary: String) -> void:
	# Commit the post-import state synchronously (not via the debounce) so the
	# import is always a distinct, restorable commit.
	is_dirty = true
	if _history_controller and _history_controller.enabled:
		if _history_capture_timer:
			_history_capture_timer.stop()
		var h := _history_controller.capture()
		if h != "" and _history_view:
			_history_view.refresh()

func _export_root() -> String:
	var md: Dictionary = current_pdb.meta_data if current_pdb else {}
	var d := str(md.get("export_dir", "res://data/generated")).strip_edges()
	return d if d != "" else "res://data/generated"

func _export_subdir(key: String, fallback: String) -> String:
	var md: Dictionary = current_pdb.meta_data if current_pdb else {}
	var d := str(md.get(key, fallback)).strip_edges()
	return d if d != "" else fallback

func _export_tres_dialog() -> void:
	if PdbWebIo.is_web():
		_web_note("Not available in the browser", "Multi-file .tres export writes into folders, which the browser can't hand back. Use the desktop app, or export JSON here.")
		return
	var data_dir := _export_root().path_join(_export_subdir("data_subdir", "data"))
	var model_dir := _export_root().path_join(_export_subdir("model_subdir", "model"))
	var result = PdbExporter.export_instances_to_tres(current_pdb, data_dir, model_dir)
	_show_export_result("Export .tres", result)
	_editor_rescan()

func _export_instances_json_dialog() -> void:
	var json_dir := _export_root().path_join(_export_subdir("json_subdir", "json"))
	_open_fs_dialog(FileDialog.FILE_MODE_SAVE_FILE, [["*.json", "JSON Files"]], "instances.json", func(path):
		var result = PdbExporter.export_instances_to_json(current_pdb, path)
		_show_export_result("Export Instances JSON", result)
	, json_dir)

func _export_full_json_dialog() -> void:
	var json_dir := _export_root().path_join(_export_subdir("json_subdir", "json"))
	_open_fs_dialog(FileDialog.FILE_MODE_SAVE_FILE, [["*.json", "JSON Files"]], "database.json", func(path):
		var result = PdbExporter.export_all_to_json(current_pdb, path)
		_show_export_result("Export Full Database", result)
	, json_dir)

func _export_all_to_folder() -> void:
	if not current_pdb:
		return
	if PdbWebIo.is_web():
		_web_note("Not available in the browser", "A full export writes several files into folders, which the browser can't hand back. Use the desktop app, or export JSON here.")
		return
	var root := _export_root()
	var model_subdir := _export_subdir("model_subdir", "model")
	var data_dir := root.path_join(_export_subdir("data_subdir", "data"))
	var json_dir := root.path_join(_export_subdir("json_subdir", "json"))
	var enum_class := _export_subdir("enum_class", "enums")
	var const_class := _export_subdir("const_class", "consts")

	var combined := {"files": [], "errors": [], "skipped": [], "notes": []}
	_merge_export(combined, PdbCodegen.export_all(current_pdb, root, enum_class, const_class, model_subdir))
	_merge_export(combined, PdbExporter.export_instances_to_tres(current_pdb, data_dir, root.path_join(model_subdir)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(json_dir))
	_merge_export(combined, PdbExporter.export_all_to_json(current_pdb, json_dir.path_join("database.json")))

	_show_export_result("Export All", combined)
	_editor_rescan()

func _merge_export(into: Dictionary, part: Dictionary) -> void:
	for key in ["files", "errors", "skipped", "notes"]:
		if part.has(key) and part[key] is Array:
			into[key].append_array(part[key])

func _show_export_result(title: String, result: Dictionary) -> void:
	validation_list.clear()
	validation_dialog.title = title

	if result.has("files"):
		for f in result.files:
			validation_list.add_item("✓ Written: %s" % f)

	if result.has("skipped"):
		for item in result.skipped:
			validation_list.add_item("⊘ Skipped: %s" % item)

	if result.has("errors"):
		for err in result.errors:
			validation_list.add_item("✗ Error: %s" % err)

	if result.has("notes"):
		for note in result.notes:
			validation_list.add_item("ⓘ %s" % note)

	if validation_list.item_count == 0:
		validation_list.add_item("No files written")

	validation_dialog.popup_centered()

func _on_export_gdscript_confirmed() -> void:
	if not current_pdb:
		return
	if PdbWebIo.is_web():
		_web_note("Not available in the browser", "GDScript codegen writes several files into a folder, which the browser can't hand back. Use the desktop app for codegen, or export JSON here and generate from that.")
		return

	var output_dir = export_dir_input.text.strip_edges()
	var enum_class = export_enum_class_input.text.strip_edges()
	var const_class = export_const_class_input.text.strip_edges()

	if output_dir.is_empty():
		output_dir = "res://data/generated"
	if enum_class.is_empty():
		enum_class = "enums"
	if const_class.is_empty():
		const_class = "consts"

	_log("Exporting GDScript to: %s" % output_dir)

	var result = PdbCodegen.export_all(current_pdb, output_dir, enum_class, const_class, _export_subdir("model_subdir", "model"))
	_show_export_result("Export GDScript", result)

	_editor_rescan()

func _validate_database() -> void:
	if not current_pdb:
		_log_warning("Cannot validate: no database open")
		return

	_log("Running database validation...")
	var issues = PdbValidator.validate_database(current_pdb)

	validation_list.clear()
	validation_dialog.title = "Validation Results"

	if issues.is_empty():
		validation_list.add_item("✓ No issues found")
	else:
		for issue in issues:
			var icon = "ℹ" if issue.severity == PdbValidator.Severity.INFO else ("⚠" if issue.severity == PdbValidator.Severity.WARNING else "✗")
			validation_list.add_item("%s %s" % [icon, issue.to_string()])

	validation_dialog.popup_centered()

func _validate_single_pattern(pattern: Resource) -> void:
	if not pattern is PdbModelInstance:
		_log("Validation only supported for instances")
		return

	var issues = PdbValidator.validate_instance(pattern as PdbModelInstance, current_pdb)

	validation_list.clear()
	validation_dialog.title = "Validate: %s" % pattern.id

	if issues.is_empty():
		validation_list.add_item("✓ No issues found")
	else:
		for issue in issues:
			var icon = "ℹ" if issue.severity == PdbValidator.Severity.INFO else ("⚠" if issue.severity == PdbValidator.Severity.WARNING else "✗")
			validation_list.add_item("%s %s" % [icon, issue.to_string()])

	validation_dialog.popup_centered()

func request_open_resource(pdb: PatternDatabaseFile) -> void:
	if pdb == null:
		return

	if pdb == current_pdb:
		_log("Already open, skipping")
		return

	if is_dirty:
		_log("Unsaved changes detected, prompting user")
		_pending_open_resource = pdb
		_pending_open_path = ""
		save_confirm_dialog.dialog_text = "You have unsaved changes to %s.\nSave before opening a new file?" % current_path.get_file()
		save_confirm_dialog.popup_centered()
	else:
		_set_active_pdb(pdb, pdb.resource_path)

func request_open_pdb(path: String) -> void:
	_log("Request to open: %s" % path)

	if current_path == path:
		_log("Already open, skipping")
		return

	if is_dirty:
		_log("Unsaved changes detected, prompting user")
		_pending_open_path = path
		_pending_open_resource = null
		save_confirm_dialog.dialog_text = "You have unsaved changes to %s.\nSave before opening a new file?" % current_path.get_file()
		save_confirm_dialog.popup_centered()
	else:
		_load_pdb_from_disk(path)

func _load_pdb_from_disk(path: String) -> void:
	_log("Loading PDB from disk: %s" % path)

	if not FileAccess.file_exists(path):
		_log_error("File not found: %s" % path)
		return

	var load_start = Time.get_ticks_msec()
	var res: Resource

	res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)

	if not res:
		_log("ResourceLoader failed, trying direct loader...")
		var loader = PdbLoader.new()
		var load_result = loader._load(path, path, false, ResourceLoader.CACHE_MODE_REUSE)
		if load_result is PatternDatabaseFile:
			res = load_result
		elif load_result is int:
			_log_error("Load failed with error code: %d" % load_result)
			return

	var load_time = Time.get_ticks_msec() - load_start

	if res is PatternDatabaseFile:
		_log("Loaded PatternDatabaseFile in %dms" % load_time)
		_log("  Version: %d" % res.version)
		_log("  Patterns: %d" % res.patterns.size())
		_set_active_pdb(res, path)
	else:
		_log_error("Invalid resource type at: %s (got %s)" % [path, res.get_class() if res else "null"])

func _set_active_pdb(pdb: PatternDatabaseFile, path: String) -> void:
	_log("Setting active PDB: %s" % path)

	current_pdb = pdb
	current_path = path
	is_dirty = false
	_loaded_mtime = _file_mtime(path)

	var enum_count = 0
	var const_count = 0
	var def_count = 0
	var inst_count = 0

	for key in pdb.patterns:
		var p = pdb.patterns[key]
		if p is PdbEnum:
			enum_count += 1
		elif p is PdbConst:
			const_count += 1
		elif p is PdbModelDefinition:
			def_count += 1
		elif p is PdbModelInstance:
			inst_count += 1
			p.set_database(pdb)

	_log("Pattern breakdown: %d enums, %d consts, %d defs, %d instances" % [enum_count, const_count, def_count, inst_count])

	pdb_opened.emit(pdb)
	_update_header_title()
	_refresh_data_tree()
	_refresh_schema_list()
	_refresh_settings_view()
	if enum_count + const_count + def_count + inst_count == 0:
		_show_workspace_message("Empty database", "Use the + Add button in the sidebar to create your first pattern.", false)
	else:
		_show_workspace_message("Select an item", "Choose an enum, constant, definition, or instance from the sidebar to edit it.", false)

	btn_add_data.disabled = false
	_set_db_dependent_tabs_enabled(true)
	_update_file_menu_state()
	_bind_history()
	if _table_view:
		_table_view.setup(pdb)
	_check_recovery_on_open()
	if pdb.incompatible:
		_warn_incompatible()
	_log("PDB activated successfully")

func _save_pdb() -> void:
	_log("Save requested")

	if not current_pdb:
		_log_warning("No PDB loaded, cannot save")
		return

	if current_pdb.incompatible:
		_log_warning("Save blocked: database format is newer than this addon supports.")
		_warn_incompatible()
		return

	_flush_history_capture()

	if PdbWebIo.is_web():
		_web_download_pdb()
		return

	if current_path.is_empty() or current_path.begins_with("uid://"):
		_log("No valid path, triggering Save As...")
		_trigger_save_as()
		return

	if _loaded_mtime > 0 and _file_mtime(current_path) > _loaded_mtime:
		_confirm_overwrite_external_change()
		return

	_write_current_pdb()

func _confirm_overwrite_external_change() -> void:
	var d := ConfirmationDialog.new()
	d.title = "File changed on disk"
	d.dialog_text = "This .pdb was modified outside PatternDB since you opened it.\n\nSaving now will overwrite those external changes."
	d.ok_button_text = "Overwrite"
	add_child(d)
	d.popup_centered()
	d.confirmed.connect(func():
		d.queue_free()
		_write_current_pdb()
	)
	d.canceled.connect(d.queue_free)

func _write_current_pdb() -> void:
	_log("Saving to: %s" % current_path)
	_log("  PDB class: %s" % current_pdb.get_class())
	_log("  PDB patterns: %d" % current_pdb.patterns.size())

	var save_start = Time.get_ticks_msec()
	var err: Error

	current_pdb.resource_path = current_path
	err = ResourceSaver.save(current_pdb, current_path)

	if err != OK:
		_log("ResourceSaver failed (error %d), trying direct saver..." % err)
		if _saver:
			err = _saver._save(current_pdb, current_path, 0)
		else:
			_log_error("No saver available for fallback")

	var save_time = Time.get_ticks_msec() - save_start

	if err == OK:
		_log("Save successful in %dms" % save_time)
		is_dirty = false
		_loaded_mtime = _file_mtime(current_path)
		_update_header_title()
		if _history_controller:
			if _history_controller.db_path != current_path:
				_bind_history()
			_history_controller.persist()

		_editor_rescan()
	else:
		_log_error("Save failed with error code: %d" % err)

func _file_mtime(path: String) -> int:
	if path.is_empty() or path.begins_with("uid://") or not FileAccess.file_exists(path):
		return 0
	return int(FileAccess.get_modified_time(path))

func _web_download_pdb(override_name := "") -> void:
	if not current_pdb:
		return
	_flush_history_capture()
	var tmp := "user://_pdb_save.pdb"
	var err: Error = _saver._save(current_pdb, tmp, 0) if _saver else ResourceSaver.save(current_pdb, tmp)
	if err != OK:
		_log_error("Web save failed to serialize (%d)" % err)
		_web_note("Save failed", "Could not serialize the database for download (error %d)." % err)
		return
	var f := FileAccess.open(tmp, FileAccess.READ)
	if not f:
		_log_error("Web save could not read serialized data")
		return
	var bytes := f.get_buffer(f.get_length())
	f.close()
	if bytes.is_empty():
		_log_error("Web save produced empty output")
		_web_note("Save failed", "The serialized database was empty; nothing to download.")
		return
	var out_name := override_name.strip_edges()
	if out_name == "":
		out_name = current_path.get_file() if current_path != "" else "database.pdb"
	if not out_name.to_lower().ends_with(".pdb"):
		out_name += ".pdb"
	_log("Web download: %s (%d bytes)" % [out_name, bytes.size()])
	PdbWebIo.download_bytes(bytes, out_name, "application/octet-stream")
	is_dirty = false
	_update_header_title()

func _web_save_as_prompt() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Download database as…"
	var vb := VBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "File name:"
	vb.add_child(lbl)
	var name_edit := LineEdit.new()
	name_edit.text = current_path.get_file() if current_path != "" else "database.pdb"
	name_edit.custom_minimum_size.x = 320
	vb.add_child(name_edit)
	dlg.add_child(vb)
	dlg.ok_button_text = "Download"
	dlg.confirmed.connect(func():
		_web_download_pdb(name_edit.text)
		dlg.queue_free()
	)
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()
	name_edit.grab_focus()
	name_edit.select_all()

func _web_note(title: String, body: String) -> void:
	var d := AcceptDialog.new()
	d.title = title
	d.dialog_text = body
	add_child(d)
	d.popup_centered()
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)

func _pick_pdb_file(save_mode: bool, default_name: String, on_selected: Callable) -> void:
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_RESOURCES if Engine.is_editor_hint() else FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save_mode else FileDialog.FILE_MODE_OPEN_FILE
	fd.add_filter("*.pdb", "Pattern Database")
	if Engine.is_editor_hint():
		fd.current_dir = "res://"
	if default_name != "":
		fd.current_file = default_name
	fd.file_selected.connect(func(path):
		on_selected.call(path)
		fd.queue_free()
	)
	fd.canceled.connect(func(): fd.queue_free())
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))

func _trigger_save_as() -> void:
	_log("Opening Save As dialog")
	if PdbWebIo.is_web():
		_web_save_as_prompt()
		return
	_pick_pdb_file(true, "", func(path):
		_log("Save As path selected: %s" % path)
		current_path = path
		current_pdb.resource_path = path
		_loaded_mtime = 0
		_save_pdb()
	)

func _close_current_pdb() -> void:
	_log("Closing current PDB")

	current_pdb = null
	current_path = ""
	is_dirty = false

	btn_add_data.disabled = true
	data_tree.clear()
	if schema_list:
		schema_list.clear()
	if code_preview:
		code_preview.text = ""
	_clear_workspace()
	_show_workspace_message("No database open", "Create a new database or open an existing .pdb file.", true)
	_update_header_title()
	_set_db_dependent_tabs_enabled(false)
	_update_file_menu_state()
	if btn_data and not btn_data.button_pressed:
		_switch_view(btn_data)
	if _table_view:
		_table_view.setup(null)
	pdb_closed.emit()

	_log("PDB closed")

func _on_add_data_item(id: int) -> void:
	if not current_pdb:
		_log_warning("Cannot add data: no PDB loaded")
		return

	match id:
		0:
			_log("Adding new Constant")
			_prompt_new_data(PDB_CONST, "Const")
		1:
			_log("Adding new Enum")
			_prompt_new_data(PDB_ENUM, "Enum")
		2:
			_log("Adding new Model Definition")
			_prompt_new_data(PDB_MODEL_DEFINITION, "Model")
		3:
			_log("Adding new Model Instance")
			_prompt_new_data(PDB_MODEL_INSTANCE, "Instance")
		4:
			_log("Creating instance from definition")
			_show_create_instance_dialog()

func _show_create_instance_dialog() -> void:
	var definitions = current_pdb.get_all_definitions()
	if definitions.is_empty():
		_log_warning("No definitions to create instances from")
		return

	var dialog = ConfirmationDialog.new()
	dialog.title = "Create Instance from Definition"
	dialog.size = Vector2i(400, 150)

	var content = VBoxContainer.new()
	content.custom_minimum_size = Vector2(350, 100)

	var def_row = HBoxContainer.new()
	var def_label = Label.new()
	def_label.text = "Definition:"
	def_label.custom_minimum_size.x = 80
	var def_picker = OptionButton.new()
	def_picker.size_flags_horizontal = SIZE_EXPAND_FILL
	for d in definitions:
		def_picker.add_item(str(d.id))
	def_row.add_child(def_label)
	def_row.add_child(def_picker)
	content.add_child(def_row)

	var id_row = HBoxContainer.new()
	var id_label = Label.new()
	id_label.text = "Instance ID:"
	id_label.custom_minimum_size.x = 80
	var id_input = LineEdit.new()
	id_input.size_flags_horizontal = SIZE_EXPAND_FILL
	id_input.placeholder_text = "NewInstance"
	id_row.add_child(id_label)
	id_row.add_child(id_input)
	content.add_child(id_row)

	dialog.add_child(content)

	dialog.confirmed.connect(func():
		var def_id = def_picker.get_item_text(def_picker.selected)
		var inst_id = id_input.text.strip_edges()
		if inst_id.is_empty():
			inst_id = "%s_%d" % [def_id, randi() % 1000]
		_create_instance_from_definition(def_id, inst_id)
		dialog.queue_free()
	)
	dialog.canceled.connect(func(): dialog.queue_free())

	add_child(dialog)
	dialog.popup_centered()

func _create_instance_from_definition(def_id: StringName, inst_id: StringName) -> void:
	if current_pdb.has_pattern(inst_id):
		_log_error("Instance ID already exists: %s" % inst_id)
		return

	var definition = current_pdb.get_pattern(def_id) as PdbModelDefinition
	if not definition:
		_log_error("Definition not found: %s" % def_id)
		return

	var instance = PdbModelInstance.new()
	instance.id = inst_id
	instance.definition_id = def_id
	instance.set_database(current_pdb)
	instance._initialize_from_definition()

	current_pdb.add_pattern(instance)
	is_dirty = true

	_log("Created instance: %s (from %s)" % [inst_id, def_id])

	_refresh_data_tree()
	_select_data_id(inst_id)

func _prompt_new_data(script_type: Script, type_name: String) -> void:
	var new_id = "New%s_%d" % [type_name, randi() % 1000]
	_log("Creating pattern with ID: %s" % new_id)

	var new_pattern = script_type.new()
	new_pattern.id = new_id

	if new_pattern is PdbModelInstance:
		new_pattern.set_database(current_pdb)

	current_pdb.add_pattern(new_pattern)

	is_dirty = true
	_log("Pattern added, refreshing UI")
	_refresh_data_tree()
	_refresh_schema_list()
	_select_data_id(new_id)

func _refresh_data_tree(filter: String = "") -> void:
	_log("Refreshing data tree (filter: '%s')" % filter)

	data_tree.clear()
	var root = data_tree.create_item()
	root.set_text(0, "Root")

	if not current_pdb:
		_log("No PDB loaded, tree empty")
		return

	var grouped: Dictionary = {
		"Enums": [],
		"Constants": [],
		"Definitions": [],
		"Instances": []
	}

	var filtered_count = 0
	var total_count = current_pdb.patterns.size()

	for key in current_pdb.patterns:
		var pattern = current_pdb.patterns[key]
		if filter != "" and not str(key).to_lower().contains(filter.to_lower()):
			continue

		filtered_count += 1

		if pattern is PdbEnum:
			grouped["Enums"].append(pattern)
		elif pattern is PdbConst:
			grouped["Constants"].append(pattern)
		elif pattern is PdbModelDefinition:
			grouped["Definitions"].append(pattern)
		elif pattern is PdbModelInstance:
			grouped["Instances"].append(pattern)

	_log("Displaying %d/%d patterns" % [filtered_count, total_count])

	for category in ["Enums", "Constants", "Definitions", "Instances"]:
		var items = grouped[category]
		if items.is_empty():
			continue

		var category_item = data_tree.create_item(root)
		category_item.set_text(0, "%s (%d)" % [category, items.size()])
		category_item.set_selectable(0, false)

		if _editor_icons_available():
			var icon_name = "Folder"
			match category:
				"Enums": icon_name = "Enum"
				"Constants": icon_name = "Dictionary"
				"Definitions": icon_name = "Script"
				"Instances": icon_name = "Object"
			category_item.set_icon(0, get_theme_icon(icon_name, "EditorIcons"))

		if category == "Instances":
			_build_instance_subtree(category_item, items)
		else:
			items.sort_custom(func(a, b): return str(a.id) < str(b.id))
			for pattern in items:
				_create_pattern_row(category_item, pattern)

	var tag_counts: Dictionary = {}
	for key in current_pdb.patterns:
		var p = current_pdb.patterns[key]
		if not p is PdbPattern:
			continue
		for raw in p.tags:
			var tname := str(raw)
			if tname == "":
				continue
			if filter != "" and not tname.to_lower().contains(filter.to_lower()):
				continue
			tag_counts[tname] = int(tag_counts.get(tname, 0)) + 1
	if not tag_counts.is_empty():
		var tag_root = data_tree.create_item(root)
		tag_root.set_text(0, "Tags (%d)" % tag_counts.size())
		tag_root.set_selectable(0, false)
		if _editor_icons_available():
			for cand in ["Bookmark", "AssetLib", "Filter", "Search"]:
				if has_theme_icon(cand, "EditorIcons"):
					tag_root.set_icon(0, get_theme_icon(cand, "EditorIcons"))
					break
		var tag_names := tag_counts.keys()
		tag_names.sort()
		for tname in tag_names:
			var titem = data_tree.create_item(tag_root)
			titem.set_text(0, "%s (%d)" % [tname, tag_counts[tname]])
			titem.set_metadata(0, {"__pdb_tag": tname})

	_log("Data tree refresh complete")
	_update_status_bar()

func _create_pattern_row(parent: TreeItem, pattern) -> TreeItem:
	var item = data_tree.create_item(parent)
	item.set_text(0, str(pattern.id))
	item.set_metadata(0, pattern)
	var thumb: Texture2D = null
	if pattern is PdbModelInstance:
		thumb = _instance_thumbnail(pattern as PdbModelInstance)
	if thumb != null:
		item.set_icon(0, thumb)
		item.set_icon_max_width(0, 24)
	else:
		var icon_name = "Object"
		if pattern is PdbConst:
			icon_name = "Dictionary"
		elif pattern is PdbEnum:
			icon_name = "Enum"
		elif pattern is PdbModelDefinition:
			icon_name = "Script"
		elif pattern is PdbModelInstance:
			icon_name = "Instance" if (pattern as PdbModelInstance).definition_id != &"" else "Object"
		if has_theme_icon(icon_name, "EditorIcons"):
			item.set_icon(0, get_theme_icon(icon_name, "EditorIcons"))
	return item

func _build_instance_subtree(parent: TreeItem, instances: Array) -> void:
	var by_def: Dictionary = {}
	for inst in instances:
		var did := str((inst as PdbModelInstance).definition_id)
		if did == "":
			did = "(no definition)"
		if not by_def.has(did):
			by_def[did] = []
		by_def[did].append(inst)

	var def_ids := by_def.keys()
	def_ids.sort()
	for did in def_ids:
		var did_str := str(did)
		var members: Array = by_def[did]
		members.sort_custom(func(a, b): return str(a.id) < str(b.id))
		var label := did_str if did_str == "(no definition)" else _pluralize(did_str)
		var sub := data_tree.create_item(parent)
		sub.set_text(0, "%s (%d)" % [label, members.size()])
		sub.set_selectable(0, false)
		if Engine.is_editor_hint():
			var icon := _definition_icon(did_str)
			if icon != null:
				sub.set_icon(0, icon)
		for inst in members:
			_create_pattern_row(sub, inst)

func _pluralize(word: String) -> String:
	if word == "":
		return word
	var lower := word.to_lower()
	var vowels := "aeiou"
	if lower.ends_with("y") and word.length() >= 2 and not vowels.contains(lower[lower.length() - 2]):
		return word.substr(0, word.length() - 1) + "ies"
	if lower.ends_with("s") or lower.ends_with("x") or lower.ends_with("z") or lower.ends_with("ch") or lower.ends_with("sh"):
		return word + "es"
	return word + "s"

func _editor_icons_available() -> bool:
	return has_theme_icon("Object", "EditorIcons")

func _definition_icon(def_id: String) -> Texture2D:
	if not _editor_icons_available() or current_pdb == null:
		return null
	var def := current_pdb.get_pattern(def_id) as PdbModelDefinition
	if def != null and def.icon_name != "" and has_theme_icon(def.icon_name, "EditorIcons"):
		return get_theme_icon(def.icon_name, "EditorIcons")
	if has_theme_icon("Instance", "EditorIcons"):
		return get_theme_icon("Instance", "EditorIcons")
	return null

func _instance_thumbnail(instance: PdbModelInstance) -> Texture2D:
	if instance == null or current_pdb == null:
		return null
	var def := current_pdb.get_pattern(instance.definition_id) as PdbModelDefinition
	if def == null:
		return null
	for field in def.fields:
		var val: Variant = instance.get_value(field.field_name)
		if val is Texture2D:
			return val as Texture2D
	return null

func _refresh_schema_list() -> void:
	_log("Refreshing schema list")

	if not schema_list:
		_log_warning("Schema list not found")
		return

	schema_list.clear()

	if not current_pdb:
		_log("No PDB loaded, schema list empty")
		return

	var enums: Array = []
	var consts: Array = []
	var definitions: Array = []

	for key in current_pdb.patterns:
		var pattern = current_pdb.patterns[key]
		if pattern is PdbEnum:
			enums.append(pattern)
		elif pattern is PdbConst:
			consts.append(pattern)
		elif pattern is PdbModelDefinition:
			definitions.append(pattern)

	enums.sort_custom(func(a, b): return str(a.id) < str(b.id))
	consts.sort_custom(func(a, b): return str(a.id) < str(b.id))
	definitions.sort_custom(func(a, b): return str(a.id) < str(b.id))

	for pdb_enum in enums:
		var idx = schema_list.add_item("enum %s" % pdb_enum.id)
		schema_list.set_item_metadata(idx, {"type": "enum", "pattern": pdb_enum})

	for pdb_const in consts:
		var idx = schema_list.add_item("const %s" % pdb_const.id)
		schema_list.set_item_metadata(idx, {"type": "const", "pattern": pdb_const})

	for definition in definitions:
		var idx = schema_list.add_item("class %s" % definition.id)
		schema_list.set_item_metadata(idx, {"type": "definition", "pattern": definition})

	_log("Schema list: %d enums, %d consts, %d definitions" % [enums.size(), consts.size(), definitions.size()])

func _on_schema_item_selected(index: int) -> void:
	if not code_preview:
		return

	var meta = schema_list.get_item_metadata(index)
	if not meta:
		return

	var pattern = meta.pattern
	var type = meta.type

	_log("Schema item selected: %s (%s)" % [pattern.id, type])

	match type:
		"enum":
			var lines = PdbCodegen._generate_enum_block(pattern)
			code_preview.text = "\n".join(lines)
		"const":
			var lines = PdbCodegen._generate_const_block(pattern)
			code_preview.text = "\n".join(lines)
		"definition":
			code_preview.text = PdbCodegen.generate_model_file(pattern, export_enum_class_input.text if export_enum_class_input else "enums", current_pdb)

func _on_data_item_selected() -> void:
	var item = data_tree.get_selected()
	if not item:
		return
	if _suppress_workspace_reopen:
		return

	var meta = item.get_metadata(0)
	if meta is Dictionary and meta.has("__pdb_tag"):
		_open_tag_in_workspace(str(meta["__pdb_tag"]))
		return
	if meta:
		_log("Data item selected: %s" % meta.id)
		_open_pattern_in_workspace(meta)

func _on_tree_item_mouse_selected(pos: Vector2, button_index: int) -> void:
	if button_index != MOUSE_BUTTON_RIGHT:
		return
	var item = data_tree.get_item_at_position(pos)
	var meta = item.get_metadata(0) if item else null
	if not (item and meta) or meta is Dictionary:
		return
	item.select(0)
	var pattern = meta

	context_menu.clear()
	context_menu.add_item("Rename", 0)
	context_menu.add_item("Duplicate", 1)
	context_menu.add_item("Validate", 2)
	if pattern is PdbModelDefinition:
		context_menu.add_separator()
		context_menu.add_item("Create Instance", 3)
	context_menu.add_separator()
	context_menu.add_item("Delete", 4)

	context_menu.reset_size()
	context_menu.position = get_screen_position() + get_local_mouse_position()
	context_menu.popup()

func _on_context_menu_action(id: int) -> void:
	var item = data_tree.get_selected()
	if not item:
		return
	var pattern = item.get_metadata(0)
	if not pattern:
		return

	match id:
		0:
			_log("Context: Rename %s" % pattern.id)
			rename_input.text = pattern.id
			rename_dialog.popup_centered()
			rename_input.grab_focus()
		1:
			_log("Context: Duplicate %s" % pattern.id)
			_duplicate_pattern(pattern)
		2:
			_log("Context: Validate %s" % pattern.id)
			_validate_single_pattern(pattern)
		3:
			if pattern is PdbModelDefinition:
				_log("Context: Create instance from %s" % pattern.id)
				var inst_id = "%s_%d" % [pattern.id, randi() % 1000]
				_create_instance_from_definition(pattern.id, inst_id)
		4:
			_log("Context: Delete %s" % pattern.id)
			_perform_delete_with_check(pattern)

func _perform_delete_with_check(pattern: Resource) -> void:
	var check = PdbValidator.can_delete_pattern(pattern.id, current_pdb)

	if check.can_delete:
		_perform_delete(pattern)
	else:
		var refs_text = ""
		for ref in check.references:
			refs_text += "\n  - %s (%s)" % [ref.pattern_id, ref.reference_type]

		var confirm = ConfirmationDialog.new()
		confirm.title = "Delete Pattern"
		confirm.dialog_text = "Pattern '%s' is referenced by:%s\n\nDelete anyway?" % [pattern.id, refs_text]
		confirm.confirmed.connect(func():
			_perform_delete(pattern)
			confirm.queue_free()
		)
		confirm.canceled.connect(func(): confirm.queue_free())
		add_child(confirm)
		confirm.popup_centered()

func _duplicate_pattern(pattern: Resource) -> void:
	var new_pattern: Resource

	if pattern is PdbEnum:
		new_pattern = PdbEnum.new()
		new_pattern.values = pattern.values.duplicate()
	elif pattern is PdbConst:
		new_pattern = PdbConst.new()
		new_pattern.data = pattern.data.duplicate(true)
	elif pattern is PdbModelDefinition:
		new_pattern = (pattern as PdbModelDefinition).duplicate_definition()
	elif pattern is PdbModelInstance:
		new_pattern = (pattern as PdbModelInstance).duplicate_instance()
		new_pattern.set_database(current_pdb)
	else:
		_log_warning("Cannot duplicate unknown pattern type")
		return

	new_pattern.id = "%s_copy" % pattern.id
	new_pattern.tags = pattern.tags.duplicate()
	new_pattern.description = pattern.description

	current_pdb.add_pattern(new_pattern)
	is_dirty = true

	_log("Duplicated %s -> %s" % [pattern.id, new_pattern.id])

	_refresh_data_tree()
	_refresh_schema_list()
	_select_data_id(new_pattern.id)

func _on_rename_confirmed() -> void:
	var new_id = rename_input.text.strip_edges()
	var item = data_tree.get_selected()
	if not item:
		return
	var pattern = item.get_metadata(0)

	_perform_rename(pattern, new_id)

func _perform_rename(pattern: Resource, new_id: StringName) -> void:
	if new_id == pattern.id or new_id.is_empty():
		_log("Rename canceled: same ID or empty")
		return

	if current_pdb.patterns.has(new_id):
		_log_error("Rename failed: ID '%s' already exists" % new_id)
		return

	var old_id = pattern.id
	var updated_refs := PdbRefactor.rename_pattern(current_pdb, old_id, new_id)
	if updated_refs < 0:
		_log_error("Rename failed for '%s' -> '%s'" % [old_id, new_id])
		return

	_log("Renamed %s -> %s (updated %d references)" % [old_id, new_id, updated_refs])

	is_dirty = true
	_refresh_data_tree()
	_refresh_schema_list()
	_select_data_id(new_id)

func _perform_delete(pattern: Resource) -> void:
	var id = pattern.id
	if current_pdb.patterns.has(id):
		current_pdb.patterns.erase(id)
		is_dirty = true
		_log("Deleted pattern: %s" % id)
		_clear_workspace()
		_refresh_data_tree()
		_refresh_schema_list()

func _open_pattern_in_workspace(pattern: Resource) -> void:
	_log("Opening in workspace: %s (%s)" % [pattern.id, pattern.get_class()])
	_flush_history_capture()
	_clear_workspace()
	_workspace_pattern_id = pattern.id

	var editor = EDITOR_FACTORY.new()
	editor.set_database(current_pdb)
	editor.load_pattern(pattern)
	editor.value_changed.connect(func():
		is_dirty = true
		var sel := data_tree.get_selected()
		if sel != null and sel.get_metadata(0) is PdbModelInstance:
			var thumb := _instance_thumbnail(sel.get_metadata(0) as PdbModelInstance)
			if thumb != null:
				sel.set_icon(0, thumb)
				sel.set_icon_max_width(0, 24)
	)

	editor.request_rename.connect(func(new_id):
		_perform_rename(pattern, new_id)
	)

	editor.request_delete.connect(func(pattern_to_del):
		_perform_delete_with_check(pattern_to_del)
	)

	editor.request_navigate.connect(func(target_id):
		_select_data_id(target_id)
	)

	editor.tags_changed.connect(func():
		is_dirty = true
		var keep := _workspace_pattern_id
		_refresh_data_tree(search_bar.text if search_bar else "")
		_reselect_without_reopen(keep)
	)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = SIZE_EXPAND_FILL

	editor.size_flags_horizontal = SIZE_EXPAND_FILL

	margin.add_child(editor)
	scroll.add_child(margin)
	workspace_panel.add_child(scroll)

func _open_tag_in_workspace(tag: String) -> void:
	_log("Opening tag view: %s" % tag)
	_flush_history_capture()
	_clear_workspace()
	_workspace_pattern_id = &""

	var q := PdbQuery.new(current_pdb)
	var members: Array = q.with_tag(tag, false)
	members.sort_custom(func(a, b): return str(a.id) < str(b.id))

	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Tag  \u00b7  %s" % tag
	title.add_theme_font_size_override("font_size", 18)
	box.add_child(title)

	var sub := Label.new()
	var noun := "object" if members.size() == 1 else "objects"
	sub.text = "%d %s carry this tag (nested paths included)" % [members.size(), noun]
	sub.add_theme_color_override("font_color", _muted_color(0.55))
	box.add_child(sub)

	box.add_child(HSeparator.new())

	if members.is_empty():
		var empty := Label.new()
		empty.text = "No objects carry this tag."
		empty.add_theme_color_override("font_color", _muted_color(0.55))
		box.add_child(empty)
	else:
		for m in members:
			var row := Button.new()
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.text = "%s      \u00b7  %s" % [str(m.id), _pattern_kind_label(m)]
			row.focus_mode = Control.FOCUS_NONE
			var mid: StringName = m.id
			row.pressed.connect(func(): _select_data_id(mid))
			if Engine.is_editor_hint():
				if m is PdbModelInstance:
					var thumb := _instance_thumbnail(m as PdbModelInstance)
					if thumb != null:
						row.icon = thumb
						row.expand_icon = true
			box.add_child(row)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	margin.add_child(box)
	scroll.add_child(margin)
	workspace_panel.add_child(scroll)

func _pattern_kind_label(p: Resource) -> String:
	if p is PdbModelInstance:
		var did := str((p as PdbModelInstance).definition_id)
		return did if did != "" else "Instance"
	if p is PdbModelDefinition:
		return "Definition"
	if p is PdbEnum:
		return "Enum"
	if p is PdbConst:
		return "Constant"
	return "Pattern"

func _clear_workspace() -> void:
	_workspace_pattern_id = &""
	for child in workspace_panel.get_children():
		child.queue_free()

func _trigger_open_dialog() -> void:
	_log("Opening file dialog")
	if PdbWebIo.is_web():
		PdbWebIo.begin_upload(".pdb", func(fname: String, bytes: PackedByteArray): _load_pdb_from_bytes(fname, bytes))
		return
	_pick_pdb_file(false, "", func(path):
		_log("File selected: %s" % path)
		request_open_pdb(path)
	)

func _load_pdb_from_bytes(filename: String, bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		_log_warning("Upload was empty")
		return
	var safe := filename.get_file()
	if not safe.to_lower().ends_with(".pdb"):
		safe += ".pdb"
	var user_path := "user://" + safe
	var f := FileAccess.open(user_path, FileAccess.WRITE)
	if not f:
		_log_error("Could not stage uploaded database")
		return
	f.store_buffer(bytes)
	f.close()
	request_open_pdb(user_path)

func _update_header_title() -> void:
	var text := "PatternDB"
	if current_path != "":
		text += "  \u00b7  " + current_path.get_file()
		if is_dirty:
			text += "  \u2022"
	label_title.text = text
	label_title.tooltip_text = text
	_update_status_bar()

func _switch_view(active_btn: Button) -> void:
	if active_btn.disabled:
		return
	_flush_history_capture()
	for btn in nav_buttons.get_children():
		btn.set_pressed_no_signal(btn == active_btn)
	var view = active_btn.get_meta("view", null)
	if view == null:
		return
	views.current_tab = view.get_index()

	if view.name == "SchemaView":
		_refresh_schema_list()
	elif view == _history_view:
		_history_view.refresh()
	elif view == _table_view:
		_table_view.refresh()

func _finalize_nav() -> void:
	btn_data.set_meta("view", $VBox/ContentArea/Views/DataView)
	btn_schema.set_meta("view", $VBox/ContentArea/Views/SchemaView)
	btn_settings.set_meta("view", $VBox/ContentArea/Views/SettingsView)
	if _history_btn and _history_view:
		_history_btn.set_meta("view", _history_view)
	if _table_btn and _table_view:
		_table_btn.set_meta("view", _table_view)
	nav_buttons.move_child(btn_settings, nav_buttons.get_child_count() - 1)

func _set_db_dependent_tabs_enabled(enabled: bool) -> void:
	if btn_schema:
		btn_schema.disabled = not enabled
	if _history_btn:
		_history_btn.disabled = not enabled
	if _table_btn:
		_table_btn.disabled = not enabled

func _setup_history() -> void:
	_history_controller = PdbHistoryController.new()

	_history_view = PdbHistoryView.new()
	_history_view.name = "HistoryView"
	views.add_child(_history_view)
	_history_view.setup(_history_controller)
	_history_view.database_mutated.connect(_refresh_after_restore)

	_history_btn = Button.new()
	_history_btn.text = "History"
	_history_btn.toggle_mode = true
	_history_btn.flat = true
	nav_buttons.add_child(_history_btn)
	_history_btn.pressed.connect(func(): _switch_view(_history_btn))

	_history_capture_timer = Timer.new()
	_history_capture_timer.one_shot = true
	_history_capture_timer.wait_time = 1.2
	add_child(_history_capture_timer)
	_history_capture_timer.timeout.connect(_on_capture_timeout)

	var vp := get_viewport()
	if vp:
		vp.gui_focus_changed.connect(_on_gui_focus_changed)

func _setup_table() -> void:
	_table_view = PdbTableView.new()
	views.add_child(_table_view)
	_table_view.committed.connect(_on_table_committed)
	_table_view.edit_instance_requested.connect(_on_table_edit_instance)
	_table_view.buffer_changed.connect(_on_table_buffer_changed)

	_table_btn = Button.new()
	_table_btn.text = "Table"
	_table_btn.toggle_mode = true
	_table_btn.flat = true
	nav_buttons.add_child(_table_btn)
	_table_btn.pressed.connect(func(): _switch_view(_table_btn))

func _on_table_committed() -> void:
	is_dirty = true
	_refresh_data_tree()
	_refresh_schema_list()
	_flush_history_capture()

func _on_table_edit_instance(id: StringName) -> void:
	_switch_view(btn_data)
	_select_data_id(id)

func _recovery_path() -> String:
	if _history_controller == null or _history_controller.db_key == "" or current_path == "":
		return ""
	return current_path.get_base_dir().path_join(".patterndb").path_join(_history_controller.db_key).path_join("recovery.dat")

func _on_table_buffer_changed() -> void:
	var p := _recovery_path()
	if p == "" or _table_view == null:
		return
	if _table_view.has_unsaved():
		_write_recovery(p, _table_view.export_recovery())
	else:
		_delete_recovery(p)

func _write_recovery(path: String, rec: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(var_to_str(rec))
		f.close()

func _delete_recovery(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _check_recovery_on_open() -> void:
	var p := _recovery_path()
	if p == "" or _table_view == null or not FileAccess.file_exists(p):
		return
	var rec = str_to_var(FileAccess.get_file_as_string(p))
	if not (rec is Dictionary) or not rec.has("rows"):
		_delete_recovery(p)
		return
	var changes: Array = _table_view.summarize_recovery(rec)
	if changes.is_empty():
		_delete_recovery(p)
		return
	_show_recovery_dialog(rec, changes, p)

func _show_recovery_dialog(rec: Dictionary, changes: Array, path: String) -> void:
	var preview: Array = changes.duplicate()
	var extra := 0
	if preview.size() > 12:
		extra = preview.size() - 12
		preview = preview.slice(0, 12)
	var body := "Unsaved table changes from your last session:\n\n" + "\n".join(preview)
	if extra > 0:
		body += "\n… and %d more" % extra
	body += "\n\nApply them to the database, discard them, or review before committing?"

	var d := ConfirmationDialog.new()
	d.title = "Recover unsaved changes"
	d.dialog_text = body
	d.ok_button_text = "Apply"
	d.add_button("Review", true, "review")
	d.get_cancel_button().text = "Discard"
	add_child(d)
	d.popup_centered()
	d.confirmed.connect(func():
		d.queue_free()
		_table_view.restore_recovery(rec)
		_table_view.apply_buffer()
	)
	d.custom_action.connect(func(action):
		if action == "review":
			d.queue_free()
			_table_view.restore_recovery(rec)
			if _table_btn:
				_switch_view(_table_btn)
			_table_view.call_deferred("flash_changes")
	)
	d.canceled.connect(func():
		d.queue_free()
		_delete_recovery(path)
	)

func _bind_history() -> void:
	if not _history_controller:
		return
	_suspend_capture = true
	_history_controller.bind(current_pdb, current_path)
	_suspend_capture = false
	if _history_view:
		_history_view.refresh()

func _schedule_history_capture() -> void:
	if _history_capture_timer:
		_history_capture_timer.start()

func _on_capture_timeout() -> void:
	if not _history_controller or not _history_controller.enabled:
		return
	if _focus_in_workspace():
		_history_capture_timer.start()
		return
	var h := _history_controller.capture()
	if h != "" and _history_view and views.current_tab == _history_view.get_index():
		_history_view.refresh()

func _focus_in_workspace() -> bool:
	var vp := get_viewport()
	if not vp:
		return false
	var f := vp.gui_get_focus_owner()
	return f != null and workspace_panel.is_ancestor_of(f)

func _warn_incompatible() -> void:
	var supported := PdbMigrations.CURRENT_FORMAT_VERSION
	var d := AcceptDialog.new()
	d.title = "Incompatible database"
	d.dialog_text = "This database was created with a newer version of PatternDB.\n\nFile format: v%d     Installed: v%d\n\nEditing is view-only and saving is disabled to avoid data loss. Please update the PatternDB addon." % [current_pdb.format_version, supported]
	add_child(d)
	d.popup_centered()
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)

func _on_gui_focus_changed(node: Control) -> void:
	if _suspend_capture or not _history_controller or not _history_controller.enabled:
		return
	if node == null or not workspace_panel.is_ancestor_of(node):
		_flush_history_capture()

func _flush_history_capture() -> void:
	if _suspend_capture or not _history_controller or not _history_controller.enabled:
		return
	if _history_capture_timer:
		_history_capture_timer.stop()
	var h := _history_controller.capture()
	if h != "" and _history_view and views.current_tab == _history_view.get_index():
		_history_view.refresh()

func _refresh_after_restore() -> void:
	_suspend_capture = true
	var reopen_id := _workspace_pattern_id
	_update_header_title()
	_refresh_data_tree()
	_refresh_schema_list()
	if _table_view:
		_table_view.setup(current_pdb)
	if reopen_id != &"" and current_pdb and current_pdb.patterns.has(reopen_id):
		_select_data_id(reopen_id)
	else:
		_clear_workspace()
	_suspend_capture = false

func _reselect_without_reopen(id: StringName) -> void:
	if id == &"" or not data_tree.get_root():
		return
	var target := _find_tree_item_by_id(data_tree.get_root(), str(id))
	if target == null:
		return
	_suppress_workspace_reopen = true
	target.select(0)
	data_tree.scroll_to_item(target)
	_suppress_workspace_reopen = false

func _select_data_id(id: StringName) -> void:
	_log("Selecting data item: %s" % id)

	var root = data_tree.get_root()
	if not root:
		return

	var target := _find_tree_item_by_id(root, str(id))
	if target != null:
		target.select(0)
		data_tree.scroll_to_item(target)
		_open_pattern_in_workspace(target.get_metadata(0))
		_log("Item selected and opened")
		return

	_log_warning("Could not find item: %s" % id)

func _find_tree_item_by_id(item: TreeItem, id: String) -> TreeItem:
	var child = item.get_first_child()
	while child:
		var meta = child.get_metadata(0)
		if meta != null and not (meta is Dictionary) and str(meta.id) == id:
			return child
		var found := _find_tree_item_by_id(child, id)
		if found != null:
			return found
		child = child.get_next()
	return null

func _on_save_confirm_action() -> void:
	_log("Save confirmed before opening new file")
	var next_res := _pending_open_resource
	var next_path := _pending_open_path
	_pending_open_resource = null
	_pending_open_path = ""
	_save_pdb()
	if next_res != null:
		_set_active_pdb(next_res, next_res.resource_path)
	elif next_path != "":
		_load_pdb_from_disk(next_path)

func _on_cancel_open_action() -> void:
	_log("Discarding changes, opening new file")
	var next_res := _pending_open_resource
	var next_path := _pending_open_path
	_pending_open_resource = null
	_pending_open_path = ""
	if next_res != null:
		_set_active_pdb(next_res, next_res.resource_path)
	elif next_path != "":
		_load_pdb_from_disk(next_path)

func _on_abort_open_action() -> void:
	_log("Open aborted; keeping current database")
	_pending_open_resource = null
	_pending_open_path = ""

func _setup_settings_view() -> void:
	var host: Control = views.get_node("SettingsView")
	if not host:
		return
	for _c in host.get_children():
		host.remove_child(_c)
		_c.queue_free()
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	host.add_child(scroll)
	var settings_view := VBoxContainer.new()
	settings_view.size_flags_horizontal = SIZE_EXPAND_FILL
	settings_view.size_flags_vertical = SIZE_SHRINK_BEGIN
	scroll.add_child(settings_view)

	settings_view.add_theme_constant_override("separation", 8)

	var heading := Label.new()
	heading.text = "Export Defaults"
	heading.add_theme_font_size_override("font_size", 16)
	settings_view.add_child(heading)

	var note := Label.new()
	note.text = "These defaults are stored inside the database (meta_data) and used to pre-fill the Export dialogs."
	note.add_theme_color_override("font_color", _muted_color(0.6))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_view.add_child(note)
	settings_view.add_child(HSeparator.new())

	settings_dir_input = _add_settings_row(settings_view, "Output Directory:", "res://data/generated", "export_dir")
	settings_enum_input = _add_settings_row(settings_view, "Enum Class Name:", "enums", "enum_class")
	settings_const_input = _add_settings_row(settings_view, "Const Class Name:", "consts", "const_class")
	settings_model_input = _add_settings_row(settings_view, "Model .gd Subfolder:", "model", "model_subdir")
	settings_data_input = _add_settings_row(settings_view, ".tres Data Subfolder:", "data", "data_subdir")
	settings_json_input = _add_settings_row(settings_view, "JSON Subfolder:", "json", "json_subdir")

	var layout_hint := Label.new()
	layout_hint.text = "enums.gd and const.gd are written to the output directory; model classes to <model>/, .tres to <data>/<definition_plural>/, and JSON to <json>/."
	layout_hint.add_theme_font_size_override("font_size", 11)
	layout_hint.add_theme_color_override("font_color", _muted_color(0.5))
	layout_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_view.add_child(layout_hint)

	settings_view.add_child(HSeparator.new())
	var exp_head := Label.new()
	exp_head.text = "Export Options"
	exp_head.add_theme_font_size_override("font_size", 16)
	settings_view.add_child(exp_head)
	settings_tags_check = CheckBox.new()
	settings_tags_check.text = "Embed tags & descriptions in exported .tres / .gd"
	settings_tags_check.button_pressed = true
	settings_tags_check.toggled.connect(func(on):
		if _loading_settings:
			return
		if current_pdb:
			current_pdb.export_tags_metadata = on
			is_dirty = true
	)
	settings_view.add_child(settings_tags_check)
	var tags_hint := Label.new()
	tags_hint.text = "Off strips pdb_tags / pdb_description metadata and skips the generated tag getters."
	tags_hint.add_theme_font_size_override("font_size", 11)
	tags_hint.add_theme_color_override("font_color", _muted_color(0.5))
	tags_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_view.add_child(tags_hint)

	settings_view.add_child(HSeparator.new())
	var conv_head := Label.new()
	conv_head.text = "Editor Conventions"
	conv_head.add_theme_font_size_override("font_size", 16)
	settings_view.add_child(conv_head)
	settings_upper_check = _add_settings_check(settings_view,
		"Enforce UPPERCASE enum value names", "enforce_upper_enums", true,
		"When on, typing an enum value forces UPPER_SNAKE_CASE (e.g. FIRE, ICE_SHARD). Spaces always become underscores regardless.")

	settings_view.add_child(HSeparator.new())
	var hl_head := Label.new()
	hl_head.text = "Table Change Highlights"
	hl_head.add_theme_font_size_override("font_size", 16)
	settings_view.add_child(hl_head)
	settings_hl_modified = _add_settings_color(settings_view, "Modified cell:", "hl_modified", PdbTableView.MODIFIED_CELL_COLOR)
	settings_hl_new = _add_settings_color(settings_view, "New row:", "hl_new", PdbTableView.NEW_ROW_COLOR)
	settings_hl_flash = _add_settings_slider(settings_view, "Review flash intensity:", "hl_flash_alpha", PdbTableView.FLASH_PEAK_ALPHA)

func _add_settings_check(parent: Control, label_text: String, meta_key: String, default_on: bool, tip: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = label_text
	cb.button_pressed = default_on
	cb.tooltip_text = tip
	cb.toggled.connect(func(on):
		if _loading_settings:
			return
		if current_pdb:
			current_pdb.meta_data[meta_key] = on
			is_dirty = true
	)
	parent.add_child(cb)
	if tip != "":
		var hint := Label.new()
		hint.text = tip
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", _muted_color(0.5))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(hint)
	return cb

func _add_settings_color(parent: Control, label_text: String, meta_key: String, default_color: Color) -> ColorPickerButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 160
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(140, 26)
	picker.edit_alpha = true
	picker.color = default_color
	picker.color_changed.connect(func(c):
		if _loading_settings:
			return
		if current_pdb:
			current_pdb.meta_data[meta_key] = c
			is_dirty = true
			if _table_view:
				_table_view.refresh()
	)
	row.add_child(label)
	row.add_child(picker)
	parent.add_child(row)
	return picker

func _add_settings_slider(parent: Control, label_text: String, meta_key: String, default_val: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 160
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = default_val
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 160
	var val_label := Label.new()
	val_label.custom_minimum_size.x = 44
	val_label.text = "%.2f" % default_val
	slider.value_changed.connect(func(v):
		val_label.text = "%.2f" % v
		if _loading_settings:
			return
		if current_pdb:
			current_pdb.meta_data[meta_key] = v
			is_dirty = true
	)
	row.add_child(label)
	row.add_child(slider)
	row.add_child(val_label)
	parent.add_child(row)
	return slider

func _add_settings_row(parent: Control, label_text: String, placeholder: String, meta_key: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 160
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.size_flags_horizontal = SIZE_EXPAND_FILL
	input.text_changed.connect(func(t):
		if current_pdb:
			current_pdb.meta_data[meta_key] = t.strip_edges()
			is_dirty = true
			_sync_export_inputs()
	)
	row.add_child(label)
	row.add_child(input)
	parent.add_child(row)
	return input

func _refresh_settings_view() -> void:
	if not settings_dir_input:
		return
	_loading_settings = true
	var md: Dictionary = current_pdb.meta_data if current_pdb else {}
	settings_dir_input.text = str(md.get("export_dir", "res://data/generated"))
	settings_enum_input.text = str(md.get("enum_class", "enums"))
	settings_const_input.text = str(md.get("const_class", "consts"))
	if settings_model_input:
		settings_model_input.text = str(md.get("model_subdir", "model"))
	if settings_data_input:
		settings_data_input.text = str(md.get("data_subdir", "data"))
	if settings_json_input:
		settings_json_input.text = str(md.get("json_subdir", "json"))
	if settings_tags_check:
		settings_tags_check.button_pressed = current_pdb.export_tags_metadata if current_pdb else true
	if settings_upper_check:
		settings_upper_check.button_pressed = bool(md.get("enforce_upper_enums", true))
	if settings_hl_modified:
		settings_hl_modified.color = md.get("hl_modified", PdbTableView.MODIFIED_CELL_COLOR)
	if settings_hl_new:
		settings_hl_new.color = md.get("hl_new", PdbTableView.NEW_ROW_COLOR)
	if settings_hl_flash:
		settings_hl_flash.value = float(md.get("hl_flash_alpha", PdbTableView.FLASH_PEAK_ALPHA))
	_sync_export_inputs()
	_loading_settings = false

func _sync_export_inputs() -> void:
	if export_dir_input and settings_dir_input:
		export_dir_input.text = settings_dir_input.text if settings_dir_input.text != "" else "res://data/generated"
	if export_enum_class_input and settings_enum_input:
		export_enum_class_input.text = settings_enum_input.text if settings_enum_input.text != "" else "enums"
	if export_const_class_input and settings_const_input:
		export_const_class_input.text = settings_const_input.text if settings_const_input.text != "" else "consts"

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_style_nav_tabs()

func _style_nav_tabs() -> void:
	if not Engine.is_editor_hint() or nav_buttons == null:
		return
	var accent := _editor_color("accent_color", Color(0.4, 0.6, 1.0))
	var base := _editor_color("base_color", Color(0.18, 0.2, 0.24))
	var text := get_theme_color("font_color", "Label")
	var clear := Color(0, 0, 0, 0)
	for btn in nav_buttons.get_children():
		if not (btn is Button):
			continue
		btn.flat = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(100, 30)
		btn.add_theme_stylebox_override("normal", _nav_box(clear, accent, 0))
		btn.add_theme_stylebox_override("hover", _nav_box(base.lightened(0.06), accent, 0))
		btn.add_theme_stylebox_override("pressed", _nav_box(base.lightened(0.13), accent, 2))
		btn.add_theme_stylebox_override("hover_pressed", _nav_box(base.lightened(0.16), accent, 2))
		btn.add_theme_stylebox_override("disabled", _nav_box(clear, accent, 0))
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		btn.add_theme_color_override("font_color", _muted_color(0.6))
		btn.add_theme_color_override("font_hover_color", text)
		btn.add_theme_color_override("font_pressed_color", text)
		btn.add_theme_color_override("font_hover_pressed_color", text)
		btn.add_theme_color_override("font_disabled_color", _muted_color(0.3))

func _editor_singleton() -> Object:
	if Engine.has_singleton("EditorInterface"):
		return Engine.get_singleton("EditorInterface")
	return null

func _editor_rescan() -> void:
	var ei = _editor_singleton()
	if ei:
		ei.get_resource_filesystem().scan()

func _editor_color(color_name: String, fallback: Color) -> Color:
	if has_theme_color(color_name, "Editor"):
		return get_theme_color(color_name, "Editor")
	var ei = _editor_singleton()
	if ei:
		var s = ei.get_editor_settings()
		var key := "interface/theme/%s" % color_name
		if s and s.has_setting(key):
			return s.get_setting(key)
	return fallback

func _nav_box(fill: Color, underline: Color, underline_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	if underline_w > 0:
		s.border_width_bottom = underline_w
		s.border_color = underline
	return s

func _muted_color(alpha := 0.6) -> Color:
	var c := get_theme_color("font_color", "Label")
	c.a = alpha
	return c

func _setup_tooltips() -> void:
	btn_file.tooltip_text = "New, open, save, import, export, validate"
	search_bar.tooltip_text = "Filter patterns and tags by name"
	btn_add_data.tooltip_text = "Add a constant, enum, definition, or instance"
	for btn in nav_buttons.get_children():
		if btn is Button and btn.tooltip_text == "":
			btn.tooltip_text = btn.text

func _update_status_bar() -> void:
	if not status_label or not counts_label:
		return
	if not current_pdb:
		status_label.text = "No database open"
		status_label.add_theme_color_override("font_color", _muted_color(0.55))
		counts_label.text = ""
		return

	if current_pdb.incompatible:
		status_label.text = "Read-only  \u00b7  newer format"
	elif is_dirty:
		status_label.text = "Unsaved changes"
	else:
		status_label.text = "Saved"
	status_label.add_theme_color_override("font_color", _muted_color(0.75))

	var e := 0
	var c := 0
	var d := 0
	var i := 0
	for key in current_pdb.patterns:
		var p = current_pdb.patterns[key]
		if p is PdbEnum:
			e += 1
		elif p is PdbConst:
			c += 1
		elif p is PdbModelDefinition:
			d += 1
		elif p is PdbModelInstance:
			i += 1
	var parts := PackedStringArray()
	if e > 0:
		parts.append("%d enum%s" % [e, "" if e == 1 else "s"])
	if c > 0:
		parts.append("%d const%s" % [c, "" if c == 1 else "s"])
	if d > 0:
		parts.append("%d definition%s" % [d, "" if d == 1 else "s"])
	if i > 0:
		parts.append("%d instance%s" % [i, "" if i == 1 else "s"])
	counts_label.text = "  \u00b7  ".join(parts) if not parts.is_empty() else "empty"
	counts_label.add_theme_color_override("font_color", _muted_color(0.55))

func _show_workspace_message(title_text: String, subtitle_text: String, show_actions: bool) -> void:
	_clear_workspace()
	_workspace_pattern_id = &""

	var center := CenterContainer.new()
	center.size_flags_horizontal = SIZE_EXPAND_FILL
	center.size_flags_vertical = SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)

	if has_theme_icon("Database", "EditorIcons"):
		var icon := TextureRect.new()
		icon.texture = get_theme_icon("Database", "EditorIcons")
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.custom_minimum_size = Vector2(48, 48)
		icon.modulate = _muted_color(0.35)
		box.add_child(icon)

	var t := Label.new()
	t.text = title_text
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 16)
	box.add_child(t)

	if subtitle_text != "":
		var s := Label.new()
		s.text = subtitle_text
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.add_theme_color_override("font_color", _muted_color(0.55))
		box.add_child(s)

	if show_actions:
		var actions := HBoxContainer.new()
		actions.alignment = BoxContainer.ALIGNMENT_CENTER
		actions.add_theme_constant_override("separation", 8)
		var new_btn := Button.new()
		new_btn.text = "New Database"
		new_btn.pressed.connect(func(): _on_file_menu_option(0))
		var open_btn := Button.new()
		open_btn.text = "Open Database..."
		open_btn.pressed.connect(func(): _on_file_menu_option(1))
		actions.add_child(new_btn)
		actions.add_child(open_btn)
		box.add_child(actions)

	center.add_child(box)
	workspace_panel.add_child(center)
