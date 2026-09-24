# Seam S6 briefs — flip cutover (Tasks 27–32)

## Task 27: native_check off DecompProject

### Context

`src/checks/support/corecheck/native_check.cpp` includes `project/decompproject.h` and resolves songs through `DecompProject::songs()` (`songWithLabel`). The S5 ProjectStore actor now owns project state. This task cuts the helper off `DecompProject` so Task 31 can delete it, without changing any `pdc_check_*` behavior.

### Exact write set

- `src/checks/support/corecheck/native_check.cpp` — replace the `DecompProject` song lookup with the S5-owned project-state song table; remove the `project/decompproject.h` include.
- Nothing else. `native_check.h` signatures are frozen.

### Prerequisites

- S5 ProjectStore actor landed with a readable published song table (label, playability, flags) for the open project.
- plan.md Global Constraints apply; no deltas beyond this brief.

### Interface contract

- All `extern "C"` exports in `native_check.h` keep exact signatures and semantics: `pdc_check_set_fixture_root`, `pdc_check_fixture_root`, `pdc_check_set_mid2agb_path`, `pdc_check_midi_exports`, `pdc_check_compile_saved_midi`, `pdc_playback_engine_*`.
- The 14-song `kRoundtripSongs` set is unchanged; playability filtering (`song.isPlayable()`) is preserved row-for-row through the new accessor.
- mid2agb compile-and-compare semantics (flags, output `.s` handling, failure bits) are byte-identical; only the song-table source changes.

### Implementation steps

1. Remove `#include "project/decompproject.h"` from `native_check.cpp`.
2. Reimplement `songWithLabel` over the S5 ProjectStore actor's published song table, preserving the label + playable-only match and the null-on-miss return.
3. Keep every other function body untouched; no new helpers, no signature changes.
4. Confirm no remaining `DecompProject` reference in `src/checks/support/corecheck/`.

### Acceptance predicate

- `grep DecompProject src/checks/support/corecheck/` returns zero hits.
- NAMED CHECKS:
  - `deno task verify --filter swiftcore --verbose` — covers the `pdc_check_midi_exports` path including the re-sourced song lookup, plus the XCMD traffic predicates.

### Task-specific constraints

- Do not touch `native_check.h`, the playback-engine fixture, or `mid2agb` invocation logic; this task re-sources one lookup.
- Filter names are frozen (filter-name preservation): nothing in the check catalog changes in this task.

## Task 28: exportcheck Swift rewrite

### Context

`src/checks/midi/tst_midiexport.cpp` (`MidiExportTest`, 4 cases) drives `pd_service_*` directly against a `DecompProject` fixture root. It is rewritten in Swift against the S5 ProjectStore actor in the new checks home `src/checks/projectstore/`. The C++ file stays on disk until Task 31; the catalog still points at it until Task 32.

### Exact write set

- New `src/checks/projectstore/ExportChecks.swift` — Swift port of all 4 `MidiExportTest` cases.
- `src/checks/CMakeLists.txt` — register the new Swift file in the checks Swift sources, following the existing `playback/*.swift` entry pattern.

### Prerequisites

- Task 27 done (no new `DecompProject` consumers).
- S5 ProjectStore actor API frozen (`open`, song open, save, bank apply/revert, lease tokens).
- plan.md Global Constraints apply.

### Interface contract

- Suite entry follows house convention: `@MainActor func runExportChecks(_ report: CheckReport, …)` with per-row `cppID: "exportcheck/MidiExportTest::<case>"` attribution preserved.
- Same 4 behaviors on the same songs: duration-calculation(render parity on `mus_route101`), valid RIFF/PCM offline export, resonance-suppression PCM delta with unchanged frame count, cancelled export removes the partial file.
- Same failure vocabulary as the C++ fixture: missing root / empty label / service denial surface as failures, never traps.

### Implementation steps

