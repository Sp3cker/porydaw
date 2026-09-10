# Task 37: Remove obsolete Tempo header scene publication

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
- Whole-plan ceiling: 400 new or materially rewritten production lines, not 400 per task. Count nonblank, non-comment lines in normal project formatting, including C++, headers, QML, build declarations and all glue in new/existing files. Use the controller-supplied fixed baseline, aggregate and remaining allowance. Verified unchanged moves/formatting-only changes, deletions and test churn are separate; deletions never offset additions. If this task would exceed the aggregate ceiling, report NEEDS_CONTEXT for simplification or explicit user approval; do not expand scope, compress code or weaken behavior/tests.

## Exact write set

- `src/ui/songview/quick/timelinequickscene.h`
- `src/ui/songview/quick/timelinequickscene.cpp`
- `src/ui/songview/quick/automationquick.cpp`

## Prerequisites

Completed/reviewed tasks: 3, 5, 13, 16, 33.

## Interface contract

Remove tempoHeaderVisible/tempoHeaderRect/tempoHeaderFill/setTempoHeader and their dedicated notify/storage only. Keep automation plot/gutter/transient/hover text models still used by the renderer or other layers.

## Implementation steps

### Step 1

Refresh LSP references and scoped QML search. Delete the unused header properties/accessors, setter definition and state. No empty compatibility setter remains.

### Step 2

Keep generic text/layer publication and paint revisions unchanged. If the old automation gutter text model becomes entirely unused after task 3, remove its dedicated getter/property/storage and publication consistently within these three files (including setAutomationTextRecords publication in automationquick.cpp) only after references prove that; do not delete shared hover/value text models.

### Step 3

Remove stale scene comments about pinned Tempo. The only global Tempo presentation is now its selectable label and active plot.

## Acceptance predicate

TimelineQuickScene has no Tempo header plate properties or publication path; all automation scene layers correspond to the single active plot and real QML labels.

## Controller verification

Controller: final app/checks build and automation-presentation/raster/rendering-playhead.

Controller checkpoint: after this writer settles, run deno task build:checks before closing the task. No undefined methods or missed exported callers may be deferred to a later task. Run the affected suite once its named surface migration is coherent; preserve existing semantic expectations and use the native/default backend for actual node pixels. Writers never run validation.

## Required report

Return DONE, NEEDS_CONTEXT or BLOCKED; exact changed files; concrete interface/behavior delivered; any deviation; evidence the controller still must run. Never claim an unrun check passed. The controller requests task-scoped spec/quality review, fixes findings against the same predicate, and closes the task after review.

Budget report: include this task's production-line contribution, source/destination evidence for any unchanged-move or formatting-only exclusions, and separate deletion/test counts. The controller recomputes the aggregate from the fixed baseline at every settled task/fix review; a passing check does not waive the 400-line ceiling.
