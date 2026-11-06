# Context
The production QML panel for live MIDI-effect inserts, bound to spec.md "MidiEffectsPresenter". The panel only picks and configures the plugin: plugin list, Rescan/Cancel Scan, Add Folder/folder rows, Retry, Open Editor, Input, Pacing, Pre-roll, Remove, Close, and the "Plugin unavailable: <reason>" status. Live, Render, Cancel Render, Grab played and their statuses live in the Effect Output section header (task 12). The presenter is task 10; this task writes against the spec's frozen names, and integration waits on it. Read plan.md Global Constraints, spec.md "MidiEffectsPresenter" and "MidiEffectsPanel.qml", rule://text-contrast and rule://qtbridge-surface. Panel shows Live inserts, not the old bake/bypass/solo/range model: no Bake, Bypass, Solo audition, bar-snap or range controls.

# Exact write set
- src/ui/songview/quick/MidiEffectsPanel.qml (new; no MidiEffects QML exists today)
- src/ui/songview/quick/swiftroll/EditorSurface.qml: `midiEffectsModel` bound to `applicationSession ? applicationSession.midiEffectsPresenter() : null`, mirroring `arpeggiatorModel` (`EditorSurface.qml:36`); `configure(baseFontPx)` beside the arpeggiator's (`:163-164`); `midiEffectsModel && midiEffectsModel.isOpen` joins `hintScopeCovered` (`:76-81`)
- src/ui/songview/quick/swiftroll/EditorSurfacePrompts.qml: mount `MidiEffectsPanel` beside `ArpeggiatorPanel` (`:33-48`), same visibility/focus contract, `z` below the arpeggiator loader's 15
- src/checks/editorqml/ShellQmlTests.swift: bootstrap property `vstFixtureFolder: String`, the `vstfixtures` directory beside the running executable; bootstrap method `injectPluginFault(track: Int, mode: Int)`, which restores the fixture fault state into the track effect's live instance through task 9's internal `TrackEffectsController.instance(for:)` (`@testable import`), changing no document state
- src/checks/editorqml/tst_ShellMidiEffects.qml (new)
- src/checks/editorqml/tst_TextContrast.qml: `auditMidiEffects(context)`, modeled on `auditArpeggiator`, called next to it

Registration (controller): `qt_add_qml_module` QML_FILES; a `ShellQmlEntries` entry `shell-midieffects` → `tst_ShellMidiEffects.qml` with `songs("mus_route101")` (arpeggiator precedent `ShellQmlEntries.swift:66-68`); the fixture bundle copied beside the shell check executable.

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
1. Build the panel by adapting `ArpeggiatorPanel`'s card, footer and selector patterns. Do not create a second style system.
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
