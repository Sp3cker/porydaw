# Task 90 brief — roll camera lattice and persistence laws through remap and view changes

# Context

Own the mounted roll's camera surface: the visible-window tick conversion,
the fractional lattice walk with its segment/seam laws, the fallback and
signature-bound grid output, and the camera's persistence through domain,
viewport and track-remap changes. The camera machinery exists
(`EditorCamera`, content-space scene, `handleDocumentChange` re-domain); the
gap is executing predicates for its output laws and the retirement of the
native raster/signal-order representations this surface supersedes. This is
not the ruler/pencil/note-command/selection surface (task 86), not keyboard
(selectionkey, task 87), not the close/reopen camera ingress (task 84), and
not shell routing or workspace persistence (tasks 83/84).

1. **Verified census: 55 selected rows of 132 open** across three rollcheck
   ledgers, queried at HEAD `e334b318ecf391e3d4fac512c4a613303aff01e3`:
   - `src/checks/rollcheck/static/proof.camera.txt` — 52 open (5 GAP +
     47 PARTIAL), 29 selected: MATCHED-destined A011, A013, A015, A018,
     A019, A022, A025, A029, A039, A040, A049, A091, A099, A100;
     RETIRED-destined A001–A010, A012, A014, A017, A023, A086.
   - `src/checks/rollcheck/static/proof.geometry.txt` — 44 open (26 GAP +
     18 PARTIAL), 14 selected, all MATCHED-destined: A009–A017, A044, A045,
     A046, A047, A050.
   - `src/checks/rollcheck/proof.remap.txt` — 36 open (19 GAP + 17 PARTIAL),
     12 selected, all RETIRED-destined: A004, A007, A010, A017, A020, A023,
     A030, A033, A036, A042, A046, A050.
   Total: 14 GAP + 41 PARTIAL. Left open (77): camera A032, A033, A041,
   A042, A047, A048, A080, A083–A085, A092–A098, A101–A105; geometry A002–
   A004, A006–A008, A018–A030, A033, A034, A038, A040, A041, A044's raster
   siblings A048, A049, A051–A054; remap's 17 cosmetic PARTIALs and the 7
   raw-promotion GAPs A061–A067.
2. **Fork laws**, read at `fceecd88`:
   - `src/checks/rollcheck/static/camera.cpp:65-91`
     (`tickRangeRejectsInvalidBounds`) over `songview::detail::tickRange`
     (`src/ui/songview/detail.cpp:241-250`): negative content clamps to tick
     0 (A011), fractional content converts to the tick below it (A013), and
     the largest double below the `kNoTick` ceiling converts exactly (A015).
   - `:94-182` (`tickRangeWalksFractionalLattice`): the fractional window's
     first segment starts at or before 96 and its next boundary reaches past
     289 (A018, A019); the walk over 96.75..289.25 emits exactly the
     expected lattice (A022); the drawn coarse stride stays below the beat
     width (A025) and the segment leaves room for two lattice steps (A029);
     the 5/8 signature seam at 102 starts its segment there and ends the
     pre-seam segment at 102 (A039, A040); deleting the signature restores
     the plain segment grid (A049).
   - `:364-435` (`cameraRangeAndPreRollRaster`): `goToStart` leaves the edit
     cursor at tick 0 (A091); from the bound home (scrollPx 0) an 8-pixel
     wheel pan leaves scrollX at −8 (A099); applying a view state with
     scrollPx −pad/2 reads back exactly (A100).
   - `src/checks/rollcheck/static/geometry.cpp:141-168` (`fallbackGrid`): the
     unsignatured grid publishes exactly 16 lines over 0..96 at whole-beat
     positions, every fourth a bar, with bar numbers index/4+1 and beat
     numbers index%4+1, and its tick-0 segment starts at 0, ends at the
     `kNoTick` sentinel with beatTicks 24 and beatsPerBar 4 (A009–A017).
   - `:335+` (`signatureGroupingKeepsBeatsAndMovesBars`): binding 3/4 makes
     the tick-0 segment start 0, next the sentinel, beatTicks 24,
     beatsPerBar 3 (A044–A047) while the view's beat content positions stay
     fixed within 1e-6 (A050).
   - `src/checks/rollcheck/remap.cpp:165-473`: every structural journey
     (move/insert/duplicate/delete/metadata) guards that the remap is
     applied before the document publication — expressed in the fork as a
     two-signal emission order (`tracksRemapped` then `documentChanged`)
     with a `QFAIL` when reversed (A004, A007, A010, A017, A020, A023,
     A030, A033, A036, A042, A046, A050).
