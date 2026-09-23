# Task 9 — Document history-suite file: loadPublication, savedIdentity, netZero, crossingIdentities, mergedOverlap

## Context

Five of the twelve `tst_songdocument_document.cpp` families (spec §5.7)
share one verification surface (`--qt documentHistory`, suite 5) and one
concept (document publication/history observables). Swift construction
finishes before an `onChange` callback can be attached; unlike C++'s
explicit `adoptSmf`/`load`, there is no public load operation that emits
the original load-time signal sequence. The constructed state/revision
remain observable. `isDirty` = identity ≠ saved; `SongHistory` coalesces
`HistoryGroup` moves and drops
origin entries. `NoteChecks.swift` is 526 lines and this adds ~150-200 —
so the five contracts land in ONE new `DocumentHistoryChecks.swift`
(~300 lines), wired from `runDocumentHistorySuite` (1-2 call lines).
Existing `gestureAndIdentityHistory`/`saveIdentity` stay untouched in
`NoteChecks.swift` (their MATCHED citations remain valid; Task 12 cites
both files). This task replaces what was previously two same-file,
same-check slices (the publication/history families and the gesture
families).

C++ references: document.cpp `documentLoadPublication`,
`documentSavedIdentity`, `documentPublicationNetZero`,
`documentCrossingIdentities`, `documentMergedOverlapPublication`.

## Exact write set

- New: `src/checks/editcheck/DocumentHistoryChecks.swift`
- `src/checks/editcheck/NoteChecks.swift` (1-2 suite-call lines in `runDocumentHistorySuite`)
- `src/checks/CMakeLists.txt` (1 source line)

## Prerequisites

Task 7 settled (CMake chain); fresh `NoteChecks.swift` writer (no prior
editor in this plan), so no checkpoint dependency beyond the CMake chain.

## Interface contract

Local `twoTrackFile()` fixture literal (division 24, format 1, conductor +
two-note track velocities 100/90 + program track — mirror the C++; do NOT
widen `NoteChecks.swift` visibility). Five private contract functions +
one entry:

- `documentHistoryContracts(_ report:)` calling, in order:
- `documentLoadPublicationContract`: construct; assert `revision == 1`
  (A002), `state.file.chunks.count == 3` and
  `engineTracks.usedTrackCount == 2` (A008/A009). The C++ original
  emits `tracksRemapped` then `documentChanged` at revision 1 during
  `fixture.stage`, with one empty-map remap (A003-A007). Swift cannot
  install `onChange` before `SongDocument(file:)` finishes, and has no
  post-construction load ingress; Task 12 records that signal protocol
  as RETIRED-REPRESENTATION. Do **not** test a freshly installed empty
  callback counter; that would assert only the test setup, not loading.
- `documentSavedIdentityContract`: `didSave(captureSave())` → clean
  (A102); edit → dirty (A103); snapshot differs from saved (A104); undo
  → clean (A105); redo → dirty (A106); re-save; undo away → dirty
  (A107); redo back → clean (A108).
- `documentPublicationNetZeroContract`: conductor + note 70 (d4) +
  note 69 (d2); onChange counter + bytes baseline; move 69 key+1 → one
  change, `trackRemap == nil`, `coreEditHistoryCountAtTip` baseline+1
  (A194-A197); inverse move → `!canUndo && !canRedo`, bytes == baseline,
  revision == inverse+1, changes +1 (A198-A203); frozen probes:
  `undoDocument()`/`redoDocument()` return false with revision, bytes,
  change count unchanged (A204-A208).
- `documentCrossingIdentitiesContract`: unterminated notes 60/61 @ tick 0
  (`idA`, `idB`); move A +1 (both 61), move B -1 (A61/B60) with pitch
  assertions per move (A166-A175); undo ×2 (61/61 → 60/61) and redo ×2
  (61/61 → 61/60) (A177-A185); ID findability after every step; depth
  deltas via `coreEditHistoryCountAtTip` (A164/A170); revision
  predicates only for the C++ revision sites (A165/A171/A176/A181/A186/
  A187).
- `documentMergedOverlapContract`: conductor + note 70 (d4) + note 69
  (d2); onChange counter; baseline depth+bytes. Mergeable move 1 (group):
  69 → 70, survivor tail-trim d2, one change, `trackRemap == nil`, depth
  baseline+1 (A211-A217); moves 2-3 (same group): → 71, → 72, survivor
  restored to d4 from origin, depth STILL baseline+1 (A218-A231); single
  undo reverts all three (A232-A234); redo → 72 (A235-A237); unmerged
  move 4 → 73: depth baseline+2; undo → 72; redo → 73 (A238-A250).

Wiring: `runDocumentHistorySuite` gains
`documentHistoryContracts(report)` (one line; or two if reviewer prefers
splitting the entry — one line is the default).

## Implementation steps

1. Read the five C++ methods, `gestureAndIdentityHistory`, `saveIdentity`,
   and `SongHistory.swift` origin-drop logic before writing.
2. Write `DocumentHistoryChecks.swift` per Interface contract; wire the
   call; append the CMake line.
3. No proof edits (Task 12).

## Acceptance predicate

- Controller: `deno task verify --filter=swiftcore --qt documentHistory`
  PASS with the five contracts' whats executing; `deno task lsp:swift`
  after Swift edits.
- Reviewer cross-checks A001-A009, A101-A108, A159-A191, A192-A250
  against predicates.
- Harness `grep` for `DocumentHistoryChecks.swift` in
  `src/checks/CMakeLists.txt`: exactly one source entry.

## Task-specific constraints

- `onChange` counting self-contained (install, count, restore nil) — no
  production observation API.
- Gesture grouping via the production `HistoryGroup` parameter only.
- If depth is NOT constant across mergeable moves 2-3, or the origin
  return does NOT empty the history, STOP and report — potential
  production coalescing divergence; BLOCKED with observations, no test
  accommodation.
