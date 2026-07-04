@tool
extends VBoxContainer

class_name PdbPatternEditorBase

signal value_changed
signal request_navigate(target_id: StringName)

var pattern: Resource
var _ui_initialized: bool = false
var _database: PatternDatabaseFile

func _ready() -> void:
	pass

func _setup_ui() -> void:
	pass

func set_database(db: PatternDatabaseFile) -> void:
	_database = db

func _create_value_editor(value: Variant, callback: Callable) -> Control:
	var type = typeof(value)
	return _create_typed_editor(type, PROPERTY_HINT_NONE, "", value, callback)

func _create_typed_editor(type: int, hint: int, hint_string: String, value: Variant, callback: Callable) -> Control:
	match type:
		TYPE_BOOL:
			var cb = CheckBox.new()
			cb.button_pressed = value if value != null else false
			cb.toggled.connect(callback)
			return cb
		TYPE_INT:
			var sb = SpinBox.new()
			sb.step = 1.0
			sb.value = value if value != null else 0
			sb.allow_greater = true
			sb.allow_lesser = true
			sb.value_changed.connect(func(v): callback.call(int(v)))
			return sb
		TYPE_FLOAT:
			var sb = SpinBox.new()
			sb.step = 0.01
			sb.value = value if value != null else 0.0
			sb.allow_greater = true
			sb.allow_lesser = true
			sb.value_changed.connect(callback)
			return sb
		TYPE_STRING, TYPE_STRING_NAME:
			if hint == PROPERTY_HINT_ENUM:
				var opt = OptionButton.new()
				var items = hint_string.split(",")
				for i in items.size():
					var parts = items[i].split(":")
					opt.add_item(parts[0], i)
				opt.selected = int(value) if value != null else 0
				opt.item_selected.connect(callback)
				return opt
			else:
				var le = LineEdit.new()
				le.text = str(value) if value != null else ""
				le.text_changed.connect(func(t):
					if type == TYPE_STRING_NAME:
						callback.call(StringName(t))
					else:
						callback.call(t)
				)
				return le
		TYPE_COLOR:
			var cp = ColorPickerButton.new()
			cp.color = value
			cp.color_changed.connect(callback)
			return cp
		TYPE_VECTOR2:
			var box = HBoxContainer.new()
			var x = SpinBox.new()
			x.prefix = "x"
			x.value = value.x
			x.step = 0.01
			x.allow_greater = true
			x.allow_lesser = true
			var y = SpinBox.new()
			y.prefix = "y"
			y.value = value.y
			y.step = 0.01
			y.allow_greater = true
			y.allow_lesser = true
			var update_vec = func(f): callback.call(Vector2(x.value, y.value))
			x.value_changed.connect(update_vec)
			y.value_changed.connect(update_vec)
			box.add_child(x)
			box.add_child(y)
			return box
		TYPE_RECT2:
			var box = GridContainer.new()
			box.columns = 2
			var x = SpinBox.new()
			x.prefix = "x"
			x.value = value.position.x
			x.step = 0.01
			x.allow_greater = true
			x.allow_lesser = true
			var y = SpinBox.new()
			y.prefix = "y"
			y.value = value.position.y
			y.step = 0.01
			y.allow_greater = true
			y.allow_lesser = true
			var w = SpinBox.new()
			w.prefix = "w"
			w.value = value.size.x
			w.step = 0.01
			w.allow_greater = true
			w.allow_lesser = true
			var h = SpinBox.new()
			h.prefix = "h"
			h.value = value.size.y
			h.step = 0.01
			h.allow_greater = true
			h.allow_lesser = true
			var update_rect = func(f): callback.call(Rect2(x.value, y.value, w.value, h.value))
			for s in [x, y, w, h]:
				s.value_changed.connect(update_rect)
				box.add_child(s)
			return box
		TYPE_OBJECT:
			if Engine.is_editor_hint():
				var picker = ClassDB.instantiate("EditorResourcePicker")
				picker.base_type = "Resource"
				if hint_string:
					picker.base_type = hint_string
				picker.edited_resource = value
				picker.resource_changed.connect(callback)
				return picker
			else:
				var lbl = Label.new()
				lbl.text = str(value)
				return lbl

	var le = LineEdit.new()
	le.text = var_to_str(value) if value != null else ""
	le.tooltip_text = "Edit in native Godot syntax"
	le.text_submitted.connect(func(t):
		var parsed = str_to_var(t)
		if typeof(parsed) == type:
			callback.call(parsed)
	)
	return le