3. **Current Swift/QML**, verified at `e334b318`:
   - `TimeDefaults.tick(from:)` (`src/swift/core/MusicTypes.swift:120-124`)
     is the surviving double→tick ingress: ≤0 → 0, ≥ `Double(noTick)` →
     `maxTick`, else truncating — the A011/A013/A015 laws.
   - `GridScene+Rebuild.visibleTicks` (`src/swift/app/roll/GridScene+Rebuild.
     swift:64-72`) resolves the camera window into integral Tick bounds
     with `max(0, …)` clamping and a deliberate `ceil(+1)` right edge; the
     lattice walk is `RollGrid.forEachSubdivision(from:to:camera:)`
     (`src/swift/app/timeline/GridGeometry.swift:309-339`) over
     `TimeAxis.segmentAt`. The fork's degenerate double-window arithmetic
     (NaN/±∞/reversed/zero-width/`0x1p64`) has no callable Swift ingress:
     the camera clamps scroll (`EditorCamera` reconcile) and the walk takes
     integral bounds.
   - `src/swift/app/timeline/EditorCamera.swift:100-260` is the camera value
     type: `updateTimeDomain(ticksPerBeat:lengthTicks:)` at `:250`,
     `updateViewport` at `:256`, `contentX(tick:)`/`tickAtContentX` at
     `:231-232`, `leadPad` at `:222`. `DocumentSession+Internals.
     handleDocumentChange` (`:107-196`) reconciles selection/mute/solo
     through `change.trackRemap`, rebuilds the timeline, and re-domains the
     camera in the same coalesced `SessionChange(trackRemap:)` publication
     (`:41-68`, `composeTrackRemaps` at `:83`) — the successor of the fork's
     two-signal order, already asserted by S003/S025 in
     `src/checks/rollcheck/remap.swift`.
   - `src/checks/rollcheck/EditorGridCameraChecks.swift` runs the lattice
     walks (`checkFractionalGridLattice`, S068–S074) over the real session
     axis; `src/checks/rollcheck/static/camera.swift`
     (`runEditorCameraChecks`) owns camera projection/wheel contracts
     (S003, S005/S006, S063); `src/checks/rollcheck/static/geometry.swift`
     (`runGeometryChecks`) owns the bind laws (S062, S064, S066). All three
     are registered in the projectsession suite
     (`src/checks/workspace/SessionChecks.swift:21,61,62`).
   - `src/checks/rollqml/tst_SwiftRollWindowing.qml` hosts the production
     `SwiftRollOverlay` composition with a real staged Route 101 session and
     already exercises ready-roll wheel zoom (`test_readyRollWheelZoom`).
     Its `functions` evidence lands in
     `build/proof-evidence/swiftroll-window.json`. The mounted remap
     ingresses exist on this surface: header drag-reorder
     (`src/swift/app/headers/TrackHeadersInput.swift:197` →
     `document.moveTrack`) and the header menu's duplicate/delete
     (`src/swift/app/headers/TrackHeaders.swift:351-368`).

# Exact write set

- `src/checks/rollcheck/EditorGridCameraChecks.swift`
- `src/checks/rollcheck/static/camera.swift`
- `src/checks/rollcheck/static/geometry.swift`
- `src/checks/rollqml/tst_SwiftRollWindowing.qml`
- `src/checks/rollcheck/static/proof.camera.txt` — only the 29 selected rows
  and their predicates.
- `src/checks/rollcheck/static/proof.geometry.txt` — only the 14 selected
  rows and their predicates.
- `src/checks/rollcheck/proof.remap.txt` — only the 12 selected rows and
  their predicates.
- `src/swift/app/timeline/EditorCamera.swift` — selected-law repair only.
- `src/swift/app/DocumentSession+Internals.swift` — selected remap/publication
  repair only. Both are conditional on executed divergence; the clamp, walk
  and re-domain machinery already exists.

Production edits are limited to a demonstrated selected-law mismatch.
No write-set file overlaps 79–82; **rebase after 82 lands** when re-reading
`GridScene+Rebuild.swift`'s integral window boundary. `tst_TimelinePan.qml`
remains 82's, and automation, velocity, router and ShellWindow stay out.
`DocumentWorkspace.swift`, `ShellPresenter.swift`, `ApplicationSession.
swift`, `EditorViewStateCodec.swift`, `session_view_state*.swift` and
`tst_ShellTabs.qml`/`tst_ShellWindow.qml` are outside the write set: the
close/reopen and in-place-reload camera ingress belongs to task 84, and
`EditorViewState` covers chrome and drawer lanes, never camera (oracle
distinction: `SongView::ViewState` owns camera/cursor/grid/track/events).
Do not re-pin camera state into the `EditorViewStateCodec` and do not
"fix" stale ledger prose by moving camera fields there.

