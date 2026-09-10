# Task 2: Add view-local parameter identity and Qt presentation bindings

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

- `src/ui/editordrawer/automationcanvas.h`
- `src/ui/editordrawer/automationcanvas_tabs.cpp` — create
- `CMakeLists.txt`

## Prerequisites

Completed/reviewed tasks: 1.

## Interface contract

Produces the following AutomationCanvas interface. `index` is a catalog position, never a LaneHandle; null m_activeController means Tempo.
```cpp
Q_PROPERTY(QStringList parameterLabels READ parameterLabels NOTIFY parameterPresentationChanged FINAL)
Q_PROPERTY(int activeParameter READ activeParameter NOTIFY activeParameterChanged FINAL)
Q_PROPERTY(QList<int> selectedParameters READ selectedParameters NOTIFY parameterSelectionChanged FINAL)
Q_PROPERTY(QVariantMap parameterAppearance READ parameterAppearance NOTIFY parameterPresentationChanged FINAL)
Q_PROPERTY(bool parametersEnabled READ parametersEnabled NOTIFY parameterPresentationChanged FINAL)
QStringList parameterLabels() const;
int activeParameter() const noexcept;
QList<int> selectedParameters() const;
QVariantMap parameterAppearance() const;
bool parametersEnabled() const noexcept;
Q_PROPERTY(int minimumContentHeight READ minimumContentHeight WRITE setMinimumContentHeight
           NOTIFY minimumContentHeightChanged FINAL)
void setMinimumContentHeight(int height); // Qt grid implicitHeight, rounded up in QML
// Reuse the existing minimumContentHeight() const noexcept declaration.
std::optional<EditorAutomationRowId> parameterRow(int index) const;
int parameterIndex(const EditorAutomationRowId &row) const noexcept;
Q_INVOKABLE void activateParameter(int index);
Q_INVOKABLE void openParameterMenu(int index, qreal sceneX, qreal sceneY);
// signals
void activeParameterChanged();
void parameterSelectionChanged();
void parameterPresentationChanged();
void minimumContentHeightChanged();
// private
LaneHandle activeLane() const noexcept;
int m_minimumContentHeight = 0;
std::optional<uint8_t> m_activeController = CoreTimeDefaults::kCcVolume;
```
Explicitly include the Qt containers and core/timedefaults.h. Do not add a font-fitting loop, gutter/font cache, refreshParameterPresentation(), or a second minimum-height getter. Qt owns text measurement, fitting, layout and binding invalidation. parameterAppearance is only the existing project-style bridge for typography/theme/layout primitives, not a cached layout snapshot. The existing minimumContentHeight getter retains its old implementation during this additive task; task 3 changes its real meaning to the Qt-measured selector minimum.

## Implementation steps

### Step 1

Implement the new methods in the cohesive new automationcanvas_tabs.cpp and register it adjacent to automationcanvas.cpp in CMakeLists.txt. parameterRow(i) validates `0 <= i <= supportedControllers().size()`: the final index returns `{Tempo,0,0}`, otherwise `{ControlChange,uint8_t(primaryTrack),controllers[i]}`. Reject invalid primary tracks. parameterIndex checks kind/primary track/controller and returns -1 for unsupported identities. activeParameter finds m_activeController in the catalog, or returns the final Tempo index. activeLane searches the existing m_nodeStack for the currently resolved row id; never cache its index across rebuilds. parameterLabels uses m4aLaneName for the classified CC, registered XCMD selector, dedicated PitchBend, and final Tempo. Do not duplicate display names or expose nested per-command maps.

### Step 2

Implement switching in this order:
```cpp
void AutomationCanvas::activateParameter(int index)
{
    const auto row = parameterRow(index);
    if (!row || !parametersEnabled() || index == activeParameter())
        return;
    cancelInteraction();
    cancelLaneMenuWithoutFocus();
    cancelNodeMenuWithoutFocus();
    m_activeController = row->kind == EditorAutomationRowKind::Tempo
                             ? std::nullopt
                             : std::optional<uint8_t>{row->controller};
    m_hoverState.clearHover();
    m_hoverState.invalidateCaches();
    m_hoverState.hoverValueLabel = {};
    syncTimelineQuickHover();
    emit activeParameterChanged();
    requestFullQuickUpdate();
}
```
Do not rebuild the logical lane table on a mere tab switch. openParameterMenu validates the index, activates it, resolves activeLane and calls existing showLaneMenuFor(handle, QPointF(sceneX,sceneY)); invalid/no-document requests do nothing. selectedParameters returns indices whose row is covered by existing m_laneSelection.coversNodes; this is selection-scope inclusion, not a count of stored nodes. parametersEnabled is `m_page.ready() && m_page.document()`.

### Step 3

Expose only `font` (caption, normalized to pixel size with Qt), `minimumFont` (same typeface at max(1, layout::fontPx(2.0/3.0))), `minimumCellHeight` (layout::fontPxF(4.0/3.0)), `inset`, `stroke`, `background`, `currentFill`, `text`, `selectionOutline`, and `focusOutline` in parameterAppearance. Reuse the existing typography and song-view theme roles; inset is layout::space(One), stroke is layout::singlePixel(). No columns, fitted font, cellHeight or minimumHeight entries. Construct this small map only when its QML binding is invalidated by the existing appearance/document lifecycle, never in scene/pointer refreshes. Do not introduce a new theme service or nine button-specific style models.

Implement setMinimumContentHeight(int) as a nonnegative scalar setter with an equality guard against the stored scalar and minimumContentHeightChanged notification. Task 5 publishes Math.ceil(grid.implicitHeight) through a Qt Binding; task 6 reads the existing minimumContentHeight() API. This is the only cross-boundary size value. No C++ row-count calculation, copied font/gutter inputs, polling, timer or layout retry loop.

### Step 4

Keep the existing value-prompt cancellation path in cancelInteraction; do not add a new prompt implementation or mutate NodeLane/phantom algorithms. The runtime QML consumer lands after the shared-plot cutover, so this task does not advertise labels backed by missing rows.

## Acceptance predicate

AutomationCanvas exposes a validated, view-local active parameter and the minimal Qt presentation bindings; switching identity cancels stale interaction state but leaves document bytes, revision, undo stack and shared selection unchanged.

## Controller verification

Controller: run `deno task build:app` after this writer settles. Run `deno task verify --filter automation-domain --verbose` for the unchanged adapter/gesture semantics. Do not run old stacked-layout assertions as acceptance for the new layout; their explicit migration tasks and final full coverage remain mandatory.

Controller checkpoint: after this writer settles, run deno task build:checks before closing the task. No undefined methods or missed exported callers may be deferred to a later task. Run the affected suite once its named surface migration is coherent; preserve existing semantic expectations and use the native/default backend for actual node pixels. Writers never run validation.

## Required report

Return DONE, NEEDS_CONTEXT or BLOCKED; exact changed files; concrete interface/behavior delivered; any deviation; evidence the controller still must run. Never claim an unrun check passed. The controller requests task-scoped spec/quality review, fixes findings against the same predicate, and closes the task after review.

Budget report: include this task's approximate production-line contribution, source/destination evidence for any unchanged-move or formatting-only exclusions, and separate deletion/test counts. The controller tracks the aggregate against the fixed baseline for its final report; it is informational, with no numeric limit and no approval step.
