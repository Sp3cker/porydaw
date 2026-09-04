# SongView layout refactor

## Status

Approved design intent. Implementation has not started.

This plan makes the visible SongView structure its actual geometry: fixed chrome and labels live left of one canonical timeline split, time-based plots live right of it, and `PlayheadOverlay` is rooted in the timeline column. The playhead retains a mask for scrollbars, resize handles, separators, hidden rows, and other holes inside that column.

The canonical split is the right edge of the piano-key strip and the left edge of the scrolling piano-roll plot. Do not describe it as the right edge of the piano roll.

Open product or architecture decisions: none. Preserve existing behavior unless this plan explicitly changes it.

## Goal

After this refactor, SongView has three physical horizontal columns:

```text
[ track-header column ][ piano-key column ][ timeline column ]
                                           ^ canonical split / tick-zero plot edge
```

Every visible row uses those columns consistently:

| Row | Fixed-side content | Time-based content |
| --- | --- | --- |
| Ruler | Corner/gutter spanning the two fixed columns | Ruler plot |
| Piano roll | Track headers, then piano keys | Notes and grid |
| Other events | Label section left of the split | Other-events plot |
| Voice changes | Label section left of the split | Voice-change plot |
| Automation | Lane labels and its left scrollbar left of the split | Automation plot |
| Velocity | Label/axis in the piano-key column | Velocity plot |

Label sections must end no farther right than the canonical split. Their right edges must align vertically with the right edge of the piano-key strip. The velocity label/axis deliberately occupies the same horizontal column as the piano keys.

`PlayheadOverlay` covers only the timeline column. Layout prevents it from entering track headers, piano keys, or label sections. Its retained mask prevents it from drawing over non-plot areas within the timeline column.

## Target invariants

1. `SongView` owns one resolved `trackHeaderWidth`, `pianoKeyboardWidth`, and `timelineSplitX`.
2. `timelineSplitX == trackHeaderWidth + pianoKeyboardWidth` in SongView coordinates.
3. Tick-zero plot edges for ruler, roll, other events, automation, velocity, and voice changes all equal `timelineSplitX`.
4. Fixed-side label and control rectangles never extend right of `timelineSplitX`.
5. Velocity labels occupy `[trackHeaderWidth, timelineSplitX)`.
6. Timeline plot rectangles begin at `timelineSplitX`; they may have different right edges where scrollbars consume space.
7. `PlayheadOverlay` is positioned at `timelineSplitX` and uses timeline-local coordinates where local `x = 0` is the plot edge.
8. The overlay mask contains plot rectangles only. Track headers and label rectangles cannot enter it.
9. A playhead whose core has local `x < 0` is fully hidden; no clipped bloom or triangle remains at the plot edge.
10. The playhead remains absent over scrollbars, drawer resize handles, separators, the drawer bar, and the event-list body.
11. Visual ownership, hit testing, context menus, wheel behavior, focus, keyboard audition, and accessibility follow the same physical rectangles.
12. Production uses the native macOS CALayer compositor on macOS and the Qt Quick `TimelinePlayheadItem` on Windows/Linux. The software QWidget fallback, Windows DirectComposition renderer, and `PORYDAW_FORCE_*` environment variables were already removed in commit `8eea7b9`.

## Current implementation and problem

### Repeated split geometry

`SongView::Geometry::resolve()` already computes the intended split in `src/ui/songview.cpp`:

```text
trackHeaderWidth     = fontPx(17.5)
pianoKeyboardWidth  = fontPx(13.0 / 3.0)
plotOrigin           = fontPx(17.5 + 13.0 / 3.0)
```

Equivalent values are independently repeated in:

- `AutomationGeometry::resolve()` in `src/ui/editordrawer/automationprojection.cpp`;
- `VoiceChangeArea` geometry in `src/ui/editordrawer/voicechangearea/voicechangearea.cpp`;
- `DrawerSections::ensureChrome()` in `src/ui/editordrawer/drawersections.cpp`;
- piano-roll geometry for the key width.

These values align today only because their formulas happen to match. The refactor must make the SongView-resolved column widths the sole source and pass them to dependent modules.

Velocity is a deliberate local-coordinate exception, not a conflicting split. Its body is offset by the track-header width, and its local plot origin is the piano-key width. This places its label/axis in the piano-key column and its plot at the shared SongView split. Preserve that visual result while replacing duplicated arithmetic.

### Bands combine chrome and plots

`TimelineBandGeometry` currently contains a full SongView-local band rectangle plus `timelineOrigin`, the plot offset inside that rectangle. Labels, plot pixels, and input can therefore occupy one owner-wide surface while consumers reproduce the split with coordinate tests.

