# PatternDB

Schema-driven game data for Godot 4.x. A `.pdb` database stores **enums**,
**constants**, **model definitions** (schemas), and **model instances** (rows),
and generates typed GDScript classes and native `.tres` resources from them.

`.pdb` files are plain Godot text resources under a custom extension, so the
format stays engine-native. Double-clicking a `.pdb` in the FileSystem dock
opens it in the PatternDB main screen.

## Install

Copy `addons/pdb/` into your project and enable **PatternDB** under
*Project → Project Settings → Plugins*.

## Concepts

- **Enum** — a named set of `name -> int` entries.
- **Constant group** — a named bag of typed constants.
- **Model definition** — a schema: ordered typed fields, an `extends` type, an icon.
- **Model instance** — a row of data conforming to a definition.
- **Tags** — multi-valued classifiers on every pattern. Dot paths
  (`element.fire`) form a hierarchy that queries can roll up.

Ids, field names, and enum/const keys must be valid GDScript identifiers.

### References

- A field whose resource hint names a **PatternDB definition** is a
  cross-instance link, stored as a `StringName` id. Pick it from a validated
  dropdown in the instance editor; resolve it with `db.get_pattern(id)` or
  `PdbQuery`.
- A field whose hint names an **engine class** (`Texture2D`, `PackedScene`, …)
  stores a `res://` path. Resolve it with `instance.get_resource(field)`. Only
  the path travels; assets are never embedded.

## Runtime API

```gdscript
var db := PatternDB.load_pdb("res://game_data.pdb")

var sword := db.get_pattern(&"Flamebrand") as PdbModelInstance
var dmg = sword.get_value(&"damage")

var q := PdbQuery.new(db)
q.pattern("Flamebrand")            # a pattern by id
q.value("Flamebrand", "damage")    # a field value
q.instances_of("Item")             # every row of a definition
q.with_tag("element.fire")         # patterns carrying a tag
q.with_tag("element", false)       # hierarchical match
q.with_all_tags(["ranged", "aoe"]) # intersection
```

`PatternDB.save_pdb(db, path)` writes a `.pdb`. Call `PdbQuery.refresh()` after
mutating the database.

With tag metadata exported (the default), generated classes expose tags
natively: `res.get_tags()`, `res.has_tag(&"weapon")` (hierarchical — matches
`weapon.sword`). Toggle with `PatternDatabaseFile.export_tags_metadata`.

## Editor

Five tabs:

- **Data Forge** — a searchable tree of every pattern with add / duplicate /
  delete / rename and a per-pattern editor. Renaming repoints every reference.
- **Schema** — model definitions with a live GDScript preview. Schema edits
  migrate existing instance data.
- **Table** — spreadsheet editing of every instance of one definition: typed
  inline cells, fill-down, reference hotlinks, resizable columns, and a
  **Nesting** slider that expands dictionary fields into sub-columns. Edits are
  buffered and committed with **Apply** as a single history commit; a dirty
  buffer is autosaved for crash recovery and offered back on the next open.
- **Settings** — output directory, class names, output subfolders (model / data
  / JSON), and table colors.
- **History** — a branchable commit tree with change summaries, per-object
  filtering, restore, branches, and snapshots. Stored as a sidecar under
  `.patterndb/` next to the database; never load-bearing.

## Codegen

`PdbCodegen.export_all(db, output_dir, enum_class, const_class, model_subdir)`
writes:

- `enums.gd` and `const.gd` at the output root, plus one typed `Resource`
  subclass per definition under `<output_dir>/<model_subdir>/` (default
  `model/`);
- enum fields typed `EnumClass.EnumName`; cross-instance references typed
  `StringName` (`Array[StringName]` for arrays);
- inheritance-aware output: fields supplied by a parent definition are not
  re-declared.

Class names default to `enums` and `consts` and are set in Settings. Any name
that isn't a valid, non-reserved GDScript identifier is replaced with a safe
default on export (reported in the result).

## Import / Export

Carried formats — convertible between one another with type-and-value
identity — are **`.pdb`, whole-database JSON, and generated `.gd`/`.tres`**:

- `PdbExporter.export_all_to_json(db, path)` — self-describing, type-exact
  JSON (schema travels with the data); round-trips through
  `PdbImporter.import_from_json`.
- `PdbExporter.export_instances_to_tres(db, output_dir, script_dir)` — one
  `.tres` per instance bound to its generated script, grouped into
  `<output_dir>/<definition_plural>/` (e.g. `data/abilities/slash.tres`); the
  instance id is preserved as `resource_name` and filenames are de-duplicated.
- `PdbImporter` also ingests enums and definitions from GDScript, instances
  from `.tres`, and tabular data from CSV (import-only).

**Export All to Configured Folder** runs codegen, `.tres`, and whole-database
JSON in one pass into the paths set in Settings.

## Format versioning

Every `.pdb` carries a user `version` and an addon-managed `format_version`.
Older files migrate on load; files written by a newer addon open read-only.

## Standalone

`standalone/pdb_app.tscn` hosts the same editor as a desktop or web app
without the Godot editor. The web build autosaves the working database to
browser storage and uses upload/download for Open and Save.

See `KNOWN_ISSUES.md` for current beta limitations.
