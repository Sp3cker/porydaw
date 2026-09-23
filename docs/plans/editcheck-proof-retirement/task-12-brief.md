# Task 12 — Document: certificate + deletion

## Context

After Tasks 9-11 every family of `tst_songdocument_document.cpp` has
executing predicates or legitimate terminal mappings (spec §5.7 table).
This task terminalizes all 250 sites and deletes the largest original.

## Exact write set

- `src/checks/editcheck/proof.tst_songdocument_document.txt` (rewrite)
- `src/checks/editcheck/DocumentTrackChecks.swift` (A098-A100 same-slot move predicates, discovered at certification)
- Delete: `src/checks/editcheck/tst_songdocument_document.cpp`

## Prerequisites

Tasks 9, 10, 11 accepted.

## Interface contract

All 250 sites terminal. Per-family mapping sources: spec §5.7 table +
the Task 9-11 site lists. In summary:

- Existing 16 MATCHED unchanged.
- STALE reclassifications: globalMetadata already done (Task 11);
  velocityAtomic A023-A026; velocityRejects A055;
  duplicateIdentities A064-A069; savedIdentity A103-A104;
  crossingIdentities A162-A163. RemapsAndRaw A098-A100 are
  BEHAVIOR-GAP, not STALE: the existing `trackMoveContract` uses a
  different `cppID`. Add three direct predicates under
  `trackRemapPublicationContract` for rejected same-slot move, unchanged
  revision, and no `onChange` publication after clearing prior changes.
- REPRESENTATION→MATCHED, each citing the exact predicate class:
  history-DEPTH sites (velocityAtomic A030/A049; velocityRejects A061;
  mergedOverlap A211/A218/A225; netZero depth deltas) cite
  `coreEditHistoryCountAtTip` predicates only — `revision` is never a
  depth proxy (spec §2.1); sites where the C++ itself asserted
  `document.revision()` (crossingIdentities A165/A171/A176/A181/A186/A187,
  netZero A195/A199) cite the revision predicates; signal-spy sites
  (velocityAtomic A035/A036/A042/A052; remapsAndRaw A074-A090 via Task
  11; duplicationOwnership A129-A135; netZero A196/A200) cite
  `DocumentChange.trackRemap`/change-count predicates.
- RETIRED-REPRESENTATION (with mapping-line evidence):
  staging sites A001/A010/A022/A053/A063/A073/A101/A109/A145(done)/
  A159/A192/A209 (§2.1 hard rule + §7 ingress proof: `fixture.stage`
  staging exists only in the uncompiled C++ original; Swift constructs
  in memory and no failure branch corresponds);
  DocNote-handle sites A031/A032/A038/A039/A044/A050/A119-A121/
  A160-A161/A193/A198/A210 (`document.note(id)` value reads);
  dynamic conductor promotion A091-A097 (`EventEditing.swift ::
  insertRawEvent` never remaps; explicit track ops only);
  raw-event NoteID tracking A117-A118 (NoteID only on projected Notes);
  load-publication spy sequence A003-A007: C++ `fixture.stage`
  explicitly emits `tracksRemapped` then `documentChanged` at
  revision 1 with one empty-map remap. Swift's non-throwing
  `SongDocument(file:)` finishes before consumers may attach `onChange`,
  and offers no public post-construction load operation, so this
  observer protocol has no Swift ingress. Cite the constructor/state
  representation difference, not an unobserved zero-change predicate;
  A002/A008/A009 still require direct initial-state predicates.
- BEHAVIOR-GAP closures: cite the Task 9-11 predicates.

## Implementation steps

1. Build the complete `S###` trailer indexing every cited predicate across
   `NoteChecks.swift`, `EventChecks.swift`, `DocumentHistoryChecks.swift`,
   `DocumentEditChecks.swift`, `DocumentTrackChecks.swift` (number
   sequentially).
2. Reclassify the 234 non-MATCHED sites via `deno task proof:edit`
   (A145-A158 already done).
3. Certificate preamble per spec §3 with §2.2 revision pinning;
   `Covered native implementation: src/core/songdocument.cpp,
   src/core/songhistory.cpp :: SongDocument::setNotesVelocities,
   duplicateTrack, moveTrack, addTrack, deleteTrack, didSave,
   captureSaveSnapshot, note identity assignment`; `Registered run
   path: … NoteChecks.swift :: runNoteEditsSuite, runDocumentHistorySuite;
   EventChecks.swift :: runEventEditsSuite; DocumentHistoryChecks.swift,
   DocumentEditChecks.swift, DocumentTrackChecks.swift ::
   document<Family>Contracts; swiftcore suites 4-6 …`. Counterparts +
   fresh SHAs for all five Swift files + shared corpus loader if cited.
4. Delete `tst_songdocument_document.cpp`.

## Acceptance predicate

- `deno task proof show tst_songdocument_document` parses; PARTIAL 0,
  GAP 0; `deno task proof list --area editcheck` agrees.
- Controller: `deno task verify --filter swiftcore --verbose` PASS
  recorded.

## Task-specific constraints

- This is the largest proof rewrite: work family by family; after each
  family, `deno task proof show tst_songdocument_document` must parse and
  the family tally must be terminal before moving on.
- Reviewer samples 20 sites (≥1 per family, all four verdict classes).
- A site fitting neither a real predicate nor a §7-proven retired
  representation stays PARTIAL and blocks deletion — report it.