Examples:

- Other-event and voice-change labels are painted into the part of their band before `plotOrigin`.
- Automation labels and its vertical scrollbar are accounted for with compensating offsets.
- Several `TimelineInputItem`s fill an entire band, while C++ interaction code rejects or reroutes positions before `plotOrigin`.

The rendered division is real to the user but not real in layout ownership.

### PlayheadOverlay is owner-wide

`SongView::syncTimelineIndicators()` sends `TimeCamera::contentX(m_playheadTick)` to `PlayheadOverlay`. The overlay then adds a ruler-derived `m_timelineOrigin` through `finalX()`, driving the native macOS `Platform` CALayer or forwarding via `TimelineQuickView::setPlayhead()` to the Qt Quick `TimelinePlayheadItem` on non-macOS platforms.

`PlayheadOverlay::synchronizeGeometry()` builds a union of visible band strips in full SongView space. It currently visits every published band, including `TrackHeaders`. Because the track-header band has `timelineOrigin == 0`, the resulting mask authorizes playhead pixels in that column. There is also no visibility gate when camera-space `contentX` becomes negative.

The mask itself is not the architectural defect. One playhead crosses disconnected vertical plots, and those plots contain scrollbars, resize handles, separators, hidden sections, and differing right edges. The defect is using the mask to reconstruct the primary chrome-versus-timeline partition.
## Target layout model

### SongView-owned columns

Keep the resolved column metrics with SongView. Rename `plotOrigin` to `timelineSplitX` when the cutover can migrate every caller atomically; do not retain an alias.

Dependent modules receive resolved dimensions from SongView rather than calling `layout::fontPx` with matching literals. Avoid a new global singleton or mutable geometry service.

The layout model must distinguish:

- a row's complete rectangle (`rect`);
- its fixed-side label/control rectangle or rectangles;
- its exact time-plot rectangle (`plotRect`).

The canonical representation in `src/ui/songview/timelinebandlayout.h` is:

```cpp
struct TimelineBandGeometry {
    QRect rect;     // visible SongView-local band rectangle, clipped by parent layout owner
    QRect plotRect; // SongView-local time-plot rectangle; empty QRect() if band has no time plot
};
```

Exact SongView-local contracts:
- `TrackHeaders`: `rect` is `[0, rollTop, trackHeaderWidth, rollHeight]`; `plotRect` is empty `QRect()`.
- `Ruler`: `rect` is `[0, 0, width, rulerHeight]`; `plotRect` is `[timelineSplitX, 0, width - timelineSplitX, rulerHeight]`.
- `Roll`: `rect` is `[trackHeaderWidth, rollTop, width - trackHeaderWidth - vbarWidth, rollHeight]`; `plotRect` is `[timelineSplitX, rollTop, width - timelineSplitX - vbarWidth, rollHeight]`.
- `OtherEvents`: `rect` is `[0, otherTop, width, otherHeight]`; `plotRect` is `[timelineSplitX, otherTop, width - timelineSplitX, otherHeight]`.
- `Automation`: `rect` is `[scrollbarWidth, autoTop, bodyWidth - scrollbarWidth, autoHeight]`; `plotRect` is `[timelineSplitX, autoTop, bodyWidth - timelineSplitX, autoHeight]`.
- `Velocity`: `rect` is `[trackHeaderWidth, velTop, width - trackHeaderWidth, velHeight]`; `plotRect` is `[timelineSplitX, velTop, width - timelineSplitX, velHeight]`. Its fixed-side gutter spans `[rect.x(), rect.y(), plotRect.x() - rect.x(), rect.height()]` = `[trackHeaderWidth, velTop, pianoKeyboardWidth, velHeight]`.

Remove `timelineOrigin` across all modules after consumers migrate to `plotRect`. Playhead overlay and Quick clipping code consume only non-empty `plotRect`s.
### Physical label and plot boxes in Qt Quick

In `TimelineCanvas.qml`, each row retains its outer band container (`TimelineSceneBand`) positioned at `bandRect`, but internally partitions fixed-side chrome from the time plot:

```text
TimelineSceneBand (x: bandRect.x, y: bandRect.y, width: bandRect.width, height: bandRect.height)
|- Fixed-side item: x: 0, width: plotRect.x - bandRect.x
|  |- Gutter chrome (background, separators, lane headers)
|  |- Gutter text layer (anchored to fixed-side item)
|  `- Gutter input item (lane selection, menus, wheel behavior)
`- Plot item: x: plotRect.x - bandRect.x, width: plotRect.width
   |- Grid and content layers (grid, notes, curves, markers, transient preview, hover)
   |- Plot text layer (note text, transient chips)
   `- Plot input item (time-axis gestures, plot-local coordinates where local x = 0 is timelineSplitX)
