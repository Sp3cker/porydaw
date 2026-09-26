# Context

Grid denomination cutover, part 1 of 2 (with task-34b). User ruling: copy the
fork's grid denomination, copy the checks; the Swift `snapScale`
"Adaptive ÷N / ×N" model was made up. Fork-main = `fceecd88`.

1. **Fork model** (`git show fceecd88:src/ui/songview/grid.h`, `grid.cpp`):
   - `GridFeel` = Straight | Triplet (grid.h:15).
   - `GridSelection` = Kind Auto/Musical/Clock + `denominator`
     (grid.h:22-45). Menu id codec: Auto → -1, Clock → 0, Musical → the
     denominator (`toMenuId` grid.h:35-38, `fromMenuId` grid.h:39-42).
   - Selection ladder `selections()` (grid.cpp:24-41): Auto, then musical
     denominators 4, 8, 16, … while `musicalTicks(candidate, feel) != 0 &&
     > clockTicks()`, then Clock. `musicalTicks` (grid.cpp:266-276) =
     `ppqn * (straight ? 4 : 8) / (denominator * (triplet ? 3 : 1))`, 0 when
     non-integral or denominator < 4 / not a power of two.
   - Canonicalization (grid.cpp:43-51): Auto stays; Musical whose
     `musicalTicks > clockTicks` stays; everything else becomes Clock.
   - Transitions: `setSelection`/`setFeel` = `setState` (grid.cpp:53-61,
     126-133: install feel, canonicalize selection against the NEW ladder);
     `narrow`/`widen` step one ladder position (grid.cpp:63-83; no-op at
     either end; a selection missing from the ladder re-canonicalizes);
     `toggleFeel` (grid.cpp:85-124) flips feel, keeps Auto/Clock spacing,
     keeps a Musical denominator whose counterpart canonicalizes, else walks
     the new ladder once for the nearest representable spacing (finer toward
     triplet: `spacing <= previous && > nearest`; coarser toward straight:
     `spacing >= previous && < nearest`), Clock fallback;
     `setTicksPerClock` (grid.cpp:135-142) moves the clock floor and
     re-canonicalizes, reporting the floor move as a change.
   - Adaptive ladders per feel, divisions per beat (grid.cpp:231-232):
     straight `{32,16,8,4,2,1}`, triplet `{48,24,12,6,3,1}`. Visible stride
     (grid.cpp:222-254): finest rung whose cell
     `pxPerSegBeat / ladder[i] >= automationGridMinimumCellWidth` (default
     coarsest = whole beats), `vis = max(beatTicks / ladder[step], clock)`;
     snap = one rung finer via `gcd(vis, fine)` floored at the clock.
   - Fixed spacing: `fixedTicks` (grid.cpp:278-287) = Musical
     `max(clock, musicalTicks)`, else clock; `clockTicks` = `max(1, m_clock)`
     (grid.cpp:261-264); unbound (no document) → `fineGridTicks` falls back
     to `gridTicksAt(0)` (grid.cpp:256-259).
   - Visible cells (grid.cpp:157-178): when `pxPerBeat <
     timelineDetailMinimumPixelsPerBeat` the cell is a bar
     (`beatTicks * beatsPerBar`), else the drawn sub-grid stride; half-open
     `[start, min(start+stride, segment.next)]` with a `kMaxTick` overflow
     guard.
   - Paint gating `drawsSubGridIn` (grid.cpp:202-215): Clock paints while
     its cell is ≥ `clockMinimumCellWidth`; Musical while ≥
     `automationGridMinimumCellWidth`; Auto while the beat is ≥
     `timelineDetailMinimumPixelsPerBeat`. Suppression is paint-only: snap
     math never reads it.
   - Anchors: `subGridAnchorIn` (grid.cpp:197-200) = tick 0 for Clock
     (absolute lattice across signature seams), segment start otherwise.
   - Lattice rounding (grid.cpp:296-326): floor/ceil/round on
     `{anchor, stride, limit}`; `tiesUp` = true only for the fine/Clock
     absolute lattice; Auto/Musical segment lattices tie down. `snapTick`,
     `snapTickDown`, `snapTickUp` clamp at 0 (grid.cpp:328-341).
   - Walkers: `nextSubdivisionTickAfter` (painted grid, clamps at the next
     seam for Auto/Musical, grid.cpp:343-355) and `nextSnapTickAfter`
     (editing grid; `fine`/Clock walk the absolute lattice, never clamp at a
     seam, grid.cpp:357-369).
   - Painted sub-beat walk `detail::forEachSubGridLine`
     (`git show fceecd88:src/ui/songview/detail.h:101-123`): stride
     `gridTicksAt`, only while `stride < beatTicks && drawsSubGridIn`,
     anchored per `subGridAnchorIn`, skipping beat/bar positions; level from
     `subGridLevel` (detail.cpp:227-234): 1 when `rel % (beat/(3|2)) == 0`,
     2 when `rel % (beat/(6|4)) == 0`, else 3.
   - Thresholds come from font math (`git show fceecd88:src/ui/songview.cpp:
     61-83, 101-105`): detail = `fontPx(5/6)`, clock cell =
     `gridLineStrokeWidth` = `fontPx(1/6)`, automation cell = `fontPx(4/3)`.
     Swift `GridMetrics` already computes all three
     (src/swift/app/timeline/GridGeometry.swift:54-56, 86-88:
     `detailMinPxPerBeat`, `gridLineStroke`, `autoGridMinCell`).
   - Host wiring: `setTicksPerClock(document.ticksPerClock())` then
     `setState(automatic, Straight)` on every song attach
     (songview.cpp:601-605); state shared by ruler, roll, automation,
     velocity, voice changes, pitch bend (`owner.grid()` — automationpage.cpp
     :31, automationprojection.cpp:39, voicechangearea.cpp:37,
     pitchbendgraph.cpp:41, pianoroll.cpp:34, timelinequickscene.cpp:648,
     timerulerquick.cpp:182).
