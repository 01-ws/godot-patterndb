# Building the PatternDB Data Forge as a standalone app

The Data Forge normally runs as a Godot editor plugin. It can also be exported
as a standalone **desktop binary** (Windows / macOS / Linux) or **web build** so
data can be edited outside the editor. This is additive — the in-editor plugin
is unchanged. Feature and usage docs live in `README.md`; this file covers only
building.

The host scene is `addons/pdb/standalone/pdb_app.tscn`. In an export it does what
`pdb_plugin.gd` does in the editor (registers the `.pdb` format and the pattern
editors, then mounts the main screen), so Open / Save / Import / Export / Validate
work with runtime file dialogs.

## Export (editor)

Open **Project → Export**. The presets in `export_presets.cfg` (Web, Windows
Desktop, macOS, Linux) load automatically; pick one and **Export Project**. If a
preset is flagged unknown, remove and re-add it for your platform.

## Export (command line)

```bash
godot --headless --export-release "Windows Desktop" build/windows/pdb_data_forge.exe
godot --headless --export-release "Linux"           build/linux/pdb_data_forge.x86_64
godot --headless --export-release "macOS"           build/macos/pdb_data_forge.zip
godot --headless --export-release "Web"             build/web/index.html
```

The Web export produces `index.html` + `.wasm` + `.pck` + `.js` in `build/web/`.

## Theme and icons: bundled automatically (Editor Version Based)

The addon registers an `EditorExportPlugin` (`pdb_theme_bundler.gd`) that runs on
**every** export — editor or headless CLI. It snapshots the current editor theme
(colors, styleboxes, constants, font sizes) and every editor **icon** (each
re-baked into a self-contained texture), and bakes them into the build as
`addons/pdb/standalone/editor_theme.res`. The standalone host loads that file on
startup, so exported builds match the in-editor look — styled chrome, tree/row
and definition icons, and a working icon picker.

Nothing to invoke, and no file is left in your project; the bundle exists only
inside the export. It reflects whichever editor theme (light or dark) was active
at export time — to switch, export again. Because it carries every icon,
`editor_theme.res` is a few MB (a one-time cached download on web). To drop the
icons and keep only the styling, remove the icon loop in `pdb_theme_bundler.gd`.

## Platform notes

- **Desktop:** Open / Save browse the OS filesystem; `.pdb`, JSON, `.gd`, and
  `.tres` read/write at any absolute path. A `.pdb` path passed as a launch
  argument opens on startup (usable as a file-association handler).
- **Web:** the browser sandbox has no filesystem — Open is an upload, Save/Export
  are downloads, editing is in memory, and work is autosaved to `user://`
  (IndexedDB) across refreshes. Folder-based operations (folder import,
  multi-file `.tres` / `.gd` codegen export) are desktop-only; export JSON in the
  browser and generate code from that.

The asset picker (browse button on `Texture2D` / `PackedScene` / `AudioStream` /
`Mesh` fields) is editor-only; reference fields still hold and round-trip their
`res://` paths in exports.

## F5 preview looks plain — expected

The theme is bundled during a real **export**, not on **F5**, so the F5 preview
uses Godot's default theme. Exported builds are correct. To make the preview
match, run this once as an `EditorScript` (Script editor → New Script, base type
`EditorScript`; File → Run); it writes `editor_theme.tres`, which the host also
loads (the export `.res` takes priority when both exist):

```gdscript
@tool
extends EditorScript

func _run() -> void:
    var src := EditorInterface.get_editor_theme()
    var dst := Theme.new()
    for t in src.get_color_type_list():
        for c in src.get_color_list(t): dst.set_color(c, t, src.get_color(c, t))
    for t in src.get_stylebox_type_list():
        for sb in src.get_stylebox_list(t): dst.set_stylebox(sb, t, src.get_stylebox(sb, t))
    for t in src.get_constant_type_list():
        for k in src.get_constant_list(t): dst.set_constant(k, t, src.get_constant(k, t))
    for t in src.get_font_size_type_list():
        for fs in src.get_font_size_list(t): dst.set_font_size(fs, t, src.get_font_size(fs, t))
    for t in src.get_icon_type_list():
        for ic in src.get_icon_list(t):
            var tex: Texture2D = src.get_icon(ic, t)
            if tex == null: continue
            var img := tex.get_image()
            dst.set_icon(ic, t, ImageTexture.create_from_image(img) if img != null else tex)
    ResourceSaver.save(dst, "res://addons/pdb/standalone/editor_theme.tres")
    print("Editor theme (with icons) written for F5 preview.")
```

> Not run-verified in this environment. Do one export for your target platform to
> confirm templates and paths on your machine.
