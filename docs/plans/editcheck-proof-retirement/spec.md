# Editcheck C++ check retirement — evidence spec

Updated: 2026-09-22 (rev 2 — controller gate corrections applied). HEAD at
scoping: `8c5e3f2a075e4239abaf172a82ab46a3b859229e`. All findings below
were verified in this worktree unless marked `[scout]` (scout evidence
spot-checked against source; discrepancies corrected).

## 1. Objective and success criteria

Retire the legacy C++ check originals in `src/checks/editcheck/` by
covering each original assertion site's *observable contract* with a
behaviorally equivalent Swift predicate, then deleting the C++ file and
rewriting its proof as a deletion certificate. Seven of the eight
remaining originals are retired by this plan; `tst_scale.cpp` is
**retained natively by default** (§5.1) — its lane is a native check, and
native/QML checks are necessary blockers, so no scale deletion or
disposition change happens absent an explicit user decision to retire the
scale feature. Legacy C++ *implementation* deletion is gated per §8.

Success criteria:

1. `deno task proof list --area editcheck` shows the seven retired proofs
   with `PARTIAL 0, GAP 0` and only terminal dispositions (`MATCHED`,
   `RETIRED-REPRESENTATION`). `proof.tst_scale.txt` keeps its live native
   accounting (§5.1) unless the user decides otherwise.
2. The four already-retired certificates (songmoves 138, songnotes 111,
   songranges 79, songraw 43 sites) are untouched.
3. Each retired original's proof is a deletion certificate in the
   songraw format (§3), with a post-deletion passing
   `deno task verify --filter swiftcore --verbose` recorded by the controller.
4. No check is relabeled to manufacture green: a site becomes `MATCHED`
   only when a Swift predicate asserts the same consumer-visible behavior;
   representation-only sites become `RETIRED-REPRESENTATION` only with the
   no-ingress proof named in §2.1/§7.
5. Deletion of C++ *implementation* files happens only through the §8
   reachability gate.

Non-goals: porting scale behavior to Swift; changing production Swift code
except where a check needs an existing public API exercised; editing files
outside the write sets named in `plan.md`.

## 2. Ground rules

### 2.1 Disposition semantics (from proof corpus + `tools/proof_reader.ts:55-66`)

- `MATCHED` — an equivalent Swift predicate exists and executes under the
  original `cppID`.
- `PARTIAL` — a related Swift predicate with an explicit unproved condition.
- `GAP` — no equivalent Swift assertion.
- `NATIVE` — retained native obligation (native lane still executes it).
- `RETIRED-REPRESENTATION` — the C++ observation is about a mechanism whose
  production ingress no longer exists; the consumer-visible behavior either
  does not exist in the Swift domain or is asserted by other predicates.
  Requires the no-ingress proof.
- A disposition change must update the site's `Mapping`/`Mapping/reason`
  line in the same edit (enforced by `tools/proof_editor.ts`).

Classification test for a PARTIAL/GAP site — apply in order:

1. **STALE** — current Swift already asserts the equivalent under the right
   `cppID` → reclassify to `MATCHED`, cite the `S###`.
2. **REPRESENTATION** — the C++ site observes Qt/C++ internals
   (`QUndoStack::count()/index()`, signal spies, `findNote` out-params,
   nullable returns) whose *behavior* is observable through public Swift API
   → add or cite a public-API predicate (§4) and reclassify to `MATCHED`.
3. **RETIRED-REPRESENTATION** — the mechanism itself is gone → reclassify
   only with the §7 ingress proof in the mapping line.
4. **BEHAVIOR-GAP** — a real consumer-visible behavior no Swift predicate
   asserts → write the Swift assertion (public APIs only), then `MATCHED`.

Hard rules (controller gate):

- **No argument echo.** A predicate that compares a value against the
  argument just passed in (e.g. `timeline.sampleRate == 44_100` after
  `build(sampleRate: 44_100)`) is not equivalent to a C++
  null/construction check. Non-optional Swift construction
  (`SongDocument(file:)`, `PlaybackTimeline.build`) has no failure branch
  to assert: those sites are RETIRED-REPRESENTATION, never MATCHED.
- **Non-throwing construction ≠ staging.** `fixture.stage()` validity
  checks, `QTemporaryFile`/disk write-read plumbing, and database-open
  staging asserts are RETIRED-REPRESENTATION (with the §7 proof) or stay
  GAP/PARTIAL — an in-memory `SongDocument(file:)` call does not MATCH
  them. A *throwing* decode/save whose failure branch the Swift predicate
  actually exercises (do/catch → `report.fail`) can MATCH a C++ read/save
  success site covering the same bytes.