2. **Invented Swift model to delete**: `GridMetrics.snapScale: Int` and
   `tripletGrid: Bool` (GridGeometry.swift:57-58), the halving/doubling +
   `*2/3` snap math in `snapTicks(camera:)` (GridGeometry.swift:141-158),
   segment-0-only lattices (GridGeometry.swift:160-184), the straight-only
   `visibleGridTicks` (GridGeometry.swift:94-114) and
   `forEachSubdivision` (GridGeometry.swift:117-139) without paint gating,
   clock anchoring or triplet levels. Swift's clock math is already correct
   and stays: `TimelineSnapPolicy.clockTicks(division:extendedClocks:)` =
   fork `SongDocument::ticksPerClock()` and `fineSnap` = fork
   `Grid::snapTick(fine:)` (src/swift/app/timeline/TimelineSnapPolicy.swift:
   7-24).
3. **Fork checks to port here (core math)**:
   `src/checks/eventviews/viewbuckets_grid.cpp`
   (`git show fceecd88:src/checks/eventviews/viewbuckets_grid.cpp`):
   - `snapLadder` (150-194): seven rows over `cell = fontPx(4/3)` —
     `straight below` pxPerBeat `4*cell-1` Auto/Straight grid 12 snap 6;
     `straight threshold` `4*cell` grid 6 snap 3; `triplet` `6*cell` Auto/
     Triplet grid 4 snap 2; `triplet eighth fixed` `6*cell` denom 8 Triplet
     8/8; `straight sixteenth fixed` `4*cell` denom 16 6/6; `straight
     quarter fixed` `4*cell` denom 4 24/24; `clock fixed` `4*cell` Clock 1/1.
   - `gridLinesSnappable` (196-225): Auto selection; every
     `forEachGridLine` tick over the whole song satisfies
     `grid().snapTick(tick) == tick` (Basic + Signatures shapes).
   - `clockLatticeCrossesSignatureSeam` (227-263): 48-PPQN fixture (clock
     stride 2), `setTimeSig(37, 5, 3)`; segments at 36/37; Clock selection;
     zoom `24*cell`; `snapTickDown(37)==36`, `snapTickUp(37)==38`,
     `nextSnapTickAfter(35)==36`, `(36)==38`, `nextSubdivisionTickAfter
     (36)==38`, `(37)==38`; `forEachSubGridLine(30,46)` =
     `{30,32,34,38,40,42,44}` (seam 37 is a beat line).
   - `fixedGridPaintDensityGuard` (265-304): musical(8): sub-grid paints at
     `2*cell`, suppresses at `cell`; `snapTicksAt(0)==12`,
     `snapTickDown(37)==36`, `nextSnapTickAfter(24)==36` unchanged by
     suppression; Clock: paints at `6*cell`, suppresses at `2*cell`,
     `snapTicksAt(0)` unchanged.
   - `PianoRollStaticTest::tickRangeWalksFractionalLattice`
     (`git show fceecd88:src/checks/rollcheck/static/camera.cpp:94-183`):
     Auto grid at zoom 384 (`lattice > 0`, sub-grid culled to viewport);
     musical(16) coarser lattice `snapG >= 3`, `beatTicks % snapG == 0`,
     `nextSubdivisionTickAfter(96) == nextSubdivisionTickAfter(97) ==
     96 + latticeG` (segment-anchored); tie resolution
     `snapTick(96 + snapG/2) == 96`, `- 0.25 → 96`, `+ 0.25 → 96 + snapG`,
     `snapTickDown(+0.25) == 96`, `snapTickUp(-0.25) == 96 + snapG`
     (Auto ties down); 5/8 seam at 102: `snapTickDown(103.5)==102`,
     `snapTickUp(101.5)==102`, sub-grid restart at the seam.
   - Fork has **no** check calling `Grid::narrow/widen/toggleFeel` directly
     (verified: only production callers, grid.cpp:398-411); ladder movement
     is covered indirectly (identity/lifecycle checks pin the state).
