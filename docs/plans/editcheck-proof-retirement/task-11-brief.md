# Task 11 — Document track-suite file: duplicationOwnership, trackRemap publication + globalMetadata reclassification

## Context

The remaining `tst_songdocument_document.cpp` families share one
verification surface (`--qt eventEdits`, suite 6) and land in ONE new
`DocumentTrackChecks.swift` (~150-200 lines), wired from
`runEventEditsSuite` (2 lines). `EventChecks.swift` is 1,231 lines — no
family growth there; existing `trackDuplicateContract`/`trackEditing`
stay untouched (their MATCHED citations remain valid). This task absorbs
the EventChecks half of the duplication families plus the
remaps/reclassification work.

C++ references: `documentDuplicationOwnership`,
`documentRemapsAndRaw`, `documentGlobalMetadata`.

## Exact write set

- New: `src/checks/editcheck/DocumentTrackChecks.swift`
- `src/checks/editcheck/EventChecks.swift` (2 suite-call lines in `runEventEditsSuite`)
- `src/checks/CMakeLists.txt` (1 source line)
- `src/checks/editcheck/proof.tst_songdocument_document.txt` (A145-A158 reclassification ONLY)

## Prerequisites

Task 10 settled (CMake chain) + C2 (EventChecks.swift reuse authorized
since C1/C2 committed Task 3/5's work).

## Interface contract

Entry `documentTrackContracts(_ report:)` calling:

- `documentDuplicationOwnershipContract`: 16-channel-budget fixture
  mirroring the C++ (track 1 note 60 ch1 + foreign ch0 event; tracks
  2-15 on ch2-15): `duplicateTrack` copy's channel == lowest free
  channel (`document.engineTracks.tracks[copy].channel`, A110/A122);
  remap payload counts via an `onChange` recorder (`DocumentChange
  .trackRemap` non-nil with expected counts, A129-A135); at ceiling
  (`usedTrackCount == trackBudget`) `duplicateTrack` returns nil and
  `addTrack` returns nil (A136-A142); undo-then-redo of a duplication
  keeps the copied note findable with matching tick (A143-A144).
- `trackRemapPublicationContract`: twoTrackFile fixture (3 SMF chunks, 2
  engine tracks), `onChange` recorder: `moveTrack(0, to: 1)` publishes a
  non-nil `trackRemap` with the moved mapping; undo/redo each publish a
  remap (A074-A077); `addTrack(voice: 3)` remap with
  `usedTrackCount` before/after (A079-A083); `deleteTrack(2)`,
  `duplicateTrack(0)` same pattern (A084-A088); `insertRawEvent` (meta)
  publishes `trackRemap == nil` (A089-A090).

Wiring: `runEventEditsSuite` gains `documentTrackContracts(report)` after
`trackRenameContract(report)`.

Proof edits (this task): reclassify A145-A158 to MATCHED citing existing
predicates — `NoteChecks.swift :: adoptionAndPairing` conductor-tempo
assertions + `EventChecks.swift :: trackEditing` conductor signature/
marker counts (A145-A148); `trackDuplicateContract` (engine duplication
never touches chunk 0), `trackMoveContract` tempo/signature/loop
survival, `trackDeleteRescueContract` loop survival, drain-undo/redo
baseline restoration (A149-A158). Write citations as
`Swift: <file> :: <function>` now; Task 12 attaches `S###` numbers.

## Implementation steps

1. Read the three C++ methods and every cited Swift predicate; verify
   each mapping asserts the site's expression (sample all 14 sites).
2. Write `DocumentTrackChecks.swift`; wire the call; append the CMake line.
3. Reclassify A145-A158 via `deno task proof:edit`.

## Acceptance predicate

- `deno task proof show tst_songdocument_document` parses; A145-A158 all
  MATCHED.
- Controller: `deno task verify --filter=swiftcore --qt eventEdits` PASS
  with the remap/ownership whats executing; `deno task lsp:swift`.
- Harness `grep` for `DocumentTrackChecks.swift` in
  `src/checks/CMakeLists.txt`: exactly one source entry.

## Task-specific constraints

- Do not reclassify any site outside A145-A158.
- A091-A097 (dynamic conductor promotion) and staging sites stay for
  Task 12 (RETIRED-REPRESENTATION with the
  `EventEditing.swift :: insertRawEvent` no-remap evidence).
- If channel allocation is not "lowest free", record the observed
  production rule and BLOCKED-report unless it matches the C++ observable.
