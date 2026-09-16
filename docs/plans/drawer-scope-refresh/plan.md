# Drawer scope refresh — delete DrawerPageLiveState snapshots and DrawerLiveDelta diffs

`SongView::drawerPageLiveState()` (`src/ui/songview/drawercoordination.cpp:122-132`) pushes a
seven-field `DrawerPageLiveState` snapshot into every drawer page on every refresh; each page
hand-compares the fields against its stored `m_live`/`m_liveState` to classify the change
(`automationpage.cpp:109-138`, `velocityarea.cpp:102-154`, `voicechangearea.cpp:140-184`).
Replace the push/diff model with scope-signals: every existing `refreshDrawerPages` /
`refresh*Page` call site already knows *why* it is refreshing, so it passes a scope set, and
each page reads the live sources it needs inside the handler. `DrawerPageLiveState`,
`DrawerPagePlaybackState`, `sameLiveState`, every `m_live`/`m_liveState` member, and the
`liveState()` accessor are deleted. Pages store no per-page live state.

## Behavior

- No user-visible change. Scroll still shifts presentation only; playhead presentation still
  goes through `presentPlayhead`; document/track/selection changes still rebuild.
- Simultaneous-change ordering is **defined**, not preserved: when one refresh carries
  several scopes, handlers run structural (`Document`, `Content`, `Selection`) before
  geometry (`HorizontalScroll`, `Zoom`) before transient (`Playhead`). A content rebuild
  re-reads every live source, so a scroll handled before or after a rebuild is at most one
  wasted presentation shift, never a wrong frame.
- The scroll-frame budget is unchanged: a `HorizontalScroll`-only refresh never rebuilds
  content. Proof: `VelocityAreaDiagnostics::contentBuildCount` stays flat across scroll and
  playhead drives (`host-integration` playhead sweep at
  `src/checks/host/tst_hostintegration.cpp:189-196`, `host-adapter` at
  `tst_hostadapter.cpp:606-612`, `drawerpresentation` velocity at
  `src/checks/drawerpresentation/velocity.cpp:616-622`), and `timelinepancheck` /
  `timelinepan-native` exercise the pan path end-to-end.

## Scope-signal contract

