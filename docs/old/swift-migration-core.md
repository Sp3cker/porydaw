# Swift migration core — historical record

Condensed 2026-09-24 from the obsolete planning set listed in §8.
Active docs/plans/swift-feature-parity stays; no source, check, or proof
ledger was edited for this record. `src/checks/**/proof.*.txt` retained.

Recovery provenance: worktree HEAD `1096534c` at condensation time; owned
paths below were unmodified in `git status`. Coverage ledger baseline
`referenceRevision 0c1d3cd5`; T7 checkpoint `97dc7fea`; pre-deletion battery
revision `45a52d80`. Full plan text recoverable from Git history of the
deleted paths.

## 1. Governing charter (was `swift-backend-charter.md`, normative)

- Precedence: charter + `qtbridge-integration-contract.md` governed the core
  rewrite; the earlier ownership design (M1/M2) was historical.
- Approved incremental scope (2026-09-19): user permits unmigrated editors to
  be **absent** from the rewrite app (not rendered/instantiated/compiled).
  Preserve their song data and core editing semantics, not their
  availability. No reverse legacy-client adapter.
- Prime directive: production conversion, not prototype. No workarounds
  without root-cause approval; no parallel implementations kept "until
  later"; destination Swift/QML is built to stay.
- Core independence over test-host convenience: never weaken Swift API,
  representation, ownership, isolation, or errors for C++ testability —
  change the harness instead. Declarations-first file ordering (public
  surface before private bodies) preserves the one interface-read advantage.
- Compatibility (2026-09-18): user behavior + permanent host interfaces bind;
  migration-only machinery (demo APIs, fixture loaders, parity adapters)
  creates no contract. INV-1 one keymap source; INV-2 arbitration moves
  wholesale, never mixed tiers; INV-3 one host authority, bands are not
  window dispatchers.
- Seam rules S-1..S-5: preserve the behavioral oracle (don't edit references
  to hide mismatches); native transport confined to adapters, Swift-to-Swift
  never serialized through C; undoability is existential — one transaction
  per gesture into one history; four cancel reasons
  (`FocusLost/PointerUngrabbed/Hidden/WindowDeactivate`) are contract;
  compute expected values with live dual-run sweeps, don't freeze them.
- Platform: Windows **deferred, not dropped**; when it returns it builds with
  **MSVC** (`msvc2022_64`). MinGW was never a decision. No MinGW
  accommodations anywhere in this track.

- Direction: Swift application/domain logic + QML views, minimal handwritten
  C++ Qt app code. Two distinct seams: QML↔Swift presentation and
  Swift↔retained native services (audio). No universal dispatcher.
- Swift domain types are never shaped around C ABI layouts; C structs,
  pointer/count buffers, and callback contexts stay inside adapters.
  Fixed-width numerics for musical ranges are domain types, not C leakage.
- Recorded baseline 2026-09-19 (`swift-qml-grid` @ `bc24c98d`, source
  inspection only — runtime rows Unverified): Qt 6.11.0 Homebrew, Apple
  swiftc 6.3.3, `Swift_LANGUAGE_VERSION 6`, `-cxx-interoperability-mode=default`,
  QtBridge pin `407714006dd21107b70db6547ce75e43df0c8a75` (early-preview
  `qt/qtbridge-swift`), Qt 6.10 CorePrivate required.
- Local patch `qtbridge-object-return.patch` (179 lines, 8 hunks, **not
  upstreamed**): object-return macro support, optional bridged-object
  conversion, public QML registration, QVariant optionals, genuine
  `beginMoveRows/endMoveRows` list moves (tab-strip reorder, 2026-09-21).
- Prospective only: in-process Qt Quick Test hosting via `QTestAppCpp` +
  own `Qt6::QuickTest` link; pinned `QTest.swift` is not compiled in. The
  camera/drawer plan's `EditorSurface.qml` extraction (property-injected
  composition) is the testable path — recorded, not verified.