4. **Ledger**: `src/checks/eventviews/proof.viewbuckets_grid.txt` — 50 A
   rows (3 MATCHED, 7 PARTIAL, 39 GAP, 1 RETIRED). Every model row above is
   GAP today; S011-S013 (`clockParityLattice`, TimeAxis seams) already
   MATCHED and must stay green. `src/checks/rollcheck/static/
   proof.camera.txt` rows A017+ (fractional lattice walk) are PARTIAL/GAP
   for the same reason.

# Exact write set

- `src/swift/app/timeline/GridGeometry.swift` — add `GridFeel`,
  `GridSelection` (kind + denominator + `toMenuId`/`fromMenuId`) and the
  `RollGrid` value type (feel, selection, clock floor) implementing every
  fork rule above against `(axis: TimeAxis, metrics thresholds,
  camera: EditorCamera)`; port `forEachSubdivision` to the fork
  `forEachSubGridLine` contract (gating, anchors, triplet levels); delete
  the invented `snapTicks(camera:)`/`snapTick*`/`lattice*` math and the
  straight-only ladder. Keep `snapScale`/`tripletGrid` stored fields and
  `gridLadderStep`'s threshold choice only as the interim seam task-34b
  deletes.
- `src/swift/app/DocumentSession.swift` — store `grid: RollGrid` (default
  Auto/Straight) next to `camera`; expose `gridClockTicks`
  (`TimelineSnapPolicy.clockTicks(division:extendedClocks:)`); reset the
  grid to the default on document (re)open (fork songview.cpp:601-605).
- `src/swift/app/roll/GridScene.swift` — painted sub-grid from
  `session.grid` (`gridTicksAt` + `drawsSubGridIn` + `subGridAnchorIn` +
  triplet `subGridLevel`), replacing `visibleGridTicks(in:camera:)` walks
  (:431-441).
- `src/swift/app/drawer/automation/AutomationContentPublication.swift`
  (:182-197), `src/swift/app/drawer/velocity/VelocitySceneValues.swift`
  (:223-241), `src/swift/app/drawer/voicechanges/VoiceChangesProjection.swift`
  (:362-385) — same painted-sub-grid switch so drawer grids follow the
  selection + feel (fork shares one Grid across all surfaces).
- `src/swift/app/drawer/automation/AutomationProjection.swift` — non-fine
  snapping (:108-122) through `session.grid` (`snapTickDown/Up`,
  `nextSnapTickAfter`), fine path unchanged.
