# Task 2 — SongTabsController + SongTabSession + multi-workspace ApplicationSession

## Context

The core port: `ApplicationSession` goes from one `DocumentWorkspace?` to a
`QListModel` of workspaces behind `SongTabsController`, matching the C++
`WorkspaceUi`/`SongTab` contract (spec.md). Source reference:
`swift-qml-songtabs-integration`'s
`src/ui/songview/quick/swift-grid-prototype/SongTabsController.swift` — port
its structure, not its `PianoGrid`-owning sessions. Consumers: Task 3's QML
binds `applicationSession.songTabs`; Task 4's window calls `openSong` /
`requestCloseAll`.

## Exact write set

- `src/swift/app/SongTabsController.swift` (new — `SongTabSession` +
  `SongTabsController`)
- `src/swift/app/ApplicationSession.swift`
- `src/swift/app/CMakeLists.txt`
- `src/ui/songview/quick/swiftroll/qtbridge-object-return.patch` (port the
  `QListModel.move(from:to:)` + `beginMoveRows` section from the songtab
  branch's patch verbatim)
- `src/swift/app/timeline/GridPalette.swift` (add `tabBackground`,
  `tabHoverBackground`, `tabSelectedBackground`; values from songtab branch:
  `#E1DBD6`, `#ECE7E1`, `#B9E8EE`)

## Prerequisites

- Task 1: `DocumentWorkspace.deactivate()`, workspace-owned `drawer`.

## Interface contract

Per plan.md Frozen interfaces — `SongTabSession` and `SongTabsController`
members are fixed there. Additional session-level members:

- `ApplicationSession.songTabs: SongTabsController` — always constructed,
  never nil.
- `ApplicationSession.palette: GridPalette` — one session-owned instance;
  `PianoGrid.palette` continues to exist per grid (grids keep their own
  palette objects; the session palette is the strip's source and the window's
  theme-push target).
- `openSong(label: String)` — new-tab semantics (spec §Open/select/close).
  Drop the `discardChanges` parameter; update `openProjectAndSong` and any
  callers.
- `requestCloseAll()` — sequential dirty-gate close; signals
  `allTabsClosed()` / `closeCancelled()`.
- `songOpen` = `tabCount > 0`; `documentDirty`/`canUndo`/`canRedo` track the
  selected workspace.

## Implementation steps

1. Port `QListModel.move` into the production QtBridge patch (songtab branch
   lines adding `move(from:to:)`, `beginMoveRows` bridge + C++ side).
2. `SongTabSession`: `@QtBridgeable` facade — `tabId`, `title`, `dirty`
   (forwards `workspace.session` dirty state), `grid` (forwards
   `workspace.grid`), plus the 11-member `EditorSurface` surface forwarding
   workspace-owned → workspace, app-scoped → `ApplicationSession` (held
   unowned).
3. `SongTabsController`: port `selectTab`/`moveTab`/`requestClose`/
   `confirmDiscard`/`cancelClose`/`closeTab`/`index(of:)`/`publishSelection`
   from the prototype; add `confirmSave()`; replace `deactivateSelectedGrid`
   with `workspace.deactivate()` + `workspace.activate()` on the incoming;
   `openTab`/`closeTab` become async workspace create/teardown driven by
   `ApplicationSession` (controller exposes the model ops; the session owns
   `DocumentSession.open`/`close` and the `aboutToReleaseGrid` handshake —
   extend the handshake to carry the releasing session identity).
4. `ApplicationSession`: `workspace` becomes computed selected workspace;
   `openSong` implements spec semantics (focus existing / reload selected /
   append new); `replaceSong` becomes append-tab; `retireCurrentDocument`
   becomes per-tab retire used by `closeTab` and `requestCloseAll`;
   `replaceProject` closes all tabs first.
5. `hostClosing` and disposal paths iterate all workspaces.

## Acceptance predicate

`deno task build:checks` && `deno task verify --filter swiftcore --filter swiftdocfeed --filter swiftcommands --filter swiftrollgated --verbose`.
Covers: session open/save/undo through the new model, document feed,
command routing, mounted grid. Tab-strip behavior itself is Task 5's surface.

## Task-specific constraints

- `QListModel.move` must use real `beginMoveRows`/`endMoveRows` — no
  remove/insert imitation, no model reset.
- No synchronous `openTab`: `DocumentSession.open` is async; the controller's
  model append happens after the workspace exists.
- `pendingCloseId` lifecycle identical to prototype (set on dirty request,
  cleared on confirm/cancel/close).
- Keep `openSong(label:discardChanges:)`'s call sites compiling: update
  `RewriteWindow` invocation in Task 4 — for this task keep a compatible
  entry point or adjust the invokeMethod name and flag Task 4 to match.