- **Revision is not history depth.** `document.revision` advances on
  every committed edit AND on undo/redo replay. `QUndoStack::count()`
  sites map to `coreEditHistoryCountAtTip` deltas only. Unchanged
  `revision` may corroborate a no-op (no commit occurred) but never
  substitutes for a depth assertion.
- Never map a presenter-level or synthetic-only assertion onto a
  corpus-site family without the corpus dimension (§2.3).

### 2.2 Proof-editing and revision-pinning protocol

- Per-site disposition edits: `deno task proof:edit <name> <A###> --before '<exact text>' --after '<replacement>' --apply` (tool enforces entry-ID preservation and mapping-line coupling).
- Certificate preamble rewrites and `S###` trailer extensions: direct file
  edits, then validate with `deno task proof show <name>` (parses clean) and
  `deno task proof list --area editcheck` (tally reconciles).
- **Reference revision / SHA pinning** (mirrors the four accepted
  certificates): each proof already carries its `Reference revision` — the
  Git revision whose tree contains the original C++ content — and an
  `Original SHA-256`. Certificates RETAIN that existing revision line.
  Before deleting a file, verify `shasum -a 256 <file>` equals the recorded
  `Original SHA-256` and that `git show <Reference revision>:<path>` yields
  it. On mismatch, find the containing revision (`git log --all --format=%H
  -- <path>` + per-rev `git show … | shasum`) and update the pair; if no
  revision matches the on-disk content, STOP and report. Never write
  placeholders (`<pending>`) or point `Reference revision` at a deletion
  commit.
- Swift counterpart SHAs: `shasum -a 256 <file>` after the last edit.
- **Acceptance searches use the harness tools** — the `grep` tool scoped
  to named paths, and `lsp references` for symbols — never shell
  `grep -rn` (AGENTS.md search discipline).

### 2.3 Corpus dimension

The legacy suite ran most slots as data rows over the 14 staged decomp songs
(`coreEditCorpusSongs` discovers them: `mus_dummy`, `mus_littleroot_test`,
`mus_route101`, `mus_route102`, `mus_gsc_route38`, `mus_caught`,
`mus_petalburg`, `mus_oldale`, `mus_gym`, `mus_surf`, `mus_victory_wild`,
`se_use_item`, `se_pc_login`, `se_fanfare_1trk`). The four retired
certificates all preserved this population via corpus row loops
(`NoteCorpusChecks.swift`, `NoteMoveCorpusChecks.swift`,
`coreRangeCorpusChecks`, `coreTimeCorpusChecks`). Retirement of a
corpus-driven family requires its per-row Swift equivalent, not only a
synthetic fixture. Corpus staging sites (`!song.midPath.isEmpty()`,
`document.load`, `track >= 0` classification) are MATCHED inside the corpus
loop exactly as `NoteMoveCorpusChecks.swift:13-52` does
(path/load/track triple per row, sentinel `rows > 0` guard) — those Swift
predicates genuinely execute the staging observables (throwing decode,
per-song classification), so they are MATCHED, not representation.

### 2.4 swiftcore suite map and verification commands

`src/checks/support/corecheck/CoreCheckSupport.swift :: pdcSuiteRun`
dispatches; `src/checks/support/corecheck/tst_swiftcore.cpp` maps QtTest
slots:

| Suite | QtTest slot | Entry | Editcheck content |
|---|---|---|---|
| 4 | `noteEdits` | `coreEditCorpusLoadCheck` + `runNoteEditsSuite` (NoteChecks.swift) | note adoption/identity, velocity, corpus note+move rows |
| 5 | `documentHistory` | `runDocumentHistorySuite` (NoteChecks.swift) | gesture/identity history, save identity, merge contracts |
| 6 | `eventEdits` | `runEventEditsSuite` (EventChecks.swift) | track contracts, raw events, lanes, metadata contracts |
| 7 | `xcmdEdits` | `runXcmdEditsSuite` (EventChecks.swift) | xcmd projection/rewrite/export |
| 9 | `timeEdits` | `runTimeEditsSuite` (TimeChecks.swift) | range/time contracts, corpus rows, clipboard |

