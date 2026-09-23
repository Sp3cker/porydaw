# Task 1 — Scale keep-native reachability record (no deletion)

## Context

`scalecheck` is the only registered native lane over editcheck sources
(`src/checks/checkcatalog.cpp:112-115`, handler `runScaleCheck` defined in
`tst_scale.cpp:154`). All 24 proof sites are GAP: no Swift scale API exists
and none is planned — the scale feature belonged to the old widget UI.
Verified reachability (spec §7): `src/porydaw_scale.cpp/.h` is compiled
only by `porydaw_checks` (self-testing); every on-disk consumer
(`src/ui/transportbar.cpp`, `workspaceui.cpp`, `songview.h`,
`songview/scalecontroller.*`, `songview/viewstate.cpp`,
`songview/pianoroll_gestures*.cpp`) is in zero CMake targets; no Swift/QML
reference exists.

Decision (controller, per user): native checks are necessary blockers.
The lane KEEPS executing and the 24 GAP dispositions STAND — GAP is the
honest steady state (no Swift parity exists or is planned). This task
records the reachability evidence in the proof so the ledger states why,
and leaves any feature-retirement decision to the user. No deletion, no
disposition change, no Swift work.

## Exact write set

- `src/checks/editcheck/proof.tst_scale.txt` (Scope section only)

## Prerequisites

None.

## Interface contract

The proof's `Scope` section gains a short reachability paragraph stating:
`porydaw_scale` is compiled only by `porydaw_checks` beside this check;
its on-disk widget consumers are in zero CMake targets; no Swift/QML
counterpart exists; the native lane remains registered and executing;
GAP dispositions reflect absent Swift parity, not pending porting work,
and any retirement of the scale feature (check + implementation) requires
an explicit user decision covering the dormant widget UI. Existing
dispositions, entries, hashes, and verification lines are unchanged.

## Implementation steps

1. Edit only the `Scope` block of `proof.tst_scale.txt` (direct edit;
   `deno task proof show tst_scale` must still parse and the tally must
   remain `GAP 24`).
2. Nothing else. Do not delete files, do not touch `checkcatalog.cpp`,
   `CMakeLists.txt`, or `tst_songdocument.h`, do not reclassify any site.

## Acceptance predicate

- `deno task proof show tst_scale` parses; `deno task proof list --area
  editcheck` still reports scale `MATCHED 0, PARTIAL 0, GAP 24`.
- Controller: `deno task verify --filter scalecheck --verbose` still PASS
  (lane untouched).

## Task-specific constraints

- This task never appears on the retirement success path; Task 13 does
  not depend on it.
- If the user later decides to retire the scale feature, that is a new
  plan (deletion of `tst_scale.cpp/.h`, `src/porydaw_scale.cpp/.h`, the
  registration, and the CMake entries), not an extension of this task.
