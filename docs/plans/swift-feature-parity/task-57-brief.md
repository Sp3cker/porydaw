# Context

Task 57 — automation drag/gesture domain. Close the gesture interaction families
(230 open rows across nine ledgers, tallies re-verified by awk at freeze) against
the mounted automation drawer surface, then delete the four fully closable
gesturecheck ledgers. Proof completion + ledger closure; production
`AutomationInteraction`/`AutomationNodeTransactions`/`AutomationSelectionCommands`/
`AutomationLaneProjection` behavior lands only where a new predicate exposes a
real divergence.

1. **Census (awk over `Disposition:` lines, verified this freeze)**:
   - `automationgesturecheck/proof.contract.txt` — 67 rows: 33 MATCHED, 27 PARTIAL,
     6 GAP, 1 RETIRED. Open **33** (contract/move/collision/rebuild-handle rows:
     A001–A005, A008–A010, A012–A027, A031/A032, A044, A062–A067).
   - `automationgesturecheck/proof.crosslane.txt` — 31 rows: 11 MATCHED, 18 PARTIAL,
     1 GAP, 1 RETIRED. Open **19** (cross-lane no-write invariants, band isolation,
     stale-batch/range-edit rows: A001/A002, A005, A007–A018, A021–A024).
   - `automationgesturecheck/proof.hover.txt` — 30 rows: 7 MATCHED, 20 GAP,
     3 RETIRED. Open **20**, all GAP (A002/A003, A005–A008, A011–A015, A017,
     A023–A030; native Quick-window hover route + case matrix, no executing check).
   - `automationgesturecheck/proof.parity.txt` — 21 rows: 8 MATCHED, 11 PARTIAL,
     2 GAP. Open **13** (sweep/parity rows: A001/A002, A006–A012, A015/A016, A018/A019).
   - `automation/proof.automationnodedrag.txt` — 71 rows: 36 MATCHED, 6 PARTIAL,
     27 GAP, 2 RETIRED. Open **33** (`nodeDragCommits` A001/A002/A008/A009,
     `nodeDragShiftAxisLocks` A014/A015, `scrolledOriginPhantomCommits` A019–A021,
     A026–A034, `selectedRangeDragAndDelete` A040/A041/A043/A045/A046,
     `escapeCancelsAdapterDrag` A050/A051/A055–A057,
     `rebuildCancelsAdapterDragAndRecovers` A060/A061/A065/A067/A068).
   - `automation/proof.automationownership.txt` — 127 rows: 76 MATCHED, 21 PARTIAL,
     16 GAP, 14 RETIRED. Open **37** (`tracksSelectionRings` A001/A003–A007,
     `tracksSelectionGroupDragUndo` A008/A025/A026, `pencilModeChange*` A045–A062,
     `detailThresholdHiddenVisibleNodePrecedence` A070–A072/A079–A083,
     `parameterSwitchCancelsNodeDrag` A093/A096/A099/A103/A104/A113/A118).
   - `automation/proof.automationselection.txt` — 173 rows: 111 MATCHED, 25 PARTIAL,
     3 GAP, 34 RETIRED. Open **28** (band isolation A004/A005/A015/A020, multi-lane
     drag A039/A041/A052–A055/A061/A067, delete/no-op A075/A077/A081/A088/A089/
     A095/A099, rebuild-abort A116/A117, cc-lane exclusion A124/A131–A133,
     ghost-toggle A165/A169/A172).
   - `automation/proof.automationpainting.txt` — 62 rows: 23 MATCHED, 3 PARTIAL,
     30 GAP, 6 RETIRED. Open **33** (lead-in composition A002/A004/A007/A008/A011/
     A013/A016–A018/A021/A023/A026/A027, step curves A031/A032/A035–A038,
     selection rings/reticles A044–A048, half-open time-selection rings A053–A057).
   - `automation/proof.automationpencil.txt` — 74 rows: 46 MATCHED, 8 PARTIAL,
     6 GAP, 14 RETIRED. Open **14** (empty-lane commit A002–A005/A017, preview
     no-mutate A026, endpoint restore A043, pitch-bend center A053/A057/A058,
     excursion delete A068/A069; A049/A050 `CoreTimeDefaults` bpm-math rows ride
     along only if the pencil predicates already cover them, else retire as
     harness-math).
   - Total in-scope open: **230**. Sprint-3 §2 family roll-up (587) counts wider
     automation rows (value-prompt 55, tap-tempo 59, command tail per §6); those
     belong to tasks 55 and the following-sprint backlog, not here.
