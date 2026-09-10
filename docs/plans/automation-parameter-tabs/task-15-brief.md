# Task 15: Adapt raster fixture identity and preserve native node pixels

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

- `src/checks/automation/raster/rasterfixture.h`
- `src/checks/automation/raster/rasterfixture.cpp`
- `src/checks/automation/raster/painting.cpp`

## Prerequisites

Completed/reviewed tasks: 5, 6, 8.

Dependency 8 is the corrected blueprint dependency for the shared test-support lookup. Raster-fixture code that already landed is corrected to call that seam by the bounded repair group, not by re-running historical task order; this brief assumes the seam exists and does not redefine it.

## Interface contract

Retains real SongTab/project fixtures, CCLaneAdapter/TempoLane adapters, default Quick backend and existing color/ring probes. No software-only replacement of QSG assertions. Rows and label items resolve through `checks::support::automationParameterIndex` / `checks::support::visualDescendant`; no copied traversal, duplicate catalog or production inverse mapping.

## Implementation steps

### Step 1

Replace hidden/empty-lane/row-height setup with outer automation height plus explicit parameter activation. Replace pinnedTempoRect with the active slot body after activating Tempo. Keep find-row and adapter identity helpers, without automatically switching during geometry queries. Replace the local `visualDescendant` copy in `rasterfixture.cpp` with `checks::support::visualDescendant`. The retained `AutomationRasterFixture::expandTempo` is already caller-free at the audited head: delete it rather than preserving or renaming it for task 16/29. If refreshed references reveal an unexpected live caller, update the bounded caller-migration write set before removal; do not create a compatibility body or a broken-caller interval.

### Step 2

In painting cases that previously inspected two visible lane bodies, activate each parameter before its own image/layer observation; retain the same literal node values, ring radii, expected colors, selected tick endpoints and source-event assertions. Do not accept a nonempty image as proof that a node or phantom exists. Keep every existing pixel probe at its current strength: no added retries, extra waits, relaxed tolerances or replaced expectations to accommodate activation.

### Step 3

Use zero vertical automation origin and preserve horizontal origin/DPR calculations. Continue to cover first-node/held-line/phantom and endpoint overflow painting; ensure the inactive plot's old QSG geometry is cleared after activation.

## Acceptance predicate

Raster probes observe the same node/phantom/selection pixels for the explicitly activated parameter, with the full logical selection still available for subsequent edits.

## Controller verification

Controller: `deno task verify --filter automation-raster --verbose` on the native/default backend after all raster source consumers compile.

Controller checkpoint: after this writer settles, run deno task build:checks before closing the task. No undefined methods or missed exported callers may be deferred to a later task. Run the affected suite once its named surface migration is coherent; preserve existing semantic expectations and use the native/default backend for actual node pixels. Writers never run validation.

## Required report

Return DONE, NEEDS_CONTEXT or BLOCKED; exact changed files; concrete interface/behavior delivered; any deviation; evidence the controller still must run. Never claim an unrun check passed. The controller requests task-scoped spec/quality review, fixes findings against the same predicate, and closes the task after review.

Budget report: include this task's approximate production-line contribution, source/destination evidence for any unchanged-move or formatting-only exclusions, and separate deletion/test counts. The controller tracks the aggregate against the fixed baseline for its final report; it is informational, with no numeric limit and no approval step.
