# Qt Quick timeline column — implementation plan

## Status

Implementation plan for replacing SongView's split timeline rendering with one retained Qt Quick scene.

This supersedes the rendering direction in `docs/native-overlay-cursor-plan.md`. The useful policies from that plan remain: camera-space content-x, independent hover/edit/playhead state, source-owned hover clearing, and hover-under-edit-under-playhead precedence. Its CALayer/DComp cursor expansion, widget fallback cursor paint, and platform-layer checks do not proceed.

The first delivery stops after **Step 3**: the existing piano roll, time ruler, and other-events strip render in one SongView-owned `QQuickWidget`. Automation, velocity, voice-change, and shared timeline chrome remain later work.

## Goal

Create one **TimelineColumn** module whose interface is semantic SongView state and whose implementation owns one Qt Quick root containing every time-axis visual band.

At the end of the complete plan:

- ruler, piano roll, automation, velocity, voice-change, and other-events visuals share one Quick scene, camera, clip tree, and presentation;
- hover guide, edit cursor, and playhead are retained Quick items;
- the existing QWidget classes continue to own input, gestures, menus, focus, and document mutation;
- `PlayheadOverlay`, native CALayer/DComp playhead trees, migrated `TimelineSurface` caches, and duplicate cursor strokes are deleted.

This is not a full SongView or application rewrite. Track headers, scrollbars, splitters, drawer controls, event-list view, track activity, menus, and editing logic remain QWidget/C++.

## Current architecture

- `TimeRuler`: QWidget `paintEvent` plus QWidget input and child grid controls.
- `PianoRoll`: QWidget input owner containing the only timeline `QQuickWidget` (`PianoRollQuickView`).
- `AutomationCanvas`, `VelocityArea`, `VoiceChangeArea`, `OtherStrip`: `TimelineSurface` QWidget/QPixmap caches painted by QPainter.
- `PlayheadOverlay`: SongView child with macOS CALayer, Windows DComp, and QWidget fallback implementations.
- `SongView::refreshTimelineViews`: independently updates ruler QWidget paint, piano-roll Quick dirty sets, other-strip cache, and playhead overlay.

The split means camera and cursor changes cross distinct presentation systems. A QWidget stroke cannot reliably cover the piano-roll FBO.

## Decisions

1. **One Quick host.** `TimelineQuickView` is the only `QQuickWidget` for the timeline column. Never add one Quick widget per lane or band.
2. **SongView owns the host.** The host is not a child or implementation detail of `PianoRoll`.
3. **QWidget keeps input.** Existing ruler, roll, and strip widgets remain the hit-test and interaction surfaces. The Quick host is `WA_TransparentForMouseEvents`, `Qt::NoFocus`, and stays below those widgets and below `PlayheadOverlay` during migration.
4. **Clean cutover per band.** Once a band renders in Quick, its QWidget paint path is deleted. No permanent renderer selector or dual-renderer fallback.
5. **C++ scene graph for dense geometry.** Reuse the piano roll's batched custom `QQuickItem` pattern. Never use `QQuickPaintedItem`, QML `Canvas`, a `Shape`/QObject per note or node, or private Qt Quick APIs.
6. **QML text only for sparse labels.** Bar/beat labels, signature chips, gutter summaries, and event labels use stable item models and QML `Text` delegates.
7. **No renderer framework.** `TimelineColumn` is the module. Its ruler, roll, strip, and later drawer renderers are private implementation modules, not adapters behind an abstract `ITimelineRenderer`.
8. **One shared camera model.** SongView remains the authority for `contentX`, `tickAtContentX`, horizontal scale, and scroll. The Quick implementation receives semantic camera/layout state; callers never pass pens, QSG nodes, or painter clips.
9. **Band geometry is explicit.** The root scene owns clipped band items positioned from QWidget geometry mapped into SongView coordinates. Piano-roll scene geometry remains roll-local inside its band.
10. **Keep the native playhead temporarily.** Steps 1–3 do not expand `PlayheadOverlay` and do not move hover/edit cursor into it. Delete it only after every visible timeline plot and the ruler live in the Quick root.
11. **No full-window Quick migration.** Keep `QQuickWidget` through the column cutover. Consider one `QQuickWindow` only after measured evidence shows the single FBO remains a problem.
12. **No empty scaffold.** Each step is a complete, verified cutover with one production owner for every rendered pixel it touches.