Swift check sources compile ONLY when listed in the `swift_core_check`
target source list (`src/checks/CMakeLists.txt:104-198`); a new Swift file
must be added there beside the existing `editcheck/*.swift` entries.

Commands (controller-owned after each task settles):

```bash
deno task verify --filter swiftcore --verbose          # full lane; certificate evidence
deno task verify --filter=swiftcore --qt timeEdits     # narrow: suite 9 only
deno task verify --filter=swiftcore --qt eventEdits    # narrow: suite 6 only
deno task verify --filter=swiftcore --qt noteEdits     # narrow: suite 4 only
deno task verify --filter=swiftcore --qt documentHistory # narrow: suite 5 only
deno task proof list --area editcheck                  # tally reconciliation
deno task lsp:swift                                     # after Swift edits (AGENTS.md)
```

`--qt` forwards a Qt argument payload to exactly one selected harness
(`tools/checks_options.ts:19-20`, `tools/run_checks.ts:403-406,514-529`).

## 3. Deletion certificate format (canonical: proof.tst_songdocument_songraw.txt)

Preamble fields, in order:

1. `Assertion correspondence: editcheck/<name>.cpp`
2. `Verification: post-deletion deno task verify --filter swiftcore --verbose — PASS <selection summary> (<timing>).`
3. `Reference revision: <the proof's existing revision pin — §2.2; never a deletion commit>`
4. `Original: src/checks/editcheck/<name>.cpp` + `Original SHA-256: <sha verified per §2.2>`
5. `Swift counterpart: <path>` + `Swift SHA-256: <sha>` (one pair per counterpart; include `Shared corpus loader: src/checks/editcheck/tst_songdocument_runner.swift` + SHA when corpus rows run)
6. `Covered native implementation: <file> :: <symbols>` — the legacy C++ implementation the original exercised.
7. `Native engine status: C++ implementation remains on disk, but current CMake targets do not build these legacy src/core sources; no active native bridge is claimed. Active checks use Swift PorydawCore.` (tense updated by Task 15 only where §8 deletes)
8. `Retirement: <N> original assertion sites, all terminal (<counts by disposition>); deleted C++ check recoverable from Reference revision and Original SHA-256. No live native run or differential comparison is claimed.`
9. `Fixture and execution:` — exact fixtures, rows, sequences.
10. `History caveat:` — public undo/redo traversal, state/identity equality; no test-only history accessor.
11. `Registered run path:` — entry function → suite number via `pdcSuiteRun`; counterpart compiled in `src/checks/CMakeLists.txt :: swift_core_check`.

Then the full `A###` inventory (all sites terminal, each citing its `S###`
where a predicate exists) and the complete `S###` predicate trailer.

## 4. Public Swift history/document API for REPRESENTATION mappings

From `src/swift/core/SongDocument.swift`, `SongHistory.swift`,
`NoteEditing.swift`, `EventEditing.swift`, `TimeEditing.swift`
(all public; no test-only accessors exist or may be added):

- `document.history.undoDocument() -> Bool`, `redoDocument() -> Bool`;
  `history.canUndo`, `history.canRedo` — availability.
- History **depth**: no public counter (entries/index private). Use
  `coreEditHistoryCountAtTip(document, report:cppID:)` in
  `src/checks/editcheck/tst_songdocument_runner.swift:74-87` — full
  undo/redo traversal asserting count==replay and exact state+identity
  restoration. `QUndoStack::count() == before + k` maps to
  `coreEditHistoryCountAtTip(...) == before + k` — and to nothing else
  (§2.1 revision rule).
- `QUndoStack::index()` checkpoint loops map to: count the applied steps,
  undo exactly that many, assert byte/state equality.
- Clean state: `document.isDirty`; save point: `document.didSave(snapshot)`
  with `document.captureSave()`.
- `document.revision: UInt64` — monotonic, advances on commits AND on
  undo/redo replay. Usable to observe that a call was a no-op (no commit
  happened) as corroboration only; never as a history-depth assertion.
- Identity: `document.history.currentIdentity: DocumentIdentity`
  (`Hashable`); state equality: `document.state: SongState: Equatable`;
  bytes: `try document.state.file.encoded()`.
- Publication: `document.onChange: ((DocumentChange) -> Void)?` with
  `DocumentChange { revision, trackRemap: TrackRemap? }` — replaces C++
  `documentChanged`/`tracksRemapped` signal spies; assert change count and
  `trackRemap == nil` / exact remap payload.
