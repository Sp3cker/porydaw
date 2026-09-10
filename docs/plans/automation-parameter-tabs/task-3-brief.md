# Task 3: Replace stacked geometry and drawing with one parameter plot

> Route: SDD-track. Execute through rule://sdd-execution-loop with a brief-first sdd-implementer. Read-only task review follows. This brief authorizes only this task, not adjacent work.

## Context

Replace vertically stacked automation rows with a compact grid of nine clickable labels in the existing left gutter and one active plot. Ordered identities: CC1 Modulation, CC7 Volume, CC10 Pan, CC20 Bend range, CC21 LFO speed, registered XCMD 0xFB Echo volume and 0xFC Echo length, dedicated 0xFF Pitch bend, then song-global Tempo. All are available even without written events. Default Volume. Active parameter is SongTab-local, retained across primary-track changes and open-tab round trips, not application-global or persisted.

## Global Constraints

- Preserve ALL automation-node semantics, especially the origin phantom: held value, source event/tick, paint/hit/hover, vertical drag, cancellation, menus and undo. A phantom edits its original event; never insert a duplicate at the viewport edge.
- Keep all logical adapters and shared selected-node batching. Only drawing, ordinary hover/hit targeting and new band selection use the active parameter. Existing explicit multi-lane selections and command targets survive switching, including unpainted lanes and global Tempo.
- Switching labels creates no event, undo entry, cursor move, selection clearing/retargeting or track change. Cancel provisional gestures and owned stale menus/value prompts before changing identity; preserve foreign popup ownership. Resolve LaneHandle from stable row identity after rebuilds.
- Preserve defaults/implicit lead-in, point-menu/value-prompt behavior, normal drag/modifiers, stationary/delete/double-click guards, pencil/sweep/ramp, snapping, same-tick order, XCMD grouping, signed bend, transaction and lifetime rules. Reuse NodeLane, adapters, projection, gesture and NodeLaneQuickPaint; do not rewrite them.
- Tempo belongs in the shared plot, not a pinned/collapsible header. All nine full labels fit without scrolling/overflow. Qt Text.HorizontalFit, FontMetrics and GridLayout own fitting/sizing; only the at-most-three-column policy is local. Use caption-or-smaller type, fontPx(2/3) floor and layout:: geometry. Bind the grid implicitHeight to the existing minimumContentHeight API; do not change shared DrawerMetrics::minBody or Velocity/Voice Changes sizes/cap/handoff.
- Active tab, shared-selection inclusion and focus have distinct indicators. QML labels own mouse input. Enter/Space activate; normal Tab traversal and unhandled SongView keys remain. No focus memory or second key dispatcher.
- Remove Add/Show/Hide, live empty-row/row-height/vertical-automation-scroll UI and unused UI facades. Leave EditorViewState storage, QSettings codec, track remapping and their tests unchanged; do not delete legacy fields/keys or add a migration. Tabs ignore old visibility/height entries. Retain laneRanges, outer section state and every song event; no unsupported tabs/MIDI reclassification. Other scrolling remains.
- Stay within the write set. Read adjacent declarations/fixtures and refresh LSP references before public API changes. Use LSP rename for cross-file renames. Unexpected semantic consumers outside scope: report NEEDS_CONTEXT for a controller brief; never silently drop them.
- Skip formatters, linters, builds and tests in the implementer. The controller runs coverage after writers settle and API/test migration completes. Never suppress failures or claim obsolete assertions passed. Do not commit, push, create a worktree or spawn agents.
- No unrelated engine/document/shared-key refactor, QWidget fallback, compatibility alias or no-op API. Preserve concurrent user changes. This brief is the implementer's single task source; agreed spec: docs/plans/automation-parameter-tabs/spec.md.
- Line-count note: the controller tracks aggregate new/materially rewritten production lines across the plan and reports the count; there is no numeric limit and no budget-based condition. Implement this brief completely and cleanly without optimizing to any size target, never weakening behavior or tests for size, and include your approximate production-line contribution in the required report (with source/destination evidence for any claimed unchanged-move or formatting-only exclusions).

## Exact write set

- `src/ui/editordrawer/cclanes.cpp`
- `src/ui/editordrawer/automationcanvas.cpp`
- `src/ui/songview/quick/automationquick.cpp`

## Prerequisites

Completed/reviewed tasks: 2.

## Interface contract

Consumes task 2 activeLane(), parameter properties and m_minimumContentHeight. Reuses minimumContentHeight() as the selector minimum rather than adding a parallel API. Keeps `rows()`, `laneBody(LaneHandle)` and all adapter/gesture interfaces intact. Every logical slot receives the same plot rectangle so selected multi-lane edits still have valid value geometry; only activeLane determines visibility/input.

## Implementation steps

### Step 1

