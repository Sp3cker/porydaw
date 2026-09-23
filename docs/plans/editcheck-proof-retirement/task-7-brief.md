# Task 7 — Songtime: extract the time-corpus family, complete all four row families

## Context

`coreTimeCorpusChecks` and its four row functions
(`coreTimeRemoveRow` / `coreTimeWholeSongRow` / `coreTimeAutomationRow` /
`coreTimeVoiceRow`, TimeChecks.swift:1858-2042) already run the four
songtime scenarios per corpus song, but miss ~40 original observables
(spec §5.6). `TimeChecks.swift` is 2,042 lines — over review-cohesion
limits — so this task moves the time-corpus family VERBATIM into a new
`TimeCorpusChecks.swift` (~250-300 lines after completion) and closes all
four families' gaps there. Behavior and existing assertions are preserved
exactly; `runTimeEditsSuite` keeps calling `coreTrackCorpusChecks`'s
time counterpart `coreTimeCorpusChecks(report)` unchanged (the function
just lives in a new file, registered in CMake). The songtime proof's
citations/SHAs are refreshed by Task 8's certificate; the interim
location change is expected and handled there.

This task replaces the previous two same-file, same-check slices (old
Tasks 8+9): one behavior change, one verification surface
(`--qt timeEdits`).

## Exact write set

- New: `src/checks/editcheck/TimeCorpusChecks.swift`
- `src/checks/editcheck/TimeChecks.swift` (extraction removal only: delete the moved functions; the `runTimeEditsSuite` call line is unchanged)
- `src/checks/CMakeLists.txt` (1 source line)

## Prerequisites

Task 5 settled (CMake serialization; otherwise independent — runs parallel
with Task 6).

## Interface contract

- Moved verbatim into `TimeCorpusChecks.swift`:
  `coreTimeCorpusChecks` (internal), the four private `coreTime*Row`
  functions, and any helpers used ONLY by them (determine by reference
  search: `coreTimeTempo`, `coreTimeTracksSorted`, and any other
  corpus-only helper move; helpers shared with non-corpus families — e.g.
  `coreTimeBytes`, `coreTimePointShape` if referenced elsewhere — STAY in
  `TimeChecks.swift`; same-module internal access makes either placement
  compile unchanged). `coreRangeCorpusChecks` does NOT move (it belongs
  to the retired songranges certificate).
- CMake: append `editcheck/TimeCorpusChecks.swift` beside the other
  `editcheck/*.swift` entries.

Row completions (under each row's existing per-song `cppID`), from the
C++ originals (tst_songdocument_songtime.cpp:14-120, 122-205):

- `coreTimeRemoveRow`: explicit commit-return assertion (A004); seam lane
  point exists at the seam tick with the last in-range value 40
  (A008/A009 — align fixture arithmetic with the C++ clocks: notes 50/52/
  56, CC7 51/52 values 30/40, span [51,54)); redo restores the rippled
  note (A012).
- `coreTimeWholeSongRow`: rescued 3/2 signature at the closing seam
  (A018/A019); rescued tempo value 150 BPM ==
  `microsecondsPerQuarterNote == 400_000` (A020); shifted note (A021) +
  its undo (A028) and redo (A032) restorations; loop-marker stability
  across removal/undo/redo via
  `PlaybackTimeline.build(state:sampleRate:).loopStartTick/.loopEndTick`
  (A022/A023/A029/A031); `coreTimeTracksSorted` after commit (A017);
  max `endTick` closes by the removed span (A024 — cite the existing
  predicate if already covered, else assert).
- `coreTimeVoiceRow`: full lifecycle — write voice 5 (A036); in-place
  value move to 9 (A037/A038); tick move to `base + step * 6` (A039);
  delete → absent (A040).
- `coreTimeAutomationRow`: interleaved lifecycle — CC7=100 @ clock 2 and
  pitch bend @ clock 3 (value mirrored from the C++ `DOC_CC_BEND` scale);
  tempo 150 @ clock 4; CC7 move to clock 5 value 90 (A046/A047) with bend
  persisting (A048); bend delete (A049); tempo delete with CC7 persisting
  (A050/A051); CC7 delete (A052); count-and-replay round trip: capture
  bytes+tempos before/after the edits, undo exactly the applied-commit
  count → originals (A053/A054), redo the same count → edited captures
  (A055/A056).

## Implementation steps

1. Reference-search every helper the four rows use (harness grep scoped
   to `src/checks/editcheck`); partition corpus-only vs shared.
2. Move the family + corpus-only helpers verbatim; add the CMake line.
3. Complete the four rows per Interface contract (keep existing
   assertions untouched except fixture re-base arithmetic, preserving
   semantics exactly and noting any moved tick expression in the report).
4. No proof edits (Task 8).

## Acceptance predicate

- Harness `grep` for `coreTimeCorpusChecks` scoped to
  `src/checks/editcheck` shows the definition in
  `TimeCorpusChecks.swift` and exactly one call, in
  `runTimeEditsSuite`; `TimeCorpusChecks.swift` appears once in
  `src/checks/CMakeLists.txt`.
- Controller: `deno task verify --filter=swiftcore --qt timeEdits` PASS —
  extraction is behavior-preserving (existing assertions still execute)
  and the new whats appear per song; `deno task lsp:swift` after edits.
- Reviewer cross-checks every A-site listed above against a predicate.

## Task-specific constraints

- Verbatim extraction first, completion second — never rewrite moved
  logic while moving it.
- Count-and-replay undo uses the exact applied-commit count, never a
  `canUndo` drain (pre-existing song history must not unwind).
- Loop-tick observation through the public timeline projection only;
  assert stability of the observed value, not a specific tick, for songs
  with unset markers (C++ sentinel semantics).
