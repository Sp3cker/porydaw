# Task 8: Give the editing fixture real parameter activation

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

- `src/checks/automation/tst_automationediting.h`
- `src/checks/automation/automationfixture.cpp`
- `src/checks/automation/tst_automationediting.cpp`
- `src/checks/support/timelinequickcheck.h`
- `src/checks/quickpopupguard.h`
- `src/checks/automation/automationmenus.cpp`

Explicit cohesive exception (six files): task 8 owns the single test-support seam. The canonical helper's relocation and its one external qualified call site move in the same edit as the definition, so no duplicate traversal and no temporary alias exists between tasks.

## Prerequisites

Completed/reviewed tasks: 5, 6.

Task 8 is the seam owner and the only task that physically defines the shared lookups. Already-landed consumers (hover, presentation, raster, scrollbar, playhead, drawer and value-prompt fixtures) are corrected to call them by the current bounded repair group, not by re-running historical task order; do not duplicate that correction here and do not leave a second physical definition of the seam. The pre-existing eventviews copy and the voice-picker copy are outside this repair.

## Interface contract

Produces `bool AutomationEditingTest::activateParameter(const EditorAutomationRowId &row);` and private slot `void parameterTabsPreserveDocumentAndSelection();`. `findRow`, `laneBody` and `inputPoint` remain pure geometry/identity queries and must not switch tabs implicitly.

## Implementation steps

### Step 1

Implement the fixture helper with real label input, on top of the shared lookups this task owns in `src/checks/support/timelinequickcheck.h` (namespace `checks::support`):

- `QQuickItem *visualDescendant(QQuickItem *root, QAnyStringView objectName)`: relocate the existing `quick_popup::visualDescendant` from `src/checks/quickpopupguard.h` into this header as the single definition. Walk `QQuickItem::childItems()` and match `root` itself too; no alias, overload or second copy in the affected fixtures. Qt 6.9's [QAnyStringView](https://doc.qt.io/archives/qt-6.9/qanystringview.html) accepts the existing QString and QLatin1String arguments without an owning-string conversion. Include QAnyStringView, pass it by value and consume it synchronously; do not store it or rewrite literal call sites.
- `automationParameterIndex(const AutomationCanvas &canvas, const EditorAutomationRowId &row)`: loop `canvas.parameterRow(i)` from `i = 0` until it returns `std::nullopt`, comparing each validated row identity, and return the matching index or `-1`. Do not read `parameterLabels().size()` and do not add a production inverse mapping.
- Migrate the one external qualified popup lookup in `src/checks/automation/automationmenus.cpp` (`quick_popup::visualDescendant(session.overlayRoot(), QLatin1String("quickMenuPanelSubmenu"))`) to `checks::support::visualDescendant`. Change nothing else in that file; task 12 owns its menu semantics.

```cpp
bool AutomationEditingTest::activateParameter(const EditorAutomationRowId &row)
{
    const int index = checks::support::automationParameterIndex(*page().canvas(), row);
    if (index < 0 || !m_quickWindow)
        return false;
    auto *quick = tab().view().quickView();
    QQuickItem *root = quick ? quick->rootObject() : nullptr;
    QQuickItem *const item = checks::support::visualDescendant(
        root, QStringLiteral("automationParameterTab%1").arg(index));
    if (!item || !item->isVisible() || !item->isEnabled())
        return false;
    const QPoint where = item->mapToScene(
        QPointF(item->width() / 2.0, item->height() / 2.0)).toPoint();
    QTest::mouseClick(m_quickWindow, Qt::LeftButton, Qt::NoModifier, where);
    return QTest::qWaitFor([this, index] {
        return page().canvas()->activeParameter() == index;
    });
}
```
Include QQuickItem/QtTest, the existing TimelineQuickView declaration and `src/checks/support/timelinequickcheck.h` explicitly. Use the same quickView()->rootObject() lookup as the current fixture and popup tests. In normal pilot setup activate the existing CC10 row after the Quick scene is ready; retain the original SMF literals and outer drawer size. Do not replace the fixture with a fake canvas. No `findChild`/QObject-name search and no production `parameterIndex` call remains here: this helper and every other suite call the same two shared lookups instead of copying them.

The early proof also exposed a stack-era fixture precondition: the active full-height plot was 320 high, not rowMaximumHeight's 128. Remove that exact-height assertion from init; keep lane validity and nonempty-body prerequisites. Do not repin to 320. Retain the still-live setRowMaximumHeight helper and init call until task 26's caller closure; existing presentation/drawer cases own the physical plot-size contract.

### Step 2

Add the new slot. Set `TimeSelection::scope = TimeSelection::Lanes`. Build an explicit Lanes time selection over `[48,144)` containing Volume and Pan plus Tempo, take FrozenDocumentState, then activate every catalog row through the helper. Assert the selection start/end/scope/lanes/tempo remain equal, FrozenDocumentState remains equal, and the current index follows the clicked label. Use `parameterRow(i)` for row lookup, not hard-coded LaneHandle indices. Include an empty supported parameter in the cycle.

### Step 3

Migrate expandTempo/setRowMaximumHeight callers in the semantic editing tasks, then remove these two main-fixture helpers in task 26 (task 28 does not delete them). The separate hover/raster helpers are not renamed by task 29: the raster dead helper is deleted by the repair group and the hover helper is already absent, so no compatibility alias or wrapper is preserved for them.

### Step 4

Remove vertical automation offsets in the three automation_test coordinate helpers and main pilot probes: windowFromContent maps the point directly; contentFromWindow returns the mapped point directly; effectiveDragContent returns its quantized viewport point directly. Keep every horizontal camera and pointer-rounding operation. All-label test iteration unwraps parameterRow(index) only after checking it has a value.

## Acceptance predicate

The main editing fixture can activate any supported row through its rendered label, and cycling all labels preserves the document, undo state and explicit shared selection.

## Controller verification

Controller: prove this task's behavior now, not at a later checkpoint. After this writer settles run `deno task build:checks`, then `deno task verify --filter automation-presentation --verbose`, then the focused editing case `deno task verify --filter automation-editing --verbose --qt parameterTabsPreserveDocumentAndSelection`, confirming its body actually executes and passes (a filtered-out or skipped slot is not proof). Shared fixture functionality must be proven before dependent suites reuse it. The complete editing suite remains the task 26 checkpoint: `deno task verify --filter automation-editing --verbose`. Obsolete scenarios are migrated, not suppressed or declared passing.

Controller checkpoint: no undefined methods or missed exported callers may be deferred to a later task. Removal of the production inverse `parameterIndex` and every landed consumer's call-site correction settle atomically in the current bounded repair group; never retain a temporary alias to satisfy old task order. Writers never run validation.

## Required report

Return DONE, NEEDS_CONTEXT or BLOCKED; exact changed files; concrete interface/behavior delivered; any deviation; evidence the controller still must run. Never claim an unrun check passed. The controller requests task-scoped spec/quality review, fixes findings against the same predicate, and closes the task after review.

Budget report: include this task's approximate production-line contribution, source/destination evidence for any unchanged-move or formatting-only exclusions, and separate deletion/test counts. The controller tracks the aggregate against the fixed baseline for its final report; it is informational, with no numeric limit and no approval step.