- `src/swift/app/roll/PianoGrid.swift` — snap/placement consumers only:
  projection `snap` (:222), draw cell via `visibleGridCellContaining`
  (:255-256), command `grid` + `nextSubdivision` closure (:490-497), and the
  published `snapTicks`/`visibleGridTicks` (:112-113, :1178-1180) computed
  from `session.grid`. Menu/command/persistence plumbing is untouched here.
- `src/swift/app/roll/GridGesture.swift` — gesture strides (:111, :116,
  :131) from `session.grid.snapTicksAt(position)` (position-aware, not
  segment-0).
- `src/swift/app/timeline/RulerMenuPresenter.swift` — `snapped(_:)`
  (:327-332) becomes `session.grid.snapTick(position, camera:)` (fork tie
  rule).
- `src/checks/editcheck/EventViewsRemapBucketsParity.swift` — port the
  `viewbuckets_grid.cpp` rows per the mapping table below.
- `src/checks/rollcheck/EditorGridCameraChecks.swift` — tie-resolution
  and musical(16)-lattice predicates for the `proof.camera.txt` rows
  (shared fixtures in `camera_grid.swift` stay helpers).
- `src/swift/app/roll/NoteCommands.swift` — only where it re-derives grid
  strides for split/join; read them from the session grid.

# Prerequisites

After task 32 (owns `GridGeometry.swift`, `PianoGrid.swift`,
`GridScene.swift` typography edits) and after task 33 (owns
`VelocitySceneValues.swift`, `VoiceChangesProjection.swift`,
`AutomationOverlayPublication.swift`, `RulerMenuPresenter.swift`,
`ApplicationSession.swift`). Task-34b depends on this brief. Task 35 (roll
pointer parity) sequences after this brief and task-34b: its
`GridGesture.swift` pendingDraw transition (:101-113) sits beside the
:111/:116 stride edits here, and its `rollcheck/selection.swift`
threshold predicate builds on the :501-516 pick re-expression in 34b
(sequencing agreed with Brief35RollInput).

# Interface contract

- `GridSelection` menu-id codec exactly forks grid.h:35-42: -1 Auto, 0
  Clock, `denominator` Musical. The ladder, canonicalization, narrow/widen/
  toggleFeel/setState/setTicksPerClock transitions reproduce grid.cpp:24-142
  bit-for-bit for the same `(axis, clock, thresholds)` inputs, including
  the toggleFeel nearest-spacing walk and the `setState` "canonicalize
  against the new feel, never the live one" rule.
- Every spacing accessor returns ≥ 1 (clock-floored). `snapTick(…, fine:)`
  and Clock use the absolute zero-anchored lattice with ties up; Auto and
  Musical use segment-anchored lattices with ties down; all clamp at 0 and
  `TimeDefaults.maxTick`. `nextSubdivisionTickAfter` clamps Auto/Musical at
  the next signature seam; `nextSnapTickAfter` never does unless the
  selection is Clock or `fine`.
- Painted sub-grid enumeration emits only sub-beat positions (never beat or
  bar lines), only while the stride is finer than a beat and `drawsSubGridIn`
  holds, with level 1/2/3 from the fork `subGridLevel` triplet-aware rule.
- DocumentSession owns the per-tab grid value: default Auto/Straight, reset
  on open, clock floor from the document. All surfaces (roll, ruler menu
  math, automation, velocity, voice changes, pitch bend snap input) read the
  same value; no surface keeps a private copy of the selection.
- No pixel constants: zoom thresholds in checks are expressed through
  `GridMetrics` values (`autoGridMinCell`, `detailMinPxPerBeat`,
  `gridLineStroke`) exactly like the fork's `layout::fontPx` multiples; no
  code comments; no C++.

# Implementation steps

1. Write the failing core predicates first
   (`EventViewsRemapBucketsParity.swift` ladder/seam/density rows;
   `EditorGridCameraChecks.swift` tie rows); record RED.
2. Add `GridFeel`/`GridSelection`/`RollGrid` to `GridGeometry.swift` with
   the full transition + query API; port `forEachSubdivision` to the
   `forEachSubGridLine` contract.
