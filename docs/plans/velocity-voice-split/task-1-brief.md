# Task 1 — Extract velocity scene + projection (pure build)

## Context

First half of the velocity split. Moves static content computation and plot
math out of the 1490L `VelocityPage.swift` owner into two new files per
`spec.md`. Producer for task 2, which consumes `VelocitySceneInput/build` and
`VelocityProjection`. Behavior change: none — Fowler extraction.

## Exact write set

- `src/swift/app/drawer/velocity/VelocityPage.swift` (delete moved value-computation bodies; keep orchestration, state, apply)
- `src/swift/app/drawer/velocity/VelocityScene.swift` (new: input/snapshot/build + moved value helpers)
- `src/swift/app/drawer/velocity/VelocityProjection.swift` (new: context-holding struct + moved math)
- `src/swift/app/CMakeLists.txt` (register the two new files)

## Prerequisites

None (first producer). Consumer: task 2.

## Interface contract

- `struct VelocityProjection` (Sendable value): constructed per rebuild from
  x-mapping, `geometry`, `devicePixelRatio`, axis mode. Methods `xForDisplayTick(_:)`,
  `yForNote(map:velocity:detentUnlock:)`, `hitTest(x:y:includeStems:handles:)` —
  same names; `hitTest` takes the handle set explicitly instead of reading
  `publishedHandles` (only signature change in this task, required by purity).
- `struct VelocityInteractionSnapshot` (Sendable, defined canonically in this task in
  `VelocityScene.swift`): frozen notes + preview values + detentUnlock, hovered `NoteID?`,
  `detentsEnabled`. Page builds it from live gesture/hover state per rebuild and passes it
  to Scene build. Task 2 adds only the per-rebuild construction call and uses the struct;
  if dispatch needs a field the snapshot lacks, task 2 extends the struct and its build
  reads in the same task.
- `struct VelocitySceneInput` (Sendable): notes + selection, bank/context
  resolution inputs, `VelocityInteractionSnapshot`, geometry/axis/DPR/font values,
  palette colors as values.
- `struct VelocitySceneSnapshot` (Sendable values + `@MainActor` handles only):
  `static let detached`, `static func build(_ input:) -> Self` returning handle
  rows, axis rows/labels, grid/band values. Palette/typography objects are
  inputs, never outputs.
- Moved whole (bodies verbatim, Page keeps its call sites): `rebuildAxis`
  computation half, `projectHandles` row-computation half,
  `trackNotes/selectedTrackNotes/voiceMap/contextResolver/resolvedContext/contextKey/effectiveContextTick/presentationContext`,
  `gridMetrics/timeAxis/fontMap/appendDashed`, typography value helper.
- Stays on Page (never moves): `attach/detach`, `configureBody`, all
  `refresh*`, `rebuildContent` + `refreshAxisAndHandles` orchestration,
  `publishReadout`, all `publish*/sync*/matches*/setPublished*` apply plumbing,
  `velocityNoteText`, every stored property and reuse cache
  (`axis`, `publishedHandles`, `handlesByID`, `paintCandidates`,
  `handleGeometryKey`, `typographyCache`, `metricsCache`, `palette`, `geometry`,
  `session`), every check-facing `@QtIgnored` accessor, all gesture/prompt
  methods (task 2). `rebuildContent`/`refreshAxisAndHandles` keep their
  signatures and now call `VelocitySceneSnapshot.build` + existing publish.
- New files add no module import the moved code did not use; Scene/Projection
  may import `QtBridge` per spec.md.

## Implementation steps

1. Create `VelocityProjection` with the three math methods; `hitTest` reads
   passed-in handles, not Page state.
2. Create `VelocitySceneInput/Snapshot/build`; move the listed value helpers
   whole. Gesture/hover-dependent reads (`gesture?.frozenNote/preview/detentUnlock`,
   `hovered`, `detentsEnabled`) become reads of the input snapshot, not live state.
3. Reduce Page's `rebuildAxis`/`projectHandles` to orchestration: build input
   (including the interaction snapshot from live state), call build, update
   caches, call existing publish. Cache-update + publish bodies stay verbatim.
4. Register both files in `CMakeLists.txt`; keep QML publish names unchanged.
5. Preserve verbatim: axis density bands, detent-toggle reads, stacked-node hit
   order, DPR/font scaling, ruler-vs-plot ownership, empty-track message path.

## Acceptance predicate

Per plan.md Verification policy; task focus: axis ladder, PSG rows, handle
projection, context resolution, playhead diagnostics
(`swiftcore/VelocityPage::*` cases; `velocity-lane` editorqml pane).

## Task-specific constraints

- Numeric divergence (handle x/y, labels, hit order) is a defect in the move —
  restore verbatim bodies, do not fix forward with new snapping.
- `publishTransient`/`publishReadout` are not in this task; do not move them.
