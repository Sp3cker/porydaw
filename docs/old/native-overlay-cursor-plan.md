# Native overlay cursor — Implementation Plan

Worktree: `.worktrees/drawer-hover-guide` (`feature/drawer-hover-guide`).

## Goal

Move the vertical **edit cursor** and **hover guide** onto `PlayheadOverlay` as native compositor elements (macOS CALayer / Windows DComp), using the same clip tree that already covers the piano-roll `QQuickWidget`. Widget-fallback `paintEvent` paints the same chrome when the platform renderer is off.

One camera-space content-x. Full-height through every visible timeline plot (ruler, roll, automation, velocity, voice-change, other-strip). Surfaces stop painting those two strokes.

This supersedes the QPainter column in `docs/drawer-hover-guide-line-plan.md`. That plan’s **arm/clear policy** (when a surface reports hover) stays; the **paint and strip-invalidation** stages do not.

## Decisions

1. **Keep `PlayheadOverlay`.** Do not rename. Do not convert the timeline column to Qt Quick.
2. **Same overlay object, not the playhead layer or `setPlayhead`.** Playback is sample-accurate; hover is mouse-move. Independent setters, independent transforms, independent hidden flags.
3. **Native element means CALayer / DComp visual**, not a sibling `QWidget`. Overlay stays `WA_TransparentForMouseEvents`. `paintEvent` is only the offscreen / `PORYDAW_FORCE_WIDGET_PLAYHEAD` path.
4. **Shared value is camera content-x**, the same argument `setPlayhead` already takes (`SongView::contentX(tick)`). Overlay adds `m_timelineOrigin` → `finalX`. Per-band `timelineOrigin` on `TimelineBand` already clips the line to each plot (keyboard vs drawer gutter). Do not store widget-local x.
5. **Z-order, bottom → top:** hover guide, edit cursor, playhead. Playhead stays the top native child (`lastObject` on macOS).
6. **Chrome clip includes the ruler plot.** Playhead body clip stays bands `[1..]` plus the ruler triangle. Edit/hover use the union of every band’s `visibleSurfaceRect` (band 0 included). Then delete the dashed stroke from `drawOverlays`.
7. **One QPen style everywhere.** Hover: `song_view_secondary_text`, `layout::singlePixel()`, `Qt::DotLine`. Edit: `song_view_edit_cursor`, `layout::singlePixel()`, `Qt::DashLine`. Rasterize those pens into vertical strips (same technique as the playhead body image). Do not use `CAShapeLayer` on macOS only.
8. **Voice-change label stays in the widget.** Only the dotted *line* moves. Insertion ghosts, node-lane hover, keyboard hover-chip stay where they are.
9. **Surfaces keep input policy.** Overlay does not event-filter mouse-move. Each plot calls `SongView::setHoverGuide(std::optional<qreal>)`. Leave / gesture / geometry / document-swap still clear through that setter.

## Module

**Module:** `PlayheadOverlay`.

**Interface SongView must know:**

```cpp
void setPlayhead(qreal timelineX, bool visible, bool playing); // unchanged
void setEditCursor(std::optional<qreal> contentX);
void setHoverGuide(std::optional<qreal> contentX);
```

Identical values are true no-ops (no layer move, no `update()`, no image rebuild).

`nullopt` = that stroke hidden. Missing timeline → both chrome setters get `nullopt`. Playhead visibility must not hide chrome.

**Implementation (not the interface):** strip images, platform layer trees, widget-fallback regions, DPR/theme cache. Callers do not pass pens, clips, or `QPainter`.

**SongView seam:** `syncPlayheadOverlay()` stays. Add `syncEditCursorOverlay()` next to it (tick, scroll, zoom, geometry, song bind/unbind). `setHoverGuide` forwards to the overlay and does not live in drawer members.

## Invariants

1. Playhead `setPlayhead` / `m_playheadTransform` / `PorydawPlayheadLayer.hidden` never move or hide the cursor layers.
2. Hover mouse-move only calls `setHoverGuide` → a layer `position` / DComp translate. No strip re-raster, no `TimelineSurface::invalidateContent`, no `rebuildOverlay`.
3. Edit-cursor tick/camera changes only call `setEditCursor`. Drawer/roll/ruler/other-strip caches do not rebuild for that stroke.
4. When platform is applied, `paintEvent` still returns without painting (native layers are the pixels). Widget fallback paints hover, then edit, then playhead, each clipped to its region.
5. Overlay `raise()` still runs on geometry sync so the QWidget host stays above siblings; native layers stay on the window content view.

