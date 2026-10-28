# App and QML ownership cutover

## Context

Expose independent voicegroup editing through existing presenters, commands and close gates, using only task 1's backend interface in [spec.md](spec.md). Read plan.md Global Constraints and spec.md first. Task 1 may be in progress; consume the specified interface rather than editing backend files.

## Exact write set

Production: `src/swift/app/ApplicationSession.swift`, `ApplicationSession+Audio.swift`, `ApplicationSession+Commands.swift`, `ApplicationSession+Close.swift`, `ApplicationSession+Tabs.swift`, `ApplicationSession+ProjectOpening.swift`, `DocumentWorkspace.swift`, `SongTabsController.swift`, `SongTabsController+Close.swift`, `history/UndoHistoryPanel.swift`, `history/UndoHistoryRow.swift`, `voicelist/VoiceListController.swift`, `voicelist/VoiceListController+Bank.swift`, `voicelist/VoiceListController+Editor.swift` if it exists, `kitstudio/KitStudioWorkflow.swift`, `export/WavExportJob.swift`, `shell/ShellPresenter.swift`, `shell/ShellPresenter+ActionPolicy.swift`, `shell/ShellActionCatalog.swift`, `commands/KeybindingRegistry.swift`; new `src/swift/app/VoicegroupEditingTarget.swift` and `CMakeLists.txt` only if a coherent named type needs them.

QML: `src/ui/shell/ShellWindow.qml`, `ShellContent.qml`, `UndoHistoryDock.qml`; `src/ui/songview/quick/docks/VoicegroupPanel.qml`, `VoiceEditor.qml`, `SongsDockColumn.qml`.

Checks: `src/checks/editorqml/tst_ShellVoicegroup.qml`, `tst_ShellVoicegroupEditing.qml`, `tst_ShellVoicegroupSave.qml`, `tst_ShellVoicegroupPicker.qml`, `ShellVoicegroupSupport.qml`, `tst_ShellTabs.qml`, `tst_ShellTabsBankLifetime.qml`, `tst_ShellTabsClose.qml`, `tst_ShellTabsReload.qml`, `tst_ShellTabsOpenSelect.qml`, `tst_ShellTabsWindowClose.qml`, `tst_ShellTabsDrawer.qml`, `tst_ShellTabsMouseHints.qml`, `tst_ShellUndoHistory.qml`, `tst_ShellKeys.qml`, `tst_TextContrast.qml`, `ShellTabsSupport.qml`, `ShellQmlEntries.swift` only if fixture declarations require it. Missing paths in this allowed list are not instructions to create them: discover actual existing check names and ask the controller for any extra write path. No backend or docs edits; controller owns docs.

Additional approved paths: `src/swift/app/voicelist/VoiceEditorController.swift`, `src/swift/app/EditorCommandRouter.swift`, `src/swift/app/samplestudio/SampleStudioWorkflow.swift`, and existing `src/checks/editorqml/tst_ShellWindowShortcuts.qml`, `tst_ShellWindowFocus.qml`, `tst_ShellWindowParameterKeys.qml`. These replace guessed missing editor/key paths where appropriate.
`src/swift/app/shell/ShellActionState.swift` is also approved for notifying current-target command labels. Preserve Split Studio draft-local undo and actual Save Voicegroup persistence; original-destination commits target the session captured when editing began, never the currently selected song's group.
Additional command verification paths: existing `src/checks/editorqml/tst_ShellMenus.qml`, `tst_ShellMenusCommands.qml`, `ShellMenusSupport.qml`, and `src/checks/keyboard/KeybindingRegistryChecks.swift`. Standard Save targets the active owner; Save All uses `Ctrl+Shift+S`; explicit Save Song/Save Voicegroup are unbound. Retained-group selection uses canonical `ProjectBankViews.sessions()`, not a second cache.
`src/ui/songview/quick/swiftroll/SongTabs.qml` is approved to bind page-stack editing to the existing canonical `isClosingAll` state. Preserve that closing state through actual project/service release; clear only on Cancel or after installing the replacement project. Keep close dialogs operable and await retired document closure before releasing their service.
`src/checks/editorqml/tst_ShellSampleStudioVoice.qml` and `tst_ShellEditInStudio.qml` are approved for ownership-aware regression coverage. Preserve sample undo and existing-kit save-back invariants; do not weaken valid persistence assertions.

## Prerequisites

Task 1's public interfaces in spec.md only. Baseline build/index succeeded at `78bb76e20f18958757ee3fda90d10726442560bf`.

## Interface contract

Voice/kit edits target `DocumentSession.voicegroup.apply` / `applyKit`; voicegroup dirty state comes from that session's publication. Song stars and `documentDirty` represent song only. Voicegroup controller retains an independent session and stays usable after the last song closes. Existing project-close bank gate targets retained sessions, with real save/discard and one prompt per canonical identity.

Use existing shell action/shortcut machinery for the current edit target. The song-assignment selector remains a song action; parameter editor and voice rows target the voicegroup. History dock renders the selected owner's steps, busy state, saved marker and jump behavior. Add context-sensitive standard Save and explicit Save Song/Save Voicegroup/Save All actions with truthful labels/enabling; do not leave dock Save wired to song save. Retain local text editing and global Space priority. Surface state is declared and observed through QtBridge.

## Implementation steps