1. Port `durationCalculationMatchesRenderParity` to open `mus_route101` through the actor and compare the duration calculation against render parity.
2. Port `offlineExportProducesValidRiffPcm` to render through the actor-loaded timeline and validate RIFF header plus PCM sample content.
3. Port `resonanceSuppressionChangesPcmWithoutChangingFrames` to assert PCM bytes change while frame count is identical.
4. Port `cancelledExportRemovesPartialFile` to assert cancellation deletes the partial output.
5. Register the file in `src/checks/CMakeLists.txt`; leave `tst_midiexport.cpp/.h` and the catalog untouched.

### Acceptance predicate

- All 4 ported rows pass under the new suite entry; C++ `exportcheck` lanes still pass unmodified (coexistence).
- NAMED CHECKS:
  - `deno task verify --filter exportcheck-loop --verbose` — covers the `mus_route101` lane.
  - `deno task verify --filter exportcheck-tail --verbose` — covers the `mus_route102` lane.

### Task-specific constraints

- Filter-name preservation: `exportcheck-loop` / `exportcheck-tail` names and `--exportcheck` argv are not renamed here (re-registration is Task 32).
- No catalog edits in this task; C++ and Swift suites coexist until Task 31 deletes the C++ file.
- The port targets the actor, never `pd_service_*` directly.

## Task 29: vgbankcheck rows into bankleases suite

### Context

`src/checks/voicegroup/tst_voicegroupbank.cpp` (`VoicegroupBankTest`, 8 cases + per-case `init`) is the native bank-lease contract. Its rows move into the `bankleases` Swift suite in `src/checks/projectstore/`, driven through the S5 ProjectStore actor. The C++ file stays on disk until Task 31; the catalog still points at it until Task 32.

### Exact write set

- New `src/checks/projectstore/BankLeasesChecks.swift` — the `bankleases` suite with all ported rows.
- `src/checks/CMakeLists.txt` — register the new Swift file alongside the Task 28 entry.

### Prerequisites

- Task 28 done (projectstore suite pattern established).
- S5 actor bank semantics frozen: lease reuse across shared voicegroups, fresh lease per applied edit, superseded-lease validity, single-shot materialization tokens.
- plan.md Global Constraints apply.

### Interface contract

- Suite entry `@MainActor func runBankLeasesSuite(_ report: CheckReport, …)` with per-row `cppID: "vgbankcheck/VoicegroupBankTest::<case>"` attribution preserved.
- Fixed inputs carried over exactly: `kDirectSoundSlot = 0`, `kBlankSlot = 13`, shared song `mus_oldale`, `VOICEGROUP_SIZE` bounds, init-case song `mus_gym` per the catalog.
- Lease/token semantics preserved: shared-voicegroup songs reuse one bank token; applied edits mint a fresh token while the old lease stays valid; unknown or spent tokens throw `bankConflict` with zero mutation; preview/filesystem failure rolls the candidate back completely.

### Implementation steps

1. Port `playableSongResolvesOnlyPlayableLabels`, `bankLeaseIsReusedAcrossSharedVoicegroup`, and `appliedScalarEditReplacesBankAndPreservesOldLease` (including old-lease-stays-valid and undo/redo view restoration).
2. Port `staleBlankAndOutOfRangeEditsConflictWithoutMutation` as a loop over the three conflict rows (stale lease, blank-expected, out-of-range slot), each asserting conflict without mutation.
3. Port `unknownIdentityIsHardError`, `previewFailureRollsBackCandidate` (slots, dirty flag, and source bytes all preserved), and `blankMaterializationRevertAndSpentToken` (single-shot token: second use conflicts).
4. Port `saveRefreshesBankAndFailedSynthSaveLeavesRecordDirty` (successful save publishes a refreshed clean bank; failed synth save leaves the record dirty).
5. Register the file in `src/checks/CMakeLists.txt`; leave `tst_voicegroupbank.cpp` and the catalog untouched.

### Acceptance predicate

