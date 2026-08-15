# Peel 03 — Velocity lane with PSG detents (the flagship feature)

Read `docs/peels/GROUND-RULES.md` first. **Depends on Peel 01** (NoteId, revision,
`setNotesVelocities`). This is the largest peel; plan milestones and expect several
commits. Source: branch commits `6d2f7e0` (models) + `552d2ee` (UI) + harness
`src/rollcheckpsgvelocity.cpp` (1989 lines, from `afcc8fa`) whose comments/asserts
are the authoritative behavior spec.

---

## STATUS (2026-08-14): milestones 1–4 done and user-approved, 5–6 remain

Branch **`peel/03-velocity-lane`**. Milestones 1 and 2 were reviewed and merged to
`main` (tip `a8a46e4`). Milestones 3 and 4 are committed on the branch, unmerged
and unpushed; the user has tried them in-app ("works and feels great") and vetoed
none of the decisions below — treat them as settled, not as open questions.

```
2aa085a  Add the PSG velocity model                          (milestone 1, on main)
f572948  Add a read-only velocity lane on the V key          (milestone 2, on main)
a8a46e4  Fix review findings on the velocity lane            (on main)
c0389a6  Add relative velocity drags to the velocity lane    (milestone 3)
986d987  Add painting, ramps, and ruler clicks               (milestone 4)
603cafa  Fix review findings on the velocity lane's gestures (/code-review high, 7 findings)
```

Continue on this branch, one commit per milestone, `/code-review high` at the end
of each. Everything below the horizontal rule at the end is the original brief and
still governs milestones 5–6.

### What already exists (do not re-port it)

- **`src/core/velocitymodel.{h,cpp}`** — `VelocityMap`, ported nearly as-is from the
  branch: voice classification, level tiling, `levelOf`/`levelRange`/`representative`,
  `canonicalize`, `moveLevels`. Complete; **nothing in the UI consumes it yet** — the
  intrinsic milestone (5) is still its first caller. Milestones 3 and 4 deliberately
  clamp instead of canonicalizing, so every velocity they write is exact.
- **`src/ui/velocityaxis.{h,cpp}`** — `VelocityAxis`, the value ruler, **continuous
  half only**: `velocityToY`, `yToVelocity`, `rulerVelocityAt`, the five density
  bands, ticks/labels, the selection's min/max markers, `paintRuler`. The branch's
  intrinsic half (`Mode`, a `VelocityMap` member, `buildIntrinsicRows`, `levelToY`,
  `yToLevel`, graduations) is deliberately *not* here yet — milestone 5 adds it, and
  `rulerVelocityAt` will need its Intrinsic branch then. The branch's vestigial
  machinery (intrinsic label columns, `focusable` flags, `showIntrinsicVelocity`, the
  `char` label arrays) was dropped; do not reintroduce it.
- **`src/ui/velocitygesturemodel.{h,cpp}`** — the branch's deferred-gesture model
  (targets + origins + preview; `takeCompletion()` carries `expectedRevision`),
  ported nearly as-is and **owned by the lane**, not by SongView: main's roll keeps
  its own velocity drag, and one gesture shared between the two surfaces is the
  branch's stretch goal, deliberately not attempted. Its unit checks live in
  `--velmodelcheck`.
- **`songview::VelocityLane`** in `src/ui/songview.cpp` — the lane widget, a
  `TimelineSurface` living beside `PianoRoll` / `AutomationArea` so it shares their
  file-local `drawGrid`, `drawPreRoll`, `drawOverlays`, and `mixTowardOklab`. It
  paints nodes + stems + ruler, handles the wheel and the middle-button pan, and owns
  every milestone 3/4 gesture (below). The **right button is still untouched**, which
  is where milestone 6 starts.
