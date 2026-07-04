@tool
extends EditorPlugin

const MAIN_SCREEN_SCENE = preload("res://addons/pdb/gui/pdb_main_screen.tscn")
const EDITOR_FACTORY = preload("res://addons/pdb/gui/editors/pdb_editor_factory.gd")

const PDB_ENUM = preload("res://addons/pdb/core/pdb_enum.gd")
const PDB_CONST = preload("res://addons/pdb/core/pdb_const.gd")
const PDB_MODEL_DEFINITION = preload("res://addons/pdb/core/pdb_model_definition.gd")
const PDB_MODEL_INSTANCE = preload("res://addons/pdb/core/pdb_model_instance.gd")

const PDB_ENUM_EDITOR = preload("res://addons/pdb/gui/editors/pdb_enum_editor.gd")
const PDB_CONST_EDITOR = preload("res://addons/pdb/gui/editors/pdb_const_editor.gd")
const PDB_MODEL_DEFINITION_EDITOR = preload("res://addons/pdb/gui/editors/pdb_model_definition_editor.gd")
const PDB_MODEL_INSTANCE_EDITOR = preload("res://addons/pdb/gui/editors/pdb_model_instance_editor.gd")

const PDB_THEME_BUNDLER = preload("res://addons/pdb/pdb_theme_bundler.gd")

var _main_screen: Control
var _loader_instance: PdbLoader
var _saver_instance: PdbSaver
var _export_plugin

func _enter_tree() -> void:
	_loader_instance = PdbLoader.new()
	_saver_instance = PdbSaver.new()
	ResourceLoader.add_resource_format_loader(_loader_instance)
	ResourceSaver.add_resource_format_saver(_saver_instance)

	EDITOR_FACTORY.register_editor(PDB_ENUM, PDB_ENUM_EDITOR)
	EDITOR_FACTORY.register_editor(PDB_CONST, PDB_CONST_EDITOR)
	EDITOR_FACTORY.register_editor(PDB_MODEL_DEFINITION, PDB_MODEL_DEFINITION_EDITOR)
	EDITOR_FACTORY.register_editor(PDB_MODEL_INSTANCE, PDB_MODEL_INSTANCE_EDITOR)

	_export_plugin = PDB_THEME_BUNDLER.new()
	add_export_plugin(_export_plugin)

	_main_screen = MAIN_SCREEN_SCENE.instantiate()
	_main_screen.plugin_reference = self
	_main_screen.set_saver(_saver_instance)
	EditorInterface.get_editor_main_screen().add_child(_main_screen)
	_make_visible(false)

func _exit_tree() -> void:
	if _main_screen:
		_main_screen.queue_free()
		_main_screen = null

	EDITOR_FACTORY.clear_registry()

	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null

	if _loader_instance:
		ResourceLoader.remove_resource_format_loader(_loader_instance)
		_loader_instance = null
	if _saver_instance:
		ResourceSaver.remove_resource_format_saver(_saver_instance)
		_saver_instance = null

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "PatternDB"

func _get_plugin_icon() -> Texture2D:
	var base := EditorInterface.get_base_control()
	for icon_name in ["Database", "PackedDataContainer", "ResourcePreloader", "FileList", "Object"]:
		if base.has_theme_icon(icon_name, "EditorIcons"):
			return base.get_theme_icon(icon_name, "EditorIcons")
	return base.get_theme_icon("Object", "EditorIcons")

func _make_visible(visible: bool) -> void:
	if _main_screen:
		_main_screen.visible = visible

func _handles(object: Object) -> bool:
	return object is PatternDatabaseFile

func _edit(object: Object) -> void:
	if not object is PatternDatabaseFile:
		return
	EditorInterface.set_main_screen_editor("PatternDB")
	_main_screen.request_open_resource(object)
