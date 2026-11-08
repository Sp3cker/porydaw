# Context
The production QML panel for live MIDI-effect inserts, bound to spec.md "MidiEffectsPresenter". The panel only picks and configures the plugin: plugin list, Rescan/Cancel Scan, Add Folder/folder rows, Retry, Open Editor, Input, Pacing, Pre-roll, Remove, Close, and the "Plugin unavailable: <reason>" status. Live, Render, Cancel Render, Grab played and their statuses live in the Effect Output section header (task 12). The presenter is task 10; this task writes against the spec's frozen names, and integration waits on it. Read plan.md Global Constraints, spec.md "MidiEffectsPresenter" and "MidiEffectsPanel.qml", rule://text-contrast and rule://qtbridge-surface. Panel shows Live inserts, not the old bake/bypass/solo/range model: no Bake, Bypass, Solo audition, bar-snap or range controls.

# Exact write set
- src/ui/songview/quick/MidiEffectsPanel.qml (new; no MidiEffects QML exists today)
- src/ui/songview/quick/swiftroll/EditorSurface.qml: `midiEffectsModel` bound to `applicationSession ? applicationSession.midiEffectsPresenter() : null`, mirroring `arpeggiatorModel` (`EditorSurface.qml:36`); `configure(baseFontPx)` beside the arpeggiator's (`:163-164`); `midiEffectsModel && midiEffectsModel.isOpen` joins `hintScopeCovered` (`:76-81`)
- src/ui/songview/quick/swiftroll/EditorSurfacePrompts.qml: mount `MidiEffectsPanel` beside `ArpeggiatorPanel` (`:33-48`), same visibility/focus contract, `z` below the arpeggiator loader's 15
- src/checks/editorqml/ShellQmlTests.swift: bootstrap property `vstFixtureFolder: String`, the `vstfixtures` directory beside the running executable; bootstrap method `injectPluginFault(track: Int, mode: Int)` delegates through `PluginFaultInjector`, restoring fixture fault state without changing document state.
- src/checks/editorqml/PluginFaultInjector.swift (new): one internal checks-support module owns fixture encoding, typed error normalization, injection/stimulus tasks and their joins, and committed-failure validation. Preserve the current two fault modes and diagnostics; do not add a production test mode or a second observer.
- src/ui/songview/quick/PromptAction.qml (new): one shared Enter/Return, pointer and accessibility action, with typed `PromptStyle` appearance and ordinary button semantics; bare Space remains unclaimed. Both the setup panel and task 12's output page consume this module. Each surface retains its own scrolling and toggle semantics; do not extract the arpeggiator's distinct radio/checkbox selectors.
- `src/swift/app/ApplicationSession.swift`: one internal, explicitly typed MainActor catalog-construction factory for parameterless QML creation. Production defaults remain unchanged and each session owns its immutable catalog. `ShellQmlLane.run` scopes and restores that factory to create real catalogs with fixture-only roots and unique caches under its private scratch; no host-installed plug-ins or user cache enter the gate.
- src/checks/editorqml/tst_ShellMidiEffects.qml (new)

Registration (controller): `qt_add_qml_module` QML_FILES includes the panel and `PromptAction`; the existing shell target's SWIFT_SOURCES includes `PluginFaultInjector.swift`. A `ShellQmlEntries` entry `shell-midieffects` → `tst_ShellMidiEffects.qml` uses `songs("mus_route101")`; existing `add_porydaw_check` fixture dependencies and shared output directory supply the bundles beside the shell executable. Link canonical `swift_core_check_support`; that target exports its native C module-map/include usage requirements rather than each consumer duplicating them. `tst_TextContrast.qml` gains `auditMidiEffects(context)` beside `auditArpeggiator`. The controller is the only writer of that contrast file across tasks 11–12.

# Prerequisites
Task 10 (the `MidiEffectsPresenter` interface, frozen in spec.md: properties, slots, status strings, objectNames, menu action 7). The panel may be drafted alongside task 10; integration and checks run after it.