3. Add `DocumentSession.grid` + `gridClockTicks` + open-time reset.
4. Rewire the consumers listed above (roll scene, three drawer
   publications, automation projection, gestures, ruler menu math, command
   dispatch, published scalars).
5. Delete the invented math from `GridGeometry.swift` (snapTicks halving/
   doubling, absolute-only lattices, straight-only visibleGridTicks);
   `snapScale`/`tripletGrid` fields remain solely for task-34b's menu
   cutover and nothing production-side reads them anymore.
6. Run the lanes below; report GREEN with predicate messages and file:line.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose`
  (`EventViewsRemapBucketsParity` suite 6 via EventChecks.swift;
  `runEditorGridCameraChecks`)
- `deno task verify:qml-roll --verbose` (GridScene painted grid)
- `deno task verify:qml --verbose` (drawer painted grids)
- `deno task verify:bridge`
- Expected RED until task-34b: `deno task verify:shell --filter
  shell-grid-menu` (still pins the nine snapScale rows) — not an acceptance
  lane for this brief.

# Visual parity

Counterpart: fork `grid.cpp` math + `timelinequickscene.cpp:648-663`,
`timerulerquick.cpp:170-187` (sub-grid walk), `detail.h:101-123`. No
dedicated reference capture exists for grid density; the acceptance
evidence is the core predicates plus the roll/drawer lanes above. Zoom the
mounted roll at default Auto/Straight and confirm bar/beat/sub-beat
densities unchanged from today's adaptive behavior (regression guard);
triplet feel and fixed denominations are new visible behavior proven by the
core predicates.

# Task-specific constraints

- Implementers never edit proof ledgers; the controller delegates
  `proof.viewbuckets_grid.txt` and `proof.camera.txt` to the ledger agent
  with the mapping below.
- Fork assertion → Swift predicate mapping (ledger agent: A rows map to
  these `cppID`/message anchors in `EventViewsRemapBucketsParity.swift`
  unless noted):
  - viewbuckets A020 (`gridTicksAt(0)`) + A021 (`snapTicksAt(0)`) → one
    loop over the seven `snapLadder` rows in `gridSnapLadder(_:)`, messages
    `"snap ladder <row>: grid ticks"` / `"snap ladder <row>: snap ticks"`
    with `<row>` the fork row name (`straight below`, …).
  - A024 (`lines > 0`) / A025 (all lines snappable) → `gridLinesSnappable
    (_:)` per fixture shape, messages `"grid lines exist"` /
    `"every drawn grid line is snappable"`.
  - A030-A035 → `clockLatticeSeamSnap(_:)` messages
    `"clock snap down crosses the seam"`, `"clock snap up crosses the
    seam"`, `"next snap after 35"`, `"next snap after 36 skips the seam"`,
    `"next subdivision after 36 skips the seam"`, `"next snap after 37"`.
  - A036/A037 → same function, messages `"clock sub-grid line count"` /
    `"clock sub-grid ticks are the absolute lattice"`.
  - A039/A040 → `fixedGridPaintDensityGuard(_:)` messages `"fixed eighth
    sub-grid paints at twice the cell"` / `"fixed eighth sub-grid
    suppresses at the cell"`; A041-A043 `"fixed snap ignores paint
    suppression"` ×3; A044/A045 `"clock sub-grid paints at six cells"` /
    `"clock sub-grid suppresses at two cells"`; A046 `"clock snap ignores
    paint suppression"`.
  - A019/A022/A023/A026-A029/A038/A047/A048 are fixture/open scaffolding
    or already-covered seam rows (A027-A029 stay S011-S013); map them to
    the same functions' setup expects, not new rows.
  - proof.camera.txt fractional-lattice rows → `EditorGridCameraChecks.swift`
    messages `"segment lattice stride is positive"`,
    `"subdivision restarts at the segment anchor"`,
    `"auto tie rounds down"`, `"tie down is floor"`, `"tie up is ceil"`,
    `"coarse lattice divides the beat"`.
- Keep `TimelineSnapPolicy` untouched (it is the fork fine path, ledger
  `proof.viewbuckets_grid.txt` already cites it).