- Failure branches: `setVelocities(_:expectedRevision:) -> UInt64?` (nil =
  stale/unknown), `addTrack(voice:) -> Int?`, `duplicateTrack(_:) -> Int?`,
  `moveTrack(_:to:) -> Bool`, `removeTime/insertBlankTime/duplicateTime ->
  Bool`, `addNotes` throws `NoteEditError`; `MidiFile.decode` throws;
  `captureSave()` throws; void mutators (`renameTrack`, `writeLane`,
  `insertRawEvent`, …) reject by leaving `revision`, `state`,
  `currentIdentity` unchanged.
- Timeline: `PlaybackTimeline.build(state:sampleRate:)` returns a
  non-optional value — C++ `QVERIFY(timeline)` null checks are
  RETIRED-REPRESENTATION (no failure path exists in Swift); assert real
  projections (`tempoMap`, `loopStartTick`, `loopEndTick`) where the
  original asserted contents.

## 5. Per-original audited status

Current tallies from `deno task proof list --area editcheck` (verified).
"Audited" = verdict after this plan's Swift work; the seven retired
originals end fully terminal. 801 sites total across the eight originals.

### 5.1 tst_scale.cpp — 24 GAP — KEEP-NATIVE (default; retirement only on explicit user decision)

All 24 sites assert `porydaw_scale` tables (scale count 28, display order,
masks, root names, defaults, membership/neighbors, diatonic destinations).
No Swift scale API exists (verified: no `ScaleId`/`isScalePitch`/
diatonic references under `src/swift` or QML). The lane is registered and
passing. Build-graph finding (§7): `porydaw_scale` is compiled only by the
checks target — but a native check guarding currently-unlinked native code
is still a live native obligation: the user decides whether the scale
feature (and its dormant widget consumers) is retired, not this plan.
This plan records the reachability evidence in the proof and leaves the
lane executing. GAP dispositions stand (no Swift parity is claimed or
planned); the Scope text gains the §7 finding so the ledger states why
GAP is the steady state.

### 5.2 tst_songdocument_runner.cpp — 4 sites (2 MATCHED, 1 PARTIAL, 1 GAP)