# Interface contract
Exactly spec.md "MidiEffectsPresenter".
- **Layout.** A modal panel like `ArpeggiatorPanel` (same `PromptStyle`/`GridPalette` pairs, `bodyFont`, font-derived geometry, deferred initial focus; `ArpeggiatorPanel.qml:9-25` is the pattern), top to bottom:
  - header: `trackLabel`, Close;
  - plugin list with Rescan/Cancel Scan and Add Folder (a `FolderDialog` like `SampleLibraryPane`'s, `objectName: "midiEffectsFolderPicker"`); folder rows with remove; skipped rows visibly distinct with Retry (`retryBlocked`); empty-list text "No MIDI-producing VST3 plugins found. Add a folder or Rescan.";
  - controls row: Open Editor, Input (None/Track notes), Pacing (Offline/Realtime), Pre-roll (0/1/2 bars);
  - status line: "Plugin unavailable: <reason>", or after a helper crash or hang "<name> stopped working." / "<name> stopped responding." with a **Reload Plug-in** button (`midiEffectsReload`, calling the presenter's reload slot);
  - footer: Remove, Close.
- **objectNames** exactly as spec.md: `midiEffectsPanel`, `midiEffectsPluginList`, `midiEffectsRescan`, `midiEffectsCancelScan`, `midiEffectsAddFolder`, `midiEffectsFolderPicker`, `midiEffectsOpenEditor`, `midiEffectsInput`, `midiEffectsPacing`, `midiEffectsPreroll`, `midiEffectsReload`, `midiEffectsRemove`, `midiEffectsClose`.
- **Enabled states** follow `hasEffect`, `canOpenEditor`, `isScanning`, `isLoading` and the presenter's crashed state (Reload visible only while crashed; Open Editor disabled while crashed). No Bake/Bypass/Solo/range UI, no Live/Render/Grab controls.
- **Settings** go only through slots, never property writes.
- **Keyboard.** Enter/Return and pointer activate controls. No control claims bare Space: Space plays the song (and from the plugin editor window too, per D6).

# Implementation steps
1. Adapt `ArpeggiatorPanel`'s modal layout and existing `PromptStyle`, not its distinct selector interaction model. Reuse `PromptAction` for Enter/Return-only actions rather than duplicating the keyboard, accessibility, focus-chrome and pointer protocol in the two new surfaces. Keep page-specific focus-reveal policy local; preserve all existing focus/scroll behavior.
2. Mount and bind it, and add it to `hintScopeCovered`.
3. Add the bootstrap property.
4. `tst_ShellMidiEffects.qml` on `mus_route101` covers panel setup only (arpeggiator shell pattern `tst_ShellArpeggiator.qml:1-63`):
   - open from the track header (action 7, `headerMenuRow_7`);
   - add `bootstrap.vstFixtureFolder` and see only the MIDI producers listed (`TestAudioOnly` absent);
   - selecting a plugin adds the effect and the header shows the plugin badge;
   - Open Editor; geometry stays inside the shell at 640 px height, as the arpeggiator check does;
   - crash: `bootstrap.injectPluginFault(track:mode: 1)` (this task's bootstrap method) makes the helper abort; the panel shows "<name> stopped working." and `midiEffectsReload`, the header badge shows "Stopped", and the shell is still running; Reload clears the status and restores the badge;
   - Remove closes the panel.
5. Add the contrast audit.

# Acceptance predicate
NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks:shell --filter shell-midieffects`
- `uv run --no-sync dev checks:shell --filter shell-text-contrast`
- `uv run --no-sync dev checks:qml-aot`
- `uv run --no-sync dev checks:bridge`

Coverage gap: opening the plugin editor is excluded from the shell lane because the editor is a native window. Task 10's checks and the final native smoke cover it.

# Task-specific constraints
- No Swift presenter edits (task 10).
- No hard-coded pixel constants.
- Versionless Qt imports; `Connections { function onX() {} }`; `required property` in delegates.
