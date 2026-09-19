# Task swift-org — production Swift rehome and obsolete-code retirement

Where this fits: second executable task of the ownership pivot
([plan.md](plan.md)); design.md §6. One cohesive organization change — not
opportunistic renaming inside feature work. Behavior-preserving: every
retained surface behaves identically after this task.

## Target

1. **Rehome**: rename `src/ui/songview/quick/swift-grid-prototype/` to
   `src/ui/songview/quick/swiftroll/` (production Swift sources + `native/`
   helpers + the QtBridge patch + `PatchQtBridge.cmake`). The C++ seam
   directory `src/ui/songview/quick/swiftgrid/` is untouched.
2. **Retire dead code** (exact symbols below; each has zero-caller evidence
   from the 2026-09-19 inventory — re-verify locally before deleting and
   record the verification in your result).
3. **Update paths together**: root `CMakeLists.txt` (swiftgrid target
   sources), `cmake/QtBridge.cmake` (`QTBRIDGE_PATCH_DIR` +
   `CMAKE_CONFIGURE_DEPENDS`), any `module.modulemap` / include paths in
   `src/checks/CMakeLists.txt` Swift targets and `src/checks/swiftgrid`-side
   includes, qrc references, and the documentation paths that name the old
   directory (docs/plans/qtbridge-integration-contract.md baseline table,
   docs/plans/swift-backend-charter.md, design.md — path strings only, no
   semantic edits).

## Deletions (verified zero-caller)

| Symbol/file | Evidence (2026-09-19 inventory) |
| --- | --- |
| `src/ui/songview/quick/swift-grid-prototype/GridFixture.swift` (whole file) | Only caller `PianoGrid.resetDemo()` (PianoGrid.swift:1351,1353); `resetDemo` itself has 0 callers repo-wide. |
| `GridUndo.swift` (whole file: `GridUndoStack`, `GridNoteSnapshot`, `GridEditCommand`, `GridControllerEvent: Equatable`) | Only callers are PianoGrid demo branches listed below. |
| `PianoGrid.resetDemo()` (PianoGrid.swift:1342-1366) | 0 callers. |
| `PianoGrid` local-undo API: `undoStack` field (:175), `canUndo`/`canRedo` (:180-181), `revision` (:182), `undo()` (:688), `redo()` (:695), `syncUndoFlags`, `applyUndoCommand` (:714) and their call sites | Production path is `commandPipe != nil` where undo/redo are no-ops; canUndo/canRedo/revision have 0 external readers (verify QML does not bind them — scoped grep in the QML files). |
| Demo branches gated on `commandPipe == nil`: `deleteSelection` (:660-677 local path), `endPointer` (:947-955 local path), `doublePointer` (:1254-1277 local path), cancel-band branch (:1164) | Production always binds the pipe before editing; delete the nil-branches, keep the pipe-present bodies. `commandPipe` stays Optional (bound in `bindEditingIfReady`); do not redesign binding. Keep the left-edge decline (:883) — production behavior. |
| `PianoGrid.escapePressed(noteMenuOpen:)` (:1105) + `GridEscapeAction` (:49) | 0 callers; keyboard routes via sgk_. |
| `PianoGrid.makePitchEditor` (:609), `previewPitchCurves` (:633), `commitPitchCurves` (:639) | 0 callers after prototype QML lane deletion. |
| `PitchEditor.swift`, `PitchGraph.swift` (whole files) | 0 external callers; prototype pitch-bend popup presenters. Ruling: git history preserves the port; the live feature is C++ `pitchbendeditor.cpp`; patch-capability coverage moves to the `swiftqtml` probe (hunks 1+4). |
| `PitchProjection.swift` (whole file) | 0 Swift callers (C++ `songview::PitchProjection` is the live implementation). |
| `native/curve_session.{h,cpp}` (`NativeGridCurve`, sgc_create/… curve ABI) | Only consumer was `PitchGraph.swift`. NOTE: these share the `sgc_` prefix with the command feed by coincidence — delete only the curve_session pair. |
| `AudioSession.swift`, `native/audio_session.{h,cpp}` (`NativeGridAudio`, `sga_*`), `PianoGrid.audio` property (:76) | `initializeDemo` 0 callers; `session == nil` in production (inert). Miniaudio standalone lane is retired. Before deleting, verify with scoped greps that no QML file binds `audio`/`audioSession` and no C++ references `sga_` — if a live reference exists, STOP that deletion and report it; do not delete referenced code. |
| `TrackHeaders.swift` transport layer: the 33 `@_cdecl("sgth_*")` exports, `TrackHeadersRegistry`, `SgthNotifyFn`/`SgthActionFn`/`SgthStringFn` typedefs (≈ lines 52-78 and 1039-1391) | 0 `sgth_` callers anywhere; `trackheaderswift.{h,cpp}` never existed in-tree. **Keep the presenter core (`TrackHeadersPresenter`, `HeaderRow`, geometry/hit-test/rename/menu state machines) intact** — it is the M1 reference implementation. File stays in the swiftgrid target. |

Keep unchanged: all live production Swift (`PianoGrid` core, `GridScene`,
`GridGeometry`, `GridGesture`, `GridPalette`, `GridTypography`, `TimeAxis`,
`Tick`, `EditCommands`, `EditKeyArbiter`, `SgcCommands`, `SgcKeys`,
`SgdDocument`, `SwiftGridHost`), all C ABI symbol names (`sgf_*`,
`sg_register_grid_types`, every `sg*` export), `native/font_metrics` and
`native/window_cancel`, and all of `src/ui/songview/quick/swiftgrid/`.

## Rules

- No behavior change: after this task every existing check must pass
  unmodified. If a check references a deleted symbol, STOP and report — the
  inventory says none does; a mismatch means the inventory is wrong, not the
  check.
- Do not split files, add subdirectory scaffolds, or rename any `sg*`
  symbol. The directory rename is the only move.
- Swift files keep their declared-surface-first ordering (charter Swift
  policy).
- After deleting `PianoGrid.audio`: any QML binding to it (SwiftRollOverlay
  and siblings under `src/ui/songview/quick/`) is removed in the same change
  only if inert (verify first); if a binding is load-bearing, STOP that piece
  and report.

## Acceptance

- `swiftroll/` exists with the retained sources; old directory gone; all
  build/reference/doc paths updated; `git status` shows a clean rename+delete
  set (no stray copies).
- Every deletion row in your result carries your local re-verification
  (scoped grep command + result, or lsp references) proving zero callers
  pre-deletion.
- Controller gates: `deno task build:checks` then
  `deno task verify --filter swiftrollgated --verbose`,
  `--filter swiftbandkeys`, `--filter swiftcommands`, `--filter swiftdocfeed`,
  `--filter rollcheck`, `--filter selectionkey`, flag-on
  selectionkey-core (40 rows), and `--filter trackheader` (header surface
  regression) — report `tests: DEFERRED_TO_CONTROLLER`.
