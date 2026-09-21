# Task 2 — Extract velocity interaction as page extension

## Context

Second half of the velocity split. Relocates gesture/hover/prompt behavior
into `VelocityInteraction.swift` as `extension VelocityPage` (the
`AutomationInteraction.swift:117,467` precedent), consuming the task-1
Scene/Projection contract. File placement only — same type, so no wiring,
no forwards, no back-channel. Behavior change: none.

## Exact write set

- `src/swift/app/drawer/velocity/VelocityPage.swift` (delete relocated method bodies)
- `src/swift/app/drawer/velocity/VelocityInteraction.swift` (new: extension + snapshot struct)
- `src/swift/app/CMakeLists.txt` (register the new file)

## Prerequisites

Task 1 interfaces: `VelocitySceneInput/Snapshot.build`, `VelocityProjection`.

## Interface contract

- Uses `VelocityInteractionSnapshot` defined canonically in task 1 (`VelocityScene.swift`):
  this task adds the per-rebuild construction call from live gesture/hover state and the
  extension's reads of it; field extensions (if dispatch needs more) update the struct
  and Scene build reads together here.
- Relocated whole into the extension (bodies verbatim, signatures unchanged):
  `pointerPress/pointerMove/pointerRelease/pointerLeave`, `handleEscape`,
  `cancelSectionInteraction`, `openSelectedVelocityPrompt/updatePromptDraft/acceptPrompt/cancelPrompt`,
  `setUseDetents/toggleDetents`, `beginGesture/freeze/freeze/cancelGesture/finishGesture/commitVelocities/setSelection/updateRampPreview/paintBetween/updateBandPreview/updateHover`,
  `promptRevisionMismatch/isShift/isControl/detentUnlocked/detentsUnlocked/refreshInteractionPublished`.
- Stays in the Page file: lifecycle, `configureBody`, all `refresh*` (they read
  gesture state directly — same type, no accessor needed), all Scene-apply and
  publish plumbing, all stored gesture/prompt state, all check-facing
  `@QtIgnored` accessors (never move files).
- Preserve: preview-never-mutates, one-commit-one-history with revision guard,
  Escape cancels, stale revision commits nothing, shift-drag ramp incl.
  out-of-span notes, band preview, detent Ctrl/Shift gates, prompt
  capture/bounds/accept/cancel/staleness, `edit.set_velocity` gate behavior.
- Extension file MUST NOT contain `import QtBridge` (spec.md rule); it imports
  only what the moved code already uses.

## Implementation steps

1. Cut the listed method bodies into `extension VelocityPage` in the new file,
   verbatim; Page file keeps declarations' absence (no stubs, no forwards).
2. Add `VelocityInteractionSnapshot` and the per-rebuild construction call in
   `refreshAxisAndHandles`; replace task 1's placeholder field with it.
3. Keep `refreshInteractionPublished` wiring so container follow-scroll gating
   sees the identical `interactionActive` fact.
4. Do not touch Scene/Projection except to call them; do not rename any
   QML-facing or check-facing name.
5. Edge cases: press-release below activation distance commits nothing;
   playhead motion inside one context rebuilds no static content.

## Acceptance predicate

Per plan.md Verification policy; task focus: frozen-gesture policy,
gesture transactions, prompt transaction, cancellation paths, undo/redo
(`swiftcore/VelocityPage::*` cases; `velocity-lane`, `velocity-prompt`
editorqml panes).

## Task-specific constraints

- Commit-count, revision-guard, or detent-rule divergence is a move defect.
  Restore verbatim; no new input behavior, no prompt redesign.