2. **Canvaslayout gesture residue (included)**: `proof.automationcanvaslayout.txt`
   holds 5 GAP + 26 PARTIAL; the gesture rows move in this task (13):
   `middleMousePanSurvivesRefresh` A072 (PARTIAL — `activateParameter(pan)` return
   never asserted); `primaryTrackSwitchRebuildsRowsDuringPan` A076/A077/A081/A084/
   A085 (PARTIAL — `addTrack(0)` return, old/new row-handle validity across the
   release); `wheelZoomAndSectionResizePreserveDrawerState` A113 (PARTIAL —
   activation return on the Volume lane instead of the pan lane), A120/A124/A125/
   A126 (GAP — active-page/section-height facts after zoom/resize), A121/A122
   (PARTIAL — viewport-height readout path). The remaining 18 canvaslayout opens
   (sectionResize label geometry, empty-param `gridTicksAt`, view-state viewport/
   split pairs) are task-56/follow-up geometry rows — do not touch here; note the
   boundary in the commit message.
3. **Fork laws** (`git show fceecd88:src/checks/…`):
   - `automationgesturecheck/contract.cpp:120` (`expectPoints`), `crosslane.cpp:147`
     (`expectUnchanged`), `parity.cpp` sweep/parity matrix, `hover.cpp:330-335`
     (native Quick-window hover route).
   - `automation/automationnodedrag.cpp:204-355` (drag commit/shift-lock/phantom/
     range/escape/rebuild-cancel), `automationownership.cpp:64-156` (selection
     rings, group drag+undo, pencil/node gesture retention, detail threshold,
     parameter-switch cancel), `automationselection.cpp:241-248` (band/multi-lane/
     delete/rebuild/ghost outcomes), painting lead-in/step/ring composition,
     pencil commit/preview/restore/delete clauses at the A-row sites above.
4. **Swift current state at freeze**: `src/swift/app/drawer/automation/`
   (`AutomationInteraction.swift` 718L with the hover model + pointer route,
   `AutomationNodeTransactions.swift` 259L, `AutomationSelectionCommands.swift`
   182L, `AutomationLaneProjection.swift` 419L with lead-in-excluded hover
   readout, `AutomationHandles.swift` per-node `hovered` flag,
   `AutomationContentPublication.swift:304` hover-flag publication). Checks:
   `src/checks/automation/domain/` (`gestureNodeDrag.swift`,
   `gesturePointRange.swift`, `gestureSweep.swift`, `gesturePencil.swift`,
   `xcmd.swift`, `xcmdRanges.swift`, `tst_automationdomain.swift`) already carry
   model-level gesture predicates; `tst_EditorDrawer.qml`
   `test_productionAutomationHoverThroughInput` proves hover-publishes-nothing,
   single-ring, ring+label pairing on the mounted page. The gap is executing
   message-anchored predicates per fork clause on the mounted surface — hover
   enter/move/leave, drag tick/count outcomes, cross-lane no-writes,
   live-preview freeze, playback-timeline projection, selection-ring paint —
   plus the scene-graph mesh/ring identity rows, which retire inside this task
   per sprint-3 §4 (never standalone).

# Exact write set

- `src/checks/automation/domain/gestureNodeDrag.swift` — node-drag tick/count
  outcomes, shift-axis locks, scrolled-origin phantom commits, selected-range
  drag+delete, escape-cancel, rebuild-cancel+recover predicates.
- `src/checks/automation/domain/gesturePointRange.swift` +
  `gestureSweep.swift` — contract/move/collision/range, cross-lane no-write and
  band-isolation invariants, sweep/parity matrix rows.
- `src/checks/automation/domain/gesturePencil.swift` — pencil commit-once,
  preview-no-mutate, endpoint restore, pitch-bend center, excursion delete,
  pencil/node gesture retention across mode change.
- `src/checks/automation/automationselection.swift` — band/multi-lane/delete/
  rebuild-abort/cc-exclusion/ghost predicates (selection rings + painted shifts).
- `src/checks/automation/presentation/painting.swift` — lead-in/step/ring
  composition predicates against `AutomationLaneProjection`.
- `src/checks/automation/automationcanvasediting.swift` — hover enter/move/leave
  predicates driving the production hover model (replaces the retired Quick route).
- `src/checks/editorqml/tst_EditorDrawer.qml` — hover/drag journey probes only
  (append-only functions; see serialization flag below).
- Production Swift (`AutomationInteraction.swift`,
  `AutomationNodeTransactions.swift`, `AutomationSelectionCommands.swift`,
  `AutomationLaneProjection.swift`) — contingent edits only where a new
  predicate exposes a real divergence (record RED→GREEN for that fix only).
