# Context

Task 52 — scrollbar live drag/paging laws. Close the scrollbar family (136 open rows)
on the mounted surface and delete its four ledgers. The surface already exists:
`TimelineScrollbar` QML is line-identical to fork `fceecd88` except the C++ base type
(`TimelineGestureScrollbar` → `Item` + plain `gestureActive`, sole diff of
`src/ui/songview/quick/TimelineScrollbar.qml`), and both tracks are mounted at
`EditorSurface.qml:708-763`. Every GAP reason saying "unmounted in EditorSurface.qml"
is stale preamble. This task is proof completion + ledger closure, not a rebuild.

1. **Census (verified this freeze)**: drag 47 rows (42 GAP, 1 PARTIAL, 4 MATCHED),
   geometry 41 (36 GAP, 1 PARTIAL, 4 MATCHED), input 35 (30 GAP, 1 PARTIAL, 4
   MATCHED), tst 44 (25 GAP, 16 RETIRED, 3 MATCHED) = 136 open. MATCHED stay
   untouched: drag A003/A007/A009/A024, geometry A014/A015/A020/A021, input
   A009/A011/A026/A028, tst A015/A017/A018.
2. **Fork laws** (`git show fceecd88:src/checks/scrollbar/…`; helpers in
   `control.cpp`; tolerance 0.01; `beginDrag` = press thumb center, move
   `startDragDistance+1`, then +1 px):
   - drag: clamp/reverse both axes (:88-111); mid-drag zoom rebase where one track
     pixel scrolls exactly `freshSpan/freshTravel` (:123-141); vertical resize
     rebase, 30 px exact (:151-169); scaleFold collapses span→0, scrollY→0, thumb
     fills track, drag no-ops, unfold restores and drags exactly (:180-213);
     released thumb repositions proportionally after an external camera set, and
     release drops the grab (:235-250).
   - geometry: canonical rects (:49-75) — h.track left = splitX, right = surface
     edge, height = `layout::space(Two)`, top = other-events bottom; v.track left =
     roll-band right, width = `space(Two)`, top/height = roll plot; plot right <
     v.track left; rendered item rects equal the canonical rects; drawer-section
     resize re-flows the roll band and v.track (:99-108); event-list visibility
     hides only the roll track while time scrolling continues (:116-131).
   - input: paging presses the midpoint of the exposed region beyond the thumb and
     pages exactly one viewport toward the click; other axis never moves (:69-112);
     wheel matrix — pixel one-to-one as DIPs (3×(0,-10)→+30), natural-sign inversion
     rides the delivered deltas (fork `Q_UNUSED(inverted)`,
     `timelinequickview.cpp:561-575`), pixel beats angle, notch =
     `wheelScrollLines` per 120 (fractional 50 → notch·50/120), the bar's own axis
     wins with the other as fallback, diagonal pixels follow the dominant axis,
     touchpad deltas follow the same law and phases never reach the scroll API
     (:166-230); keyboard focus + single step + Home/End park the thumb flush at
     the ends; horizontal minimum is negative pre-roll (:265-322).
   - tst: standalone signed-range control (min −80/max 80/page 20/track 240): thumb
     = `page/(max−min+page)·track`, mid-drag model re-range keeps value and resizes
     the thumb (span 260), one-pixel law, overshoot clamps, released model set
     repositions the thumb (:304-344); automation scrollbar absent end-to-end and
     the Tempo parameter stays clickable on a resized automation section (:283-297).
3. **Swift current state**: mounts already pin the canonical geometry — `x:
   root.timelineSplitX` (:712), `width: root.width - x` (:714), breadth =
   `headersModel.scrollbarWidth` (:42) = `px(0.5)`
   (`TrackHeadersGeometry.swift:95`) = fork `SPACE_MULTIPLIERS[3]=0.5`
   (`layout.cpp:34`); v.track `x: rollStack.x + rollStack.width`, `y: rollPlot.y`,
   `height: rollPlot.height` (:740-743); `externalVisible: !root.showEvents`
   (:755); `TimelineScrollbar.wheelDips` (`TimelineScrollbar.swift:50-59`) mirrors
   fork `scrollbarWheelDips`, and `PianoGrid.scroll*ByWheel` (:391-407) drops
   `inverted` exactly as the fork ignores it — no production law gap identified at
   freeze. Existing checks: `ScrollbarChecks.swift` (6 predicates, rides
   `runProjectSessionSuite` via `SessionChecks.swift:22`) and
   `tst_TimelineScrollbar.qml` (5 tests, roll lane). PARTIAL residuals: exact
   one-pixel displacement (drag A017), drawer-driven resize (geometry A030), full
   wheel matrix (input A017).
