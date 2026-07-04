# Known issues and limitations — 0.2.0-beta.1

- **Exotic value types** (Transform2D/3D, Basis, Quaternion, AABB, Plane,
  Projection, less common packed arrays) are edited as text in native Godot
  syntax. They serialize and round-trip correctly in all carried formats
  (`.pdb`, JSON, and generated `.gd`/`.tres`).
- **Instances-only JSON export** carries no schema; re-importing it requires
  the definitions to already exist. Use whole-database JSON for a standalone
  round-trip.
- **Binary resources are not imported.** Re-save a `.res` as text `.tres`.
- **Enum import reads decimal values only** (no bit-flag or hex expressions).
- **Editing reference / array / embedded fields on an instance imported from a
  `.tres` may not persist on re-export** — such instances are re-emitted from
  their captured source graph, which overlays scalar edits only. Instances
  authored in PatternDB are unaffected.
- **Tags added to a `.tres`-imported instance** travel in `.pdb`/JSON but not
  in that instance's re-exported `.tres`.
- **Generated `.tres` reference their model script** under `<export_dir>/model/`,
  so run GDScript codegen (or "Export All") alongside the `.tres` export, or the
  resources won't resolve their script class.
- **Class names must be valid, non-reserved GDScript identifiers.** A reserved
  keyword used as the enum/const class name is replaced with a safe default on
  export (shown in the result); definitions, enums, and constant groups named
  after a keyword are rejected until renamed.
- **History restore stringifies dictionary keys.** Non-string keys are
  preserved in all carried formats; only in-editor history navigation is
  affected.
- **History follows a database's stable id** (`db_uid`, stored in the file), so
  a new database that reuses a previous file's name no longer inherits its
  history. Renaming a `.pdb` still starts a fresh sidecar, and files created
  before this field existed remain keyed to their path until re-created.
- **Web builds can't write to folders** — multi-file `.tres`/`.gd` export and
  folder import are desktop-only; JSON and `.pdb` import/export work in the
  browser.
- **Bulk import/export and history capture run synchronously**; very large
  databases can briefly block the editor.
- **No concurrent-write locking** beyond an external-change warning on save.
- A one-time "Missing .uid file" message can appear the first time Godot scans
  the `.pdb` format. It is harmless.
