# task-5-brief.md — Voicegroup service data, bank load, and undoable `-G`

## Context

The Swift rewrite already has the song-list service baseline: `PdSongListEntry`,
`pd_service_list_songs`, and `ProjectService.songs()`. Do not reimplement that
work. This task adds the project voicegroup catalog, sample/keysplit browse
payload, and canonical bank-load operation consumed by the voicegroup panel,
sample picker, and undoable `-G` selector. It also completes `DocumentSession`
configuration undo/redo rebinding and preserves service-backed bank-history
behavior when a source is replaced.

Relevant compiled service-path sources: `VoicegroupSource::catalogScan`,
`directSoundCatalog`, `progWaveSymbols`, and `keysplitInstruments`
(`src/project/voicegroupsource.h:326-358`); worker-owned
`DecompProject::loadSampleSet` / `loadBank` (`src/project/decompproject.h:151-159`);
`DocumentSession.save`, `undo`, `redo`, and `adoptBank`
(`src/swift/app/DocumentSession.swift:248-369`); `ServiceBankAction`
(`src/swift/app/ServiceBankHistory.swift`).

## Exact write set

- `src/project/swift_project_service.h` — catalog, sample-browse, and
  bank-load C payloads, callbacks, and declarations.
- `src/project/swift_project_service.cpp` — the three worker operations.
- `src/swift/app/ProjectService.swift` and
  `src/swift/app/ProjectServiceCallbacks.swift` — owned Swift values and
  completion copies.
- `src/swift/app/DocumentSession.swift` — `setVoicegroupArgument(_:)`,
  config-change undo/redo rebinding, and the observable clean-save result.
- `src/checks/voicelist/voicegroup_payload.swift` — new service/session
  scenarios.
- `src/checks/workspace/SessionChecks.swift` — dispatch the new scenarios
  from `runProjectSessionSuite`.
- `src/checks/CMakeLists.txt` — register the new Swift check source.

## Prerequisites

Task 1's song service is accepted M0 baseline, not new implementation scope.
Keep its shared bridge/`ProjectService.swift` ownership serial with this task:
add Task 5's independent catalog/sample/bank operations only after the
baseline ownership is closed, leaving the song-list operation unchanged.
Task 6 consumes this task's catalog and `-G` interfaces.

## Interface contract

Spec sections 4.1 and 4.2. Exact behavior:

- **Voicegroup catalog** — one asynchronous service operation copies
  `VoicegroupSource::catalogScan(projectRoot)`,
  `directSoundCatalog(projectRoot)`, and `progWaveSymbols(projectRoot)` into
  owned Swift values. Include keysplit pairs (subvoicegroup symbol to table
  symbol), drumkit symbols, typical ADSR by symbol and family, DirectSound
  symbols, programmable-wave symbols, synth definitions, synth macro words,
  and `perFileVoicegroups`. Set that Bool from actual existence of
  `projectRoot/sound/voicegroups`, matching the native catalog gate. Include
  the flag on every successful catalog completion; do not infer it from
  selector args or fabricate `false` for a failed/missing catalog result.
  `VoicegroupCatalogData` is `Equatable, Sendable`. Task 9 consumes
  `perFileVoicegroups` from this compiled payload as the creation gate; do not
  add a Swift-side filesystem probe. Do not put `groupArgs` in this payload:
  existing `pd_service_voicegroup_args` and `ProjectService.voicegroupArgs()`
  remain the sole selector feed. A missing project `sound` directory is a
  failed completion, not a successful empty catalog; a valid project with
  empty optional synth data remains valid.