4. **Test-API boundary** (Qt docs, `qml-qttest-testcase.html`): QML `mouseWheel`
   synthesizes angle deltas in eighths of a degree only — no `pixelDelta`, no
   `inverted`, no phase control, so angle-only wheel cases close on the mounted
   lane while pixel/precedence/touchpad cases close in swiftcore against
   `wheelDips` + `EditorCamera.scrollByPx/scrollRollBy` (the law the mounted
   handler applies; `EditorSurface.qml:730-733,759-762` forward `event.pixelDelta`
   verbatim, so angle delivery proven mounted plus the pixel law proven in
   swiftcore covers the chain).
5. **Ingresses verified**: fold `grid().setScaleFold(fold:)` (`PianoGrid.swift:299`,
   read-only here); event list `session.songTabs.setSelectedTabEventsVisible(bool)`
   (`SongTabsController.swift:303`, `tst_ShellTabs.qml:1405` precedent); drawer
   section `drawerPresenter.setSectionBodyHeight(kind:height:)`, automation = 0
   (`EditorDrawer.swift:180`, `EditorDrawerTypes.swift:8`); automation tabs
   `automationParameterTab{i}`, tempo tab identified by its `automationTempoTapButton`
   child (`AutomationTabs.qml:38,93`); roll-lane drawer precedent
   `tst_SwiftRollAutomation.qml`.

# Exact write set

- `src/checks/rollqml/tst_TimelineScrollbar.qml` — new test functions (canonical
  layout, exact paging + axis stillness, keyboard thumb-park/preroll/stillness,
  angle wheel matrix, scale-fold journey, external released thumb, event-list
  toggle, drawer resize, standalone signed-range, automation scrollbar absence) and
  one-pixel exactness added to `test_zoomDuringHeldDragRebase`.
- `src/checks/scrollbar/ScrollbarChecks.swift` — wheel-dip matrix block applied
  through `EditorCamera`.
- `src/swift/app/timeline/TimelineScrollbar.swift`*,
  `src/ui/songview/quick/swiftroll/EditorSurface.qml`* — contingent only: no law
  gap found at freeze; edit solely to fix a divergence a new predicate exposes.
  `PianoGrid.swift` and production `TimelineScrollbar.qml` are read-only.
- Ledgers (controller-delegated ledger agent, this task's commit scope): flip then
  delete `src/checks/scrollbar/proof.drag.txt`, `proof.geometry.txt`,
  `proof.input.txt`, `proof.tst_scrollbar.txt`.

No CMake changes (no new files), no `PianoGrid.swift`, no drawer/automation sources.
Sizing exception: one behavior family over 2 check files + ledgers, one
verification-surface set — named for the dispatch table.

# Prerequisites

Task-41b settled (owns uncommitted `EditorSurface.qml`/`PianoGrid.swift` edits; the
sprint gate for dispatching 52). Nothing consumed from 50a; re-snapshot if 41b
moved lines.

# Interface contract

No production interface changes. The predicates are the deliverable; quoted strings
are the ledger anchors (one per fork clause), tolerance 0.01 unless noted, and every
message cited by an S row or PARTIAL reason stays verbatim (drag S001 "drag
overshoots clamp at both time bounds", S002 "drag clamps at the near end"; input S001
"wheel favors pixel then axis angle and retains natural sign", S002 "horizontal
track wheel advances camera time"; function names `test_zoomDuringHeldDragRebase`,
`test_tracksFollowViewportAndCamera`, `test_wheelAndResizeRebase` are cited by
PARTIAL reasons and keep their names).

`tst_TimelineScrollbar.qml` adds, reusing the file's `bar`/`midpoint`/`cameraValue`/
`waitForNative` helpers and the drawer patterns of `tst_SwiftRollAutomation.qml`:
- "the scrollable span straddles the midpoint before dragging" — per axis (drag
  A001/A002, A041/A042).
- "the thumb stays inside its track through clamp, reversal and release" (drag
  A004/A006/A008/A010, A014, A021, A036, A047).
- "one track pixel after the rebase scrolls the fresh span over the thumb travel" —
  after the zoom rebase settles, a one-px move ⇒ camera = rebased +
  `1·freshSpan/freshTravel`; assert `expected < maximum` first (drag A011-A017,
  closes the PARTIAL).
- "folding collapses the roll span and parks the scroll at zero"; "a folded roll
  track fills its thumb and ignores drags"; "unfolding restores the roll span and
  thumb fraction"; "a restored roll thumb drags by the fresh span per track
  distance" (30 px exact) (drag A025-A040, via `setScaleFold`).
- "a released thumb abandons its grab; movement without a press does not scroll"
  (drag A043 behavioral equivalent of the grabber query); "an external camera move
  repositions the released thumb proportionally" — after release,
  `setCameraHScroll(min + span/4)` ⇒ thumb pos = `(value−min)/span·travel` (drag
  A044-A046).
- "the roll and other-events bands publish live geometry"; "the horizontal track
  spans the plot width under the other-events band"; "the vertical track hugs the
  roll band's right edge for its full height"; "the rendered tracks sit exactly on
  their canonical rects" (scene-mapped item rects; the fork's ±1 is integer-
  alignment rounding, not a law); "both tracks stay inside the editor surface"
  (geometry A001-A013, A016-A019, A022-A025; breadth compared to
  `headersModel.scrollbarWidth`).
