# Editor drawer contract

This document defines the current editor drawer behavior and the seams that
own it. It is normative for the drawer, automation page, velocity page,
view-only persistence, and their integration with `SongView` and
`SongDocument`. It is not an implementation diary.

## Product boundary

The piano roll remains the primary editor. `EditorDrawer` is a bottom overlay:
opening or resizing it never changes the roll, track-header, time-scroll, or
zoom geometry. It exposes exactly two pages, Automations and Velocity. The
visible page may be hidden by clicking its tab; the other tab switches page and
opens the drawer. A new song opens Automations unless persisted state says
otherwise. Unmodified `A` and `V` are window-local shortcuts, routed only to
the active `SongView`; they are disabled while the raw event list is visible.
Tab tooltips and announcements are:

- `Show or hide automation lanes (A)` / `Show or hide note velocities (V)`.
- `Automation lanes shown`, `Automation lanes hidden`.
- `Velocity lane shown`, `Velocity lane hidden`.

Tabs, the stack, and the automation scroll container do not take focus.
`AutomationArea` and `VelocityArea` use click focus. Switching to a visible
page focuses its canvas; closing the drawer returns focus to the main content.
Page hide or switch clears hover/preview state, updates scrollbars and the
playhead overlay, and cancels its active interaction. There is no row-collapse
control.

The drawer owns visibility, page, height, tabs, shortcuts, focus transfer, and
view-state publication. It does not mutate MIDI. `SongView` owns shared song,
selection, camera, timeline, track, voice, playback, and focus context. It
coordinates `EditorDrawer`, `AutomationPage`, and `VelocityArea`. `AutomationPage`
and `AutomationArea` own automation rows, plotting, menus, selection, and
automation gestures. `VelocityArea` owns velocity plotting, hit testing,
selection projection, previews, and velocity gestures. `VelocityAxis` owns
ruler geometry and labels. `VelocityMap` owns voice-to-axis domain rules.
`ViewSidecar` owns detached JSON capture/restore. `SongDocument` owns SMF
mutation, revision checks, remaps, playback rebuild notifications, and Undo.

## Shared interaction rules

All three editor surfaces share selected track, selected notes, horizontal
scroll and time zoom, edit cursor, playhead, grid/snap settings, and track
color/voice context. View-only actions do not alter MIDI, dirty the document,
or add Undo commands. Each completed song-editing gesture creates one
undoable command; unchanged edits create none.

A live interaction is cancelled when its page or drawer becomes hidden, the
song or selected track is replaced, the document mutates, Undo/Redo or reload
occurs, the mouse grab/window focus is lost, or Escape is pressed. A staged
song edit restores its preview and creates no command. A provisional selection
restores its starting selection. View-only pan and resize keep the already
applied camera or size. Follow-scroll is paused during a gesture and resumes
after commit or cancellation.

`SongDocument::revision()` is monotonic. A successful mutation, load, Undo, or
Redo increments it once before remapping and before `documentChanged`; failed
edits, no-ops, and cosmetic changes do not. Batch edits validate expected
revision and every address before modifying any event.

## Shared geometry and rendering

Static geometry for the drawer, pages, rows, ruler, track header, piano
keyboard, plot origin, paint extents, hit tolerances, clamps, and density
thresholds comes from `layout::editorGeometry()`, `layout::space(...)`,
`layout::singlePixel()`, or a semantic layout accessor. Target components do
not add raw screen-space constants. Derived values may combine resolved layout
values with live widget bounds. The plot origin is the resolved track-header
width plus piano-keyboard width; plot width clamps to zero when the host is
narrower. Tab widths partition the resolved track-header width.

The drawer handle spans the host from the track-header edge through the plot;
its height, row default/minimum/maximum, wheel increment, point radii, velocity
hit tolerances, and continuous-axis density thresholds are resolved layout
values. The default drawer height is one fifth of host height. Minimum height is
the default row plus add-lane strip, bounded by the host; maximum leaves the
resolved minimum piano-roll height when possible. Resize clamps to these
limits, and only the drawer height changes.

Automation and velocity content are cached surfaces. Routine playhead movement
updates only `PlayheadOverlay`/the page overlay and must not rebuild content.
Edits, selection, zoom, scroll, resize, theme, document, and voice-context
changes invalidate the affected content. Painting honors the Qt update region;
no broad paint culling is introduced. While playing, drawer voice context uses
`drawerContextTick(double) = floor(max(0, t) + 0.5)` converted to `uint64_t`;
while stopped it uses the edit cursor. No consumer defines another rounding
helper.

## Automation behavior

