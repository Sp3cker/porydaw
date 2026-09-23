# Task 3 — xcmd lane CRUD: canonical edits and sweep (A001-A009, A040-A042)

## Context

All 62 `proof.xcmd.txt` sites are GAP; none is closable by the existing
minimal-fixture predicates (spec §5.3). This task lands the shared xcmd
check fixture and the first two slot ports, closing 12 sites:
`xcmdCanonicalEdits` (A001-A009) and `xcmdSweepPreservesNotes`
(A040-A042). Consumer contract for later tasks: Task 4 appends the
opaque-epoch slot *inside* the entry function this task creates, and
Task 6's certificate cites these predicates' `S` entries — name and place
them exactly as specified here.

The predicates run in the projectSession suite beside
`drawerAutomationXcmdParity`, the established home of this folder's
document-level domain rows (spec §2.4).

## Exact write set

- `src/checks/automation/domain/xcmd.swift` (append-only)
- `src/checks/automation/AutomationPageChecks.swift` (one line)

## Prerequisites

None (wave-1 task; in particular no CMake or editcheck-file dependency).

## Interface contract


- `private struct XcmdDomainFixture` — the document-fixture idiom of
  `DrawerDomainCheckFixture` (`tst_automationdomain.swift:405-499`),
  specialized for xcmd: `let document: SongDocument` built from
  `MidiFile(division: 24, chunks: [MidiChunk(events:
  [.channel(status: 0xC0, data0: 0)], endTick: 9216)])`; `snapshot`
  (bytes via `try! document.captureSave().bytes`, `revision`,
  `history.currentIdentity`); `oneEdit(_:) -> Bool` (revision+1 and
  changed identity); `setLane(_ controller: UInt8, _ points: [(Tick,
  Int)])` → `document.writeLane(track: 0, lane: .controller(controller),
  from: 0, through: TimeDefaults.noTick, points: …)`; `insertCc(_ tick:
  Tick, _ controller: UInt8, _ value: UInt8)` → `insertRawEvent`;
  `clearXcmd()` (empty writeLane on both echo lanes);
  `seedBaseline()` (CC10 `[(0,80),(384,110)]`, CC7 `[(0,64),(288,48)]`);
  `points(_ controller:) -> [String]` via `document.lanePoints(track: 0,
  lane:)` shaped `"\(tick):\(value)"`; `xcmdBytes(at:) -> [(UInt8,
  UInt8)]` and `xcmdBytes() -> [(UInt8, UInt8)]` filtering
  `document.rawChunks[0].events` for `0xB0` status and controllers in
  `{Xcmd.selectorController, Xcmd.payloadController,
  Xcmd.alternatePayloadController}` at the tick / anywhere (the
  `xcmd.cpp:24-55` contract); `ccChain() -> [(Tick, UInt8, UInt8)]`
  additionally admitting controllers 7 and 10 (`xcmd.cpp:57-73`);
  `notes() -> [(Tick, UInt8, UInt8, UInt8)]` note-event tuples
  (tick, status nibble, key, velocity) from `document.notes(in: 0)`
  events; `undoToRoot() -> Bool` (repeat `history.undoDocument()` while
  it returns true).
- `@MainActor func drawerAutomationXcmdLaneEdits(_ report:
  CheckReport)` — executes, in order: the canonical section, then the
  sweep section, and (Task 4 later) the opaque-epoch section. Task 3's
  version contains the first two sections only — no placeholder calls to
  not-yet-written sections.
- Wiring line in `AutomationPageChecks.swift`, immediately after
  `drawerAutomationXcmdParity(report, suite: session, service: service)`
  (line 366): `drawerAutomationXcmdLaneEdits(report)`.

Behavior (cppID `"automation-domain/AutomationDomainTest::<slot>"`):

- Canonical (fixture values from spec §5.3 row 1): write volume
  `[(96,34)]`, length `[(96,17)]`; assert lane projections
  `["96:34"]`/`["96:17"]` (A001/A002); bytes at 96 expected
  `[(Xcmd.selectorController, 0x08), (Xcmd.payloadController, 34),
  (Xcmd.selectorController, 0x09), (Xcmd.payloadController, 17)]` (A003);
  move volume 96→192 v35 via `moveLanePoints(track:lane:moves:
  [LanePointMove(point: <lanePoints front>, tick: 192, value: 35)])`;
  `oneEdit` (A004); points `["192:35"]` (A005); bytes at 192
  `[(sel, 0x08), (pay, 35)]` (A006); `undoToRoot()` then bytes ==
  pre-edit snapshot bytes and both lane projections empty (A007-A009).
- Sweep (spec §5.3 row 4): fresh fixture; inject note pair via two
  `insertRawEvent` calls (note-on 0x90 key 60 vel 100 at 8772, matching
  note-off 0x80 at 8808, channel 0); `setLane(volume, [(8844, 48)])`;
  capture `notes()`; commit the accepted span
  `AutomationCommit.apply(AutomationLaneEdit(parameter: .controlChange(
  track: 0, controller: Xcmd.echoVolumeLane), revision:
  document.revision, tickBegin: 8736, tickEnd: 8844, points:
  [AutomationLanePoint(tick: 8736, value: 32), AutomationLanePoint(tick:
  8844, value: 48)], unchanged: false), in: document)`; assert
  `notes()` unchanged (A040); points `["8736:32", "8844:48"]` (A041);
  `undoToRoot()` + bytes == pre-sweep snapshot (A042 — the original's
  `while (index() > before.undoIndex)` walk to the pre-edit base).

## Implementation steps

1. Append `XcmdDomainFixture` and `drawerAutomationXcmdLaneEdits` to
   `xcmd.swift`; add the wiring line in `AutomationPageChecks.swift`.
2. Use only the public APIs of spec §4; no production edits, no
   accessors.
3. Keep byte-chain expectations as literal arrays matching spec §5.3
   exactly; if an assertion fails, that is a §5.3 behavioral finding —
   report, do not adjust expectations.

## Acceptance predicate

- NAMED CHECKS (controller): `deno task verify --filter swiftcore --qt
  projectSession --verbose` PASS with the new cppIds
  `automation-domain/AutomationDomainTest::xcmdCanonicalEdits` and
  `::xcmdSweepPreservesNotes` present in the PASS lines; then `deno task
  lsp:swift`. Implementer: `deno task proof show automation/domain/
  xcmd.cpp` still parses with `GAP 62` (reclassification is Task 6's).
- Coverage: the projectSession run executes every predicate this task
  adds (they run in `runAutomationPageChecks`); its PASS is execution
  evidence for the 12 sites' later MATCHED mappings.

## Task-specific constraints

- Append-only in `xcmd.swift`: no edits above the current line 90 beyond
  the entry-point comment block if needed (spec §5.3 mapping-rules
  citation may extend the header comment; keep it short).
- The move in canonical uses the *lane point identity* from
  `lanePoints` output, never a reconstructed tick equality.
- `Xcmd.selectorController` is `0x1E`; never hard-code it where a
  constant exists.