New flag enum in `src/ui/editordrawer/drawerpage.h` (replaces the deleted structs' home):

```cpp
enum class DrawerScope : quint8 {
    Document        = 1u << 0, // SongDocument revision changed (documentChanged fan-out)
    Content         = 1u << 1, // primary track, track scope, edit cursor, view state,
                               // voice-context crossing, page-initiated full refresh
    Selection       = 1u << 2, // note/time selection changed without a document edit
    HorizontalScroll= 1u << 3, // camera scrollX changed
    Zoom            = 1u << 4, // camera pxPerBeat changed (with or without scroll)
    Playhead        = 1u << 5, // playhead tick or playing flag changed
};
Q_DECLARE_FLAGS(DrawerScopes, DrawerScope)
```

Emission points (existing call sites, scope substituted for today's implicit diff):

| Call site | Scopes |
|---|---|
| `SongView::onDocumentChanged` → `refreshDrawerPages` (`songview.cpp:809`) | `Document` |
| `SongView::setEditCursorTick` (`songview.cpp:1175`) | `Content` |
| `coordinateSelectionChange` note-selection → `refreshVelocityPage` (`songview.cpp:990`) | `Selection` |
| `coordinateSelectionChange` time-selection → `refreshAutomationPage` (`songview.cpp:999`) | `Selection` |
| `coordinateSelectionChange` primary/trackScope → `refreshDrawerPages` (`songview.cpp:1002`) | `Content` |
| `setPlayheadSample` voice-context crossing → `refreshVelocityPage`/`refreshVoiceChangePage` (`songview.cpp:1087-1090`) | `Content` |
| `refreshViewportLayout` (`songview.cpp:257`) | `HorizontalScroll \| Zoom` (viewport clamp can move either) |
| `syncHorizontalCamera` (`camera.cpp:100`) | `HorizontalScroll` |
| `setEditorTimeZoom` / `zoomTimelineAtWheel` / `zoomAroundContentX` tails (`camera.cpp:42,60`) | `Zoom` |
| `setGridMinDenom`/`setGridFeel` tail (`grid.cpp:385`) | `Content` |
| `setFollowPlayhead` (`viewstate.cpp:204`) | `Content` |
| `applyEditorViewStateToWidgets` → `refreshAllDrawerPages` (`viewstate.cpp:232`) | `Content` |
| `SongView::applyViewState` grid-changed tail (`songview.cpp:907`) | `Content` (same change class as `grid.cpp:385`) |
| `SongView::zoomKeyHeight` tail (`camera.cpp:80`) | `Zoom` (camera-scale change) |
| `EditorDrawer::publishViewState` (`editordrawer.cpp:218`) | `Content` (drawer view-state publish; found during task 1, was a plan defect) |

`setPlayheadSample` keeps calling `presentPlayhead` directly (`songview.cpp:1092-1095`);
`Playhead` scope exists for the combined-refresh tail, not a new routing path.

Per-page handler mapping (priority order: Document > Content > Selection > Zoom >
HorizontalScroll > Playhead; first matching arm wins, `presentPlayhead` tail always runs):

- **VelocityArea::refresh(DrawerScopes)**: `Document` → `cancelInteraction` + rebuild
  (matches `documentChanged`); `Content`/`Selection`/`Zoom` → interaction-preserve when
  `m_interaction != None && revision unchanged` (live-read `m_owner.document().revision()`
  vs a captured `m_documentRevision` taken at gesture start — see task 2), else
  `cancelInteraction` + `rebuildVisualState`; `HorizontalScroll` → resolve hover/current
  context as `velocityarea.cpp:113-121` does today; if it equals `m_axis.map()`, present
  playhead and return, else fall through to rebuild; `Playhead` → `presentPlayhead` plus
  rebuild when `m_owner.playing()` differs from the last-seen flag (replaces the
  `playback.playing` comparison at `velocityarea.cpp:140`).
- **VoiceChangeArea::refresh(DrawerScopes)**: recapture `m_engineTrack = primaryTrack()`
  first (unchanged, `voicechangearea.cpp:145-147`); `Document` or track-changed →
  `cancelInteraction` + `rebuildVisualState`; `Content`/`Zoom` → pan-preserve when
  `m_interaction == Pan && revision unchanged`, else cancel + rebuild; `HorizontalScroll` →
  present playhead, return; `Playhead` → `presentPlayhead`.
- **AutomationPage::refresh(DrawerScopes)**: `Document`/`Content`/`Zoom` → `preservePan`
  check (`m_canvas->isPanning()` && revision unchanged && view state unchanged) →
  `requestFullQuickUpdate`, else `rebuildRows`; `Selection` → `rebuildViewModel` +
  `requestSelectionQuickUpdate`; `HorizontalScroll` → return (Quick `HorizontalPan` layer
  already shifts); `Playhead` → no-op (automation has no playhead presentation today).

## Live-source map (snapshot field → live read)

| Field | Live source | Evidence |
|---|---|---|
| `documentRevision` | `m_owner.document().revision()` / `m_page.document().revision()` | `drawercoordination.cpp:125`; `SongDocument::revision()` `src/core/songdocument.h:144` |
| `timeZoom` | `m_camera.pxPerBeat()` | `drawercoordination.cpp:126`; `timecamera.h:40` |
| `horizontalScroll` | `m_camera.scrollX()` | `drawercoordination.cpp:127`; `timecamera.h:41-43` |
| `editCursorTick` | `m_owner.editCursorTick()` | `drawercoordination.cpp:128`; `songview.h:278` |
| `trackColor` | `SongView::trackColor(m_owner.selectionModel().primaryTrack())` | `drawercoordination.cpp:129`; `trackvoiceops.cpp:123-126` |
| `playback.playheadTick` | `m_owner.playheadTick()` | `drawercoordination.cpp:130`; `songview.h:272` |
| `playback.playing` | new `SongView::playing()` accessor over `m_playing` | `drawercoordination.cpp:130`; `songview.h:947` (no getter today) |

Non-refresh `m_live` reads and their replacements:

- `velocityarea.cpp:322-323` `currentContext()` → `m_owner.playing() ? drawerContextTick(m_owner.playheadTick()) : m_owner.editCursorTick()`.
- `velocityarea.cpp:220` `presentPlayhead` write → drop; `m_lastPresentedPlayheadTick` already dedupes.
- `velocityarea_interaction.cpp:317-320` pan → `m_camera.scrollX()` for both the request base and the post-scroll read (the write-back to `m_live` dies with the member).
- `voicechangearea.cpp:222,227` `presentPlayhead` → `m_owner.playing()` for the gate; drop the `m_live` write.
- `voicechangearea.cpp:516-519` pan → `m_camera.scrollX()`.
- `automationcanvas.cpp:144,158` → `m_page.document().revision()` (accessor already exists, `automationpage.h:68`); `liveState()` accessor deleted.
- `automationcanvas_input.cpp` already reads `m_page.scrollX()` (`:44,46,173`) — no change.

## Camera notification decision

**Route scope-signals through the existing SongView fan-out; do not signal-ify TimeCamera.**
`TimeCamera` is a plain value class owned as a `SongView` member (`songview.h:944` area;
`timecamera.h:13` documents "never notifies anyone — mutators report change, the host
redraws"). Every mutation already funnels through `SongView` wrappers
(`camera.cpp:29-158`, `songview.cpp:275-276,348,894-902`, `viewstate.cpp:170`), and each
wrapper already runs the drawer refresh tail — the emission points above are exactly those
tails. Making `TimeCamera` a `QObject` would add a second notification convention beside the
established bool-return + host-fan-out seam and buy nothing: no page outlives or out-owns
the camera, and no caller mutates it except through `SongView`.

## Coalescing contract

- Scene work batches to the existing Quick flush: `TimelineQuickView::requestUpdate` /
  `requestTimelineUpdate` / `requestAutomationUpdate` OR into pending sets and restart the
  single-shot zero-interval `m_flushTimer` (`timelinequickview.cpp:117-120,835-852`);
  `flushUpdate` dispatches one sync per dirty band (`timelinequickview.h:327-339`). Page
  handlers keep requesting dirty flags through `requestTimelineQuickUpdate` /
  `requestAutomationQuickUpdate` / `requestQuickUpdate`; they never paint synchronously.
- Document side: `SongDocument::documentChanged` is emitted once per committed mutation and
  `SongView::onDocumentChanged` (`songview.cpp:797-810`) is the single synchronous fan-out —
  pages' `documentChanged()` then `refresh(Document)`. This is already one emission per
  commit; no new coalescing is needed or added.
- Scroll: `syncHorizontalCamera` emits `HorizontalScroll` once per camera change; the Quick
  `HorizontalPan` dirty bit coalesces per frame in the flush timer, so a wheel burst costs
  one scene shift per frame regardless of event count.

## Tasks

| # | Task | Route |
|---|---|---|
| 1 | Scope enum + SongView fan-out rewrite (drawerpage.h, drawercoordination.cpp, camera.cpp, songview.cpp, grid.cpp, viewstate.cpp, songview.h) | SDD-track — multi-file routing contract; seat `sdd-implementer` |
| 2 | VelocityArea + VoiceChangeArea live-read rewrite (velocityarea.{h,cpp}, velocityarea_interaction.cpp, voicechangearea.{h,cpp}) | SDD-track — interaction-preserve semantics; seat `sdd-implementer` |
| 3 | AutomationPage/Canvas live-read rewrite + check-fixture migration (automationpage.{h,cpp}, automationcanvas.cpp, rasterfixture.{h,cpp}, drawerpresentation fixtures/velocity, automationcanvasediting) | SDD-track — crosses production + harness seams; seat `sdd-implementer` |

Tasks are serial: 2 and 3 consume task 1's `refresh(DrawerScopes)` signatures; task 3 also
migrates the check-side `refreshLiveState` drivers that would not compile after task 2.

## Global Constraints

- Every task inherits this section. Write sets are closed; preserve unrelated changes.
  Refresh source sections before editing. An unlisted production file the compiler names is
  a plan defect — escalate, do not expand.
- Scope priority is fixed: structural (`Document`, `Content`, `Selection`) > geometry
  (`Zoom`, `HorizontalScroll`) > transient (`Playhead`). Handlers evaluate arms in that
  order; never re-derive ordering from field comparisons.
- No stored per-page live state: no `m_live`, no snapshot member, no field-diff helper.
  Pages read `m_owner`/`m_camera`/`m_page.document()` inside the handler. The one permitted
  retained value is a gesture-start `documentRevision` capture where today's semantics
  compare "revision unchanged since gesture began" (velocity interaction-preserve,
  voice pan-preserve, automation preservePan) — that is gesture state, not a live snapshot.
- No second notification convention: camera stays bool-return; scopes travel on the
  existing `refreshDrawerPages`/`refresh*Page`/`refreshAllDrawerPages` fan-out. Do not add
  signals to `TimeCamera`, do not add a parallel callback registry.
- Scroll handling shifts presentation only: a `HorizontalScroll`-only refresh MUST NOT call
  `rebuildVisualState`/`rebuildRows`/`rebuildViewModel` on any page.
- `presentPlayhead` stays the sole playhead-presentation entry point and keeps its
  `m_lastPresentedPlayheadTick` dedupe.
- Use `deno task` for format/build/harness. Implementers reuse the Verification policy
  commands without repeating discovery; reassess only if the change alters scope or a
  command proves stale or unavailable, reporting the concrete mismatch.

## Verification policy

- Build: `deno task build:checks`.
- Task 1: `deno task verify --filter editor-drawer --filter scrollbar --verbose` — fan-out
  rewiring with pages still on the old entry points is proven by keeping a thin
  `refreshLiveState` forwarder until task 2/3 land (see task 1 brief); these two harnesses
  cover drawer surface lifecycle and scroll routing.
- Task 2: `deno task verify --filter velocity-page --filter velocity-editing --filter drawerpresentation --filter timelinepancheck --filter host-adapter --filter host-integration --verbose` — velocity/voice rebuild-vs-preserve arms, scroll-frame budget counters, pan path.
- Task 3: `deno task verify --filter automation-editing --filter automation-presentation --filter automation-hover --filter automation-raster --filter editor-drawer --verbose` — automation refresh arms plus the migrated fixtures themselves.
- Final sweep (controller, after all tasks settle): `deno task verify --filter scrollbar --filter timelinepancheck --filter drawerpresentation --filter velocity-page --filter automation-presentation --verbose`.

## Risks

- **Negative playhead seam.** `automationcanvasediting.cpp:219-222` injects
  `playback = {-3.0, true}` through `refreshLiveState`; `setPlayheadSample` takes
  `uint64_t` samples and cannot express a negative tick. Task 3 must drive the same oracle
  through `VelocityArea::presentPlayhead(-3.0)` (public, `velocityarea.h:58`) or an explicit
  test seam — decide in the brief, do not leave a live-state-shaped backdoor.
- **Interaction-preserve without a snapshot.** The velocity arm at `velocityarea.cpp:129-134`
  compares "revision unchanged since the gesture's last refresh". With no `m_live`, the
  gesture-start revision must be captured at `beginFrozenGesture`/pan start; capturing at
  the wrong moment silently turns preserve into rebuild (or vice versa). Task 2 brief names
  the capture points.
- **`playing` toggle detection.** `m_playing` flips inside `setPlayheadSample`
  (`songview.cpp:1070`) which bypasses `refreshDrawerPages` for the common case; the
  `Playhead` arm's "playing changed → rebuild" needs a last-seen flag on the page
  (`m_lastPlaying`), updated in `presentPlayhead`. Voice's `presentPlayhead` gate
  (`voicechangearea.cpp:222`) reads `m_owner.playing()` live instead.
- **Viewport/layout refresh scope.** `refreshViewportLayout` (`songview.cpp:253-264`) fires
  on resize/DPR where scroll may clamp; emitting `HorizontalScroll|Zoom` there preserves
  today's "refresh everything that moved" behavior without a rebuild — verify no page
  treats that pair as content.
- **Check fixtures.** `rasterfixture.{h,cpp}` and `drawerpresentation/fixtures.cpp` build
  `DrawerPageLiveState` by hand; they must drive `view.setEditCursorTick`,
  `setEditorTimeZoom`, `setEditorHorizontalScroll`, `setPlayheadSample` (or
  `presentPlayhead`) so the production fan-out produces the scopes — no fixture-side scope
  fabrication beyond calling the real entry points.
