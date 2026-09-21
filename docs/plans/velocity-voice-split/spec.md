# Velocity/voice split — spec

Behavior-preserving (Fowler) extraction. No gesture semantics, snap lattice,
detent rule, picker/menu rows, commit/undo shape, or QML publish names change
unless a brief names the rename. Non-goal: timeline-band cutover
(`velocityquick.cpp`, `voicechangequick.cpp`, C++ areas stay live); QML logic
moves (QML stays render-only); new features.

## Vocabulary

- Owner: `@QtBridgeable @MainActor` page class retained by `ApplicationSession`
  (`VelocityPage`, `VoiceChangesPage`). Owns lifecycle (`attach`/`detach`),
  session refresh (`refreshFromDocument`, `refreshEditCursor`, `refreshCamera`,
  `refreshPlayhead`), and publication. Thin after split (~250L).
- Scene (pure): static content build from `DocumentSession` — handles/markers,
  rows/labels, spans, grid/gutter/typography inputs. No `QtBridge`, no gesture
  state, no session retention. Reusable by a future timeline adapter.
- Projection (pure): plot-relative x/y math, axis mapping, hit-test, snap.
  No `QRect`, no QML types.
- Interaction: pointer/wheel/keyboard dispatch, frozen gesture/occurrence,
  hover/selection/preview, prompt/picker/menu sequencing. Calls Scene and
  `VelocityTransactions` / `VoiceChangesTransactions` for commits.
- Transactions (existing): document-history commits. Unchanged shape.

## Forward interfaces (post-split)

- `VelocitySceneSnapshot` (`VelocityScene.swift`, pure): `static build(session:camera:geometry:...)`
  + `detached`; Page applies it via existing `publishHandles/publishAxis/publishGrid/publishBands/publishTransient`.
- `VelocityProjection` (`VelocityProjection.swift`, pure): `xForDisplayTick`,
  `yForNote(map:velocity:detentUnlock:)`, `hitTest(x:y:includeStems:)`,
  `projectHandles()` inputs. Same numeric behavior as today.
- `VelocityInteraction` (`VelocityInteraction.swift`): owns `pointerPress/Move/Release/Leave`,
  `beginGesture/freeze/cancelGesture/finishGesture`, `updateRampPreview/paintBetween/updateBandPreview/updateHover`,
  prompt dispatch, `handleEscape/cancelSectionInteraction` behavior. Page forwards.
- `VoiceChangesSceneSnapshot` (`VoiceChangesScene.swift`, pure): `markerEntries/projectMarkers`
  inputs, `publishMarkers/publishSpans/publishGrid/publishGutter/publishTypography/publishReadout` inputs.
- `VoiceChangesInteraction` (`VoiceChangesInteraction.swift`): owns
  `pointerPress/Move/Release/Leave/DoubleClick`, `captureTarget/openPicker/openMenu`,
  picker + menu dispatch, `updateHover/clearHover`, `cancelDrag/cancelPan`.
  Occurrence-identity + camera-scroll staleness rules unchanged.
- QML (`VelocityPage.qml`, `VelocityPrompt.qml`, `VoiceChangesPage.qml`,
  `VoicePicker.qml`, `VoiceChangeMenu.qml`): render published primitives only.
  Publish names stable; task 5 lists the only renames (none planned — cutover
  is include/delegate, not rename).

## Import rule

Only the Owner and Transactions import `QtBridge`. Scene/Projection/Context/
Policy import `Foundation` + `PorydawCore` (+ `NativeGridTypography` where
already used) and never retain `DocumentSession`. Enforced by grep in task 5.
