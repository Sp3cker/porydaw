# Task 2 — Document, note edits and history

## Context

Make native Swift own editable song state and undo, without porting the C++
command-class architecture. Tasks 3–4 add other semantic edits through the same
private transaction mechanism; task 6 owns the session/service lifecycle.
See [plan.md](plan.md#global-constraints) and
[spec.md](spec.md#document-and-history).

## Exact write set

Create `src/swift/core/SongDocument.swift`, `src/swift/core/SongHistory.swift`,
`src/swift/core/NoteEditing.swift`, `src/checks/swiftcore/NoteChecks.swift`.
Modify `src/swift/core/CMakeLists.txt`, `src/checks/CMakeLists.txt`,
`src/checks/swiftcore/{core_check.h,tst_swiftcore.h,tst_swiftcore.cpp}`.
Read-only oracle: `src/core/songdocument.{h,cpp}`, `src/core/songhistory.{h,cpp}`,
`src/core/songdocument_tempo.cpp`, and `src/checks/editcheck/`.

## Prerequisites

Task 1's `MidiFile`, musical types and Swift-owned check/reporting boundary accepted.

## Interface contract

Produce `SongDocument`, `SongState`, `SongHistory`, `HistoryGroup`,
`DocumentChange`, `TrackRemap`, `SaveSnapshot`, and `BankHistoryAction` as specified.
Implement note queries and all note edit methods in the spec, including explicit
pitch destinations, both resize edges, batch velocity and stable identities.
Expose the native save-capture/identity contract; project I/O is task 6.

The private transaction mechanism stores COW before/after values. No `EventOp`
interpreter, inverse-operation log, public generic command dispatcher, or one
class per edit. Read projections do not become second writable stores.
Implement bank entry ordering/confirmation behavior against its service contract;
real service integration is task 6, not a placeholder bank implementation here.

## Implementation steps

1. Implement adoption, note pairing, track mapping, typed-tempo extraction and
   identity allocation from the existing document behavior. Keep configuration
   and complete underlying MIDI data, not only note fields used by the grid.
2. Implement the shared transaction/history mechanism and note operations.
   Preserve edited-note-wins overlap handling and whole-batch rejection, exact
   duplicate insertions, minimum durations and unterminated-note behavior.
3. Implement repeated-key grouping from the gesture origin, save boundaries,
   undo/redo identity restoration and no-op removal. A returned-to-origin group
   still updates consumers. Snapshot only at actual transaction boundaries.
4. Implement save identity and the confirmed-bank entry variant on the same
   history sequence; bank entries do not dirty document state. Keep native
   replay separate from the core's ordering decision.
5. Implement `noteEdits` and `documentHistory` scenarios and assertions in
   `NoteChecks.swift`, calling production Swift directly. Existing editcheck
   cases supply inputs/expected outcomes and temporary oracle comparisons;
   C++ slot edits are invocation/reporting only.

## Acceptance predicate

A real note edit/gesture, its undo and redo have the same musical data and
identity behavior as the reference. One leading-edge resize or batch operation
is one entry; crossing a neighbor and moving back restores that neighbor;
saving seals merge boundaries and newer edits remain dirty. Controller commands:

```sh
deno task verify --filter swiftcore --verbose --qt noteEdits documentHistory
deno task verify --filter editcheck --filter noteidcheck --verbose
```

The Swift slots use cases from `tst_songdocument_songnotes.cpp`,
`tst_songdocument_songmoves.cpp`, `tst_songdocument_document.cpp` and identity
checks. Project-save I/O and worker-confirmed bank replay are explicit coverage
gaps closed by task 6 before the core milestone, not inferred from this run.

## Task-specific constraints

Do not carry forward feed IDs, save-state-token/revision/identity triples merely
because the C seam had them: keep the identity/revision needed by actual save
completion and consumer behavior. Preserve that behavior with the smallest state.
Do not implement a second history for the session or grid.
