# task-2-brief.md — Wire the existing song-list presenter into the session

## Context

The rewrite already has `src/swift/app/songlist/SongListPresenter.swift`. It owns the Songs list model keyed by stable `songId`, filters playable listings, publishes the current row, and exposes `setSongs(_:)`, `activateSelection()`, `requestOpen(songId:)`, and `requestOpenInNewTab(songId:)`. This task completes the missing `ApplicationSession` feed and navigation wiring; it does not create or port another presenter.

## Exact write set

- `src/swift/app/ApplicationSession.swift` — own the existing presenter, feed it from the active `ProjectService`, and synchronize current-song identity; leave `songCount()`, `songLabel(index:)`, and the private `labels` cache in place because native `RewriteWindow::chooseSong()` still consumes them until task 3 removes that caller.
- `src/checks/editorqml/tst_EditorDrawer.qml` — migrate the staged-label failure diagnostic to the presenter's row model and assert the real open song's stable selected/current identity.

## Prerequisites

Task 1's existing `ProjectService.songs()` / `SongListing` feed.

## Interface contract

- Preserve the presenter at `src/swift/app/songlist/SongListPresenter.swift`; its row identity is `SongListRow.songId`, not a label-derived ID. Its existing `setSongs(_ newSongs: [SongListing])`, `listing(songId:)`, `activateSong(songId:)`, `activateSelection()`, `setCurrentSong(songId:)`, `restoreFilters(search:sort:category:)`, `focusSearch()`, `searchFocusRequest`, `revealRequest`, and `revealSongId` remain the API.
- `ApplicationSession.songList` is the same presenter instance for the session lifetime. On project replacement, call `ProjectService.songs()` and pass the new project's complete listings to `setSongs(_:)` only after the replacement succeeds.
- Synchronize `currentSongId` from the selected `SongTabsController` page's label to the matching listing ID; clear the presenter current ID when no page is selected. Do not synthesize identity from list position or label.
- Route `onSongActivated` and `onSongOpenInNewTabRequested` by resolving the supplied ID with `listing(songId:)`, then call the existing `openSong(label:)`. This preserves existing activation/reload, focus-existing-tab, and one-tab-per-label behavior.
- Keep `ApplicationSession.songCount()`, `songLabel(index:)`, and its private `labels` cache during this task: native `RewriteWindow::chooseSong()` still calls them. Task 3 removes the native chooser and these compatibility methods/cache together. `ProjectService.songLabels()` remains a separate existing service API and is not a replacement presenter feed.

## Implementation steps

1. Construct `@QtTracked public var songList: SongListPresenter` in `ApplicationSession.init` before tab attachment. Wire the presenter's two open callbacks to the ID-resolution path above.
2. In `replaceProject`, obtain `[SongListing]` from the replacement service once. While the native chooser still needs its compatibility cache, derive `labels` from that same result with `newSongs.map(\.label)`; publish the full listing to `songList.setSongs(_:)` only as part of successful project replacement. Leave the prior project's feed and cache intact if opening the replacement fails.
3. In the existing tab-selection publication path, update the presenter's current song from the selected page title; clear it when there is no selected page.
4. In the existing QML drawer test, replace `stagedLabels()`'s `songCount()` / `songLabel(index:)` loop with a `Repeater` over `session.songList.rows`, reading its `label` role and preserving the first-eight/ellipsis diagnostic. After the real `mus_route101` project/song bootstrap, find that row and assert its `songId` equals both `session.songList.selectedSongId` and `session.songList.currentSongId`, with the row visibly selected and current. Exercise `session.songList.focusSearch()` from QML and assert `searchFocusRequest` advances, proving the session exposes the presenter's existing focus handoff.

## Acceptance predicate

- `deno task verify --filter swiftcore --verbose` passes the existing `swiftcore/SongList::*` presenter and service proofs.
- `deno task verify:qml` passes the editor-drawer assertions that the staged `mus_route101` row is selected/current by its stable song ID and that the existing `focusSearch()` → `searchFocusRequest` handoff is exposed.

## Task-specific constraints

- Do not create `SongEntry`, `setEntries`, a second presenter, a new service bridge, a new Swift check file, or redundant `SessionChecks`/CMake registration; the presenter and its proofs already exist.
- Migrate the QML diagnostic to `songList.rows`, but retain `songCount()`, `songLabel(index:)`, and the private `labels` cache until task 3 removes them in the same cutover as native `RewriteWindow::chooseSong()`.
- Do not edit `SongTabsController` or change its one-tab-per-label policy.
