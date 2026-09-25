# Context

R07 and the existing, non-autosaving portion of R08: two live documents using the same canonical bank must observe one current bank view, not independent stale copies. Base: `fea4034d`. Read [plan.md](plan.md) Global constraints and its linked spec. The subsequent BANK-CLOSE task consumes the project-scoped bank-view lifetime; this task does not implement close prompts or change what ordinary Save writes.

Original contract: `voicegroupsave/switching.cpp` at `a7fcaa3e9ea51a057c85bc1959e541c69fe4a3ea`, `voicegroupsave/savecore.cpp` at `c1f165eb1aa49af49c72a3e4f15cf6d9f23b6735`, and `voicegroup/tst_voicegroupviewcache.cpp`. C++ `WorkspaceUi::applyBankView` updated every matching tab, while `VoicegroupViewCache` held the shared dirty/slot publication. Current `bank_sharing.swift` opens its second song only after editing; that is not a two-live-session regression. `bank_switching.swift` already covers returning to dirty A before saving, not saving B and closing the project.

# Exact write set

- `src/swift/project/ProjectStore.swift`
- `src/swift/project/ProjectStore+Bank.swift`
- `src/swift/app/ProjectService.swift`
- `src/swift/app/SharedBankState.swift` (new)
- `src/swift/app/DocumentSession.swift`
- `src/swift/app/ServiceBankHistory.swift`
- `src/swift/app/CMakeLists.txt` (register the new Swift source only)
- `src/checks/workspace/bank_sharing.swift`
- `src/checks/workspace/bank_switching.swift`
- `src/checks/workspace/SessionChecks.swift` (register the new shared-bank scenarios only)
- `src/checks/editorqml/tst_ShellVoicegroup.qml`
- `src/checks/editorqml/ShellQmlTests.swift` (only add `mus_route102` to the `shell-voicegroup` fixture declaration)
- `src/checks/projectstore/BankLeasesChecks.swift` (qualify the suite/service cases for MainActor and use the existing run-loop-aware helper for `ProjectService` operations; retain actor-only store checks)
- `src/checks/drawerpresentation/velocity.swift` (only replace the two noncanonical session fixtures in `drawerVelocityKeysplitPerNoteMapping` with actual loaded banks while retaining its behavioral assertions)
- `src/checks/voicelist/voicelist_session.swift` (only the queued-origin case: assert discarded work leaves the original document history unchanged while the valid peer edit publishes to both views of the shared bank)
- `src/checks/projectstore/ExportChecks.swift` (controller-owned follow-through: replace its main-thread-blocking ProjectService fixture waits with the existing `runBlocking`, preserve rendering/assertions and report close failures)
- `src/checks/workspace/bank_saves.swift` (controller-owned removal of the obsolete diagnostic-substring check; `bankBindingIdentityIsolation` already proves typed old-store refusal and unchanged replacement view/native source)

Proof-only reconciliation is separately owned after check sources freeze. Candidate surface ledgers are `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt`, `src/checks/voicegroup/proof.tst_voicegroupbank.txt`, `src/checks/voicegroupsave/proof.switching.txt`, `src/checks/voicegroupsave/proof.savecore.txt`, `src/checks/drawerpresentation/proof.velocity.txt`, and `src/checks/midi/proof.tst_midiexport.txt`; report exact affected original sites and executing predicates, do not edit proofs. The export ledger is limited to the changed fixture helper description; no export parity promotion. Unrelated mappings and unresolved clauses remain untouched.

The same cutover removes the copied obsolete S175 entry from these eight workspace ledgers only: `proof.selftest_timeline.txt`, `proof.selftest_transport.txt`, `proof.selftest_workspace.txt`, `proof.session.txt`, `proof.tabs_lifecycle.txt`, `proof.tabs_persistence.txt`, `proof.tabs_scale.txt`, and `proof.tabs_transport.txt`. Check direct citations before removal; if any exist, map only that affected clause to its exact executing replacement or preserve it unresolved. No other workspace rows are authorized.

