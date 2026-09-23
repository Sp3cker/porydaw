# Task 5 — Track corpus complete: CMake source, driver, all seven row families, two marker assertions

## Context

Seven of eight `tst_songdocument_songtracks.cpp` families were corpus
data-row tests in C++ (capability-gated over the 14 staged songs, spec
§2.3); the Swift contracts run only synthetic fixtures. The corpus
dimension must be preserved for retirement (the four accepted certificates
all kept it). This task delivers it as ONE behavior change on ONE
verification surface (`--qt eventEdits`), following the
`NoteMoveCorpusChecks.swift:5-57` pattern (per-song path/load/track
staging triple, `rows > 0` sentinel, distant-base offsets), plus the two
trivial in-synthetic gaps (A038/A039) in `trackMarkerNameContract`.
Audited site coverage: spec §5.5 (13 corpus staging sites; eligibility
sites A003/A013/A021/A052/A059/A022/A014; undo-depth sites A024/A026/
A064/A065 → `coreEditHistoryCountAtTip`).

File-ownership: all new code lives in the new `TrackCorpusChecks.swift`
(150-400 lines; the two A038/A039 assertions land inside the existing
`trackMarkerNameContract` in `EventChecks.swift` — they belong to that
contract). `EventChecks.swift` gains exactly one suite-call line;
`src/checks/CMakeLists.txt` gains exactly one source line. This task is
the sole CMake writer until it settles (plan §file-ownership policy).

## Exact write set

- New: `src/checks/editcheck/TrackCorpusChecks.swift`
- `src/checks/editcheck/EventChecks.swift` (1 suite call + 2 assertions in `trackMarkerNameContract`)
- `src/checks/CMakeLists.txt` (1 source line in `swift_core_check`)

## Prerequisites

Task 3 accepted + C1 (EventChecks.swift reuse authorized).

## Interface contract

```swift
// TrackCorpusChecks.swift — corpus rows for tst_songdocument_songtracks.cpp
@MainActor internal func coreTrackCorpusChecks(_ report: CheckReport)
// private row functions:
coreTrackCreateDeleteRow(_ report:, _ document: SongDocument, _ id: String) throws
coreTrackDuplicateRow(...) throws
coreTrackMoveRow(...) throws
coreTrackDeleteRescueRow(...) throws
coreTrackRenameRow(...) throws
coreSongTimeSignatureRow(...) throws
coreLoopCfgUndoRedoRow(...) throws
// eligibility helper:
firstNoteTrack(_ document: SongDocument) -> Int?   // mirrors NoteMoveCorpusChecks.firstNoteTrack
```

CMake: append `editcheck/TrackCorpusChecks.swift` to the `swift_core_check`
`add_library` source list in `src/checks/CMakeLists.txt`, beside the
existing `editcheck/*.swift` entries (lines 118-141). Plain source append
per qt-cmake-project conventions; no new targets, no property changes.

Driver semantics (mirror `coreNoteMoveCorpusChecks`): per
`coreEditCorpusSongs(report)` row, decode + construct `SongDocument`; skip
songs with no note track (EditableTrack classification); count rows,
assert `rows > 0` under `editcheck/EditCheckTest::addSongRows`. Per
family, per song, id = `editcheck/EditCheckTest::<method>[<label>]` with
the staging triple (path non-empty; fresh document via throwing
`MidiFile.decode` in a do/catch that `report.fail`s; note-track exists).
Eligibility gates reproduce `SongCapability`: create/duplicate families
additionally assert `usedTrackCount < trackBudget` (A003/A014); move
asserts `usedTrackCount >= 2` (A022). A family finding zero eligible songs
across the corpus `report.fail`s (never vacuous).

Row behaviors (distant base `coreEditDistantBase(document)`, step =
ticksPerBeat/clocksPerBeat; C++ refs tst_songdocument_songtracks.cpp:36-135,
188-326):

- `coreTrackCreateDeleteRow` (36-57): `addTrack(voice: 7)` non-nil; lane
  points non-empty, front tick 0, value 7; `addNotes` one note found in
  `notes(in:)`; `deleteTrack`; note gone; `chunksSortedByTick`.
- `coreTrackDuplicateRow` (69-86): budget assertion; source note shapes of
  track 0; `duplicateTrack(0)` non-nil ≠ 0; copied shapes equal;
  `deleteTrack(copy)`; sorted invariant.
- `coreTrackMoveRow` (98-135): no-op `moveTrack(0, to: 0)` false with
  `coreEditHistoryCountAtTip` unchanged (A024); real move true with count
  +1 (A026); notes/channel survive at `last`; single undo restores
  track-0 notes; redo + move back returns them.
- `coreTrackDeleteRescueRow` (188-204): loop ticks via
  `PlaybackTimeline.build(...).loopStartTick/loopEndTick`; `deleteTrack(0)`
  leaves them; `undoDocument()` leaves them.
- `coreTrackRenameRow` (216-255): rename to "editcheck name" (name set,
  bare 0x03 count 1); trimmed rename and marker-shaped `"["`/`" ][ "`
  leave `coreEditHistoryCountAtTip` unchanged and name intact
  (A064/A065/A066); clear → empty name, count 0; undo restores; redo
  clears.
- `coreSongTimeSignatureRow` (267-292): 3/3 → exists; replace 7/2 →
  exists with count +1 via `coreEditHistoryCountAtTip`; move → source
  cleared, destination 7; delete → cleared.
- `coreLoopCfgUndoRedoRow` (306-326): baseline bytes; `setLoop(end:
  false, tick:)`; sorted invariant; flip `masterVolume` via `setConfig`;
  drain-undo → baseline bytes + original volume; drain-redo → bytes ≠
  baseline; drain-undo → baseline.

Synthetic additions in `trackMarkerNameContract` (EventChecks.swift),
under `editcheck/EditCheckTest::trackMarkerName`, after construction:
`report.expect(document.engineTracks.usedTrackCount >= 2, …)` (A038) and
`report.expectEqual(0, document.engineTracks.tracks[0].midiChunk, …)`
(A039).

## Implementation steps

1. Read `NoteMoveCorpusChecks.swift` and
   `tst_songdocument_songtracks.cpp:36-326` fully; mirror idioms.
2. Write `TrackCorpusChecks.swift` (driver + 7 rows + helper).
3. Add `coreTrackCorpusChecks(report)` to `runEventEditsSuite` after
   `trackRenameContract(report)`; add the two marker assertions.
4. Append the CMake source line.
5. No proof edits (Task 6 maps sites).

## Acceptance predicate

- Harness `grep` for `TrackCorpusChecks.swift` scoped to
  `src/checks/CMakeLists.txt` shows exactly one `swift_core_check` source
  entry.
- Controller: `deno task verify --filter=swiftcore --qt eventEdits` PASS —
  builds the CMake change (missing entry fails the link) and executes all
  seven row families per song; `deno task lsp:swift` after Swift edits.
- Reviewer cross-checks each row against the C++ sequence (site lists in
  spec §5.5 and the Task 6 brief).

## Task-specific constraints

- No synthetic duplication of the corpus families; no skipping eligible
  songs; the `rows > 0` / family-vacuity guards are mandatory.
- Depth assertions use `coreEditHistoryCountAtTip` before/after — never
  `document.revision` as a depth proxy (spec §2.1).
- Drain loops use `while document.history.canUndo { … }` — never an index
  property.
- One new Swift file + one CMake line + the two in-contract assertions;
  no other EventChecks.swift changes, no CMake reordering.