1. Migrate all owned voice and kit mutation callsites to the backend session. Separate controller's bank binding from optional song context/used marks so dirty banks survive tab removal and remain editable; selecting an assigned group still edits song config when a song is present.
2. Remove bank dirt from song/tab/window dirty indicators. Show a named group-specific star. Adapt export's mutation guards and existing observers to new owners without global blocking of unrelated histories.
3. Route undo/redo/history and standard Save using a clear current editing target in the existing router; explicit save actions are unambiguous, and text fields retain their native command ownership. Save All operates each dirty song/group once, including zero-tab groups, with explicit failure handling.
4. Keep song close/reload document-scoped; protect retained dirty banks at project close/switch/quit via the existing bank gate. Before release, wait for every canonical group's admitted operations and observe settlement even when it has no song or editor subscribers; detach close-owned observations on settle/cancel. Implement functioning bank Discard and Save failures; do not mark a dirty bank answered without restoring it. Avoid changing a confirmed close target across awaits.
5. Migrate affected QML checks from mixed song/bank expectations to the spec. Cover real parameter editing, focused keyboard undo/save, unchanged MIDI bytes on bank save, independent song/bank stars, shared history across two songs, retained editing after last-tab close, Save All and bank Save/Discard/Cancel/failure. Reuse fixtures and production QML rather than copied surfaces.

## Acceptance predicate

All five spec scenarios hold through the mounted production surfaces. Controller runs `uv run --no-sync dev build:checks`, `uv run --no-sync dev checks:shell --filter shell-voicegroup --filter shell-tabs --filter shell-undo-history --filter shellwindow-shortcuts --filter shellwindow-focus --filter shellwindow-parameter-keys --filter shell-text-contrast --pool=1`, `uv run --no-sync dev checks:bridge`, `uv run --no-sync dev checks:qml-aot`, and formatting at the settled-tree gate. Existing voicegroup save/editing checks cover persistence and real UI gestures; tabs/bank-lifetime checks cover no-tab retention and close gates. Add focused behavioral cases for independent command targets and Save All if not covered; do not count unselected filters as evidence.

## Task-specific constraints

SHARED_TREE: skip build/test/lint/formatter commands while writing; perform read-only local structural inspection and report checks DEFERRED_TO_CONTROLLER. No backend changes, commits, report or scratch files. Coordinate interface mismatches through the controller. Keep QML text contrast in all themes; use existing palette pairs and font-relative geometry. Any newly touched Swift check source requires controller inspection for proof-ledger ownership; none currently exist.

## R1 audit fixes

Use the m1 `GracefulOwnershipAudit` and `AppSpecGate` findings, with the controller decisions below. First add focused QML regressions for retained-group sample import/captured destination and no-song Standard Save, while backend adds export/cancellation probes. Freeze checks for the controller's failing-before runs; do not mutate production until the controller releases the repair phase.

1. Remove the shared-group busy precondition from immutable WAV export capture; retain song-assignment transition safety. Coordinate the `bindingTransitionInFlight` rename with backend.
2. Sample Studio captures its canonical destination group, slot and expected voice at admission and commits through that captured group, including with no song tabs. Never re-read the currently displayed group's value as a substitute conflict baseline. Migrate picker sample info/audition to the project service and bound group; investigate actual no-song voice audition with the existing audio seam and preserve it without a dependency workaround.
3. Cancel must stop bank close immediately during an admitted Save/Discard. Delete the swallowing guard; retain the existing in-flight sentinel until its completion clears it, so late completion cannot advance the cancelled walk. No cancellation flag or new state machine. Remove `answeredCloseBanks`; successful real saves/discards are represented by canonical clean state alone.
4. Keep only `documentDirty`; remove its duplicate `songDocumentDirty` property and migrate callers. Remove obsolete async-history consumers and stale song-bank transition names. Move catalog refresh off song-only saves onto successful group-save paths.
5. Replace command-target `objectName` matching with declared semantic ownership on the existing roots. Prefer statically typed component casts/local control references over untyped dynamic properties, new AOT rejections, or wrapper infrastructure. Persistent chrome keeps the last valid editing domain; with no song remaining, the bound voicegroup is the effective command owner. Cover no-song Standard Save after the song was the last focused editor.
6. Remove `VoiceListEditOrigin`'s redundant source/section fields; the immutable canonical session identity suffices. Rebuild retained-group choices from actual group/binding/save changes, not every song refresh; keep close wake-ups owned by close/save transitions. If Kit Studio applies to a captured background group but persistence fails, refresh its retained dirty indicator on the guarded failure path too.
7. Reuse backend `VoicegroupSession.displayName` and the exposed `copyVoice` conversion. Put existing-kit padding/edit construction with the existing `KitDraftCodec` implementation, not a second mapping in the workflow. Add explicit closure types. Initialize a newly created action's target label without re-evaluating the entire action catalog.
8. Add consumer regressions for retained-group sample import and captured destination, no-song picker info/audition where the existing seam supports actual behavior, and normalized no-song keyboard ownership. Native export/cancellation/saved-marker probes belong to backend. Extra approved paths: `ApplicationSession+Samples.swift` and the existing `KitDraftCodec` implementation; discover their actual locations before editing.

Keep the two explicit history projections rather than introducing a new common history protocol/framework. Do not add a project-release flag, retries, synthetic focus forwarding or a compatibility path. All existing full native, GUI, studio, bridge, AOT and format gates remain required, followed by an m1 fix review.

Additional approved GUI consumers: `src/checks/editorqml/tst_ShellExport.qml` and `tst_ShellImportCommit.qml`, limited to migrating the removed dirty-property alias; their existing export/import harnesses join the verification gate.