## Non-goals

- Qt Quick cursor item, `TimelineColumn`, second `QQuickWidget`, same-turn `flushUpdate`.
- Piggybacking hover onto the playhead sample clock or sharing `m_playheadTransform`.
- Renaming `PlayheadOverlay` / a general chrome abstraction.
- Overlay-owned mouse policy.
- Porting voice-change hover *labels*, note insertion lines, keyboard hover-chip.
- Full-app Qt Quick / `QQuickWindow`.
- Pixel-identity with today’s slightly different roll dash (`space(One)` dash/gap) vs drawer `Qt::DashLine`. Overlay uses decision 7.

## File-size

`playheadoverlay.cpp` is already ~462L. Do not absorb strip raster + two platform trees into it.

| File | Owns |
|---|---|
| `playheadoverlay.h` | Setters, optional content-x members, chrome image caches |
| `playheadoverlay.cpp` | QWidget host, geometry/clips, setter no-ops, `updatePaintRegion` union, widget-fallback paint dispatch |
| New `playheadoverlay_chrome.cpp` (and a short `.h` if the raster helpers are shared with checks) | Dash/dot strip raster (`QImage` + `QPainter` with the two pens), widget-fallback `paintChromeLine` |
| `playheadrenderer_macos.mm` | Sibling layers under a parent that is **not** hidden with the playhead |
| `playheadrenderer_dcomp.cpp` | Extra visuals with their **own** translate transforms; playhead transform stays playhead-only |

If `playheadrenderer_dcomp.cpp` (~777L) grows past a clean add, extract only the new cursor visual helpers — do not refactor the existing playhead tree in this plan.

CMake: add `playheadoverlay_chrome.cpp` next to `playheadoverlay.cpp`. No new target.

## Native trees

### macOS

Today: `PorydawPlayheadLayer` is a sublayer of the window `NSView`; `setPosition` sets `root.hidden` from playhead visibility.

Required:

```
PorydawTimelineOverlayLayer          // never hidden just because playhead is off
  PorydawHoverGuideLayer             // strip image, position = finalX
  PorydawEditCursorLayer
  PorydawPlayheadLayer               // existing body + triangle; hidden = playhead visible
```

Same body mask path as now, but hover/edit masks include the ruler plot. Re-add the **parent** if it is not the top-level overlay; playhead must remain the top child of that parent.

`setPosition` splits: playhead body/triangle + `PorydawPlayheadLayer.hidden`; chrome positions are separate calls.

`findPlayheadLayer` in `rollcheckplayhead_macos.mm` keeps finding `PorydawPlayheadLayer`. `renderMacPlayheadOverlay` must `renderInContext` the **parent** (`PorydawTimelineOverlayLayer`) so grabs include cursor chrome.

### Windows DComp

`m_playheadTransform` is applied to every body clip. Cursor visuals must not use it.

Add hover/edit surfaces (theme-colored dash/dot strips, not playing/paused variants) and clip visuals that reuse the chrome region (all bands). Independent `IDCompositionTranslateTransform` per stroke. `SetContent(nullptr)` hides a stroke; do not hide `m_rootVisual` for playhead-off.

### Widget fallback

`updatePaintRegion` dirty union = playhead region + edit strip + hover strip. `paintEvent` when `!m_platformApplied`: clip each stroke to the chrome region (all visible band plots).

## Surface cutover (delete the duplicate stroke)

| Site | Today | After |
|---|---|---|
| `PianoRollQuickScene::rebuildOverlay` `addDashedVertical` | edit cursor on roll | delete that stroke; Overlay dirty bit no longer needed for cursor |
| `drawOverlays` dashed `song_view_edit_cursor` | ruler + other-strip | delete the stroke; keep selection/loop |
| `AutomationCanvas::paintEditCursor` / `paintHoverGuideLine` | QPainter in plot | delete both paints |
| `VelocityArea` paint hover + edit | QPainter in `contentClip` | delete both paints |
| `VoiceChangeArea` dotted line | line + label | delete **line only** |
| `m_hoverGuideX` / `m_hoverX` as paint truth | widget-local | report `contentX = widgetX - origin` to SongView; members may die if the transition helper can call SongView directly |

Keep `hoverGuidePlot()` (or equivalent) as the **hit test** for “pointer is in a lane body,” not as a paint clip.