## Module seam

`SongView` knows one rendering module: `TimelineQuickView`.

Its interface owns these facts, not rendering details:

- root geometry in SongView coordinates;
- band geometry and visibility;
- piano-roll semantic dirty set;
- ruler and other-events semantic dirty state;
- camera, theme, font, document, selection, and interaction snapshots required by those bands.

The implementation owns:

- `TimelineCanvas.qml` and clipped band items;
- scene data and text models;
- QSG geometry buffers;
- dirty coalescing and queued synchronization;
- DPR/theme/font caches;
- framebuffer coordinate mapping used by checks.

No caller receives an internal scene item or model.

## Shared geometry invariants

1. Global timeline tick 0 aligns at `SongView::Geometry::plotOrigin`.
2. The roll band starts at the mapped `PianoRoll` rectangle; its local timeline origin remains `pianoKeyboardWidth`.
3. Ruler and other-events local timeline origin remains `plotOrigin`.
4. Mapping a tick through either origin lands on the same SongView x coordinate.
5. Hidden or replaced bands publish an empty/invisible band rectangle; stale pixels cannot survive a stack-page or drawer change.
6. Root or band size changes dirty only domains whose local dimensions changed.
7. The Quick host never consumes mouse, wheel, keyboard, focus, tooltip, or context-menu events.

## Workflow gate for every implementation step

Before implementation, dispatch a `plan` agent to challenge the proposed file/symbol changes, find missing call sites, and identify a simpler cutover. Incorporate or explicitly reject each finding before editing. Reuse the same Plan agent for later steps while its session is available so reviews retain the prior design context.

After implementation, send the diff and verification evidence to the same persistent `thermo-nuclear-reviewer`. Resolve every confirmed finding, then return the revision to that same reviewer. A step is complete only when that reviewer explicitly validates the resolutions and approves the step. Stage agents skip formatters and project-wide test suites; the parent runs focused checks at each step and final formatting once.

## Step 1 — Move Quick-host ownership to SongView

**Preflight:** `plan` agent. **Implementation:** `task` agent or parent. **Review:** persistent `thermo-nuclear-reviewer`.

Files:

- `src/ui/songview.h`
- `src/ui/songview.cpp`
- `src/ui/songview/pianoroll.h`
- `src/ui/songview/pianoroll.cpp`
- `src/ui/songview/quick/pianorollquick.h`
- `src/ui/songview/quick/pianorollquick.cpp`
- focused roll/window checks if ownership is directly asserted

Change:

1. SongView creates and owns the current Quick host after constructing the complete roll-pane and drawer tree.
2. Remove the child layout and ownership from `PianoRoll`; keep `PianoRoll` as the input and scene-data authority.
3. Lower the SongView-child Quick host beneath the ruler, roll-pane, and strip widget tree. Opt only `m_rollStack` out of the application-wide opaque `QStackedWidget` background rule; its roll page remains nonpainting and its event-list page remains self-opaque.
4. Position the host at the roll's mapped SongView rectangle and synchronize it on roll show, hide, move, and resize events. Geometry synchronization never raises the host or schedules a redundant scene update.
5. Route existing `PianoRoll::requestQuickUpdate` and all six appearance events through guarded SongView-owned hooks, covering the construction interval before the host exists without an attach/setter protocol.
6. Keep the current `PianoRollCanvas.qml`, local scene coordinates, framebuffer pixels, dirty domains, and object name during this ownership-only cutover.

Acceptance:

- exactly one timeline `QQuickWidget` exists;
- its QObject parent is SongView, not PianoRoll;
- the rendered roll is pixel-identical to the pre-step framebuffer;
- roll mouse, wheel, keyboard, focus, tooltip, menus, and gesture checks still pass;
- event-list switching hides the roll pixels and restores them without stale content;
- the editor drawer still paints above the roll, and the event-list page remains opaque;
- playhead stacking remains unchanged.

