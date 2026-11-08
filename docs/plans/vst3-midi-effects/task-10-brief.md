# Context
`MidiEffectsPresenter` is the panel model over one track's plugin effect: select/add/replace, input/pacing/preroll, editor open/close, catalog folders, unavailable and crash status, and manual Reload. It also owns the header menu row 7 and the track-header plugin badge with its Live/Stopped caption, and routes play/pause from a focused plugin editor window to `ShellPresenter.activate`. Live, Render and Grab played live in the Effect Output section (task 12) through `TrackEffectsController`; this presenter never arms, renders or grabs. Consumer: task 11 (QML panel binds this presenter, including `midiEffectsReload`). Read plan.md Global Constraints and spec.md "MidiEffectsPresenter" and "Space and transport".

# Exact write set
- `src/swift/app/miditools/MidiEffectsPresenter.swift` (new; presenter plus `MidiEffectPluginRow`)
- `src/swift/app/headers/TrackHeaders.swift` (action 7 "MIDI Effects...", `onMidiEffectsRequested: ((Int) -> Void)?`, cleared with the other callbacks at `:161-164`; `activateHeaderMenuAction` gains case 7; menu labels at `:530-538` gain the row)
- `src/swift/app/DocumentWorkspace.swift` (own `midiEffects`; header callback wiring; `midiEffects.documentChanged()` on `.document` or `.effects`; close on `.bank`, suspension, deactivation; presenter drives `effects`. Effect-only history/state changes do not rebuild the MIDI playback timeline.)
- `src/swift/app/ApplicationSession.swift` + `src/swift/app/ApplicationSession+Tabs.swift` (reuse task 9's sole app-wide `PluginCatalog` and workspace injection; add `midiEffectsPresenter()` and presenter refresh to the session-owned catalog fan-out. Do not recreate the catalog or replace its callback. The tab-close `effects.shutdown()` ordering stays as it landed)
- `src/swift/app/SongTabsController.swift:91` (`SongTabSession.midiEffectsPresenter()`, mirroring `arpeggiatorPresenter()`)
- `src/swift/app/shell/ShellPresenter.swift:169` (once constructed: pass single-stroke `KeybindingRegistry().sequences("transport.play_pause")` strokes to `PluginEditorShortcuts`; handler is `[weak self] in self?.activate(id: "transport.play_pause")`; plugin views never receive those keystrokes)
- `src/swift/app/headers/TrackHeadersGeometry.swift` (row build at `:295-302`: `row.effectName` from the track effect's `config.plugin.name`, `row.liveArmed` from `effects.isLive`, `row.effectStopped` from its crash state) + `TrackHeaderSnapshot` fields `effectName: String` and `effectStopped: Bool` (`:27-43`)
- `src/swift/app/headers/TrackHeaders.swift` row handle (`:566-616`): `effectName`, `liveArmed` and `effectStopped` published like `muteChecked`
- `src/ui/songview/quick/swiftroll/TrackHeaderRows.qml` (`required property string effectName`, `required property bool liveArmed` and `required property bool effectStopped`; a badge in the subtitle font showing `effectName` elided to the available width, visible only when non-empty, plus `qsTr("Live")` while armed and `qsTr("Stopped")` instead when crashed)
- `src/checks/trackheaders/trackheadermenu.swift:18,234` (update: rows `[1…7]`, fresh-menu count 7)
- `src/checks/miditools/MidiEffectsPresenterChecks.swift` (new; `@MainActor func runMidiEffectsPresenterChecks(_ report: CheckReport, session: DocumentSession, service: ProjectService)`, called from `runProjectSessionSuite` in `src/checks/workspace/SessionChecks.swift:123-125` beside the track-header checks)

Registration (controller): new sources into `src/swift/app/CMakeLists.txt` and `src/checks/CMakeLists.txt`; the `runMidiEffectsPresenterChecks` call in `src/checks/workspace/SessionChecks.swift:123-125`; `PorydawQmlTypes.swift` uncreatable registration + `QmlUncreatable` conformance; `bridge:baseline`.

# Prerequisites
Task 8 (helper editor windows and `PluginEditorShortcuts` interception) and task 9 (controller: instances, crash state and Reload, `isLive`/`setLive`, `render`, `cancelRender`, `grabPlayed`, store, lifecycle ordering; the presenter reads effect/Live state and invokes Reload but never arms, renders or grabs).

# Interface contract
Exactly spec.md "MidiEffectsPresenter", plus:
- `selectPlugin` adds or replaces (`addEffect(replacing:)`, one undo step) with default settings; settings writes use one `HistoryGroup` per panel session.
- Status strings verbatim: "Plugin unavailable: <reason>", "<name> stopped working." for unexpected exit, "<name> stopped responding." for a hang. Expose `canReload` and `reloadPlugin()` for the panel button `midiEffectsReload`, visible on crash and routed to the controller. Empty-list text verbatim: "No MIDI-producing VST3 plugins found. Add a folder or Rescan." The panel list shows only MIDI producers plus blocked entries; `TestAudioOnly` never appears. Diagnostics: one line of the non-zero `NormalizationReport` counters.
- Header badge: the header row shows `config.plugin.name` elided to the available width, plus "Live" while armed or "Stopped" instead when crashed. `effectName: String` (empty = no effect; assigned from the config, never formatted per frame), `liveArmed: Bool` and `effectStopped: Bool` are published like `muteChecked`. Badge ink/background: a header-appearance pair from `GridPalette` meeting WCAG AA; captions use a distinct pair (`liveMarkerBackground`/`liveMarkerText`, or reuse an existing pair) that also meets AA.
- Editor and closing: `openEditor()` while open raises the window. The panel closes on `.bank`, suspension, deactivation, teardown, after Remove, and when its effect disappears. Closing the panel alone keeps the editor and Live; suspension, deactivation and removal follow task 9's lifecycle.
- Folders: `PreferencesStore` key `vst3PluginFolders` using the `SampleLibraryModel` pattern (`src/swift/sampleui/SampleLibraryModel.swift:85-90,122-132`: static key, injected `PreferencesStore`, normalize/persist roots).
- Accessor: `midiEffectsPresenter()` on `SongTabSession`/`ApplicationSession`; `EditorSurface.qml` binds it as `midiEffectsModel`; `hintScopeCovered` includes it (QML wiring itself is task 11).

# Implementation steps
1. Build the presenter: open/close per track, plugin list rows (`name`, `vendor`, `detail`, `blocked`; MIDI producers plus blocked entries only), select/replace, settings with one `HistoryGroup` per session, Remove with panel close.
2. Surface the "Plugin unavailable: <reason>" status and diagnostics; `open(track:)` triggers `scan(folders:force: false)`, `rescan()` triggers `force: true`.
3. Wire folders (add/remove/persist), rescan/cancel, `retryBlocked`, `isLoading`/`isScanning` states.
4. Wire editor open/close plus the Space routing through `ShellPresenter.activate(id: "transport.play_pause")`.
5. Wire header menu action 7 after "Arpeggiator...", workspace ownership and callbacks, `documentChanged` closing.
6. Add the plugin-name header badge plus the "Live" caption for the armed track and "Stopped" in its place when crashed; selecting adds the effect and the header shows the badge. Publish crash status and Reload to the panel.
7. Checks (see Acceptance).

# Acceptance predicate
NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks --filter swiftcore-projectsession`: track-header menu (`runProjectSessionSuite` runs `trackheadermenu.swift`): `headerMenuOpensWithTypedRowsAndDismissesWithoutWrite` now expects rows `[1…7]`; `headerMenuStaleStructuralChangeCancelsWithoutWrite` expects count 7; dismiss still writes nothing. The badge shows `effectName` on select; `liveArmed` follows the controller on arm/disarm; `.crashed` shows "Stopped" instead of "Live" and successful Reload restores the appropriate caption.
- `uv run --no-sync dev checks:qml --filter editorqml-drawer`: header rows regression (`tst_EditorDrawerHeaders.qml`), including badge and "Live"/"Stopped" caption ink audit.
- `uv run --no-sync dev checks --filter swiftcore-projectsession`, presenter suite — select adds effect (one undo) and the header badge follows; `TestAudioOnly` never listed; settings session reverts in one undo; editor open/close; folders persist via `vst3PluginFolders`; `PluginEditorShortcuts` handler routes through `ShellPresenter.activate("transport.play_pause")`; panel closes on Remove and on effect disappearance; panel close keeps the editor and Live. Crash and hang publish the exact panel statuses, expose Reload only when crashed and invoke the controller's manual Reload.
- `uv run --no-sync dev checks:bridge`

# Task-specific constraints
- Presenter and renderer never call `pdph_*` directly; through PorydawPluginHost only.
- Exact spec status strings; no invented copy. No product names or links.
- No audio-engine edits. Arpeggiator behavior unchanged.
- QML-facing members in the class body (rule://qtbridge-surface); geometry from the base font, never hard-coded pixels; persistent chrome never claims bare Space.