- **Gestures (milestones 3 and 4)**, all deferred through the gesture model — the
  pointer moves a preview and the document mutates once, as one undo entry, on the
  release via `setNotesVelocities(expectedRevision, …)`:
  - node/stem grab (`VelocityLane::noteAt`: a node's circle outranks a bare stem, a
    selected note outranks an unselected one, then nearest, then later-painted) and
    relative drag of the whole selection by the drag's own vertical travel, each note
    measured from its own origin (`VelocityGestureModel::updateByDelta`);
  - click semantics under the activation slop: plain collapses onto the node, Ctrl
    toggles its membership, empty plot clears — always on the release;
  - **paint** (`paintBetween`): a drag from empty plot brushing only selected notes
    whose tick the segment crosses, interpolating along it, starting at the press;
  - **ramp** (`updateRamp`): Shift anywhere in the plot, the press→pointer line with
    a guide line in `song_view_edit_preview_outline`;
  - **ruler click** (`rulerClick`): the whole selection set to a printed value;
  - cancel on Escape / focus-out / `QEvent::UngrabMouse` / a document rebuild
    (`VelocityLane::documentChanged`, called from `SongView::updateSong`), restoring
    the pre-press selection;
  - the status readout through the roll's own `SongView::announceNote`, and
    `gestureActive()` (so follow-scroll pauses) now covering the edits too.
- **Selection translation**: `ViewNote` already carries `NoteId`, so the lane builds
  its gesture targets straight from the view model; only the *selection* needs
  translating, and main's `SongView::NoteKey` (tick, key) is what the lane reads and
  writes. No `findNote` round trip is needed anywhere.
- **Hosting**: a third pane in the existing roll/lanes `QSplitter`, between the roll
  pane and the automation lanes' scroll area, hidden by default. `SongView` grew
  `velocityLaneVisible()` / `setVelocityLaneVisible()` / the
  `velocityLaneVisibilityChanged` signal, and the lane is the fifth band in
  `songview::TimelineSurfaces` (so the playhead crosses it).
- **Toggle**: keymap command `view.velocity_lane` (`Context::PianoRoll`, default
  **V**) dispatched through `SongView::handleEditKey` like M/S/B, plus a
  View-menu checkable action with **no shortcut of its own** (a bare letter must
  never become a window shortcut). Visibility persists app-wide in QSettings
  (`velocityLane`, `MainWindow`); the pane's height rides the sidecar's splitter
  sizes, with pre-lane two-entry sidecars mapped to `{roll, lane, lanes}`.
- **Harnesses** in `src/velcheck.cpp` (1199 lines), both in `tools/run_checks.sh`:
  - `--velmodelcheck` — self-contained `VelocityMap` **and** `VelocityGestureModel`
    checks.
  - `--velcheck <projectRoot> <song> [shot.png]` — the lane, driven offscreen: the
    toggle, node/stem placement, the selection's ring and ruler markers, ruler
    density, zoom/pan, the view-state round trip, and every milestone 3/4 gesture
    with its deferral, preview, status wording, and cancel paths; plus
    `runVelocityAxisBandCheck` (a unit-style pass over the density bands and the
    ruler's click targets).
- SPEC §6.1's "Between them — Velocity lane" bullet and the CHANGELOG entry describe
  everything through milestone 4; both still say the marquee and the PSG detents are
  not in yet. Update them per milestone.

### Decisions already taken (settled; keep or raise with the user first)

- Splitter pane, not the branch's overlay drawer chrome (the brief's recommendation).
- The lane sits **above** the automation lanes, directly under the roll.
- Milestone 2 is continuous-only: a PSG track still shows the plain 1–127 ruler
  until milestone 5, matching this brief's milestone list.
- The densest ruler band steps from 124 (the branch used 123, which floated every
  label off its graduation); the run lands exactly on `MaximumTicks`.
- Node/stem/ring weights are authored in DIPs, floored at one physical pixel.
- Unselected-node dimming counts the **whole track's** selection, never the visible
  slice (`VelocityLane::dimUnselectedNodes`, the one statement of it).
- The lane owns the gesture model (see above); no shared roll/lane gesture.
- The drag's activation slop is main's lanes' figure, `lyt::fontPx(5.0/12.0)`, and is
  measured on **y alone** — velocity has no horizontal axis, so a sideways wobble
  stays a click instead of arming a drag that commits nothing and selects nothing.
  The ramp requires the same travel before it commits (the branch committed on any
  pixel of travel).
- Commits announce "Painted"/"Ramped"/"Set note velocities." by gesture, rather than
  the branch's single "Painted note velocities." for all of them. Cancels keep the
  branch's "Velocity edit cancelled because notes changed.", but only when the
  document actually refused the batch.
- The ruler's click targets are exactly the values it prints: selection markers
  included, marker-covered fixed labels excluded (`paintRuler` drops a label within a
  full label height of a marker, so `rulerVelocityAt` must too). The track-header
  column left of the ruler is not the lane's — a press there is ignored.
