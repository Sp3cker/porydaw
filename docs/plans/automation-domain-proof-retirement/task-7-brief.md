# Task 7 — Shared header deletion + engine reachability gate

## Context

After Tasks 1 and 6, both remaining includers of
`src/checks/automation/domain/tst_automationdomain.h` (`gestures.cpp:1`,
`xcmd.cpp:1`) are deleted. The header's `runAutomationDomainCheck`
declaration has had no definition or caller since `31ea635f` deleted the
`.cpp`. This task removes the last domain C++ artifact and records the
engine-side reachability audit (spec §7-§8) fresh — never trusting the
scoping snapshot. It performs no engine deletion.

## Exact write set

- delete `src/checks/automation/domain/tst_automationdomain.h`
- new `docs/plans/automation-domain-proof-retirement/engine-reachability.md`

## Prerequisites

Tasks 1 and 6 accepted (both C++ originals deleted and certified).

## Interface contract

- `engine-reachability.md` records, with command output excerpts:
  1. Zero-includer verification for `tst_automationdomain.h`
     (harness `grep` for `tst_automationdomain.h` scoped to `src/`)
     performed before the deletion.
  2. Fresh CMake audit: harness `grep` for `xcmd`, `nodelane`,
     `cclanes`, `songdocument`, `gestures`, `automationdomain` across
     every `CMakeLists.txt` outside `build*/`/`external/` — confirming
     the domain check family and its covered engine sources appear in
     zero targets.
  3. The engine-family blocker chain (spec §8): `src/core/xcmd.h`
     remains included by `src/core/songdocument.h`,
     `src/core/midiimport.cpp`, and dormant `src/ui/editordrawer/*`
     sources; `src/ui/editordrawer/nodelane/*` and `cclanes.*` remain
     included within the dormant editordrawer family. Conclusion:
     no engine deletion in this plan; each family waits for its own
     retirement decision (editcheck plan §8 records the same chain for
     the songdocument core).
  4. Statement that native/QML lanes elsewhere are untouched and remain
     necessary blockers (spec §6).

## Implementation steps

1. Run the zero-includer grep; if any includer remains, STOP and report
   (do not delete around a blocker).
2. Delete `tst_automationdomain.h`.
3. Write `engine-reachability.md` per the contract above with fresh
   command evidence (harness tools only — AGENTS search discipline).
4. Confirm the folder's final content: three proofs + four Swift files
   (`gestures.swift`, `tst_automationdomain.swift`, `xcmd.swift`,
   `xcmdRanges.swift`).

## Acceptance predicate

- NAMED CHECKS (controller, final handoff C3): `deno task verify
  --verbose` PASS (all registered native, Swift and QML harnesses,
  preserving the live checks outside this retired uncompiled C++ family);
  `deno task proof list --area automation/domain` shows all three proofs
  terminal (gestures 66 MATCHED + 1 RETIRED-REPRESENTATION;
  tst_automationdomain 106 + 1; xcmd 62 + 0 — zero PARTIAL/GAP/
  NATIVE-SETUP); `engine-reachability.md` exists with the four records.
- Coverage: the all-harness run proves the retired family's Swift
  predicates and surviving native/QML checks pass together; the proof
  list reconciles the ledger named in spec §1.

## Task-specific constraints

- No CMake change: nothing being deleted was ever listed (spec §7); if
  step 2's fresh audit finds otherwise, STOP and report rather than
  editing build files.
- This task never deletes engine sources; it only records (spec §8).
