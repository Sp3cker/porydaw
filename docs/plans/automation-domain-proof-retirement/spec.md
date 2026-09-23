# Automation/domain C++ check retirement — evidence spec

Updated: 2026-09-22. HEAD at scoping: `ec57b115` (worktree additionally
carries in-flight, uncommitted editcheck plan work — see plan.md baseline
policy). All findings below were verified in this worktree at scoping time;
tasks re-verify the mutable ones (SHAs, reachability, suite pass state) at
execution.

## 1. Objective and success criteria

Retire the legacy C++ check originals in `src/checks/automation/domain/` by
covering each original assertion site's *observable contract* with a
behaviorally equivalent Swift predicate, then deleting the C++ file and
rewriting its proof as a deletion certificate (format §3). Three originals,
236 sites total:

| Proof | Original | Sites today | Audited end state |
|---|---|---|---|
| `proof.gestures.txt` | `gestures.cpp` (on disk) | 62 MATCHED, 5 PARTIAL | 66 MATCHED, 1 RETIRED-REPRESENTATION |
| `proof.tst_automationdomain.txt` | `tst_automationdomain.cpp` (deleted at `31ea635f`) | 106 MATCHED, 1 NATIVE-SETUP | 106 MATCHED, 1 RETIRED-REPRESENTATION |
| `proof.xcmd.txt` | `xcmd.cpp` (on disk) | 62 GAP | 62 MATCHED |

Success criteria:

1. `deno task proof list --area automation/domain` shows all three proofs
   with `PARTIAL 0, GAP 0` and only terminal dispositions.
2. `gestures.cpp` and `xcmd.cpp` are deleted; `tst_automationdomain.h` is
   deleted once its last includers are gone (Task 7). Each certificate names
   the `Reference revision` + `Original SHA-256` the deleted file is
   recoverable from (§2.2 — all three pins verified at scoping).
3. A post-deletion `deno task verify --verbose` PASS is recorded by the
   controller, covering registered native and QML checks as well as the
   Swift lane; the focused Swift-only runs occur at intermediate gates.
4. No site is relabeled to manufacture green: MATCHED requires an executing
   Swift predicate under the original observable; the two representation
   reclassifications carry the §7 no-ingress proof (A052, A001).
