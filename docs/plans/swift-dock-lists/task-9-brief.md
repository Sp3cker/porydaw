# Context

Add the existing native **New Voicegroup** action to the Swift/QML voicegroup dock. This task creates a per-file voicegroup, refreshes the catalog, and assigns it to the selected song through the existing undoable `DocumentSession.setVoicegroupArgument(_:)` path. It is not a new-song wizard and does not implement another voicegroup presenter.

The native behavior reference is `WorkspaceUi::runCreateVoicegroupFlow()` (`src/ui/workspaceui_project.cpp:598-656`). The compiled implementation must use a new `pd_service_*` bridge on the existing `PdProjectService` worker; `CreateVoicegroupInput`/`ProjectIo::createVoicegroup` are uncompiled and must not become Swift call paths. The selected-tab bank identity supplies the copy source path and section label.

# Exact write set

- `CMakeLists.txt` — register `NewVoicegroupDialog.qml` in the existing `swift_roll_qml` resource list.
- `src/project/swift_project_service.h` and `.cpp` — add `pd_service_create_voicegroup` directly to the compiled `PdProjectService` serial worker, calling compiled `VoicegroupSource::createVoicegroup` and `appendIncludeLine`; return its result/error without depending on uncompiled `CreateVoicegroupInput` or `ProjectIo`.
- `src/swift/app/ProjectService.swift` — add `createVoicegroup(name:copyFromFile:copySectionLabel:)` using the existing catalog result and service error vocabulary.
- `src/swift/app/ProjectServiceCallbacks.swift` — add the worker completion that copies the create result/error before resuming Swift.
- `src/swift/app/DocumentWorkspace.swift` — handle the existing `VoiceListController.onNewVoicegroupRequested` intent installed through `SongTabSession.voiceListController()`; coordinate the dialog result, project service operation, and selected `DocumentSession` assignment.
- `src/ui/songview/quick/swiftroll/VoicegroupPanel.qml` — add the New Voicegroup affordance.
- `src/ui/songview/quick/swiftroll/NewVoicegroupDialog.qml` — new QML dialog with only the native name and source choices.
- `src/checks/workspace/voicegroup_creation.swift` — new service/session behavior checks.
- `src/checks/workspace/SessionChecks.swift` and `src/checks/CMakeLists.txt` — register the SwiftCore check and SwiftRollGated source/slot.
- `src/checks/swiftrollgated/voicegroupchecks.cpp` and `src/checks/swiftrollgated/tst_swiftrollgated.h` — add the real QML creation-flow check and slot.
- `src/checks/voicelist/VoiceListIntentChecks.swift` — rename the existing intent-only `cppID` so it does not claim the full creation predicate.

# Prerequisites

Tasks 5–8: task 5 provides the catalog and undoable `-G` rebind; task 6 provides `VoiceListController`, `DocumentWorkspace`, and `VoicegroupPanel.qml`; tasks 7–8 complete the editor/picker surface mounted by that panel. Run after those owners at the shared Swift, QML, and root CMake boundaries.

# Interface contract