- Swift 6.4 was installed but unqualified at the time: the plans kept the 6.3.3 evidence standing and required the controller to record the selected compiler/SDK/deployment/flags/pin before accepting affected work (historical qualification requirement of those plans, not a new dispatch). No SwiftPM migration; macro-build compiler selection audit only.

## 3. Core rewrite scope (was `swift-core-rewrite/`, supersedes M1/M2)

33 files under `src/core/` (9,409 lines) → native Swift under `src/swift/`;
piano grid first direct consumer; then stop. Sequencer (`TimelinePlayer`)
rewritten in Swift, not moved to `audio/`. Native device/DSP, instrument
loading, project-file services, small Qt host retained.

| C++ source | Swift destination | Task |
| --- | --- | --- |
| `smf`, note/tempo/track vocabulary, m4a semantics/velocity tables | `MidiFile`, `MusicTypes`, `MidiSemantics` | T1 codec + primitives |
| `songhistory`, `songdocument` (+tempo/xcmd parts) | `SongHistory`, `SongDocument`, `Note/Event/Xcmd/TimeEditing` | T2 doc/notes/history; T3 tracks/raw/lanes/import; T4 range/time |
| `miditimeline`, `timelineplayer` | `PlaybackTimeline`, `playback/Sequencer` | T5 timeline + scheduler |
| project services, sessions | `ProjectService`, `Document/ApplicationSession` | T6 persistence/session |
| cutover host | `RewriteWindow`, `NativeAudio`, `native_host.h` | T7 runtime cutover |
| grid feeds/executor/mount | direct `PianoGrid(session:)` consumer | T8 grid, then stop |

Task briefs T1–T8 were per-boundary execution slices with closed write sets
and frozen native boundary (deletions + mechanical maintenance only after
T7). Milestones: storage accepted (T1) → core accepted, old core gone, editor
area intentionally absent (T2–T7) → one consumer accepted (T8, terminal).

Recorded execution state: T7 accepted/checkpointed at `97dc7fea` (grid
conversion already present: `PorydawApp` membership, `gridPresenter()`,
`NoteCommands`/`Clipboard` on `pd_clipboard_write/read`,
`swiftrollgated` real-window suite). T8 amended to verification +
coverage-closure + obsolete-source retirement only. Pre-deletion battery at
`45a52d80`: full `deno task verify` PASS; 7B oracle/core deletion blocked on
T8 adjudication. Reticle/raster repairs (selection-fill alpha 30/255,
`selectionRing` role, note/chrome raster slots under `swiftrollgated`)
passed all 18 harnesses — bounded fixes, not coverage acceptance.

## 4. Ownership cutover history (was `swift-ownership-cutover/`, superseded 2026-09-19)

- M0 probe (`swiftqtml` harness, real QML delegates) + swift-org rehome
  (`swift-grid-prototype/` → `swiftroll/`, dead-code retirement with
  zero-caller evidence) were the only executable slice; M1/M2 proposals
  rejected for the rewrite, never dispatch.
- Retained proof reference (do not edit proofs): `src/checks/swiftqtml/proof.tst_swiftqtml.txt:836-838` quotes the deleted `src/checks/swiftqtml/` harness originals, naming `docs/plans/qtbridge-integration-contract.md` as the evidence home of the M0 object-argument capability probe (recorded there as Unsupported-after-SIGSEGV at that pin+patch; the probe must not be re-executed in-check). The M0-probe brief deleted above is the design record for that harness; both recover via Git history, not this record.
- M2 gate inventory (2026-09-19 @ `bc24c98d`): every mutation routes through
  `SongDocument`'s typed command API into one owned `QUndoStack`
  (`songdocument.h:621-622`); 17 surfaces / 50+ call sites enumerated
  (ruler, lanes, automation, event list/table, range/clipboard, voice ops,
  headers, velocity, legacy pianoroll, config, async voice-bank).
- Rejected recommendation: bounded shared legacy-client adapter (option B)
  and two-consumer M1a/M1b staging — moot once unmigrated editors were
  approved absent. C ABI frozen; no new `sg*` symbols.