Four mainwindowrouting ledgers also copy that same S175 entry: `src/checks/mainwindowrouting/proof.tst_mainwindowrouting_input.txt`, `proof.tst_mainwindowrouting_lifecycle.txt`, `proof.tst_mainwindowrouting_native.txt`, and `proof.tst_mainwindowrouting_state.txt`. The identical S175-only removal/reference rule applies; no routing behavior or other rows change.

# Prerequisites

Tasks 4, 5 and 7 provide concrete project-store actor operations, origin-scoped workspace/audio publication, and request-time voice-edit identity. Task 11 preserves Qt-main execution with finite, reentrancy-safe drains. Their interfaces remain intact. The integration checkpoint is pushed.

The mounted peer scenario uses `mus_route101` and `mus_route102`; the checked-in `sound/songs/midi/midi.cfg` maps both to `_fixture_rich`. Add the second MIDI through the existing manifest `songs` helper, not runtime fixture copying or a new bootstrap hook.

Task 13 remains the sole writer of `CoreCheckSupport.swift` and qualifies its suite-31 dispatch for the MainActor-owned `runBankLeasesSuite`. The existing bank-lease service cases must no longer block the Qt main thread through `awaitValue` while `ProjectService` awaits UI publication. Use `runBlocking` for those service calls and typed error handling; pure `ProjectStore` cases keep their existing worker wait. No timeout increase, new wait helper or production scheduling bypass.

`drawerVelocityKeysplitPerNoteMapping` currently injects different slot arrays under the same already-published lease identity. That contradicts the new canonical binding and caused six observed CORE failures. Keep its pure `VelocityContextPolicy` value checks, but load real bank/subgroup fixture data for the session/page journey: keys 60/72 resolve Square 1, key 67 resolves Wave, and the unsupported scene uses genuinely undefined program slots. Do not bypass the cache with invented owners, revisions, closed services or a test-only constructor. Own fixture additions must be isolated and cleaned up; retain the original detent, mixed-axis, handle, hover, prompt, undo and unsupported-input predicates.

The queued-origin case also assumed peer bank edits remain invisible to the first tab. Retain its same-bank/two-document setup to exercise document-origin rejection, but replace that obsolete visibility assertion with unchanged original document history and the valid peer voice appearing in both bank views. Keep stale type rejection, valid edit completion and undo. A distinct-bank fixture alone would weaken coverage of the document-origin guard.

# Interface contract

- `ProjectStore.adoptBankLease(view:)` stamps immutable publications in its actor-isolated ordering. Add `publicationOwner: UUID` and `publicationRevision: UInt64` to `ProjectBankLease`; the owner is unique to the store instance, and revisions advance monotonically for adopted snapshots. No actor closure trampoline, native ABI change, loader-thread change or mutable lease.
- `NativeBankLease` exposes those stamps internally to PorydawApp. Bank binding identity includes store owner, relative source path and section label; neither native pointer equality nor source path alone is bank identity.
- Add the MainActor-owned `ProjectBankViews` and `SharedBankState` in `SharedBankState.swift`. `ProjectService` owns one `nonisolated let bankViews: ProjectBankViews`; the view owner has a nonisolated initializer that performs no actor work. `ProjectBankViews.state(for: AppliedBankEdit) -> SharedBankState` and `publish(_ value: AppliedBankEdit)` maintain the newest immutable view per binding identity. Its `reset()` clears the project projection on service replacement/close. This is a publication cache, not another editable bank/source/history store.
- `SharedBankState.value` is read-only outside its owner. Its `attach(_ session: DocumentSession)` / `detach(_ session: DocumentSession)` subscription is weak. Accept only newer revisions of the same identity, and do not notify consumers for an unchanged bank/slots/dirty/load-name publication. Snapshot iteration must tolerate callbacks that detach or rebind; no strong session cycle or process-global registry.
- `DocumentSession` retains one private shared binding. Preserve public getter types/names `bankLease`, `bankSlots`, `bankDirty`, `bankLoadName`, its initializer and all editing/save/history signatures; replace their independent stored snapshots with getters through that binding. Add internal `sharedBankDidChange(_ state: SharedBankState)` for the existing `SessionChange` publication path. Closed or rebound sessions ignore old-binding callbacks.
- Successful load/open, edit, history replay and bank-save stages publish through the same project view owner. A completed bank-save stage must reach peers even if the later MIDI/flags stage fails. Old receipts cannot overwrite newer edits. Preview-only leases do not become canonical publications. Receipts from a replaced/closed store must not publish into the current project's bindings. An old store's lease must also be rejected before mutating a replacement store on the same `ProjectService`; matching relative paths/sections are insufficient.
- Preserve one history per document. Cross-tab disjoint-slot undo keeps the other edit; stale same-slot replay prunes only the stale command. `ServiceBankAction.merged(with:)` and `rebaseCurrent(with:)` require complete binding identity as well as their existing service/slot/value constraints.

