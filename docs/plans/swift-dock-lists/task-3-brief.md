# task-3-brief.md — Songs panel, shell dock, and song mutations

## Context

Move the Songs list from the native popup/widget surface into the rewrite shell as a QML dock. Reuse the session-fed `SongListPresenter` and its existing ID-based activation, Register, and Delete intents. The panel owns project navigation and filtering; the host retains the window-level Find Song shortcut and transport. This task includes the functional service-plan confirmations, not just list presentation.

## Exact write set

- `src/ui/songview/quick/swiftroll/SongsPanel.qml` — new production panel.
- `src/ui/songview/quick/swiftroll/SwiftRollOverlay.qml` — shell-level dock column, splitter, and tab-strip placement.
- `src/swift/app/ApplicationSession.swift` — presenter mutation callbacks, service-plan confirmation state, mutation methods, refreshed list publication, and removal of `songCount()`, `songLabel(index:)`, and the private `labels` cache in the same cutover as the native chooser.
- `src/swift/app/timeline/GridPalette.swift` — expose the item-view palette roles used by the panel.
- `src/app/RewriteWindow.cpp` — remove native `chooseSong()` and its Open Song popup/action path, install Find Song, persist dock/filter state, and push panel palette values.
- `src/app/RewriteWindow.h` — remove the obsolete Open Song action/member and chooser declaration.
- `src/checks/swiftrollgated/songlistchecks.cpp` — new native QML/host interaction scenarios.
- `src/checks/swiftrollgated/tst_swiftrollgated.h` — declare the new scenario slots.
- `src/checks/CMakeLists.txt` — compile the new swiftrollgated scenario source.
- `CMakeLists.txt` — add `SongsPanel.qml` to `swift_roll_qml`.

## Prerequisites

Tasks 1 and 2: the existing `ProjectService.songs()` feed and session-owned `SongListPresenter`. Run after task 2; both update `ApplicationSession.swift`, and this task depends on task 2's completed feed/navigation wiring.

## Interface contract

- `SongsPanel` takes `applicationSession` as a QML `var` exposing `songList` and `palette`; production passes the real `ApplicationSession`. Bind visible rows to `songList.rows` and category choices to `songList.categories`; use the existing row fields `songId`, `label`, `text`, `warning`, `registrationGapText`, `selected`, and `current`. Observe the presenter's `searchFocusRequest` and `revealRequest` / `revealSongId`: Find Song focuses the search field and selects its text; current-song reveals scroll its row into view. This permits the visual-only check to pass a check-local presentation adapter without adding a production presenter-seeding API.
- Preserve the existing panel/source object names `songListSearch`, `songListCategory`, `songListSort`, `songList`, and `songListCount`. Keep the shell root's `applicationSession` and `gridModel` contracts used by `RewriteWindow::attachGridScene` and `gridcheck::NativeScene`.
- Use existing presenter methods: `selectSong(songId:)`, `activateSong(songId:)`, `activateSelection()`, `requestOpen(songId:)`, `requestOpenInNewTab(songId:)`, `requestRegister(songId:)`, `requestDelete(songId:)`, `canRegister(songId:)`, and `focusSearch()`. Do not call the nonexistent `moveSelection` or `activateCurrentOrFirst`.
- Row activation and both Open context actions resolve by song ID and route through `ApplicationSession.openSong(label:)`. That method owns current behavior: focus an already-open non-selected tab, request the existing reload path for the selected tab, and append one tab for a new label.
- Add real Register/Delete confirmation state to `ApplicationSession`, retaining the exact `SongRegistrationPlan` / `SongDeletionPlan` privately until Confirm or Cancel. The QML dialogs receive:
  - `songRegistrationConfirmationRequested(label, constant, player, missingFiles)`.
  - `songDeletionConfirmationRequested(label, tableIndex, tableCount, lastEntry, inSongsH, inLdScript, inCharmap, inDebugMenu, deletableVoicegroupName, deletableVoicegroupDisplay)`; empty voicegroup strings mean the service plan offers none.
  - `confirmSongRegistration()`, `cancelSongRegistration()`, `confirmSongDeletion(deleteVoicegroup:)`, and `cancelSongDeletion()` consume or discard the stored plan.
