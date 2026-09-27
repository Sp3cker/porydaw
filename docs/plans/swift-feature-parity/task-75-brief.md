# Task 75 brief — pitch-bend surface close-out (curve/controller/lifecycle re-baseline + prototype pitch-curve certificates)

# Context

Task 75 finishes the pitch-bend editor surface after tasks 40/41/41b: the 13
open rows of the pitch-bend ledgers plus the 47 pitch-curve certificate rows
of the retired prototype harness whose GAP reasons predate the landed surface
("PitchBendPopup.qml unreferenced by production" — stale: it is mounted at
`EditorSurface.qml:942-998`). Surface: the mounted `PitchBendPopup` over
`src/swift/app/pitchbend/*` (owners `PitchBendKernel/Scene/Presenter`);
checks `src/checks/rollcheck/pitch_bend.swift` (swiftcore-projectsession,
`SessionChecks.swift:77`) and `src/checks/editorqml/tst_ShellPitchBend.qml`
(shell-pitch-bend lane, `ShellQmlTests.swift:64-65`). Three small behavior
predicates, one fixture repair, and per-row certification; production is
expected unchanged.

1. **Census (verified this freeze by awk over `Disposition:`)**:
   - `proof.lifecycle.txt` — 2 PARTIAL: A069/A070 pin the window cursor's
     non-null pixmap (`QTRY_VERIFY(!cursor().pixmap().isNull())`,
     lifecycle.cpp:289/:293 @ `0b4c9ea6`); the advertised `cursorKind`/
     `SizeHorCursor` is already proven (S061/S062, S047/S048) and the
     pixmap-not-shape deviation is registered in the rows.
   - `proof.curve.txt` — 3 PARTIAL: A025/A026 (curve.cpp:98/:99 @
     `4ae6619d`) pin Standard-Undo-shortcut delivery joined to the history
     index and the serialized song bytes; the fork's `sendUndo()` is a real
     keyClick on the Standard Undo binding (fixture.cpp:330-338). S046
     proves the mounted shortcut restores the curve; S017/S018 prove the
     index/bytes restores through the API undo path; no predicate joins
     them. A059 (curve.cpp:213) pins the duplicate-note fixture holding
     exactly two notes on the track.
   - `proof.controller.txt` — 8 PARTIAL: A011-A018 (controller.cpp:79-89 @
     `a1244957`): bend/lfo item guards, `QWindow` visible/exposed guard,
     real hover delivery over both scrub fields, and twice
     `view.cursor().shape() == Qt::SizeVerCursor`. S040 drives real hover
     and observes the hint; S041 asserts the advertised
     `cursorShape` — the window-cursor observation is engine-native.
   - Prototype certificates (same surface, stale reasons): `src/checks/
     swiftgridprototype/proof.interaction_smoke.txt` A003-A008/A029-A048
     (26 GAP) and `proof.jurisdiction_smoke.txt` A056-A068/A166-A173
     (21 GAP), pinned `18fee935`. The fork asserts the pitch-curve laws
     through the retired `sgc_` C seam: canonical export collapses
     redundant plateaus while keeping fine samples and endpoints
     (interaction_smoke.cpp:110-133), stroke/vertex edits, undo/redo
     persistence and Escape dismissal. The Swift `PitchBendKernel` owns
     these laws and `pitch_bend.swift` already carries 145 executed
     predicates (curve canonicalization ≈ "the written BENDR point is
     visible in the lane"/byte-contract anchors; vertex/undo/Escape laws =
     task 40/41 anchors).
