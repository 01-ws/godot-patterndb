@tool
extends EditorExportPlugin

const BUNDLE_PATH := "res://addons/pdb/standalone/editor_theme.res"

func _get_name() -> String:
	return "PatternDBEditorTheme"

func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
	if not Engine.has_singleton("EditorInterface"):
		return
	var ei = Engine.get_singleton("EditorInterface")
	var src := ei.get_editor_theme() as Theme
	if src == null:
		return

	var dst := Theme.new()
	for t in src.get_color_type_list():
		for c in src.get_color_list(t):
			dst.set_color(c, t, src.get_color(c, t))
	for t in src.get_stylebox_type_list():
		for sb in src.get_stylebox_list(t):
			dst.set_stylebox(sb, t, src.get_stylebox(sb, t))
	for t in src.get_constant_type_list():
		for k in src.get_constant_list(t):
			dst.set_constant(k, t, src.get_constant(k, t))
	for t in src.get_font_size_type_list():
		for fs in src.get_font_size_list(t):
			dst.set_font_size(fs, t, src.get_font_size(fs, t))
	var icon_count := 0
	for t in src.get_icon_type_list():
		for ic in src.get_icon_list(t):
			var tex: Texture2D = src.get_icon(ic, t)
			if tex == null:
				continue
			var img := tex.get_image()
			if img != null:
				dst.set_icon(ic, t, ImageTexture.create_from_image(img))
			else:
				dst.set_icon(ic, t, tex)
			icon_count += 1

	var tmp := "user://_pdb_theme_bundle.res"
	if ResourceSaver.save(dst, tmp) != OK:
		push_warning("[PatternDB] Could not serialize the editor theme for export.")
		return
	var f := FileAccess.open(tmp, FileAccess.READ)
	if f == null:
		return
	var data := f.get_buffer(f.get_length())
	f.close()
	add_file(BUNDLE_PATH, data, false)
	print("[PatternDB] Bundled editor theme into export: %d icons, %d bytes." % [icon_count, data.size()])
