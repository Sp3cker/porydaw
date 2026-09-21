# Task 2 — Extract velocity interaction + prompt dispatch

## Context

Second half of the velocity split. Moves gesture/hover/prompt behavior out of
`VelocityPage.swift` into `VelocityInteraction.swift`, consuming the task-1
Scene/Projection contract. Behavior change: none — same frozen-gesture,
preview-never-mutates, one-commit-one-history, Escape-cancels, stale-revision-
commits-nothing semantics.

## Exact write set

- `src/swift/app/drawer/velocity/VelocityPage.swift` (delete moved methods; add forwarding)
- `src/swift/app/drawer/velocity/VelocityInteraction.swift` (new)
- `src/swift/app/CMakeLists.txt` (register the new file; only if task 1 did not already pattern-cover it)

## Prerequisites

Task 1 interfaces: `VelocitySceneSnapshot.build`, `VelocityProjection`
(`xForDisplayTick/yForNote/hitTest/projectHandles`).

## Interface contract

- `VelocityInteraction` owns, with unchanged public signatures for everything
  QML/session calls: `pointerPress(x:y:surface:button:modifiers:)`,
  `pointerMove(x:y:buttons:) -> Bool`, `pointerRelease(x:y:button:) -> Bool`,
  `pointerLeave()`, `handleEscape() -> Bool`, `cancelSectionInteraction()`,
  `openSelectedVelocityPrompt() -> Bool`, `updatePromptDraft(draft:)`,
  `acceptPrompt() -> Bool`, `cancelPrompt()`, `setUseDetents(enabled:)`,
  `toggleDetents()`; internals `beginGesture/freeze/cancelGesture/finishGesture/commitVelocities/setSelection/updateRampPreview/paintBetween/updateBandPreview/updateHover/promptRevisionMismatch/isShift/isControl/detentUnlocked/detentsUnlocked/refreshInteractionPublished`
  move whole with bodies intact.
- Page keeps: lifecycle, `configureBody`, session refresh, content-apply
  (`rebuildContent` call), published state, `selectedNoteIdText()`. Forwards
  input calls to the interaction object; `interactionActive` still published
  from the same source of truth.
- Preserve: shift-drag ramp incl. out-of-span notes, band preview selection,
  detent lock/unlock incl. Ctrl/Shift gates, prompt capture/bounds/accept/
  cancel/staleness, `edit.set_velocity` availability gate behavior.
- Interaction may read Scene/Projection + `VelocityTransactions`; must not
  retain `DocumentSession` beyond a call, must not import new modules beyond
  what the moved code already uses.

## Implementation steps

1. Move the pointer/gesture/hover/ramp/band/detent/prompt declarations listed
   above whole into `VelocityInteraction.swift`; Page methods become one-line
   forwards.
2. Keep commit path verbatim: preview writes preview state only;
   `commitVelocities(_:expectedRevision:)` single history entry with revision
   guard; `cancelGesture`/`handleEscape`/`cancelPrompt` clearing the same state.
3. Keep `refreshInteractionPublished` wiring so container follow-scroll gating
   sees the identical `interactionActive` fact.
4. Do not touch Scene/Projection files except to call them; do not rename
   QML-facing prompt/detent vars.
5. Edge cases: press-release below activation distance commits nothing;
   shared-playhead motion inside one context rebuilds no static content
   (diagnostics path untouched).

## Acceptance predicate

Gesture/prompt behavior identical; Page forwards. Verified by:

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` (frozen-gesture, transactions,
  prompt, cancellation, undo/redo cases)
- `deno task verify --filter editorqml-drawer --verbose` (`velocity-lane`, `velocity-prompt` panes)
- `deno task verify --filter velocity --verbose`
- `deno task format --check`

## Task-specific constraints

- Any commit-count, revision-guard, or detent-rule divergence is a defect in
  the move, not a behavior to update. Restore verbatim bodies.
- No new swipe/double-click/keyboard behavior; no prompt redesign.