# Prerequisites

Sprint-3 §8 split/repair and the 77a/77b content-space camera work are
settled. Consumes only existing `EditorCamera`, `RollGrid`/`TimeAxis`,
`DocumentSession` re-domain and header-input interfaces. No dependency on
tasks 79–88 and no new interface consumed by them. Group A is file-disjoint.

# Interface contract

- Preserve every existing camera and grid API: `EditorCamera.
  updateTimeDomain/updateViewport/updateLimits`, `contentX(tick:)`,
  `tickAtContentX`, `snapshot`, `mutateCamera`, `RollGrid.
  forEachSubdivision(from:to:camera:)`, `TimeAxis.segmentAt`,
  `forEachGridLine`, `TimeDefaults.tick(from:)`. No new bridge API, no new
  camera persistence store, no second view-state codec.
- `static/camera.swift` gains: the three `TimeDefaults.tick(from:)` clamp
  laws (negative→0, fractional→tick below, largest-below-ceiling exact);
  the bound-home 8-pixel wheel pan reaching exactly −8 through the existing
  `checkGridCameraWheel` fixture shape; and the fractional scroll
  read-back exactness across a `updateTimeDomain` call.
- `EditorGridCameraChecks.swift` gains, over the real session axis and grid:
  the segment bracket laws at 96 (start ≤ 96, next ≥ 289), the fractional
  window walk equality against an independently computed expected lattice,
  the coarse-stride-below-beat and two-steps-below-segment-end bounds, the
  5/8 seam segment boundaries, and a real signature-delete journey
  (document edit, not a rebuilt axis) restoring the plain segment grid.
- `static/geometry.swift` gains, over a real unsignatured document and a
  real 3/4 bind: the sixteen-line fallback publication with positions, bar
  flags, bar and beat numbers; the fallback segment defaults (start 0, next
  `noTick`, beatTicks 24, beatsPerBar 4); the 3/4-bound segment defaults;
  and beat content positions preserved within 1e-6 across the bind.