`EditCheckTest::initTestCase` corpus staging only. Audited: A001 GAP→MATCHED
(S001 `coreEditCorpusSongs` fails the suite on a missing staged root — the
observable contract of "editcheck requires its staged project root"); A002
PARTIAL→RETIRED-REPRESENTATION: the site asserts `DecompProject::open`
(database/songs.mk project open) — a staging mechanism with no Swift
ingress in this suite (Swift stages via the Deno fixture staging plus
direct `sound/songs/midi` directory + `midi.cfg` enumeration;
`coreEditCorpusSongs` never opens a project database), and the C++ file is
uncompiled (§7). The surviving observable — unreadable staging fails the
suite — is asserted by the throwing loader catch (S001/S003/S004/S007);
the database-open step itself is retired representation. A003/A004 already
MATCHED (S006/S002). File is uncompiled; its `runEditCheck`/
`runNoteIdentityCheck`/two-arg `runScaleCheck` entry points have no callers
(checkcatalog uses `tst_scale.cpp:154`'s single-arg `runScaleCheck`).
Retirement = proof reclassification + certificate + delete. No Swift changes.

### 5.3 tst_songdocument_timerange.cpp — 193 sites (192 MATCHED, 1 NATIVE)

Nine synthetic time-range families, fully ported into `TimeChecks.swift ::
removalAndSeams / insertionAndBoundaries / duplicationAndGlobals` (suite 9).
Sampled 9 MATCHED mappings across all families — no mapping errors found.
The single NATIVE site:

- `A154 | timeRangeAutomationSeamsAndDefaults | tst_songdocument_timerange.cpp:468`
  — `QVERIFY(timeline)` on `buildTimeline(44100.0)` returning a heap
  pointer. Swift `PlaybackTimeline.build(state:sampleRate:)` is
  non-optional: **no failure path exists to assert**, and a sample-rate
  echo predicate would be argument identity, not equivalence (§2.1).
  A154 → RETIRED-REPRESENTATION; the usable-timeline observable is already
  asserted by S145 (`tempoMap` non-empty) and S146 (front 120 BPM). No
  Swift change.

Certificate prerequisites: Verification Result line, `Covered native
implementation`, `Native engine status`, `Retirement` block (§3 fields
6-8); then delete the file. Proof-only task.

### 5.4 tst_songdocument_metadata.cpp — 125 sites (9 MATCHED, 21 PARTIAL, 95 GAP)

Eight families; `EventChecks.swift` already contains dedicated contract
functions for all eight, and six are wired into `runEventEditsSuite`
(verified call list at EventChecks.swift:5-26). Audited mix:

| Family | Sites | Audited verdicts |
|---|---|---|
| `xcmdSaveSnapshot` | A001-A012 | Wired snapshot contract, direct saved-byte/purity and A004 history-depth checks; retire only staging/chunk-index mechanisms with §7 ingress proof |
| `formatZeroCoercion` | A013-A036 | Existing format-0 conversion predicates plus A034 chunk end tick; retire only proven staging |
| `formatZeroGlobals` | A037-A045 | Previously uncalled globals/loop contract now wired; retire only proven staging |
| `formatZeroSaveRoundTrip` | A046-A063 | Existing save/tempo predicates plus A051 saved-minus-tempo, A058 redecoded format-0 provenance, and A059 redecoded-original-to-snapshot exact byte equality; retire only proven disk staging and inaccessible second explicit conversion A060 |
| `markerVersusTrackName` | A064-A070 | Marker vs bare-name precedence and rename; retire only proven staging |
| `duplicateLaneAndTempoLoad` | A071-A087 | Duplicate lane and exact typed-tempo values, A085 independently constructed full saved-file byte equality, A086 live-byte preservation; retire only proven staging/disk mechanisms |
| `duplicateCanonicalization` | A088-A103 | Canonicalization, exact undo byte restoration, public history-depth and cursor checks for A092/A093/A100/A101; retire only proven staging mechanisms |
| `duplicateReplacementsAndNoOps` | A104-A125 | Lane/tempo no-op behavior plus public history-depth/cursor stability for A109/A110/A119/A120; retire only proven staging mechanisms |

Swift work: wire the two previously uncalled metadata contracts, assert
saved-file outcomes A034/A051/A058/A059/A085/A086, and add direct
public-history observations for A004/A092/A093/A100/A101/
A109/A110/A119/A120. At-tip history traversal must not be used while
the document is undone: total depth and cursor position are distinct.
A060's second explicit conversion is private Swift representation only;
A059 still requires direct original-to-save equality. Each certificate
site must cite a behavior-specific executing predicate or a justified
representation-only retirement; source tally is not parity.

### 5.5 tst_songdocument_songtracks.cpp — 89 sites (33 MATCHED, 20 PARTIAL, 36 GAP)

Eight families; synthetic Swift contracts exist and are wired
(`trackCreateDeleteContract` … `loopCfgUndoRedoContract`). Audited:
33 MATCHED-NOW, 29 STALE (proof never reconciled with the contracts),
12 sites needing public corpus eligibility/history predicates or
representation-only treatment (A003/A014 `canAddTrack` → public budget
check; A013/A021/A052/A059 `firstEditableTrack` → per-family corpus
eligibility; A024/A026/A064/A065 `undoStack()->count()` →
`coreEditHistoryCountAtTip`; A037/A062 non-optional construction →
RETIRED-REPRESENTATION), 2 synthetic BEHAVIOR-GAPs (A038
`usedTrackCount >= 2`, A039 `tracks[0].midiChunk == 0` in
`trackMarkerNameContract`), and 13 corpus staging sites (7 of 8 families
were corpus data-row driven in C++). The corpus driver must select each
family's original SongCapability independently: Playable for signature
and loop/config, AddTrack for create, DuplicateTrack for duplicate,
ReorderableTrack for move, EditableTrack for delete-rescue and rename.
Do not skip Playable/AddTrack songs merely because they have no notes.
Use the `NoteMoveCorpusChecks.swift` row/staging pattern (§2.3) — new file
`src/checks/editcheck/TrackCorpusChecks.swift`, **added to the
`swift_core_check` source list in `src/checks/CMakeLists.txt`**, called
from `runEventEditsSuite`, one row function per family operating at
`coreEditDistantBase` offsets.

### 5.6 tst_songdocument_songtime.cpp — 56 sites (7 MATCHED, 26 PARTIAL, 23 GAP)

Four corpus-driven families. `coreTimeCorpusChecks` (TimeChecks.swift:1859)
already runs all four scenarios per corpus song with row functions
`coreTimeRemoveRow` / `coreTimeWholeSongRow` / `coreTimeAutomationRow` /
`coreTimeVoiceRow`. Audited: 7 MATCHED-NOW, 3 STALE (A018/A019/A026 —
asserted under `timeRangeWholeSong` cppIDs, need same-contract citations),
6 REPRESENTATION (A010/A025 undo count → `coreEditHistoryCountAtTip`;
A053-A056 index-checkpoint loops → count-and-replay), 40 BEHAVIOR-GAP, all
closeable with existing public APIs:

- `timeRangeRemove`: seam lane point value 40 (A008/A009), explicit commit
  return (A004), redo restores rippled note (A012).
- `songWholeSongRemove`: rescued tempo value 150→400,000 µs (A020), shifted
  note (A021), loop marker stability via `PlaybackTimeline.loopStartTick/
  loopEndTick` (A022/A023/A029/A031), sorted invariant (A017), undo restores
  tempo/note (A027/A028), redo (A032).
- `voiceLanePoint`: full voice-program lifecycle — add 5, in-place value→9,
  tick move, delete (A036-A040).
- `automationLanePoints`: interleaved CC7/pitch-bend/tempo lifecycle with
  persistence across moves and deletes (A044-A052) and count-and-replay
  undo/redo byte+tempo equality (A053-A056).

Zero hard engine gaps (all APIs exist: `writeLane`, `moveLanePoints`,
`deleteLanePoints`, `editTempo`, `removeTime`, `PlaybackTimeline.build`).

### 5.7 tst_songdocument_document.cpp — 250 sites (16 MATCHED, 93 PARTIAL, 141 GAP)

Twelve synthetic families; `NoteChecks.swift` is the primary counterpart
(suites 4/5), `EventChecks.swift` secondary (suite 6). Audited per family
(full site-level tables live in the task briefs):

| Family | Sites | Audited mix |
|---|---|---|
| `documentLoadPublication` | A001-A009 | C++ load emits `tracksRemapped` then `documentChanged` at revision 1 with one empty-map remap; Swift has no post-construction load operation or callback attachment before `SongDocument(file:)` completes. RETIRED-REPRESENTATION for staging and inaccessible load-time signal protocol A003-A007; MATCHED via public initial revision/chunk/engine state A002/A008/A009. Never call an empty callback counter a load-time observation. |
| `documentTempoEmpty` | A010-A021 | 1 MATCHED, 1 RETIRED-REPRESENTATION (staging), BEHAVIOR-GAP (default 120 BPM timeline, add/remove tempo undo/redo, `captureSave` zero tempo metas) |
| `documentVelocityAtomic` | A022-A052 | 4 MATCHED, STALE fixture IDs, MATCHED via `trackRemap == nil` change assertions and `coreEditHistoryCountAtTip`, RETIRED-REPRESENTATION (staging, `DocNote` handles), BEHAVIOR-GAP (batch undo/redo restore 100/90↔99/127, 0-clamps-to-1 commit) |
| `documentVelocityRejects` | A053-A062 | 2 MATCHED, 1 STALE, MATCHED via `coreEditHistoryCountAtTip` stability (A061), BEHAVIOR-GAP (no-op same-value commit: bytes/onChange/depth unchanged) |
| `documentDuplicateIdentities` | A063-A072 | 1 MATCHED, 6 STALE, 1 RETIRED-REPRESENTATION (staging), BEHAVIOR-GAP (undo/redo of duplication keeps minted IDs) |
| `documentRemapsAndRaw` | A073-A100 | 1 MATCHED, 5 STALE (move no-op already asserted in `trackMoveContract`), MATCHED via `DocumentChange.trackRemap` payloads (A074-A088), 8 RETIRED-REPRESENTATION (A091-A097 dynamic conductor promotion on raw events — Swift `insertRawEvent` never remaps; explicit track ops only; + staging) |
| `documentSavedIdentity` | A101-A108 | 2 MATCHED, 2 STALE, BEHAVIOR-GAP (redo→dirty, undo away from new save point→dirty, redo back→clean) |
| `documentDuplicationOwnership` | A109-A144 | 1 MATCHED, 10 STALE, MATCHED via remap payload (A129-A135), 5 RETIRED-REPRESENTATION (staging + raw-event NoteID tracking A117-A120), BEHAVIOR-GAP (lowest free channel allocation, ceiling `duplicateTrack == nil`, undo/redo note survival) |
| `documentGlobalMetadata` | A145-A158 | A145 RETIRED-REPRESENTATION (fallible synthetic `fixture.stage` has no Swift ingress); A146-A158 BEHAVIOR-GAP until a dedicated `DocumentTrackChecks.swift` contract asserts the entire typed tempo/signature/loop + raw-meta-count conjunction on the original two-track fixture before/after duplication, move, delete, and each undo/redo. Duplicate channel 2 and exactly three rechanneled raw MIDI events require direct predicates. Existing cross-fixture `trackEditing`/`trackMove`/`trackDeleteRescue`/`adoptionAndPairing` assertions corroborate components but cannot alone MATCH the whole original scenario. |
| `documentCrossingIdentities` | A159-A191 | 2 STALE, MATCHED via `coreEditHistoryCountAtTip`/revision observables, RETIRED-REPRESENTATION (staging/handles), BEHAVIOR-GAP (two-note pitch-swap sequence with ID stability across 2×undo/2×redo) |
| `documentPublicationNetZero` | A192-A208 | 1 MATCHED, MATCHED via empty-stack (`!canUndo && !canRedo`) + frozen state/bytes/change-count observables, RETIRED-REPRESENTATION (staging/handles), BEHAVIOR-GAP (return-to-origin entry drop observable) |
| `documentMergedOverlapPublication` | A209-A250 | 3 MATCHED, MATCHED via merged-entry `coreEditHistoryCountAtTip` constancy + `trackRemap == nil`, RETIRED-REPRESENTATION (staging/handles), BEHAVIOR-GAP (3-step merged gesture: intermediate tail-trim d2, origin restore d4, single-undo revert, unmerged boundary) |

Zero architectural blockers: `SongHistory` gesture coalescing,
origin-entry dropping, and no-op short-circuiting already exist in
production (`SongHistory.swift`, `SongDocument.swift :: commit`).

### 5.8 tst_songdocument_logic.cpp — 60 sites (6 MATCHED, 9 PARTIAL, 45 GAP)

Two populations:

- **A001-A024** — `ScaleCheckTest` copied verbatim from `tst_scale.cpp`.
  Uncompiled duplicate of §5.1; terminal as RETIRED-REPRESENTATION: the
  duplicate sites live in an uncompiled file and the live native coverage
  remains in the registered `scalecheck` lane (`proof.tst_scale.txt`).
  No dependency on any scale decision.
- **A025-A060** — `NoteIdentityCheckTest`: 6 MATCHED (adoption assertions
  in `NoteChecks.swift :: adoptionAndPairing`), 9 RETIRED-REPRESENTATION
  (A025-A027 temp-file write plumbing; A041 non-throwing `adoptSmf`→
  `SongDocument(file:)` construction has no failure branch; §2.1 rules),
  1 MATCHED via throwing decode (A028 `readFile` success →
  `try MidiFile.decode` of the same bytes, failure asserted by catch),
  20 BEHAVIOR-GAP closeable with existing APIs: raw chunk/event
  classification on decode (A029-A033, A036), re-adoption reminting
  (A042-A049), `NoteID` equality blindness in `MidiEvent.==` and encoding
  (A051-A055), `PlaybackTimeline` note-ID transport (A056-A060).

## 6. What must remain native

`scalecheck` remains: it is a registered, passing native lane, and
native/QML checks are necessary blockers. Its dormant-implementation
reachability (§7) is recorded for a future user decision about the scale
feature and the dormant widget UI; this plan neither deletes it nor
changes its dispositions. Native and QML-facing checks elsewhere
(selectionkey, swiftrollgated, audio, playback, midi native engine checks)
are untouched by this plan and remain necessary blockers for their areas.

## 7. Implementation reachability — verified build-graph evidence

Checked every `CMakeLists.txt` outside `build*/`/`external/` (root,
`src/checks/CMakeLists.txt`, `src/swift/*/CMakeLists.txt`, tools):

- `porydaw` (executable) = `src/main.cpp` + resources, links whole-archive
  `porydaw_app` (root CMakeLists.txt:349-352).
- `porydaw_app` compiles only: `src/app/RewriteWindow.cpp`,
  `src/ui/songview/quick/swiftroll/native/font_metrics.cpp`,
  `src/audio/*`, `src/project/{decompproject,projectidentity,songregistry,
  songsmk,swift_project_service,samplereg,sidecar,voicegroupprojectcontext,
  voicegroupsource}.cpp`, `src/ui/{applicationstartup,keymap,layout,
  typography}.cpp`, `src/ui/theme/*`, and QML resources. **No `src/core/`
  source and none of the old widget files** (`transportbar.cpp`,
  `workspaceui.cpp`, `songview.cpp`, `scalecontroller.cpp`,
  `viewstate.cpp`, `pianoroll_gestures*.cpp`, `editordrawer/*`,
  `eventtablemodel*`) are in any target.
- `src/porydaw_scale.cpp/.h` appears in exactly one target:
  `porydaw_checks` (src/checks/CMakeLists.txt:59-60) — i.e. only the check
  binary that self-tests it. Its on-disk consumers (above widget files)
  are all uncompiled. No Swift/QML reference exists. **Recorded, not
  acted on** (§5.1/§6): the reachability finding goes into
  `proof.tst_scale.txt`'s Scope for the user's feature decision.
- Legacy `src/core/songdocument*.cpp`, `songhistory.cpp`, `smf.cpp`,
  `miditimeline.cpp`, `xcmd.cpp`, `timelineplayer.cpp` appear in **zero**
  targets. On-disk includers: dormant production sources
  (`src/project/projectworkspace.h:14` includes `core/songdocument.h`;
  old `src/ui/*` widget files) and uncompiled check originals of other
  areas (`midi/tst_midismf.cpp`, `workspace/selftest_timeline.cpp`,
  `voicegroupsave/*`, `mainwindowrouting/*`, `drawerpresentation/*`).
  Each was spot-verified against all CMakeLists (zero references).
- `mid2agb` compiles only `external/poryaaaa/ccomidi/mid2agb/*`;
  `porydaw_render_cli` links `PorydawPlayback` + poryaaaa only.

Consequence for RETIRED-REPRESENTATION no-ingress proofs: for the retired
check files the ingress proof is "the C++ file is uncompiled in every
target and unregistered in `checkcatalog.cpp`" (verified above); for the
staging mechanisms inside them, add "the Swift suite stages via Deno
fixture staging + `coreEditCorpusSongs` and never touches the C++
mechanism (`fixture.stage`, `QTemporaryFile`, `DecompProject::open`)".

## 8. Implementation-deletion gate (Task 15; cross-area)

Exact closed candidate set — only these files are even candidates, and
only after ALL seven original proofs are terminal certificates:

`src/core/songdocument.cpp`, `songdocument.h`, `songdocument_range.cpp`,
`songdocument_tempo.cpp`, `songdocument_timeeditor.cpp`,
`songdocument_timeeditor.hpp`, `songdocument_timeeditor_insert.cpp`,
`songdocument_timeeditor_xcmd.cpp`, `songdocument_xcmd.cpp`,
`songhistory.cpp`, `songhistory.h`.

Per-file gates (all must pass; any failure = keep + record blocker):

1. Zero CMake references (harness `grep` scoped to all `CMakeLists.txt`
   outside build/external — re-run fresh, never trust this snapshot).
2. Every proof naming the file under `Covered native implementation` is a
   terminal certificate (naming alone never proves cross-area value — the
   gate is the conjunction of 1+2+3).
3. No remaining on-disk includer that is itself unretired source —
   including dormant production sources. **Known blocker today**:
   `src/project/projectworkspace.h:13-14` includes `core/smf.h` and
   `core/songdocument.h`; the old widget UI files include the family
   transitively. Until the dormant workspace/widget set is itself retired
   by its own decision, the engine family stays; Task 15 records the
   blocker chain rather than deleting around it (no dead-code-bypass
   workarounds, no stub headers).

Explicitly NOT candidates (other areas' unretired originals still
reference them): `smf.cpp/.h`, `miditimeline.cpp/.h`, `xcmd.cpp/.h`,
`timelineplayer.cpp/.h`, `midiimport.*`, `m4asemantics.*`,
`mid2agbtables.*`, `velocitymodel.*`, `lanemoveplan.*`, `noteid.h`.

## 9. Retirement order

The task dependencies, source ownership, and checkpoints live in
`plan.md`'s dispatch table. Timerange and runner are proof-only early
retirements. Metadata predicates precede its certificate and the track
corpus; the track corpus precedes the songtime extraction. Document
history, edit, and track contracts precede the document certificate; note
identity follows the shared `NoteChecks.swift` checkpoint. Shared support
cleanup and the §8 implementation-deletion gate run last. Scale stays
native throughout this plan.
