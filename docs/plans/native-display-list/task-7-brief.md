# Task 7 brief — Voice-changes drawer on display lists

## Context

Voice-changes cuts over from the C++ drawer raster to per-frame Swift
viewport-space `PdDlRect`s. It replaces `VoiceChangesPage.drawingContent()` /
`contentRevision` with plan Contract §3 list 0 (grid) and consumes the
`DrawerStaticsContent` builder API defined by Task 6 without re-deciding it.
Held-span fills (§11 tick-space rects) and grid lines (§7 time axis) move
into one Swift-built list; markers stay QML delegates.

## Exact write set

- `src/swift/app/drawer/voicechanges/VoiceChangesPage.swift`
- `src/swift/app/drawer/voicechanges/VoiceChangesPublication.swift`
- `src/ui/songview/quick/drawer/VoiceChangesPage.qml`
- `src/swift/app/DocumentWorkspace.swift` (only `applyCamera`, `:383-391`)
- `src/checks/drawerpresentation/VoiceChangesPageChecks.swift` (scroll/zoom stability, lane-write republish)
- `src/checks/drawerpresentation/voice_projection.swift` (held-span count via `VelocityContentProbe`, rewritten by Task 6 — consume, do not co-edit)
- `src/checks/drawerpresentation/voice_interaction.swift` (detach publishes no held span)
- `src/checks/editorqml/tst_EditorDrawerVoiceTransactions.qml`
- `src/checks/editorqml/tst_EditorDrawerVoicePicker.qml`
- `src/checks/editorqml/tst_EditorDrawerVoiceInputIsolation.qml`
- `src/checks/editorqml/tst_ShellDrawerParityVoiceVelocity.qml` (shared with Task 6; this task owns the voice-half edits only)

## Prerequisites

- Task 1 interfaces (`DisplayListWriter`, wire format) and Task 2
  (`DisplayList` item fetch protocol).
- Task 6's rewritten `DrawerStaticsContent` builder API (`buildGrid`,
  `buildTickRects`, `buildAnchored`, `buildDashedFrame`); this task calls it
  and must not modify it — mismatches are reported, not worked around.

## Interface contract

- `VoiceChangesPage` (in its `@QtBridgeable` class body):
  `@QtTracked public var displayRevision = 0` and
  `public func displayList(_ list: Int) -> Data` with list 0 only, per plan
  Contract §3. Rebuilds bump `displayRevision` once. `drawingContent()` /
  `contentRevision` (`VoiceChangesPage.swift:174-175`) / `drawingContentData`
  (`:250`) are removed; no shim remains.
- Per-frame Swift builder (extending the existing `rebuildContent` /
  `publishDrawingContent(entries:session:)` at
  `VoiceChangesPublication.swift:82-136`): writes list 0 through
  `DisplayListWriter`, retaining the buffer across frames:
  - grid via `DrawerStaticsContent.buildGrid` over the visible tick range
    (`RollGrid.forEachSubdivision`,
    `src/swift/app/timeline/GridGeometry.swift:309-339`;
    `TimeAxis.forEachGridLine`,
    `src/swift/app/timeline/TimeAxis.swift:120-160`), projected with the
    unified `viewX`/`displayX`, culled as `drawer_scene.cpp:31-65` does;
  - held spans via `buildTickRects` from the rects assembled at
    `VoiceChangesPublication.swift:97-120` (program-section fills,
    `tickStart`/`tickEnd`, full plot height, track-identity alpha-18 color);
  - no anchored records and no dash pattern on this page (no `flags: 4`
    producer exists here); `buildAnchored`/`buildDashedFrame` are not called.
- Empty-page behavior preserved: `VoiceChangesPage.swift:294-297` clears to
  empty bytes + revision bump on detach; the display-list equivalent is an
  empty list 0 with a bumped `displayRevision`.

## Implementation steps

1. Replace `publishDrawingContent(entries:session:)` internals to emit
   through `DisplayListWriter` + Task 6 builders instead of
   `DrawerStaticsContent.pack` (`VoiceChangesPublication.swift:130-135`);
   keep the held-span assembly (`:97-120`) and palette/metrics inputs.
2. Add `displayRevision` / `displayList(_:)`; remove `contentRevision`,
   `drawingContent()`, `drawingContentData`. Rebuild trigger: existing
   `rebuildContent` and its camera path (`VoiceChangesPage.refreshCamera` at
   `VoiceChangesPage.swift:377-381` → `rebuildContent` at
   `VoiceChangesPublication.swift:82-95`); camera moves must change bytes +
   revision since grid lines are camera-derived. Today scroll-only camera
   changes skip this page (`DocumentWorkspace.applyCamera`, arm
   `(.voiceChanges, false): break`, `:383-391`) because the C++ item read
   `scrollX` itself; the list is viewport-space, so that arm becomes
   `voiceChangesPage.refreshCamera()`. Leave `deferredCameraZoom` and the
   other arms alone (plan Contract §7).
3. Flip `VoiceChangesPage.qml`: replace the `TimelineRenderer` item
   (`voiceGridLines` at `:279-288`) with
   `DisplayList { source: pageModel (existing contentSource); list: 0; revision: pageModel.displayRevision }`,
   objectName preserved; delete `band` / `pixelsPerTick` / `scrollX` /
   `devicePixelRatio` / `contentRevision` bindings on that item. Do not touch
   marker delegates, translated container, or gutter.
4. Migrate the checks in the write set from `drawingContent()` /
   `contentRevision` to `displayList(0)` / `displayRevision`:
   `VoiceChangesPageChecks.swift:224-270` (scroll/zoom stability, lane-write
   republish), `voice_projection.swift:40-44`, `voice_interaction.swift:272-276`
   (decode via the Task 6-rewritten `VelocityContentProbe`; do not co-edit the
   probe), keeping the camera-stability assertions' intent inverted as in Task
   6 (camera moves change bytes + revision). The QML files keep working
   through the preserved `voiceGridLines` objectName; edit them only where an
   assertion names `TimelineRenderer` properties or `contentRevision`.

## Acceptance predicate

- `deno task checks:qml --verbose` covers the voice QML suites and raster
  identity of grid + held spans at dpr 1/2.
- `deno task checks:shell --verbose` covers shell voice/velocity parity
  journeys.
- `deno task checks --filter swiftcore --verbose` covers the rewritten
  `VoiceChangesPageChecks` and voice projection/interaction suites.
- `deno task checks:bridge` covers the new `displayRevision`/`displayList`
  surface and removed members.
- `deno task proof check --executed` covers ledger health.
- Gap: per-frame pack cost is covered only by controller manual smoke
  (screenshots + Instruments against the Task 0 budget).

## Task-specific constraints

- This task does not edit `DrawerStaticsContent.swift` (single writer: Task
  6). If the Task 6 API cannot express the held-span fills, stop and report
  the gap instead of adding a local pack path.
- All records use `PD_DL_ID_NONE`; paint order is record order.
