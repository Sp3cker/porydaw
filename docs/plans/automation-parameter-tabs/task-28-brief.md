# Task 28: Preserve pencil edits on empty supported parameters

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

- `src/checks/automation/automationpencil.cpp`

## Prerequisites

Completed/reviewed tasks: 8, 9, 10, 12, 18.

## Interface contract

Use an empty supported modulation row (CC1) instead of CC11 for the old empty-lane pencil fixture, activated through task 8's real fixture helper (shared `checks::support::automationParameterIndex` / `visualDescendant` seam). Preserve all stroke ticks/values/transaction/undo expectations and all existing snapping behavior.

## Implementation steps

### Step 1

Rename the file-local kExpressionController to kEmptyController with LSP, and set it to CoreTimeDefaults::kCcModulation. Remove addEmptyLane and activate the resulting row through the real fixture helper. Keep values 40/72/96, grid-cell projection and original document/timeline expected results.

### Step 2

For Tempo and Pitch bend pencil cases, explicitly activate their parameter. Remove individual-row-height setup; the shared plot uses the fixture's outer automation height. Retain signed bend conversion, interpolated points, snapping, cancel/rebuild guards and one-undo transaction assertions.

Main fixture helper deletion belongs to task 26 after this pencil migration and the remaining stroke caller move; do not delete a helper with live references here.

## Acceptance predicate

Pencil painting still commits exactly one original transaction for empty CC, Tempo and Pitch bend cases, without relying on an unsupported manually inserted CC11 presentation row.

## Controller verification

Controller: after writers settle, run `deno task verify --filter automation-editing --verbose` once the editing-suite migration group is complete. Compilation is required at each settled task; run the suite at its completed surface checkpoint. Obsolete scenarios are migrated, not suppressed or declared passing.

Controller checkpoint: after this writer settles, run deno task build:checks before closing the task. No undefined methods or missed exported callers may be deferred to a later task. Run the affected suite once its named surface migration is coherent; preserve existing semantic expectations and use the native/default backend for actual node pixels. Writers never run validation.

## Required report

Return DONE, NEEDS_CONTEXT or BLOCKED; exact changed files; concrete interface/behavior delivered; any deviation; evidence the controller still must run. Never claim an unrun check passed. The controller requests task-scoped spec/quality review, fixes findings against the same predicate, and closes the task after review.

Budget report: include this task's approximate production-line contribution, source/destination evidence for any unchanged-move or formatting-only exclusions, and separate deletion/test counts. The controller tracks the aggregate against the fixed baseline for its final report; it is informational, with no numeric limit and no approval step.
