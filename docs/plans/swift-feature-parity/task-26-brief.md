# Context

Event List visual parity, divergence items 6 and 7 (verified table:
`agent://InventoryVerify/report`; fork-main = `fceecd88`, reference captures
`/tmp/porydaw-qwidget-ref/b-event-list.png` vs `/tmp/porydaw-swift-ref/b-event-list.png`).

1. **Chunk combo label (item 6).** Swift `EventListPresenter.rebuildFromDocument`
   hardcodes `index == 0 ? "0: Tempo / metadata" : "\(index): MIDI chunk"`
   (src/swift/app/eventlist/EventListPresenter.swift:386-389). Fork-main
   `EventListController::rebuildChunks` builds one label per raw SMF chunk:
   the first engine track whose `smfTrackFor(track) == chunk` yields
   `tr("Chunk %1 — Track %2").arg(chunk).arg(engineTrack + 1)` (em dash U+2014,
   bytes `e2 80 94`), otherwise `tr("Chunk %1 (tempo/meta)").arg(chunk)`
   (`git show fceecd88:src/ui/songview/quick/eventlistcontroller.cpp` lines
   251-270). `%1` is the raw chunk index, `%2` is the 1-based engine track.
   The combo shows `chunkLabels[chunk]`
   (fork `src/ui/songview/quick/EventListPage.qml` lines 670-681) and the
   chunk menu rows reuse the same labels (`rebuildChunkMenu`, same file lines
   1030-1043); Swift already mirrors both consumers
   (src/ui/songview/quick/EventListPage.qml:690-692,
   src/swift/app/eventlist/EventListMenus.swift:68-76), so only the formatter
   diverges. Labels rebuild on document change / track remap
   (eventlistcontroller.cpp:361-385) and the chunk follows the selected track
   (387-397, 326-346) — Swift already does both
   (EventListPresenter.swift:153-167, 353-358). For `mus_route101` (conductor
   chunk 0 meta-only, chunks 1-2 = engine tracks 0-1) the expected labels are
   `Chunk 0 (tempo/meta)`, `Chunk 1 — Track 1`, `Chunk 2 — Track 2`; the
   reference capture's combo reads `Chunk 1 — Track 1`.
2. **Event List placement (item 7).** Swift `SongTab.qml` swaps the whole
   surface: the editor Loader goes inactive and an `EventListPage` Loader
   fills the tab (src/ui/songview/quick/swiftroll/SongTab.qml:34-57), which
   unmounts ruler, track headers and the drawer. Fork-main shows the list
   **in place of the roll band only**:
   - `SongView::eventListRect()` returns `resolveViewportGeometry().rollStack`
     — `{trackHeaderWidth, rulerHeight, viewportWidth - trackHeaderWidth,
     rollPaneHeight}` — empty while hidden
     (`git show fceecd88:src/ui/songview.cpp` lines 191-196, geometry at
     218-238). So the band covers everything right of the track-header column,
     below the ruler, including the keyboard column and the roll scrollbar
     lane; it does not touch ruler, headers or drawer.
   - The roll band is published only `if (!m_eventListVisible)`
     (songview.cpp:141-150); ruler (132), track headers (133-136) and the
     drawer bands (154-164) publish unconditionally, and the drawer's
     `setEventListVisible` never touches the drawer (songview.cpp:820-831).
     The keyboard lives in the roll band's gutter, so it disappears with it.
   - The vertical roll scrollbar lane is empty without a roll band
     (songview.cpp:179-186); the horizontal scrollbar row stays
     (172-177 unconditional).
   - The drawer overlay stays bottom-anchored in the roll pane at full width
     (`git show fceecd88:src/ui/editordrawer/editordrawer.cpp` lines 106-123)
     and renders above the list (`DrawerChromeLayer` z: 20, fork
     `src/ui/songview/quick/TimelineCanvas.qml` lines 723-731 vs `eventListHost`
     z: 0 at 264-292), so velocity/automation stay visible below the list and
     their collapse/expand keeps working (splitter behavior unchanged: the
     list band never resizes with the drawer; fork occludes rows beneath the
     opaque overlay instead).
   - The playhead/guides never paint the list band: the playhead's band list
     excludes the event list (TimelineCanvas.qml:570-578) while the ruler
     triangle and drawer segments remain.
   - Focus: show focuses the event list input, hide refocuses the roll band
     (songview.cpp:833-847); view-state restore re-runs the same path (919).

# Exact write set

- `src/swift/app/eventlist/EventListPresenter.swift` — the `chunkLabels`
  computation in `rebuildFromDocument` only (reuse `firstEngineTrack`,
  lines 372-378; no new lookup, no other edit).
- `src/ui/songview/quick/swiftroll/SongTab.qml` — remove the event-page
  Loader, the `active: !root.showEvents` exclusion and the
  `onShowEventsChanged` block (moves into EditorSurface).
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — mount the
  `EventListPage` host inside `rollBandContent` below the ruler; gate roll
  gutter/plot/content-band visibility and the roll vertical scrollbar; own the
  presenter-visible/focus choreography.
- `src/ui/songview/quick/swiftroll/SharedPlayhead.qml` — one
  `rollBodyVisible` style property gating the roll body line and the two roll
  guide segments; ruler triangle and drawer segments unchanged.
- `src/checks/eventviews/EventListPageChecks.swift` — chunk-label predicates.
- `src/checks/editorqml/tst_ShellEventList.qml` — combo-label and mounted
  layout/visibility predicates.

# Prerequisites

