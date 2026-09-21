# Velocity/voice split — spec

Behavior-preserving (Fowler) extraction. No gesture semantics, snap lattice,
detent rule, picker/menu rows, commit/undo shape, or QML publish names change.
Non-goal: timeline-band cutover (`velocityquick.cpp`, `voicechangequick.cpp`,
C++ areas stay live); QML logic moves (QML stays render-only); new features.

## Vocabulary

- Owner: `@QtBridgeable @MainActor` page class retained by `ApplicationSession`
  (`VelocityPage`, `VoiceChangesPage`). Owns lifecycle (`attach`/`detach`),
  session refresh, all published state, all reuse caches, and all
  publish-apply plumbing (`publish*`, `sync*`, `matches*`, `setPublished*`).
  Thin after split: lifecycle + refresh + apply only.
- Scene (pure build): static content computation from explicit inputs —
  handles/markers, rows/labels, spans, grid/gutter/typography values. Never
  retains `DocumentSession`; never touches gesture/drag/hover state except
  through its declared snapshot input (below). Reuse guarantee is scoped:
  no `QtBridge`/QML types in signatures, no retained session — not
  "timeline-ready"; a future adapter with a `DocumentSession` can call it.
- Projection: plot-relative x/y math, axis mapping, hit-test, snap. A
  context-holding value type constructed per rebuild (camera mapping,
  geometry, DPR, axis mode), not a namespace.
- Interaction: pointer/wheel/keyboard dispatch, frozen gesture/occurrence,
  hover/selection/preview, prompt/picker/menu sequencing. Implemented as
  `extension VelocityPage` / `extension VoiceChangesPage` in separate files,
  following the `AutomationInteraction.swift:117,467` precedent — no wiring
  object, no back-channel, no forwarding methods. Page refresh methods read
  interaction state directly.
- Transactions (existing): document-history commits. Unchanged shape.

## Forward interfaces (post-split)

- `VelocityScene` (`VelocityScene.swift`): `struct VelocitySceneInput`
  (notes + selection, `VelocityInteractionSnapshot`, geometry/axis/DPR/font,
  palette colors as values, bank/context resolution closure) and
  `static func build(_:) -> VelocitySceneSnapshot` producing handle rows,
  axis rows/labels, grid/band values. Page applies via the existing
  `publishHandles/publishAxis/publishGrid/publishBands` (which stay on Page).
- `VelocityInteractionSnapshot` (Sendable struct in `VelocityInteraction.swift`):
  frozen notes + preview values + detentUnlock, hovered `NoteID?`,
  `detentsEnabled`. Page builds it from live gesture/hover state per rebuild
  and passes it to Scene build. Transient/readout publication
  (`publishTransient`, `publishReadout`) stays on Page and reads live state —
  never moves to Scene.
- `VelocityProjection` (`VelocityProjection.swift`): `struct VelocityProjection`
  holding x-mapping/axis/geometry/DPR; methods `xForDisplayTick`,
  `yForNote(map:velocity:detentUnlock:)`, `hitTest(x:y:includeStems:)`.
  Reuse caches (`handleGeometryKey`, `handlesByID`, `typographyCache`,
  `metricsCache`) stay stored properties on Page; Scene/Projection take
  `reuseGeometry: Bool` + previous-handle lookup as parameters.
- `VoiceChangesScene` (`VoiceChangesScene.swift`): `struct VoiceChangesSceneInput`
  (lane points, bank slots, track, `VoiceInteractionSnapshot`, geometry/DPR/font)
  and `static func build(_:) -> VoiceChangesSceneSnapshot` producing marker
  entries, spans, labels, grid/gutter/typography values. Page applies via the
  existing `publishMarkers/publishSpans/publishGrid/publishGutter/publishTypography/publishReadout`
  (which stay on Page). `publishTransient` stays on Page.
- `VoiceInteractionSnapshot` (Sendable struct in `VoiceChangesInteraction.swift`):
  drag preview state, hover/selected occurrence identities. Page passes it per
  rebuild. Marker/span caches (`markerLookup`, `entriesRevision/entriesTrack/cachedEntries`,
  `metricsKey/cachedMetrics`) stay on Page.
- Check-facing `@QtIgnored` public accessors never move files: they stay
  declared on Page (extensions share access, so nothing breaks and no forwards
  are needed). QML-facing publish names stable.
- Snapshot field rule: snapshots carry Sendable value types and `@MainActor`
  handles only; `GridPalette`/typography objects stay build inputs, never
  outputs.

## Import rule

Scene/Projection files MAY import `QtBridge` (scene primitives
`SceneRect`/`SceneText`, `QVariantSettable` — cf. `AutomationScene.swift:4`,
`VoiceChangesProjection.swift:4`) plus `Foundation`, `PorydawCore`,
`NativeGridTypography` as needed. Interaction extension files MUST NOT contain
`import QtBridge` (they operate on Page state and call Page apply methods;
any bridge-dependent call stays a Page method). Enforced by grep in task 5.
No file adds a module import the moved code did not already use.