- Every ported row passes; the C++ `vgbankcheck` lane still passes unmodified (coexistence).
- NAMED CHECKS:
  - `deno task verify --filter vgbankcheck --verbose` — covers all ported bank-lease rows on `mus_gym`.

### Task-specific constraints

- Filter-name preservation: the `vgbankcheck` name and `--vgbankcheck` argv are untouched here (re-registration is Task 32).
- Slot constants, shared-song labels, and the conflict-row triple are fixed inputs; do not generalize or parameterize them.
- No-partial-revert rule (from the risk register): any failed or conflicting edit leaves the visible bank, dirty flag, and source bytes exactly as before; reverts are all-or-nothing.

## Task 30: Flip ProjectService internals onto the ProjectStore actor

### Context

`src/swift/app/ProjectService.swift` (`ProjectService` actor, `NativeBankLease`, `LoadedSong`, `AppliedBankEdit`, `SaveReceipt`, `ProjectServiceError`) currently fronts the native worker via `pd_service_*`. This task flips its internals to delegate to the S5 ProjectStore actor. The public Swift API does not change; all existing Swift callers (`ApplicationSession`, checks) recompile untouched.

### Exact write set

- `src/swift/app/ProjectService.swift` — reimplement every operation as delegation to the S5 ProjectStore actor.
- Nothing else. `src/swift/project/` (S5-owned) is read-only in this task.

### Prerequisites

- Tasks 27–29 done (all native-bank consumers run through Swift suites).
- S5 ProjectStore actor owns project state, materialization tokens, and bank records.
- plan.md Global Constraints apply.

### Interface contract

- CORRECTED topology: `ProjectService` delegates to the S5 ProjectStore actor; it does NOT call `ProjectFileStore` (or any file store) directly. The actor is the sole owner of project state, tokens, and bank records; `ProjectService` is a thin async front.
- Public API frozen: `open(root:)`, `openSong(label:)`, `save(_:bank:)`, `bankApply(lease:slot:value:expected:)`, `bankRevert(lease:token:)`, `NativeBankLease` (handle, `sourcePath`/`sectionLabel`, `bankToken`), `LoadedSong`, `AppliedBankEdit` (with single-shot `materializationToken`), `SaveReceipt`, and all `ProjectServiceError` cases with identical equatability.
- Ordered save preserved exactly: optional bank save, then MIDI bytes, then flags (`PdSaveRequest` field order is the spec).
- Explicitly NOT ported (dead across the seam): `writeSynthDefinitions`, `ensureSynthDataIncluded`, `reopenedVoicegroupContext`, `pruneStaleBanks`, the `saveVoicegroup` mapsChanged path (`swift_project_service.cpp:425` always passes `{}`, so synthDefinitions never cross the seam), and `checkRegistrations` / `applyRegistrationGaps` (`PdSongMeta` carries no gaps field).
- Song file basenames use `completeBaseName` = LAST-suffix strip (`deletingPathExtension().lastPathComponent`).
- Error mapping: stale expected value, occupied blank slot, out-of-range slot, and spent/unknown materialization token all throw `bankConflict`; hard native failures throw `operationFailed`; use-after-close throws `serviceClosed`.

### Implementation steps

1. Replace the `pd_service_*` worker plumbing in `open`, `openSong`, `save`, `bankApply`, and `bankRevert` with calls into the S5 ProjectStore actor, keeping every public signature and every continuation/error-translation site.
2. Reimplement `NativeBankLease` ownership over the actor's lease handle with the same deinit-release and `bankToken` semantics.
3. Preserve the ordered save (bank, MIDI bytes, flags) statement-for-statement; carry `sourcePath`/`sectionLabel` from the lease into save requests.
4. Delete the `pd_service_*`/`PdBankLease` C bridging from this file only; leave the C header itself for Task 31.

### Acceptance predicate

