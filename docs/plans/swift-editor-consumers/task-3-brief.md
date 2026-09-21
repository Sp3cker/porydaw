# Task 3 — Integrate the shared Swift playhead

## Context

Follow [Global Constraints](plan.md#global-constraints), [Shared playhead](spec.md#shared-playhead), [Drawer container and page seam](spec.md#drawer-container-and-page-seam), and [Verification ownership and parity ledger](spec.md#verification-ownership-and-parity-ledger).

Tasks 1 and 2 are accepted at `5f0924e8` and `becfeb40`. The running app already has one document-owned `EditorCamera`, one `PlaybackTimeline`, one `NativeAudio`, one `PianoGrid`, one `EditorDrawerPresenter`, and one production `EditorSurface.qml`. This task adds the single playback-position presentation owner that every later page consumes. It does not add an editor page, a page-local clock, a public follow toggle, or a native bridge capability.

Behavioral authority is the current Swift architecture plus the shared-playhead behavior in `src/ui/songview/quick/{timelinequickview.cpp,TimelineCanvas.qml}`, `src/ui/songview/songview.cpp`, `src/ui/editordrawer/velocityarea/velocityarea.cpp`, `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`, and the legacy scenarios in `src/checks/drawerpresentation/velocity.cpp` and `src/checks/automation/automationcanvasediting.cpp`. These C++ sources are read-only inventories; do not compile or wrap them.

## Exact write set

Create:

- `src/swift/app/SharedPlayhead.swift`: pure follow/projection policy plus the one bridged MainActor presenter/owner and its polling lifecycle.
- `src/ui/songview/quick/swiftroll/SharedPlayhead.qml`: the production segmented/clipped playhead item.
- `src/checks/swiftcore/SharedPlayheadChecks.swift`: direct mapping, follow, publication, lifecycle, and no-rebuild policy checks.

Modify:

- `src/swift/app/ApplicationSession.swift`: retain/expose the shared presenter, bind it to the current session/audio service, refresh immediate transport/timeline/camera transitions, and cancel it during retirement/host close.
- `src/swift/app/EditorDrawer.swift`: add `interactionActive` to `EditorDrawerPage`; make resize state plus attached page activity queryable as the presenter aggregate.
- `src/ui/songview/quick/swiftroll/PianoGrid.swift`: expose its live gesture as Swift-only `interactionActive`; do not publish or duplicate gesture state to QML.
- `src/swift/app/CMakeLists.txt`: compile `SharedPlayhead.swift`.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml`: obtain the shared presenter and place one production `SharedPlayhead` across the roll plot and visible drawer body rectangles.
- `CMakeLists.txt`: add `SharedPlayhead.qml` to the existing `swift_roll_qml` resource only.
- `src/checks/swiftcore/SessionChecks.swift`: dispatch the new direct checks.
- `src/checks/CMakeLists.txt`: compile `SharedPlayheadChecks.swift`.
- `src/checks/editorqml/DrawerTestPage.swift`: satisfy the expanded page seam with real mutable interaction state.
- `src/checks/editorqml/EditorQmlTests.swift`: expose only the deterministic lane controls/observations needed to drive authoritative samples, transport state, camera projection, and test-page interaction through production owners.
- `src/checks/editorqml/tst_EditorDrawer.qml`: add production-composition shared-playhead cases; do not create a separate test QML suite or copied playhead.
- `src/checks/swiftrollgated/notevisuals.cpp`: if and only if the accepted note-border probe overlaps the now-canonical stopped tick-0 playhead, move that existing native raster probe to the legacy production-authority edge/inset so it still checks the border without requiring the playhead to disappear. This is oracle maintenance only: add no scenario, helper, infrastructure, or weakened color tolerance.

Read-only: `src/swift/core/PlaybackTimeline.swift`, `src/swift/app/{DocumentSession,NativeAudio}.swift`, existing native audio C API, all other legacy C++ production/check sources, and sibling-worktree references. No other file changes.

## Prerequisites

- HEAD includes the accepted task-2 commit `becfeb40`.
- `ApplicationSession` owns `audio`, `documentSession`, `grid`, and `drawer`.
- `DocumentSession.timeline` and `DocumentSession.camera` are current before `onPlayback`/`onChange` observers run.
- `NativeAudio.playheadSamples`, `transport`, `play()`, `pause()`, `stop()`, and `seek(sample:)` are the existing authoritative interface.
- `PlaybackTimeline.tick(for:)` is the sole sample-to-tick mapping.
- `EditorCamera.contentX(tick:)`, `snapshot.pixelsPerTick`, `snapshot.viewportWidth`, and `mutateCamera` are the existing projection/mutation path.
- `EditorSurface.qml` already knows the roll plot and every drawer body rectangle.

If any prerequisite is false, stop the task as `NEEDS_CONTEXT`; do not replace it with wall-clock interpolation, a QML timer, a bridge addition, or a copied camera.

## Interface contract

### Owner and published state

`SharedPlayhead.swift` contains one focused module. Use a pure value/policy layer for deterministic checks and one `@MainActor @QtBridgeable public final class SharedPlayheadPresenter` retained by `ApplicationSession`.

The presenter publishes QML primitives:

- `tick: Double`;
- `contentX: Double` (plot-local camera projection);
- `timelineAttached: Bool`;
- `visible: Bool` (`timelineAttached` and projected x inside the camera viewport);
- `playing: Bool` (`NativeAudio.transport == 2`); and
- `presentationCount: UInt64` (diagnostic increment for each distinct authoritative presentation accepted by the presenter).

Expose `ApplicationSession.playheadPresenter() -> SharedPlayheadPresenter` exactly once. No page gets an independent presenter. The presenter owns/cancels one polling `Task`; it does not own another document, timeline, camera, history, or audio service.

Swift-only deterministic methods may inject a `(sample, transport)` observation and set `followEnabled`; these are `@QtIgnored` and exist for policy checks, not production QML. `followEnabled` defaults true. Do not add user-facing UI.

### Polling and immediate transitions

Start polling only after `documentSession`, `grid`, and the audio binding are installed. Each iteration reads `NativeAudio.playheadSamples` and `NativeAudio.transport` on the MainActor, maps the sample through the current `DocumentSession.timeline.tick(for:)`, and presents it. Use one modest display cadence; cancellation must not be delayed by sleep.

Refresh synchronously after `playPause`, `stop`, any existing/new Swift `seek` entry point, camera publication, timeline publication/tempo edit, initial document installation, and follow-induced camera mutation. Pause/stopped presentation remains attached and shows the authoritative sample. Stop/seek behavior comes from `NativeAudio`; do not synthesize a tick.

Before scene retirement/host close: cancel the task and synchronously clear the attached presentation while owners still exist. A replacement starts a new task only after the new owners are installed. A late cancelled task must not publish into the replacement.

### Follow policy

Aggregate interaction is:

```text
grid.interactionActive || drawer.interactionActive || explicitFollowSuspension
```

`PianoGrid.interactionActive` is `gesture != nil`. `EditorDrawerPresenter.interactionActive` is true while `EditorDrawerLayout.resizeKind != nil` or any attached page reports `interactionActive`. Extend the page protocol and test page; do not infer activity from focus or QML pointer state.

When playing, follow enabled, and aggregate interaction false:

```text
x = camera.contentX(tick: tick)
if x < 0 || x > 0.85 * camera.snapshot.viewportWidth:
    target = tick * camera.snapshot.pixelsPerTick
             - camera.snapshot.viewportWidth / 10
    documentSession.mutateCamera { $0.setHScroll(target) }
```

Let camera clamping and the existing camera callback publish. Paused/stopped transport never follows. Loop wrap is just a backward authoritative sample. Equal sample/transport/camera presentation publishes nothing except where camera reprojection changes `contentX`/visibility. A camera-only refresh does not increment a content-build diagnostic.

### QML rendering

`SharedPlayhead.qml` is a visual component only. It takes the shared presenter, palette color, roll plot rectangle, and the three drawer section states/placement facts. It creates one clipped vertical segment in the roll plot and one in each visible/available body. All segments use the same presenter `contentX`; body-local x accounts only for the canonical shared plot origin.

Segments never cover the roll keyboard gutter, drawer gutters, resize handles, hidden/unavailable bodies, or bottom chrome. Keep the playhead item mounted while the timeline is attached; hide individual segments when x is outside their plot clip. Use the grid palette's existing playhead/selection color; do not add a palette source or hard-coded color. No `Timer`, `NumberAnimation`, `Behavior`, local interpolation, or page-owned playhead.

### Publication and performance invariants

- Sample-only presentation changes no `GridScene`, note summary, page content, document revision, dirty state, history, camera, or audio publication.
- Camera-only change reprojects the existing tick and may update visibility without changing the authoritative tick.
- Follow changes camera once through `mutateCamera`; the camera callback reprojects the same tick without feedback oscillation.
- Repeated identical observations are no-ops.
- 128 distinct sample positions advance presentation diagnostics but leave the grid static-scene/content-build diagnostic unchanged.

## Implementation steps

1. Add direct policy/check scaffolding first: sample mapping across tempo boundaries, paused/playing flags, visibility edges, follow thresholds/target, suspension, loop-wrap discontinuity, repeated no-op, replacement token/lifecycle, and static-content invariants.
2. Implement `SharedPlayheadPresenter` and its polling/cancellation lifecycle without touching QML.
3. Integrate it into `ApplicationSession` transport, camera, timeline, replacement, and retirement paths. Add the Swift-only interaction queries to grid/drawer/page seam.
4. Add `SharedPlayhead.qml` and mount it once in `EditorSurface.qml` using production rectangles.
5. Extend the existing editor-QML lane with production rendering and real-input/suspension cases.
6. Run only the exact commands below. Do not run project-wide formatting/lint or unrelated suites inside the writer task.

## Acceptance predicate

All are required:

- one and only one production Swift playhead owner/task exists for the attached document;
- authoritative audio samples map through the current `PlaybackTimeline` across tempo changes, seek, pause/stop, loop wrap, and document replacement;
- follow-scroll uses the exact 85%/10% policy and is suspended by grid gesture, drawer resize, page interaction, or explicit suspension;
- roll and every visible drawer body render aligned, clipped segments from the same position while gutters/chrome/hidden bodies render none;
- stopped/paused position remains visible, out-of-viewport position is clipped/hidden, camera change reprojects immediately;
- playhead-only updates do not rebuild grid/page content, mutate history/document/audio, or move the edit cursor;
- polling and late callbacks cannot survive retirement or target a replacement document;
- legacy shared-playhead/performance intent is translated to Swift/QML coverage with no C++ scenario body; and
- exact verification passes:

```bash
deno task build:app
deno task verify --filter swiftcore --verbose --qt projectSession
deno task verify:qml --filter editorqml-drawer --verbose
deno task verify --filter swiftrollgated --verbose
```

The controller also formats/checks only the changed Swift/QML files using the existing project formatter if it supports those file kinds.

## Task-specific constraints

- No editor page implementation in this task.
- No new public follow command or toggle.
- No native/C++/QtBridge/test-bootstrap expansion.
- No second polling source, page-local timer, animation, interpolation, or copied sample-to-tick math.
- No QML-derived interaction authority.
- Do not modify or commit unrelated dirty planning documents or `.scratch/`.
- The writer must report exact changed files, command outcomes, translated legacy scenario IDs, and any residual native-window/DPR/lifecycle evidence left to task 7.