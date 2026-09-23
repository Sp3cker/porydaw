# Task 11 — Document track-suite file: duplicationOwnership, trackRemap publication, globalMetadata

## Context

The remaining `tst_songdocument_document.cpp` track families share the
`--qt eventEdits` verification surface. Land them in ONE new
`DocumentTrackChecks.swift` file, wired from `runEventEditsSuite` (one
call). `EventChecks.swift` is already large — do not grow its families;
existing `trackDuplicateContract`/`trackEditing` stay untouched. In
particular, their cross-fixture global predicates do NOT establish the
entire original `documentGlobalMetadata` scenario (spec §5.7); assert
its complete conjunct and raw cloned events on the original fixture.

C++ references: `documentDuplicationOwnership`,
`documentRemapsAndRaw`, `documentGlobalMetadata`.

## Exact write set

- New: `src/checks/editcheck/DocumentTrackChecks.swift`
- `src/checks/editcheck/EventChecks.swift` (one suite-call line in `runEventEditsSuite`)
- `src/checks/CMakeLists.txt` (one source line)
- `src/checks/editcheck/proof.tst_songdocument_document.txt` (A145-A158 reclassification ONLY)

## Prerequisites

Task 10 settled (CMake chain) + C2 (EventChecks.swift reuse authorized
since C1/C2 committed Task 3/5's work).

## Interface contract

Entry `documentTrackContracts(_ report:)` calling three contracts:

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

- `documentGlobalMetadataContract`: literal two-track fixture matching
  `tst_songdocument_document.cpp:422-482`: chunk 0 track-name `lead`,
  500_000-us typed tempo, 4/2 time signature, program 6 on channel 0,
  note 60 velocity 100 from tick 0 to 24, raw annotation at tick 4,
  loop-start marker `[` at 12, colon marker `:` at 16; chunk 1 program
  7 on channel 1. Before any edit and after duplicate, move copy to
  slot 0, delete slot 0, EACH of three undos, and EACH of three redos,
  assert the original complete `globalsOriginal()` conjunction:
  typed tempo == [(0,500_000)], exactly one typed signature at tick 0
  with numerator 4 and denominatorPower 2, loopStartTick 12 and
  loopEndTick == TimeDefaults.noTick, zero raw tempo metas, one raw
  signature meta, one raw `[` marker and one raw `:` marker over ALL
  chunks. One local predicate may calculate the entire conjunction;
  each stage calls `report.expect` under original cppID (A146, A153,
  A155-A158; A157/158 execute three times each). Assert duplicate
  succeeds (A147), copy channel 2 (A148), clone contains EXACTLY the
  three channel events `(0xC2,0,6)`, `(0x92,0,60,100)`,
  `(0x82,24,60,0)` in order with no conductor/annotation metas
  (A149-A152); assert move returns true (A154). Guard undo/redo
  success before inspecting their checkpoints.

Wiring: `runEventEditsSuite` calls `documentTrackContracts(report)` after
`trackRenameContract(report)`.

Proof edits (this task): A145 GAP→RETIRED-REPRESENTATION with named
no-ingress evidence for the fallible C++ `fixture.stage` operation and
the surviving initial-state predicates in the dedicated contract.
A146-A158 → MATCHED citing the exact executing
`documentGlobalMetadataContract` predicates on the original fixture.
Write `Swift: src/checks/editcheck/DocumentTrackChecks.swift ::
documentGlobalMetadataContract` now; Task 12 attaches `S###` numbers.

## Implementation steps

1. Read the three C++ methods and every cited Swift predicate; verify
   the site-level mapping and original global metadata fixture.
2. Write `DocumentTrackChecks.swift` with all three contracts; wire the
   call and append the CMake line.
3. Reclassify A145-A158 via `deno task proof:edit`.

## Acceptance predicate

- `deno task proof show tst_songdocument_document` parses; A145 is
  RETIRED-REPRESENTATION and A146-A158 MATCHED.
- Controller: `deno task verify --filter=swiftcore --qt eventEdits` PASS
  with the remap/ownership whats executing; `deno task lsp:swift`.
- Harness `grep` for `DocumentTrackChecks.swift` in
  `src/checks/CMakeLists.txt`: exactly one source entry.

## Task-specific constraints

- Do not reclassify any site outside A145-A158.
- A091-A097 (dynamic conductor promotion) and all staging sites OTHER
  THAN A145 stay for Task 12 (RETIRED-REPRESENTATION with the
  `EventEditing.swift :: insertRawEvent` no-remap evidence).
- If channel allocation is not "lowest free", record the observed
  production rule and BLOCKED-report unless it matches the C++ observable.