5. Deletion of C++ *implementation* files (engine side) happens through no
   gate in this plan — Task 7 records reachability and blockers only
   (§8; mirroring the editcheck plan's conservative gate).

Non-goals: retiring any other automation proof (the parent
`src/checks/automation/`, `hover/`, `presentation/` ledgers stay as they
are); porting the dormant widget UI; touching native/QML lanes anywhere
(they remain necessary blockers); editing production Swift beyond exercising
existing public API from checks.

## 2. Ground rules

### 2.1 Disposition semantics

Vocabulary is global (`tools/proof_reader.ts:55-66`): `MATCHED`, `PARTIAL`,
`GAP`, `NATIVE`, `NATIVE-SETUP`, `RETIRED-REPRESENTATION`,
`RETIRED-BACKEND-MECHANISM`, `RETIRED-ROLE-PROTOCOL`, `DEFERRED-KEYBOARD`.
A disposition change must update the site's `Mapping/reason` line in the
same edit (`tools/proof_editor.ts` enforces). `NATIVE-SETUP` is **not**
terminal for a deletion certificate: a site so labeled either gains an
executing predicate or is reclassified `RETIRED-REPRESENTATION` with the
§7 proof.

Classification test for an unsettled site — apply in order:

1. **STALE** — live Swift already asserts the equivalent under a compatible
   predicate → reclassify to `MATCHED`, cite the predicate (file + line).
2. **REPRESENTATION** — the C++ site observes Qt/C++ API shape (optional
   `has_value()` guards, injected constructor arguments, `QUndoStack`
   index introspection, `smf().write()` byte dumps) whose *behavior* is
   observable through public Swift API → add or cite a public-API predicate
   and reclassify to `MATCHED`.
3. **RETIRED-REPRESENTATION** — the mechanism itself has no Swift ingress →
   reclassify only with the §7 ingress proof in the mapping line.
4. **BEHAVIOR-GAP** — real consumer-visible behavior nothing asserts →
   write the Swift predicate, then `MATCHED`.

Hard rules (controller gate):

- **No argument echo.** A predicate comparing a value against the argument
  just passed in is not equivalence.
- **Non-throwing construction never MATCHes setup sites.** `SongDocument(
  file:)` has no failure branch; a C++ bool/error-string guard around
  document construction/adoption is RETIRED-REPRESENTATION, never MATCHED
  (editcheck spec §2.1 precedent; applies to A001 here).
- **No synthetic parameter fabrication.** A predicate that passes only by
  hand-constructing an `AutomationParameterMetadata`/lane state no
  production parameter can hold (e.g. an invented `defaultValue: 20`) is
  synthetic-only evidence and never MATCHes a site whose scenario is that
  unconstructible state (decides A052 — see §5.1).
- **Revision is not history depth.** `revision` advances on commits and on
  undo/redo replay. C++ `undoStack()->undo()` loops and `index()`
  checkpoint walks map to count-free undo (`undoDocument()` until the
  known-clean base, asserting byte equality), never to revision arithmetic.
- Exact-array predicates legitimately close size, order, and per-index sites
  together (established in this proof family: `proof.gestures.txt` A055/A056
  both cite one array equality).

### 2.2 Proof-editing and revision-pinning protocol

- Per-site disposition edits: `deno task proof:edit automation/domain/
  <name>.cpp <A###> --before '<exact text>' --after '<replacement>' --apply`.
- Certificate preamble rewrites: direct file edits, validated with
  `deno task proof show automation/domain/<name>.cpp` (parses, tally
  reconciles) and `deno task proof list --area automation/domain`.
- SHA pins verified at scoping (re-verify before use; never write
  placeholders, never point `Reference revision` at a deletion commit):
  - All three proofs: `Reference revision f3069ef693542bdb63564b80a29773e2f5b2a360`.
  - `gestures.cpp` `edb8678ec7f2c28b8ad7bac746f6b858670708add290c079be186657d069e380`
    (on-disk == revision content, verified).
  - `xcmd.cpp` `ce94aa2bcbce0e2561750338e11d1e55d6bb2f7d98fae1142998f64e8cde99ab`
    (on-disk == revision content, verified).
  - `tst_automationdomain.cpp` `50413de58668643dee1e9aab4d4bfba348242b94a351706d1236916a8f825bf1`
    (file deleted at `31ea635f`; `git show f3069ef6:…` reproduces the SHA,
    verified).
  - Swift counterpart SHAs in the three preambles match on-disk at scoping;
    the xcmd certificate task refreshes `xcmd.swift`'s after the last Swift
    edit and adds the new counterpart pair (§3).
- Acceptance searches use the harness `grep` tool scoped to named paths and
  `lsp references` for symbols — never shell `grep -rn` (AGENTS.md).

### 2.3 Fixture dimension (no corpus rows in this folder)

All three originals are synthetic-fixture checks: no staged decomp-song
corpus, no Deno-staged files. The only data-row dimension is the original
`QFETCH(int, adapterKind)` tempo/cc row pair, already reproduced by
`tst_automationdomain.swift` (`for parameter in [.tempo, .controlChange(
track: 0, controller: 11)]` — `DrawerDomainCheckFixture` at
`tst_automationdomain.swift:405-499`). New xcmd work builds documents from
inline `MidiFile` constants exactly as `xcmd.swift:43-51` and
`DrawerDomainCheckFixture.document` (division 24, one program-change chunk,
`endTick: 9216`) already do. Per-slot fixture constants and expected values
are fixed in §5.3; tasks do not invent values.

### 2.4 Suite map and verification commands

`src/checks/support/corecheck/CoreCheckSupport.swift :: pdcSuiteRun`
dispatches; `src/checks/support/corecheck/tst_swiftcore.cpp` maps QtTest
slots. Entries relevant to this folder:

| Suite | QtTest slot | Entry | Domain content |
|---|---|---|---|
| 10 | `projectSession` | `runProjectSessionSuite` → `SessionChecks.swift:44` → `runAutomationPageChecks` (`AutomationPageChecks.swift:344-383`) | all `drawerAutomation*` functions: gestures five, `drawerAutomationXcmdParity`, Legacy rows (Resolver/Metadata/DefaultPromotion/Span), awaited pan-undo regression |
| 6 | `eventEdits` | `runEventEditsSuite` → `EventChecks.swift:11` → `coreEventAutomationGestureCoreSeams` (`gestures.swift:691`) | gesture seam core |
| 9 | `timeEdits` | `runTimeEditsSuite` → `TimeChecks.swift:16` → `coreTimeXcmdTimeTraffic` (`xcmd.swift:42`) | xcmd time traffic; new range family wires here |

Swift check sources compile only when listed in the `swift_core_check`
target (`src/checks/CMakeLists.txt:152-154` already lists
`automation/domain/{tst_automationdomain,gestures,xcmd}.swift`; the new
`xcmdRanges.swift` must be added beside them — exactly one CMake line,
Task 5).

Commands (controller-owned after each task settles; all recorded well under
180 s — full swiftcore measured at build ≈32 s + run ≈8.5 s in
`proof.automationmenus.txt`'s verification record):

```bash
deno task verify --filter swiftcore --qt projectSession   # narrow: suite 10
deno task verify --filter swiftcore --qt timeEdits        # narrow: suite 9
deno task verify --filter swiftcore --verbose             # full lane; certificate evidence
deno task proof show automation/domain/<name>.cpp         # parse + tally
deno task proof list --area automation/domain             # ledger reconciliation
deno task lsp:swift                                       # after Swift edits (AGENTS.md)
```

`--qt` forwards a Qt payload to exactly one selected harness
(`tools/checks_options.ts:19-20`, `tools/run_checks.ts:403-406,514-529`).
`--verbose` surfaces the per-`cppId` PASS lines the mapping evidence cites.

cppID convention for new predicates: `"automation-domain/
AutomationDomainTest::<slotName>"` — identical to the seven cppIDs already
emitted by `xcmd.swift:55-88`.

## 3. Deletion certificate format

Canonical shape: `src/checks/editcheck/proof.tst_songdocument_songraw.txt`
(editcheck spec §3). Preamble fields, in order:

1. `Assertion correspondence: automation/domain/<name>.cpp`
2. `Verification: post-deletion deno task verify --filter swiftcore
   --verbose — PASS <selection summary> (<timing>).`
3. `Reference revision: f3069ef693542bdb63564b80a29773e2f5b2a360` (retain;
   never a deletion commit)
4. `Original: src/checks/automation/domain/<name>.cpp` + verified
   `Original SHA-256` (§2.2)
5. `Swift counterpart:` path + post-edit `Swift SHA-256` — one pair per
   counterpart (`gestures.swift` unchanged for gestures;
   `tst_automationdomain.swift` unchanged; `xcmd.swift` +
   `xcmdRanges.swift` for xcmd)
6. `Covered native implementation:` — §5 per-original lines
7. `Native engine status:` — the engine sources remain on disk uncompiled;
   Task 7 records the reachability audit; no active native bridge claimed
8. `Retirement:` N sites, all terminal (counts by disposition); deleted C++
   recoverable from Reference revision + SHA; no live native run claimed
9. `Fixture and execution:` — inline fixtures, slots, undo counts
10. `History caveat:` — public undo/redo traversal, byte/identity equality;
    no test-only accessors
11. `Registered run path:` — entry function → suite number via `pdcSuiteRun`;
    counterpart compiled in `src/checks/CMakeLists.txt :: swift_core_check`

Then the full `A###` inventory (all terminal, each citing its predicate)
and the trailing `S###` index / supplemental sections the proof already
carries (gestures' supplemental awaited-history section is preserved
verbatim — its Swift-only scenarios stay live in `gestures.swift`).

## 4. Public Swift API used by this plan (all verified public; no test-only
accessors exist or may be added)

Document core (`src/swift/core/`): `SongDocument(file:trackBudget:)`
non-throwing; `lanePoints(track:lane:)` (Xcmd-descriptor-aware,
`SongDocument.swift:338`); `writeLane(track:lane:from:through:points:)`
(`EventEditing.swift:374`); `moveLanePoints(track:lane:moves:
[LanePointMove])` (`:399`); `deleteLanePoints(track:lane:points:)`
(`:426`, Xcmd-aware); `insertRawEvent(chunk:event:)` (`:206`);
`notes(in:)` (`SongDocument.swift:320`); `rawChunks: [MidiChunk]`
(`SongDocument.swift:276`); `applyRangeEdit(RangeEdit) -> Bool`
(`TimeEditing.swift:94`); `moveRange(notes:points:by:tempo:) -> Bool`
(`:226`); `removeTime(TimeRange, scope: TimeScope) -> Bool` (`:280`);
`duplicateTime(TimeRange, scope:)` (used `xcmd.swift:54`); `engineTracks.
usedTrackCount`; `revision`; `history.undoDocument()/redoDocument()/
canUndo/canRedo/currentIdentity`; `captureSave()` bytes via the
`DrawerDomainCheckFixture.snapshot` idiom (`tst_automationdomain.swift:
423-426`). Types: `RangeEdit{minimumEngineTrackCount, removePoints,
addNotes, addPoints}` (`TimeEditing.swift:3-41`), `LaneWrite{tick,value}`,
`LanePointMove{point,tick,value}`, `LanePoint`, `TimeRange`, `TimeScope`,
`Tick = UInt32`, `TimeDefaults.noTick`.

Xcmd (`src/swift/core/Xcmd.swift`): `selectorController 0x1E`,
`payloadController 0x1D`, `alternatePayloadController 0x1F`,
`echoVolumeLane 0xFB`, `echoLengthLane 0xFC`, `descriptors`, `assess(_:)`.

Drawer automation (`src/swift/app/drawer/automation/`):
`AutomationPencilTransaction` + `completion()` → `AutomationLaneReplacement.
heldSpan` (`AutomationDrawingTransactions.swift:397-399`);
`AutomationLaneFreeze` (`AutomationTransactions.swift:195-211`);
`AutomationFrozenFacts.freeze(includingLeadIn:)` (`:182-190`);
`snapshot.leadInValue` derives from `metadata.defaultValue`
(`AutomationLaneProjection.swift:162-165`).

Shared check helpers (internal, same target): `coreTimeBytes` /
`coreTimeXcmdTraffic` / `coreTimePointShape` (`src/checks/editcheck/
TimeChecks.swift:1561-1581`); `DrawerDomainCheckFixture` snapshot/oneEdit/
replay idiom (`tst_automationdomain.swift:405-499`).

## 5. Per-original audited status

### 5.1 gestures.cpp — 67 sites (62 MATCHED, 5 PARTIAL)

Five slots, all ported into `gestures.swift` and wired through
`runAutomationPageChecks` (`AutomationPageChecks.swift:361-365`). The 62
MATCHED stand. The five PARTIAL sites are the empty-lane pencil block
(`gestures.cpp:218-226`): the C++ `AutomationPencilGesture::start(…,
NodePoint{0, 20}, …)` **injects an arbitrary lead-in 20 into an empty
lane**; Swift's `AutomationPencilTransaction(facts:firstSample:firstCell:
clockTicks:)` reads the lead-in from facts — `freeze(includingLeadIn:)` →
`snapshot.leadInValue` → `metadata.defaultValue` — so the empty Modulation
lane in the live predicate uses its engine default 0 (`gestures.swift:
618-638`). Audited:

- **A048** (`has_value()`), **A049** (`!unchanged`), **A050** (`size()==2`),
  **A051** (`points[0]==(24,80)`) → **MATCHED (STALE)**: none of these four
  observables reads the injected 20. Existing executed predicates under
  `drawerAutomationPointRangeID`: start guard `gestures.swift:623-631`
  (`report.fail` + return — same mapping pattern as the already-MATCHED
  A053), `!stroke.completion().unchanged` `:637`, exact array
  `["24:80","48:0"]` `:632` (covers size, order, first point; array-closes
  multiple sites per §2.1).
- **A052** (`points[1]==(48,20)`) → **RETIRED-REPRESENTATION**: the
  constructor-injected arbitrary lead-in has no Swift public ingress
  (§2.1 no-fabrication rule). No-ingress proof for the mapping line: the
  injection point is the C++ `start()` signature; Swift's only pencil
  entry derives the lead-in from `metadata.defaultValue`
  (`AutomationLaneProjection.swift:162-165`) and no public parameter
  carries 20. The surviving observable — the completion restores the held
  lead-in at the span end, with the original's exact values — is asserted
  through the same production completion path
  (`AutomationPencilTransaction.completion()` delegates to
  `AutomationLaneReplacement.heldSpan`) by `gestures.swift:652`
  (past-last pencil, `["24:80","48:20"]` exact) and `:544` (heldSpan
  freeze, `[24:80, 48:20]`).

Task 1 is **proof-only**: no `gestures.swift` edit (its SHA pin stays
valid; eight other proofs cite its line anchors — see plan.md append-only
policy). Certificate + delete `gestures.cpp`.

### 5.2 tst_automationdomain.cpp — 107 sites (106 MATCHED, 1 NATIVE-SETUP)

Fully ported into `tst_automationdomain.swift` (Legacy Resolver/Metadata/
DefaultPromotion/Span rows + DeleteTransactions; execution evidence in the
proof's Verification section: all 107 sites passed `projectSession`). The
original `.cpp` was **already deleted** by `31ea635f` (T2 boundary sweep);
the proof still carries the old-style preamble and one non-terminal
disposition:

- **A001** `QVERIFY2(m_document->adoptSmf(std::move(smf), song, &error),
  qPrintable(error))` — NATIVE-SETUP → **RETIRED-REPRESENTATION**. The Qt
  bool/error-string guard is a setup-return representation: Swift
  constructs the same division-24/one-program-track/end-9216 fixture via
  non-throwing `SongDocument(file:)`, which has no failure branch to
  assert (§2.1 hard rule — the identical editcheck precedent is
  `tst_songdocument_logic` A041). The two postconditions the guard
  protected are asserted as A002/A003 (`legacyMetadataRows`). No-ingress
  proof: the C++ file is deleted and was uncompiled; the Swift suite never
  touches `adoptSmf`/error-string plumbing.

Task 2 is **proof-only, Direct** (disposition pre-decided above;
certificate rewrite; nothing to delete). `tst_automationdomain.h` is NOT
touched here — it is still included by `gestures.cpp` and `xcmd.cpp`;
Task 7 deletes it after both are gone.

### 5.3 xcmd.cpp — 62 sites (all GAP) → all MATCHED via new predicates

Seven slots, no Swift predicates mapped yet. `xcmd.swift` (90 lines) holds
16 executing candidate predicates (`drawerAutomationXcmdParity` S001-S009
under `drawerAutomationProjectionID`; `coreTimeXcmdTimeTraffic` S010-S016
under the seven slot cppIDs) built on *deliberately minimal* fixtures —
none reproduces an original site's exact fixture values, so none closes a
site; they remain supplementary evidence in the certificate's S index.
Audited verdict for every site: **BEHAVIOR-GAP, closeable with existing
public APIs** (§4 — zero missing APIs found). No RETIRED-REPRESENTATION is
needed: every raw-byte observable is directly assertable.

C++→Swift mapping rules for these slots:

- `doc.addLanePoint(t, c, tick, v)` → `document.writeLane(track: 0, lane:
  .controller(c), from: 0, through: TimeDefaults.noTick, points:
  [LaneWrite(tick: tick, value: v)])` (same observable: lane ends holding
  exactly that point set).
- `xcmdBytesAt` / `xcmdBytes` / `ccChain` (`xcmd.cpp:24-73`) → check-local
  helpers over `document.rawChunks[0].events` filtering `0xB0` status and
  the three Xcmd controllers (pattern: `coreTimeXcmdTraffic`,
  `TimeChecks.swift:1566`); `ccChain` additionally admits controllers 7
  and 10.
- `insertCc` → `document.insertRawEvent(chunk: 0, event: .channel(tick:
  status: 0xB0, data0: c, data1: v))`.
- `clearXcmd`/`seedBaseline` (`xcmd.cpp:88-98`) → `writeLane` empty / CC10
  `[(0,80),(384,110)]` + CC7 `[(0,64),(288,48)]`.
- `doc.moveLanePoints({{t, c, point, tick, v}})` → `document.moveLanePoints(
  track:lane:moves: [LanePointMove(point: LanePoint, tick: tick, value: v)])`.
- `doc.deleteLanePoints(t, c, {points})` → `document.deleteLanePoints(
  track:lane:points:)` with points from `document.lanePoints(track:lane:)`.
- `doc.removeTimeRange(range, scope)` → `document.removeTime(range,
  scope:)`; `TimeScope` via `lanes:` or `wholeSong`.
- `doc.moveRange({}, points, delta)` → `document.moveRange(notes: [],
  points: by: delta)`.
- `doc.applyRangeEdit(name, edit)` → `document.applyRangeEdit(RangeEdit(…))`
  with `removePoints`/`addNotes`/`addPoints`/`minimumEngineTrackCount`.
- `lane.replaceSpan(begin, end, points)` (CCLaneAdapter) →
  `AutomationCommit.apply(AutomationLaneEdit(parameter:revision:tickBegin:
  tickEnd:points:unchanged: false), in: document)` — the accepted-span
  idiom `DrawerDomainCheckFixture.replace` documents as the NodeLane::
  replaceSpan equivalent (`tst_automationdomain.swift:476-483`).
- `isOneEdit(before)` → `document.revision == before.revision + 1 &&
  document.history.currentIdentity != before.identity`
  (`DrawerDomainCheckFixture.oneEdit`, `:485-487`).
- `QCOMPARE(doc.smf().write(), before.smf)` → `coreTimeBytes(document) ==
  before.bytes` (bytes from `captureSave()`, `:423-426`).
- Undo walks (`undoStack()->undo()` ×N, `while (index() > k) undo()`) →
  count-free `undoDocument()` until the named clean base (root for A007/
  A042 whose base is the freshly constructed document; exact step counts
  otherwise), each asserting byte equality per §2.1.
- `QCOMPARE(doc.engineTrackCount(), newTrack + 1)` →
  `document.engineTracks.usedTrackCount == newTrack + 1`.

Per-slot site map, fixtures, and expected values (from `xcmd.cpp:102-387`;
tasks reproduce these exactly — no invented values):

| Slot | Sites | Task | Fixture & sequence | Notable expected values |
|---|---|---|---|---|
| `xcmdCanonicalEdits` | A001-A009 | 3 | write volume `[(96,34)]` + length `[(96,17)]`; move volume 96→192 v35; undo to root | A003 bytes at 96: `[(sel,0x08),(pay,34),(sel,0x09),(pay,17)]`; A006 at 192: `[(sel,0x08),(pay,35)]`; A007 bytes==pre-edit; A008/A009 both lanes empty |
| `xcmdOccurrencesAndOpaqueProtection` | A010-A028 | 4 | volume `[(96,34),(192,35)]`; delete front; re-add; move front→384 v36; clear; volume `[(96,34)]` + length `[(96,17),(192,18)]`; move volume 96→160 v36; clear; raw selector 0x01 epoch ticks 0-2; write at tick 1; undo to root; malformed selector-0x03 epoch ticks 4-9; write 400:30; range-write at tick 8 | A017 all XCMD bytes empty; A021-A024 per-tick bytes incl. length-only at 96 after volume moved; A025 snapshot unchanged (epoch-occupied write rejected); A026 one edit; A027 full 7-pair chain ending `(sel,0x08),(pay,30)`; A028 snapshot unchanged (range write at occupied selector tick rejected) |
| `xcmdTimeRangeCuts` | A029-A039 | 5 | volume `[(96,34)]`+length `[(96,17)]`; `removeTime(96..<192, volume scope)`; undo; redo+undo; clear; volume+length `[(96,17)@96,(18)@192]`… whole-song cut; undo; redo | A030 volume empty; A031/A036 length bytes at 96 `[(sel,0x09),(pay,17)]`/`[(sel,0x09),(pay,18)]`; A032/A037 bytes restored; A035/A039 length `{{96,18}}`; A038 volume empty after redo |
| `xcmdSweepPreservesNotes` | A040-A042 | 3 | synthetic doc (end 9216) + note pair at 8772/8808 + lane point 8844:48; `replaceSpan(8736, 8844, [(8736,32),(8844,48)])`; undo to pre-edit base | A040 note events unchanged across the sweep; A041 points `[(8736,32),(8844,48)]`; A042 bytes==before |
| `xcmdRangeRemoveOnly` | A043-A048 | 5 | volume `[(96,34),(192,35)]`+length `[(96,17)]`+seedBaseline; `RangeEdit(removePoints: [volume@96, length@96])` | A044 volume `[(192,35)]`; A045 length empty; A046 ccChain `[(0,0x0A,80),(0,0x07,64),(192,sel,0x08),(192,pay,35),(288,0x07,48),(384,0x0A,110)]`; A047/A048 undo/redo bytes |
| `xcmdRangeMoves` | A049-A056 | 5 | length `[(96,17),(192,18)]`+volume `[(192,34)]`+seedBaseline; `moveRange(points: volume, by: -48)`; undo/redo; clear; length same + volume `[(96,34)]`; `moveRange(by: +96)` | A050 left ccChain 10 entries (length at 96/192, volume at 144); A054 right ccChain (volume joins length at 192 — length pair first); A051-A052/A055-A056 undo/redo bytes |
| `xcmdExpansionPaste` | A057-A062 | 5 | `RangeEdit(minimumEngineTrackCount: new+1, addNotes: [(new, [(0,60,96,100)])], addPoints: [(new, volume, [(96,34)])])` | A058 usedTrackCount == new+1; A059 points `[(96,34)]`; A060 new-track ccChain `[(96,sel,0x08),(96,pay,34)]`; A061/A062 undo/redo bytes |

Behavioral risks (genuine findings to report, never to force green):

- **Equal-tick byte order.** A050/A054 expect length-before-volume pair
  order at tick 192 (length lane written first). If Swift's raw event
  order differs, that is a real ordering contract finding — report it;
  do not reorder expectations to pass.
- **Opaque-epoch write rejection.** A025/A028 depend on Xcmd-aware lane
  writes refusing to encode inside unknown-selector epochs
  (`EventEditing.swift:426-429` shows the descriptor-aware branch). A
  failure here is a production gap, not a check fix.

## 6. What must remain native

Nothing in `src/checks/automation/domain/` is a registered native lane:
`gestures.cpp`, `xcmd.cpp`, `tst_automationdomain.h` appear in no CMake
target and `runAutomationDomainCheck` has no caller (verified: zero
references in `src/checks/checkcatalog.cpp` and every `CMakeLists.txt`
outside build/external). Native and QML lanes elsewhere (audio, playback,
midi, swiftrollgated, selectionkey, scalecheck, themelayout) are untouched
and remain necessary blockers. The parent-folder automation proofs
(`proof.automation*.txt` etc.) are not this plan's scope.

## 7. Implementation reachability — verified build-graph evidence

Checked every `CMakeLists.txt` outside `build*/`/`external/` (root,
`src/checks`, `src/swift/{core,app,playback}`):

- `porydaw_checks` compiles only the native lanes listed at
  `src/checks/CMakeLists.txt:33-102` (audio, scale, voicegroup, midi,
  playback, swiftrollgated, themelayout) plus shared
  checkregistry/checkcatalog/fixturecatalog and `porydaw_scale` +
  `ui/activity/trackactivity`. **No automation, editordrawer, or
  `src/core/` source is compiled.**
- `gestures.cpp`, `xcmd.cpp`, `tst_automationdomain.h`: zero CMake
  references; zero registrations in `checkcatalog.cpp`.
- Engine-side files these checks exercised — `src/core/xcmd.cpp/.h`,
  `src/ui/editordrawer/nodelane/*`, `src/ui/editordrawer/cclanes.*`,
  `src/core/songdocument*`: zero CMake references (consistent with the
  editcheck spec §7 audit).
- On-disk includers of `core/xcmd.h` besides the checks being retired:
  `src/core/songdocument.h`, `src/core/midiimport.cpp`,
  `src/checks/editcheck/tst_songdocument_metadata.cpp` (unretired
  editcheck original at scoping), dormant `src/ui/editordrawer/*` files.
- Includers of `tst_automationdomain.h`: exactly `gestures.cpp:1` and
  `xcmd.cpp:1` (its `runAutomationDomainCheck` declaration has no
  definition since `31ea635f` deleted the `.cpp`).

No-ingress proofs for RETIRED-REPRESENTATION therefore cite: the C++
original is uncompiled/unregistered (or deleted), and the specific
mechanism (adoptSmf error-string guard; pencil constructor lead-in
argument) has no public Swift ingress (§5.1/§5.2 name the exact symbols).

Task 7 re-runs this audit fresh (never trust this snapshot) before
deleting `tst_automationdomain.h`, and records the engine-family blocker
chain in `engine-reachability.md`.

## 8. Engine-deletion gate (Task 7; record-only)

This plan deletes **no engine implementation**. Post-plan candidates and
their blockers (recorded, not acted on):

- `src/core/xcmd.cpp/.h` — blocked: included by `songdocument.h` (legacy
  core family), `midiimport.cpp`, dormant editordrawer sources; the
  editcheck §8 gate already lists them as cross-area-blocked.
- `src/ui/editordrawer/nodelane/*`, `cclanes.*` — blocked: included by the
  dormant editordrawer family itself (`automationprojection.*`,
  `tempolane.h`, `automationviewmodel.*`); that family's retirement is a
  separate user decision (same reasoning as editcheck Task 15).

Deleting around blockers (stub headers, dead-code bypasses) is forbidden
(AGENTS workarounds policy).

## 9. Retirement order (ranked)

1. **tst_automationdomain** (certificate-only; file already deleted).
2. **gestures** (proof-only: 4 STALE reclassifications + 1 representation
   + certificate + delete).
3. **xcmd** (three Swift tasks — lane CRUD, opaque epochs, range family —
   then certificate + delete).
4. **Final**: `tst_automationdomain.h` deletion + reachability record +
   full-lane verify.

## 10. Assumptions and unresolved items

- Tasks start after the editcheck plan's CMake/TimeChecks chain settles
  (plan.md baseline policy); the only shared-file intersections are
  `src/checks/CMakeLists.txt` and `TimeChecks.swift`, both touched by
  exactly one line in Task 5.
- The recorded suite pass state (proofs' Verification sections) is assumed
  to hold at execution; the controller's post-task narrow runs are the
  authoritative evidence.
- `gestures.swift` and `tst_automationdomain.swift` are assumed unedited by
  any concurrent work (not in any editcheck write set); Task 1/2 therefore
  refresh no Swift SHAs. If a task observes drift, it re-reads, re-pins per
  §2.2, and reports.
- The two §5.3 behavioral risks (equal-tick order, opaque-epoch rejection)
  are the only places this plan could surface a production gap; both are
  report-and-stop conditions for the task, not check-side workarounds.
