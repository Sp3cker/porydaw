# Task 110 brief — voice edits share save and Undo without dirty-state drift

# Context

Finish the voice editor release/save/Undo journey: document dirty state, bank dirty state, engine value, disk bytes and asynchronous save receipt must agree at their own boundaries. This is not the unresolved catalog-outage policy or a New Voicegroup implementation. Task 113 reuses the settled shell command owner afterward.

Verified planning selection: **43 open rows (34 GAP + 9 PARTIAL)**. Counts are the in-flight snapshot, not a post-106 completion claim.

- `src/checks/voicegroupsave/proof.savecore.txt` — A003, A004, A015, A028, A029, A031, A032, A033, A034, A035, A036, A037, A038, A039, A040, A041, A042, A043, A044, A045, A046, A048, A053, A054, A056, A057, A063, A064, A065, A066, A067, A068, A072, A073, A075, A078.
- `src/checks/voicegroupsave/proof.presentation.txt` — A055, A056, A057, A058, A059, A063, A077.

Oracle: `fceecd88`; per-ledger source pins, in the order above: `c1f165eb1aa49af49c72a3e4f15cf6d9f23b6735`, `4346c26abdcab317ccf97e178c959a82301081c9`. Read each selected original expression through `deno task proof sites` / `show`; the original C++ check paths are absent and must not be recreated.

# Exact write set

- `src/swift/app/DocumentSession.swift`
- `src/swift/app/ApplicationSession.swift`
- `src/swift/app/shell/ShellPresenter.swift`
- `src/swift/app/voicelist/VoiceListController.swift`
- `src/swift/app/voicelist/VoiceEditorController.swift`
- `src/ui/songview/quick/docks/VoiceEditor.qml`
- `src/ui/shell/ShellWindow.qml`
- `src/checks/workspace/bank_saves.swift`
- `src/checks/workspace/bank_switching.swift`
- `src/checks/editorqml/tst_ShellVoicegroup.qml`
- `src/checks/voicegroupsave/proof.savecore.txt`
- `src/checks/voicegroupsave/proof.presentation.txt`

Closed list: production files are conditional repairs only within the interface below; correct owners remain unchanged. Selected ledger rows change with their proving surface, not in a standalone reconciliation.

# Prerequisites

All 99–106 precede Group A. Rebase ApplicationSession over 103's final-close/lifecycle work; ShellWindow over 99/106; preserve existing task-89/98 bank-save and voice-editor contracts. The savecore A016–A026 user decision is not a prerequisite and is not selected.

# Interface contract

- `DocumentSession.save`, `applyBankEdit`, `ApplicationSession` save routing and `ShellPresenter.windowModified` retain their current ownership. Window-modified follows document dirty state; bank-only changes have their own dirty state. Save captures one coherent snapshot and completion cannot clean newer edits.
- Missing-argument selection both reports a visible status containing the argument and preserves the last valid bank while adopting the intended cfg argument. Do not expand this into savecore A016–A026's unresolved unavailable-directory/catalog policy.
- Drive the real release field and real standard Undo. Prove exact bank release and engine release before/after, document clean state, window unmodified state, one Undo activation, and disk bank bytes unchanged by Undo. Then make a song edit and prove the document/window dirty boundary independently of bank-only dirty state. DirectSound must offer the synth controls before a type switch; a later Square-only control observation cannot close presentation A063.
- `bankQueuedSave` must observe genuine asynchronous yielding/receipt, not inline completion or a fabricated native heartbeat counter. Preserve captured-stale/newer-edit behavior. After two note undos the document stays dirty while the saved bank stays clean; undoing past the bank edit makes both dirty; re-save cleans the intended snapshot. Reopen the persisted bank and observe the exact release value, not only that reopening succeeded.
- Retire savecore A028/A032/A033/A035/A036/A037/A038/A046/A053/A065/A066/A068/A078's native widget/action/fixture guards, and presentation A055–A059/A077's native file/fixture staging, only alongside the resulting consumer journey. A039/A040's real focused-field Undo propagation, A041's exactly-once edit and A042–A045's state/bytes remain behavioral even though their native event/action representation disappears. No setup-only replacement assertions.

# Implementation steps

1. Extend bankQueuedSave and bankSaveRoundTrip with the exact document/bank dirty and asynchronous receipt clauses; extend the existing missing-argument bank-switch check without entering catalog-outage policy.
2. Extend the real release/Undo/unified-save journeys in tst_ShellVoicegroup, including focus, exact engine/bank release, disk-byte preservation, window-modified and pre-switch DirectSound controls.
3. Repair only demonstrated divergence in the declared save/presenter/voice-editor owners; preserve 103's tab lifecycle and the one canonical Undo path.
4. Map the selected 43 rows with exact boundary evidence and bounded representation retirements. Keep both ledgers: savecore A016–A026 and presentation A032–A037 remain unselected.

# Acceptance predicate

checkcatalog registers bankHistory as swiftcore-bankhistory; bankQueuedSave/bankSaveRoundTrip do not become covered merely by running projectsession. Run both domains and the real shell-voicegroup lane. All 43 selected rows close; the eleven catalog-policy and six New Voicegroup rows remain intact.

Under sprint-3 §12's controller-owned settled-group verification policy, the narrow commands are:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-bankhistory --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --filter swiftcore-projectsession --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --filter shell-voicegroup --verbose
```

The §12 full-shell, full-verify and executed-proof gate also applies; these narrow runs are not a replacement.

# Task-specific constraints

Read sprint-3 §10–§12, including §12 “Evidence and execution contract,” as part of this brief. No New Voicegroup, catalog-outage decision, applied-song-volume proxy, host row or savecore A016–A026 write. The visible save/Undo contract is the boundary; do not redesign project persistence.
