# Task 4 — Extract voice interaction as page extension

## Context

Second half of the voice split. Relocates pointer/picker/menu/hover/drag
dispatch into `VoiceChangesInteraction.swift` as `extension VoiceChangesPage`
(same precedent as task 2), consuming the task-3 scene contract. File
placement only — same type, no wiring, no forwards. Behavior change: none.

## Exact write set

- `src/swift/app/drawer/voicechanges/VoiceChangesPage.swift` (delete relocated method bodies)
- `src/swift/app/drawer/voicechanges/VoiceChangesInteraction.swift` (new: extension + snapshot struct)
- `src/swift/app/CMakeLists.txt` (register the new file)

## Prerequisites

Task 3 interfaces: `VoiceChangesSceneInput/Snapshot.build`, scene value helpers.

## Interface contract

- Uses `VoiceInteractionSnapshot` defined canonically in task 3 (`VoiceChangesScene.swift`):
  this task adds the per-rebuild construction call from live drag/hover/selection state and
  the extension's reads of it; field extensions update the struct and Scene build reads together here.
- Relocated whole into the extension (bodies verbatim, signatures unchanged):
  `pointerPress/pointerMove/pointerRelease/pointerLeave/pointerDoubleClick`,
  `handleEscape`, `cancelSectionInteraction`, `dismissModal`,
  `setPickerFilter/selectPickerRow/pressAndHoldPickerRow/releasePickerAudition/movePickerSelection/acceptPicker/cancelPicker`,
  `activateMenuAction/activateMenuRow/dismissVoiceMenu`,
  `currentTrack/captureTarget/commit/openPicker/openMenu`,
  `updateHover/clearHover`, `cancelDrag/cancelPan`, `refreshInteractionPublished`.
- Stays in the Page file: lifecycle, `configureBody`, all `refresh*` (read
  drag/picker/menu state directly), `rebuildContent` orchestration, all publish
  apply bodies, `publishPicker/refreshPicker/selectPickerProgram` sequencing
  calls, all caches and stored state, all check-facing `@QtIgnored` accessors.
- Preserve: occurrence identity `(revision, track, chunk, event index, tick,
  value)` frozen at open and revalidated before every commit; camera scroll
  never drifts the captured target; rewrite-between-open-and-activate rejects
  the pick; typed menu rows per target; picker capture/filter/accept/insert/
  replace/no-op/cancel/Escape/outside-right; marker-drag activation distance +
  single-move commit; alt fine-clock lattice; same-value no-op; audition
  callback + history shape.
- Extension file MUST NOT contain `import QtBridge`.

## Implementation steps

1. Cut the listed bodies into `extension VoiceChangesPage` verbatim; no stubs
   or forwards left behind.
2. Add `VoiceInteractionSnapshot` and its per-rebuild construction; wire into
   task 3's input in place of the placeholder.
3. Keep `refreshInteractionPublished` wiring identical for container gating.
4. Do not touch Scene/Projection/Policy/Transactions except to call them; do
   not rename picker/menu publish names.
5. Edge cases: drag below activation distance commits nothing; blank-slot rules
   unchanged; native audio integration stays separately verified.

## Acceptance predicate

Per plan.md Verification policy; task focus: picker insertion/replacement,
marker-drag transactions, context-menu transactions, cancellation paths,
collision/blank-slot, alt lattice, audition (`swiftcore/VoiceChangesPage::*`
cases; `voice-picker` editorqml pane).

## Task-specific constraints

- Retarget, menu-row, or commit-count divergence is a move defect. Restore
  verbatim; no picker ranking or menu-content improvements.
- No new keyboard shortcuts; no audition redesign.