- Registration planning/commit uses `ProjectService.songRegistrationPlan(label:)` and `registerSong(_:)`. Show the proposed label, constant, player, and missing files; Cancel performs no mutation. Delete planning/commit uses `songDeletionPlan(label:)` and `deleteSong(label:voicegroupName:)`. Show the plan's table index/count and affected registration files; explain the last-entry versus reusable-slot result; offer the extra voicegroup checkbox only when `deletableVoicegroupName` is present, and pass only that plan-owned name when checked. Table index `0` is the engine fallback and cannot be deleted.
- On successful mutation, refresh with `ProjectService.songs()` and `songList.setSongs(_:)`; keep selected/current song identity if it remains in the listing. After a successful delete, call `songTabs.requestClose(tabId:)` only for the matching open tab and let its normal dirty-close gate run; do not close unrelated tabs. Cancel before commit or service failure must not close or replace a tab. Surface plan/mutation failures through the existing `lastSaveError` and `operationFailed(message:)` path.
- `RewriteWindow` removes `chooseSong`, `invokeOpenSong`, `m_openSongAction`, and the `QInputDialog` include. The replacement Find Song `QAction` attaches to existing `keymap::Registry` ID `songs.find` (`src/ui/keymap.cpp`) and calls `applicationSession.songList.focusSearch()`; the resulting `searchFocusRequest` focuses and selects all in the QML search field. Keep the window-scoped `transport.play_pause` Space action working while the list/search has focus.
- Dock and filter persistence uses `QSettings` keys `swiftDock/columnWidth`, `songList/search`, `songList/sortIndex`, and `songList/category`. Restore/persist root `columnWidth` (default 280, user drag clamp 200–480), `searchText`, `sortIndex`, and `categoryPrefix`.
- Add these `GridPalette` properties for the item-view roles consumed by `SongsPanel`: `itemBackground`, `itemAlternateBackground`, `itemText`, `itemOutline`, `itemHoverBackground`, `itemHoverText`, `itemSelectedBackground`, and `itemSelectedText`. Push them from the matching existing `themes::Role` values in `RewriteWindow::applyGridPalette`: `item_background`, `item_alternate_background`, `item_text`, `item_outline`, `item_hover_background`, `item_hover_text`, `item_selected_background`, and `item_selected_text`. Incomplete-registration text retains the native amber `#C08030`.

## Implementation steps

1. Implement the QML panel: search/clear, category and sort controls, count, visible-row selection and activation, selected/current rendering, and the existing Open/Open in New Tab context actions. Handle Up/Down/PageUp/PageDown from both the list and the focused search field by moving `ListView.currentIndex` (one row for Up/Down, one visible page for PageUp/PageDown) and calling the presenter's existing `selectSong(songId:)`; Enter calls `activateSelection()`. Observe `searchFocusRequest` to focus the search field and select all, and `revealRequest` / `revealSongId` to scroll the current row into view. Ignore bare Space at `ShortcutOverride` before the search field handles text so the window-level transport shortcut receives it; Space must not be inserted into the query.
2. Add Register Song for rows where `presenter.canRegister(songId)` is true and Delete Song for listed rows. Wire both through the presenter's existing intent closures. Display the service plans in QML confirmation dialogs; Confirm calls the matching session method, Cancel calls the cancel method, and neither path fabricates a service result. Refresh the listing only after a successful service mutation.
3. Place the Songs panel in a shell-level left column; re-anchor `SongTabs` in the remaining area without changing tab/editor composition. Expose root `columnWidth` with a 280 fallback and clamp drag updates to 200–480.
4. Replace `RewriteWindow`'s Open Song action/popup with Find Song, preserve the `songs.find` and `transport.play_pause` keymap IDs, restore/persist the specified `QSettings` values, and add the item-view role mappings to the existing palette push. `songs.find` calls the existing presenter `focusSearch()`; QML consumes the ensuing `searchFocusRequest`.
5. Add these slots to `SwiftRollGatedTest`: `songListPanelNavigationAndTabPolicy` (real `gridcheck::NativeScene`); `songListMutationConfirmations` (before opening the isolated scratch project, stage a readable `include/constants/songs.h` for the existing fixture songs using the pattern in `src/checks/songlist/songlist_service.swift`; then copy fixture `sound/songs/midi/mus_route101.mid` to `mus_stray_test.mid` without adding its registration row or constant. Assert registration-plan details, cancel leaves it unregistered, Confirm registers and refreshes it, deletion-plan details, Cancel leaves it registered, then Confirm removes the MIDI/registration, refreshes it out of the list, and closes only its matching tab while the unrelated `mus_route101` tab remains); `songListFindKeyboardAndSpacePriority` (actual `RewriteWindow`: trigger the `songs.find` action, assert `searchFocusRequest` advances and the QML search field focuses/selects all, test each arrow key from search against list selection and page movement, then press bare Space and assert the transport action fires without changing the query); and `songListDockSettingsRoundTrip` (actual host reopened with isolated `QSettings`, asserting the user `columnWidth` and filters persist).

## Acceptance predicate

- `deno task verify --filter swiftrollgated --verbose` passes `songListPanelNavigationAndTabPolicy`, `songListMutationConfirmations`, `songListFindKeyboardAndSpacePriority`, and `songListDockSettingsRoundTrip` in the native `swiftrollgated` harness. These assert service-backed plan details, cancel/no-mutation and confirmed mutation outcomes, refreshed rows and matching-tab behavior, Find Song focus/select-all, search-to-list Up/Down/PageUp/PageDown routing, Enter activation, bare-Space transport priority without search insertion, and the isolated QSettings round-trip.

## Task-specific constraints

- Do not create a second presenter or a new service bridge; do not replace the existing service plan/mutation APIs with UI-side file edits.
- Remove the temporary `songCount()`, `songLabel(index:)`, and private `labels` cache in this task as part of removing native `RewriteWindow::chooseSong()`; task 2 migrates the QML diagnostic to `songList.rows` while retaining these legacy accessors/cache for the still-live native chooser.
- Do not scaffold a new-song wizard or a future voicegroup dock section. Keep Register and Delete visible/functional according to the plan above; no placeholder or disabled replacement actions.
- Do not edit `SongTabs.qml` or per-tab `EditorSurface` composition unless the root re-anchor proves a direct change necessary.
- Keep root `columnWidth` user-controlled and persist only that user value. Neither the Songs panel nor editor actions may force the dock wider; editor content must adapt at the default 280 width without rewriting the saved width.