- `save` line-diff: the new save path diffed against the old ordered save shows identical stage order (bank → MIDI → flags) with only the transport (actor vs C worker) changed.
- NAMED CHECKS (all three drive the flipped front end-to-end):
  - `deno task verify --filter vgbankcheck --verbose` — covers lease reuse, edit minting, conflicts, reverts, save refresh.
  - `deno task verify --filter exportcheck-loop --verbose` — covers open-song + render through the flipped service.
  - `deno task verify --filter exportcheck-tail --verbose` — covers the second export lane through the flipped service.

### Task-specific constraints

- Save-ordering line-diff (from the risk register): the diff is produced and inspected in this task; any reordering is a defect, not a refactor.
- No-partial-revert rule: `bankRevert` with a spent or unknown token throws `bankConflict` and mutates nothing; never a partial rollback.
- No new public API, no overloads, no deprecation shims; callers recompile untouched.

## Task 31: Build-graph surgery + corpse deletion

### Context

With Tasks 27–30 done, the native project implementation and its C++ check corpses are unreachable. This task deletes them, renames the Swift module to its final bank-lease-only shape, and repoints the build. `banklease.{h,cpp}` already exists from Task 1 and is NOT touched by the deletion.

### Exact write set

- Delete every other file under `src/project/`: `decompproject.{h,cpp}`, `projectidentity.{h,cpp}`, `projectio.{h,cpp}`, `projectworkspace.{h,cpp}`, `songregistry.{h,cpp}`, `songsmk.{h,cpp}`, `samplereg.{h,cpp}`, `sidecar.{h,cpp}`, `voicegroupprojectcontext.{h,cpp}`, `voicegroupsource.{h,cpp}`, `swift_project_service.{h,cpp}`. Keep `banklease.{h,cpp}` and `src/swift/project/` (repoint nothing at them; they are already wired).
- Delete the ported C++ check corpses: `src/checks/midi/tst_midiexport.{cpp,h}`, `src/checks/voicegroup/tst_voicegroupbank.cpp`, and the whole `src/checks/project/` directory (its successors live in `src/checks/projectstore/`).
- `src/swift/app/module.modulemap.in` — rename the module `PorydawProjectService` → `PorydawBankLease`, keeping the `native_host.h` header line for `pd_clipboard_*`.
- Rename `import PorydawProjectService` → `import PorydawBankLease` in exactly the Swift files that still reference module symbols (`PdBankLease`/`pd_bank_*`/`pd_clipboard_*`, found by grep — expected 4); delete the import line everywhere else it became unused.
- `CMakeLists.txt` files (root, `src/project` if any remains, `src/checks/CMakeLists.txt`, `src/swift/app/CMakeLists.txt`) — drop deleted sources, point at `banklease.{h,cpp}` where the old service sources were listed.
- `src/ui/newsongwizard.{h,cpp}` — delete the `DecompProject*` constructor overloads; the `ProjectData` path is the only construction route.

### Prerequisites

- Tasks 27–30 done and green; S1–S5 successors for `src/checks/project/` content landed.
- plan.md Global Constraints apply (Windows first-party toolchain rules govern the CMake/modulemap edits: MSVC-clean C++, no Apple-only constructs).

### Interface contract

- After this task, `grep -r DecompProject src/ CMakeLists.txt` and `grep -r PorydawProjectService src/ CMakeLists.txt` both return zero hits.
- Module `PorydawBankLease` exports exactly the bank-lease C boundary plus `native_host.h` (`pd_clipboard_*`); every Swift file that compiled against the old module name compiles against the new one with no other change.
- `NewSongWizard` constructs from `ProjectData` only; no caller passes a project object.

### Implementation steps

1. Delete the `src/project/` files listed above (keep `banklease.{h,cpp}`); update the build lists so nothing references the deleted paths.
2. Delete the C++ check corpses and `src/checks/project/`; drop them from `src/checks/CMakeLists.txt`, keeping the `projectstore/` Swift registrations from Tasks 28–29.
3. Apply the modulemap rename, preserving the `native_host.h` line; grep for module-symbol users, rename the imports in exactly those files (expected 4), and remove the now-unused import elsewhere.
4. Delete the `DecompProject*` constructors in `newsongwizard.{h,cpp}`; verify zero callers via references check before removing each overload.
5. Delete any other widget whose only caller was the deleted native service (zero callers per references check required before each deletion); rewire nothing.

