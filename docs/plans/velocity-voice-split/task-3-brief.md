# Task 3 — Extract voice scene (pure)

## Context

First half of the voice split. Moves static marker/span/label/grid content
build out of the 1211L `VoiceChangesPage.swift` owner into pure
`VoiceChangesScene.swift`, mirroring task 1. Producer for task 4. Behavior
change: none.

## Exact write set

- `src/swift/app/drawer/voicechanges/VoiceChangesPage.swift` (delete moved declarations; keep owner + forwarding)
- `src/swift/app/drawer/voicechanges/VoiceChangesScene.swift` (new)
- `src/swift/app/CMakeLists.txt` (register the new file)

## Prerequisites

None on tasks 1–2 (disjoint write set; may run parallel). Consumer: task 4.

## Interface contract

- `VoiceChangesSceneSnapshot` (Sendable, pure): `static let detached` plus
  `static func build(...)` over `(session: DocumentSession, camera: EditorCamera,
  geometry, bank slots, track, plot size/DPR/font)` returning marker entries,
  spans, slot-label inputs, grid/gutter/typography/readout inputs. Field names
  match what `publishMarkers/publishSpans/publishGrid/publishGutter/publishTypography/publishReadout` consume.
- Move whole: `markerEntries`, `projectMarkers(_:reuseGeometry:)`,
  `publishMarkers/publishSpans/publishGrid/publishGutter/publishTypography/publishReadout/countSummary/publishTransient`,
  `slotViews`, `contextLabel(at:)`, `lanePoints`, `firstProgram`,
  `syncPickerRows` (picker-row build only; dispatch stays task 4).
  Preserve `VoiceProjectionEntry`, `VoiceMarkerHandle`, `VoicePickerRowHandle`,
  `VoiceLanePolicy.swift`, `VoiceChangesProjection.swift` (526L), `VoiceChangesTransactions.swift` (106L) untouched.
- New file imports `Foundation` + `PorydawCore` only. Never `QtBridge`; never
  retains `DocumentSession`. Slot-blank rule stays verbatim (blank/read-only/
  broken slots publish no parsed voice; fallback program-number → type-name →
  "Voice").

## Implementation steps

1. Move the listed build/publish-input declarations whole; Page keeps thin
   `publish*` apply calls over the snapshot plus lifecycle/refresh (`attach/detach`,
   `configureBody`, `refreshFromDocument/refreshEditCursor/refreshCamera/refreshPlayhead`).
2. Keep track-switch full re-derivation, bank-slot label sourcing, held-program
   spans, right-aligned context readout, marker hit radius, playhead-diagnostic
   retention behavior (`publishTransient` untouched semantically).
3. Register the new file in `CMakeLists.txt` beside `drawer/voicechanges/VoiceChangesPage.swift`.
4. Do not move pointer/picker/menu/hover methods (task 4 owns `pointerPress/Move/Release/Leave/DoubleClick`,
   `captureTarget/openPicker/openMenu`, picker + menu dispatch, `updateHover/clearHover`, `cancelDrag/cancelPan`, `commit`).
5. Edge cases: empty-lane message, second-track fixtures, crossing vs inside-span
   playhead updates (rebuild-once rules preserved).

## Acceptance predicate

Scene output identical; owner thin; new file import-clean. Verified by:

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` (marker projection, labels,
  context, identity, history cases)
- `deno task verify --filter editorqml-drawer --verbose` (`voice-picker` pane + drawer)
- `deno task verify --filter drawerpresentation --verbose` (legacy voice/menus unchanged)
- `deno task format --check`

## Task-specific constraints

- Label/symbol diffs are defects in the move, not bank updates. Keep
  `paintTextFor` fallback order verbatim.
- No picker filtering/sorting changes; no new collision policy.
