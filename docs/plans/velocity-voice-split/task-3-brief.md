# Task 3 — Extract voice scene (pure build)

## Context

First half of the voice split. Moves static marker/span/label/grid value
computation out of the 1211L `VoiceChangesPage.swift` owner into pure
`VoiceChangesScene.swift`, mirroring task 1. Producer for task 4. Disjoint
write set from tasks 1–2; may run parallel. Behavior change: none.

## Exact write set

- `src/swift/app/drawer/voicechanges/VoiceChangesPage.swift` (delete moved value-computation bodies; keep orchestration, state, apply)
- `src/swift/app/drawer/voicechanges/VoiceChangesScene.swift` (new: input/snapshot/build + moved value helpers)
- `src/swift/app/CMakeLists.txt` (register the new file)

## Prerequisites

None on tasks 1–2. Consumer: task 4.

## Interface contract

- `struct VoiceInteractionSnapshot` (Sendable, defined canonically in this task in
  `VoiceChangesScene.swift`): drag preview state, hover/selected occurrence identities.
  Page builds it per rebuild from live drag/hover/selection state. Task 4 adds only the
  per-rebuild construction call and uses the struct; field extensions update the struct
  and its build reads together there.
- `struct VoiceChangesSceneInput` (Sendable): lane points, bank slots, track,
  `VoiceInteractionSnapshot`, geometry/DPR/font values.
- `struct VoiceChangesSceneSnapshot` (Sendable values + `@MainActor` handles
  only): `static let detached`, `static func build(_:) -> Self` returning marker
  entries, spans, slot-label values, grid/gutter/typography/readout values.
- Moved whole (value computation only, bodies verbatim): `markerEntries`,
  `projectMarkers` entry-computation half, `slotViews`, `lanePoints`,
  `firstProgram`, `countSummary`, grid/gutter/typography value helpers behind
  `publishGrid/publishGutter/publishTypography`, `xForTick`, `snapTick`,
  `markerHit`, `effectiveContextTick`, `contextKey`, and a pure
  `sceneContextLabel(slot:slots:)` helper backing `contextLabel(at:)`.
- Stays on Page (never moves): `attach/detach`, `configureBody`, all `refresh*`,
  `rebuildContent` orchestration, `publishMarkers/publishSpans/publishGrid/publishGutter/publishTypography/publishReadout/publishTransient`
  apply bodies, `syncPickerRows` + `publishPicker/refreshPicker/selectPickerProgram`
  (picker-row apply; row dispatch moves in task 4), `contextLabel(at:)` (kept;
  calls the Scene helper), `updateHover/clearHover` behavior ownership stays
  task 4 but the methods move there, every stored property and cache
  (`published`, `markerLookup`, `pickerCache`, `caption/title`,
  `metricsKey/cachedMetrics`, `entriesRevision/entriesTrack/cachedEntries`,
  `soundingProgram`, grid/font helpers, `fontFamily`), every check-facing
  `@QtIgnored` accessor.
- Preserve verbatim: slot-blank rule (blank/read-only/broken publish no parsed
  voice; fallback program-number → type-name → "Voice"), held-program spans,
  right-aligned readout, marker hit radius, track-switch full re-derivation,
  inside-vs-crossing-span playhead rebuild rules.
- New file adds no module import the moved code did not use; may import
  `QtBridge` per spec.md.

## Implementation steps

1. Create input/snapshot/build; move the listed value helpers whole.
   Drag/hover/selected-identity reads become reads of the input snapshot.
2. Reduce Page's `projectMarkers` to orchestration: build input, call build,
   update `markerLookup`/entry caches, call existing publish. Apply bodies stay.
3. Register the new file in `CMakeLists.txt`; keep QML publish names unchanged.
4. Do not move pointer/picker/menu/hover/drag dispatch (task 4).
5. Edge cases: empty-lane message, second-track fixtures, collision/blank-slot
   commit rules unchanged.

## Acceptance predicate

Per plan.md Verification policy; task focus: marker projection, slot labels,
voice context, occurrence identity, history (`swiftcore/VoiceChangesPage::*`
cases; `voice-picker` editorqml pane).

## Task-specific constraints

- Label/symbol diffs are move defects, not bank updates. Keep the
  `paintTextFor` fallback order verbatim.
- `publishTransient` is not in this task; do not move it.
