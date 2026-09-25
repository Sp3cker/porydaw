# Context

R08: saving one bank section must not discard an unsaved bank section in the same physical source file. `VoicegroupStore` currently holds separate whole-file `VoicegroupSource` snapshots by section identity; saving B changes the file timestamp, and the next load of dirty A replaces its record from disk. The original switching checks do not cover this inherited data-loss case. Repair source ownership, not the timestamp symptom. Read [plan.md](plan.md) Global constraints and its linked spec. The following BANK-CLOSE task depends on safe sequential saves of dirty banks sharing a file.

The controller captures BASE from the accepted shared-bank/audio checkpoint at dispatch. Do not dispatch before task 12's review/checkpoint: its proof ownership overlaps the save-core surface.

# Exact write set

- `src/swift/project/VoicegroupSource.swift`
- `src/swift/project/VoicegroupSave.swift`
- `src/swift/project/VoicegroupStore.swift`
- `src/checks/projectstore/VoicegroupBankLogicChecks.swift`
- `src/checks/projectstore/SaveCoreChecks.swift`

The controller owns any necessary source-local proof handoff to `src/checks/voicegroupsave/proof.savecore.txt`. Existing `saveCoreBankRoundTrip` anchors and unresolved UI/save clauses remain intact; new same-file regressions do not retroactively create an original C++ assertion for this gap. No implementer proof edits.

# Prerequisites

Task 12 supplies immutable shared-bank publications and complete bank identity. Preserve those interfaces without editing the app publication cache. The existing project-store bank-logic and save-core registrations already execute the two check files; no new lane or registration is required.

# Interface contract

- Preserve the public interfaces of `VoicegroupSource`, `VoicegroupStore`, `LoadedBankView`, `VoicegroupId`, edit results and blank-materialization tokens. A bank remains identified by relative source path plus section label within its store.
- Add internal `VoicegroupSource.rebasePreservingEdits(from disk: VoicegroupSource) throws -> Bool`. The argument is a successfully parsed disk snapshot of the same source/section identity. Return true only when the selected section's current editable bytes remain unchanged after rebasing. Adopt disk changes outside that section and use the fresh disk bytes as the pristine baseline. Keep the local selected section and its dirtiness when disk still matches its prior baseline. If disk already matches the exact local section, adopting that baseline may make it clean. A dirty overlapping section change throws without altering the source. A clean externally changed selected section returns false without mutating the receiver, allowing the caller to adopt the fresh source through its existing native-load transaction.
- `VoicegroupSource.save()` must reconcile against current disk bytes before writing, even when timestamps compare equal. It writes only the selected section's pending change into the fresh full-file image; unrelated bytes remain exact. Standalone banks own their whole source. Missing, invalid, relocated or overlapping source input fails explicitly rather than recreating or overwriting it silently. A failed write retains the selected edits and dirty state; no success or clean receipt may be fabricated.
- Parsing used for rebase must validate before committing parsed fields. Failure cannot leave new line arrays paired with old slot indices or pristine bytes. Preserve existing source declaration resolution, formatting and narrow materialization semantics.
- `VoicegroupStore.loadBank`, `refreshIfStale` and `saveVoicegroup` keep source, native bank and publication coherent. Reuse the current native bank and token registry when only other sections changed. A true selected-section reload retains the existing load-before-install transaction. Do not expire a materialization merely because a sibling section saved. Publish clean/dirty changes honestly; prior `LoadedBankView` values remain immutable.

# Implementation steps

1. Add a two-section regression to the existing bank-logic suite before changing production. Both banks are open before edits. Edit A, edit/save B, then load A again. Assert A's edited value and dirty state survive, while disk contains saved B and still-original A. Stop after this check-only phase for the controller's before-state observation.
2. Implement section-aware byte rebasing in the existing source owner. Reuse the parser's selected-section boundaries rather than adding a parallel source parser or whole-project file store. Preserve CRLF/raw formatting, comments, unrelated section order and trailing-LF convention, including a sibling insertion that changes the selected section's line offset. Do not replace dirty A with its on-disk snapshot or write A as part of B's Save.
3. Integrate rebasing with cache refresh and source save. A swallowed refresh error must not permit a subsequent destructive write. Retain canonical native ownership and narrow undo tokens when the selected section is unchanged; prepare any replacement native bank before installing a genuinely changed selected source. Preserve the existing loader worker and actor confinement.
4. Extend the native regression through independent disk reload, a later Save of A that preserves B, and narrow blank-materialization undo after a sibling save. Exercise an earlier sibling's line insertion so offset rebasing is real. Add source-level refusal coverage for an overlapping disk edit and malformed/missing selected section: disk bytes and local selected edits survive failure. Prove a same-timestamp sibling change is preserved by Save. Keep fixture setup within the runner's staged-project conventions, with explicit timestamps where a refresh fence is the stimulus rather than sleeps.
5. Keep the existing standalone save, stale clean-store refresh, expected-value conflict, preview-only and materialization behavior checks. Remove stale comments in touched constructs without adding new code comments. Do not re-pin incidental counts or wording; compare the meaningful bank values and conserved bytes.

# Acceptance predicate

The new same-file regression fails with dirty A lost before the repair, then passes with A retained and only B persisted. Later saving or undoing A preserves B exactly. Real native bank publications agree with the retained source, independent fresh loads agree with saved bytes, and conflict/failure paths preserve pending selected edits rather than silently replacing them.

Controller-run named checks after the writer freezes:
- `deno task verify --filter projectstore-banklogic --verbose` — before-state reproduction, then native cache/save/materialization regressions.
- `deno task verify --filter projectstore-savecore --verbose` — standalone/source-save and section-byte conservation/refusal checks.
- `deno task verify --filter projectstore --verbose` — source parsing/editing, actor operations, lease and stale-store consumers.
- `deno task verify --filter swiftcore --verbose` — shared document bank bindings, save/history and non-autosaving voicegroup switching from task 12.
- `deno task proof check --executed` — after any required frozen-source proof handoff; retain unrelated unresolved clauses.

# Task-specific constraints

No autosave on bank selection, all-bank Save command, close dialog change, generic merge framework, timestamp bypass, native ABI change or new source-copy authority. Overlapping external edits are a visible conflict, not permission to choose one writer silently. Do not claim whole-project atomicity: MIDI/flags and synth-definition write ordering are unchanged. Keep unrelated source formats and the public save/edit contracts intact.