# Implementation steps

1. First add an isolated two-already-open-session regression to `bank_sharing.swift` and its registration. Edit A and assert B's actual voice value and dirty state update without reopening/rebinding. Stop after this test-only phase so the before-state failure can be observed; production changes start only after that observation.
2. Implement the versioned shared-view boundary above, including catch-up when a session attaches after a newer publication. Remove `previousBankVoices` and the stale-expected-value-as-busy special case: actual in-flight transitions retain their existing gate; an idle stale expected value goes through the canonical expected-value conflict path. Replace the sleep-dependent coordinator test with `Task.immediate` admission ordering, without a production timing workaround.
3. Route all session bank binding and replay paths through the shared state. Preserve immediate ordinary document edits during an async save. Coalesce only bank notifications during an owned bank transition and flush the latest state on success or failure; do not defer unrelated document notifications across an await or send duplicate bank refreshes for one completed operation. Keep the existing `onChange` subscriber, workspace active guards, native audio update path, blank-materialization tokens and save snapshot identity rules.
4. Complete native regressions: two live sessions share edits/undo/save/dirty values; document dirtiness remains independent; disjoint and conflicting histories behave as above; closing/rebinding one subscriber does not retarget it; unrelated bank/section/project identities remain isolated; a newer peer edit is not cleaned by an older save completion. Preserve dirty A across switch-to-B and undo without writing A's source. Exercise the existing real `ApplicationSession`/`DocumentWorkspace` plus `NativeAudio` telemetry so a background-bank edit reaches the selected workspace's sounding voice, not only its model. Reuse the fixture and bounded-run-loop conventions in `transport_checks.swift`; no new production test getter.
5. Add a mounted VoicegroupPanel regression using the existing numeric editor and Save control with two live app documents sharing a bank. Observe the peer's editor/dirty state after selection, and clean publication after Save. Tab creation/selection may be setup through existing app APIs; do not claim physical tab-click coverage. Keep existing tests isolated from the scenario's edits and preserve request-time edit-origin behavior.

# Acceptance predicate

The new two-live-session check fails on the unchanged production implementation with stale peer value/dirty state, then passes after the repair. Actual native audio and mounted editor/save observations must pass along with history, identity, save-failure and switch byte-conservation cases; a pointer/count-only assertion is not a substitute.

Named checks, controller-run after writers settle:
- `deno task verify --filter swiftcore --verbose` — before regression observation, then final domain/session/audio/history checks.
- `deno task verify --filter projectstore --verbose` — adopted leases and project actor operations.
- `deno task verify:shell --filter shell-voicegroup --verbose` — mounted editor and Save interaction.
- `deno task verify:shell --filter shell-tabs --verbose` and `deno task verify:shell --filter shell-transport --verbose` — subscriber lifecycle and previously repaired selected-workspace behavior.
- `deno task proof check --executed` — after the frozen-source proof handoff; inspect classifications, not just exit status.
- `deno task verify:bridge` — the new ordinary Swift owner must not introduce accidental Qt declarations.

# Task-specific constraints

Ordinary Save still writes only its current song and dirty bound bank. No autosave on `-G` change, new dialog, all-bank save, source-file merge algorithm or orphan-bank close policy in this task. Multi-section dirty-source preservation when another section saves the same file remains a separately tracked R08 risk; do not hide it with timestamp guards or silently claim it fixed. No changes to `VoicegroupStore` editing algorithms, C++ sources, `NativeAudio`, global executor or `ProjectContext.ContextWorker`. The controller owns shared build/test/lint/format commands and proof files; local structural inspection remains required.