- Ledgers (controller-delegated ledger agent, this task's commit scope): flip
  then **delete** `automationgesturecheck/proof.contract.txt`,
  `proof.crosslane.txt`, `proof.hover.txt`, `proof.parity.txt`; row flips only
  in `proof.automationnodedrag.txt`, `proof.automationownership.txt`,
  `proof.automationselection.txt`, `proof.automationpainting.txt`,
  `proof.automationpencil.txt`, and the 13 gesture rows of
  `proof.automationcanvaslayout.txt`.

No `src/checks/automation/` prompt/menu/clipboard/tap-tempo files (tasks 55,
backlog), no velocity/voice/roll files, no new C++, no hot-file edits outside
the Escape-reuse rule below.

# Prerequisites

- Task 56 settles the canvaslayout converted-lane anchors (S051–S111) this task's
  13 gesture rows build beside; re-snapshot anchor lines at freeze.
- **Serialization flag — task 59b in flight**: 59b owns `tst_EditorDrawer.qml`
  velocity sections now and will add ONE `Escape` branch in
  `ApplicationSession.handleGridEscape` plus one `tst_ShellWindow.qml` journey.
  This task's drawer edits checkpoint **after** 59b lands (sprint chain
  55 → 56 → 57 drawer-serial); 59b's Escape branch is the single keyboard
  ingress this task's `escapeCancelsAdapterDrag` rows (nodedrag A050–A057) route
  through — NEVER add a second Escape dispatcher, synthetic-forwarding path, or
  focus-memory seam (AGENTS.md keyboard priority). If 59b has not landed at
  dispatch, implement all swiftcore predicates first and hold the drawer probes.

# Interface contract

- New check anchors (message-anchored, one per fork clause family; the `what:`/
  `message:` strings are the ledger anchors and stay verbatim once written):
  - node-drag — "a node drag commits the tick and count outcomes"; "shift locks
    the drag axis"; "a scrolled-origin drag commits through its phantom";
    "a selected-range drag deletes through the range";
    "escape cancels the adapter drag without mutation";
    "a rebuild cancels the adapter drag and the lane recovers".
  - contract/sweep — "a move commits one edit"; "a colliding move resolves
    without duplication"; "a row rebuild keeps its handles"; "a sweep ramp
    commits its band".
  - cross-lane — "a cross-lane gesture writes nothing outside its lane";
    "a stale batch release writes nothing"; "tempo, pan and LFO lanes isolate
    by band".
  - hover — "hover enter publishes exactly one ring"; "hover move republishes
    without writing"; "hover leave clears the ring"; "a hover is not the page's
    interaction" (extends the existing `test_productionAutomationHoverThroughInput`
    anchors, which stay verbatim).
  - selection — "band selection isolates tempo and CC rows";
    "a multi-lane drag preserves tempo and CC order"; "an empty delete is a
    no-op"; "a document rebuild aborts the drag"; "ghost toggles are view-only".
  - painting — "an empty tempo store composes no lead-in"; "a first-nonzero
    tempo point composes its implicit lead-in"; "an explicit tick-zero point
    suppresses the lead-in"; "step curves compose their nodes"; "selection
    rings and reticles compose"; "a half-open time selection composes node rings".
  - pencil — "a pencil stroke on an empty lane commits once";
    "a pencil preview mutates nothing until release"; "a stroke restores its
    held endpoint value"; "a single click on a pitch-bend lane restores center
    at cell end"; "a pencil click on an excursion node deletes the excursion".
  - canvaslayout gesture rows — "activating the pan lane returns its handle";
    "a track switch rebuilds rows during the pan"; "a wheel zoom preserves the
    drawer's active page and section heights".
- Preservation contract: production behavior in all four automation Swift files
  is unchanged except RED→GREEN fixes with ledger-cited evidence; every existing
  check message in touched files stays verbatim; the retired C++ gesture harness
  never rebuilds (native-window hover rows are proven through the production
  hover model, not re-hosted).

# Implementation steps

1. Contract/sweep/crosslane/parity: add the swiftcore predicates in
   `gestureNodeDrag.swift`, `gesturePointRange.swift`, `gestureSweep.swift`,
   `xcmdRanges.swift`, `automationselection.swift` per the contract; run
   swiftcore (lane §1) after each file.