```

For the Piano Roll:
- `PianoRollCanvas.qml` partitions the piano keyboard (keys, highlights, key text) into the fixed-side key column (`[0, pianoKeyboardWidth)`), and note fills, grid, borders, selections, and overlay into the plot column (`[pianoKeyboardWidth, rollBand.width)`).

C++ Scene Graph & Layer strategy:
- Separate gutter chrome from plot chrome in `TimelineQuickScene` layer generation:
  - Time-plot layers (`PianoGrid`, `PianoNoteFills`, `AutomationCurves`, `AutomationNodes`, `OtherEventsMarkers`, `VelocityGrid`, `VoiceChangesSpans`, etc.) use plot-local coordinates where `TimeCamera::displayX(tick, 0.0, dpr)` is relative to `0.0`.
  - Gutter chrome layers and text model records use gutter-local coordinates relative to their parent fixed-side item.
  - No single layer draws across both sides of `timelineSplitX`.
- The Qt Quick playhead (`TimelinePlayheadItem`) is anchored directly in the timeline column at `x: timelineSplitX`, spanning the height of the scene with width `Math.max(0, root.width - timelineSplitX)`. It receives timeline-local `plotRects` translated by `(-timelineSplitX, 0)` and tracks `playheadContentX` directly.

### Input and accessibility

Move input ownership with the physical boxes:

- **Plot input (`TimelineInputItem` inside Plot item):** receives plot-local X, where `0` is the canonical split (`timelineSplitX`). No coordinate subtraction or `x < plotOrigin` guard is required in plot gesture code.
- **Gutter input (`TimelineInputItem` inside Fixed-side item):** receives gutter-local coordinates. Owns lane menus, track header interactions, vertical wheel behavior, and gutter hover.
- **Piano-key input:** continues to own audition and key interaction within the piano-key column (`[trackHeaderWidth, timelineSplitX)` in SongView space).
- **Automation gutter:** retains vertical lane scrolling, lane header drag, and lane popup menus.
- **Velocity gutter:** retains axis labels and detent toggle button behavior within the piano-key column.
- **Focus:** `TimelineQuickView::focusBand()` focuses the primary plot input item of the band for keyboard editing.
- **Accessibility bounds:** match the visible item that owns the interaction.
## PlayheadOverlay after the layout cutover

### Root geometry

Make the overlay root a timeline-column surface:

```text
SongView x = timelineSplitX
SongView y = 0
width      = max(0, SongView width - timelineSplitX)
height     = SongView height
```

The root may span rows that do not paint. Its mask decides which timeline-row pixels are visible.

All renderer geometry below the root is timeline-local. Translate each SongView-local `plotRect` by `(-timelineSplitX, 0)` before supplying it to the renderer mask.

### Position and visibility

`SongView` continues to send raw `TimeCamera::contentX(playheadTick)`. That value is already the desired overlay-local X.

Remove:

- `PlayheadOverlay::m_timelineOrigin`;
- `PlayheadOverlay::finalX()`;
- ruler-origin addition during position updates;
- per-band left-origin reconstruction in playhead masks.

Define effective visibility from semantic visibility and viewport position:

```text
effectiveVisible = requestedVisible
                   && a ruler plot exists
                   && localX >= 0
                   && localX < overlay width
