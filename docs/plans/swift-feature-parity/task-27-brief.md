# Context

Visual-parity inventory item 2 (REAL divergence per the verified table in
`agent://InventoryVerify/report`): the 'Other events (N)' band below the
drawer is in every QWidget capture (`/tmp/porydaw-qwidget-ref/a-main-window.png`,
`b-event-list.png`, `d-auto-base.png`) and absent in the Swift captures.
Fork-main `fceecd88` facts:

1. **Band layout.** The viewport stacks ruler → roll pane (the EditorDrawer
   docks at the roll pane's bottom) → Other events band → horizontal scrollbar
   row (`git show fceecd88:src/ui/songview.cpp` lines 217-237). Band height =
   `QFontMetrics(bodyFont).height() + lyt::space(Space::Two)` (lines 44-48);
   `plotRect` starts at `timelineSplitX` (track headers + piano keyboard), the
   gutter is the left remainder (`timelinebandlayout.h:35-46`,
   `songview.cpp:123-151`). The band is present even when every drawer section
   is collapsed (drawer ledger A139).
2. **Rendering** (`git show fceecd88:src/ui/songview/quick/otherstripquick.cpp`):
   band fill = role `song_view_timeline_chrome_background` (the ruler's chrome
   role, `timerulerquick.cpp:71` → Swift `palette.chromeBackground`); a 1-px
   top hairline `song_view_separator` → `palette.separator`; gutter label
   `SongView::tr("Other events (%1)").arg(model.strip.size())`, primary text,
   left + vcenter aligned, inset `space(Two)`; a pre-roll mask from the plot's
   left edge to camera tick 0 filled `mixTowardOklab(chrome, gridLineColor(),
   0.15)` → Swift `palette.rulerPreRollMask` (ShellAppearance.swift:167-168
   recomputes exactly this per theme); one diamond per strip item centered at
   band-height/2, half-width `fontPx(1.0/3.0)`, half-height `fontPx(5.0/12.0)`
   (`otherstrip.cpp:21-24`), colored `SongView::trackColor(track)` — 16 fixed
   identity fills (`trackidentitycolors.h:13-22` → GridPalette.swift:230-231) —
   or, for `track < 0`, role `song_view_file_event_marker` = preset `outline`
   (presetcolors.h rolePresetColors, song_view block) → `palette.outline`.
   Hit slop `fontPx(1.0/3.0)`; markers culled beyond plot bounds ± slop.
3. **Strip model** (`git show fceecd88:src/ui/songviewmodel.cpp` lines 100-140):
   strip = orphan note-offs (`"Note off (key %1) without a note on"`) + CCs
   that `m4aClassifyCc` does not classify Audible (labeled
   `m4aAdvancedCcLabel`) + `tl.otherEvents` labels verbatim, stable-sorted by
   tick; XCMD-consumed CCs are skipped (xcmd projection, lines 33-59). The
   label's N counts the whole strip, not just `otherEvents`. Swift already has
   the ingredients: `PlaybackTimeline.otherEvents` with
   `PlaybackOtherEvent{tick, sample, track, label}` (PlaybackTimeline.swift:148,
   420-435; `track == -1` = file-level via `chunkToEngine` default, line 341),
   `m4aAdvancedCCLabel` (MidiSemantics.swift:267-271, a line-for-line port),
   `m4aClassifyCC` (MidiSemantics.swift:165), `Xcmd.Projection.consumed`
   (Xcmd.swift:62), `GridPalette.trackIdentityFills` (GridPalette.swift:220-231).
   Orphan note-off pairing (per (track,key) open stack, fork lines 26-33,
   100-110) has no Swift counterpart yet.
4. **Interactions.** `OtherStrip` overrides only `pointerMove`; press,
   double-click and release return false (`timelineinput.h:120-123`), so clicks
   do nothing, do not take focus, and preserve the roll selection
   (`selectionkey/corearrows.cpp:39-44`, OtherEvents `clickTakesFocus` false).
   Hover shows a tooltip: one line per strip item within hit slop of the
   pointer x, `"%1:%2 · %3 · %4"` (minutes, 2-digit zero-padded seconds,
   `Track %1`.arg(track+1) or `File`, item label), at most 12 lines then a
   trailing `…`, joined `\n`, anchored at the pointer, cleared on leave,
   cancel and detach (`otherstrip.cpp:52-108`; QML shape in
   `quick/OtherStripToolTip.qml`). Wheel over the band scrolls the shared camera.

This is a bounded first slice: band geometry, chrome, label, markers, wheel and
tooltip. Out of scope: programmatic/keyboard focus traversal onto the band
input (fork `focusTimelineBand`), and raster-pixel proofs (native-only rows).

# Exact write set

- NEW `src/swift/app/drawer/otherEvents/OtherEventsStrip.swift` — pure
  projection: strip items (three sources + XCMD skip + stable tick sort),
  marker records (x, color, culled), tooltip lines, the band-height metric.
- NEW `src/swift/app/drawer/otherEvents/OtherEventsBandPresenter.swift` —
  `@QtBridgeable`: publishes `bandHeight`, `labelCount`, a markers list model,
  `toolTipVisible/Text/X/Y`, tooltip colors; entry points `pointerMoved(x, y)`,
  `pointerLeft()`, `inputCancelled()`; no camera or document ownership.
- NEW `src/ui/songview/quick/drawer/OtherEventsBand.qml` — chrome rect + top
  hairline, gutter label, pre-roll mask, marker `Repeater`, plot/gutter
  MouseAreas (`acceptedButtons: Qt.NoButton`, `hoverEnabled`), WheelHandlers
  routed to `gridModel.handleWheel` like VelocityPage.qml:459-472; hosts the
  existing `RulerToolTip` with `objectName: "timelineOtherEventsToolTip"`.
- `src/ui/songview/quick/swiftroll/EditorSurface.qml` — mount the band between
  `editorDrawer` and `horizontalScrollBar` (drawer bottom re-anchors to the
  band top); `rollBandContent.height` (lines 145-146) and the drawer
  `configureLayout` host height (lines 876-881) subtract `bandHeight`.
- `src/swift/app/DocumentWorkspace.swift` — construct the presenter; refresh it
  in `cameraDidChange` beside the drawer pages (~lines 276-348) and in the
  document-change refresh (~line 317).
- `src/swift/app/ApplicationSession.swift` — `otherEventsBand()` accessor with
  an empty-fallback presenter, mirroring `drawerPresenter()` (lines 378-383).
- Root `CMakeLists.txt` — add `src/ui/songview/quick/drawer/OtherEventsBand.qml`
  to the drawer QML block (lines ~250-257).
- NEW `src/checks/drawerpresentation/other_events_band.swift`, invoked from
  `runEditorDrawerChecks` (EditorDrawerChecks.swift:219-230), registered in
  `src/checks/CMakeLists.txt` (~line 183).
- `src/checks/editorqml/tst_EditorDrawer.qml` — mounted predicates (the file
  already mounts EditorSurface and opens `mus_route101`, lines 168, 208).

No `GridPalette.swift`/`ShellAppearance.swift` edits — every role the band
needs already exists (tooltip triple as in EventListMenus.swift:56-58).

# Prerequisites

After task 22 (owns `ApplicationSession.swift`) and after task 26 (owns
`EditorSurface.qml`/`SongTab.qml`; task-26-brief.md records the same
27-after-26 ordering — the band composes after its event-list host).
Tasks 23/24/25 are file-disjoint.

# Interface contract

- Label: QML `qsTr("Other events (%1)").arg(presenter.labelCount)`; N = full
  strip count (orphan note-offs + advanced CCs + otherEvents). Gutter font =
  application font; inset and the metric base follow `EditorDrawerMetrics`
  conventions (`Int(fontPx(base, ratio))`, EditorDrawerTypes.swift:85-96);
  `bandHeight = Int(appFontLineSpacing) + Int(fontPx(base, 0.5))` mirroring
  fork `QFontMetrics(body).height() + space(Two)`.
- Strip sources, exact strings: orphan note-off
  `"Note off (key \(key)) without a note on"`; advanced CC via
  `m4aAdvancedCCLabel(controller:value:)` (includes
  `"CC \(cc) = \(value) (no m4a meaning)"`); otherEvents labels verbatim from
  `PlaybackTimeline`. XCMD-consumed CCs excluded (`Xcmd` projection over the
  CC events, fork songviewmodel.cpp:33-59); audible-lane CCs excluded per
  `m4aClassifyCC` (Swift and fork classify identically). Stable order: by
  tick, events-loop items before otherEvents items at equal ticks.
- Markers: plot-local `x = camera.contentX(tick: Double(tick))`; cull to
  `[-slop, plotWidth + slop]`, slop `fontPx(1/3)`; rhombus half-width
  `fontPx(1/3)`, half-height `fontPx(5/12)` (render as a 45°-rotated Rectangle
  whose side is `diagonal / √2`); color `GridPalette.trackIdentityFills[
  trackIdentityIndex(track)]` for `track >= 0`, else `palette.outline`.
- Tooltip lines: `"\(m):\(String(s, padTo2)) · \(track >= 0 ? "Track \(track+1)"
  : "File") · \(label)"` from `item.sample / sampleRate`; cap 12 lines then
  append `"…"`; join `"\n"`; position = pointer (plot-local x, y); visible
  while non-empty; cleared by `pointerLeft`/`inputCancelled`.
- Inputs: `objectName` "timelineOtherEventsInput" (plot) and
  "timelineOtherEventsGutterInput" (gutter, width = timelineSplitX); clicks
  never take focus; wheel routes to the roll camera (gutter passes
  `overGutter: true`).
- Unit predicates (cppID `swiftcore/OtherEventsBand::*`), with synthetic
  fixtures built like `drawerVoiceVoiceChangesPageFixture`
  (VoiceChangesPageChecks.swift:66-85) and `PlaybackTimeline.build`: advanced
  CC item, orphan note-off item, audible CC absent, otherEvents item,
  XCMD-consumed CC absent, loop-marker metas absent, tick-stable order,
  marker x/cull/colors, tooltip format + `…` cap + clear, label count ==
  strip count.
- QML predicates on `mus_route101`: band y == drawer bottom and height ==
  `presenter.bandHeight`; band present with all sections hidden; gutter label
  text matches count; both input objectNames present with gutter width ==
  timelineSplitX; marker delegate count matches the projection after scrolling
  one marker into view (existing `setCameraHScroll`), its x == the camera
  content x of its tick and its color a track-identity fill or `outline`;
  tooltip visible with the hovered item's label after `mouseMove` over that
  marker and hidden after moving to the ruler band; roll input keeps
  `activeFocus` after a click at band center. Contract-shaped messages, no
  pixel constants, no sleeps (`waitForNative`).

# Implementation steps

1. Write the failing unit and QML predicates first; record the RED output.
2. `OtherEventsStrip` projection + presenter (pure Swift, no QML yet).
3. Workspace construction + session accessor + refresh fan-out.
4. `OtherEventsBand.qml`, CMake registration, EditorSurface mounting.
5. Run the lanes below; report GREEN with exact predicate strings + file:line.
   At controller capture, read the reference's exact 'Other events (N)' and
   confirm the Swift label matches.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
- `deno task verify:qml --verbose` (drawer lane; split per case if > 180 s)
- `deno task verify:qml-roll --verbose` (EditorSurface mounting changed)
- `deno task verify:bridge`
- Controller visual acceptance per skill `porydaw-qwidget-reference-capture`:
  capture in the same theme as `/tmp/porydaw-qwidget-ref/a-main-window.png` and
  list remaining differences (label text, diamond shape/colors, chrome, mask).

# Visual parity

Counterpart: fork-main `fceecd88` `src/ui/songview/quick/otherstripquick.cpp`
(rendering), `src/ui/songview/otherstrip.cpp` (tooltip), `src/ui/songview.cpp`
(band layout), `src/ui/songviewmodel.cpp` (strip model),
`src/ui/songview/quick/OtherStripToolTip.qml` (tooltip shape → RulerToolTip).
Out of scope: keyboard focus of the band input, native raster invariance.

# Task-specific constraints

- No new C++, no code comments, no pixel constants (font-ratio metrics only),
  no polling (refresh rides the existing camera/document fan-out), one palette
  authority (session GridPalette via published strings), no ledger edits.
- Ledger dispositions for the controller's ledger agent (implementer does not
  edit ledgers): Behavior — drawer A139; host A027-A033, A068, A074, A122,
  A123, A125-A133, A135 (geometry/inputs/tooltip, message-anchored predicates
  above); host A124, A137-A139 (timeline fields + loop markers never strip
  items); keyboard A041, A042. Representation — keyboard A040 (native seed
  guard), A043-A046 (framebuffer pixels / native unwind); host A134, A119-A121
  (already RETIRED-REPRESENTATION), A136, A141, A142 (raster equality). None
  Blocked.
