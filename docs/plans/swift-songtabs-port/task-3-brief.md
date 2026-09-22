# Task 3 — QML port: SongTab.qml, SongTabs.qml, SwiftRollOverlay, tabart

## Context

Brings the prototype strip into the production QML resource. Source files:
`swift-qml-songtabs-integration` worktree
`src/ui/songview/quick/swift-grid-prototype/{SongTabs.qml,SongTab.qml}` and
`tabart/` (8 PNGs + `window-close.svg`). The strip/port must keep filenames
and object names so future songtab-branch work merges cleanly.

## Exact write set

- `src/ui/songview/quick/swiftroll/SongTabs.qml` (new — port)
- `src/ui/songview/quick/swiftroll/SongTab.qml` (new — FocusScope wrapping
  `EditorSurface`)
- `src/ui/songview/quick/swiftroll/SwiftRollOverlay.qml` (rewrite — hosts
  `SongTabs`)
- `src/ui/songview/quick/swiftroll/tabart/` (new — copy 9 files from the
  songtab worktree, preserving the SVG license comment)
- `CMakeLists.txt` (`swift_roll_qml` FILES gains `SongTabs.qml`,
  `SongTab.qml`, and the `tabart/` files)

## Prerequisites

- Task 2's frozen contract: `applicationSession.songTabs` (controller),
  `applicationSession.palette` (session `GridPalette` with tab roles),
  `SongTabSession` facade members.

## Interface contract

- `SongTabs.qml` root: `Item` with `required property QtObject controller`.
  All prototype behavior preserved: `revealSelectedTab`, StripButton /
  ScrollButton components, `songTabStrip`/`songTabSelect_*`/`songTabClose_*`/
  `songTabScroll*`/`songTabPages`/`songTab_*` object names, DragHandler
  reorder → `controller.moveTab`, dirty-close Dialog.
- `SongTab.qml` root: `FocusScope` with `required property QtObject session`
  (a `SongTabSession`); body is `EditorSurface { applicationSession: session }`
  filling it. `visible`/`enabled`/`focus` bind to selection as in the
  prototype page delegate.
- `SwiftRollOverlay.qml`: `SongTabs { anchors.fill: parent; controller:
  applicationSession.songTabs }` — keeps `required property QtObject
  applicationSession`.

## Implementation steps

1. Copy `SongTabs.qml`; apply only these deltas: `gridPalette` →
   `controller.palette`; `font`/`baseFontPx`/`monoFamily` props →
   `Application.font` and `Application.font.pixelSize`; dirty marker binding
   `session.grid.canUndo` → `session.dirty`; `tabart/` URLs → relative
   `tabart/...` paths inside the `swift_roll_qml` prefix; dialog gains a Save
   button calling `controller.confirmSave()` (Save / Discard / Cancel order
   per C++ `askDirtyDecision`); page delegate instantiates `SongTab` with
   `session: model.display`.
2. Write `SongTab.qml` as the thin FocusScope wrapper (no prototype body —
   `EditorSurface` owns input/menus/viewport; keep `onVisibleChanged` hidden
   → `session.cancelGridInput(2)` only if `EditorSurface` doesn't already
   cover it — it does via its own `onVisibleChanged`, so omit).
3. Rewrite `SwiftRollOverlay.qml` to host `SongTabs`.
4. Copy `tabart/` (8 arrow PNGs + `window-close.svg` with license comment);
   register all in `swift_roll_qml`.
5. `EditorSurface` is unchanged — it already takes `applicationSession` and
   binds the facade's 11 members.

## Acceptance predicate

`deno task build:app` && `deno task verify --filter swiftrollgated --filter editorqml --verbose`.
Covers: overlay still mounts, grid renders, drawer binds through the facade.
Strip interaction is Task 5's surface.

## Task-specific constraints

- Strip always visible (C++ QTabWidget parity); zero tabs → blank page area,
  no placeholder text.
- All strip controls `focusPolicy: Qt.NoFocus`; no `Keys.onSpacePressed`,
  no ShortcutOverride (AGENTS.md global-shortcut rule).
- `pixelAligned: true` on the strip Flickable preserved.
- Do not restyle: production strip metrics come from the ported formulas
  (`tabMargin`, `tabPadding`, `closeExtent`, `scrollExtent`, `tabHeight`).