## Step 2 — Expand into one timeline root

**Preflight:** `plan` agent. **Implementation:** `task` agent or parent. **Review:** the same persistent `thermo-nuclear-reviewer`.

Files:

- new `src/ui/songview/quick/TimelineCanvas.qml`
- `CMakeLists.txt`
- `src/ui/songview/quick/pianorollquick.h/.cpp`
- `src/ui/songview/quick/PianoRollCanvas.qml`
- `src/ui/songview.h/.cpp`
- rollcheck framebuffer/window harnesses

Change:

1. Rename the host to `TimelineQuickView` and load `TimelineCanvas.qml`.
2. Expand the host geometry to the timeline-column rectangle from the ruler top through the other-events bottom, excluding the horizontal scrollbar.
3. Publish explicit ruler, roll, and other-events band rectangles in root-local coordinates.
4. Instantiate the existing piano-roll content inside a clipped roll-band item. Preserve every existing piano-roll layer and text model.
5. Size-driven piano-roll invalidation follows the roll band size, not the root widget size.
6. Keep unmigrated ruler, strip, and drawer widgets painting opaquely above the root. Keep all input widgets above the root and transparent to Quick events.
7. Update framebuffer checks to crop/sample the roll band from the unified root rather than assuming the framebuffer equals the roll size.

Acceptance:

- one Quick host spans the complete timeline column;
- only the roll band is exposed from Quick; existing ruler, strip, and drawer visuals are unchanged;
- roll output remains pixel-identical after translating framebuffer coordinates by the band offset;
- resizing, drawer changes, event-list switching, and font/theme changes keep all band rectangles aligned;
- QWidget input remains authoritative across ruler, roll, and strip;
- `PlayheadOverlay` stays above the root with unchanged behavior.

## Step 3 — Port TimeRuler and OtherStrip visuals

**Preflight:** `plan` agent. **Implementation:** `task` agent or parent. **Review:** the same persistent `thermo-nuclear-reviewer`.

Files:

- `src/ui/songview/quick/TimelineCanvas.qml`
- `src/ui/songview/quick/pianorollquick.h/.cpp`
- new focused timeline Quick geometry/scene files as required by the reviewed design
- `src/ui/songview/timeruler.h/.cpp`
- delete `src/ui/songview/timeruler_paint.cpp` after cutover
- `src/ui/songview/otherstrip.h/.cpp`
- `src/ui/songview.h/.cpp`
- `CMakeLists.txt`
- `src/checks/rollcheck/loading_ruler.cpp`
- `src/checks/rollcheck/keyboard.cpp`
- `src/checks/rollcheck/harness.cpp`
- playhead/windowing checks where composite capture changes

Shared primitive rule:

Extract or generalize the existing batched rectangle/text machinery only when ruler/strip become its second consumers. Add triangle geometry only for shapes that require it, such as other-event diamonds. Do not create parallel QSG chunk implementations.

### TimeRuler

Move these pixels into its clipped Quick band:

- chrome background and separator;
- pre-roll fill;
- time selection and loop fills/edges;
- edit cursor stroke while shared chrome has not yet migrated;
- sub-grid, beat, and bar ticks;
- bar/beat labels;
- time-signature chips and marker lines;
- loop bracket labels;
- marker/time-signature drag preview and time-selection handles.

Keep in `TimeRuler` C++:

- grid control widgets;
- tick enumeration and adaptive label decisions;
- hit testing, scrub, wheel, loop/signature/selection gestures;
- menus and document mutations.

### OtherStrip

Move these pixels into its clipped Quick band:

- background and separator;
- gutter summary text;
- pre-roll, loop/time-selection overlays, and edit cursor;
- track-colored event diamonds.

Keep in `OtherStrip` C++:

- event hit testing;
- tooltip text and display;
- font-relative geometry policy.

After cutover, `TimeRuler` is a nonpainting QWidget input host. `OtherStrip` emits no migrated pixels from `paintContent`, but remains a transparent `TimelineSurface` through Step 7 so existing cache diagnostics continue to exercise the composition seam. Its `TimelineSurface` base and transparent cache are removed only with the obsolete rendering infrastructure in Step 7. Child controls and tooltips remain QWidget-owned.

