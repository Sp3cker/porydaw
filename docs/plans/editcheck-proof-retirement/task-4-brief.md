# Task 4 — Metadata: certificate + deletion

## Context

After Task 3, every `tst_songdocument_metadata.cpp` observable contract
must have an executing Swift predicate or a justified terminal mapping
(spec §5.4). This task audits all 125 sites and deletes the uncompiled
original only when every site's disposition is defensible. Staging and
disk-I/O sites with proved no-ingress are RETIRED-REPRESENTATION, never
MATCHED via non-throwing construction. `QUndoStack::count()` and
`QUndoStack::index()` sites need actual Swift history depth/cursor predicates,
not revision or the fact that the C++ original is uncompiled.

## Exact write set

- `src/checks/editcheck/proof.tst_songdocument_metadata.txt` (rewrite)
- Delete: `src/checks/editcheck/tst_songdocument_metadata.cpp`

## Prerequisites

Task 3 accepted (its four assertions and two wired contracts are the
predicates cited here).

## Interface contract

All 125 sites must be audited individually:

- MATCHED: cite the exact executing `S###` predicates in the wired
  metadata contracts plus existing `NoteChecks.swift`/`MidiChecks.swift`
  mappings. A034, A051, A058/A059, A085, A086 and the Task-3 history
  require direct, behavior-specific assertions. Do not renumber existing
  MATCHED sites.
- History: A004, A092/A093, A100/A101, A109/A110, A119/A120 require
  observed public Swift history depth/cursor behavior. At-tip count
  assertions alone cannot prove A100/A101 after undo: count stays one while
  index returns to zero and redo becomes available. `revision` is not a
  history-depth proxy.
- RETIRED-REPRESENTATION: identify the specific original staging,
  temporary-file, or chunk-index mechanism and its §7 no-ingress proof;
  mention surviving Swift observables as corroboration without claiming
  the mechanism MATCHED. Never classify a meaningful history or save
  outcome as retired solely because its original check is uncompiled.
- A060 is the C++ second explicit `convertToFormat1(&reloaded)` after
  its decode already converted. Swift `MidiFile.decode` converts
  format-0 once via a private converter with no public second-conversion
  ingress. Only that second invocation is RETIRED-REPRESENTATION;
  A059's original-to-snapshot equality must MATCH a direct predicate.
- Any site that fits neither an actual MATCHED predicate nor a proven
  representation-only retirement stays PARTIAL and blocks deletion. Do
  not force a precomputed count of MATCHED/RETIRED sites.

## Implementation steps

1. Extend the `S###` trailer to index every predicate in the eight
   contracts, including all saved-byte and history observations from
   Task 3 (number sequentially from the current last `S###`).
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

- Audit all nine history sites and at least one additional site from each
  other original family against the actual executing Swift predicate text
  before finalizing; the reviewer repeats this. A citation without the
  site's observable assertion is a failed task.
- The A015/A016 (`MidiChecks.swift`) and A040/A056/A079/A087/A115/A122/A124
  (`NoteChecks.swift`) mappings already exist as MATCHED — do not renumber
  their `S###`s; cite them as-is.
- A site that fits neither MATCHED nor a §7-proven RETIRED-REPRESENTATION
  stays PARTIAL and blocks deletion — report it; never force it.
