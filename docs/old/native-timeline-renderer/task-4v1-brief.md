# Task 4v1 — Velocity page model-space drawer content (Swift side)

Plan: `docs/old/native-timeline-renderer/plan.md` — read Contract ("Versioned binary layout", row §11
`drawerStatics`), Decision 1 (content handoff), Decision 7 (drawer pages), §8 phase 4 unit U4v.

## Goal

The velocity drawer page publishes its static rect layers (`gridLines`, `psgBands`, `transientRects`,
`VelocityPage.swift:211-215`) as one model-space blob instead of camera-baked `QListModel<SceneRect>`
rows, so horizontal scroll and zoom stop republishing them. A later task (U4a + QML cutover) makes the
native `TimelineRenderer` (band 3) draw the blob and deletes the models.

## Change

1. New `src/swift/app/drawer/DrawerStaticsContent.swift` (register in `src/swift/app/CMakeLists.txt`):
   the shared §11 writer. Blob framing is identical to the roll blob (`RollDrawingContent.swift`: magic
   `0x50544452`, `u16 version = 1`, `u16 sectionCount`, per section `u16 kind, u32 byteLength`),
   little-endian. It writes section 11 `drawerStatics` exactly as the plan table specifies: `u32 count`;
   per rect `u32 tickStart, u32 tickEnd, f32 y, f32 h, u32 argb, u8 flags` (bit0 `pxSpace`: x fields
   are pre-projected content px, used only for camera-free value-axis lines; bit1 `viewportSticky`).
   Reuse the roll writer's append helpers by extracting them to a shared internal location rather than
   duplicating them; keep `RollDrawingContent`'s output byte-identical.
2. `VelocityPage` gains `@QtTracked public var contentRevision` and `public func drawingContent() ->
   Data` (a slot; `Data` return is supported — same shape as `GridScene.drawingContent()`).
3. `VelocityScene.grid`/`bands`/transient rects produce tick-space records (x = ticks; y/h plot-local
   as today). Scroll (`scrollX`) must not enter any record. Zoom must not enter any record unless the
   content genuinely depends on zoom (state which, with evidence, if any).
4. `refreshHorizontalProjection` (`VelocityPublication.swift:48-62`) stops rebuilding statics on
   scroll/zoom: the revision bumps exactly once per real content change (document, selection, palette,
   PSG band inputs, transient gesture rects, plot height) and never on scroll/zoom.
5. Keep the existing `QListModel` publications and QML untouched in this task (the QML cutover task
   deletes them). Do not change `VelocityPage.qml`.
6. Checks: add a §11 decoder to the checks target (`src/checks/velocity/`, registered in
   `src/checks/CMakeLists.txt`), mirroring the plan layout, and add assertions in the existing velocity
   Swift checks proving: (a) a scroll-only and a zoom-only camera change leave `contentRevision` and the
   blob bytes unchanged; (b) a content change bumps the revision once and the decoded records carry the
   expected tick spans / colors for a known fixture. Follow existing check conventions (`report.expect`,
   `cppID`, message literals).

## Out of scope

`src/render/*`, `src/swift/app/roll/*`, `src/ui/**`, other drawer pages, proof ledgers.

## Verification (controller-run; SHARED_TREE)

The build tree is owned by another agent. Do not run `deno task` build/check/format commands; report
`tests: DEFERRED_TO_CONTROLLER`. Controller runs `deno task build:checks`, `deno task checks --filter
swiftcore --verbose`, `deno task checks:qml --verbose`.

## Global constraints

Swift 6. No code comments; delete stale comments you touch. Geometry derives from base font px. No
workarounds/fallbacks for broken invariants — report instead. Scoped searches only. No commits.
