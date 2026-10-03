# Task 74 brief — timeline-pan gutter residue close-out (representation retirement + named blockers)

# Context

Task 74 closes the timeline-pan ledger `src/checks/timelinepan/
proof.tst_timelinepan.txt` to its final honest state: 43 GAP rows (tally 88
MATCHED / 43 GAP / 7 RETIRED-REPRESENTATION, verified by awk this freeze)
against the mounted roll pan surface. The pan laws are landed and passing —
the lane records `deno task verify:qml-roll` green with
`test_wheelPansCamera`, `test_middleDragPansCamera`, `test_hoverChipOverlay`,
`test_coalescedRefreshMatchesFull`, `test_trackSwitchKeepsNoteLabels` and
`test_selectedPanRenders` — so the open rows are representation residue, two
message-anchor joins, and a genuinely absent product capability that stays
blocked. Proof completion only; no production change is expected.

1. **Census (verified this freeze; fork = `git show c17d966f:
   src/checks/timelinepan/tst_timelinepan.cpp` at each row's `expr` line)**:
   - **13 representation rows**:
     - QSG/scene-graph internals — A003/A004/A006/A007: dashed-line builder
       equality and geometry-node reuse stages of the retired native harness
       (`dashPhasePreservesClip`, :288-:388); the Swift scene has no
       node-pool or dashed-builder counterpart (`GridScene` paints the
       selection frame directly).
     - Signal-identity clauses of the retired C++ gutter text model — A021
       (`voiceChanges.signalCount() == 0` after an empty wheel, :486) and
       A024 (`structuralChangeCount() == 0` across pans, :500): the Swift
       model rebuild path emits `modelReset` by design, so no zero-signal
       assertion can exist; the observable outcomes are already asserted
       (empty wheel leaves camera and gutter summary unchanged,
       `tst_TimelinePan.qml:251-253`; "gutter labels survive eight pans
       unchanged", `:264`).
     - Overflow/unclipped-gutter geometry — A040, A102, A113, A114, A131,
       A137, A138: the fork asserts long pad labels and chips may exceed or
       cross the keyboard gutter (:564, :828, :858-:859, :883, :894-:895);
       the landed Swift typography authority clips labels and chips to the
       gutter (tasks 29-33; R12's registered deviation), so overflow
       permission is retired, not ported.
   - **30 blocked rows** (stay GAP, blocker named in the reason):
     - Drum-pad label model — A034-A039, A041-A044, A061, A064, A065, A069,
       A080, A082, A085, A087: the fork resolves per-pad names ("Kick",
       black-key classification, long-name geometry, row disappearance on
       drum-track switch). No drum/pad symbol exists anywhere in
       `src/swift/app/roll/` or `src/swift/app/timeline/` (verified by
       search); the keyboard model is track-independent. Blocker: the
       drum-keyboard surface does not exist; it belongs to the keyboard
       family (`src/checks/keyboard/proof.tst_velocitymodel.txt`), not this
       ledger.
     - Per-track program surface — A028, A055, A071, A072, A073, A077,
       A079, A081, A083, A084, A086, A090: program-number classification,
       program-change events and current-program readback along the hover
       chip/track-switch journeys. Blocker: the roll publishes no per-track
       program surface; rides with the same future keyboard/drum surface.
2. **Current mounts (verified)**: `tst_TimelinePan.qml` runs in the
   `swiftroll-window` lane (`RollQmlTests.swift`); production owners are the
   `PianoGrid.swift` pan paths, `EditorCamera.swift` scroll policy and
   `GridScene.swift` chip/label projection, all landed. The ledger's 88
   MATCHED rows already cover the pan/refresh/hover laws.
3. **Overlap ruling**: `PianoGrid.swift`/`SongTabs.qml` are owned in flight
   by task 72. No production file is in this write set; if classification
   ever exposed a real pan divergence requiring a `PianoGrid.swift` fix,
   serialize that fix after 72 lands. Tasks 73/75/76 are disjoint.

# Exact write set

- `src/checks/rollqml/tst_TimelinePan.qml` — add message anchors to the two
  bare compares of the empty-wheel no-op case (:251-253); nothing else.
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row edits only in `src/checks/timelinepan/proof.tst_timelinepan.txt`.

No production files, no other check files, no in-flight-owned files.

# Prerequisites

None. Free-parallel with tasks 73/75/76.

# Interface contract

- Message anchors (added to existing asserts; existing messages verbatim):
  - "an empty wheel leaves the camera and gutter summary unchanged" (A021's
    behavior half).
  - A024's behavior half stays cited to the existing "gutter labels survive
    eight pans unchanged" (:264) — no new anchor.
- Row dispositions (ledger agent; fork-verified at `c17d966f`):
  - RETIRED-REPRESENTATION (one-line reason each, citing the anchored
    behavior half): A003/A004/A006/A007 (retired QSG dashed-builder/
    node-reuse harness internals; no Swift counterpart exists);
    A021/A024 (the rows' clauses are the retired C++ gutter text model's
    signal counts; the Swift rebuild path emits `modelReset` by design —
    the observable outcomes are the anchors: A021 → the new empty-wheel
    anchor, A024 → "gutter labels survive eight pans unchanged" (:264)
    plus the new anchor's summary compare); A040/A102/A113/A114/A131/
    A137/A138 (fork overflow permission contrary to the landed
    clipped-gutter typography authority; the clamped chip/label geometry
    is the registered deviation and is asserted by `test_hoverChipOverlay`).
  - GAP (unchanged, blocker named): the 30 drum-pad/program rows above,
    each reason naming "no drum-pad label model / no per-track program
    surface in the Swift roll; rides with the keyboard-family surface".
- Preservation contract: every existing test function and message in
  `tst_TimelinePan.qml` stays verbatim; no production behavior changes.

# Implementation steps

1. Fork-verify each of the 13 retirement rows at `c17d966f` and record the
   one-line reason (builder identity, signal identity, overflow clause).
2. Add the single new message anchor to the existing empty-wheel compares;
   keep the compares' logic identical.
3. Produce the rowMap (row id → disposition → anchor or reason) for the
   controller's ledger agent; confirm the 30 blocked rows' reasons name the
   blocker exactly.
4. Run the lane below.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:qml-roll --verbose` — the pan suite with the anchored
  empty-wheel case plus regressions.
- `deno task proof check --executed` — the new anchor executes.
- Runtime prerequisite: macOS for the QML lane.

# Task-specific constraints

- No production edits; no new C++; no code comments; no pixel constants.
- One message-anchored predicate per fork clause; existing messages
  verbatim.
- Implementers never edit ledgers; the controller's ledger agent applies
  the dispositions. The ledger file stays (30 blocked rows remain open);
  no deletion is claimed.
- No drum/program predicates are invented: absent surfaces stay blocked,
  never faked (charter V-1).

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`; `deno task proof sites --area
   timelinepan --status GAP` shows exactly the 30 blocked drum/program rows.
2. Confirm `deno task verify:qml-roll` is green at the settled tree.
