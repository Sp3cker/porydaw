# Task 4 — Metadata: certificate + deletion

## Context

After Task 3, every `tst_songdocument_metadata.cpp` observable contract has
an executing Swift predicate or a legitimate terminal mapping (spec §5.4
table). This task terminalizes all 125 sites and deletes the uncompiled
original. Controller gate rules apply in full (spec §2.1): staging and
disk-I/O sites are RETIRED-REPRESENTATION (never MATCHED via non-throwing
construction); `QUndoStack::count()` sites map to `coreEditHistoryCountAtTip`
deltas only.

## Exact write set

- `src/checks/editcheck/proof.tst_songdocument_metadata.txt` (rewrite)
- Delete: `src/checks/editcheck/tst_songdocument_metadata.cpp`

## Prerequisites

Task 3 accepted (its four assertions and two wired contracts are the
predicates cited here).

## Interface contract

All 125 sites terminal:

- **MATCHED (97)** — cite the exact `S###` predicates in the now-wired
  contracts (`xcmdSaveSnapshotContract`, `formatZeroCoercionContract`
  incl. the new A034 predicate, `formatZeroGlobalsContract`,
  `formatZeroSaveRoundTripContract` incl. A051,
  `markerVersusTrackNameContract`, `duplicateLaneAndTempoLoadContract`
  incl. A085/A086, `duplicateCanonicalizationContract`,
  `duplicateReplacementsAndNoOpsContract`) plus the already-MATCHED
  `NoteChecks.swift`/`MidiChecks.swift` mappings (A015/A016, A040, A056,
  A079/A087, A115/A122/A124) and the QUndoStack sites below.
- **MATCHED via history-depth predicates (8)** — A004, A092/A093,
  A100/A101, A109/A110, A119/A120: each cites a
  `coreEditHistoryCountAtTip` stability/delta predicate (or a Task-3/4
  addition if the contract asserts it via count; if the contract only
  asserts `revision`, ADD the countAtTip observation is NOT allowed here —
  this task is proof-only. If no depth predicate exists for a site,
  classify that site RETIRED-REPRESENTATION only if the §7 ingress proof
  covers it, else leave PARTIAL and STOP: report the site).
- **RETIRED-REPRESENTATION (20)** — staging sites (A001, A013, A037,
  A046, A064, A071, A088, A104) and disk-I/O sites (A047/A048, A057-A060,
  A083/A084): mapping lines carry the no-ingress proof — the C++ file is
  uncompiled in every target and unregistered (spec §7); the Swift suite
  constructs documents in memory and stages/saves via
  `SongDocument(file:)`/`captureSave()`/`MidiFile.decode`, never via
  `fixture.stage`/`QTemporaryFile`. Where a surviving observable exists
  (e.g. capture leaves live bytes untouched; unreadable bytes fail the
  throwing decode), name that predicate as corroboration in the mapping
  line without claiming the retired mechanism MATCHED. Two further sites
  (A002 chunk-index plumbing, per-family where the C++ asserted a local
  file handle) follow the same rule.

## Implementation steps

1. Extend the `S###` trailer to index every predicate in the eight
   contracts plus the four Task-3 additions (number sequentially from the
   current last `S###`).
2. Reclassify each of the 116 non-MATCHED sites via
   `deno task proof:edit` per the §5.4 table and the rules above; every
   disposition change updates its mapping line in the same edit.
3. Rewrite the preamble to the certificate format (spec §3), retaining
   the proof's existing `Reference revision` and verifying the
   `Original SHA-256` against the on-disk file before deletion (spec §2.2).
   `Covered native implementation: src/core/songdocument.cpp,
   src/core/songdocument_xcmd.cpp, src/core/songdocument_timeeditor*.cpp
   :: SongDocument xcmd save snapshot, format-0 coercion, globals rescue,
   duplicate canonicalization`. `Registered run path: … EventChecks.swift
   :: runEventEditsSuite -> <contracts>, swiftcore suite 6 …`.
   Counterparts + fresh SHAs for `EventChecks.swift` and any other file
   whose predicates are cited.
4. Delete `tst_songdocument_metadata.cpp`.

## Acceptance predicate

- `deno task proof show tst_songdocument_metadata` parses; tally
  PARTIAL 0, GAP 0 (MATCHED + RETIRED-REPRESENTATION only).
- `deno task proof list --area editcheck` reflects the same.
- Controller: `deno task verify --filter swiftcore --verbose` PASS
  recorded as the certificate Result line.

## Task-specific constraints

- Spot-check 10 reclassified sites against the actual Swift predicate text
  before finalizing (reviewer repeats this); a citation that names a
  predicate which does not assert the site's expression is a failed task.
- The A015/A016 (`MidiChecks.swift`) and A040/A056/A079/A087/A115/A122/A124
  (`NoteChecks.swift`) mappings already exist as MATCHED — do not renumber
  their `S###`s; cite them as-is.
- A site that fits neither MATCHED nor a §7-proven RETIRED-REPRESENTATION
  stays PARTIAL and blocks deletion — report it; never force it.
