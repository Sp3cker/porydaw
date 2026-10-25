# Backend ownership cutover

## Context

Move voicegroup edit history and lifecycle out of song documents. App/QML task 2 consumes the public interface in [spec.md](spec.md); preserve that interface and communicate concrete blockers immediately. Read plan.md Global Constraints and spec.md first.

## Exact write set

Production: `src/swift/core/SongHistory.swift`, `DocumentChangeSet.swift`, `SongDocument.swift`; `src/swift/document/DocumentSession.swift`, `DocumentSession+Internals.swift`, `SharedBankState.swift` (replace/remove), `ServiceBankHistory.swift`, `CMakeLists.txt`, `service/ProjectService.swift`, `service/ProjectService+Bank.swift`; new `src/swift/document/VoicegroupSession.swift`, `VoicegroupHistory.swift`, `ProjectBankViews.swift` if needed; `src/swift/project/ProjectStore+Bank.swift`, `ProjectStore+Save.swift`; `src/swift/voicegroup/VoicegroupStore.swift`, `VoicegroupSource.swift`, `VoicegroupSave.swift`.

Checks: existing `src/checks/workspace/SessionChecks.swift`, `bank_edits.swift`, `bank_history_probes.swift`, `bank_saves.swift`, `bank_sharing.swift`, `bank_sharing_history.swift`, `bank_switching.swift`, `bank_undo_publication.swift`, `history_jump.swift`, `session_save.swift`, `session_save_delta.swift`, `session_io.swift`, `session_playback.swift`, `session_support.swift`, `voicegroup_creation.swift`, `sample_commit.swift`; `src/checks/editcheck/DocumentHistoryChecks.swift`, `NoteHistoryChecks.swift`; `src/checks/projectstore/BankOwnershipChecks.swift`. Ask the controller for any additionally required write path before modifying it. No app/QML/docs edits.
`src/checks/editcheck/NoteChecks.swift` is additionally approved solely to remove the obsolete `confirmedBankOrdering(report)` mixed-owner probe registration; preserve all document-only note/history checks.
Additional check-only migrations: `src/checks/projectstore/BankLeasesChecks.swift`, `ExportCaptureChecks.swift`; `src/checks/drawerpresentation/voice_lifecycle.swift`; `src/checks/velocity/VelocityClickCancellationChecks.swift`, `tst_velocityediting.swift`; `src/checks/voicelist/voicelist_session.swift`. Preserve observable export, presentation and audition guarantees while migrating removed bank APIs.
`src/checks/voicelist/VoiceListChecks.swift` is approved to remove obsolete no-song assignment-selector enablement/callback probes; real song-assignment behavior remains covered in `voicelist_session.swift`. Bank save failures must retain their typed error and identify the original source/section even when resource discovery fails before writing.

## Prerequisites

Pushed UI checkpoint `78bb76e20f18958757ee3fda90d10726442560bf`; worktree provisioned and baseline build/index succeeded. No production prerequisite from task 2.

## Interface contract

Implement all backend contracts in spec.md exactly. Preserve SongHistory document identity, merge, track remap, cap and projection semantics while removing whole bank-entry/action replay ownership from it. Remove obsolete bank-only test probes from Core-only check modules rather than introducing a Document dependency there; retain meaningful bank behavior coverage in the existing workspace bank suite. Preserve song-assignment load failure/undo semantics and selection repair. Public reference changes require LSP references first; unavailable reference results must be reported, not trusted as absence.

## Implementation steps

1. Evolve the existing canonical registry and shared state into the spec's voicegroup session; keep one publication/observer path and project-scoped lifetime. Protect project epochs and avoid new retain cycles.
2. Extract bank undo/merge/replay into VoicegroupHistory; record only successful edits and share history across all consumers. Remove bank payload/inbox paths from song history and session, preserving document-only behavior and assignment transitions.
3. Route bank and kit mutations through the new session; provide real independent save and discard via existing storage. Retain section-aware external edit rebasing, other groups' pending edits, aliases, materialization and kit dependencies. Save/discard invalidate/seal history only at their actual success boundary. No catch-and-ignore or fallback on conflicts.
4. Make song save song-only; expose the new session, registry access and history projection contracts for task 2, without obsolete bank-edit compatibility methods.
5. Migrate affected backend checks and add consumer-visible coverage for shared chronological undo, independent persistence/dirty state, last-song lifetime and failure/discard. Delete assertions that exclusively require the removed mixed-owner behavior. Do not re-pin incidental implementation tests.

