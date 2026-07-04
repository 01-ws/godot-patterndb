extends Control

const MAIN_SCREEN_SCENE := preload("res://addons/pdb/gui/pdb_main_screen.tscn")
const EDITOR_FACTORY := preload("res://addons/pdb/gui/editors/pdb_editor_factory.gd")
const PDB_ENUM := preload("res://addons/pdb/core/pdb_enum.gd")
const PDB_CONST := preload("res://addons/pdb/core/pdb_const.gd")
const PDB_MODEL_DEFINITION := preload("res://addons/pdb/core/pdb_model_definition.gd")
const PDB_MODEL_INSTANCE := preload("res://addons/pdb/core/pdb_model_instance.gd")
const PDB_ENUM_EDITOR := preload("res://addons/pdb/gui/editors/pdb_enum_editor.gd")
const PDB_CONST_EDITOR := preload("res://addons/pdb/gui/editors/pdb_const_editor.gd")
const PDB_MODEL_DEFINITION_EDITOR := preload("res://addons/pdb/gui/editors/pdb_model_definition_editor.gd")
const PDB_MODEL_INSTANCE_EDITOR := preload("res://addons/pdb/gui/editors/pdb_model_instance_editor.gd")

var _loader: PdbLoader
var _saver: PdbSaver
var _main_screen: Control

const SESSION_FILE := "user://session/working.pdb"
var _session_timer: Timer

func _ready() -> void:
	_loader = PdbLoader.new()
	_saver = PdbSaver.new()
	ResourceLoader.add_resource_format_loader(_loader)
	ResourceSaver.add_resource_format_saver(_saver)

	EDITOR_FACTORY.register_editor(PDB_ENUM, PDB_ENUM_EDITOR)
	EDITOR_FACTORY.register_editor(PDB_CONST, PDB_CONST_EDITOR)
	EDITOR_FACTORY.register_editor(PDB_MODEL_DEFINITION, PDB_MODEL_DEFINITION_EDITOR)
	EDITOR_FACTORY.register_editor(PDB_MODEL_INSTANCE, PDB_MODEL_INSTANCE_EDITOR)

	_main_screen = MAIN_SCREEN_SCENE.instantiate()
	_main_screen.set_saver(_saver)
	add_child(_main_screen)
	_main_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_bundled_theme()

	_open_initial_database()
	if PdbWebIo.is_web():
		_start_session_autosave()

func _apply_bundled_theme() -> void:
	for theme_path in ["res://addons/pdb/standalone/editor_theme.res", "res://addons/pdb/standalone/editor_theme.tres"]:
		if ResourceLoader.exists(theme_path):
			var t = load(theme_path)
			if t is Theme:
				_main_screen.theme = t
				return

func _open_initial_database() -> void:
	if PdbWebIo.is_web() and FileAccess.file_exists(SESSION_FILE):
		_main_screen.request_open_pdb(SESSION_FILE)
		_main_screen.is_dirty = true
		_main_screen._update_header_title()
		return
	for arg in OS.get_cmdline_args():
		if arg.to_lower().ends_with(".pdb") and FileAccess.file_exists(arg):
			_main_screen.request_open_pdb(arg)
			return
	var empty := PatternDatabaseFile.new()
	empty.ensure_uid()
	_main_screen._set_active_pdb(empty, "")

func _start_session_autosave() -> void:
	DirAccess.make_dir_recursive_absolute(SESSION_FILE.get_base_dir())
	_session_timer = Timer.new()
	_session_timer.wait_time = 5.0
	_session_timer.autostart = true
	_session_timer.timeout.connect(_autosave_session)
	add_child(_session_timer)

func _autosave_session() -> void:
	if _main_screen == null or _main_screen.current_pdb == null:
		return
	if not _main_screen.is_dirty:
		return
	if _saver:
		_saver._save(_main_screen.current_pdb, SESSION_FILE, 0)