Rows are ordered Tempo, Voice when present, then visible controller rows for
the primary selected track. Controller numbers sort ascending and pitch bend
(pseudo-controller `255`) is last. A multi-track header selection broadens
track-scoped edits but does not duplicate rows. Hidden lanes participate in
track-scoped range edits; lane-scoped selections include only visible rows.
Rows scroll vertically inside the drawer; shared time scroll and zoom control
the x axis.

The add strip appears only with a document and lists, in order: Modulation
(CC1), Volume (CC7), Pan (CC10), Bend range (CC20), LFO speed (CC21), and
Pitch bend. Existing lanes are omitted. Hidden lanes follow a separator as
`Show: <parameter> (hidden)`. If no new lane is available, a disabled
`All parameters already have lanes` item remains before the separator. Adding
an empty lane is cosmetic until its first event exists.

A controller or pitch-bend gutter menu supports copy whole lane (absolute
ticks), paste replace from one nonempty whole-lane clip, hide, clear events,
remove an empty cosmetic lane, and confirmed deletion of a nonempty lane.
Paste clamps values and is one Undo command. Row height and display range
survive hiding, removal, deletion, and recreation. Eligible controllers offer
Auto, 0–16, 0–32, 0–64, and 0–127; pitch bend, pan, and tune do not. Auto picks
the smallest of 16, 32, 64, and 127 containing the data, and display ranges
never clip values. Successful lane actions use the established status channel.

Middle drag pans time and lane scroll. Ctrl-wheel changes all row heights by
the resolved increment; Shift/horizontal wheel scrolls time; plain wheel over
plot zooms around the pointer and over gutter scrolls the outer view. A left
drag on a row divider resizes only that row; other buttons do nothing.

Automation points use the resolved hit radius. Left drag moves a point; a drag
from blank plot paints crossed grid cells, filling fast sweeps. Shift-left
drag draws a ramp and has priority over grabbing; Alt uses the MIDI-clock grid;
normal snapping follows editor snap rules. Ctrl magnetizes pan/tune to 64 and
pitch bend to zero within the resolved neutral radius. Right drag makes a
half-open time selection across visible crossed rows. Right-click inside it
opens its menu; outside it deletes the nearby time-axis point within the
resolved delete radius. Blank controller/tempo right-click clears selection;
blank voice-row right-click does not. Exact entry domains are tempo 1–999,
pitch bend −8192…8191, pan/tune −64…63 stored plus 64, and other controllers
0…127. A cancelled dialog is a no-op; a double-click is atomic.

Voice markers open Change voice or Insert voice change pickers; unchanged
choices do nothing, right-click deletes, and empty-space hover previews the
voice at the snapped tick without obscuring an existing marker. Playback and
hover context both use the shared drawer tick conversion.

## Velocity behavior and domains

`VelocityArea` draws every note on the primary selected track and uses
`SongView`'s `NoteId` selection; it does not maintain a second selection model.
`NoteId` distinguishes duplicate notes at the same track, tick, and key. At a
gesture start, each selected ID is frozen with its exact SMF track/on-event
address and document revision. Any mutation, Undo, Redo, or reload cancels the
preview, and stale batches are rejected as a whole.

`VelocityMap` resolves a note's voice to Unresolved, Invalid, Keyless,
DirectSound, Square1, Square2, Wave, or Noise. DirectSound, missing/invalid
voice data, keyless or nested splits, and incompatible selections use a
continuous axis. A compatible selection freezes one intrinsic map for the
whole gesture. Key-split voices resolve by note key; an unselected top-level
split has no key context and remains continuous. Square1, Square2, and Noise
are distinct maps even when they have equal level counts.

Stored velocity is always the exact MIDI value 1…127. For PSG display,
`E = min(ceil(s / 4) * 4, 127)` and intrinsic level `G = floor((E - 1) / 8)`;
this is independent of mixer/controller values. Square1, Square2, and Noise
have representatives `1,12,20,28,36,44,52,60,68,76,84,92,100,108,116,127`.
Wave has classes 1…16→1 (mute), 17…48→32, 49…80→64, 81…112→96, and
113…127→127. Moving between intrinsic levels uses representatives; returning
to the starting level restores each exact starting value. Typed velocity entry
always stores the typed exact value and uses the existing piano-roll command.

The continuous ruler maps 127 to top and 1 to bottom with resolved vertical
insets. It always includes endpoints; tick/label density adapts to drawable
height using the four resolved thresholds. Static labels disappear only during
relative continuous dragging. A labeled graduation sets all selected notes in
one Undo command. Intrinsic labels read
`Volume N (value)`, use one column for five levels and staggered columns for
more than eight, and emphasize active extrema only. Nodes and labels are not
focus targets and have no tooltips.

