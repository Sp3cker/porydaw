# Swift parity handoff — shared banks and audio lifetime

## Stop boundary and authority

The user requested a stopping point, a committed handoff, and a push. This wave stopped after stabilizing and accepting **task 12 / R07** and **task 13 / R24**. No next feature was started. The overall Swift parity objective is **not complete**.

[plan.md](plan.md) is the authoritative inventory/status document. Read its Global constraints, then [verification.md](verification.md). The older QtBridge cleanup plan and `current-surfaces.md` are historical evidence, not competing execution plans.

- Worktree: `/Users/spencer/dev/cProjects/porydaw/.worktrees/swift-qml-grid`.
- Branch / remote: `feature/swift-qml-grid` / `origin/feature/swift-qml-grid`.
- Baseline for tasks 12/13: `fea4034d` (already pushed integration checkpoint).
- Earlier accepted repair checkpoint: `e171f3ef`.
- Whole-branch review base: `fceecd888e29c0a39c3a98d17e47d3d734b1de06`.
- Assessment base: `86c88903661ee6d44a77da505bf4b9fef777f6e0`.

## Bounded repair wave

### Task 12: canonical shared-bank publication

[task-12-brief.md](task-12-brief.md) owns the exact contract and write set.

- `ProjectStore` stamps bank publications with a store owner UUID and monotonic revision.
- `ProjectService` owns the MainActor `ProjectBankViews` publication cache. Binding identity includes owner, relative path and section. This is not another editable source/history store.
- `DocumentSession` reads its bank through `SharedBankState`; weak subscriptions publish to already-open peers, including dirty state, history replay and completed bank-save stages.
- Stale receipts and old-store leases cannot overwrite or mutate a replacement store. History remains document-local; disjoint bank edits survive peer undo and stale same-slot replay is pruned.
- Existing `-G` switches remain non-autosaving. Dirty bank A survives switching to B and undo, without writing A's source.
- Coverage includes a real selected-workspace audio change from Square 1 channel 0 to Noise channel 3, plus the mounted VoicegroupPanel numeric editor and Save control. Tab creation/selection in that QML scenario is setup through app APIs, not proof of physical tab clicks.

The cutover exposed old check assumptions. `BankLeasesChecks` must use the run-loop-aware `runBlocking` for MainActor-publishing ProjectService calls, not block the Qt thread through `awaitValue`. Velocity page integration fixtures must load real banks rather than inject conflicting slot arrays under an existing canonical lease. The queued-origin check must distinguish document-history ownership from shared bank visibility.

### Task 13: NativeAudio lifetime

[task-13-brief.md](task-13-brief.md) owns the exact contract and write set.

- `NativeAudio.device` no longer escapes isolation with `nonisolated(unsafe)`; teardown uses `isolated deinit`.
- Preserve `withExtendedLifetime(bankLease) { device.shutdown() }`: callbacks join and engines are destroyed before the borrowed bank is released.
- Real forced-null audio checks exercise sounding callbacks, service-close bank pinning, MainActor final release and deterministic detached-task final ownership.
- Task 13 is the sole writer of the MainActor envelopes in `CoreCheckSupport.swift`, suites 3 and 31; task 12 owns the bank-lease suite itself.
- **Keep the native C++ backend lane.** The Swift suite remains Apple-gated; its success does not qualify Linux/Windows or authorize removing their retained backend coverage.

## Observed verification for this source snapshot

All commands ran from this worktree through `deno task`, after source writers froze.

| Command | Observed result |
| --- | --- |
| `deno task verify --filter swiftcore --verbose` | PASS, 21.46s; 1 selected harness, 30 filtered out |
| `deno task verify --filter projectstore --verbose` | PASS, all 23 selected entries, 0.90s |
| `deno task verify --filter audiocheck-backend --verbose` | PASS, 0.09s; retained native backend lane |
| `deno task verify:shell --filter shell-voicegroup --verbose` | PASS, 2.29s; includes mounted two-live-tab numeric edit and Save |
| `deno task verify:shell --filter shell-tabs --verbose` | PASS, 10.13s |
| `deno task verify:shell --filter shell-transport --verbose` | PASS, 5.03s |
| `deno task verify:shell --filter shell-polyphony --verbose` | PASS, 3.74s |
| `deno task build:app` | PASS, 62.44s |
| `deno task verify:bridge` | PASS, zero findings |
| `deno task lsp:swift` | Exited zero, but indexed **0/0**; not semantic qualification |