- The middle-button pan and a left-button edit refuse each other: panning moves the
  ticks a live gesture's press coordinates were measured against.

### Gotchas that cost time here

- **Mutation-based negative tests on `songview.cpp` must anchor on lane-specific
  text.** `TimeRuler`, `PianoRoll`, and `AutomationArea` contain byte-identical
  wheel/pan blocks (and `if (event->modifiers() & Qt::ShiftModifier)` appears three
  times); a first-occurrence replace silently mutates the wrong widget and the probe
  then "passes" for the wrong reason. Anchor on the lane's own comments.
- **A mutation harness must `touch` the file it restores.** Restoring a backup keeps
  the backup's old mtime, so `make` skips the rebuild and the *previous* mutation
  stays linked into the binary — probes then fail for reasons that have nothing to do
  with the mutation under test. This cost about 40 minutes.
- **Anchor mutations on the post-`clang-format` text.** Re-running `tools/format.sh`
  rewraps the lines a mutation script matched on, and the anchor silently stops
  matching.
- **`velcheck`'s undo assertions use `undoStack()->index()`, not `count()`.** The
  gesture probes undo as they go, and the next commit discards the redo branch, so
  the stack's size stops growing while the index keeps tracking.
- **The gesture probes need the camera put back.** The zoom/pan checks earlier in
  `velcheck` leave the view zoomed in and scrolled away, with nothing usable on
  screen; restore `beforeZoom` and scroll home first.
- **Probe notes need headroom.** A ±20 drag must not clamp, so the probe picks notes
  with velocity in [25, 103] — `mus_abandoned_ship`'s track 0 is mostly 108, which is
  why the first attempt found no candidates. The paint probe additionally needs an
  *unselected* note under the stroke (its partner is therefore the farthest
  candidate, not the nearest) and endpoints on rows with nothing on them.
- **Pixel probes must dodge the overlay verticals** (edit cursor, loop markers,
  playhead). The loop marker's ink equals `palette().highlight()`, which quietly
  satisfied a selection-ring probe until the probed note was moved clear of it.
  `velcheck.cpp`'s `overlayContested` lambda does this; reuse it.
- A selected note's **stem** is painted in the same highlight color as its ring, so a
  ring probe has to sample *above* the node, not across it.
- The harness never shows the window: use `isHidden()` and `view.focusWidget()`,
  never `isVisible()` / `hasFocus()` (both are activation-sensitive).
- `QSplitter::setSizes` renormalizes to the splitter's height, and the stretchy roll
  pane absorbs the slack — assert restored sizes accordingly.
- Test mirrors on the lane are dynamic properties set in `paintContent`
  (`velocityAxisTop`, `velocityAxisBottom`, `velocityTickCount`,
  `velocityMarkerCount`, `velocityDimmed`), following the lanes' `hoverNodeTick`
  precedent. Add to them rather than exposing widget internals in `songview.h`.
- The harness must mirror the app's own rebuild wiring
  (`documentChanged` → `buildTimeline` → `SongView::updateSong`, as `rollcheck` does)
  or the lane hit-tests a stale model after the first commit.

### Milestones remaining

5. PSG intrinsic mode + detent toggle + unlock modifier (first consumer of
   `VelocityMap`; also grows `VelocityAxis` its intrinsic half and adds the
   `song_view_psg_velocity_levels` theme role).
6. Marquee selection.

The deferred gesture model, the `setNotesVelocities(expectedRevision, …)` commit
path, the status readout, and the selection translation described under "Porting
notes" below all landed with milestones 3 and 4; 5 and 6 build on them. Milestone 5
is where the gestures' clamping becomes `canonicalize` / `moveLevels`, where
`yForNote` gains its level-center placement, and where the frozen notes need the
per-note `VelocityMap` the branch's `FrozenNote` carries.

---

## What it is

A dedicated, resizable, hidden-by-default **velocity lane** sharing the piano
roll's timeline: each note of the selected track is a node (circle at tick ×
velocity) with a duration stem. It adds multi-note velocity painting, ramps,
marquee selection in the velocity domain, an adaptive value ruler, and — the
namesake — **PSG-aware quantization** to the engine's real loudness detents.

## Branch anatomy (read these)

