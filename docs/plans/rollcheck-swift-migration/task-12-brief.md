# Task 12 — Ready/gated channel transitions

## Context

`static/proof.gate.txt` carries 9 addressable sites (A025, A028, A033,
A037, A038, A061, A063, A066, A068; 2 GAP + 7 PARTIAL) auditing
ready/gated channel state transitions. The other 73 sites are NATIVE
(window/framebuffer gate obligations) and stay — **including blockers
A076–A082** (ruler-tooltip floating hover/leave geometry; would need a new
QML file, which is prohibited). The PARTIAL sites relate to the
`runEditorCameraChecks` predicates already executed in suite 10 (per the
proof's "Execution and ownership" note). QML observation rides the
existing `tst_SwiftRollWindowing.qml`.

## Exact write set

- `src/checks/rollcheck/static/gate.swift` (new)
- `src/checks/rollcheck/static/proof.gate.txt`
- `src/checks/CMakeLists.txt` (append stem, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (one suite call, original
  slot position)
- `src/checks/rollqml/tst_SwiftRollWindowing.qml` (adapt; gated-state
  observation cases)

## Prerequisites

Task 1 (camera/viewport contract the gate observations ride on).

## Interface contract

- `@MainActor func runGateChecks(_ report: CheckReport)`; scenarios
  assert the gate-slot state transitions the original observed, at
  presenter/model level; `cppID: "swiftcore/PianoRollStatic::<scenario>"`
  or the original class name from the proof header.
- Certified contract: ready→gated→ready transition ordering and the
  state visible to the QML surface per adapted case.

## Implementation steps

1. Read `deno task proof sites rollcheck/static/gate.cpp` for the 9
   addressable sites; extract each transition's trigger and expected
   state verbatim.
2. Write `gate.swift`; the 7 PARTIAL sites flip only when their named
   unproved condition (execution/observation of the transition) is
   discharged by an executing assertion.
3. Register per spec.md §Registration.
4. Adapt `tst_SwiftRollWindowing.qml` where the transition must be
   observed through the existing QML surface.
5. Flip the 9 listed sites to MATCHED; leave all 73 NATIVE sites
   (including A076–A082) untouched; refresh evidence + Tally.

## Acceptance predicate

All 9 listed sites MATCHED; NATIVE unchanged (73), A076–A082 untouched;
`deno task proof check` passes. NAMED CHECKS — controller:
`deno task verify --filter swiftcore --verbose` and
`deno task verify:qml-roll --verbose`; implementer-local:
`deno task proof check`.

## Task-specific constraints

- Do not mount `RulerToolTip.qml` anywhere and do not create a QML file
  to chase A076–A082; they are permanent blockers of this plan.
- Final handoff: after this task the controller runs the whole-plan gate
  in plan.md §"Verification policy".

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task verify:qml-roll --verbose`;
`deno task lsp:swift`; then the final whole-plan gate
(`deno task proof check`; `deno task proof list --area rollcheck`).
