# Spec — production SongTabs on the Swift session

## Vocabulary

- **Workspace**: one `DocumentWorkspace` — a `DocumentSession` plus its editor
  presenters (`PianoGrid`, `TrackHeadersPresenter`, `VelocityPage`,
  `VoiceChangesPage`, `AutomationPage`, `EditorDrawerPresenter`).
- **Tab**: a `SongTabSession` — the QML-facing facade over one workspace.
- **Strip**: the `SongTabs.qml` tab row — select, close, drag-reorder,
  overflow scroll, dirty-close dialog.
- **Active workspace**: the selected tab's workspace — the only one bound to
  audio, playhead and the shared drawer-attached state.

## Session model

`ApplicationSession` owns exactly one `SongTabsController`, which owns
`tabs: QListModel<SongTabSession>`. Each `SongTabSession` owns one
`DocumentWorkspace`. `ApplicationSession` keeps app-scoped singletons:
`NativeAudio`, `SharedPlayheadPresenter`, `MouseHints`, `ProjectService`.

`ApplicationSession.workspace` becomes the *selected* workspace accessor
(derived from `songTabs.selectedId`); every existing consumer
(`gridPresenter()`, `requestUndo()`, `playPause()`, `EditorCommandRouter`,
`refreshDocumentState()`) reads through it unchanged.

## Workspace lifecycle

- `DocumentWorkspace.init` no longer binds audio. `activate()` binds audio
  (`audio.bind(timeline:bank:config:)` from the session's stored values),
  attaches playhead + drawer sections, starts polling. `deactivate()` is the
  exact inverse minus destruction: cancel input (hidden reason), detach
  playhead + drawer sections, `audio.stop()` + `audio.unload()`, clear
  `session.onPlayback`. `teardown()` = `deactivate()` + presenter `detach()`s.
- `EditorDrawerPresenter` moves from `ApplicationSession` into
  `DocumentWorkspace` (per-tab drawer state, C++ parity). `attachSection` /
  `detachSection` calls move correspondingly. `ApplicationSession.drawerPresenter()`
  forwards to the selected workspace's presenter; with no tabs it returns a
  retained empty presenter so existing bindings never see nil.

## Open / select / close semantics

- `openSong(label:)`: if a live tab has the label → `selectTab`. If it is the
  selected tab → dirty gate, then in-place reload (close + reopen preserving
  index). Otherwise → async `DocumentSession.open`, append `SongTabSession`,
  select it. The `discardChanges` parameter is dropped — the dirty gate lives
  in the tab close path, not the open path (C++ `maybeSaveTab` prompts on the
  outgoing tab, which tabs no longer destroy).
- `selectTab`: deactivate outgoing, publish selection, activate incoming.
- `requestClose(tabId:)`: clean → close immediately; dirty → `pendingCloseId`
  drives the QML dialog. `confirmDiscard()` closes; `confirmSave()` saves then
  closes on success (failed save reopens the prompt state); `cancelClose()`
  clears.
- `closeTab(index:)`: remove from model → host acknowledgment handshake
  (`aboutToReleaseGrid` / `detachContinuation` — extended to per-tab release)
  → `teardown()` → `session.close()`. Selected close picks `min(index, count-1)`;
  background close preserves selection.
- `requestCloseAll()`: sequential per-tab dirty gate; resolves
  `allTabsClosed()` when every tab is gone, `closeCancelled()` on any Cancel.
- `openProject`: `requestCloseAll`-equivalent teardown of every tab before
  service swap (C++ `destroyAllTabs` ordering: selection publication first,
  then destruction).

## QML surface

- `SwiftRollOverlay.qml` → `SongTabs { controller: applicationSession.songTabs }`.
  The strip is always visible; with zero tabs the page area is blank.
- `SongTab.qml`: `FocusScope` wrapping `EditorSurface` with
  `applicationSession: <SongTabSession>`. Keeps `visible`/`enabled`/`focus`
  bound to selection. Prototype-only members (`pitchBridge`, `noteMenu`,
  `resetDemo`, `escapePressed`, own Flickable) are gone — production
  `EditorSurface` owns input, menus and viewport.
- `SongTabs.qml`: ported with these changes only —
  `gridPalette` → `controller.palette` (session `GridPalette` + 3 tab roles);
  `font`/`baseFontPx` → `Application.font` / its `pixelSize`; `monoFamily`
  dropped; `session.grid.canUndo` → `session.dirty`; dialog gains a Save
  button (`controller.confirmSave()`); `tabart/` references become relative
  resource paths in the `swift_roll_qml` prefix.
- Object names preserved: `songTabStrip`, `songTabSelect_<id>`,
  `songTabClose_<id>`, `songTabScrollLeft/Right`, `songTabPages`,
  `songTab_<id>`.

## RewriteWindow

- `chooseSong` → `invokeOpenSong(label)` (no dirty gate — tabs keep the
  outgoing document alive).
- `closeEvent`: `session.requestCloseAll()`; `allTabsClosed` → accept,
  `closeCancelled` → ignore. Reentrancy: ignore further closeEvents while a
  close-all is in flight.
- `applyGridPalette` targets the session palette (once), not per-grid.
- `songOpen`-gated actions follow "any tab open"; undo/redo/save act on the
  selected workspace.

## Non-goals

- No song-list/browser UI (opening stays on the File menu + `openStartup`).
- No tab persistence/session restore.
- No plus button, dropdown, tab keyboard navigation.
- No C++ feed/seam layer; no `swiftgrid/` resurrection.
- `widget_interop`/`widget_window_fixtures` are not ported (their wizard is
  already QML on the songtab branch; production wizard port is separate work).
