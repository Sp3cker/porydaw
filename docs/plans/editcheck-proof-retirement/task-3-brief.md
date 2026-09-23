# Task 3 — Metadata: wire two written-but-uncalled contracts, add four assertions

## Context

All eight `tst_songdocument_metadata.cpp` families have dedicated Swift
contracts in `EventChecks.swift`, and six are wired into
`runEventEditsSuite` (call list at EventChecks.swift:5-26, verified).
Two are dead code today: `xcmdSaveSnapshotContract` (~line 797) and
`formatZeroGlobalsContract` (~line 940) are defined but called nowhere, so
their predicates never execute — 8+7=15 proof sites cannot be MATCHED while
the contracts are unwired (spec §5.4). Four further sites need one-line
assertions inside existing contracts.

## Exact write set

- `src/checks/editcheck/EventChecks.swift` only.

## Prerequisites

None. Coordinate with any in-flight sibling owning EventChecks.swift
(spec Global Constraints); Task 5 adds one call line to the same function —
serialize via the controller if parallel.

## Interface contract

- `runEventEditsSuite` gains exactly two calls:
  `xcmdSaveSnapshotContract(report)` placed with the other metadata
  contracts (after `duplicateReplacementsAndNoOpsContract(report)`), and
  `formatZeroCoercionContract(report)`.
- Four new assertions (spelling follows each contract's local idiom):
  1. A034 in `formatZeroCoercionContract`: all chunks' `endTick == 48`
     (`document.state.file.chunks.allSatisfy { $0.endTick == 48 }`),
     what: "coerced format-0 chunks close at the encoded end tick".
  2. A051 in `formatZeroSaveRoundTripContract`: saved bytes with the
     tempo meta events stripped equal `convertedLive` (compare
     `MidiFile.decode(snapshot.bytes)` chunk events filtered of
     `metaType == 0x51` re-encoded, against the captured
     `convertedLive` bytes).
  3. A085 in `duplicateLaneAndTempoLoadContract`: the saved snapshot's
     first chunk begins its events with the tempo meta before any channel
     event (what: "saved file leads with the tempo event").
  4. A086 in `duplicateLaneAndTempoLoadContract`: live bytes equal the
     pre-save capture (what: "capture leaves live bytes untouched" — reuse
     the `xcmdSaveSnapshotContract` comparison idiom).

## Implementation steps

1. Read both contract functions fully; confirm their local variable names
   (`report`, document names, captured byte constants) before editing.
2. Add the two suite calls (Interface contract order).
3. Add the four assertions under the cppIDs
   `editcheck/EditCheckTest::formatZeroCoercion`,
   `…formatZeroSaveRoundTrip`, `…duplicateLaneAndTempoLoad` respectively.
4. No proof edits in this task (Task 4 maps sites).

## Acceptance predicate

- Harness `grep` for `xcmdSaveSnapshotContract\(report\)` and
  `formatZeroGlobalsContract\(report\)` scoped to
  `src/checks/editcheck/EventChecks.swift` shows both calls inside
  `runEventEditsSuite`, with both function definitions still present.
- Controller: `deno task verify --filter=swiftcore --qt eventEdits` passes;
  the suite's assertion count grows (suite-abort guard at
  CoreCheckSupport.swift:147-149 requires nonzero — it will be far beyond);
  `deno task lsp:swift` after edits.

## Task-specific constraints

- Do not modify the bodies of the two contracts beyond what wiring needs
  (nothing) — they are complete; only call them.
- The four assertions must exercise public API only
  (`document.state.file`, `document.captureSave()`, `MidiFile.decode`).