- **Sample browse result** — add
  `sampleBrowseData(symbol:auditionKey:)`, with `auditionKey` defaulting to
  `60`, and return `SampleBrowseResult`: `.playable(SampleBrowseData)` or
  `.refused`. Refusal is an expected native no-play outcome, never a
  success-shaped empty payload or thrown user-facing operation error; genuine
  project/loader failures remain service errors. A DirectSound input returns
  signed PCM bytes, frequency, loop flag, and loop start (`WaveData.status &
  0x4000`; one-shots use start `0`); a programmable-wave input returns its
  16 packed bytes. A keysplit input resolves its catalog-paired
  `LoadedKeysplit`, indexes the requested key (Task 8 must use key `60`),
  bounds-checks the table entry, and returns `.playable` only when the
  resolved non-nested leaf has a valid DirectSound sample payload or
  16-byte programmable-wave payload. A PCM leaf carries the child's ADSR and
  key; a programmable-wave leaf carries the child's ADSR. Return `.refused`
  for an unknown/unavailable source, invalid/overflow table index, nested
  split, missing payload, CGB square/noise child, or any other unsupported
  tone. Preserve `MainWindow::auditionKeysplit`'s no-play behavior: refusals
  start no audition and create no new user-facing operation error.
- **Bank load** — `pd_service_bank_load` clones the canonical
  `playableSong(label)` `SongInfo`, sets its `cfg.voicegroupArg`, maps an
  empty argument to `"_dummy"` as `makeCfg` does, then calls the canonical
  `loadBank` path. Return the existing `PdBankEditCompletion` shape with
  `PD_BANK_EDIT_APPLIED`, copied bank slots/lease, and token `0`; report hard
  load errors through the failed completion. Do not bypass the service's
  bank identity/cache behavior.
- **Undoable selector commit** — `DocumentSession.setVoicegroupArgument(_:)`
  records `document.setConfig` as an ordinary undoable document change.
  Empty and `"_dummy"` compare as the same selector value; selecting the
  current value is a no-op. Guard against `bankPersistenceInFlight` and
  `document.history.bankTransitionInFlight`. On a successful canonical load,
  adopt the new lease and publish `.document`, `.bank`, `.dirty`, and
  `.history`. On load failure, retain the prior bank and lease, keep the
  already-recorded config change undoable, publish `.document`, `.dirty`, and
  `.history` without claiming a bank change, and throw so the shell can show
  the error.
- **Undo/redo** — capture the `-G` value before history traversal. If a
  successful document-history crossing changes it, load and adopt the matching
  bank before publishing. A failed rebind preserves the old lease/slots,
  publishes the changed config/history state, then propagates the error.
  Bank edit history continues to replay value edits and one-shot blank-slot
  materialization tokens against the canonical source identity after
  `-G` source replacement; do not restore stale whole-file bytes.
- **Clean save result** — `DocumentSession.save()` returns
  `SaveReceipt?`: `nil` for a clean session without calling the service and
  the service receipt for a performed save. Mark it `@discardableResult` so
  current app callers that intentionally ignore the receipt remain valid.

## Implementation steps

1. Add flat C structs with pointer/count arrays and completion callbacks.
   Include `perFileVoicegroups` in the catalog payload and set it from the
   actual `sound/voicegroups` directory query on successful scans; never
   replace a missing/failed catalog result with a default `false`. Keep
   callback memory borrowed only until completion returns, matching existing
   service operations.
2. Implement catalog, sample-browse, and bank-load worker operations inside
   compiled `PdProjectService`. Catalog uses the existing `VoicegroupSource`
   accessors without duplicating `pd_service_voicegroup_args`; include the
   actual `perFileVoicegroups` directory result in the same successful
   catalog completion. Sample browse calls worker-owned
   `DecompProject::loadSampleSet`, resolves the requested keysplit table
   entry to its actual non-nested leaf, and copies only the supported PCM or
   programmable-wave payload and required playback fields. Encode expected
   no-play cases as an explicit refusal completion with no sample payload;
   use the failed completion only for genuine project/loader errors. Free
   the set with `voicegroup_free_samples`; do not call the UI
   `ProjectWorkspace` or sample-import/DSP modules.
3. Add Swift `VoicegroupCatalogData` (including the required
   `perFileVoicegroups` Bool), keysplit/ADSR/synth value types,
   `SampleBrowseData`, and `SampleBrowseResult` (`.playable` or `.refused`);
   copy all callback data once into owned `Equatable, Sendable` values. Keep
   expected refusals separate from thrown project/loader errors. Add
   `voicegroupCatalog()`, `sampleBrowseData(symbol:auditionKey:)`, and
   `loadBank(label:voicegroupArg:)`.
4. Implement the selector commit and undo/redo rebinding contract. Return
   `nil` on the existing clean-save early return and return the actual receipt
   on the dirty-save path.
