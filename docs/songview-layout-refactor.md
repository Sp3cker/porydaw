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
12. Production assumes the native macOS CALayer or Windows DirectComposition playhead renderer works. The QWidget fallback and `PORYDAW_FORCE_WIDGET_PLAYHEAD` do not remain.

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

`SongView::syncTimelineIndicators()` sends `TimeCamera::contentX(m_playheadTick)` to `PlayheadOverlay`. The overlay then adds a ruler-derived `m_timelineOrigin` through `finalX()` and renders in an owner-sized surface.

`PlayheadOverlay::synchronizeGeometry()` builds a union of visible band strips. It currently visits every published band, including `TrackHeaders`. Because the track-header band has `timelineOrigin == 0`, the resulting mask authorizes playhead pixels in that column. There is also no visibility gate when camera-space `contentX` becomes negative.

The mask itself is not the architectural defect. One playhead crosses disconnected vertical plots, and those plots contain scrollbars, resize handles, separators, hidden sections, and differing right edges. The defect is using the mask to reconstruct the primary chrome-versus-timeline partition.

## Target layout model

### SongView-owned columns

Keep the resolved column metrics with SongView. Rename `plotOrigin` to `timelineSplitX` when the cutover can migrate every caller atomically; do not retain an alias.

Dependent modules receive resolved dimensions from SongView rather than calling `layout::fontPx` with matching literals. Avoid a new global singleton or mutable geometry service.

The layout model must distinguish:

- a row's complete rectangle;
- its fixed-side label/control rectangle or rectangles;
- its exact time-plot rectangle.

A suitable final representation is a band geometry containing an explicit `bandRect` and `plotRect`, both in SongView coordinates. Lane-specific label rectangles remain owned by the lane layout because velocity, automation, and full-width labels use the fixed columns differently. Remove `timelineOrigin` after all consumers use `plotRect`.

`TrackHeaders` may remain a published visual/input band if the shared Quick host requires it, but it must have no time `plotRect`. Playhead code consumes only non-empty time-plot rectangles.

### Physical label and plot boxes

For each migrated Quick row, create sibling fixed-side and plot items rather than painting both through one full-band item:

```text
Row
|- fixed-side item: label/control paint and gutter input
`- plot item: grid/content paint and time-axis input
```

The fixed-side item ends at the canonical split. The plot item begins there and uses plot-local coordinates.

Do not require every fixed-side item to have the same internal span:

- other-event, voice-change, and automation label sections may span both fixed columns but stop at the split;
- velocity label/axis starts at `trackHeaderWidth` and spans only the piano-key column;
- track headers and piano keys remain separate adjacent boxes in the roll row.

Use existing `layout::` and typography primitives for text inset and vertical centering. Do not introduce hard-coded pixels.

### Input and accessibility

Move input ownership with the visible boxes; do not leave owner-wide input surfaces behind a physically split presentation.

- Plot input receives plot-local X, where zero is the canonical split.
- Gutter input owns label menus, vertical wheel behavior, and gutter hover.
- Piano-key input continues to own audition and key interaction.
- Automation gutter retains vertical scrolling and lane-menu behavior.
- Velocity gutter retains axis-label and detent behavior.
- Drawer resize handles, toggles, scrollbar, and bar retain their dedicated Quick input objects and accessible names.
- Accessibility bounds must match the visible item that owns the interaction.

Delete obsolete `x < plotOrigin` routing only after the equivalent gutter input path exists. Do not add coordinate shims that preserve both models.

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

The explicit left gate is required even with rectangular clipping: otherwise a core just left of zero can leave part of its right bloom or triangle visible at the plot edge. Hide; do not clamp or pin.

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

### Native renderers

For macOS:

- set the root CALayer frame to the timeline-column rectangle mapped into the native host;
- keep child playhead positions timeline-local;
- use the local plot-region path as the body mask;
- use the local ruler plot as the triangle mask;
- clip root sublayers to the timeline-column bounds.

For Windows:

- set the DirectComposition root/host geometry to the timeline-column rectangle;
- use local X for the shared playhead transform;
- keep per-row rectangle clips for plot holes and differing right edges.

Both renderers consume the same local layout and effective visibility. Platform code must not reconstruct SongView gutters.

### Quick playhead path

Migrate the existing opt-in Quick playhead to the same timeline-local contract so tests do not preserve a second coordinate system:

- parent it to the timeline-column item;
- provide local plot rectangles;
- position it with raw `contentX`;
- apply the same effective-visibility rule;
- keep track headers structurally outside its parent.

This does not make Quick the production playback renderer.

### Remove QWidget fallback

Delete the software playhead fallback and its selector as part of the same clean cutover:

- `PlayheadOverlay::FallbackWidget`;
- fallback painting and region-update helpers;
- `fallbackWidget()` and fallback-only test access;
- `PORYDAW_FORCE_WIDGET_PLAYHEAD`;
- failure messages that claim the renderer will fall back to QWidget.

Assume the compiled platform-native renderer applies successfully. Keep explicit failure reporting rather than silently switching renderers.

`src/checks/rollcheckplayhead_fallback.cpp` also contains retained Quick scene and rendering-check runner functions. Move those retained functions to an accurately named check source before deleting only the forced-widget assertions and setup. Update `CMakeLists.txt` atomically so the check binary continues to link.

## Implementation sequence

### Phase 1 - Lock geometry contracts in checks

1. Extend the relevant geometry checks to assert one SongView-local split for every visible plot row.
2. Assert the exact fixed-side spans:
   - other-event, voice-change, and automation labels end at the split;
   - velocity label/axis occupies the piano-key column;
   - no label/control rectangle enters a plot rectangle.
3. Cover normal and fractional DPR, resize, font-scaled metrics, drawer visibility changes, and event-list switching.
4. Add native-playhead assertions that no playhead-role pixels occur left of the split or inside excluded chrome.
5. Add a case where `contentX(playheadTick) < 0` and assert that core, bloom, and triangle are all absent.

These checks establish observable contracts; do not assert implementation field names or source text.

### Phase 2 - Establish one column source

1. Make SongView's resolved geometry the sole source for track-header width, piano-key width, and split X.
2. Pass the resolved dimensions into piano-roll and drawer lane layout calculations.
3. Remove repeated `fontPx(17.5 + 13.0 / 3.0)` and matching key-width formulas from dependent modules.
4. Preserve velocity's intentional placement in the piano-key column through explicit rectangles rather than compensating origins.
5. Keep all widget geometry font-relative through `layout::` primitives.

### Phase 3 - Publish physical row and plot rectangles

1. Replace `TimelineBandGeometry::timelineOrigin` with explicit full-row and time-plot rectangles.
2. Update `SongView::resolveTimelineBandLayout()` to publish exact SongView-local plot rectangles.
3. Exclude roll and its playhead plot while event-list mode is active.
4. Ensure automation's left scrollbar and the roll's right vertical scrollbar are outside their plot rectangles.
5. Update TimelineQuickView's geometry properties and coordinate conversion to consume explicit rectangles.
6. Remove every migrated `rect.x + timelineOrigin` reconstruction.

Perform a clean cutover; do not retain both `timelineOrigin` and `plotRect` as parallel authorities.

### Phase 4 - Split visible and input boxes

1. In `TimelineCanvas.qml`, give each migrated row separate fixed-side and plot items positioned from the published geometry.
2. Move other-event, voice-change, automation, and velocity label drawing into their fixed-side items.
3. Keep all grid, notes, curves, nodes, selections, hover, and edit chrome inside plot items.
4. Split or relocate input surfaces so gutter behavior stays on fixed-side items and time editing uses plot-local coordinates.
5. Preserve drawer chrome stacking, resize cursors, menus, focus, keyboard audition, and accessible names.
6. Delete superseded coordinate rejection and translation code once each caller is migrated.

### Phase 5 - Rebase PlayheadOverlay

1. Size and position the overlay root from the canonical timeline-column rectangle.
2. Convert its state and platform calls to timeline-local X.
3. Build the retained body mask from local plot rectangles and the triangle mask from the ruler plot.
4. Apply effective visibility before publishing any renderer state.
5. Update macOS, DirectComposition, and opt-in Quick playhead implementations to the same contract.
6. Confirm position-only native movement remains a compositor-only update and does not rebuild Quick scene data or masks.

### Phase 6 - Remove fallback and obsolete geometry

1. Remove the QWidget fallback implementation and environment selector.
2. Preserve and relocate non-fallback rendering-check functions currently sharing its source file.
3. Remove dead paint helpers, accessors, state, includes, CMake entries, comments, and warning text.
4. Remove all obsolete per-band origin fields and aliases.
5. Search the affected modules for duplicated split formulas and old fallback names; no compatibility path remains.

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
5. Verify on macOS. Keep Windows-specific DirectComposition behavior covered by compile and focused checks; perform an actual Windows surface check before release when a Windows runner is available.
6. Run the full `deno task verify` only after focused behavior is clean. Resolve every failing assertion before handoff.

## Acceptance criteria

The refactor is complete only when all of the following are observable:

- The right edge of the piano-key strip forms one uninterrupted vertical split through the SongView.
- Other-event, voice-change, and automation label sections end at that split.
- The velocity label/axis occupies the piano-key column and ends at the same split.
- Every timeline plot begins at the split at every supported UI scale.
- Tick zero and all timeline guides align across ruler, roll, other events, automation, velocity, and voice changes.
- No playhead pixel appears over track headers, piano keys, labels, scrollbars, resize handles, separators, drawer chrome, or event-list content.
- Moving the playhead core left of the visible plot hides the complete playhead rather than pinning or slicing it.
- Paused and playing playheads follow the same geometry and visibility rules.
- Drawer and gutter interactions retain their current behavior and accessibility bounds.
- Native playhead position-only updates remain independent of Quick scene rebuilds.
- No QWidget playhead fallback, `PORYDAW_FORCE_WIDGET_PLAYHEAD`, `timelineOrigin` compatibility field, or duplicated split formula remains.

## Non-goals

- Moving the production playback playhead into Qt Quick.
- Creating one playhead renderer per timeline band.
- Teaching `TimeCamera` about headers, keys, labels, or SongView layout.
- Changing musical scrolling, zoom, follow-playhead, or pre-roll semantics.
- Redesigning lane labels, typography, colors, menus, or drawer controls beyond the geometry needed for the physical split.
- Forcing all plot rows to have the same right edge when their scrollbar layouts differ.
- Removing the mask that protects scrollbars, handles, separators, and inactive regions.
- Adding a general-purpose layout framework or renderer abstraction.

## Design rationale

The layout and mask enforce different classes of constraints:

- **Layout is semantic:** fixed chrome is not timeline content and cannot be a playhead surface.
- **The mask is presentational:** disconnected timeline rows contain temporary or row-specific obstructions.

Using layout for the major partition makes the implementation match the visible UI and prevents a mask-enumeration error from exposing headers or keys. Retaining the mask preserves the single high-frequency native playhead and prevents it from drawing through scrollbars and drawer chrome. The resulting `PlayheadOverlay` remains one deep module: callers provide timeline-local state and resolved plot geometry; renderer-specific clipping, images, and compositor updates remain private.