Change CCLanes::rebuildRows after the existing ready/primary-track guard to append every supported controller, without consulting model presence, emptyLanes or hidden state:
```cpp
for (const uint8_t controller : supportedControllers())
    appendRow(laneRow(track, controller));
```
Keep adapter points/leadIn/replaceSpan and text-cache construction unchanged. Unsupported legacy presentation rows no longer decide catalog membership.

### Step 2

In rebuildNodeStack retain the Tempo slot and all CC adapters. Use one plot body for every slot:
```cpp
const QRect body = m_inputHost ? m_inputHost->bounds().toAlignedRect() : QRect{};
```
This is plot-local input geometry, not automationViewportSize().width(): the latter is the whole allocated band including gutter. In hostAppearanceChanged compare current input bounds with the existing common body; rebuild geometry only when the size changes, emit parameterPresentationChanged only for the existing host appearance notification, not for paint/pointer refreshes. Gutter width is already a QML geometry binding and needs no C++ measurement notification. TimelineInputItem::geometryChange already invokes hostAppearanceChanged after the actual QML bounds update. This avoids stale pre-publication band widths and does not add another timeline split. Replace top accumulation/per-row height use with that rectangle, including Tempo. laneAt(y) returns activeLane only when y lies within this body. refreshHoverAt resolves that active slot directly; it must not treat Tempo as gutter/header content. Stop calling pinned-tempo layout from scroll/resize paths. Existing minimumContentHeight temporarily returns minimumParameterHeight while the page still owns its old scroll API; those APIs are retired later, not kept as final shims. Refresh label presentation on font/gutter geometry changes and emit parameterSelectionChanged from requestSelectionQuickUpdate; invalidate selection indicators on full row rebuild/track change too.

### Step 3

As part of the real shared-plot cutover, make minimumContentHeight() return m_minimumContentHeight; make content/viewport Y transforms identity and contentBounds use the input-host plot bounds. Keep the existing method names/signatures. Remove pinned layout calls from live layout/scroll-notification paths, preserving their hover/preview/refresh work until their callers migrate in task 4. Do not leave minimumContentHeight dependent on TempoLane::totalHeight or CCLanes::minimumHeight. Notify parameterSelectionChanged from the existing selection refresh and parameterPresentationChanged on document/track rebuild; do not add cached selection membership.

Change rebuildQuickScene visible-lane setup to zero or one active slot; retain the existing node-composition body rather than re-authoring the renderer. Keep the existing Content/Transient/Hover dirty-layer separation. Remove stacked visibility iteration, pinned Tempo clips, collapse/header/add-strip text and `setTempoHeader` publication. Compose the grid once over the viewport. Reuse the existing NodeLaneQuickPaint context, with `body=slot.body`, `plot=viewport`, `overflow=nodelane::nodeOverflowClip(body,m_geometry).intersected(viewport)`, and `contentYOffset=0`. Keep current Tempo versus track color choices; do not redesign node paint.

### Step 4

Preserve the exact phantom handoff and all selected-node gesture data:
```cpp
const auto phantom = phantomGesture && phantomGesture->lane == handle
    ? std::optional<OriginPhantom>{OriginPhantom{handle, phantomGesture->point.current,
          phantomGesture->point.minimumValue, phantomGesture->point.maximumValue}}
    : originPhantom(handle, projection, points);
```
Pass this into the same `.phantom` context field; keep composeStatic/composeTransient/composeHover and the existing value-label clipping path. Clear obsolete automation gutter text records rather than painting old stacked labels. Do not restrict collectSelectedNodeDrags or hasMultipleSelectedNodes to activeLane.

## Acceptance predicate

All eight CC adapters and Tempo remain logically available, while exactly the active parameter is rendered and hit-tested in one full-height plot using the unchanged NodeLaneQuickPaint and phantom algorithms.

## Controller verification

Controller: run `deno task build:app` after this writer settles. Run `deno task verify --filter automation-domain --verbose` for the unchanged adapter/gesture semantics. Do not run old stacked-layout assertions as acceptance for the new layout; their explicit migration tasks and final full coverage remain mandatory. The existing layout tests are intentionally migrated in later named tasks; do not weaken their musical assertions to accommodate missing adapters.

Controller checkpoint: after this writer settles, run deno task build:checks before closing the task. No undefined methods or missed exported callers may be deferred to a later task. Run the affected suite once its named surface migration is coherent; preserve existing semantic expectations and use the native/default backend for actual node pixels. Writers never run validation.

## Required report

Return DONE, NEEDS_CONTEXT or BLOCKED; exact changed files; concrete interface/behavior delivered; any deviation; evidence the controller still must run. Never claim an unrun check passed. The controller requests task-scoped spec/quality review, fixes findings against the same predicate, and closes the task after review.

Budget report: include this task's approximate production-line contribution, source/destination evidence for any unchanged-move or formatting-only exclusions, and separate deletion/test counts. The controller tracks the aggregate against the fixed baseline for its final report; it is informational, with no numeric limit and no approval step.