Earlier red runs were resolved rather than hidden: service fixture waits blocked Qt-main publication; velocity fixtures contradicted canonical bank identity; queued-origin visibility assumed independent bank snapshots; an obsolete diagnostic-substring check expected the old native error. That wording check was deleted, not re-pinned. `bankBindingIdentityIsolation` instead verifies typed `.serviceClosed` refusal and unchanged replacement view, native bank and dirty state. Export fixture waits were repaired without changing rendering or claiming production WAV export.

The final commands above are bounded repair-wave coverage, not a fresh full-roadmap ALL/SHELL/DRAWER/ROLL qualification. The earlier full integration gates belong to `fea4034d`; retain that distinction.

Native macOS smoke also passed: launched `build/porydaw.app/Contents/MacOS/porydaw --project src/checks/fixtures/decompproject --song mus_route101` with private `HOME=/tmp/porydaw-handoff-native-home`, `PORYDAW_AUDIO_BACKEND=null` and `QSG_INFO=1`. Metal used Apple M4 Pro; the song, primary/ghost notes and drawer rendered. Actual Space advanced the clock from `0:00.0` to `0:05.4` and moved/followed the playhead. Normal Cmd-Q exited **0**. This proves application/null-backend lifetime, not audible hardware output. Captures: `/tmp/porydaw-handoff-native.png` and `/tmp/porydaw-handoff-playing.png`. Two zero-pixel-font warnings remain under R27.

Final proof structure/execution classification passed after the proof-only handoff: 188 files, 13,789 original sites, 9,496 resolved anchors (28 historical), 8,868 executed, **13 not executed** and **615 unverifiable**. The 13 unchanged non-executed entries are automation voice S029/S030/S046/S194/S195/S270; drawer voice S027/S028/S044/S187/S188/S263; roll identity S005. These are remaining evidence obligations, not a full-parity pass. `deno task format --check` passed for 22 Deno and 118 C/C++ files; it does not qualify Swift formatting or SourceKit semantics.

Proof adjudication was deliberately conservative: view-cache A023 remains PARTIAL (observed non-clobber, not the original returned-result/record-existence clauses); A024/A025 and save-core A052 remain GAP. Adjacent passing state checks do not prove history counts, redo availability or successful MIDI byte writes. The obsolete diagnostic anchor S175 was unreferenced and removed from its twelve copied indexes, without renumbering or promoting unrelated rows.

Both task-scoped reviews approved **spec compliance and code quality**, with no Critical or Important findings. Runtime qualifications were resolved by the observed gates; preview remains a store-only returned lease, outside the app publication cache. The controller independently checked that each of the twelve deleted S175 records had no direct original-site citation.

Review rulings and one deferred minor:

- Retain case-level audio `cppID`s with unique message anchors, the existing convention. Cost: manual tracing needs the message as well as the case id, not the id alone.
- Defer the harmless duplicate map probe in `DocumentSession.adoptBank` to the next change in that owner (R25). Cost: one redundant lookup/revision no-op per adoption; no observed behavior failure.
- `ProjectBankViews.reset(owner:)` is necessary internal epoch initialization, not public API drift.
- Retain `try runBlocking { await service.close() }`: `runBlocking` itself throws on its 25-second deadline even though `close()` is nonthrowing. Removing `try` would be incorrect. The audio checks' inner waits are five seconds.

## Next implementation: task 14, not yet started

[task-14-brief.md](task-14-brief.md) is written but **has not been dispatched or implemented**. Capture its base from the accepted tasks 12/13 checkpoint before starting.