2. **Swift current state**: the mounted undo journey delivers the real
   shortcut (`keySequence(StandardKey.Undo)`, tst_ShellPitchBend.qml:237)
   and reads the production history observables `app.canUndo`/`canRedo`
   (:242, :286); a serialized-lane observable is already read by the live-
   stroke test (:707 "undo changes the serialized lane beneath the live
   stroke"); `SongHistory` exposes `index`/`canUndo`
   (src/swift/core/SongHistory.swift:231). Native byte/index predicates
   exist (S017/S018 "undoing the BENDR write restores the history index /
   the serialized song").
3. **Boundary**: `src/checks/selectionkey/proof.localinputtier_pitchbend.txt`
   (10 open) is the local-input keyboard-arbitration surface — not this
   task. The two prototype ledgers' non-pitch rows (note-menu keyboard,
   transport) belong to task 76; both tasks edit row-disjoint sections of
   the same two ledger files.
4. **Overlap ruling**: tasks 68/69/72 own `ShellWindow.qml`,
   `ShellPresenter.swift`, `ApplicationSession.swift`,
   `tst_ShellWindow.qml`, `PianoGrid.swift` — none in this write set.
   `tst_ShellPitchBend.qml`/`pitch_bend.swift` have no in-flight writer.

# Exact write set

- `src/checks/rollcheck/pitch_bend.swift` — the duplicate-note fixture
  repair (A059) and, only if the mounted join cannot read an observable,
  native predicates for the A025/A026 joins.
- `src/checks/editorqml/tst_ShellPitchBend.qml` — extend
  `test_keyboardUndoWhileOpenRestoresCurve` with the two joined asserts
  (existing tests and messages byte-identical).
- Ledgers (controller-delegated ledger agent, this task's commit scope):
  row flips in `proof.curve.txt`, `proof.controller.txt`,
  `proof.lifecycle.txt` (then delete all three — their C++ originals are
  already deleted at `67544720`) and the pitch-curve rows (A003-A008,
  A029-A048, A056-A068, A166-A173) of the two swiftgridprototype ledgers.

No production files expected (contingent only), no
`proof.vertex/raster/fixture.txt` (already deleted by 41b), no
`localinputtier_pitchbend` rows.

# Prerequisites

None hard. Ledger coordination: tasks 75/76 flip row-disjoint sections of
`proof.interaction_smoke.txt`/`proof.jurisdiction_smoke.txt`; the controller
serializes the two ledger passes (or lands them in one commit) and deletes
those two ledgers only after both tasks' rows close.

# Interface contract

- Mounted anchors (message-anchored; existing messages verbatim):
  - "the undo shortcut returns the history stack to its pre-stroke depth"
    (A025 join: real `keySequence(StandardKey.Undo)` delivery with the
    `canUndo`/`canRedo` transitions of a single-stroke fixture).
  - "the undo shortcut restores the serialized lane beneath the stroke
    exactly" (A026 join: the :707 serialized-lane observable read before
    the stroke and re-read after the shortcut; whole-song byte equality
    stays cited to S018 in the mapping line).
- Native anchor: "the duplicate-note fixture holds exactly two notes"
  (A059: reshape that fixture's track to exactly the two duplicate notes —
  real checked-in fixture data, no synthetic seam).
- Row dispositions (ledger agent; fork-verified at each ledger's pinned
  revision):
  - MATCHED: A025/A026 → the two new mounted joins (S017/S018 cited as the
    byte/index halves); A059 → the native fixture anchor; controller
    A015/A017 → S040 (real hover delivery over bend/lfo observed);
    prototype pitch rows → per-row fork-verified mapping to the landed
    `pitch_bend.swift`/`tst_ShellPitchBend.qml` predicates (canonical
    export/stroke/vertex/undo/Escape laws).
  - RETIRED-REPRESENTATION (one-line reason each): lifecycle A069/A070
    (native window cursor pixmap; the advertised cursor kind/shape is the
    registered deviation); controller A011-A014/A016/A018 (harness item
    guards, `QWindow` visible/exposed guard, engine-native window-cursor
    shape observation); prototype rows whose clause pins the `sgc_` seam
    itself (session construction, coordinate helpers) rather than curve
    behavior — reason "retired sgc_ prototype seam; the behavior half is
    [anchor]".
- Preservation contract: production behavior in `PitchBendKernel`,
  `PitchBendScene`, `PitchBendPresenter`, `PitchBendPopup.qml` unchanged
  (contingent edits only if a RED join exposes a real divergence — record
  RED→GREEN for that fix only); every existing check message in touched
  files stays verbatim.

# Implementation steps

1. Classification pass first: for each of the 47 prototype rows, fork-verify
   the clause (`git show 18fee935:src/checks/swiftgridprototype/
   interaction_smoke.cpp` / `jurisdiction_smoke.cpp`) and record
   mapping-vs-seam-internal in the rowMap before any edit.
2. A059: reshape the duplicate-note fixture so its track holds exactly the
   two duplicate notes; assert the count (RED first: today's fixture has
   other notes).
3. A025/A026: extend the mounted undo test with the two joined asserts
   (RED first: no joined predicate exists). If the serialized-lane
   observable proves insufficient for exactness, add the native
   shortcut-route join in `pitch_bend.swift` instead and record why.
4. Run the lanes; hand the rowMap (row id → disposition → anchor file:line
   or reason) to the controller's ledger agent.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — the fixture anchor
  (and any native join) plus pitch-bend regressions.
- `deno task verify:shell --filter shell-pitch-bend --verbose` — the
  extended undo journey plus regressions (macOS host).
- `deno task verify:bridge`, `deno task format --check` (controller-side).
- `deno task proof check --executed` — every new anchor executes.
- RED evidence for each of the three new predicates before it passes.

# Task-specific constraints

- No new C++; no code comments; no test-only seams — `canUndo`/`canRedo`
  and the serialized-lane state are production observables; do not publish
  a history-index property for QML.
- One message-anchored predicate per fork clause; existing messages
  byte-identical; real key delivery only (no synthetic forwarding).
- WCAG AA beats parity; base-font sizing only.
- Implementers never edit ledgers; the controller's ledger agent flips the
  13 + 47 rows and deletes `proof.{lifecycle,curve,controller}.txt` in this
  task's commit when all rows are closed. The two prototype ledgers stay
  until task 76's rows close.
- No row of `localinputtier_pitchbend` is touched.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`; `deno task proof sites --area
   pitchbend` reports no open rows (three ledgers deleted).
2. Confirm `deno task verify --filter swiftcore` and
   `deno task verify:shell --filter shell-pitch-bend` are green at the
   settled tree.
3. Coordinate with task 76's ledger pass on the two swiftgridprototype
   files (row-disjoint; single commit allowed); after both land,
   `deno task proof sites --area swiftgridprototype` must report no open
   rows and the ledgers delete with their certificates.