### Acceptance predicate

- Both zero-hit greps above hold; no dangling `#include` of a deleted header remains.
- NAMED CHECKS (prove the surgery changed no behavior):
  - `deno task verify --filter vgbankcheck --verbose` — covers the bank-lease boundary post-rename.
  - `deno task verify --filter exportcheck-loop --verbose` — covers service + build wiring on `mus_route101`.
  - `deno task verify --filter exportcheck-tail --verbose` — covers service + build wiring on `mus_route102`.

### Task-specific constraints

- Filter-name preservation: this task renames modules and files but no check filter names; catalog entries are byte-identical until Task 32.
- Repoint nothing: `banklease.{h,cpp}` and `src/swift/project/` keep their existing build wiring; the task only deletes and renames around them.
- Deletion gate: a file or overload is deleted only with zero remaining callers verified by references check; anything still referenced is a task blocker, not a silent keep.

## Task 32: Catalog re-registration + full gate

### Context

The catalog (`src/checks/checkcatalog.cpp`) still describes the old native lanes. This task re-registers the three flipped lanes onto their Swift suites and runs the full gate. It is the only task that edits the catalog.

### Exact write set

- `src/checks/checkcatalog.cpp` — re-register `vgbankcheck`, `exportcheck-loop`, and `exportcheck-tail` onto the `projectstore/` Swift suites.

### Prerequisites

- Task 31 done: corpses deleted, module renamed, three named lanes green.
- plan.md Global Constraints apply.

### Interface contract

- Filter names and argv commands are byte-identical: `vgbankcheck` / `--vgbankcheck` on `mus_gym`; `exportcheck-loop` / `exportcheck-tail` / `--exportcheck` on `mus_route101` / `mus_route102`. Existing `deno task verify --filter …` invocations and proof logs keep working (filter-name preservation).
- Fixture roots, staged file sets (`bank`, `route101`, `route102` lists), scratch kinds, and the `PORYDAW_AUDIO_BACKEND=null` environment are unchanged; only the handler (Swift suite) and any suite-owned fixture plumbing change.
- The Apple-gate caveat is documented at the re-registered entries in a code comment: `swiftcore`, `swiftrollgated`, `swiftbandkeys`, `swiftqtml`, and `selectionkey` live inside `#ifdef __APPLE__` (with `Windowing::WindowSystem` for the grid lanes), so a non-Apple full gate legitimately skips them — absence there is not a regression.

### Implementation steps

1. Re-register `vgbankcheck` onto the Task 29 `bankleases` suite with the unchanged `bank` file set, `mus_gym` song, and `voicegroupBank` handler lineage.
2. Re-register `exportcheck-loop` and `exportcheck-tail` onto the Task 28 export suite with the unchanged `route101`/`route102` file sets and songs.
3. Add the Apple-gate caveat comment at the re-registered entries (and only there): which lanes are Apple-gated and why their absence off-Apple is expected.
4. Run the full gate with no filter.

### Acceptance predicate

- `git diff` on the catalog shows handler/fixture-plumbing changes only; every check name, `--command`, song label, and file set is untouched.
- NAMED CHECKS:
  - `deno task verify --filter vgbankcheck --verbose` — covers the re-registered bank lane.
  - `deno task verify --filter exportcheck-loop --verbose` — covers the re-registered loop lane.
  - `deno task verify --filter exportcheck-tail --verbose` — covers the re-registered tail lane.
  - `deno task verify --verbose` — the full gate with no filter; every registered lane passes (Apple-gated lanes pass on Apple; their documented absence off-Apple is not a failure).