## Acceptance predicate

The spec's five acceptance scenarios hold at the backend seam; all public callers have a migration target and no bank history remains owned by SongHistory. Controller runs `uv run --no-sync dev build:checks`, `uv run --no-sync dev checks --filter swiftcore-bankhistory --filter swiftcore-projectsession --filter swiftcore-documenthistory --filter swiftcore-noteedits`, then the plan's settled-tree gates. Existing bankHistory and projectSession registrations cover shared publication, editing, save, switching, history and lifecycle. Core document-history and note-edit suites protect document-only identities, gestures and remaps. Report any coverage gap explicitly.

## Task-specific constraints

SHARED_TREE: skip build/test/lint/formatter commands during writing; perform read-only local structural inspection and report checks DEFERRED_TO_CONTROLLER. Preserve App task 2's disjoint ownership. No commits, report files or scratch files. Swift proof ledgers are absent; do not create any.

## R1 audit fixes

R1 reviews: `GracefulOwnershipAudit` (m1) and `BackendSpecGate`; controller adjudicated the proposed removal of the explicit save marker as unsafe without replacing its policy.

1. Reproduction phase: add deterministic native coverage for export capture during an admitted shared-group operation, and Cancel after a bank close-answer is admitted but before its real Save/Discard completes. Use existing action/task/save-state seams and real storage. Freeze the check sources before any production repair; controller runs the failing-before probes. No hooks, polling or C++ adapter.
2. Replace `BankResultInbox` with typed replay results: `BankHistoryAction.apply` returns `AppliedBankEdit`, and history step returns the optional applied result. Preserve progress when retiring a stale entry by observing the existing history revision, not by conflating a nil result with no cursor change. Publish only after the cursor/action record is updated.
3. Remove the history's copied busy flag. Use one session observer channel for documents and UI; document `.bank` notifications must ignore busy/history-only and value-identical publications. A session-owned semantic value revision is permitted to preserve precision without repeated table comparisons in document observers. Restore observable-value equality suppression while always accepting the latest lease.
4. Synchronize saved markers from clean canonical content after the history cursor settles. Busy publications must not mark the pre-replay cursor saved: an independent song-open publish can interleave while replay awaits. Apply the same rule at operation finish and out-of-operation publication; remove exact-publication-revision save/discard failures, but never reset history over a newer dirty value. Add meaningful adversarial coverage using the existing controlled action seam.
5. Delete obsolete async `SongHistory.undo/redo` forwarding wrappers and migrate callers to document-only synchronous operations. Rename remaining song-assignment state to `HistoryDirection`, `beginBindingTransition`, and `bindingTransitionInFlight`. The final audit refines the intermediate `saveInFlight` name to internal `songOperationInFlight`, covering persistence, assignment loading and replay; coordinate app-facing migrations.
6. Rename `SharedBankState.swift` to `ProjectBankViews.swift` and the old document notification method to voicegroup terminology. Add Qt-free `VoicegroupSession.displayName` using the existing load-name/section fallback, and expose the existing `copyVoice` conversion (no duplicate alias) for Kit Studio. Avoid duplicate owner prefixes in superseded-save errors.
7. Migrate all owned native checks, including the controlled orphan-close action, for the typed result and renamed APIs. The app retains only `documentDirty`, removes `songDocumentDirty` and `answeredCloseBanks`; migrate native consumers accordingly. Cover unchanged-publication suppression without testing wiring alone.

No new history framework, module, retry queue, or project-release flag is authorized. Preserve the existing document suspension admission policy. Controller runs the full native/storage/lease/export gate and app integration gates after both writers freeze, then obtains fix review against an immutable R2 patch.

Additional approved native consumer: `src/checks/rollcheck/ruler_loop_menu_sweep.swift`, limited to the neutral history-direction type migration.