5. In `voicegroup_payload.swift`, stage the fixture project and exercise:
   - on `stageTestProject`, `voicegroupArgs()` contains `"_test_vg"`
     independently of the catalog; assert empty keysplit/drumkit and
     synth-definition/macro datasets remain valid empty arrays;
   - on `CheckEnvironment.fixtureRoot` after `richVoicegroupFiles()`,
     assert the catalog contains fixture DirectSound/prog-wave symbols,
     keysplit pairs, drumkits, typical ADSR entries, and
     `perFileVoicegroups == true`;
   - stage a valid single-file layout with `_test_vg` in
     `sound/voicegroups.inc` and no `sound/voicegroups` directory; assert the
     successful catalog retains `_test_vg` and explicitly reports
     `perFileVoicegroups == false`. Use the returned flag, never a Swift
     default or an empty fallback;
   - catalog outage: hide the staged `sound` directory, assert the catalog
     operation fails, restore it, and assert recovery succeeds;
   - sample data: `DirectSoundWaveData_fixture_loop` returns `.playable`
     looped PCM with valid frequency/start, and
     `ProgrammableWaveData_fixture_saw` returns `.playable` with 16 bytes.
     Stage key-60 keysplit cases for playable PCM and wave leaves; assert the
     PCM leaf's ADSR/key and wave leaf's ADSR. Square/noise leaves,
     unknown/missing sources, invalid/overflow entries, and nested splits
     return `.refused`, not a thrown/user-facing operation error; genuine
     project/loader failures remain service failures;
   - selector/rebind: `selectorSwitchUsesUndoableCfgEdit` changes config and
     bank together, undo/redo restore both, and
     `failedRebindRetainsBinding` keeps the prior lease/slots while the
     config remains changed and undoable;
   - `switchCarriesUnsavedBankEdit` preserves the unsaved home-bank edit
     across an away/back `-G` change;
   - `valueCommandSurvivesSourceReplacement` and
     `blankTokenRebasesAcrossSourceReplacement` undo/redo against the
     refreshed source while preserving unrelated source bytes;
   - `cleanSaveEmitsNoReceipt` first saves a bank-only dirty session and
     asserts a nonnil receipt with a bank result; a subsequent clean save
     returns `nil` and leaves the lease and on-disk song/bank bytes unchanged.
6. Register and dispatch the scenario file using the existing
   `swift_core_check` / `runProjectSessionSuite` path.

## Acceptance predicate

- `deno task build:checks` succeeds.
- `deno task verify --filter swiftcore --verbose` passes the named catalog and
  `perFileVoicegroups` true/false, sample/refusal/keysplits, rebind,
  source-replacement, and bank-only-dirty-receipt / clean-nil scenarios.
- The final integrated validation owner runs these gates once after all task
  edits settle; no native desktop is required for this task's SwiftCore
  scenarios.

## Task-specific constraints

- Keep `pd_service_voicegroup_args` and `ProjectService.voicegroupArgs()` as
  the one source of `-G` choices; never add a second `groupArgs` payload.
- This is the only existing save API signature change:
  `DocumentSession.save()` surfaces its optional receipt. Keep
  `ProjectService.save()` and its ordered-write behavior unchanged; likewise
  preserve `openSong`, `bankApply`, and `bankRevert` semantics. Do not add
  duplicate service-save behavior.
- Preserve the sample/wave bytes and playback fields needed by Task 8.
  Task 8 must request keysplit key `60`, audition only `.playable` PCM or
  programmable-wave results, and handle `.refused` as no playback without
  inventing a user-facing operation error. CGB square/noise keysplit children
  remain intentional refusal cases.
- Implement catalog, read-only sample-browse, and bank-load operations through
  the compiled `PdProjectService` worker and `ProjectService` bridge. Use the
  worker-confined `DecompProject::loadSampleSet` / owned loaded values for
  sample payloads; do not call `ProjectWorkspace`, uncompiled `ProjectIo`
  command inputs, or sample-import/DSP editor modules.
- Do not edit C++ widgets, QML, proof ledgers, frozen fixtures, or other
  task briefs.