- "growing a drawer section shrinks the roll band and its vertical track follows" —
  `setSectionBodyHeight(0, current+80)` ⇒ roll-plot height changes, v.track
  y/height re-follow, span changes, thumb in track (geometry A026-A032, closes the
  PARTIAL).
- "showing the event list hides only the roll track"; "the hidden roll track keeps
  the time track scrolling" (settle `min + span/3`); "hiding the event list
  restores the roll track" (geometry A033-A041; the fork's empty-rect accessor maps
  to the mounted `visible` law).
- "the mounted tracks publish the camera's bounds and page" — minimum/maximum/
  pageStep vs `grid()` camera and plot viewport (input A001-A003, A007).
- "a track click beyond the thumb pages exactly one viewport toward the click" —
  fork target formula (exposed-region midpoint), unclamped expectation from
  `pageStart = min + (span−page)/2`, both axes both directions; "paging never
  disturbs the other axis" (input A004-A012).
- "the horizontal track owns a negative pre-roll bound" (`h.minimum < 0`);
  "keyboard scrolling never disturbs the other axis"; "Home parks the thumb flush
  at the near end"; "End parks the thumb flush at the far end" (input A021/A022,
  A027/A029, A030-A035; A025 maps to `control.activeFocus` asserted while driving).
- "rotary notches scroll the wheel-scroll-lines step" (±120 and fractional ±50 via
  `Qt.styleHints.wheelScrollLines`); "a horizontal track scrolls its own axis from
  either wheel axis" (x-only and y-only angle on h.track; x-only on v.track);
  "wheel keeps the other axis still" (input A013-A020 angle rows).
- "the standalone thumb sizes by the page fraction of its model span"; "a standalone
  drag tracks the model value"; "a mid-drag model re-range keeps the value and
  resizes the thumb"; "one track pixel after the re-range moves the model value by
  the fresh span over travel"; "overshoot clamps the model value and parks the
  thumb at the far end"; "a released model value change repositions the thumb
  proportionally" (tst A032-A044; inline `createTemporaryObject` fixture mirroring
  the fork's `kStandaloneScrollbarQml`: min −80, max 80, page 20, track 240×20,
  minimumThumbLength 24, re-range to max 180/page 60).
- "the automation drawer mounts no scrollbar track or thumb" (findChild nulls for
  `drawerAutomationScrollBar`/`drawerAutomationScrollThumb` after the automation
  page loads); "a resized automation section still activates its Tempo parameter"
  (click the tempo tab after `setSectionBodyHeight(0, +120)`; presenter
  `activeParameter` becomes tempo); "the activated tempo lane renders a live plot"
  (`automationPlot` positive size + non-empty scene content) (tst A025-A028).

`ScrollbarChecks.swift` adds `scrollbar/TimelineScrollbar::wheelDipMatrix`, driving
`wheelDips` + `EditorCamera.scrollByPx/scrollRollBy` with `wheelScrollLines = 3`:
3×(0,−10) px → +30; (0,−10) → +10 (inversion rides the deltas — same input, same
result); pixel (0,−10) with angle (0,120) → +10; angle (0,120) → −3; angle (0,50) →
−3·50/120; px (10,0) horizontal → −10; angle (120,0) horizontal → −3; px (20,−10)
horizontal → −20; touchpad px (8,0) horizontal → −8 and (0,−6) vertical → +6 (input
A013-A020 pixel/precedence/touchpad rows).

