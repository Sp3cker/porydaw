# Context

Task 66 — track-header tooltips + mutation/menu proof. Close the trackheaders family's
provable rows on the already-mounted band (`TrackHeaderBand.qml` at
`EditorSurface.qml:238-250`), retire its native-harness representation rows, absorb
proof.keyboard.txt A022/A023 that task 53 left open ("A022/A023 (header records guard)
stay open for task-66's headers surface", task-53-brief.md:256-259), and delete the three
fully closable ledgers. Proof completion + ledger closure, not a rebuild — but three
distinct freeze-time discoveries reshape the work:

1. **Census (verified this freeze)**: mutations 45 open (8 GAP, 37 PARTIAL), menu 18
   (10 GAP, 8 PARTIAL), input 11 (10 GAP, 1 PARTIAL), raster 10 (all PARTIAL),
   tst_trackactivitymeter 30 (1 GAP, 29 PARTIAL) = 113 open; plus keyboard A022/A023.
   All five ledgers pin Reference revision `f3069ef6` (SHA-256 prefixes verified:
   10de3d24, 33aaa04e, 86a016fc, b1617fff, d673e4f7); keyboard pins `a1244957`. Fork
   C++ check sources are deleted (`Deleted in: 67544720`); read originals via
   `git show f3069ef6:src/checks/trackheaders/<name>.cpp`.
2. **Stale-reason hazard, twice**:
   - The tooltip GAP reasons ("Feature not yet ported…") are wrong: the fork law
     `hoveringHeadersDoesNotCreateTooltip` (trackheaderinput.cpp:335-345) is a NEGATIVE
     law — hover at the title point resolves the row, the move is accepted, and NO
     `timelineTrackHeaderToolTip` item exists. The mounted band already has no tooltip;
     a drawer-lane twin already executes (tst_EditorDrawer.qml, committed 5ea213cb).
     Task 66 adds the roll-lane twin and flips the rows; no feature is built.
   - "Over-budget dimming residual" (sprint line) is already closed: budget-styling
     predicates execute at `TrackHeadersChecks.swift:104-145` (landed f7b04f18) and no
     open row cites dimming. Nothing dimming-related remains.
3. **The header→voice-picker journey is genuinely unmounted** — the dominant mutations
   residual (~41 rows). `TrackHeaders.activateAddTrack` fires `onAddTrackRequested`
   (`TrackHeaders.swift:287`) which `DocumentWorkspace` never wires (only
   `onChangeTrackVoiceRequested` is wired, `DocumentWorkspace.swift:120` → QtSignal
   `ApplicationSession.changeTrackVoiceRequested` at :568); no QML listens to that
   signal, and the only `completeTrackHeaderVoiceRequest` callers are checks
   (`tst_EditorDrawer.qml:2702`, `tst_SwiftRollWindowing.qml:284`). The fork's picker
   form lives on in the drawer surface (`drawer/VoicePicker.qml`, mounted only inside
   `VoiceChangesPage.qml:541`). Per the binding ruling (no test-only bridge seams; real
   user paths or presenter-level + PARTIAL mounted), these rows keep a **named
   deferral**: "header→voice-picker mount" (wire both callbacks to a mounted picker
   completing through `completeTrackHeaderVoiceRequest`), recorded in the surviving
   ledgers and the following-sprint backlog. Task 66 does not half-wire the callback
   (a signal into the void is a dead action).

**Fork laws** (`git show f3069ef6:src/checks/trackheaders/…`):
- trackheaderinput.cpp:76-105 — band published canonical viewport-local; band/input
  visible; input width = band − scrollbar width; Repeater count == model rowCount;
  captured band frame non-null with distinct pixels. :122-139 selection click flips the
  row's base-color role and alters the retained raster. :308-333 scroll clamps;
  scrollbar+thumb visible. :335-345 hover law above.
- trackheadermenu.cpp — menu rows receive real clicks; Change-voice closes the menu
  panel before the picker request, no revision change (:198-206); Rename begins
  synchronously after close, editor takes active focus, Escape hides it, name/revision
  unchanged (:242-263); Show-voice reveals the current program without a write and the
  dispatch retains header-band focus (:281-292); Duplicate/Delete run one queued command
  each, copy content, undo restores bytes and row (:305-351); a structural remap after
  open cancels the menu synchronously, focus never rests on the dismissed menu content
  (:372-384); stale queued Delete/Duplicate dropped by the execution-time identity
  check, only the move's write lands (:455-502); outside left/right presses dismiss
  without click-through, band focus restored (:529-555).
- trackheadermutations.cpp — add-row hover/press/cancel guards
  (FocusLost releases the press, revision unchanged; release outside requests nothing;
  the outside point stays inside the input bounds, :269-294); rename-editor rows
  A001/A022/A027 want the mounted editor observed after a discarded rename/transient
  cancellation. The picker journey (:299-434: open, search focus, filter,
  accept-disabled, audition payloads (program,key,velocity = 127,60,112 hold /
  127,60,0 release), dismiss/reopen, accept +1 revision +1 undo, rebuild
  sorted/unique, undo/redo, remap-phase teardown) is the deferred slice.
- tst_trackactivitymeter.cpp — single-track model (rowCount 1 when the document cannot
  add, :139); activity level change republishes exactly the driven row, pixel-identical
  level is silent (:164-200, :318-321); paused fill spans the meter; captured raster
  dimensions equal the device-pixel spans of (bandX, activityWidth) and (rowY,
  meterHeight) at the observed dpr (:236-238); stereo left/right fill heights differ at
  the top and share identity at the bottom; second row's raster is captured, opaque and
  unpainted when undriven (:275-311); dataChanged count/first/last/roles conjuncts are
  Qt-model signal internals.
- trackheaderraster.cpp — every residual reads "The paired Swift predicate does not
  establish the original native QML window/raster observation" while citing executing
  converted-window anchors (S038-S041, S059/S060, S062, S065-S068). Sprint-3 §4
  assigns this ledger's representation sweep to this task.
- rollcheck/keyboard.cpp:166-167 (a1244957) — inside `timelineRulerScope`, after the
  seeded −11 transpose: guard `QVERIFY2(headers, "could not find the Quick track-header
  model")` and `QVERIFY2(recordsMatchTimeline(headers, timeline, canAddTrack), …)` —
  rows follow used timeline tracks in order, plus one trailing add row iff canAddTrack
  (oracle `trackheaderoracles.h:37-63`).

**Swift current state — no production law gap identified at freeze**: hover/hit/press,
five-action menu (`activateHeaderMenuAction` 1-5 with target-identity recheck,
`TrackHeaders.swift:351-368`), rename, reorder, meter publication, budget dimming and
reconciliation (`tst_trackheadermodel.swift:119,137`) all exist. Checks executing:
headers suites ride `swiftcore-projectsession` (`SessionChecks.swift:87-88`); presenter
picker-journey predicates S030-S057/S012-S018/S036-S039; meter S001-S027; the roll-lane
`tst_SwiftRollTrackHeaders.qml` (11 tests, `swiftroll-window`); committed drawer-lane
header tests (raster S031-S041/S059-S060/S062-S068, tooltip twin).

# Exact write set

- `src/checks/rollqml/tst_SwiftRollTrackHeaders.qml` — new mounted functions (contract
  below); reuse the file's lookup/wait helpers and `openHeaderMenu`/`chooseHeaderAction`.
- `src/checks/trackheaders/TrackHeadersInputChecks.swift` — new
  `rulerScopeHeaderRecordsGuard` block (keyboard A022/A023) and the stale
  delete/duplicate identity-guard + in-bounds add-release predicates.
- `src/checks/trackheaders/tst_trackactivitymeter.swift` — single-track contract,
  driven-row-only republish and pixel-identical silence predicates (identity-based).
- `src/checks/trackheaders/trackheadermenu.swift` / `trackheadermutations.swift` /
  `headerinputfixture.swift` — extend existing functions with the missing conjunct
  predicates only (stale-guard variants; the in-bounds guard).
- `src/ui/songview/quick/swiftroll/TrackHeaderBand.qml`,
  `src/swift/app/headers/*.swift` — **contingent only**: no gap found at freeze; edit
  solely to fix a divergence a new predicate exposes.
- Ledgers (controller-delegated ledger agent, this task's commit scope): flip then
  delete `proof.trackheaderinput.txt`, `proof.trackheaderraster.txt`,
  `proof.tst_trackactivitymeter.txt`; row flips only in `proof.trackheadermenu.txt`,
  `proof.trackheadermutations.txt`, `src/checks/rollcheck/proof.keyboard.txt` (A022/A023).

No CMake changes (no new files). NOT touched: `tst_EditorDrawer.qml` (hot: 54 in flight,
59b queued — its committed header tests stay as-is), `EditorSurface.qml`,
`PianoGrid.swift`, `ShellPresenter.swift`, `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `ShellWindow.qml` (read-only; 54/58/65 own them) and
`SessionChecks.swift` (dispatch already reaches every touched suite). No `src/project/`
or `external/` changes. Sizing exception: one proof family over ~4 check files + six
ledgers, one verification-surface set — named for the dispatch table.

# Prerequisites

None. Free-parallel by the sprint plan (§5). Re-snapshot line references if task-54's
in-flight `EditorSurface.qml`/`ApplicationSession.swift` edits move them; 66 consumes
no interface from 54/58/65.

# Interface contract

No production interface changes. New message anchors (verbatim once written; one per
fork clause family), tolerance 0.01 where geometric; every existing message in touched
files stays verbatim.

`tst_SwiftRollTrackHeaders.qml` adds:
- "the mounted band and its input stay visible on the canvas" — `timelineQuickTrackHeaders`
  visible, on-canvas rect == presenter bandRect; `timelineTrackHeadersInput` visible with
  positive size (input A004/A009).
- "the rendered rows count equals the presenter's rows" — Repeater count ==
  `headersModel.rows.count` (input A017, closes the PARTIAL; the "model count not
  exposed" reason is stale — `TrackHeaderBand.qml:201` binds it).
- "the band renders a real frame with distinct pixels" — band-region grab non-null,
  dimensions match, at least two distinct pixel values (input A018/A019).
- "clicking a title selects the row and alters the retained raster" — click title point →
  `titleBold` flips and the captured row region differs (input A021).
- "the header scrollbar and its thumb stay visible while content overflows" (input A087).
- "hovering a header title does not create a tooltip" — roll-lane twin of the drawer test:
  resolve row + title point, `mouseMove`, no `timelineTrackHeaderToolTip` descendant
  (input A095-A098; four clauses: row lookup, title point, hover accepted via the band's
  hover state, absent tooltip).
- "the header menu dispatches all five actions and restores band focus" — mounted
  `chooseHeaderAction` per action: change-voice closes the menu and fires the request
  without a write; show-voice fires reveal without a write, band input keeps
  activeFocus; rename begins; duplicate/delete run one command each, undo restores
  (menu A003/A027/A043/A097/A140 establishment + A067 reveal-focus + five-actions).
- "the rename editor takes focus and Escape discards it" — menu→Rename: editor visible
  and focused, Escape hides it, title unchanged, still hidden after settle; same
  observation after a transient (focus-loss) cancellation (menu A049/A053/A057;
  mutations A001/A022/A027).
- "a structural remap cancels the open menu and returns focus to the band" — open menu,
  remap via the presenter, menu closes, activeFocus is the band input, never the menu
  frame (menu A101/A102).
- "the meter raster spans exact device pixels" — captured meter raster width/height ==
  device-pixel spans of (band x, activityWidth) and (row y, meterHeight) at the observed
  dpr (activitymeter A037/A038); "the stereo right channel paints its partial height" —
  counted painted rows of the right channel at a partial level, bottom row shared with
  the left (A048); "an undriven neighbor row's meter stays unpainted" — second row's
  raster captured and equal to its zero-level capture (A052/A054).

`TrackHeadersInputChecks.swift` adds:
- `rulerScopeHeaderRecordsGuard` (cppID `swiftcore/PianoRoll::timelineRulerScope`,
  the established Swift id for that fork function — keyboard.txt S072-S075 precedent):
  seed a note, apply the fork-shaped −11 move, then guard-lookup the attached presenter
  (`report.fail` on absence — keyboard A022) and assert rows reconcile: non-add rows
  equal used timeline tracks in order, add row present iff `canAddTrack`
  (keyboard A023; reuse the `headerReconciliationStructural` shape,
  `tst_trackheadermodel.swift:137`).
- Stale destructive guards: after `openMenu` + `moveTrack`, `activateHeaderMenuAction(4/5)`
  writes nothing beyond the move and requests no picker (menu A123/A133 — behavioral
  equivalent of the fork's interposed-activation race, task-52 drag-A043 precedent).
- In-bounds add-release guard: the outside release point stays inside the input bounds
  (mutations A090).

`tst_trackactivitymeter.swift` adds:
- "a single-track document without capacity publishes exactly one row" — attach to a
  document with one used track and `canAddTrack == false` → one row, no add row
  (activitymeter A005).
- "a level change republishes exactly the driven row" and "a pixel-identical level
  republishes nothing" — row-handle identity comparison across `advanceActivity`
  (underpins the dataChanged retirements; presenter law `TrackHeaders.swift:438-442`).

# Implementation steps

1. Add the presenter-level predicates first (expected GREEN: presenter already obeys;
   a failure exposes a real divergence — fix in the contingent files and record
   RED→GREEN for that fix only).
2. Add the mounted roll-lane functions; same expectation. Reuse the meter-capture
   helpers in `test_zMountedMeterWindowRasterAndScopedRows`.
3. Run the lanes below; the evidence JSONs (`swiftroll-window.json`,
   `swiftcore-projectsession.json` under `build/proof-evidence/`) feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:qml-roll --verbose` — all new + existing roll-lane header predicates
  and regressions (`tst_SwiftRoll*`, `tst_TimelineScrollbar`, `tst_TimelinePan`).
- `deno task verify --filter swiftcore-projectsession --verbose` — headers suites with
  the new ruler-scope/stale/single-track/silence predicates, keyboard-guard included,
  plus session-suite regressions.
- Runtime prerequisite: the roll lane's usual offscreen-capable Qt windowing; no native
  audio.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no pixel
  constants in production.
- Implementers never edit ledgers; the controller delegates them to the ledger agent.
  Mapping (agent; re-verify each row against the evidence JSONs and the fork sources at
  the ledgers' pinned revisions — f3069ef6 for the five trackheaders files, a1244957 for
  keyboard):
  - trackheaderinput: A004/A009 → visibility anchor; A017 → rows-count anchor; A018/A019
    → distinct-pixels anchor; A021 → selection-raster anchor; A087 → scrollbar anchor;
    A095/A096/A097/A098 → the tooltip anchors. Delete the file when closed.
  - trackheaderraster: A002, A007-A011, A018, A019, A021, A022 → `RETIRED-REPRESENTATION`
    (each residual pins the fork's native QQuickWindow/QuickFramebuffer raster
    observation; the behavioral conjuncts already carry executing converted-window
    anchors S038-S041/S059/S060/S062/S065-S068 — cite them in the retirement line).
    Delete the file.
  - tst_trackactivitymeter: A002/A003 (native fixture discovery), A011 (role-number
    registry), A012-A016/A025-A028/A032-A035/A056-A059 (QAbstractItemModel::dataChanged
    count/first/last/roles), A036 (native band-layout lookup), A040/A053 (fork isOpaque
    alpha scan; converted grabs opaque by construction) → `RETIRED-REPRESENTATION`, each
    citing the executing row-identity anchor it behavioral-maps to (existing
    S020/S021/S025/S026, new silence/identity anchors); A005 → single-track anchor;
    A037/A038 → device-pixel-span anchors; A048 → right-channel count anchor; A052/A054
    → neighbor-row raster anchors. Delete the file.
  - trackheadermenu: A003/A027/A043/A097/A140 → five-actions/focus anchors (MATCHED);
    A049/A053/A057 → rename-focus anchors (MATCHED); A067 → reveal-focus anchor
    (MATCHED); A101/A102 → remap-cancellation focus anchors (MATCHED); A123/A133 →
    stale destructive anchors (MATCHED, behavioral-equivalent note in the mapping);
    A035/A038 STAY GAP with the named header→voice-picker deferral. Ledger NOT deleted.
  - trackheadermutations: A001/A022/A027 → rename-editor observation anchors (MATCHED;
    these are mutations-ledger rows, distinct from keyboard A022/A023); A090 →
    in-bounds anchor (MATCHED); the remaining 41 picker-journey rows (GAP A075/A098/
    A108/A117/A119/A128/A147/A152, PARTIAL the other 33) keep their dispositions with
    the deferral appended verbatim: "Blocked on the header→voice-picker mount (callbacks
    unwired: DocumentWorkspace.swift:120 wires only changeTrackVoiceRequested; no QML
    handler; fork picker form lives in drawer/VoicePicker.qml)". Ledger NOT deleted.
  - keyboard: A022 → the ruler-scope guard's `report.fail` predicate; A023 → the
    reconciliation anchor. Rows flip in this task's commit; the keyboard ledger
    survives its other open rows.
- RETIRED-REPRESENTATION rows must be fork-verified at the pinned revision before
  retiring (the dataChanged rows against `tst_trackactivitymeter.cpp:169-172,197-200,
  228-231,314-317`; the raster rows against `trackheaderraster.cpp:73-194`).
- The deferred picker rows are the surface spec for a future slice; do not weaken their
  spec text and do not close any with presenter-only evidence (the picker-window
  conjuncts are user-visible behavior).

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check --executed` (pre-deletion state
   shows input/raster/activitymeter fully closed with executing anchors), then
   `deno task proof sites --area trackheaders` confirms the three deletions and the
   survivors (menu 2 GAP, mutations 41); `--area keyboard` shows A022/A023 closed.
2. Visual smoke (desktop): hover a track title — no tooltip appears; right-click a
   header — five menu rows; run Rename/Escape, Duplicate, Delete + undo; double-click a
   voice cell — nothing opens (known deferral; confirm no crash or leaked state); watch
   the activity meter while playing.