- Durable mechanics preserved into the rewrite spec: async shared-bank
  protocol (worker-confirmed pushes, two-phase undo/redo crossing, conflict
  obsolescence, scalar merge sealing); save identity (canonical SMF +
  revision/token/identity, stale-save refusal); lock-free `TimelineHandoff`
  playback publication with mid-playback controller/voice chase.

## 5. Coverage ledger disposition (deleted `coverage-ledger.json`, 978 KB)

Purpose: case-by-case baseline inventory (Task 1 deliverable): every
registered QTest row identity mapped to a Swift/retained-native target,
`dueTask`, classification, and run evidence. Final state: 845 rows —
455 verified, 291 pending, 59 deferred-ui, 40 excluded; by due task
T8:293 / T7:146 / T3:127 / T6:57 / T5:54 / T2:36 / T4:23 / T1:20 / none:89.

Obsolete because: per-row acceptance lives on in the live proof ledgers
(e.g. `src/checks/support/corecheck/proof.tst_swiftcore.txt`, ref
`59f48ea0`) and the T7/T8 adjudication records in `plan.md` §§ preserved
above; the giant table's command/revision labels were explicitly marked
historical-parity-only, not executable acceptance. Git history of the
deleted path is the recovery source.

Unique conclusions retained (not the table): T8's 43 in-scope-core rows =
29 verified + 14 pending — five `automation-domain/*` + five
`vgsavecheck/*` unapproved exclusion recommendations, four
`clipcheck`/`clipmimecheck` rows with no executed equivalent for native MIME
transport/routing facets. Absent-surface suites report **deferred, never
passing**. No C++ core/oracle deletion while the retirement gate is open;
post-cutover proof requires mapped retained cases still executing on Swift.

## 6. Undo/redo compatibility audit (deleted report, findings preserved)

Verdict stood: **do not accept history parity or retire the C++ reference on
that evidence** — architecture (one history, typed reversible change sets
amending whole-snapshot history, 2026-09-19) approved, behavior not yet
proven. Frozen snapshot (`bdb63b53` + working changes; Swift 6.3.3 probe):
H1 Critical reproduced — suspended bank undo could skip a newer edit and
mark unsaved data clean (index ownership across suspension); H2 two further
source-confirmed bank-history mismatches (initial/stale-conflict policy
nuance); H7 coverage claims not establishing named reference behavior.
Earlier blanket-`expect(true)` block already absent from the frozen
snapshot. Implementer owned repairs; C++ reference stayed until Swift
behaviors + real-UI cutover demonstrated.

## 7. Historical unresolved findings (as of the deleted plans — not current status)

These were open at the time of the source snapshots below; later work may
have superseded any of them. Consult the active plan
(`docs/plans/swift-feature-parity/`) and current proofs before treating any
as still true:

- Leading-edge resize one-transaction-per-gesture limitation open (Wave 4
  `fe1ff4df` closed only the re-scoped grid milestone).
- T8 acceptance pending with the 14 rows in §5 unresolved.
- Runtime QtBridge rows, DPR/font matrix, fractional scroll/zoom, ghost
  projection, unmounted-surface baselines unverified.
- All plan commands/revisions are historical labels, not re-runnable
  acceptance without fresh controller execution.

## 8. Manifest

Deleted (20): `swift-core-rewrite/plan.md`, `spec.md`, `task-1..8-brief.md`,
`undo-redo-compatibility-report.md`, `coverage-ledger.json`;
`swift-ownership-cutover/plan.md`, `design.md`, `m1m2-gate-decisions.md`,
`task-m0-probe-brief.md`, `task-m1a-brief.md`, `task-swift-org-brief.md`;
`swift-backend-charter.md`; `qtbridge-integration-contract.md`.
Retained: all `src/checks/**/proof.*.txt` and sources; active
`docs/plans/swift-feature-parity/`. `coverage-ledger.json` was the sole
non-Markdown file owned and removed (disposition §5).