# Implementation steps

1. Add the new predicates against the mounted surface; they are expected to pass
   immediately (proof, not fix). A failing predicate exposes a real production
   divergence — fix it in the contingent files, record RED→GREEN for that fix only.
2. Extend `test_zoomDuringHeldDragRebase` with the one-pixel exact move; tighten
   the resize expectation in `test_wheelAndResizeRebase` to 0.01 via
   `fuzzyCompare` (message verbatim); add the remaining QML functions and the
   `wheelDipMatrix` block per the contract.
3. Run the lanes below; the evidence JSONs (`build/proof-evidence/
   swiftroll-window.json`, `swiftcore-projectsession.json`) feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:qml-roll --verbose` — all new + existing scrollbar predicates
  and roll-lane regressions (`tst_SwiftRoll*`, `tst_TimelinePan`).
- `deno task verify --filter swiftcore-projectsession --verbose` — the six existing
  scrollbar predicates plus `wheelDipMatrix`, with session-suite regressions.
- Runtime prerequisite: the roll lane's usual offscreen-capable Qt windowing; no
  native audio.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no pixel
  constants in production (standalone-fixture numbers in the QML check are
  check-side, as in the fork's own block).
- `mouseWheel` deltas are eighths of a degree; never claim pixel-delta delivery
  from QML (Context ¶4).
- Ledger mapping (agent; re-verify at freeze against the evidence JSONs):
  - drag: A001/A002/A041/A042 → midpoint anchor; A004/A006/A008/A010 → within-track
    anchor; A011-A016 → zoom-rebase anchors; A017 → one-pixel anchor; A018-A023 →
    the existing resize-rebase messages (0.01-tight); A025-A028/A029-A033/
    A034-A037/A038-A040 → the four fold anchors; A043 → released-grab anchor;
    A044-A047 → external-camera anchor (+ within-track anchor).
  - geometry: A001/A002 → bands anchor; A003-A008/A009-A013/A016-A019/A022-A025 →
    the four canonical-rect anchors + containment anchor; A026-A032 → drawer-resize
    anchor; A033-A041 → the three event-list anchors (A034/A036/A040 map to the
    `visible`-law anchors — mounted item visibility is the direct observation).
  - input: A001-A003/A007 → bounds-and-page anchor; A004-A008 → exact-paging
    anchor; A010/A012 → paging axis-stillness anchor; A013-A017/A019 →
    `wheelDipMatrix` expects + mounted angle anchors per case; A018/A020 → mounted
    "wheel keeps the other axis still"; A021/A022 → preroll/settle anchors;
    A023-A026/A028/A029 → existing keyboard anchors + the activeFocus observation;
    A027/A029 → keyboard axis-stillness anchor; A030-A032/A033-A035 → thumb-park
    anchors.
  - tst: A001/A003/A004/A005/A006/A020/A021 → `RETIRED-REPRESENTATION` (pin the
    native fixture's `LoadedSong`/`SongTab`/bank-lease/band-focus construction and
    `QGuiApplication` focus-object identity; the roll lane stages its own fixture
    via `RollQmlBootstrap` — same obligation, different mechanism); A016 → the
    existing "both rendered scroll tracks have a thumb and travel"; A025/A026 →
    automation-absent anchor; A027/A028 → tempo anchors; A032-A044 → the six
    standalone anchors.
  - After every row is MATCHED/RETIRED, delete all four proof files in this task's
    final commit (fork C++ check sources are already gone — headers record
    `Deleted in:` 67544720 and 31ea635f; per verification.md the ledger agent may
    delete its assigned completed files).
- MATCHED rows without visible mapping lines (e.g. drag A003) are superseded by the
  deletion; do not run a repair pass first.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed` (pre-deletion state shows the four ledgers
   fully closed), then confirm deletion: `deno task proof sites --area scrollbar`
   reports no ledger files.
2. Visual/native smoke (desktop): drag both thumbs to the clamps and back; zoom
   mid-drag and continue one pixel; fold/unfold the roll scale; toggle Event List
   (only the roll scrollbar disappears, time scrolling continues); page-click by
   exactly one viewport; notch-wheel both tracks; Home/End park the thumbs; grow
   the automation drawer section — the roll track shrinks with the plot.
