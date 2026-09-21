# Task 4 — Extract voice interaction (pointer/picker/menu/hover)

## Context

Second half of the voice split. Moves dispatch out of `VoiceChangesPage.swift`
into `VoiceChangesInteraction.swift`, consuming the task-3 scene contract.
Behavior change: none — same occurrence-identity freeze/revalidate, alt fine-
clock lattice, camera-scroll staleness rejection, audition + undo/redo shape.

## Exact write set

- `src/swift/app/drawer/voicechanges/VoiceChangesPage.swift` (delete moved methods; add forwarding)
- `src/swift/app/drawer/voicechanges/VoiceChangesInteraction.swift` (new)
- `src/swift/app/CMakeLists.txt` (register the new file)

## Prerequisites

Task 3 interfaces: `VoiceChangesSceneSnapshot.build`, marker/span publish inputs.

## Interface contract

- `VoiceChangesInteraction` owns, with unchanged public signatures:
  `pointerPress(x:y:surface:button:modifiers:)`, `pointerMove(x:y:buttons:modifiers:) -> Bool`,
  `pointerRelease(x:y:button:) -> Bool`, `pointerLeave()`, `pointerDoubleClick(x:y:) -> Bool`,
  `handleEscape() -> Bool`, `cancelSectionInteraction()`, `dismissModal()`,
  `setPickerFilter(text:)`, `selectPickerRow(index:)`, `pressAndHoldPickerRow(index:)`,
  `releasePickerAudition()`, `movePickerSelection(delta:)`, `acceptPicker() -> Bool`,
  `cancelPicker()`, `activateMenuAction(actionId:) -> Bool`, `activateMenuRow(index:) -> Bool`,
  `dismissVoiceMenu()`; internals `currentTrack/captureTarget/commit/openPicker/openMenu/updateHover/clearHover/cancelDrag/cancelPan/refreshInteractionPublished/xForTick/snapTick/markerHit/effectiveContextTick/contextKey`
  move whole.
- Page keeps: lifecycle, `configureBody`, session refresh, scene-apply,
  published modal/models/diagnostics state, `contextLabel(at:)`.
  Occurrence identity stays `(revision, track, chunk, event index, tick, value)`
  frozen at open, revalidated before every commit; camera scroll never drifts
  the captured target; rewrite-between-open-and-activate rejects the pick.
- Preserve: typed menu rows per target (Change/Delete vs Insert), picker
  capture/filter/accept/insert/replace/no-op/cancel/Escape-outside-right,
  marker-drag activation distance + single-move commit, alt fine-clock lattice,
  audition callback + document-history shape.
- Interaction may read Scene/Projection/Policy + Transactions; must not retain
  `DocumentSession` beyond a call.

## Implementation steps

1. Move the listed dispatch/capture/hover/teardown declarations whole; Page
   methods become forwards preserving signatures and return values.
2. Keep `commit(_ mutation: VoiceLaneMutation)` single-entry history path and
   staleness guard verbatim; keep `selectPickerProgram/refreshPicker/publishPicker`
   sequencing (build from Scene, dispatch here).
3. Keep `refreshInteractionPublished` wiring identical for container gating.
4. Do not touch Scene/Projection/Policy/Transactions except to call them; do
   not rename picker/menu publish names.
5. Edge cases: same-value pick = no-op; blank-slot commit rules; outside-right
   dismissal with no retarget; drag below activation distance commits nothing.

## Acceptance predicate

Dispatch behavior identical; Page forwards. Verified by:

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` (picker/drag/menu/cancellation/
  collision/alt-lattice/audition cases)
- `deno task verify --filter editorqml-drawer --verbose` (`voice-picker` pane)
- `deno task verify --filter drawerpresentation --verbose`
- `deno task format --check`

## Task-specific constraints

- Any retarget, menu-row, or commit-count divergence is a move defect. Restore
  verbatim; do not "improve" picker ranking or menu contents.
- No new keyboard shortcuts; no audition redesign (native audio integration
  stays separately verified on the production workspace).
