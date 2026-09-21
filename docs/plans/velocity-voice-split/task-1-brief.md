# Task 1 — Extract velocity scene + projection (pure)

## Context

First half of the velocity split. Move static content build and plot math out
of the 1490L `VelocityPage.swift` owner into two pure files per `spec.md`,
so a future timeline adapter can call the same build. Producer for task 2,
which consumes the extracted projection/interaction boundary. Behavior change:
none — Fowler extraction, identical numbers.

## Exact write set

- `src/swift/app/drawer/velocity/VelocityPage.swift` (delete moved declarations; keep owner + forwarding)
- `src/swift/app/drawer/velocity/VelocityScene.swift` (new)
- `src/swift/app/drawer/velocity/VelocityProjection.swift` (new)
- `src/swift/app/CMakeLists.txt` (register the two new files)

## Prerequisites

None (first producer). Consumer: task 2.

## Interface contract

- `VelocitySceneSnapshot` (Sendable, pure): `static let detached` plus
  `static func build(...)` over `(session: DocumentSession, camera: EditorCamera,
  geometry: AutomationPlotGeometry`-equivalent velocity geometry, bank slots,
  selection, plot size/DPR/font)` returning handles, axis rows/labels, grid/band
  inputs. Field names match what `publishHandles/publishAxis/publishGrid/publishBands`
  already consume — no publish-name changes.
- `VelocityProjection` (pure): `xForDisplayTick(_:)`, `yForNote(map:velocity:detentUnlock:)`,
  `hitTest(x:y:includeStems:) -> NoteID?`, `projectHandles() -> [VelocityHandle]`.
  Bit-identical mapping to today's private methods (same names, same signatures,
  now internal to the new file); `VelocityPage` forwards.
- Preserve: `VelocityHandle` + `matches`, `VelocityPagePolicy`, `VelocityInputSurface`,
  `VelocityQtButton`, `VelocityModifier`, `VelocityAxis.swift`, `VelocityContext.swift`,
  `VelocityTransactions.swift` untouched. Do not move gesture/prompt methods
  (task 2 owns `pointerPress/Move/Release/Leave`, `beginGesture/freeze/cancelGesture/finishGesture`,
  `updateRampPreview/paintBetween/updateBandPreview/updateHover`, prompt dispatch).
- New files import `Foundation` + `PorydawCore` only (plus existing typography
  helper if the moved code already uses it). Never `QtBridge`; never retain `DocumentSession`.

## Implementation steps

1. Move content-rebuild declarations whole: `rebuildContent`, `refreshAxisAndHandles`,
   `rebuildAxis`, `projectHandles`, `xForDisplayTick`, `yForNote`, `hitTest`,
   `publishHandles/syncRects/syncTexts/matchesText/rectMatches/fontMatches/publishAxis/fontMap/gridMetrics/timeAxis/publishGrid/publishBands/publishTransient/appendDashed`
   bodies into Scene/Projection by responsibility (build vs math vs publish-apply;
   apply stays on Page as thin `publish*` calls over the snapshot). Keep every
   branch, radius, density band, detent-toggle read, and stacked-node hit order.
2. Keep `attach/detach`, `configureBody`, `refreshFromDocument/refreshEditCursor/refreshCamera/refreshPlayhead`,
   composition input, and all gesture/prompt state exactly where they are.
3. Register both new files in `CMakeLists.txt` beside `drawer/velocity/VelocityPage.swift`.
4. Enforce import rule on the new files; no `QListModel`/`SceneRect`/`QVariant`
   types leak into Scene/Projection (those stay behind Page publish calls).
5. Edge cases to preserve verbatim: continuous vs PSG axis density, empty-track
   message path, DPR/font scaling, ruler `[0, gutter)` vs plot-x ownership.

## Acceptance predicate

Behavior identical; owner thin; pure files import-clean. Verified by:

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` (VelocityPage axis/projection/context/gesture Concept cases)
- `deno task verify --filter editorqml-drawer --verbose` (`velocity-lane` pane)
- `deno task verify --filter velocity --verbose` (legacy C++ unchanged)
- `deno task format --check`

## Task-specific constraints

- If any numeric output differs (handle x/y, axis labels, hit order), stop: the
  extraction is wrong, do not "fix forward" with new snapping. Keep the old
  method bodies verbatim in the new home.
- Do not rename published QML-facing vars (`handles`, axis/grid/band models).