Camera/geometry change: clear hover (`setHoverGuide(std::nullopt)`). Next mouse-move re-arms. Do not try to keep a stale widget x across scroll/zoom.

## Hover reporters

Convert widget x with that surface’s plot origin, then `m_sv->setHoverGuide(contentX)` or `nullopt`.

| Surface | Arm | Clear |
|---|---|---|
| `AutomationCanvas` | move inside `hoverGuidePlot()`, idle interaction | leave, gesture, cancel, pencil, geometry, hide/deactivate, document/song |
| `VelocityArea` | `Interaction::None` and x in plot | same family as today |
| `PianoRoll` | x ≥ `pianoKeyboardWidth` (new: this is how the guide covers notes) | leave, keyboard column, geometry |
| `VoiceChangeArea` | existing hover-active plot x (line goes to overlay; label stays) | existing clearHover |
| `TimeRuler` / `OtherStrip` | x ≥ `plotOrigin` | leave / geometry |

SongView: last writer wins. Leave from surface A must not clear a guide already retargeted by surface B (compare source widget, or ignore a clear if the pointer is now in another band). Recommended: `setHoverGuide(QObject *source, std::optional<qreal>)` — clear only if `source` is the current owner.

## Checks (retarget, do not keep canvas-column budgets)

Today’s hover oracles assert **canvas backing-store** pixels and `TimelineSurface` strip invalidation. After cutover those are the wrong layer.

1. **Hover-only must not rebuild drawer caches.** `contentPaintCount` / `contentInvalidationCount` unchanged across a hover arm/move/leave on automation and velocity. Delete strip-budget formulas that assumed a 2px column invalidate.
2. **Chrome is on the overlay.** Widget-fallback (`PORYDAW_FORCE_WIDGET_PLAYHEAD`, already set for non-Apple rollcheck): overlay/widget paint contains the dotted/dashed color at `finalX`. Apple native: `grabSongViewWithPlayhead` / parent-layer `renderInContext` must show hover and edit, not only the playhead.
3. **`rendering-playheadcheck.cpp`** asserts `fixtureBand->grab()` changes when `editCursorTick` moves and that the canvas painted `song_view_edit_cursor`. That must move to the overlay composite; canvas grab must **stay equal**. Playhead-does-not-rebuild-canvas stays.
4. **`automationgesturecheck/hover.cpp`** `guideSpansStack` / `guideUnderCursor` / leave-restores: sample the overlay composite (or SongView+native grab), not `rig.renderArea()` of the canvas, for the *guide column*. Insertion line / held ghost / label stay canvas oracles.
5. **Sweep-restore trail check** (`checkHoverSweepRestores`): if the canvas no longer inks the guide, this oracle either drops or moves to overlay fallback paint. Do not keep a canvas trail test for ink that is gone.
6. **Precedence:** where hover x == edit x, dashed edit color is visible (edit layer above hover). Playhead still wins above both.
7. **Playhead independence:** `setPlayhead` while hover is armed does not hide the guide; hiding playhead does not hide edit/hover.

`deno task build:checks`, then the existing rollcheck / rendering-playhead / automation hover domain. No project-wide extra suites mid-wave.

## Stages

Each stage names the subagent that executes it. Do not start a stage until the previous acceptance holds. Skip formatters and `deno task verify` inside stages; the parent runs `deno task format` and the listed checks once at the end.

### Stage 0 — Confirm clip math (explorer, read-only)

Map `timelineBands()` origins vs `PlayheadOverlay::visibleSurfaceRect` / `m_timelineOrigin` (ruler `plotOrigin` in owner space). Confirm one content-x already aligns roll (header + `pianoKeyboardWidth`) with drawer `plotOrigin`. Record whether the ruler plot is already expressible as band 0’s visible rect (needed for decision 6).

Acceptance: a short note in the implementation PR/commit message, not extra code. If origins do not align, stop; do not invent a second content-x.

### Stage 1 — Overlay chrome (task)

Files: `playheadoverlay.h/.cpp`, new `playheadoverlay_chrome.cpp`, `playheadrenderer_macos.mm`, `playheadrenderer_dcomp.cpp`, `CMakeLists.txt`.

1. Add `setEditCursor` / `setHoverGuide`.
2. Raster dash/dot strips; cache on height/DPR/theme (not on x).
3. macOS parent layer + two chrome layers; stop hiding the playhead root for chrome.
4. DComp independent transforms + surfaces.
5. Widget-fallback paint + dirty union.
6. Playhead path unchanged: same `setPlayhead`, same triangle, same glow images.

