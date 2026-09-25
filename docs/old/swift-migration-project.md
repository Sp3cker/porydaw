# Swift migration project — historical record

Supersedes the deleted proposal plans `docs/plans/swift-project-store/`
(8 files) and `docs/plans/swift-dock-lists/` (18 files). Those were
pre-implementation proposals and work queues, not as-built documentation.
Do not treat anything below as a fresh work queue.

Status at time of archiving (HEAD `1096534c`): the ProjectStore Swift
implementation is already integrated per the active baseline, and the
dock-lists migration state is owned by the live sources, checks, and
`docs/plans/swift-feature-parity` (retained). Open proposal tasks below
are historical unknowns — not claims about what exists today and not
assignments to do them.

## 1. Project-store proposal (what it proposed)

Port everything behind the `PdProjectService` C seam (serial-thread worker
owning `DecompProject`) into a new Swift static library `PorydawProject`
at `src/swift/project/`. Freeze the public surface of
`src/swift/app/ProjectService.swift` (`open`, `songLabels`, `openSong`,
`save`, `bankApply`, `bankRevert`, `close`; `LoadedSong`, `SaveReceipt`,
`AppliedBankEdit`, `BankVoice`, `BankSlotView`, `NativeBankLease`,
`SongConfig`, `SongSource`; `serviceClosed`/`operationFailed`/
`bankConflict`; verbatim error strings such as `"No playable song named %1."`).

### Durable decisions worth keeping

- **Surviving C++ is only the lease box.** `src/project/banklease.{h,cpp}`:
  `VoicegroupLease` + verbatim wrap/discard/borrow, opaque `PdBankLease`
  box (`pd_bank_lease_adopt`/`release`/`bank_token`/`native`) plus
  `borrowVoicegroupLease`; Qt-free, POSIX-free, MSVC-clean, `poryaaaa` native via modulemap.
- **Dead surface is deleted, not ported.** `synthDefinitions` write path
  dead (always `{}` → `mapsChanged` always false): no synth-definition
  write/ensure/reopen/prune. `registrationGaps` never crosses the seam
  (no `PdSongMeta` field): no registration/removal-plan port.
  SampleReg/Sidecar/ProjectIo/ProjectWorkspace + widget corpses uncompiled — delete, never shim.
- **Lease semantics (frozen contract):** reuse across shared voicegroups,
  replace-on-edit, old-lease readability, single-shot materialization
  tokens. `bankConflict` for stale-expected/occupied-blank/out-of-range/
  spent-token; no partial revert — a failed edit leaves bank, dirty flag,
  and source bytes exactly as before.
- **Conflict taxonomy:** expected-mismatch and validation no-ops are
  `.conflict` (confirmed not-applied), never throws; hard native failures
  throw `operationFailed`. Save is persist + reload + memo refresh only —
  no context swap, no synth payload, no `mapsChanged` branch.
- **Byte conservation:** `.inc` parser keeps raw/indent/macro/arg/tail
  splits with `\r` preserved; save differs from pristine only on edited
  voice lines. Preview shadow basename must equal `loadName`.
- **Slot stability:** sparse blank-slot materialization uses the
  `voice_group NAME[, startingNote]` convention plus silent square-wave
  padding so existing slots never shift; revert is a narrow byte-exact
  delta, never a whole-buffer restore.
- **Structural-vs-scalar taxonomy:** only macro or sample/wave symbol flips
  are structural (force reload path); envelope/pan/key/sweep/duty/period
  edits stay scalar. `vgAdsrFamily` collapses `_alt`/`no_resample` onto
  base, `-1` for keysplit/drumkit.
- **Threading:** `ProjectStore` actor on a dedicated-thread serial executor,
  never the cooperative pool; `VoicegroupProjectContext` worker-confined.
