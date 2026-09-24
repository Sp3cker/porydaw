# Task 9 — Velocity, time-signature, ruler/loop menus

## Context

The prompts-and-menus family, largest task in the plan (282 sites):
`proof.velocity_prompt.txt` (105 GAP: A001–A105) audits the numeric
velocity prompt — `rollcheck/velocity_prompt.swift` already exists and is
registered, but covers none of these sites yet;
`proof.time_signature_prompt.txt` (6 GAP: A007–A009, A011, A039–A040; 35
NATIVE stay) audits the time-signature prompt's model behavior;
`proof.timemenu.txt` (58 GAP: A002–A004, A015–A018, A024, A026, A033–A047,
A048–A064, A068, A071–A072, A076, A078, A084–A088, A091–A095, A099–A100;
42 NATIVE stay) audits the time context menu; `proof.ruler_loop_menu.txt`
(113 GAP: A001–A113) audits ruler loop markers, two-step undo, enablement,
stale cancel, insert-time dialog. Owners: `VelocityPage` /
`VelocityPromptPolicy` (`src/swift/app/drawer/velocity/`),
`PromptAppearance` (`src/swift/app/drawer/`), `TimeEditing`
(`src/swift/core/`). Consumes Task 5's command-transaction idiom and
Task 6's time-shortcut contracts.

## Exact write set

- `src/checks/rollcheck/velocity_prompt.swift` (extend)
- `src/checks/rollcheck/time_signature_prompt.swift` (new)
- `src/checks/rollcheck/timemenu.swift` (new)
- `src/checks/rollcheck/ruler_loop_menu.swift` (new)
- `src/checks/rollcheck/proof.velocity_prompt.txt`
- `src/checks/rollcheck/proof.time_signature_prompt.txt`
- `src/checks/rollcheck/proof.timemenu.txt`
- `src/checks/rollcheck/proof.ruler_loop_menu.txt`
- `src/checks/CMakeLists.txt` (append three new stems,
  `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (three new suite calls;
  `velocity_prompt` registration already exists — extend scenarios in
  place, keep its call)
- `src/checks/rollqml/tst_SwiftRoll.qml` (adapt; menu/prompt observation
  cases)
- Conditional production-QML adaptations, only where a Swift backend
  change requires them (justify each in the report):
  `src/ui/songview/quick/VelocityPrompt.qml`,
  `src/ui/songview/quick/TimeSignaturePrompt.qml`,
  `src/ui/songview/quick/QuickMenuPanel.qml`,
  `src/ui/songview/quick/RulerControls.qml`

## Prerequisites

Task 5, Task 6 (interfaces only).

## Interface contract

- `@MainActor func runVelocityPromptChecks` (existing name, extended),
  `runTimeSignaturePromptChecks(_:, session:)`, `runTimemenuChecks(_:,
  session:)`, `runRulerLoopMenuChecks(_:, session:)`; `cppID:
  "swiftcore/PianoRoll::<scenario>"` per proof headers.
- Certified contracts: prompt validation (1–127) and commit/cancel
  boundaries, stale-context invalidation, menu action application and
  closure, loop-marker two-step undo, insert-time shift.

## Implementation steps

1. Read all four proofs' sites; port fixtures (tempos, tick positions,
   marker pairs, undo steps) verbatim; one scenario per original case —
   do not generalize prompt/menu variants into shared cases that blur
   transaction boundaries.
2. Extend `velocity_prompt.swift` first (105 sites; existing file keeps
   its name and registration).
3. Write the three new stems; register per spec.md §Registration.
4. Adapt `tst_SwiftRoll.qml` for QML-observable prompt/menu behavior;
   adapt production prompt QML only where a Swift backend requires it.
5. Flip all 282 sites to MATCHED; 35 + 42 NATIVE stay (native prompt
   window/menu obligations); refresh evidence + Tallies.

## Acceptance predicate

All 282 listed sites MATCHED; NATIVE unchanged (35 / 42);
`deno task proof check` passes. NAMED CHECKS — controller:
`deno task verify --filter swiftcore --verbose` and
`deno task verify:qml-roll --verbose`; implementer-local:
`deno task proof check`.

## Task-specific constraints

- Numeric-entry Space-yield and host prompt focus are deferred decisions
  (parity handoff #3): assert model-level validation/commit only; do not
  mark keyboard-delivery assertions.
- This task is scheduled as its own serial wave; no parallel sibling may
  edit `SessionChecks.swift` or `src/checks/CMakeLists.txt` while it runs
  (plan.md shared-integration-files rule).
- Over-cap exception named in plan.md: four stems are one prompt/menu
  family with one verification pair.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task verify:qml-roll --verbose`;
`deno task lsp:swift`.
