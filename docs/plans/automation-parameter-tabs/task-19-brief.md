# Task 19: Verify automation minimum without changing other drawer sections

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

- `src/checks/drawerpresentation/tst_drawerpresentation.h`
- `src/checks/drawerpresentation/drawer.cpp`
- `src/checks/drawerpresentation/fixtures.cpp`
- `src/checks/drawerpresentation/valueprompt.cpp`
- `src/checks/support/quickframebuffer.h`
- `src/checks/support/quickframebuffer.cpp`
- `src/checks/support/editorrig.cpp`

Named seven-file cohesive exception: the drawer fixture, geometry checks, real Pan prompt entry points and shared first-frame readiness form one measured repair. The `plan` agent approved the three support-file additions after the stale crop was measured; a file-count target must not force duplicate waits or leave these consumers unowned.

## Prerequisites

Completed/reviewed tasks: 6, 13.

## Interface contract

Uses DrawerSections::minimumBodyHeight for public geometry observations, not the old shared minBody as an automation minimum. Reuse task 8's `checks::support::visualDescendant` and `automationParameterIndex` from the existing timelinequickcheck.h; do not copy either lookup into drawer fixtures. Identity/geometry probes never activate parameters. Existing voice resize baselines and expected musical outcomes remain unchanged.

Audit status: the normal-font minimum case, both Pan prompt cases and all three Voice pixel cases pass after the bounded repair. The enlarged-font repeat remains unproven. Before repair, a full-suite Voice capture requested `QRect(0,325 1000x102)` and returned after the band moved to `QRect(0,369 1000x102)`; the isolated case started at y=369 and passed. Frame PNGs showed the displaced crop. No drawer fixture changes the application font. Exposed/nonempty inputs were not a first-rendered-layout boundary.

## Implementation steps

### Step 1

Update drawerStackAndCanonicalInputs for one automation plot/no automation scrollbar. Keep the separate three drawer sections and their canonical order exactly as before.

### Step 2

Extend minimum-height/resize tests: request an automation height below the measured label grid, verify all labels remain within the automation gutter; increase font scale and repeat; cancel resize and verify prior stored section state restores. Preserve independent voice/velocity size assertions.

### Step 3

In voice-handle overflow cases use separate voice and automation minimums in expected geometry while keeping the existing voice maximum and delta handoff contract. Do not raise the shared minBody or loosen the voice cap to make automation labels fit.

### Step 4

In valueprompt.cpp, activate CC10 through its rendered label before the two insertion/Escape scenarios obtain Pan probe coordinates and send their double click. The default active parameter is Volume; adding/probing a Pan event does not change it. Keep the real pointer path, displayed centered range/value conversion, committed source event, undo and focus assertions. Do not change production prompt semantics or repin expectations to Volume. Remove wording-only assertions and incidental pixel-quantized initial-number assertions (`32` versus observed `33`), not replace them with new literals. Typing displayed 0 must still commit stored 64; this also detects failure to select the initial input for replacement.

### Step 5

Repair the measured stale-geometry cause, not Voice painting. Extract the existing exposure/afterRendering wait from captureQuickBand into one test-only `waitForQuickFrame(QQuickWindow &, QString * = nullptr)` in quickframebuffer.h/.cpp. Retain the existing deadlines and fail-fast hidden-window precondition; callers explicitly show the window. Reuse it from captureQuickBand and showQuickViewport. EditorRig waits before returning only when `config.show` is true; DrawerFixture waits after staging focus and before returning ready.

This is an earlier first-frame boundary, not another scheduler or retry policy. Keep all three Voice pixel comparisons unchanged. No sleeps, discarded captures, retries, hidden Automation or relaxed pixels. The stronger showQuickViewport boundary applies to all its callers: diagnose any newly failing geometry assertion individually, changing only proven pre-settle/incidental assumptions. Never presume every failure is stale or change musical outcomes to obtain a pass.

## Acceptance predicate

Automation resizing honors the measured label minimum at normal and enlarged font, Pan prompt input reaches Pan, and Velocity/Voice Changes sizes, voice cap and overflow handoff retain their behavior. Shown fixtures return after the first rendered layout; existing Voice pixel cases pass without changing their comparisons. Normal-font/readiness repair evidence does not close the still-unrun enlarged-font gate.

## Controller verification

Controller: run `deno task verify --filter editor-drawer --verbose` after source writers settle. Record the two Pan cases, normal/enlarged-font minimum and voice-cap handoff separately from the Voice pixel cases. A passing new minimum case alone does not close this task. Resolve failures in this task's responsibility; a proven external failure must have a named repair owner and remain an explicit final-gate blocker. Do not repeatedly stress-run desktop-input cases.

Controller checkpoint: after this writer settles, run deno task build:checks before closing the task. No undefined methods or missed exported callers may be deferred to a later task. Run the affected suite once its named surface migration is coherent; preserve existing semantic expectations and use the native/default backend for actual node pixels. Writers never run validation.

## Required report

Return DONE, NEEDS_CONTEXT or BLOCKED; exact changed files; concrete interface/behavior delivered; any deviation; evidence the controller still must run. Never claim an unrun check passed. The controller requests task-scoped spec/quality review, fixes findings against the same predicate, and closes the task after review.

Budget report: include this task's approximate production-line contribution, source/destination evidence for any unchanged-move or formatting-only exclusions, and separate deletion/test counts. The controller tracks the aggregate against the fixed baseline for its final report; it is informational, with no numeric limit and no approval step.
