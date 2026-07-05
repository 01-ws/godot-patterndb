# Roadmap — post-0.2.0-beta

Planned directions for PatternDB, roughly in priority order. These are
intentions, not dated commitments; scope may shift as the beta matures.

- **Editor architecture — composition over one large class.** Decompose the
  main-screen "god object" into small, single-responsibility controllers and
  panels (data tree, form editor, table, history, settings) that communicate
  through signals, so each surface can be tested, reused, and replaced on its
  own.
- **Data portability.** Broaden and harden conversion across the carried
  formats (`.pdb`, JSON, `.gd`/`.tres`) and external tooling: wider import
  coverage, stricter round-trip fidelity guarantees, and cleaner interchange
  when moving data between projects, authors, and pipelines. (Closely related to
  imported-source fidelity, below.)
- **Bulk editing in the Table view.** Multi-cell and multi-row selection,
  paste-to-fill and fill-series, find-and-replace, and column-wide operations
  (set / clear / transform), all committed through the existing buffered
  **Apply** as single, revertible history entries.
- **Fidelity of externally imported data.** Full display, editing, and
  retention for data authored outside PatternDB — exotic value types, embedded
  sub-resources, and engine-resource references (scenes, textures, audio) — so
  imported `.tres` and other external sources round-trip without silently
  dropping edits or downgrading types. Directly targets today's "imported
  `.tres` re-emits scalar edits only" limitation.
- **Per-instance unsaved state.** Inline dirty highlighting and non-blocking
  recovery for individual instances in the form editor: edits are visibly
  marked and recoverable without gating navigation — unlike the Table's
  buffered Apply, which intentionally blocks switching until you Apply or
  revert.
- **Test suite and CI rebuild.** Reintroduce the headless suites (core model,
  forge round-trips, history, table, integration) and a CI matrix across
  supported Godot 4.x builds, as the compatibility and regression gate.
- **Responsiveness at scale.** Move bulk import/export and history capture off
  the synchronous path (chunked or threaded), with progress feedback, so large
  databases don't stall the editor. Includes virtualized tree/table rendering
  for databases with thousands of instances.
- **Reference integrity and navigation.** Proactive detection of dangling
  references and schema drift, plus "find usages" / backlinks so you can see
  what points at an instance before renaming or deleting it.
- **Object-level merge and restore.** Reconcile individual patterns within a
  database's own history — merge an updated object forward, or restore a prior
  version of a single object — without replacing the whole `.pdb`, building on
  the existing per-object diff/apply engine.
- **Cross-copy diff and merge (developer-driven).** Compare two independent
  copies of a database — your `game.pdb` against another author's or a branch's
  — and reconcile them by hand. A structural diff surfaces added / removed /
  changed patterns and fields with clear conflict marking; you accept or reject
  each change per object (and per field where they diverge), with the diff and
  context there to inform every decision. Nothing merges or resolves
  automatically — the tool presents the differences and guides the choice; the
  final decision is always yours. Extends the per-object diff/apply engine from
  one file's history to two arbitrary sources (`.pdb`, JSON, or `.gd`/`.tres`).
- **Localization.** First-class handling of translatable string fields and
  locale variants, so writers can manage copy alongside the rest of the data.
- **Performance tests and competetive validation.** Created some performance 
  tests against sqlite, json, .pdb vs .tres.