- `tst_SwiftRollWindowing.qml` gains mounted journeys (no ledger rows; smoke
  evidence in the lane's function list): wheel-pan/zoom, then a header
  drag-reorder and a header-menu delete/duplicate, asserting
  `cameraScrollX`/zoom survive each remap publication and re-clamp when the
  timeline length shrinks; and a viewport resize asserting the fractional
  scroll persists within bounds.
- Dispositions: 28 rows MATCHED with one new literal message anchor per
  clause (distinct literals per law: each clamp, each bracket, the walk
  equality, each stride bound, each seam boundary, the signature-removal
  restore, the goToStart cursor, the bound-home wheel pan, the scroll
  read-back, each fallback line/number/segment default, each 3/4 segment
  default, the beat-position preservation). 27 rows retire:
  - camera A001–A010, A012, A014, A023 — the deleted double
    `tickRange(double, double)` ingress's degenerate-input arithmetic
    (`camera.cpp:65-91`, `detail.cpp:241-250`), superseded by integral walk
    bounds + `TimeDefaults.tick(from:)` + camera scroll clamping; the
    end-truncation rows A012/A014 additionally differ by the successor's
    deliberate `ceil(+1)` right-edge coverage
    (`GridScene+Rebuild.swift:64-72`).
  - camera A017, A086 — native `CameraFixture` window/rendering
    obligations whose convertible clauses are the selected sibling laws.
  - remap A004, A007, A010, A017, A020, A023, A030, A033, A036, A042,
    A046, A050 — the fork's `tracksRemapped`-then-`documentChanged`
    two-signal emission order, superseded by the single coalesced
    `SessionChange(trackRemap:)` publication
    (`DocumentSession+Internals.swift:41-68`) already executed by S003/S025.
  No check re-creates a deleted ingress, a native raster or a signal order.
- Preserve every existing message verbatim, including the S046–S074 camera
  and lattice literals and the remap/geometry messages; do not relabel an
  existing stride or bind predicate as new seam evidence.

# Implementation steps

1. Add clamp, bracket, walk, stride, seam, fallback and bind predicates before
   any production repair. The controller executes after the group settles;
   report honestly green existing behavior, never manufacture a RED.
2. Drive the seam and signature-removal journeys through the real document
   API (set/delete time signature) so the axis rebuild is the production
   path, never a hand-built `TimeAxis`.
3. Add the mounted remap/resize camera journeys to
   `tst_SwiftRollWindowing.qml` using the existing bootstrap/mount helpers
   and the production header reorder/menu ingresses; read camera state
   through the mounted grid's published fields, not a new probe.
4. Fix only demonstrated divergences in `EditorCamera.swift` or
   `DocumentSession+Internals.swift`; any workaround stops for user
   approval. Run the acceptance lanes after the write group settles; attach
   only the executed anchors to the selected rows in the same surface
   change, including the 27 retirements.

# Acceptance predicate

Controller-run on the settled built tree, each invocation capped at 180 s:

- `deno task verify --filter swiftcore-projectsession --verbose` — clamp,
  lattice, seam, fallback, bind, wheel and scroll-persistence predicates;
  `build/proof-evidence/swiftcore-projectsession.json`.
- `PORYDAW_ROLL_QML_SUITE=tst_SwiftRollWindowing.qml deno task verify:qml-roll --verbose`
  — only the mounted SwiftRollWindowing suite, including the remap/resize
  camera journeys and existing windowing regressions;
  `build/proof-evidence/swiftroll-window.json`.

Registration is unchanged: `runEditorCameraChecks`,
`runEditorGridCameraChecks`, `runGeometryChecks` at
`src/checks/workspace/SessionChecks.swift:21,61,62` and the swiftcore suite
entry `src/checks/checkcatalog.cpp:125`; the suite selector is the existing
harness feature at `src/checks/rollqml/RollQmlTests.swift:25-36,100-126`.
Evidence writer: `tools/run_checks.ts:426-434`. The first lane does not
prove mounted camera survival; the second is required even if every Swift
predicate passes. Offscreen QML is real mounted behavior, not proof of
physical-screen DPR; report that visual limit accurately.

# Task-specific constraints

Incorporate **sprint-3 §8 Wave constraints and §9 policy**: Swift 6.4 idioms,
borrowed/fixed-size storage where appropriate, no hot-path allocations or
repeated font measurement, two-line comments, base-font sizing, WCAG AA via
GridPalette. Keep one window dispatcher; no synthetic forwarding, focus
memory or bare Space capture in chrome. One anchored predicate per fork clause,
existing messages verbatim, real fixtures, no test seams, no `Qt.callLater`
coalescing or idempotence guards. Workarounds need user approval. Deferred
menus, parked areas and savecore A016–A026 stay out. No new C++.

This is not permission for a camera refactor, a view-state persistence
redesign, or a sweep of unselected rollcheck rows. The raster-probe rows
(camera A093–A098, geometry A020–A030, A033, A034, A038, A040, A041,
A051–A054) stay open until a task owns their painted surface; retiring them
here without selected sibling behavior would be an unanchored sweep. Camera
A102–A105 (double-click scratch draw) are not selected by task 86 and remain
for a later draw surface. Remap A061–A067 need raw-event conductor promotion,
a separate production feature. The 17 cosmetic remap PARTIALs need view-state
preservation during remap; neither task 83's shared drawer nor task 84's tab
lifecycle proves that transition. Ledgers accompany executing surface work.

# Controller verification

After both lanes have fresh evidence, run `deno task proof check --executed`.
Then run, separately:

- `deno task proof sites src/checks/rollcheck/static/proof.camera.txt --status GAP`
- `deno task proof sites src/checks/rollcheck/static/proof.camera.txt --status PARTIAL`
- `deno task proof sites src/checks/rollcheck/static/proof.geometry.txt --status GAP`
- `deno task proof sites src/checks/rollcheck/static/proof.geometry.txt --status PARTIAL`
- `deno task proof sites src/checks/rollcheck/proof.remap.txt --status GAP`
- `deno task proof sites src/checks/rollcheck/proof.remap.txt --status PARTIAL`

Exactly the 55 selected rows are expected to leave GAP/PARTIAL (28 MATCHED,
27 RETIRED-REPRESENTATION); 77 stay open with the reasons above. Confirm
each walk-equality clause compares against an independently computed
expected lattice (never the production walker's own output), that the seam
journeys ran through real document signature edits, and that the mounted
remap/resize journeys appear in `swiftroll-window.json`'s function list. No
ledger is deleted.