```

The key invariant is that the **playhead itself** (the 1px core line, vertical body, and ruler triangle) never renders to the left of the piano keys / timeline split. Soft playhead glow/bloom passing over to the left of the split into the key column is explicitly accepted as an insignificant detail; the strict requirement is preventing the playhead core and triangle from rendering over fixed chrome or keys.
### Retained mask

Build the mask from the local plot rectangles for:

- ruler;
- piano roll when the roll page is active;
- other events;
- voice changes;
- velocity;
- automation.

The plot rectangles must already exclude their scrollbars and fixed-side controls. Their union naturally preserves differing right edges. The empty vertical spaces between those rectangles keep resize handles, separators, and the drawer bar playhead-free.

The ruler triangle uses only the ruler plot rectangle. The playhead body uses the union of visible plot rectangles.

Never add `TrackHeaders` or a label/control rectangle to this mask.

### Platform renderers

#### macOS (Native CALayer Compositor)
- Set the root CALayer frame to the timeline-column rectangle mapped into the native window: `CGRectMake(overlayOffset.x() + timelineSplitX, overlayOffset.y(), overlaySize.width() - timelineSplitX, overlaySize.height())`.
- Keep child playhead positions timeline-local (`contentX`).
- Use the timeline-local plot-region path as the body mask (`plotRect.translated(-timelineSplitX, 0)`).
- Use the timeline-local ruler plot as the triangle mask.
- Clip root sublayers to the timeline-column bounds.

#### Windows & Linux (Qt Quick Playhead)
- Anchor `TimelinePlayheadItem` at `x: timelineSplitX` in `TimelineCanvas.qml`.
- Translate published `plotRect`s by `(-timelineSplitX, 0)` to provide timeline-local clip strips.
- Position the item with raw `contentX(playheadTick)`.
- Apply identical effective-visibility rules (`localX >= 0 && localX < overlayWidth`).
- Keep track headers and piano keys structurally outside the playhead's parent coordinate frame.

### Prior cutovers already completed
Commit `8eea7b9` completed the initial renderer simplification:
- Deleted `PlayheadOverlay::FallbackWidget` and software QWidget fallback painting.
- Deleted the Windows DirectComposition renderer (`playheadrenderer_dcomp.cpp`).
- Removed `PORYDAW_FORCE_WIDGET_PLAYHEAD` and all playhead environment overrides.
- Renamed and transitioned playhead checks to `src/checks/rollcheckplayhead_quick.cpp`.

The current refactor does not need to remove those components; it completes the geometry model by migrating macOS CALayer and Qt Quick playheads onto the unified timeline-local coordinate system and removing `m_timelineOrigin`, `finalX()`, and `TimelineBandGeometry::timelineOrigin`.
## Implementation sequence

### Phase 1 - Lock geometry contracts in checks

1. Extend the relevant geometry checks to assert one SongView-local split for every visible plot row.
2. Assert the exact fixed-side spans:
   - other-event, voice-change, and automation labels end at the split;
   - velocity label/axis occupies the piano-key column;
   - no label/control rectangle enters a plot rectangle.
3. Cover normal and fractional DPR, resize, font-scaled metrics, drawer visibility changes, and event-list switching.
4. Add playhead assertions that no playhead core or triangle pixels occur left of the split or inside excluded chrome (exercising `rollcheckplayhead.cpp` on macOS and `rollcheckplayhead_quick.cpp` on non-macOS).
5. Add a case where `contentX(playheadTick) < 0` and assert that the core and triangle are absent (soft bloom passing over the boundary is non-blocking).

These checks establish observable contracts; do not assert implementation field names or source text.

### Phase 2 - Establish one column source

1. Make SongView's resolved geometry the sole source for track-header width, piano-key width, and split X.
2. Pass the resolved dimensions into piano-roll and drawer lane layout calculations.
3. Remove repeated `fontPx(17.5 + 13.0 / 3.0)` and matching key-width formulas from dependent modules.
4. Preserve velocity's intentional placement in the piano-key column through explicit rectangles rather than compensating origins.
5. Keep all widget geometry font-relative through `layout::` primitives.

### Phase 3 - Publish physical row and plot rectangles

1. Replace `TimelineBandGeometry::timelineOrigin` with explicit full-row (`rect`) and time-plot (`plotRect`) rectangles.
2. Update `SongView::resolveTimelineBandLayout()` to publish exact SongView-local plot rectangles.
3. Exclude roll and its playhead plot while event-list mode is active.
4. Ensure automation's left scrollbar and the roll's right vertical scrollbar are outside their plot rectangles.
5. Update TimelineQuickView's geometry properties and coordinate conversion to consume explicit rectangles.
6. Remove every migrated `rect.x + timelineOrigin` reconstruction.

Perform a clean cutover; do not retain both `timelineOrigin` and `plotRect` as parallel authorities.

### Phase 4 - Split visible and input boxes

1. In `TimelineCanvas.qml`, give each migrated row separate fixed-side and plot items positioned from the published geometry.
2. Separate other-event, voice-change, automation, and velocity gutter chrome and label drawing from plot items.
3. Keep all grid, notes, curves, nodes, selections, hover, and edit chrome inside plot items in plot-local coordinates.
4. Split or relocate input surfaces so gutter behavior stays on fixed-side items and time editing uses plot-local coordinates.
5. Preserve drawer chrome stacking, resize cursors, menus, focus, keyboard audition, and accessible names.
6. Delete superseded coordinate rejection and translation code once each caller is migrated.

### Phase 5 - Rebase PlayheadOverlay

1. Size and position the overlay root from the canonical timeline-column rectangle.
2. Convert its state and platform calls to timeline-local X.
3. Build the retained body mask from local plot rectangles and the triangle mask from the ruler plot.
4. Apply effective visibility before publishing any renderer state.
5. Update macOS CALayer and Qt Quick playhead implementations to the unified timeline-local contract.
6. Confirm position-only native movement remains a compositor-only update and does not rebuild Quick scene data or masks.

### Phase 6 - Remove obsolete geometry

1. Remove `m_timelineOrigin`, `finalX()`, and ruler-origin addition in PlayheadOverlay.
2. Remove `timelineOrigin` from `TimelineBandGeometry` and QML property bindings.
3. Remove all dead coordinate helper functions, comments, and unused origin fields.
4. Search the affected modules for duplicated split formulas; ensure no compatibility path remains.
### Phase 7 - Verify the complete surface

1. Format the changed files with `deno task format`.
2. Build with `deno task build:checks`.
3. Run focused harnesses:

```text
deno task verify --filter rendering-playhead --verbose
deno task verify --filter rollwindowingcheck --verbose
deno task verify --filter rollcheck --verbose
deno task verify --filter host-adapter --verbose
deno task verify --filter host-seams --verbose
deno task verify --filter editor-drawer --verbose
deno task verify --filter automation --verbose
deno task verify --filter automation-gestures --verbose
deno task verify --filter velocity-page --verbose
```

4. Launch the application and exercise the actual SongView surface:
   - scroll tick zero left of the plot;
   - play and pause;
   - resize the window and each drawer section;
   - show and hide each drawer lane;
   - switch between piano roll and event list;
   - operate automation gutter menus and scrolling;
   - audition piano keys;
   - inspect label alignment at normal and fractional display scale.
5. Verify on macOS and verify Qt Quick playhead behavior through focused checks and `porydaw_checks`.
6. Run the full `deno task verify` only after focused behavior is clean. Resolve every failing assertion before handoff.

## Acceptance criteria

The refactor is complete only when all of the following are observable:

- The right edge of the piano-key strip forms one uninterrupted vertical split through the SongView.
- Other-event, voice-change, and automation label sections end at that split.
- The velocity label/axis occupies the piano-key column and ends at the same split.
- Every timeline plot begins at the split at every supported UI scale.
- Tick zero and all timeline guides align across ruler, roll, other events, automation, velocity, and voice changes.
- No playhead core or triangle pixel appears over track headers, piano keys, labels, scrollbars, resize handles, separators, drawer chrome, or event-list content.
- Soft playhead bloom/glow passing slightly over to the left of the split is non-blocking; the strict requirement is that the playhead itself (core, triangle, and vertical stem) never renders to the left of the piano keys.
- Moving the playhead core left of the visible plot hides the complete playhead rather than pinning or slicing it.
- Paused and playing playheads follow the same geometry and visibility rules.
- Drawer and gutter interactions retain their current behavior and accessibility bounds.
- Native playhead position-only updates remain independent of Quick scene rebuilds.
- No `timelineOrigin` compatibility field or duplicated split formula remains.

## Non-goals

- Moving the production macOS playback playhead into Qt Quick.
- Creating one playhead renderer per timeline band.
- Teaching `TimeCamera` about headers, keys, labels, or SongView layout.
- Changing musical scrolling, zoom, follow-playhead, or pre-roll semantics.
- Redesigning lane labels, typography, colors, menus, or drawer controls beyond the geometry needed for the physical split.
- Forcing all plot rows to have the same right edge when their scrollbar layouts differ.
- Removing the mask that protects scrollbars, handles, separators, and inactive regions.
- Adding a general-purpose layout framework or renderer abstraction.

- Pixel-perfect clipping or elimination of soft playhead glow/bloom that bleeds slightly left of the split boundary (this detail is explicitly out of scope; the requirement is keeping the playhead itself—core, triangle, and body—strictly to the right of the piano keys).
## Design rationale

The layout and mask enforce different classes of constraints:

- **Layout is semantic:** fixed chrome is not timeline content and cannot be a playhead surface.
- **The mask is presentational:** disconnected timeline rows contain temporary or row-specific obstructions.

Using layout for the major partition makes the implementation match the visible UI and prevents a mask-enumeration error from exposing headers or keys. Retaining the mask preserves the single high-frequency native playhead and prevents it from drawing through scrollbars and drawer chrome. The resulting `PlayheadOverlay` remains one deep module: callers provide timeline-local state and resolved plot geometry; renderer-specific clipping, images, and compositor updates remain private.