- `src/core/velocitymodel.{h,cpp}` — `VelocityMap`: voice classification from
  `ToneData::type & VOICE_TYPE_CGB_MASK` (keysplit resolved by key); pulse/noise
  share a 16-level path (representatives {1,12,20,…,127}, level n = [n*8+1,(n+1)*8]),
  wave collapses to 5 levels via the gCgb3Vol mapping; `levelOf` uses the engine's
  effective-velocity math `min(((v+3)/4)*4,127)`; `canonicalize`, `moveLevels`
  (level moves preserve exact origins on round-trip). **DONE — ported in `2aa085a`.**
- `src/ui/editordrawer/velocityaxis.{h,cpp}` — value ruler: always 1–127 domain,
  no vertical zoom; Continuous mode with 5 density-adaptive tick/label bands;
  Intrinsic (PSG) mode with one graduation per level labeled "Vol 1…N"; min/max
  markers for the active values; accessible description. **Continuous half ported
  in `f572948`, its `yToVelocity` / `rulerVelocityAt` in `c0389a6`/`986d987`; the
  Intrinsic half is milestone 5's job.**
- `src/ui/editordrawer/velocityarea.{h,cpp}` (~1185 lines) — the lane widget.
  Rewrite against main's SongView (see Porting notes). **Ported as
  `songview::VelocityLane` through milestone 4; what remains of this file is the
  marquee (milestone 6) and everything PSG (milestone 5): `currentContext`,
  `contextForNote`, `levelBoundaryY`, `levelCenterY`, `yForNote`, `detentsUnlocked`,
  the intrinsic paint, and the `FrozenNote::map` / `exactOrigin` fields.**
- `src/ui/velocitygesturemodel.{h,cpp}` — deferred gesture (targets + originals +
  preview; `takeCompletion()` carries `expectedRevision`). **DONE — ported in
  `c0389a6`, owned by the lane.**
- `src/ui/selectionreticle.{h,cpp}` — shared marquee painter (tiny, port as-is).
  **Not ported yet (milestone 6).**
- Assets: `resources/velocity.svg`, `resources/velocity_labels.svg`.
- Theme: new role `song_view_psg_velocity_levels` (branch `theme_roles.h:179`,
  `themeresolver.cpp:566-570` — derived `shiftOklabLightness(pianoRollBackground,
  -0.08)`, deliberately dark in every theme; also `presetcolors.h:289`).
  **Not added yet — milestone 5 needs it (and a themecheck pass).**
- Keymap: new `Context::Velocity`; `velocity.detent_unlock` modifier command,
  default Ctrl; the shortcuts dialog must filter Shift-bearing chords for it
  (branch `keyboardshortcutsdialog.cpp:228-240`) because Shift means ramp.
  **Not added yet — milestone 5. Note main already has `view.velocity_lane` in
  `Context::PianoRoll`; decide then whether the lane's own commands want a new
  context or stay on `PianoRoll` (the lane routes `handleEditKey` already).**

## Behavior spec (assert all of this; harness refs are rollcheckpsgvelocity.cpp)

- **Nodes/stems**: selected-track notes only; selected nodes ring + highlight,
  unselected dim when >1 selected; stems in OKLab-darkened track color. **DONE.**
- **Left drag on node/stem** = relative move of ALL selected notes (unselected
  press replaces selection; Ctrl adds). Activation slop; unactivated release is a
  click (Ctrl toggles membership, plain collapses to that note). **DONE** — the slop
  is measured on y alone (see the decisions above).
- **Left drag on empty plot** = Paint: brushes only currently-selected notes whose
  x the stroke crosses, interpolating along the segment. Painting nothing ⇒ the
  release (not the press) clears the selection (harness :1119, :1123). **DONE.**
- **Shift+drag** = linear ramp across the selection between press and cursor.
  **DONE**, plus the activation travel the branch skipped.
- **Ruler click** = absolute set for the whole selection (Continuous: only within
  ±half a label height of a printed label; Intrinsic: any y in the level).
  **Continuous DONE** — with the marker rule from the decisions above; **Intrinsic is
  milestone 5.**
- **Right-drag** = marquee: replaces selection, Ctrl unions; Ctrl+right-click
  toggles a node; right-click empty clears. No context menu in the lane.
  **Milestone 6 — the right button is untouched today.**
- **Middle drag** pans; plain wheel zooms time anchored at cursor; Shift/horizontal
  wheel scrolls; wheel over ruler ignored. **DONE** (the ruler column passes the
  wheel on rather than swallowing it; the pan now refuses to start under a live
  edit).
