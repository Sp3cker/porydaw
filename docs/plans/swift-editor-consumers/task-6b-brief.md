# Task 6b — Restore mounted Automation editing

## Context

Follow [Global Constraints](plan.md#global-constraints), [Page transaction contract](spec.md#page-transaction-contract), [Mounted Automation page](spec.md#mounted-automation-page), [Focus, commands, and lifetime](spec.md#focus-commands-and-lifetime), and [Verification ownership and parity ledger](spec.md#verification-ownership-and-parity-ledger).

Task 6a supplies the complete Swift model/projection/transaction layer. This task attaches it to the current document and restores production Automation QML, real input, tabs, prompts, menus, tap tempo, focus, cancellation, and rendered parity. Production and checks under `src/ui/editordrawer/automation*`, `cclanes*`, `nodelane/`, `tempolane*`, `taptempo.h`, `src/checks/automation/`, `src/checks/automation/presentation/`, and sibling `automation-tabs` references are behavior authority.

## Exact write set

Create:

- `src/ui/songview/quick/drawer/AutomationPage.qml`: production tabs, gutter/value axis, curve/point canvas, hover/selection/ghost/readout, shared plot alignment, and input delivery.
- `src/ui/songview/quick/drawer/AutomationPrompt.qml`: Swift-owned captured point/range/tempo value prompt.
- `src/ui/songview/quick/drawer/AutomationMenu.qml`: Swift-owned point/background/context actions.
- `src/ui/songview/quick/drawer/TapTempo.qml`: local modal tap-tempo interaction using the page's Swift state.

Modify:

- `src/swift/app/AutomationPage.swift`: expose the production QML bridge methods/properties, modal/tap-tempo state, interaction routing, and synchronous cancellation using task 6a semantics.
- `src/swift/app/ApplicationSession.swift`: own/attach/refresh/cancel/detach the Automation page within acknowledged document lifetime and connect existing command/clipboard/audio context routes.
- `CMakeLists.txt`: add the four production QML components to `drawer_qml`.
- `src/checks/editorqml/EditorQmlTests.swift`: expose deterministic production-owner observations/inputs only.
- `src/checks/editorqml/tst_EditorDrawer.qml`: add production Automation mounting, real input, prompt/menu/tap-tempo, cancellation, playhead-performance, and rendered cases.
- `src/checks/swiftcore/AutomationPageChecks.swift`: add direct modal/tap-tempo/input-boundary checks only where the behavior is pure Swift and not already covered in task 6a.

The implementer may modify `EditorDrawer.qml` only for a production-generic modal/focus fact that existing Loader/section geometry cannot provide. No new QML test file, executable, manifest entry, C++ source, or bridge expansion.

## Prerequisites

- Task 6a is accepted/checkpointed and its semantic operations cover every production interaction listed here.
- Shared playhead/follow interaction aggregation and drawer attachment lifetime are accepted.
- Earlier page changes touching `ApplicationSession`/drawer resources/tests are accepted/checkpointed.
- Existing Swift clipboard supports in-app semantic automation payloads; native MIME gaps remain separate.

## Interface contract

### Production mounting

`ApplicationSession` creates one `AutomationPage` for the current `DocumentSession`, attaches it before scene mount, refreshes it after document/timeline/camera/playhead/selection/track/history changes, cancels while the scene exists, and detaches/releases after host acknowledgment. Drawer preferences survive; page state tied to the old document does not.

`AutomationPage.interactionActive` is true for pointer/pan/node/pencil/range gestures, open prompt/menu, tap-tempo session, audition/context interaction, or explicit follow suspension. Global cancellation synchronously clears all of them.

### QML composition and input

`AutomationPage.qml` renders directly from task 6a projection models and the shared drawer/camera geometry. It owns no document model, camera, playhead, clock, or history. The composition includes production parameter tabs, selected inactive indicators, gutter/value labels, curve/step/ramp shapes, nodes, selection/range, hover/ghost/readout, cursor policy, and the single composition-owned shared playhead segment.

Real pointer and wheel input drives page-owner begin/update/end methods for pencil, node drag, range selection/edit, pan, hover, and context actions. Pointer ungrab, Escape, hide, window deactivation, parameter/track/document switch, Undo/Redo, or scene retirement uses one cancellation route. Follow-scroll is suspended exactly while an interaction is active.

Tabs activate with pointer, Enter/Return, and accessibility press; bare Space remains global transport. Preserve explicit modal text-entry exceptions without a second global dispatcher.

### Prompts and menus

A prompt/menu captures document revision, track, parameter, point/range identity, and before-state at open. It never follows later active state. Accepted input commits one existing transaction; invalid input stays non-mutating with an error; Escape/outside/hide/replacement/stale identity commits nothing and restores focus.

Support production point/background actions, set value, delete, copy/cut/paste availability, range actions, parameter-specific choices, and synthetic/default-point rules. Do not expose disabled actions as successful no-ops.

### Tap tempo

Implement production tap-tempo cadence/reset/average/commit behavior in the Swift page owner with QML delivering taps and displaying state. Use monotonic input timestamps supplied at the event boundary only for measuring user tap intervals; this is not playback position and must not create a second playhead clock. Commit tempo once through `SongDocument.editTempo`; cancellation/reset commits nothing.

### Render/performance coverage

Exercise the production component with actual pointer/key/accessibility input and representative volume, pan, CC, tempo, XCMD, empty, collision, and same-tick content. Compare `automation-tabs` at macOS DPR 2/font 12 and 16 plus any sibling pane baseline grounded before implementation. Repeated shared-playhead updates must not rebuild curves/points or close/retarget modal state unless a playing-context semantic boundary requires it.

Translate observable categories from legacy automation suites: tabs/selection, pencil, node drag, range, point menus/prompts, actions/clipboard, ownership/cancellation, tempo/CC parity, tap tempo, hover/labels/counts, cursor/gutter boundary, focus/keys, and performance. Never call a C++ scenario body.

## Implementation steps

1. Extend `AutomationPage` with the bounded bridge/input/modal/tap-tempo surface; add direct checks for pure policy.
2. Attach the page through `ApplicationSession` lifecycle and aggregate interaction/follow cancellation.
3. Implement production QML canvas/tabs/input, then prompt/menu/tap-tempo components.
4. Extend the existing editor-QML lane with real interaction, focus/accessibility, cancellation, history, playhead-performance, and rendered cases.
5. Run only the exact commands below; skip project-wide formatter/lint and unrelated suites in the writer task.

## Acceptance predicate

- normal production composition mounts the real Automation page for the current document;
- every task-6a semantic route is reachable through real QML input with production projection/rendering;
- tabs/selection, pencil, node drag, range, prompt/menu actions, delete, in-app clipboard, Tempo/CC/XCMD parity, tap tempo, focus/keys, cancellation, Undo/Redo, and shared playhead/follow behavior match production;
- modal/gesture state cannot retarget after parameter/track/document/history replacement;
- shared-playhead-only updates do not rebuild static Automation content;
- production rendered evidence covers `automation-tabs` DPR 2 font 12/16 and other grounded sibling pane baselines;
- five task-6a exclusion rows now have both pure semantic and mounted-input evidence where applicable;
- native MIME gaps remain separate and explicit;
- no C++ scenario body, bootstrap, bridge, page-local clock, or copied dispatcher exists; and
- exact verification passes:

```bash
deno task build:app
deno task verify --filter swiftcore --verbose --qt projectSession
deno task verify:qml --filter editorqml-drawer --verbose
deno task verify --filter swiftrollgated --verbose
```

## Task-specific constraints

- QML is input/rendering only; no duplicate semantic model.
- Monotonic tap timestamps are allowed only for tap-tempo intervals, never playback.
- No native MIME, C++/QtBridge, popup-controller, or new test-lane expansion.
- No page-local playhead/camera/history/selection authority.
- Do not touch unrelated dirty planning documents or `.scratch/`.
- Return exact changed files, verification output, translated legacy-category map, rendered-profile evidence, and any blocker.