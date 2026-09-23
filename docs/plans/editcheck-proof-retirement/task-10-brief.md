# Task 10 — Document edit-suite file: velocityAtomic, velocityRejects, duplicateIdentities, tempoEmpty

## Context

Four more `tst_songdocument_document.cpp` families (spec §5.7) share one
verification surface (`--qt noteEdits`, suite 4) and land in ONE new
`DocumentEditChecks.swift` (~200-250 lines), wired from
`runNoteEditsSuite` (1 line). Existing `velocityEditing` and
`saveIdentity` in `NoteChecks.swift` stay untouched (their MATCHED
citations remain valid; Task 12 cites both files). This task absorbs the
velocity families and the NoteChecks half of the duplication/tempo
families; the EventChecks half lives in Task 11.

C++ references: `documentVelocityAtomic`, `documentVelocityRejects`,
`documentDuplicateIdentities`, `documentTempoEmpty`.

## Exact write set

- New: `src/checks/editcheck/DocumentEditChecks.swift`
- `src/checks/editcheck/NoteChecks.swift` (1 suite-call line in `runNoteEditsSuite`)
- `src/checks/CMakeLists.txt` (1 source line)

## Prerequisites

Task 9 accepted + C2 (`NoteChecks.swift` reuse; CMake chain).

## Interface contract

Local `twoTrackFile()` fixture literal (as Task 9; do not widen
`NoteChecks.swift` visibility). Entry `documentEditContracts(_ report:)`
calling:

- `documentVelocityAtomicContract`: batch
  `setVelocities([note0 → 0], [note1 → 200], [note0 → 99], expectedRevision:)`
  → last-write-wins note0=99, note1 clamped 127 (corroborating the
  existing MATCHED sites); undo → 100/90 restored, one change per replay
  with `trackRemap == nil` (A037, A040-A041, A043, A045); redo → 99/127;
  depth +1 via `coreEditHistoryCountAtTip` (A030/A049); zero-clamp
  commit `setVelocities([note0 → 0])` → floor 1, depth +1 (A046-A048,
  A051).
- `documentVelocityRejectsContract`: stale-revision single + multi-entry
  rejects → nil (corroborates A054/A056); no-op same-value commit:
  capture depth (`coreEditHistoryCountAtTip`), bytes, onChange count;
  `setVelocities([both → current], expectedRevision:)` → returns current
  revision (A057-A058), bytes equal (A059), revision unchanged (A060),
  zero changes (A062), depth unchanged (A061 — helper re-called; never
  inferred from revision).
- `documentDuplicateIdentitiesContract`: `duplicateTrack(0)` on the
  two-note fixture; capture `notes(in: copy).map(\.id)`; undo → copy
  gone; redo → notes back with EXACTLY the captured IDs (A071/A072).
- `documentTempoEmptyContract`: empty-typed-tempo document:
  `PlaybackTimeline.build(state:sampleRate: 48_000).tempoMap` == single
  (tick 0, 120 BPM) (A012-A013); `editTempo(TempoEdit(add: [150 BPM @
  24]))` then remove → empty; undo → present; redo → empty (A014-A018);
  `MidiFile.decode(try captureSave().bytes)` chunk scan: zero
  `metaType == 0x51` (A019-A021).

## Implementation steps

1. Read the four C++ methods, `velocityEditing`, `saveIdentity`,
   `NoteEditing.swift :: setVelocities`, and `SongDocument.swift ::
   commit` (`differs(from:)` short-circuit) before writing.
2. Write `DocumentEditChecks.swift` per Interface contract; wire the
   call; append the CMake line.
3. No proof edits (Task 12).

## Acceptance predicate

- Controller: `deno task verify --filter=swiftcore --qt noteEdits` PASS
  with the four contracts' whats executing; `deno task lsp:swift`.
- Reviewer cross-checks A022-A072 (velocity/duplicate families) and
  A010-A021 against predicates.
- Harness `grep` for `DocumentEditChecks.swift` in
  `src/checks/CMakeLists.txt`: exactly one source entry.

## Task-specific constraints

- Velocity floor: read `NoteEditing.swift` clamping first; the C++
  asserted 0 → 1 — assert only what production guarantees.
- If the no-op commit publishes or advances revision/depth, STOP and
  report — production no-op short-circuit regression; BLOCKED with
  observations.
- Depth via `coreEditHistoryCountAtTip` only; revision cited only where
  the C++ itself asserted revision (spec §2.1).
