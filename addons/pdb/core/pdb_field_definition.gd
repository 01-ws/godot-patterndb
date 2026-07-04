@tool
class_name PdbFieldDefinition
extends Resource

@export var field_name: StringName = &""

@export var field_type: Variant.Type = TYPE_STRING

@export var hint: PropertyHint = PROPERTY_HINT_NONE

@export var hint_string: String = ""

@export var default_value: Variant = null

@export var export_group: String = ""

@export var description: String = ""

@export var required: bool = false

func _init(
	p_name: StringName = &"",
	p_type: Variant.Type = TYPE_STRING,
	p_hint: PropertyHint = PROPERTY_HINT_NONE,
	p_hint_string: String = "",
	p_default: Variant = null
) -> void:
	field_name = p_name
	field_type = p_type
	hint = p_hint
	hint_string = p_hint_string
	default_value = p_default

func get_property_info() -> Dictionary:
	# EDITOR-only usage: `data` is the single stored source. STORAGE here would
	# serialize every field twice.
	return {
		"name": field_name,
		"type": field_type,
		"hint": hint,
		"hint_string": hint_string,
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE
	}

func get_default() -> Variant:
	if default_value != null:
		return default_value
	return _get_type_default(field_type)

func _get_type_default(type: Variant.Type) -> Variant:
	match type:
		TYPE_BOOL:
			return false
		TYPE_INT:
			return 0
		TYPE_FLOAT:
			return 0.0
		TYPE_STRING:
			return ""
		TYPE_STRING_NAME:
			return &""
		TYPE_VECTOR2:
			return Vector2.ZERO
		TYPE_VECTOR2I:
			return Vector2i.ZERO
		TYPE_VECTOR3:
			return Vector3.ZERO
		TYPE_VECTOR3I:
			return Vector3i.ZERO
		TYPE_VECTOR4:
			return Vector4.ZERO
		TYPE_VECTOR4I:
			return Vector4i.ZERO
		TYPE_RECT2:
			return Rect2()
		TYPE_RECT2I:
			return Rect2i()
		TYPE_COLOR:
			return Color.WHITE
		TYPE_TRANSFORM2D:
			return Transform2D.IDENTITY
		TYPE_TRANSFORM3D:
			return Transform3D.IDENTITY
		TYPE_BASIS:
			return Basis.IDENTITY
		TYPE_QUATERNION:
			return Quaternion.IDENTITY
		TYPE_AABB:
			return AABB()
		TYPE_PLANE:
			return Plane()
		TYPE_PROJECTION:
			return Projection.IDENTITY
		TYPE_ARRAY:
			return []
		TYPE_PACKED_BYTE_ARRAY:
			return PackedByteArray()
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array()
		TYPE_PACKED_INT64_ARRAY:
			return PackedInt64Array()
		TYPE_PACKED_FLOAT32_ARRAY:
			return PackedFloat32Array()
		TYPE_PACKED_FLOAT64_ARRAY:
			return PackedFloat64Array()
		TYPE_PACKED_STRING_ARRAY:
			return PackedStringArray()
		TYPE_PACKED_VECTOR2_ARRAY:
			return PackedVector2Array()
		TYPE_PACKED_VECTOR3_ARRAY:
			return PackedVector3Array()
		TYPE_PACKED_COLOR_ARRAY:
			return PackedColorArray()
		TYPE_PACKED_VECTOR4_ARRAY:
			return PackedVector4Array()
		TYPE_DICTIONARY:
			return {}
		TYPE_NODE_PATH:
			return NodePath()
		TYPE_RID:
			return RID()
		TYPE_OBJECT:
			return null
		TYPE_CALLABLE:
			return Callable()
		TYPE_SIGNAL:
			return Signal()
		_:
			return null

func duplicate_field() -> PdbFieldDefinition:
	var copy = PdbFieldDefinition.new()
	copy.field_name = field_name
	copy.field_type = field_type
	copy.hint = hint
	copy.hint_string = hint_string
	copy.default_value = default_value
	copy.export_group = export_group
	copy.description = description
	copy.required = required
	return copy

func is_enum_field() -> bool:
	return hint == PROPERTY_HINT_ENUM

func is_resource_field() -> bool:
	return field_type == TYPE_OBJECT and hint == PROPERTY_HINT_RESOURCE_TYPE

func is_external_resource() -> bool:
	if not is_resource_field():
		return false
	if hint_string == "":
		return true
	return ClassDB.class_exists(hint_string) and ClassDB.is_parent_class(hint_string, "Resource")

func is_array_field() -> bool:
	return field_type == TYPE_ARRAY

func get_enum_values() -> PackedStringArray:
	if not is_enum_field():
		return PackedStringArray()
	return hint_string.split(",", false)

func get_resource_type() -> String:
	if not is_resource_field():
		return ""
	return hint_string

func get_array_element_type() -> String:
	if not is_array_field():
		return ""
	if hint == PROPERTY_HINT_ARRAY_TYPE:
		return hint_string
	return ""

func validate_value(value: Variant) -> bool:
	if value == null:
		return not required
	if typeof(value) != field_type:
		if field_type == TYPE_OBJECT and (value is Object or value is String or value is StringName or value is Dictionary):
			return true
		return false
	return true

func _to_string() -> String:
	return "<PdbFieldDefinition:%s:%s>" % [field_name, type_string(field_type)]