- **PSG quantization**: when all selected notes resolve to one PSG voice (or, with
  no selection, the voice at playhead/edit cursor), the ruler goes Intrinsic, nodes
  snap visually to level-row centers, per-voice-section level boundary lines paint
  across the plot, and edits snap to representatives / move whole levels.
  `velocity.detent_unlock` (Ctrl, captured at press-time only — harness :1519)
  gives exact values; a detent on/off toggle button (velocity_labels.svg icon)
  appears only in PSG context and resets to on when leaving it. **Milestone 5.**
- **Deferred commits**: document mutates once on release via
  `setNotesVelocities(expectedRevision, …)`; mid-gesture doc change cancels with
  "Velocity edit cancelled because notes changed."; Escape/focus-loss/ungrab
  cancels and restores the pre-press selection. Announce "Painted note velocities."
  **DONE**, with the per-gesture wording from the decisions above.
- Status readout during gestures: key, stored velocity, effective `((v+3)/4)*4`,
  duration ticks/clocks. Follow-scroll paused during gestures. **DONE** — the
  readout reuses the roll's `SongView::announceNote`, which already prints exactly
  that line, and `VelocityLane::gestureActive()` now covers the edits as well as the
  pan.

## Porting notes (the real work)

- **Hosting: do NOT port the branch's overlay drawer chrome** (`editordrawer.cpp`,
  `drawersections.cpp`). **SETTLED and implemented**: the lane is its own pane in
  main's roll/lanes `QSplitter`, between the roll and the automation lanes, resized
  by the splitter. Main's automation pane is untouched and always available.
- **Toggle**: **DONE** — `view.velocity_lane` (default V) in `keymap::Registry`,
  dispatched via `handleEditKey`, View-menu action without its own shortcut,
  visibility persisted app-wide in QSettings (Follow Playhead precedent).
- **Selection**: branch uses stable `NoteId` selection on SongView; main's roll
  selection is `{tick,key}` pairs (`SongView::NoteKey`). **DONE, minimally**: main's
  roll selection stayed, and the lane translates at its own boundary — it reads
  membership through `SongView::isSelected(ViewNote)` and writes `NoteKey`s back,
  while the gesture targets ride the `NoteId` that `ViewNote` already carries, so no
  document lookup is involved. Full parity (roll and lane share one NoteId selection
  + live gesture model so a roll Ctrl-drag live-updates the lane) remains a stretch
  milestone — flag it, don't attempt it inside 5 or 6.
- SongView surface needed by the lane: `paintGrid`-equivalent (**done** — the lane
  calls the file-local `drawGrid`/`drawPreRoll`/`drawOverlays` directly),
  `zoomAroundContentX`, scroll plumbing (**done**), `voiceContext(tick)` (branch
  `songview.cpp:5630-5648`; main has `currentProgram(track)` / `programAtTick` —
  extend, **still to do**, milestone 5), follow-scroll pause (`gestureActive`
  pattern, **done**), `announce` / `announceNote` (**done — the gestures use them**).
- Suggested milestones: (1) `VelocityMap` + unit-style checks **[DONE]**;
  (2) read-only lane (nodes/stems/ruler/zoom/pan, V toggle) **[DONE]**;
  (3) relative drag + click semantics **[DONE]**; (4) paint + ramp + ruler-click
  **[DONE]**; (5) PSG intrinsic mode + detent toggle + unlock modifier;
  (6) marquee selection. Commit per milestone.

## Tests

- Port `src/rollcheckpsgvelocity.cpp` incrementally alongside the milestones — it
  is the spec. **Registered as `--velcheck` (lane) and `--velmodelcheck` (model) in
  main.cpp/CMake + run_checks; grow those rather than adding new flags.**
  Negative-test every probe; SF 1/1.5/2; full ASAN sweep + ctest.
- SPEC.md section for the lane **[exists — extend it per milestone]**; CHANGELOG
  entry **[exists — it now describes everything through milestone 4]**.

## Open questions for the user

- ~~Splitter-pane vs stacked-above-automation hosting~~ — settled: splitter pane.
- ~~Whether the status readout and hover feedback arrive with milestones 3/4~~ —
  the readout did; **hover feedback (the branch's hovered-node context) never has
  been ported** and is not scheduled. Milestone 5 is where the branch uses it (the
  hovered node's voice decides the intrinsic context), so decide there.
- Whether roll/lane live-shared gestures (stretch milestone) are wanted in v1.
