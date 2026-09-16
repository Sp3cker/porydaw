# Task 3 — AutomationPage/Canvas live reads, struct deletion, fixture migration

## 1. Context

Consumes task 1's scoped fan-out and completes the cutover task 2 began: AutomationPage
switches to `refresh(DrawerScopes)` with live reads, `AutomationCanvas` reads
`m_page.document().revision()` directly, and `DrawerPageLiveState`,
`DrawerPagePlaybackState`, `sameLiveState`, `liveState()`, `m_liveState`, and
`SongView::drawerPageLiveState()` are deleted. The check fixtures that hand-build snapshots
migrate to driving the real SongView entry points so the production fan-out produces the
scopes.

## 2. Exact write set

- `src/ui/editordrawer/drawerpage.h` (delete `DrawerPagePlaybackState`, `DrawerPageLiveState`)
- `src/ui/editordrawer/automationpage.h`, `automationpage.cpp`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/songview/drawercoordination.cpp` (delete `drawerPageLiveState`)
- `src/ui/songview.h` (drop the declaration)
- `src/checks/automation/raster/rasterfixture.h`, `rasterfixture.cpp`
- `src/checks/drawerpresentation/fixtures.cpp`, `velocity.cpp`
- `src/checks/automation/automationcanvasediting.cpp`

## 3. Prerequisites

- Task 1: `DrawerScopes`, scoped fan-out, `SongView::playing()`.
- Task 2: velocity/voice already on `refresh(DrawerScopes)`; the shared struct is now used
  only by automation + fixtures.

## 4. Interface contract

```cpp
// automationpage.h
void refresh(DrawerScopes scopes);            // replaces refreshLiveState
// deleted: liveState() accessor, m_liveState member
// kept: m_viewState (view-state comparison is unrelated to the snapshot)
```

`AutomationPage` gains `uint64_t m_panRevision = 0;` captured when the canvas pan begins —
or, simpler and preferred, the preservePan arm reads `m_canvas->isPanning()` plus a
revision captured at pan start; today's check is `m_canvas->isPanning() && revision
unchanged && !viewStateChanged` (`automationpage.cpp:122-124`). The revision half needs a
capture point: add `AutomationCanvas::panStartRevision()` set where `m_pan.startHScroll` is
captured (`automationcanvas_input.cpp:172-173`), or have the page capture
`document().revision()` on the first refresh that observes `isPanning()`. Pick the canvas
capture — it mirrors the velocity/voice `m_interactionRevision` convention.

## 5. Implementation steps

1. `AutomationPage::refresh(DrawerScopes)` — compute `viewState =
   m_owner.editorViewState()` and `viewStateChanged = m_viewState != viewState`; assign
   `m_viewState` before the arms (as `automationpage.cpp:126` does today). Arms:
   - `Document | Content | Zoom` → if `m_canvas->isPanning() &&
     m_canvas->panStartRevision() == document().revision() && !viewStateChanged`:
     `m_canvas->requestFullQuickUpdate()`; else `m_canvas->rebuildRows()`.
   - `Selection` → `m_canvas->rebuildViewModel()` +
     `m_canvas->requestSelectionQuickUpdate()` (the `!liveChanged && !viewStateChanged`
     arm at `automationpage.cpp:130-132`).
   - `HorizontalScroll` → return (Quick `HorizontalPan` layer shifts presentation).
   - `Playhead` → no-op.
   - `viewStateChanged` with any of the above follows the same arm; a view-state change
     alone (no scope bits beyond `Content`, which `applyEditorViewStateToWidgets` already
     emits) rebuilds rows.
2. Delete `sameLiveState` (`automationpage.cpp:16-…`), `refreshLiveState`, `m_liveState`,
   `liveState()` (`automationpage.h:66`), and the stale comment at `automationpage.h:65`.
3. `automationcanvas.cpp:144` → `target.documentRevision = m_page.document().revision();`;
   `:158` → `const uint64_t documentRevision = m_page.document().revision();`. Add the
   `panStartRevision` capture at `automationcanvas_input.cpp:172-173` (write-set addition:
   `automationcanvas_input.cpp`, `automationcanvas.h`).
4. Delete `DrawerPagePlaybackState` and `DrawerPageLiveState` from `drawerpage.h`;
   `DrawerPageGridState`, `DrawerPageVoiceContext`, `DrawerPageTimeSelectionMenuRequest`
   stay. Delete `SongView::drawerPageLiveState` (`drawercoordination.cpp:122-132`) and its
   `songview.h` declaration.
5. Fixture migration — drive real entry points, never fabricate scopes:
   - `rasterfixture.{h,cpp}`: delete `m_live`; `refreshPage()` calls
     `m_page->refresh(DrawerScope::Content)`; cursor/zoom/scroll setters keep calling the
     `m_view->setEditCursorTick`/`setEditorTimeZoom`/`setEditorHorizontalScroll` they
     already call and drop the `m_live` bookkeeping lines (`:150-152,166-168,316-317,325,
     488-493,500-501`).
   - `drawerpresentation/fixtures.cpp:685-696` `VelocityFixture::refresh` → drive
     `rig->view().setPlayheadSample(...)` when a timeline is bound, else call
     `area->presentPlayhead(playheadTick)` + `area->refresh(DrawerScope::Content)`; the
     `playing` flag needs the same path the production code uses — if the fixture has no
     bound timeline, keep `presentPlayhead` plus a `Content` refresh and note the gap.
   - `drawerpresentation/velocity.cpp:419-424` → `fixture.area->presentPlayhead(inputs[index])`
     plus `refresh(DrawerScope::Content)`; the voice-context oracle reads
     `view.voiceContext(...)` unchanged.
   - `automationcanvasediting.cpp:219-222` negative-playhead oracle →
     `velocity->presentPlayhead(-3.0)` then `velocity->refresh(DrawerScope::Playhead)`;
     `presentPlayhead` is public (`velocityarea.h:58`) and the axis clamp at -3.0 is the
     asserted behavior. If `presentPlayhead` alone does not reach the axis-map oracle,
     drive `refresh(DrawerScope::Content)` instead — pick whichever keeps the QCOMPARE on
     `axis().map()` green; do not resurrect a snapshot-shaped seam.
6. `VelocityArea::refresh`/`VoiceChangeArea::refresh` forwarder bodies from task 1 are
   already replaced; confirm no `refreshLiveState` symbol remains tree-wide:
   `grep -rn 'refreshLiveState\|DrawerPageLiveState\|sameLiveState' src/` must be empty.

## 6. Acceptance predicate

- `deno task verify --filter automation-editing --filter automation-presentation --filter
  automation-hover --filter automation-raster --filter editor-drawer --filter
  drawerpresentation --filter velocity-page --verbose` passes.
  - `automation-raster` proves the migrated raster fixture drives identical refreshes.
  - `automation-editing`/`automation-hover` prove preservePan and selection arms.
  - `drawerpresentation` + `velocity-page` prove the migrated velocity fixtures.
- The grep in step 6 returns nothing.

## 7. Task-specific constraints

- `HorizontalScroll`-only refresh MUST NOT call `rebuildRows`/`rebuildViewModel`/
  `requestFullQuickUpdate` on AutomationPage (Global Constraints).
- Fixtures must call production entry points; a fixture that constructs `DrawerScopes` and
  calls `page->refresh(...)` directly is acceptable only for `Content`/`Playhead` where no
  production entry point exists for the injected condition (negative playhead).
- Do not change `AutomationProjection`, `m_viewState` semantics, or any Quick layer.