- **Paths:** pure-String lexical normalizer replicating `QDir::cleanPath` +
  `VoicegroupId` rejects; `completeBaseName` = LAST-suffix strip;
  `isAbsolutePath` covers `/`, `X:\`, `X:/`, `\\` (non-ASCII Windows roots may differ at poryaaaa `fopen`; noted, never fixed).
- **Windows-first-party constraint:** only Foundation APIs with real Windows
  implementations; never `FileManager.replaceItem`, CryptoKit, Dispatch, NSString path helpers; C++ MSVC-clean.
- **History seam:** `SongHistory.markSaved(_:)` seals an adjacent
  *document* entry but not a bank entry; explicit `sealBankMerge()` seals
  only the top bank entry. `DocumentSession.applyBankEdit` seals on a
  clean bank before `beginBankTransition()`; failed applications record
  nothing. (Proposed; verify against live `SongHistory.swift`.)
- **Flip intent:** check filter names (`vgbankcheck`,
  `exportcheck-loop/tail`) preserved; Apple-gated Swift lanes documented as
  expected-absent off Apple.

### Check-porting dispositions (historical intent)

- `workspace/*.swift` suites unchanged (flip regression net).
- `proof.identity.txt` A001–A036 → `ProjectIdentityChecks`, A037–A052 dropped.
  `proof.mk.txt` rows → `SongsMkChecks`/`tst_midicfg`; `proof.save.txt` midi.cfg rows → `tst_midicfg`.
- `proof.ioflow`/`iomutations`/`workspace`/`ignore` retired (dead
  transport/surface). `proof.voicegroupsourceediting.txt` +
  `proof.savecore.txt` → `VoicegroupStoreChecks`.
  `proof.voicegroupsourcecatalog.txt` retired (dead surface).
- Live `vgbankcheck` → `bankleases` suite; `exportcheck-loop/tail`
  rewritten as Swift suite + native bridge; audio/playback natives
  untouched against the lease shim.

## 2. Dock-lists proposal (what it proposed)

Build Songs + Voicegroup surfaces into the Swift rewrite shell
(`RewriteWindow` + `SwiftRollOverlay.qml`) reusing existing owners:
`SongListPresenter`, `VoiceListController` (never a new presenter),
`ProjectService`, `DocumentSession`, `NativeAudio`. QML renders and
forwards; no duplicated business rules. New-song wizard excluded.

Supersession notice: the C++ worker-bridge APIs named below for voicegroup
creation (`pd_service_create_voicegroup`) and sample probe/read/commit
(`pd_service_probe_samples`, `pd_service_read_sample`,
`pd_service_commit_sample`) were historical proposals only. They are
rejected/superseded under the active Swift-only plan — behavior contracts
survive, the named interfaces must NOT be implemented.

### Durable behavior contracts

- **Songs:** resolve selection by `SongListRow.songId` at the
  `openSong(label:)` boundary; never row index or display label. Find Song
  on the existing `songs.find` keymap ID via `focusSearch()` and QML
  `searchFocusRequest`; search-field bare Space goes to transport,
  Up/Down/PageUp/PageDown to the list. Register/delete are functional
  confirmation flows (cancel = no mutation; conflicts/errors reported;
  listing refreshed after success).
- **Voicegroup `-G` rebind:** reuse `pd_service_voicegroup_args` and
  `voicegroupArgs()` as the single sorted argument list.
  `setVoicegroupArgument(_:)` records an undoable cfg edit, loads a fresh
  bank, adopts and publishes; undo/redo rebind before publication. Failed
  rebind keeps the prior lease; catalog outage fabricates nothing; clean save stays receipt-free.
- **Voice list/editor:** 128 stable rows; preserve `BankSlotView.tone`
  fallback when no parsed `BankVoice` exists; keep the `structural`
  callback flag through the QML/controller path; blank materialization,
  readonly/broken notices, family controls, keysplit/drumkit handling,
  ADSR history, conflict/undo behavior per the native oracle.
- **Keysplit audition:** resolve row-browse via `table[60]`; reject
  invalid/nested targets silently without recursion or fallback. Valid
  direct Sample leaf: MIDI 60 + leaf `ToneData.key` as `toneKey` + leaf
  ADSR; Wave leaf: MIDI 60 + leaf ADSR, no `toneKey`. Square/noise stay
  silent (native refusal), never fabricated.
- **Picker/synth:** Sample/Wave/Keysplit browse audition preserved with
  exact samplepicker pins incl. `vgSamplePickerList`; picker changes the
  pending draft, commit stays the `applyBankEdit` path. Synth minting is
  session-scoped, memory-only until save; clean save receipt-free.
- **Voicegroup creation (behavior only; C++ API superseded):** assignment
  via the undoable `-G` path; undo restores the prior assignment without
  deleting the created file. Name grammar `[A-Za-z][A-Za-z0-9_]*`,
  duplicate-checked against `"_" + name` in `voicegroupArgs()`.
  Single-file layouts show unsupported-layout info and do nothing; per-file vs monolithic gated by `perFileVoicegroups`.
- **Sample New/Edit (behavior only; C++ APIs superseded):** New accepts
  audio import or SF2 zone; stereo phase-cancel offers left-channel-only
  re-import; names validated `^[a-z0-9_]+$` live; source hash + import
  params stored in sidecar; commit refreshes catalog and assigns through
  one `applyBankEdit`. Edit requires a project-sample DirectSound voice,
  name read-only; sidecar source re-imported only on hash match, else
  committed WAV fallback with stale provenance removed. Sidecar write
  failure stays distinct from WAV commit result; cancellation mutates
  nothing; a later assignment failure does not roll back a committed sample.
- **Dock layout:** one shared left dock column; outer width persisted
  `swiftDock/columnWidth` (default 280, clamped 200–480); inner
  Songs-over-Voicegroup `SplitView` with `songsRatio` default 0.5, clamped
  so both panes keep controls + one full row and scroll independently.
  Editor adapts within the saved width, never forces the dock wider, and
  scrolls at short pane heights.
- **Visual pins (frozen, historical):** songlist, voicegroupbrowser (incl.
  sample buttons/regions), `editor-square1`/`editor-readonly`,
  samplepicker (incl. `vgSamplePickerList`), and sample-editor dialog
  pins — names only; sizes/regions live in the deleted briefs and frozen
  baselines.
- **Sample lifecycle (historical requirements):** `editor`/`integration`/
  `project` oracles with 1:1 `samplecheck/SampleProcessingTest` method
  identity; `engineLoop` headless, `pipelinePrefillCollision`/`pipelineRateCommit`
  QML-only; sidecar v1 (abspath, SHA-256, leftOnly, sf2Zone, full params).

### Incomplete paths / explicit unknowns

- Samplecheck ledgers were left mostly unmapped (GAP/NATIVE) with per-site
  correspondence gating any source retirement; a matching `cppID` alone
  never proved a site, and `deno task proof check` is structure-only —
  live tree owns whether they were since retired.
- The allowlisted source-deletion set was gated on every retired assertion
  being `MATCHED`; mixed/blocked ledgers kept. Do not assume it ran.
- Within this dock scope, the modal sample editor's focused audition
  control consuming bare Space was the sanctioned local exception to
  Space-goes-to-transport; current rules additionally except modal/text
  entry contexts — see the live keybinding contract, not this record.

## 3. Provenance

- Originals: `docs/plans/swift-project-store/{plan.md,spec.md,
  briefs-s1.md,briefs-s2.md,briefs-s3.md,briefs-s4.md,briefs-s5.md,
  briefs-s6.md}` and `docs/plans/swift-dock-lists/{plan.md,spec.md,
  task-1-brief.md,task-2-brief.md,task-3-brief.md,task-4-brief.md,
  task-5-brief.md,task-6-brief.md,task-7-brief.md,task-8-brief.md,
  task-9-brief.md,task-10-brief.md,task-11-brief.md,task-12-brief.md,
  task-13-brief.md,task-14-brief.md,task-15-brief.md,task-16-brief.md}`.
  Every assigned file is byte-identical to revision `1096534c` (that pin
  covers only these assigned docs; the full tree had unrelated concurrent
  work, and the deletions are uncommitted): recover any one with
  `git show 1096534c:<path>`. Do not reconstruct old plans from this
  summary.
- Pinned revisions seen in the plans: store plan `75ce445d`, lease-box
  extraction `d2558e14`; dock plan correction `4c52acd8`, audition parity
  `76832a3e`; samplecheck reference revisions
  `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea`
  (analysis/editor/integration/project/soundfont)
  `5af4355e8fc1337f38da60c545da4af246160bcf` (decoder)
  `1f9f8a5faa78069bf86c0ed9997c04c07f1f37d7` (dsp); viewcache oracle
  `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea` with original SHA-256
  `d15a353f65745a70977fdbd756cd37e87e25d71940b5b6d5ac1267702e2dd693`.
  Per-inventory original SHA pins lived in the deleted task-14 brief.
- Navigation: behavior in `src/swift/project/` (or successor),
  `src/swift/app/ProjectService.swift`,
  `src/swift/app/DocumentSession.swift`,
  `src/swift/core/SongHistory.swift`; checks in `src/checks/projectstore/`,
  `workspace/`, `voicelist/`, `songlist/`; baselines under `src/checks/fixtures/visual/`.