Acceptance:

- ruler, roll, and other-events pixels come from the same Quick framebuffer and present together;
- no ruler `paintEvent` and no migrated other-strip pixels from `paintContent` remain; the strip's transparent `TimelineSurface` composition survives until Step 7;
- ruler and strip QWidget grabs/composite captures match the visual contract across themes and DPR;
- bar/beat density, signatures, loop brackets, selection, pre-roll, edit cursor, and event diamonds match before-cutover geometry and colors;
- grid controls, ruler gestures, strip tooltips, roll gestures, and playhead stacking still work;
- camera changes issue one coalesced Quick synchronization for the three migrated bands;
- no QML object per tick or event marker and no duplicate QSG geometry engine.

## Step 4 — Port velocity and voice-change visuals

**Preflight:** `plan`. **Implementation:** `task`. **Review:** the persistent `thermo-nuclear-reviewer` for that implementation run.

- Batch velocity stems, points, selection rings, PSG bands, axis ticks, and gesture previews.
- Batch voice held spans and marker geometry; preserve C++ label collision/elision and publish sparse text records.
- Keep QWidget input and document mutation.
- Remove both `TimelineSurface` paint paths after framebuffer and gesture checks pass.

## Step 5 — Port automation with visible-row virtualization

**Preflight:** `plan`. **Implementation:** `task`. **Review:** the persistent `thermo-nuclear-reviewer` for that implementation run.

- Render only rows intersecting the automation viewport; never allocate a Quick surface matching the full scroll-area content height.
- Keep `AutomationProjection`, lane state, gestures, selection, and commits in C++.
- Split scene data by grid, curves, points, selection, and transient gesture previews so mouse movement cannot rebuild unrelated geometry.
- Remove `AutomationCanvas` painting and cache only after all automation visual/gesture checks pass.

## Step 6 — Move shared timeline chrome and delete platform overlay

**Preflight:** `plan`. **Implementation:** `task`. **Review:** the persistent `thermo-nuclear-reviewer` for that implementation run.

- Add stable retained hover-guide, edit-cursor, and playhead Quick items with independent positions and hidden state.
- Use camera-space content-x and the root band clip tree.
- Enforce z-order: hover, edit, playhead.
- Remove duplicate per-band edit/hover strokes.
- Delete `PlayheadOverlay`, macOS CALayer renderer, Windows DComp renderer, widget fallback, native layer tests, and their CMake wiring.

## Step 7 — Remove obsolete timeline rendering infrastructure

**Preflight:** `plan`. **Implementation:** `task`. **Review:** the persistent `thermo-nuclear-reviewer` for that implementation run.

- Delete `TimelineSurface` if no users remain.
- Delete migrated QPainter-only helpers and cache diagnostics.
- Retarget captures to the unified Quick framebuffer/composite.
- Remove obsolete strip-invalidation and split-present assertions.

## Checks for the first delivery

Run focused checks after the relevant step; no project-wide suite inside implementation/review agents:

```sh
deno task build:checks
deno task verify --filter rollcheck --verbose
deno task verify --filter hostcheck --verbose
deno task format --check
```

Manual verification after Step 3:

- resize and pan with ruler, roll, and other events visible;
- use the ruler grid controls, scrub, loop markers, time signatures, and time selection;
- hover event diamonds and verify tooltips;
- switch roll/event-list pages;
- open/resize/collapse the editor drawer;
- change theme and font scale;
- confirm ruler, roll, and other-events move in one presented frame while the native playhead remains above them.

## Rejected

- Extending `PlayheadOverlay` with hover/edit CALayer or DComp visuals before the timeline-column migration.
- A separate `QQuickWidget` for each band.
- Rewriting input and editing behavior in QML.
- `QQuickPaintedItem` wrappers around existing QPainter functions.
- One QML delegate per note, automation point, grid tick, or event marker.
- An abstract renderer interface with one implementation.
- Keeping old and new renderers behind an environment switch.
- Moving to `QQuickWindow` before measuring the single-root `QQuickWidget`.