- Reuse `VoiceListController.requestNewVoicegroup()` and its `onNewVoicegroupRequested` callback. Extend the `DocumentWorkspace` owner wiring; do not introduce `VoicegroupPresenter`, another session owner, or a second `-G` mutation path.
- `ProjectService.createVoicegroup(name:copyFromFile:copySectionLabel:)` dispatches `pd_service_create_voicegroup` on the existing worker and calls compiled `VoicegroupSource::createVoicegroup` followed by `appendIncludeLine`; it does not return a catalog. After success, `DocumentWorkspace.refreshVoicegroupData()` separately refreshes task 5's `voicegroupCatalog()` catalog-scan operation and the existing `voicegroupArgs()` backed by `pd_service_voicegroup_args`, publishing the snapshot only when both succeed. Do not conflate the APIs or duplicate group-argument enumeration. `NativeBankLease.sourcePath` is project-relative: resolve it against the open project root before passing it as `copyFromFile`; pass the selected lease's `sectionLabel` unchanged. The empty-template choice passes empty path and label.
- The dialog offers the selected tab's current voicegroup file/section as “Copy of …” when one is bound, plus “Empty (dummy template)”. The name grammar is `[A-Za-z][A-Za-z0-9_]*`; reject a duplicate when the current `ProjectService.voicegroupArgs()` contains `"_" + name` (the selector value used by the existing project path), not by searching `voicegroupCatalog()` payload data. The worker remains authoritative for a conflicting `.inc` path.
- Disable/reject submission when no project is open, a project operation is busy, the catalog is still loading, or task 5's `VoicegroupCatalogData.perFileVoicegroups` is false. For a single-file layout, show the native unsupported-layout information and perform no operation.
- Cancel has no service, file, catalog, or song-config effect. A service failure is surfaced and does not change the selected song's `-G`. On service success, await `refreshVoicegroupData()`; if either the catalog or args refresh fails, surface the error and leave `-G` unchanged without deleting the created file/include. Only after the refreshed snapshot is published, call `DocumentSession.setVoicegroupArgument("_" + name)` exactly once. It is one normal undoable config command and uses task 5's existing bank rebind/error policy; do not add a second history entry or delete the created file when the assignment is undone.
- If file creation or include-line append fails part-way, report the compiled service error and do not assign the new argument. Do not claim cross-file rollback that `VoicegroupSource::createVoicegroup` plus `appendIncludeLine` do not provide. If the subsequent bank rebind fails, preserve the previous bank lease according to task 5 and report the failure without hiding the new selector choice from the refreshed args.

# Implementation steps

1. Add the thin `pd_service_create_voicegroup` bridge to the existing compiled service worker. Call `VoicegroupSource::createVoicegroup` followed by `appendIncludeLine`, preserving its naming, copy-section, write-order, and failure behavior; resolve a bound `NativeBankLease.sourcePath` against the project root and pass its `sectionLabel`. Refresh the catalog and selector separately via task 6's `DocumentWorkspace.refreshVoicegroupData()`, which uses task 5's catalog operation and existing `pd_service_voicegroup_args`.
2. Add the QML dialog and dock button, preserving the existing workspace busy/open gate and controller intent. Copy-source values come from the selected session's bank identity, not from a guessed filename or list display label.
3. After successful creation, refresh and publish both catalog and args with `refreshVoicegroupData()`. Do not set `_name` if that refresh fails; otherwise call `setVoicegroupArgument` once and ensure undo/redo rebinds through the same session path.
4. Add the full SwiftCore service/session check for copied/empty creation, `refreshVoicegroupData()` readback of both `voicegroupCatalog()` and `voicegroupArgs()`, and undo/redo, with `cppID` `vgsavecheck/VoicegroupSaveTest::newVoicegroupCreatesAndAssignsUndoably`. Add a SwiftRollGated scenario that exercises the real QML dialog for valid submit, duplicate/unsupported state, service error, and cancel.

# Acceptance predicate

- `deno task build:app` and `deno task build:checks` succeed.
- `deno task verify --filter swiftcore --verbose` proves the service-created file/include, successful refresh of Task 5 catalog data with `perFileVoicegroups` still true and the separate `pd_service_voicegroup_args` selector feed containing the new argument, plus the selected song's undo/redo `-G` transitions and bank rebind.
- `deno task verify --filter swiftrollgated --verbose` exercises the production QML button/dialog, including cancellation and rejected submissions, without writing or assigning on those paths.
- On successful creation and refresh, the refreshed catalog has `perFileVoicegroups == true`, `voicegroupArgs()` exposes `_<name>`, and the selected song uses `_name`; undo restores the old choice/bank without deleting created source files, and redo restores `_name`.

# Task-specific constraints

- Keep the name, duplicate, unsupported-layout, cancel, and service-failure paths explicit; do not replace the dialog with an inert button or a generic error-only path.
- Preserve the `VoicegroupSource::createVoicegroup` dummy-template and copy-section behavior. Do not alter the native worker's write order or broaden to song creation.
- Keep the existing intent-only assertion under the distinct `cppID` `vgsavecheck/VoicegroupSaveTest::newVoicegroupIntentReachesOwner`; reserve `vgsavecheck/VoicegroupSaveTest::newVoicegroupCreatesAndAssignsUndoably` for the full file-creation, catalog, assignment, and undo/redo predicate.