Acceptance: with `PORYDAW_FORCE_WIDGET_PLAYHEAD=1`, calling the two setters from a throwaway/host path draws two independent columns clipped to band plots; moving playhead does not move them; `setPlayhead(..., false, ...)` leaves them. Native macOS: `PorydawPlayheadLayer` still exists; parent layer present; playhead `hidden` does not hide chrome children.

### Stage 2 — SongView sync + delete duplicate strokes (task)

Files: `songview.h/.cpp` (and the existing `syncPlayheadOverlay` call sites), `pianorollquickscene.cpp`, `detail.cpp` `drawOverlays`, `automationcanvas_paint.cpp`, `velocityarea_paint.cpp`, `voicechangearea_paint.cpp`.

1. `syncEditCursorOverlay()` beside `syncPlayheadOverlay()`; call both on camera/song/tick changes.
2. `setHoverGuide` on SongView.
3. Delete the strokes listed in the cutover table.
4. Do not strip voice-change labels or `rebuildOverlay`’s non-cursor geometry.

Acceptance: drawer/roll/ruler/other-strip grabs do not contain the edit/hover pens; overlay composite does at `contentX(editCursorTick)`. Changing edit tick does not bump automation `contentPaintCount`.

### Stage 3 — Hover reporters (task)

Files: automation input transition helper, velocity interaction, piano-roll mouse move/leave, voice-change `updateHover`/`clearHover`, ruler/other-strip mouse move/leave.

Replace widget-local paint state with SongView reports. Delete `hoverGuideTransition` strip dirty if nothing else uses it. Keep arm/clear *paths* from the old hover-guide plan.

Acceptance: hover in automation, velocity, **or** the roll plot draws one dotted column through all visible plots including notes; leave clears; gesture on automation clears; moving from automation into velocity does not flash off.

### Stage 4 — Checks (task)

Files: `rollcheckhover.cpp`, `rollcheckplayhead.cpp`, `rollcheckplayhead_macos.mm`, `renderingplayheadcheck.cpp`, `automationgesturecheck/hover.cpp` (guide-column oracles only).

Retarget as in **Checks** above. Extend `renderMacPlayheadOverlay` to the parent layer.

Acceptance: listed harnesses pass on the worktree. Canvas hover-column budgets are gone. Native macOS grab includes cursor chrome.

### Stage 5 — Review (reviewer)

Dedicated `reviewer` after Stage 4 (and after Stage 1 if the platform trees drifted). Check: no shared playhead transform; no canvas invalidate on hover; overlay still transparent to mouse; voice-change label intact; file-size of `playheadoverlay.cpp` / dcomp; `PorydawPlayheadLayer` lifecycle check still valid.

## Verification (parent, once)

```sh
deno task build:checks
deno task verify --filter rollcheck --verbose
# plus rendering-playhead / automation hover domain as wired in checkcatalog
deno task format --check
```

Manual: hover the roll, automation, and velocity — one dotted column through notes and lanes, covering the Quick FBO. Edit cursor dashed, on top of hover, under the playhead. Pause playback: playhead may hide; edit/hover stay. Theme change recolors strips without a stuck old color.

## Critical files

- `src/ui/playheadoverlay.h`
- `src/ui/playheadoverlay.cpp`
- `src/ui/playheadrenderer_macos.mm`
- `src/ui/playheadrenderer_dcomp.cpp`
- `src/ui/songview.cpp` / `songview.h`
- `src/ui/songview/quick/pianorollquickscene.cpp`
- `src/ui/songview/detail.cpp`
- `src/ui/editordrawer/automationcanvas_paint.cpp`
- `src/ui/editordrawer/automationcanvas_input.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea_paint.cpp`
- `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp`
- `src/ui/editordrawer/voicechangearea/voicechangearea_paint.cpp`
- `src/checks/rollcheckhover.cpp`
- `src/checks/rollcheckplayhead.cpp`
- `src/checks/rollcheckplayhead_macos.mm`
- `src/checks/renderingplayheadcheck.cpp`
- `src/checks/automationgesturecheck/hover.cpp`

## Rejected

- Hover chip on the roll + QPainter on the drawer (third adapter; one-frame trail; cannot cover the FBO).
- N `QQuickWidget`s.
- Same-turn `flushUpdate`.
- One native layer whose contents are playhead+cursor, recomposited on the playhead clock.
- `QWidget` overlay paint as the production path on Cocoa/DComp.
