# Task 3 — Metadata: wire contracts, saved bytes, and undo history

## Context

All eight `tst_songdocument_metadata.cpp` families have dedicated Swift
contracts in `EventChecks.swift`, and six are wired into
`runEventEditsSuite` (call list at EventChecks.swift:5-26, verified).
Two are dead code today: `xcmdSaveSnapshotContract` (~line 797) and
`formatZeroGlobalsContract` (~line 940) are defined but called nowhere, so
their predicates never execute — 8+7=15 proof sites cannot be MATCHED while
the contracts are unwired (spec §5.4). Six saved-file/conversion
assertions and nine history-depth/cursor sites still need direct predicates.

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
  `formatZeroGlobalsContract(report)`.
- Six saved-file/conversion assertions (spelling follows each contract's local idiom):
  1. A034 in `formatZeroCoercionContract`: all chunks' `endTick == 48`
     (`document.state.file.chunks.allSatisfy { $0.endTick == 48 }`),
     what: "coerced format-0 chunks close at the encoded end tick".
  2. A051 in `formatZeroSaveRoundTripContract`: saved bytes with the
     tempo meta events stripped equal `convertedLive` (compare
     `MidiFile.decode(snapshot.bytes)` chunk events filtered of
     `metaType == 0x51` re-encoded, against the captured
     `convertedLive` bytes).
  3. A085 in `duplicateLaneAndTempoLoadContract`: the original
     `QCOMPARE(saved.write(), expected.write())` compares the entire saved
     file, not merely tempo precedence. Independently construct expected
     bytes from the pre-save live MIDI with the four typed tempo metas
     inserted at their original ordered event positions; assert exact
     encoded saved-byte equality. Checking only event index 1 can miss a
     channel event placed before the tempo and cannot prove no other bytes
     changed.
  4. A086 in `duplicateLaneAndTempoLoadContract`: live bytes equal the
     pre-save capture (what: "capture leaves live bytes untouched" — reuse
     the `xcmdSaveSnapshotContract` comparison idiom).
  5. A058 in `formatZeroSaveRoundTripContract`: independently decoded
     original fixture retains `wasFormat0 == true`, not merely a flag on
     another codec fixture.
  6. A059 in `formatZeroSaveRoundTripContract`: the independently
     redecoded original file's canonical encoded bytes equal captured
     `snapshot.bytes`. The saved-minus-tempo and tempo-placement
     conjunction alone does not imply this original-to-save equality.
     A060's *second explicit* conversion has no public Swift ingress:
     `MidiFile.decode` already invokes a private converter; Task 4 must
     document that representation difference without mislabeling A059.
- A004, A092/A093, A100/A101, A109/A110, A119/A120:
  assert undo-depth and cursor behavior through public Swift history. At the
  tip, `coreEditHistoryCountAtTip` measures entry count and verifies replay
  restores state/identity; compare counts before and after capture,
  canonicalizing edits, lane no-ops, and tempo no-ops. A100/A101 are after
  undo: count remains one while the cursor returns to zero, with redo
  available. Do NOT call the at-tip helper from that undone position: it
  replays to the tip and changes the cursor. Observe the undone state and
  redo/undo round-trip, restoring its exact state/identity before the next
  edit. Place any traversal after existing revision/publication assertions
  so its undo/redo callbacks cannot satisfy or invalidate those checks.
  Never substitute `document.revision` for a history-depth assertion.

## Implementation steps

1. Read both contract functions fully; confirm their local variable names
   (`report`, document names, captured byte constants) before editing.
2. Add the two suite calls (Interface contract order).
3. Add the six saved-file/conversion assertions under the cppIDs
   `editcheck/EditCheckTest::formatZeroCoercion`,
   `…formatZeroSaveRoundTrip`, `…duplicateLaneAndTempoLoad` respectively.
4. Add the nine public-history observations under their original cppIDs;
   Task 4 maps their exact predicates. No proof edits in this task.

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
- Both saved-byte and history predicates must exercise public API only
  (`document.state.file`, `document.captureSave()`, `MidiFile.decode`,
  `document.history.undoDocument()/redoDocument()/canUndo/canRedo`, and
  `coreEditHistoryCountAtTip`). No test-only hook.
