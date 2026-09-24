# Task 6 — Keyboard transpose, snap nudges, timeline insertion

## Context

`proof.keyboard.txt` carries 94 addressable sites (A001–A028, A030–A031,
A035–A036, A039–A042, A046–A047, A049–A052, A054–A105; 91 GAP + 3 PARTIAL)
auditing keyboard note transposition, keep-visible scrolling, ruler scopes,
time shortcuts, and batch resizing. The 11 NATIVE sites are window-tier
key delivery obligations and stay. Owners: `EditKeyArbiter` /
`EditCommands` (`src/swift/app/commands/`), `NoteCommands`, `PianoGrid`
keep-visible behavior, `TimeEditing` for insertion. Binding user decision
(parity handoff #3): numeric-input Space yield and host-arbitration work
is deferred — do not mark deferred assertions; assert the model-level
routing and document effects only.

## Exact write set

- `src/checks/rollcheck/keyboard.swift` (new)
- `src/checks/rollcheck/proof.keyboard.txt`
- `src/checks/CMakeLists.txt` (append stem, `swift_core_check` only)
- `src/checks/workspace/SessionChecks.swift` (one suite call, original
  slot position)
- `src/checks/rollqml/tst_SwiftRoll.qml` (adapt; QML-observable
  keep-visible scrolling cases)

## Prerequisites

Task 3 (note/selection fixtures interface).

## Interface contract

- `@MainActor func runKeyboardChecks(_ report: CheckReport, session:
  DocumentSession)`; scenarios drive `EditKeyArbiter` decisions and the
  commands they dispatch — normalized key payloads, never raw window
  events (charter INV-3); `cppID: "swiftcore/PianoRoll::<scenario>"`.
- Certified contract: transpose/octave semantics, snap nudge quantum,
  batch resize steps, timeline insert shift, keep-visible scroll clamp.

## Implementation steps

1. Read `deno task proof sites rollcheck/keyboard.cpp`; group sites by
   original scenario; port fixtures (selected pitches, snap ticks,
   expected scroll) verbatim.
2. Write `keyboard.swift`; discharge the 3 PARTIAL conditions by
   completing what their Mapping/reason lines name.
3. Register per spec.md §Registration.
4. Adapt `tst_SwiftRoll.qml` only for keep-visible/scroll observation.
5. Flip the 94 listed sites to MATCHED; leave the 11 NATIVE sites and any
   site whose assertion is deferred keyboard-delivery (report them, do
   not invent coverage); refresh evidence + Tally.

## Acceptance predicate

All 94 listed sites MATCHED; NATIVE unchanged (11); deferred-delivery
sites (if any) reported by id and left in their current disposition;
`deno task proof check` passes. NAMED CHECKS — controller:
`deno task verify --filter swiftcore --verbose` and
`deno task verify:qml-roll --verbose`; implementer-local:
`deno task proof check`.

## Task-specific constraints

- No second dispatcher, no synthetic forwarding, no focus memory
  (AGENTS.md Space exceptions; INV-1/INV-2/INV-3).
- Over-cap exception named in plan.md: one keyboard-behavior family, one
  verification pair.

## Controller verification

`deno task verify --filter swiftcore --verbose` (narrow
`--qt projectSession`); `deno task verify:qml-roll --verbose`;
`deno task lsp:swift`.
