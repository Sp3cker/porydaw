# Context

Before retiring `src/checks/voicegroup/tst_voicegroupviewcache.cpp`, give its frozen `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt` inventory runnable Swift counterparts. Its 70 original sites belong to `VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions` (A001–A032), `mergeRules` (A033–A039), and `coordinatorRoutesTransitionsAndGates` (A040–A070). Existing `historyTransitionRegressions`, `bankMergeSealing`, and `bankCoordinatorGate` already report some matching `cppID`s, but prove only fragments of those scripts. Task 16 consumes the **executed assertions** from this task for per-site correspondence, not those IDs alone. See `plan.md` Global constraints and `spec.md` §§4.2, 5.2, 6–7.

There is a real merge-boundary difference to fix, not explain away: native `SongHistory::markDocumentSaved` changes saved identity without sealing a bank command; `WorkspaceUi::submitPickerEdit` explicitly seals the top bank command before a new edit when the bank view is clean. Swift `SongHistory.markSaved(_:)` currently seals both document and bank entries, and `DocumentSession.applyBankEdit` has no clean-bank seal. Preserve the native distinction and the existing Swift document-save boundary.

# Exact write set

- `src/swift/core/SongHistory.swift` — separate document-save sealing from explicit top-bank merge sealing.
- `src/swift/app/DocumentSession.swift` — seal an existing bank merge before submitting an initial edit against a clean bank.
- `src/checks/workspace/bank_history_probes.swift` — history lifecycle and stale/failure predicates.
- `src/checks/workspace/bank_edits.swift` — four independent merge histories and post-save service behavior.
- `src/checks/workspace/bank_sharing.swift` — coordinator, identity, and mutation-gate predicates.
- `src/checks/workspace/SessionChecks.swift` — dispatch the three new predicates in the existing SwiftCore bank-history suite, retaining every existing call.

Read-only oracles: the C++ check and its frozen proof inventory, the existing bank/session check fixtures, `src/core/songhistory.cpp`, and `src/ui/workspaceui_voicegroup.cpp`. Do not edit any C++ source, QML, fixture, proof inventory, or registration/build file.

# Prerequisites

Task 12 and its settled SwiftCore/service check boundary. Task 16 may start only after this task's runtime assertions pass; Task 17 source retirement waits Task 16 as well as Tasks 13 and 14.

# Interface contract

- `SongHistory.markSaved(_ identity: DocumentIdentity)` retains its saved-identity/document-merge semantics: it seals an adjacent **document** history entry, but must not implicitly seal a top **bank** entry. Add `public func sealBankMerge()` that seals only the top bank entry, with no effect on a document entry or empty history. Keep transition ownership and dirty/identity semantics intact. In `DocumentSession.applyBankEdit(slot:value:expected:)`, call this explicit seal when `bankDirty == false`, after all existing open/persistence/stale-expected admission guards and immediately before `beginBankTransition()`; do not seal on every edit. Subsequent bank edits made while dirty may merge normally. In particular a failed application never records an edit.
- Register exactly three new runnable SwiftCore check functions: `viewcacheHistoryLifecycleParity(report:fixtureRoot:)` in `bank_history_probes.swift`, `viewcacheMergeRulesParity(report:fixtureRoot:)` in `bank_edits.swift`, and `viewcacheCoordinatorRoutesParity(report:fixtureRoot:)` in `bank_sharing.swift`; each receives `CheckReport` and the staged-fixture root as existing helpers do. Their assertions use, respectively, the exact source identities `voicegroupviewcachecheck/VoicegroupViewCacheTest::historyLifecycleAndStaleTransitions`, `voicegroupviewcachecheck/VoicegroupViewCacheTest::mergeRules`, and `voicegroupviewcachecheck/VoicegroupViewCacheTest::coordinatorRoutesTransitionsAndGates`. Names/IDs identify an executable check, never substitute for an asserted predicate.
- Exercise the compiled `SongHistory`, `SongDocument`, `DocumentSession`, `ProjectService`, and real bank worker through these existing owners. A controlled async `BankHistoryAction` may hold or fail a core transition to test admission/error state; it cannot replace real service apply/revert/lease checks. Compare observable document identity/dirty state, voice/slot/lease snapshots, token rejection/renewal, undo/redo availability and reached states, and tab-session close admission rather than duplicating private Qt stack/cache classes or asserting inaccessible stack internals.

# Implementation steps