R08 is the remaining same-physical-file bank safety problem: saving section B must preserve unsaved section A, and later saving A must retain B's bytes. The chosen repair belongs in the existing `VoicegroupSource` / `VoicegroupStore` owners, not a timestamp bypass or second source store. The brief specifies a real failing-before regression, narrow source rebasing, byte conservation, blank-materialization undo after sibling line shifts, and missing/malformed/overlap conflicts. Task 12 does not claim this is fixed.

Task 14 reuses `proof.savecore.txt`, so checkpoint the accepted task 12 surface before assigning that ledger again. Freeze check sources, run the named gates, then delegate only the explicitly affected proofs to `ledger-agent`. Preserve unproved GAP/PARTIAL clauses.

## Authorized subsequent bank-close policy

The user selected this policy explicitly:

- Ordinary Save remains current-song/current-bound-bank only.
- Switching `-G` neither autosaves nor prompts.
- Existing project/window Save–Discard–Cancel handling must account for **every dirty bank**, including banks no longer bound to any open song.

`BANK-CLOSE` is pending; no implementation brief or code for it was started. It consumes the task 12 shared-bank lifetime and task 14 safe same-file saves. Freeze a bounded brief before implementation; no new unrelated UI is authorized.

Read-only continuation leads, **not runtime-confirmed defects**:

- `ApplicationSession.startProjectSwitch` has a `tabCount == 0` bypass that must not bypass dirty orphan banks.
- `SongTabsController` uses a tab-oriented close walk; window cancellation can follow earlier tab removals. Inspect transactional expectations before changing it.
- `SongTabs.qml` projects its dialog from a nonnegative `pendingCloseId` and a real tab. A bank-only close target needs an explicit model, not a magic tab id.
- Check discard-during-save and stale save completion against current dirty/revision identity; an old successful save must not authorize losing a newer edit.
- `SongDocument.captureSave` / `didSave` already carry and validate revision/history identity. Reuse that authority.

## Protected unrelated user work

Do not stage, revert, or absorb these into the repair/handoff checkpoint:

- Staged deletion of `.lsp.json`.
- `.omp/agents/sdd-implementer.md`.
- `.omp/rules/sdd-execution-loop.md`.
- Untracked `.omp/rules/ledger-delegation.md`.
- The pre-existing tooltip removal in `src/ui/songview/quick/swiftroll/SongTabs.qml`.
- The pre-existing diagnostic Text removal in `src/ui/songview/quick/drawer/VelocityPage.qml`.

The protected tracked diff snapshot before this repair wave had SHA-256 `e33966cec471d795758b0d1612d9e3db8cefbdf9d7f091fd199561c22d0dcbc8` (`git diff HEAD --` the five tracked paths above, excluding the untracked ledger rule). Commit an explicit owned path set; a bare commit would include the user's staged deletion.

## Remaining obligations and limits

- Do not infer product parity from successful aggregate checks or proof counts. Remaining R/P/J rows stay in `plan.md`.
- R15–R18 still contain concrete UI/proof obligations; R20/R21 concern validator/platform truthfulness; R22–R27 remain bounded existing-surface work.
- R27's zero-font source candidate is the add-track snapshot's two zero-sized fonts rendered by hidden `TrackHeaderBand.qml` Text items. Isolate the actual warning path before changing it. Missing fonts, QTP0004 and usable QML lint imports are also unresolved.
- Preserve Linux Qt-main integration `c47b55f4` and `ProjectContext.ContextWorker`. Linux and Windows runtime qualification require their hosts; macOS checks do not provide it.
- SourceKit has reported indexing `0/0`. Treat that as an indexing limitation, not a semantic-reference pass. Refresh with `deno task lsp:swift` after Swift/CMake changes; empty references with working hover are not reliable evidence of no callers.
- The integrated cleanup removed only the unused native context-property setter. `QmlEngineAccess.swift`, `qml_engine_host.h/.cpp` and their live source registration remain necessary.
- Sample Studio, WAV export, onboarding and other absent surfaces remain inventoried but deferred pending scope authorization. Do not add placeholder controls or silently mark them delivered.
