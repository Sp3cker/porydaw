# Task 6a — Restore Automation domain, projection, and transactions

## Context

Follow [Global Constraints](plan.md#global-constraints), [Page transaction contract](spec.md#page-transaction-contract), [Automation domain and projection](spec.md#automation-domain-and-projection), and [Verification ownership and parity ledger](spec.md#verification-ownership-and-parity-ledger).

This task builds the complete pure-Swift Automation model before mounting QML. Behavioral authority is the production automation model/projection/page/canvas/node/tempo sources under `src/ui/editordrawer/`, the observable behavior inventory in `src/checks/automation/` and `src/checks/automation/presentation/`, and current sibling worktree changes. Translate behavior categories, not C++ implementation structure.

Existing Swift APIs are sufficient: `lanePoints`, lane write/move/delete, tempo editing, range editing, XCMD descriptors/operations, clipboard semantics, time selection, camera, history, and selection. No native/QtBridge expansion is authorized or needed.

## Exact write set

Create (keep each file cohesive and normally 200–400 lines; split only at these named seams):

- `src/swift/app/AutomationProjection.swift`: parameter identity/metadata, time/value transforms, curve/segment construction, snapping, interpolation, hit testing, labels, lane counts, and display rows.
- `src/swift/app/AutomationTransactions.swift`: frozen pencil/node/range/prompt/delete/clipboard transaction values and semantic commit/cancel policy.
- `src/swift/app/AutomationPage.swift`: document-bound owner, selected parameter state, selection/hover/preview/context, refresh/publication diagnostics, page seam, and future QML bridge primitives; do not attach it in production yet.
- `src/checks/swiftcore/AutomationPageChecks.swift`: direct projection, transaction, history, selection, cancellation, parity, and diagnostics checks.

Modify:

- `src/swift/app/CMakeLists.txt`: compile the three Automation sources.
- `src/checks/swiftcore/SessionChecks.swift`: dispatch the new checks.
- `src/checks/CMakeLists.txt`: compile the checks.

Read-only: `ApplicationSession.swift`, QML/resources, native/C++ code, legacy checks, and sibling references. Task 6b owns production attachment/input/rendering.

## Prerequisites

- Earlier shared session/page interface changes are accepted/checkpointed.
- `SongDocument` semantic APIs named above are current and history-producing.
- `DocumentSession` owns the selected track, edit cursor, timeline, camera, bank slots, and history.
- Existing Swift clipboard/time-selection models are the authority; native MIME integration remains a separate ledger gap.

## Interface contract

### Parameter and point identity

Define a finite Swift parameter identity matching production: volume, pan, supported control-change lanes, tempo, and XCMD rows exposed by the current document APIs. Preserve track scope where applicable and global scope for tempo. Identity must be stable across rendering/publication and serializable only where existing clipboard semantics require it.

Every projected point carries stable source identity: document revision, parameter/track identity, occurrence identity, tick, raw value, and derived x/y. Never use visible-array index as mutation identity. Parameter switching changes active presentation only; it does not mutate the document or discard explicit inactive-parameter selection.

### Projection

Use the shared `EditorCamera` for every time transform. Parameter metadata owns exact value range, neutral/default value, vertical direction, formatting, tick labels, snapping, and interpolation mode. Build visible curve segments/steps/ramps and points deterministically from document lane/tempo/XCMD data. Define half-open cell/boundary behavior and collision ordering once.

Projection covers empty/single/multiple points, before-first/after-last held values, same-tick occupants, viewport edges, negative pre-roll, zoom/scroll, tempo values, pan neutral snapping, and active/inactive selection indicators. Pure projection never mutates the document.

### Transactions

All interactions freeze document revision, selected track, parameter identity, target identities, before-values, camera/value projection, time selection, modifier policy, and collision occupants at begin.

Implement semantic models for:

- pencil insert/paint/sweep with stepping/ramp and trailing held-value restoration;
- node drag with axis lock, phantom preview, time/value clamping, collisions, and no-op detection;
- range selection/edit/replace across points and tempo;
- prompt set-value;
- delete;
- copy/cut/paste through existing Swift clipboard semantics; and
- parameter/track/document/history change cancellation.

Motion/typing updates preview only. Commit calls existing `SongDocument` APIs once per completed user action, creating at most one history entry. Cancel/no-op/stale/missing-target paths create none and restore projection from the document. Clipboard data remains internal Swift semantic payload; do not claim native MIME interoperability.

### Selection/context/publication

Maintain explicit per-parameter point/time selection exactly as production. Parameter tabs may show selected inactive scope. Playing voice context consumes the shared playhead state when the owner is later mounted; stopped context consumes edit cursor. No page clock or playhead line.

Separate `contentBuildCount` from presentation counters. Camera/content/selection/history changes rebuild only required layers. Shared-playhead-only updates must not rebuild static curves/points unless effective context changes their semantic display.

### Reopened exclusion rows

Provide direct Swift evidence for these five previously absent-UI automation-domain rows:

1. `nodeDragAndPhantomOutcomes`;
2. `panNeutralSnap`;
3. `pointRangeAndPencilReplacements`;
4. `sweepFinishRestoresTrailingHeldValue`;
5. `sweepSteppingAndRampFinish`.

Map each row to named observable checks. Do not mark it covered by file existence or a case count.

## Implementation steps

1. Inventory existing Swift semantic method signatures and legacy observable scenario categories; record mappings in check IDs/comments, not a new report file.
2. Implement parameter metadata and pure projection with direct boundary checks.
3. Implement frozen transaction values and commit/cancel routes using existing document APIs.
4. Implement the page owner/publication diagnostics without production attachment or QML.
5. Translate the five exclusion rows plus representative behavior from legacy categories: parameter selection, pencil, node drag, range/selection, prompts, actions, clipboard, ownership/cancellation, tempo/CC parity, and history.
6. Run only the exact commands below; skip project-wide formatter/lint and unrelated suites in the writer task.

## Acceptance predicate

- all current production Automation parameter kinds project exactly through the shared camera and parameter value maps;
- stable identity survives same-tick occupants and prevents stale/index retargeting;
- pencil/node/range/prompt/delete/clipboard transactions freeze inputs, preview without mutation, commit once, and cancel cleanly;
- Undo/Redo reconstructs exact document-derived curves/selection and no operation creates duplicate history;
- pan neutral, point-range replacements, phantom drag, trailing held-value restoration, and sweep step/ramp behavior have direct observable checks;
- selected inactive parameters and playing/edit-cursor context rules are represented without a page-local playhead;
- no native/C++/QtBridge/QML/test-scenario expansion occurs;
- native MIME clipboard gaps remain explicitly separate; and
- exact verification passes:

```bash
deno task build:app
deno task verify --filter swiftcore --verbose --qt projectSession
```

## Task-specific constraints

- No production page attachment/QML in this task.
- No copied C++ class hierarchy, generic lane-plugin framework, or parallel history.
- No native MIME claim or bridge addition.
- No array-index mutation identity.
- No page-local clock/camera/playhead.
- Do not touch unrelated dirty planning documents or `.scratch/`.
- Return exact changed files, verification output, legacy-category mappings, the five exclusion-row mappings, and any unsupported semantic API as a blocker rather than a workaround.