# Task 6 — xcmd certificate: 62 GAP→MATCHED, preamble, delete

## Context

After Tasks 3-5, every one of `proof.xcmd.txt`'s 62 GAP sites has an
executing Swift predicate reproducing the original fixture values
(producers: task-3/4/5 briefs' Interface contracts; the controller's
recorded narrow-suite PASS lines are the execution evidence). This task
maps every site to its predicate, rewrites the proof as a deletion
certificate, and deletes `xcmd.cpp`.

## Exact write set

- `src/checks/automation/domain/proof.xcmd.txt`
- delete `src/checks/automation/domain/xcmd.cpp`

## Prerequisites

Tasks 3, 4, 5 accepted and C2 committed (final `xcmd.swift` state).

## Interface contract

- All 62 A entries: `Disposition: MATCHED`; each mapping names the slot
  section, the predicate's `xcmd.swift`/`xcmdRanges.swift` location, and
  the observable (lane projection, byte pair/chain at tick, oneEdit,
  byte equality after undo/redo, count). Array-valued predicates close
  size/order/index sites together where they cover them (spec §2.1
  array rule — cite one predicate for A050+A051-style pairs only when
  the array genuinely asserts both observables).
- Undo-walk sites (A007, A042, and every `QCOMPARE(smf().write(),
  before.smf)` after an undo/redo): mapping states the count-free undo
  to the named clean base and byte equality — never a claim about
  `QUndoStack` depth (spec §2.1 revision rule).
- Preamble per spec §3: retain `Reference revision
  f3069ef693542bdb63564b80a29773e2f5b2a360`; `Original SHA-256 ce94aa2b…` verified against
  disk and `git show f3069ef6:…` before deletion; TWO Swift counterpart
  pairs — `xcmd.swift` and `xcmdRanges.swift` — each with its post-C2
  `shasum -a 256` (verify at execution; never placeholders); `Covered
  native implementation: src/core/xcmd.cpp :: xcmd selector/payload
  canonicalization; src/core/songdocument*.cpp :: writeLanePoints/
  moveLanePoints/deleteLanePoints/removeTimeRange/moveRange/
  applyRangeEdit`; `Registered run path:` names both entries
  (`drawerAutomationXcmdLaneEdits → runAutomationPageChecks →
  projectSession (suite 10)` and `coreTimeXcmdRangeEdits →
  runTimeEditsSuite → timeEdits (suite 9)` plus the pre-existing
  `coreTimeXcmdTimeTraffic` and `drawerAutomationXcmdParity` paths);
  Verification line records the controller's post-deletion full
  swiftcore PASS.
- The existing `S001-S016` trailer is preserved (supplementary
  minimal-fixture evidence) and extended with the new predicates the
  mappings cite, in execution order.

## Implementation steps

1. Verify SHAs (original on-disk vs proof pin vs reference revision;
   both Swift counterparts post-C2).
2. Reclassify the 62 sites with `deno task proof:edit … --apply`
   (mapping coupled). Batch by slot; after each slot batch, confirm
   `deno task proof show automation/domain/xcmd.cpp` parses and the
   tally moved by exactly that slot's site count.
3. Rewrite the preamble to the certificate format; keep the fixture/
   loop inventory section.
4. Delete `src/checks/automation/domain/xcmd.cpp`.

## Acceptance predicate

- NAMED CHECKS: `deno task proof show automation/domain/xcmd.cpp` parses
  with 62 sites terminal (62 MATCHED); `deno task proof list --area
  automation/domain` shows xcmd `PARTIAL 0, GAP 0`; `xcmd.cpp` absent.
  Controller: `deno task verify --filter swiftcore --verbose` (records
  the Result line — certificate evidence) — this run must still execute
  every predicate the mappings cite, since the deleted original only
  ever provided the obligation, not the execution.
- Coverage: the proof commands prove the terminal ledger; the full-lane
  run re-proves the predicates' execution post-deletion.

## Task-specific constraints

- No Swift edits in this task; if a mapping cannot honestly cite a
  passing predicate, the site stays GAP and the file stays unretired —
  report instead of forcing (plan.md global constraints).
- Do not touch `tst_automationdomain.h` (Task 7 deletes it) or any other
  proof file.
