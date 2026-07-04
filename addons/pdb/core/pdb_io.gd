@tool
extends RefCounted
class_name PdbIO

static var _temp_counter: int = 0

static func _tag() -> String:
	return "IO"

static func _unique_temp_path(ext: String) -> String:
	_temp_counter += 1
	return "user://.pdb_tmp_%d_%d.%s" % [Time.get_ticks_usec(), _temp_counter, ext]
