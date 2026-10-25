# Voicegroup editing ownership contract

## Behavior

A song owns MIDI, song settings and its voicegroup assignment. A voicegroup owns its voice parameters and kit edits. Editing a voicegroup changes playback for all songs using it but never dirties or adds history to those songs. Switching a song's assigned group is still an undoable song edit; undo reconnects the current shared group, not a historical copy of its voices. Creating a group writes a project resource and then assigns it; undoing assignment does not delete the file.

One voicegroup editing session is canonical per existing `BankBindingIdentity` (project publication owner, relative source path, section label), including aliases. No per-song voicegroup undo stacks. Sessions survive all song tabs closing and are released only with the project; dirty sessions remain reachable in the dock and in project-close gates.

A song star means song edits only. The dock names its group and shows that group's dirty star. Undo/redo and the history panel target the current editing surface: roll/events/song assignment selector target song; voice rows/parameter editor target voicegroup. Text entry retains its local editing ownership. Use the existing shortcut path; no synthetic key forwarding or global shortcut competition. Menus identify their actual undo/save target. The dock Save button saves only its group. The existing standard Save command is context-sensitive; Save All saves all dirty songs and canonical groups once, including groups with no song consumer. Explicit Save Song remains available. Only song saving writes MIDI/flags/backups; only group saving writes group resources. Saving one owner never clears another owner's dirtiness.

Closing/reloading a song protects its song edits only, and does not discard its group's edits. Project switch/quit protects each dirty song and each dirty group once. Bank Discard restores the bank for all consumers and its history coherently, not merely suppressing a prompt. Save or discard failure preserves the pending close and editable state; Cancel cancels closing. No edit can enter a project being released. Keep storage's existing section-aware rebase/conflict and kit dependency behavior.

## Backend interface consumed by app task

All new document-layer types are Qt-free and `@MainActor`.

- `DocumentSession.voicegroup: VoicegroupSession` is publicly readable; bound bank snapshot accessors (`bankLease`, `bankSlots`, `bankLoadName`) remain useful read projections. Remove `DocumentSession.bankDirty`, `applyBankEdit`, `applyKitEdit` and bank-action inbox/history ownership. `DocumentSession.save()` saves song only. Assignment load/undo retains safe suspension protection.
- `VoicegroupSession.identity: BankBindingIdentity`, `value: AppliedBankEdit`, `isBusy: Bool`, `history: VoicegroupHistory` are publicly readable. `value` remains the authoritative published bank/dirty snapshot.
- `VoicegroupSession.addObserver(_ observer: @escaping @MainActor () -> Void) -> UUID` and `removeObserver(_ token: UUID)` expose canonical value/history/busy changes independently of song subscribers. Publish busy begin/end and committed results through the same path; UI observers capture weakly and detach on rebind.
- `VoicegroupSession.apply(slot: Int, value: BankVoice, expected: BankVoice?) async throws -> AppliedBankEdit` and `applyKit(_ edit: KitEditValue, expected: KitEditValue) async throws -> AppliedBankEdit` commit and record the shared history. Redundant edits do not create entries. Existing compare-before-edit conflict behavior remains.
- `VoicegroupSession.undo() async throws -> Bool`, `redo() async throws -> Bool`, `jump(toIndex: Int) async throws -> Int`, `save() async throws`, `discard() async throws` operate on that same session. Save and discard publish to all consumers, even without any song. Save failure leaves dirty state/history; discard failure leaves the previous live state. No service/session retention cycle.
- `VoicegroupHistory` exposes `revision`, `undoCount`, `undoIndex`, `canUndo`, `canRedo`, `hasEvictedSteps`, `baseIsSaved`, and `step(at: Int) -> HistoryStep?` for existing history-panel projection; preserve 512-entry cap, drag merging, save seals, redo truncation and correct saved markers. Use shared domain-neutral history direction if needed, not song-owned bank entries.
- `ProjectBankViews.session(for: BankBindingIdentity) -> VoicegroupSession?`, `sessions() -> [VoicegroupSession]`, and `dirtySessions() -> [VoicegroupSession]` expose retained sessions, sorted deterministically. Evolve the existing registry rather than duplicate it. Existing service publication feeds these sessions; weak song observers notify bank/history consumers without mutating song history.

If source inspection makes a specified interface impossible or unnecessarily duplicative, report the exact mismatch to the controller and propose the smaller replacement before diverging. App/backend writers coordinate only through this interface; neither edits the other's owned files.

## Acceptance scenarios

1. Two clean songs share one session. Editing Attack changes both playback bindings, marks only the group dirty, and leaves both song revisions/history and MIDI bytes unchanged.
2. Interleaved voice edits from both songs form one chronological group history. Undo from either view reverses the latest group edit, not a per-song stale command; song-note undo remains independent. Undo/redo to the save point updates group dirtiness correctly.
3. Save group changes group files only. Save song changes song files only. Save All handles both and groups without tabs; each failure identifies the owner and cannot silently clear unsaved work.
4. Closing the last clean song leaves a dirty editable group accessible; switching songs/groups preserves other groups' dirty state/history. Project release waits for admitted operations on every retained canonical group and resumes when they settle, even after rebinding or removal of the last song. Quit/project switch then prompts once per dirty group, with functioning Save/Discard/Cancel and failure handling; cancellation removes close-owned observations and restores editing.
5. Changing a song's group and undoing it changes assignment only. Existing group edits survive. Existing blank-slot materialization, kits, aliases, external-file conflicts, playback/export leases, creation and local text shortcuts retain their observable guarantees.
