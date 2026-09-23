# Task 6 — Songtracks: certificate + deletion

## Context

After Task 5, all 89 sites of `tst_songdocument_songtracks.cpp` are
coverable: 33 already MATCHED, 29 STALE (contracts exist and were always
wired — the proof was frozen mid-migration), 12 REPRESENTATION, 2 closed
by Task 5's marker assertions, 13 closed by Task 5's corpus rows
(spec §5.5).

## Exact write set

- `src/checks/editcheck/proof.tst_songdocument_songtracks.txt` (rewrite)
- Delete: `src/checks/editcheck/tst_songdocument_songtracks.cpp`

## Prerequisites

Task 5 accepted.

## Interface contract

All 89 sites terminal, each citing an `S###` where a predicate exists:

- STALE reclassifications (29) → MATCHED, citing the existing predicate in
  the wired synthetic contracts:
  - `trackCreateDeleteContract`: A005 (`!voices.isEmpty`), A006
    (`expectEqual(Tick(0), voices.first?.tick)`), A007 (`value == 7`),
    A008/A009 (note contains after add / gone after delete), A010
    (`chunksSortedByTick`).
  - `trackMoveContract`: A022 (`usedTrackCount >= 2`), A030 (time-signature
    5/2 survival; if the predicate asserts only the numerator, add the
    `denominatorPower == 2` conjunct in this task — a one-line Swift
    addition — and note it in the mapping; write set extends to
    EventChecks.swift accordingly).
  - `trackMarkerNameContract`: A042/A043 (loop ticks survive move), A045
    (baseline bytes after undo-all), A046 (name restored), A047/A048 (loop
    ticks restored).
  - `trackRenameContract`: A068 (bare count 0 after clear).
  - `songTimeSignatureContract`: A073-A080, A082.
  - `loopCfgUndoRedoContract`: A085-A089.
- REPRESENTATION (12):
  - A024/A026/A064/A065 → MATCHED citing the exact
    `coreEditHistoryCountAtTip` delta/stability predicates from
    `trackMoveContract`/`trackRenameContract`/Task 5 rows (depth sites
    never map to `revision` — spec §2.1).
  - A013/A021/A052/A059 → MATCHED citing the corpus eligibility staging
    assertions (Task 5 rows).
  - A003/A014 → MATCHED citing the public budget assertions.
  - A037/A062 → RETIRED-REPRESENTATION (non-optional construction /
    non-optional `PlaybackTimeline.build`: no failure branch exists to
    assert; §2.1 hard rule, §7 ingress proof).
- Task 5 closures: A038/A039 → the two new `trackMarkerNameContract`
  predicates; corpus staging 13 (A001/A002, A011/A012, A019/A020, A050/
  A051, A057/A058, A071/A072, A084) → the driver's staging triple
  (throwing decode executes the load observable — §2.3).
- Existing 33 MATCHED unchanged.

## Implementation steps

1. Extend the `S###` trailer for every newly citable predicate (index the
   synthetic contracts' existing predicates, numbering from the current
   last `S###`; include the Task 5 corpus-row predicates in
   `TrackCorpusChecks.swift`).
2. Reclassify the 56 non-MATCHED sites via `deno task proof:edit` per the
   lists above.
3. Certificate preamble per spec §3, retaining the existing `Reference
   revision` and verifying `Original SHA-256` against the on-disk file
   before deletion (§2.2); `Covered native implementation:
   src/core/songdocument.cpp :: SongDocument::addTrack, deleteTrack,
   duplicateTrack, moveTrack, renameTrack, setTimeSig, moveTimeSig,
   deleteTimeSig, setLoopTick, setCfg, canAddTrack`; `Registered run
   path: … EventChecks.swift :: runEventEditsSuite -> track* contracts +
   TrackCorpusChecks.swift :: coreTrackCorpusChecks, swiftcore suite 6 …`.
   Counterparts + fresh SHAs: EventChecks.swift, TrackCorpusChecks.swift,
   tst_songdocument_runner.swift (Shared corpus loader + SHA).
4. Delete `tst_songdocument_songtracks.cpp`.

## Acceptance predicate

- `deno task proof show tst_songdocument_songtracks` parses; PARTIAL 0,
  GAP 0; list command agrees.
- Controller: `deno task verify --filter swiftcore --verbose` PASS recorded.

## Task-specific constraints

- Reviewer samples 12 reclassified sites (4 synthetic-stale, 4 corpus, 4
  representation — including A037/A062 as RETIRED-REPRESENTATION) against
  predicate text; any miscitation fails the task.
- A site that fits neither a real predicate nor a §7-proven retired
  representation stays PARTIAL and blocks deletion — report it.