1. Fix the save/seal distinction in the two production owners above. Assert the C++ A038/A039 sequence directly on compiled `SongHistory` using a mergeable bank action **only to observe core history bookkeeping**: two same-field edits separated only by `markSaved(currentIdentity)` remain one undo step; explicitly call `sealBankMerge()` before a third edit and observe two steps. Separately save and edit through the real `DocumentSession`/worker: the first subsequent clean-bank edit seals the prior command, so one undo reaches the just-saved bank view rather than crossing it. Saving after a document edit must still seal its document merge boundary. Do not skip the real service check or alter a `cppID` to imply it passed.
2. In `viewcacheHistoryLifecycleParity`, preserve the single ordered A001–A032 script:
   - A001–A007: valid identity and empty history, real document edit/undo/redo, exact document values and saved/current identity (or its observable dirty equivalent).
   - A008–A016: occupied-slot scalar bank edit, unchanged document identity, inverse and forward voice on undo/redo, and untouched other rows at each step.
   - A017–A021: blank-slot materialization with real token, successful revert on undo, rematerialization on redo with a **different** token, spent old-token rejection, unchanged other slots.
   - A022–A032: in that sequence, invalidate a blank undo token and then a blank redo expectation by intervening real-worker mutations; each stale replay leaves view/document intact, removes only its stale entry, preserves saved/current document identity and earlier reachable undo, and leaves the invalid redo unavailable. Reacquire current snapshots/leases/expectations after every transition; never reuse a prior undo/redo draft as a new one. Additionally exercise a deterministic hard replay failure: throw without crossing/removing its history entry or changing document/bank state, then verify the entry remains retryable.
3. In `viewcacheMergeRulesParity`, use four isolated history instances rather than the prior shared mutable `swiftcore-bank-test` timeline:
   - A033–A035: two same-slot/same-field scalar changes against an isolated staged service collapse; one undo restores the original voice.
   - A036: isolated real service A→B→A annihilates the bank entry; the immediately preceding **document** edit is the next undo.
   - A037: isolated staged real service performs five valid sequential edits: blank materialization, scalar edit on that slot, edit on another slot, different changed-field set, structural voice change. Prove all five separate undo steps and intermediate views; adapt C++'s history-only pushes to actual worker expected values without changing the five no-merge categories.
   - A038–A039: a fourth, independent core `SongHistory` proves mark-saved-without-bank-seal then explicit bank seal as in step 1; the companion real service post-save boundary check proves the production caller. Do not map either site from the existing pan-merge or shared-session annihilation assertion.
4. In `viewcacheCoordinatorRoutesParity`, stage two labeled sessions/tabs with shared-bank and second-bank identities using test-local project data, not checked-in fixture edits:
   - A040–A043: identity/read on fresh session, dirty publication after a bank edit and clean refresh after save.
   - A044–A049: admitted Initial transition; while held, a second request for its owner is refused, owner close/mutation is gated, other tab close remains admissible. Complete or conflict a **different session's** bank identity and assert the original owner remains pending and unchanged; only the owning completion records one undoable edit and releases its gate. Do not fabricate a callback of another identity into a Swift session that cannot receive one.
   - A050–A055: freshly requested Undo and Redo on the owning identity cross one step each, adopt the right bank view, change history availability and release the gate.
   - A056–A066: Initial conflict keeps history/view unchanged; stale Undo and then stale Redo each remove only their failed entry without publishing a new bank view.
   - A067–A070: a different identity's hard failure cannot release the owner's held transition; the owner's hard replay failure releases its gate without consuming its retryable command; closing/clearing and reopening exposes no old bank view or blocked action.
   Use deterministic controlled suspension for pending/history admission and real service results for bank receipts, not sleeps or incidental actor scheduling. Keep tab/identity snapshots and the number of reachable undo/redo steps at each point; a reported `cppID` alone proves none of this.
5. Extend `runBankHistorySuite` to execute all three predicates after its fixture-root guard without removing or weakening existing scalar, blank, merge, sharing, stale, and hard-failure checks. Give independent staged scripts unique `stageTestProject` directory names and service/session lifetimes; never remove another active scenario's staged tree. Compare exact before/after snapshots at each meaningful transition so Task 16 can locate each ledger site's actual runnable assertion.

# Acceptance predicate

- `deno task verify --filter swiftcore --verbose` passes with all three newly dispatched method-named predicates and the already-green SwiftCore checks. It exercises the compiled app/service/history sources, real staged bank writes/reverts and failures, isolated four-case merge policy including A038/A039 and post-save clean-bank seal, and two-tab/two-identity Initial/Undo/Redo/conflict/hard-error/gate states. No `vgbankcheck` run or retired Qt test substitutes for this Swift runtime evidence.
- For each source site A001–A070, the corresponding method contains an actually executed value/state assertion under the original setup, ordering, and row constraints; some Swift assertions may cover multiple sites only if they really prove each constituent condition. If an original site (notably a foreign completion or per-tab gate) has no observable equivalent in these compiled Swift owners, stop and report the exact site, missing API/behavior, and attempted observation to the controller rather than inventing a cache double, claiming the `cppID` as proof, or calling the task green. Task 16 receives only the resulting runnable predicate names, observed assertions, and passing command; it alone changes `proof.tst_voicegroupviewcache.txt` and runs its structural `deno task proof check`.

# Task-specific constraints

- Keep the production fix limited to bank-versus-document merge boundaries; no Qt C++ port, extra bridge, duplicate coordinator, new fixture corpus, or broad history refactor. Preserve existing successful check scenarios and their IDs.
- The frozen ledger stays untouched here; its 70 current `GAP`s remain open until Task 16 maps actual runtime predicates. No source retirement in this task.
