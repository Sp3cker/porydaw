# Task 5 — xcmd range family: cuts, remove-only, range moves, expansion (A029-A039, A043-A062)

## Context

The four range/time-family xcmd slots — `xcmdTimeRangeCuts` (A029-A039),
`xcmdRangeRemoveOnly` (A043-A048), `xcmdRangeMoves` (A049-A056),
`xcmdExpansionPaste` (A057-A062) — 31 sites. They land in a new
`xcmdRanges.swift` wired into the timeEdits suite beside
`coreTimeXcmdTimeTraffic` (`TimeChecks.swift:16`): a real ownership seam
(document time-family operations in the suite that already owns xcmd time
traffic), not a line-count split (keep-files-small rule).

This task owns the plan's only intersections with editcheck-plan files:
one line in `src/checks/editcheck/TimeChecks.swift` and one line in
`src/checks/CMakeLists.txt`. Precondition: the editcheck plan's
CMake/TimeChecks chain has settled and been checkpointed (plan.md
baseline policy). If drift is observed in either file at task start,
re-read, anchor by symbol, never revert unrelated hunks.

This slot carries the second report-and-stop risk (spec §5.3): equal-tick
byte order in the ccChain expectations (length pair before volume pair at
tick 192).

## Exact write set

- new `src/checks/automation/domain/xcmdRanges.swift`
- `src/checks/editcheck/TimeChecks.swift` (one line)
- `src/checks/CMakeLists.txt` (one line)

## Prerequisites

None from this plan (wave-1 parallel task; it depends only on the
editcheck-chain precondition above). Consumer contract: Task 6's
certificate cites this file's predicates and its post-edit SHA.

## Interface contract

New file `src/checks/automation/domain/xcmdRanges.swift` (~350 lines,
one concept: xcmd range/time editing over the document):

- `@MainActor func coreTimeXcmdRangeEdits(_ report: CheckReport)` — the
  single entry; runs four sections in original slot order. Wired by one
  line in `runTimeEditsSuite` (`TimeChecks.swift`, immediately after
  `coreTimeXcmdTimeTraffic(report)` at line 16).
- A file-private `XcmdRangeFixture` mirroring Task 3's
  `XcmdDomainFixture` idiom (spec §2.3/§4; same document constructor,
  snapshot/oneEdit/undoToRoot, `setLane`, `insertCc`, `seedBaseline`,
  `ccChain`) — file-private to this file; it does NOT import or duplicate
  Task 3's type (different suite, no shared-module coupling beyond what
  `coreTimeBytes` already provides).
- Registered in `src/checks/CMakeLists.txt` in the `swift_core_check`
  source list immediately after `automation/domain/xcmd.swift` (line 154)
  — one line.

Behavior (cppIDs per slot; fixture values spec §5.3 rows 3, 5-7):

- **Cuts** (`::xcmdTimeRangeCuts`): volume `[(96,34)]` + length
  `[(96,17)]`; `removeTime(TimeRange(startTick: 96, endTick: 192),
  scope: TimeScope(lanes: [volume]))` returns true (A029); volume
  projection empty (A030); bytes at 96 = length pair (A031); undo →
  bytes == pre-cut (A032). Then redo+undo, `clearXcmd`, volume
  `[(96,34)]` + length `[(96,17),(192,18)]`; whole-song scope
  (`TimeScope(wholeSong: true)`, the initializer used at
  `TimeChecks.swift:221`) `removeTime(96..<192)` true (A033); volume
  empty (A034); length `["96:18"]` — the 192 point re-anchored to the cut
  edge (A035); bytes at 96 = `[(sel,0x09),(pay,18)]` (A036); undo →
  bytes (A037); redo → volume still empty (A038) and length still
  `["96:18"]` (A039).
- **Remove-only** (`::xcmdRangeRemoveOnly`): volume
  `[(96,34),(192,35)]` + length `[(96,17)]` + `seedBaseline()`;
  `applyRangeEdit(RangeEdit(removePoints: [<volume@96>, <length@96> from
  lanePoints>]))` → `oneEdit` (A043); volume `["192:35"]` (A044); length
  empty (A045); ccChain `[(0,0x0A,80),(0,0x07,64),(192,sel,0x08),
  (192,pay,35),(288,0x07,48),(384,0x0A,110)]` (A046); undo → bytes
  (A047); redo → bytes == post-edit snapshot (A048).