2. Node-drag outcomes (tick/count, shift-lock, phantom, range-delete,
   escape-cancel via 59b's branch, rebuild-cancel) in `gestureNodeDrag.swift`.
3. Ownership/selection (rings, group drag+undo, mode retention, detail
   threshold, parameter-switch cancel, band/multi-lane/delete/rebuild/ghost) in
   `automationselection.swift` + domain files.
4. Painting/pencil composition predicates in `presentation/painting.swift`,
   `gesturePencil.swift`, `automationcanvasediting.swift` (hover enter/move/leave).
5. Canvaslayout gesture rows: activation-return, row-handle validity, zoom
   page/height predicates beside the task-56 anchors (no geometry-row drift).
6. After 59b lands: append the drawer hover/drag journey probes to
   `tst_EditorDrawer.qml`; run the drawer lane.
7. Run the full lane set below; the per-lane evidence JSONs under
   `build/proof-evidence/` feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — all new gesture/domain/
  selection/painting/pencil predicates + regressions (the ledgers' recorded
  command).
- `deno task verify:qml --verbose` — editor drawer lane incl. the existing
  `test_productionAutomationHoverThroughInput` and the new hover/drag probes.
- Shared baseline after the writer settles: `deno task verify:bridge`,
  `deno task format --check`, `deno task proof check`,
  `deno task proof check --executed` (pre-deletion state shows the four
  gesturecheck ledgers fully closed with executing anchors).
- Runtime prerequisite: macOS for swiftcore/project-adjacent rows only where
  the lane declares `Platform::MacOS`; drawer-lane probes need the offscreen
  QML host, not native audio.

# Task-specific constraints

- No new C++; no comments; one message-anchored predicate per fork clause; WCAG
  AA beats parity where they conflict; visual parity with `fceecd88`; base-font
  sizing only; GridPalette colors for any ring/label QML touched.
- Scene-graph mesh/ring identity rows (sprint-3 §4: ownership/nodedrag) retire
  inside this task with named RETIRED-REPRESENTATION reasons — no standalone
  reconciliation, no second representation sweep.
- Hover rows MUST drive `AutomationInteraction`'s production hover path (the
  mounted `automationPlotInput` → `model.hoverDisplay` route the drawer probe
  already exercises); never re-host the retired Quick window or assert
  `Qt::WindowTransparentForInput`.
- Escape handling reuses 59b's `ApplicationSession.handleGridEscape` branch;
  no second dispatcher, no synthetic event forwarding, no focus memory.
- Implementers never edit ledgers; the controller delegates them to the ledger
  agent. Ledger mapping (agent; re-verify each row against the evidence JSONs
  and the fork sources cited above): contract A001–A067 → sweep/contract
  anchors; crosslane A001–A024 → no-write/isolation anchors; hover A002–A030 →
  hover enter/move/leave anchors (A001 + 3 RETIRED stay); parity A001–A019 →
  parity-matrix anchors; nodedrag/ownership/selection/painting/pencil opens →
  same-family anchors per the contract; canvaslayout A072/A076/A077/A081/A084/
  A085/A113/A120–A122/A124–A126 → gesture-row anchors. Delete the four
  gesturecheck files only when every row is MATCHED/RETIRED.
- If any predicate's runtime observation contradicts the fork clause it claims,
  stop and report those rows with the observed evidence instead of adjusting
  the check to the divergence.

# Controller verification

1. `deno task proof sites --area automation` confirms the four gesturecheck
   deletions and the surviving opens (nodedrag/ownership/selection/painting/
   pencil PARTIAL/GAP only, canvaslayout minus the 13 gesture rows).
2. Confirm no `tst_EditorDrawer.qml` merge residue with 59b's velocity sections
   and exactly one Escape branch in `ApplicationSession.handleGridEscape`.
3. Store-level smoke (headless, same lanes): swiftcore + drawer lanes green with
   no regressions against the pre-task run.

# Deliverable answers

- **Path**: `docs/plans/swift-feature-parity/task-57-brief.md` (this file).
- **Write set**: `src/checks/automation/domain/gestureNodeDrag.swift`,
  `gesturePointRange.swift`, `gestureSweep.swift`, `gesturePencil.swift`,
  `src/checks/automation/automationselection.swift`,
  `src/checks/automation/presentation/painting.swift`,
  `src/checks/automation/automationcanvasediting.swift`,
  `src/checks/editorqml/tst_EditorDrawer.qml` (probes only, post-59b),
  contingent production edits in `src/swift/app/drawer/automation/
  AutomationInteraction.swift`, `AutomationNodeTransactions.swift`,
  `AutomationSelectionCommands.swift`, `AutomationLaneProjection.swift`.
- **Open questions**:
  1. Pencil A049/A050 (`CoreTimeDefaults` bpm math) — harness-math retire vs
     pencil-predicate cover? Recommend retire; controller confirms at freeze.
  2. Canvaslayout A109 (`timelineSplitX`) sits beside the gesture rows but is a
     view-state pair — confirm it stays with task-65-style state work, not 57.
  3. If 59b's Escape branch changes shape before landing, who re-anchors the
     escape-cancel predicates — 57 implementer (preferred) or 59b follow-up?
- **Deletable ledgers on close**: `src/checks/automationgesturecheck/
  proof.contract.txt`, `proof.crosslane.txt`, `proof.hover.txt`,
  `proof.parity.txt`. All other ledgers in scope keep row-flips only and survive
  (canvaslayout: 18 non-gesture opens remain; nodedrag/ownership/selection/
  painting/pencil close fully only if every open row proves — otherwise the
  residue rides the automation command-tail backlog per sprint-3 §6).
