@tool
class_name PdbLog
extends RefCounted

static var enabled: bool = false

static func info(tag: String, msg: String) -> void:
	if enabled:
		print("[PDB][%s] %s" % [tag, msg])

static func warn(tag: String, msg: String) -> void:
	push_warning("[PDB][%s] %s" % [tag, msg])
	if enabled:
		print("[PDB][%s] WARN: %s" % [tag, msg])

static func error(tag: String, msg: String) -> void:
	push_error("[PDB][%s] %s" % [tag, msg])
	if enabled:
		printerr("[PDB][%s] ERROR: %s" % [tag, msg])