- **Range moves** (`::xcmdRangeMoves`): length `[(96,17),(192,18)]` +
  volume `[(192,34)]` + seedBaseline; `moveRange(notes: [], points:
  <volume lanePoints>, by: -48)` → oneEdit (A049); ccChain 10 entries
  `[(0,0x0A,80),(0,0x07,64),(96,sel,0x09),(96,pay,17),(144,sel,0x08),
  (144,pay,34),(192,sel,0x09),(192,pay,18),(288,0x07,48),(384,0x0A,110)]`
  (A050); undo → bytes (A051); redo → bytes (A052). `clearXcmd`; length
  same + volume `[(96,34)]`; `moveRange(by: 96)` → oneEdit (A053);
  ccChain with volume pair after both length pairs at 192 (A054); undo
  (A55) / redo (A56) byte equalities.
- **Expansion** (`::xcmdExpansionPaste`): `let newTrack =
  fixture.document.engineTracks.usedTrackCount`;
  `applyRangeEdit(RangeEdit(minimumEngineTrackCount: newTrack + 1,
  addNotes: [NewNote(track: newTrack, tick: 0, pitch: 60, duration: 96,
  velocity: 100)], addPoints: [RangeEdit.LaneInsertion(
  track: newTrack, lane: .controller(Xcmd.echoVolumeLane), points:
  [LaneWrite(tick: 96, value: 34)])]))` → oneEdit (A057);
  `usedTrackCount == newTrack + 1` (A058); volume projection on
  `newTrack` `["96:34"]` (A059); new-track ccChain `[(96,sel,0x08),
  (96,pay,34)]` (A060); undo → bytes (A061); redo → bytes == post-edit
  (A062).

## Implementation steps

1. Create `xcmdRanges.swift` with fixture + entry + four sections; add
   the TimeChecks wiring line and the CMake source line.
2. On A050/A054 order mismatch, report the §5.3 equal-tick finding
   with the observed chain. If the test reproduces the original scenario
   and the gap is in production, use the scoped source correction below;
   never weaken or relabel the expectation.

## Acceptance predicate

- NAMED CHECKS (controller): `deno task verify --filter swiftcore --verbose
  --qt timeEdits` PASS with the four new cppIds present in the PASS
  lines (this also exercises the CMake addition — a missing source line
  fails the build); then `deno task lsp:swift`. Implementer: `deno task
  proof show automation/domain/xcmd.cpp` still parses with `GAP 62`.
- Coverage: the timeEdits run executes all 31 new predicates (they run in
  `runTimeEditsSuite` after `coreTimeXcmdTimeTraffic`); PASS is the
  execution evidence Task 6 cites.

## Task-specific constraints

- Exactly one line each in `TimeChecks.swift` and `CMakeLists.txt`; no
  other editcheck-file changes.
- This task does not touch `xcmd.swift` (parallel wave-1 discipline).
- The ccChain helper admits controllers 7, 10 and the three Xcmd
  controllers only (`xcmd.cpp:57-73` contract) — no other CC traffic
  exists in these fixtures.

## Scoped source correction discovered during execution (Task 5a)

The first timeEdits run passed A049-A052 and A056 but failed A053-A055:
the rightward move returned false; the unchanged volume pair remained at
tick 96, rather than following the length pair at tick 192. This fixture
matches `xcmd.cpp:317-365`. Swift `TimeEditing.moveRange` passed every
XCMD payload to `Xcmd.reconcile`, whose destination-epoch protection
correctly rejects that raw-byte relocation. Native
`SongDocument::moveRange` instead projects known descriptor points and
uses `xcmd::rewritePoints` for their logical move
(`songdocument_range.cpp:251-304`), leaving opaque relocations under
`reconcileRaw`. No relaxation of `Xcmd.reconcile` is valid.

Scoped write set: `src/swift/core/TimeEditing.swift` plus one
consumer-visible mixed-controller regression in Task 5's
`xcmdRanges.swift`. In `moveRange`'s `materialize` pass, classify
projected known payloads into per-chunk `Xcmd.PointWrite` and removal
identities, apply one `Xcmd.rewrite` patch atomically alongside
ordinary event actions; leave raw/opaque actions in `Xcmd.reconcile`.
Reject overlapping patches rather than double-removing a byte.
Native `moveRange` emits logical XCMD patch bytes before moved raw CC
bytes (`songdocument_range.cpp:324-336`); a supplemental fixture moves
volume and CC7 onto an occupied length tick, asserting their exact
same-tick order and undo bytes. Do not add a production hook or alter
the A001-A062 assertions. Acceptance: the corrected timeEdits command
above passes A049-A056 and the mixed-controller ordering regression,
projectSession and full swiftcore pass, then `deno task lsp:swift`;
review source byte ordering, opaque preservation, and mixed-move
atomicity before C1.
