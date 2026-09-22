# Swift SongTabs port — production tabs on the Swift session

Status: authored. Base: `feature/swift-qml-grid` @ `94671884`.
Source artifacts: `swift-qml-songtabs-integration` branch (worktree
`.worktrees/swift-qml-songtab`), files under
`src/ui/songview/quick/swift-grid-prototype/`: `SongTab.qml`, `SongTabs.qml`,
`SongTabsController.swift`, `tabart/`, and the `QListModel.move` section of
`qtbridge-object-return.patch`.

## Goal

Port the prototype SongTabs surface onto the production Swift session so the
three artifacts remain mergeable: same filenames, same controller API, same
strip object names. The production tabs model is `ApplicationSession` owning a
`QListModel` of per-song workspaces — the Swift counterpart of the dead C++
`WorkspaceUi`/`SongTab`/`QTabWidget` layer, which remains the behavioral
authority.

## Behavioral contract (from C++ `workspaceui_tabs.cpp` / `songtab.cpp`)

- One live tab per song label. `openSong(label)` focuses the existing tab;
  re-opening the selected tab is the in-place reload path (close + reopen at
  the same index, after the dirty gate).
- New tabs append and select. Selecting a tab deactivates the outgoing
  workspace (cancel input, stop audio, detach playhead/drawer) and activates
  the incoming one. Hidden tabs keep their full workspace state.
- Reorder uses genuine `beginMoveRows`/`endMoveRows`; page instances, camera,
  selection and undo survive.
- Dirty close prompts Save / Discard / Cancel (production has real
  persistence — the prototype's Discard/Cancel-only dialog gains Save).
  Background close preserves selection; selected close selects the adjacent
  survivor; final close leaves the empty strip + blank page (C++ empty
  QTabWidget).
- Strip is always visible, `Qt::NoFocus` on all strip controls, native
  accessibility press retained. No plus button, dropdown, or new shortcuts.
- Per-tab drawer state: each workspace owns its `EditorDrawerPresenter`
  (C++ per-tab drawer parity). Playhead stays app-scoped — one shared audio
  engine means one transport position.
- `openProject` closes all tabs (C++ `destroyAllTabs` on project switch).
- Window close iterates dirty tabs with the same Save/Discard/Cancel gate;
  Cancel aborts the close.

## Global Constraints

- `deno task` only: `build:app`, `build:checks`, `verify --filter X --verbose`.
  Never raw cmake. Tool timeouts ≤ 300s.
- Work happens in a dedicated worktree created via
  `deno task worktree:create -- swift-songtabs-port --base feature/swift-qml-grid`.
- Push every checkpoint commit to origin.
- No C++ seam resurrection: nothing under the retired `swiftgrid/` feed layer
  returns. Tabs are pure Swift publication + QML.
- No new tab features beyond C++ parity: no plus button, dropdown, keyboard
  tab navigation, focus caches, or second dispatchers.
- Implementers reuse the verification commands recorded in each brief.
  Implementers perform read-only local inspection only; controller runs all
  builds/checks/format on the settled tree (SHARED_TREE).
- Workarounds require approval; fix root causes.
- The user's uncommitted WIP in the swift-qml-grid worktree is off-limits.

## Frozen interfaces

- `SongTabSession` (`@QtBridgeable`, `src/swift/app/SongTabsController.swift`):
  `tabId: Int`, `title: String`, `dirty: Bool`, `grid: PianoGrid`, plus the
  `EditorSurface` session surface — `gridPresenter()`, `trackHeadersPresenter()`,
  `drawerPresenter()`, `playheadPresenter()`, `mouseHintsPresenter()`,
  `velocityPage()`, `voiceChangesPage()`, `automationPage()`, `songOpen`,
  `cancelGridInput(reason:)`, `requestGridContextMenu(x:y:)`. Workspace-owned
  members forward to its `DocumentWorkspace`; app-scoped members forward to
  `ApplicationSession`.
- `SongTabsController` (`@QtBridgeable`, same file): `tabs: QListModel<SongTabSession>`,
  `selectedId`, `selectedIndex`, `tabCount`, `pendingCloseId: Int`;
  `selectTab(tabId:)`, `moveTab(tabId:destinationIndex:)`, `requestClose(tabId:)`,
  `confirmDiscard()`, `confirmSave()`, `cancelClose()`. No `openTab` on the QML
  surface — opening is `ApplicationSession.openSong`.
- `ApplicationSession`: `songTabs: SongTabsController` (always constructed),
  `palette: GridPalette` (session-owned; per-grid palette reads it or shares it —
  decided: session owns one `GridPalette`, each `PianoGrid.palette` remains the
  same object), `openSong(label:)` → new-tab semantics above,
  `requestCloseAll()` → async dirty-gate iteration emitting `allTabsClosed()` /
  `closeCancelled()`.
- `DocumentWorkspace`: `deactivate()` (non-destructive inverse of `activate()`:
  cancel input, detach playhead + drawer sections, stop + unload audio, clear
  `session.onPlayback`), `activate()` extended to (re)bind audio. Owns its
  `EditorDrawerPresenter`.
- QML: `SongTabs.qml` + `SongTab.qml` under
  `src/ui/songview/quick/swiftroll/`; `SwiftRollOverlay.qml` becomes
  `SongTabs { controller: applicationSession.songTabs }`. `SongTab.qml` is a
  `FocusScope` wrapping `EditorSurface` bound to the tab's `SongTabSession`.
- QtBridge patch gains the `QListModel.move(from:to:)` section ported from the
  songtab branch's `qtbridge-object-return.patch`.
- Tab art: `tabart/` PNGs + `window-close.svg` into the `swift_roll_qml`
  resource under `tabart/`; QML references `tabart/...` relative paths.
- `GridPalette` gains `tabBackground`, `tabHoverBackground`,
  `tabSelectedBackground` (values from the songtab branch).

## Tasks

| # | Task | Route | Why |
|---|------|-------|-----|
| 1 | `DocumentWorkspace` activate/deactivate + per-workspace drawer presenter | SDD-track | Lifecycle surgery on shared audio/playhead/drawer ownership; behavior-preserving refactor verified by existing suites |
| 2 | `SongTabsController` + `SongTabSession` + `ApplicationSession` multi-workspace + QtBridge `move` | SDD-track | New model surface; async open/close semantics; the core port |
| 3 | QML port: `SongTab.qml`, `SongTabs.qml`, `SwiftRollOverlay.qml`, palette roles, tabart resources | SDD-track | QML-heavy; strip geometry/tooltip/dirty-dialog contract |
| 4 | `RewriteWindow` wiring: openSong new-tab, closeEvent iteration, palette push to session palette | SDD-track | Qt/C++ window contract changes |
| 5 | Tab scenarios in `swiftrollgated` | SDD-track | Port the 8 `songtabs_smoke` scenarios to the production gate |

Dependencies: T2 consumes T1's `deactivate()`; T3 consumes T2's controller API
(contract frozen above — may pipeline during T2 review); T4 consumes T2's
`requestCloseAll`; T5 consumes all.

## Checkpoints

- After T1 accepted (lifecycle refactor lands alone — pure refactor).
- After T2+T3+T4 accepted (feature lands together; T3/T4 re-edit nothing from T1).
- Final: T5 + whole-branch review.

## Controller verification

- `deno task build:checks`
- `deno task verify --filter swiftrollgated --filter swiftcore --filter swiftdocfeed --filter swiftcommands --filter editorqml --verbose`
- `deno task verify --filter selectionkey --verbose` (keyboard routing parity)
- `deno task format --check` on changed C++ files
- Native-input scenarios need a quiet desktop; run sequentially.