Notes draw a track-colored duration stem and start node; selected notes have a
thicker selection-colored stem and ring. Hit testing uses resolved node radius,
duration-line vertical radius, and horizontal slop. Plain/Ctrl left selects or
toggles hits; Ctrl-left drag unions then drags. Right drag replaces or unions
box hits with Ctrl; stationary right-click replaces or toggles. Blank plain
click clears selection; blank Ctrl-click preserves it. A right press consumes
the pending context menu and begins a band only after Qt drag distance.

Relative drag freezes notes, map, and values. Continuous mode applies one
shared delta, clamps DirectSound to 1…127, and canonicalizes each incompatible
PSG note through its own map. Intrinsic mode applies one shared level delta,
preserving exact origins on return. Release submits one
`SongDocument::setNotesVelocities` batch. The batch addresses stable IDs,
checks revision, deduplicates by SMF track/on-index with last edit winning,
clamps 1…127, skips no-ops, and retains exact Undo values.
Piano-roll velocity-handle and modifier drags publish the same clamped
selected-note preview to the velocity area on every change. The document
remains unchanged until the piano-roll gesture releases.

## Remapping and typed sidecars

`SongDocument` emits one complete `TrackRemap` after rebuilding its track map
and before `documentChanged` whenever SMF chunk or engine-track ownership
changes. It maps old SMF chunk indices and old engine slots to new indices;
`-1` means deleted or no longer an engine owner, and new counts identify
inserted owners. Apply, Undo, and Redo use the same ordering and contract;
identity/no-op mutations emit no remap. Consumers remap selection, event-list
anchors, mute/solo state, empty lanes, hidden lanes, heights, and ranges.
Deleted-owner state is dropped; surviving owners follow their new slot; new
owners receive defaults. Tempo state is not engine-track remapped.

`EditorViewState` is value-only sidecar data stored in the root `editor`
object: drawerVisible, drawerPage, drawerHeight (zero means layout default),
laneHeight (zero means default), laneHeights, laneRanges, emptyLanes, and
ordered hiddenLanes. Row IDs are `tempo`, `voice:<track>`, or
`cc:<track>:<controller>` with tracks 0…15 and controllers 0…127 or 255. The
decoder rejects malformed, non-canonical, and out-of-range IDs/entries
independently. Ranges are integers 0…127; zero means auto. Heights clamp to
current layout bounds. Valid non-menu ranges survive load, remap, and save.

`ViewSidecar` reads `<project-root>/.porydaw/<song-label>.json`. The root
`view` object contains camera, grid, and event-list state; the root `editor`
object contains `EditorViewState`. Saving replaces both canonical objects,
preserves unrelated root fields, and writes atomically with `QSaveFile`.
A missing or malformed `editor` object uses `EditorViewState` defaults.
Missing, malformed, unreadable, or failed state I/O falls back silently.
Sequential restores replace, rather than append, lane collections.
Save on tab close, project switch, song replacement, and application close,
not on each drag update. Sidecar changes never dirty MIDI.

## Verification entrypoints

Focused native entrypoints are scoped to their owning seam:

- `editorlayoutcheck --base-font-px 12` and `--base-font-px 16` cover resolved
  geometry, scaling/invariance, derived origin, and shared hit-test values.
- `editcheck <scratch-project>` covers revision-checked velocity batches,
  stale/invalid rejection, no-op filtering, exact Undo, and track remaps.
- `rollcheckdrawer`, `rollcheckautomation`, and `rollcheckpsgvelocity` cover
  drawer lifecycle, automation gestures/rows, and continuous/intrinsic axes.
- `viewsidecarcheck` covers the canonical view/editor schema, typed decoding,
  defaults, strict validation, root-field preservation, and replacement restores.
- `mainwindowroutingcheck`, `tabcheck`, and `eventviewcheck` cover active-tab
  shortcut routing, focus/status behavior, and remap ordering at integration
  boundaries.

The performance check must reset warmup counters, send 120 playhead-only
updates while each page is visible, assert no content-build increase, and
assert playhead presentation reaches the final tick. It must then observe
invalidation for an edit, selection, zoom, and theme change. A full roll check
and the focused entrypoints run on the same fixture; failures are attributed
only after comparison with the current base. Manual coverage should exercise
both pages, lane menus and gestures, duplicate-note selection, mixed voice
contexts, exact intrinsic restoration, sidecar round-trip without MIDI diff,
and smooth playback without steady content rebuilds.
