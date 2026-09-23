# Task 8 — Songtime: certificate + deletion

## Context

After Task 7 all 56 sites of `tst_songdocument_songtime.cpp` are
coverable: 7 MATCHED, 3 STALE, 6 REPRESENTATION, 40 closed by the
completed rows in `TimeCorpusChecks.swift` (spec §5.6).

## Exact write set

- `src/checks/editcheck/proof.tst_songdocument_songtime.txt` (rewrite)
- Delete: `src/checks/editcheck/tst_songdocument_songtime.cpp`

## Prerequisites

Task 7 accepted.

## Interface contract

All 56 sites terminal with `S###` citations:

- 7 existing MATCHED unchanged (their predicates moved files in Task 7 —
  update the citation locations to `TimeCorpusChecks.swift` where the
  proof referenced `TimeChecks.swift`; predicates themselves unchanged).
- STALE (3): A018/A019 cite the whole-song row's rescued-signature
  predicate under the correct cppID; A026 cites the row's undo-bytes
  predicate.
- REPRESENTATION (6): A010/A025 cite `coreEditHistoryCountAtTip` +1 deltas
  in the rows; A053-A056 cite the count-and-replay byte/tempo predicates
  — mapping lines state the QUndoStack-index representation is replaced
  by public replay.
- 40 row closures: cite the exact predicate per the Task 7 site lists;
  corpus staging triples (A001-A003, A013-A015, A033-A035, A041-A043)
  cite the driver's staging assertions.

## Implementation steps

1. Index the completed rows' predicates into the `S###` trailer
   (locations: `TimeCorpusChecks.swift`).
2. Reclassify the 49 non-MATCHED sites via `deno task proof:edit`.
3. Certificate preamble per spec §3 with §2.2 revision pinning;
   `Covered native implementation: src/core/songdocument_range.cpp,
   src/core/songdocument_timeeditor*.cpp, src/core/songdocument_xcmd.cpp
   :: SongDocument::removeTimeRange, addLanePoint, moveLanePoints,
   deleteLanePoints, applyTempoEdit, loopTick`; `Registered run path: …
   TimeChecks.swift :: runTimeEditsSuite -> TimeCorpusChecks.swift ::
   coreTimeCorpusChecks -> <rows>, swiftcore suite 9 …`. Counterparts +
   fresh SHAs: TimeChecks.swift, TimeCorpusChecks.swift,
   EventChecks.swift (laneEditing citations if used),
   tst_songdocument_runner.swift (Shared corpus loader + SHA).
4. Delete `tst_songdocument_songtime.cpp`.

## Acceptance predicate

- `deno task proof show tst_songdocument_songtime` parses; PARTIAL 0,
  GAP 0; list agrees.
- Controller: `deno task verify --filter swiftcore --verbose` PASS
  recorded in the Result line.

## Task-specific constraints

- Reviewer samples 10 sites (3 stale, 2 representation, 5 row closures)
  against predicate text.
- Do not touch `coreRangeCorpusChecks` or its citations (songranges is
  already retired).