Sequence after task 22 (owns `src/swift/app/eventlist/*`,
`src/ui/songview/quick/EventListPage.qml`, `EventListPageChecks.swift`,
`tst_ShellEventList.qml`, `ApplicationSession.swift`) — this brief edits the
same presenter and check files. Task 24 (ShellPresenter/ShellWindow/
GridPalette roles) and Brief25Colors are disjoint: no palette, shell or
appearance edits here. Task 27 (Other-events band) also edits
`EditorSurface.qml` (`rollBandContent.height`, `configureViewport`): sequence
task 27 after this brief — the event-list host anchors to
`rollBandContent`'s height below the ruler and composes with that change.

# Interface contract

- Chunk labels: exactly `Chunk \(chunk) — Track \(engineTrack + 1)` (U+2014)
  for the first engine track whose `midiChunk == chunk`, else
  `Chunk \(chunk) (tempo/meta)`; one label per `document.rawChunks` index,
  rebuilt by the existing `rebuildFromDocument` paths (document change, remap,
  selection-driven chunk change). Combo label and chunk-menu rows consume
  `chunkLabels` unchanged.
- Layout: with the list shown, `eventListPage` fills the rect
  `{x: trackHeaderWidth, y: rulerHeight, width: surfaceWidth -
  trackHeaderWidth, height: rollBandHeight - rulerHeight}` in surface
  coordinates (rollBandHeight = the roll column the drawer leaves). Ruler
  band (with the grid division/feel gutter controls), track headers, drawer
  (all sections, interactive), horizontal scrollbar and hint status stay
  visible; `timelineQuickRollGutter`, `swiftRollInput`/`rollPlot`,
  `rollContentBand` and the roll vertical scrollbar (`externalVisible`) hide.
  Toggling off restores the roll exactly (camera state untouched).
- Drawer interplay: the drawer keeps its geometry and input while the list
  shows; no occlusion band is added (Swift's host stops at the drawer top —
  pixel-identical to fork's under-overlay extension, which is invisible).
- Playhead: no playhead line or edit/hover guide pixels inside the list band;
  the roll triangle at the ruler edge and all drawer segments/guides remain.
- Focus: on show, `presenter.setVisible(true)` then the page takes focus
  (Qt.callLater as today); on hide, `presenter.setVisible(false)` and
  `rollInput` regains focus; a tab restored with `showsEvents == true`
  focuses the page on mount (fork songview.cpp:919 → 833-847).
- Checks assert the exact fixture strings and relative geometry (page edges vs
  published `trackHeaderWidth`/`rulerHeight`/`editorDrawer.y`), never pixel
  constants; predicates use `waitForNative`.

# Implementation steps

1. Write the failing predicates first (label strings; mounted layout and
   visibility matrix); record the RED output.
2. Replace the `chunkLabels` formatter with the fork rule via
   `firstEngineTrack`; verify the `mus_route101` combo reads
   `Chunk 1 — Track 1`.
3. Move the mount: add the host + Loader in `EditorSurface`, gate the roll
   surfaces and vertical scrollbar, move the visible/focus choreography;
   strip the swapped Loaders from `SongTab.qml` (drop the orphaned comment
   lines that describe the removed block).
4. Gate the SharedPlayhead roll body/guides on the new property.
5. Run the lanes below; report GREEN with predicate strings and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:shell --filter shell-event-list --verbose`
- `deno task verify:shell --filter shell-menus --verbose`
- `deno task verify:shell --filter shell-tabs --verbose`
- `deno task verify:qml-roll --verbose`
- `deno task verify:qml --verbose`
- `deno task verify:bridge`
- Controller visual acceptance: relaunch per skill
  `porydaw-qwidget-reference-capture`, capture the Event List in the reference
  theme, and compare against `/tmp/porydaw-qwidget-ref/b-event-list.png`:
  chunk combo text, list replacing only the roll/keyboard area, drawer and
  ruler/headers still visible.

# Visual parity

Counterpart: fork-main `fceecd88` `src/ui/songview.cpp`
(`eventListRect`, `resolveTimelineBandLayout`, `resolveViewportGeometry`,
`setEventListVisible`, `focusContent`), `src/ui/songview/quick/
TimelineCanvas.qml` (`eventListHost`, playhead bands, drawer chrome layer),
`src/ui/editordrawer/editordrawer.cpp` (`overlayRect`),
`eventlistcontroller.cpp` (`rebuildChunks`, `rebuildChunkMenu`), fork
`EventListPage.qml` toolbar. Reference capture:
`/tmp/porydaw-qwidget-ref/b-event-list.png`. Known remaining differences out
of scope here: row height / Data column proportions (task 22 scope note),
missing Other-events strip below the drawer (task 27), track-header-adjacent
ruler span (fork's ruler rect spans the full window width over the header
column, songview.cpp:132 — pre-existing Swift layout difference; report it in
the capture comparison, do not fix here).

# Task-specific constraints

- No new UI surfaces, no new C++, no code comments, no pixel constants.
- Geometry only from published presenter values (`trackHeaderWidth`,
  `rulerHeight`, drawer height); the host adds no font math.
- No palette/role edits; text contrast work stays in task 22.
- No proof ledger edits by the implementer. No ledger row pins the chunk-label
  strings or the band layout; nearest rows (A004 ff. in
  `src/checks/eventviews/proof.chrome.txt`, chunk-follows-track) pin behavior
  this task does not change — the controller's ledger agent may separately
  refresh GAP dispositions whose reason cites an unmounted EventListPage.
