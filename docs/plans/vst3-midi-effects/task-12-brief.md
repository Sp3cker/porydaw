# Context
The session-only Effect Output drawer section (plan D7): the selected track's effect output as note rectangles on the roll camera, with note selection and Copy onto the existing `PorydawClip` clipboard. Consumers: none; the normal roll paste (task: existing grid executor) receives the clip. Read plan.md Global Constraints, spec.md "Effect Output drawer section", rule://text-contrast and rule://qtbridge-surface.

# Exact write set

- src/swift/app/drawer/effectoutput/EffectOutputPage.swift (new: page presenter, publication, selection, commands; one file — no gesture/modal seams, so no split)
- src/ui/songview/quick/drawer/EffectOutputPage.qml (new)
- src/swift/document/view/EditorDrawerTypes.swift: `effectOutput = 3`; stack/toggle order place it last; `name`, `keyName`, `toggleSlot` gain the fourth case (`:7-43`)
- src/swift/app/drawer/EditorDrawer.swift: `effectOutputSection` state, `section(kind:)` case (`:103-125`), `chromeState`/`toggleSection`/`setSectionVisible` cases (`:144-203`)
- src/swift/app/drawer/EditorDrawerLayout.swift: fourth `KindValues` entry (`:21-24`); `restorePreferences` gains the effect-output visible/height pair (`:148-162`)
- src/swift/app/DocumentWorkspace.swift: create the page beside the automation page (`:143-151`), pass it to `drawer.attachSections` (`:264-267`), and connect `EffectOutputPage.onAddEffectRequested` to `midiEffects.open(track:)` for the selected track
- src/ui/songview/quick/drawer/EditorDrawer.qml: kind/index/key/icon/loader cases (`:29-70`) and a fourth `DrawerSection` instance after the automation one (`:353-375`); `activateFromPointer` counts the new section's visibility with the other three
- src/swift/app/EditorCommandRouter.swift: route `roll.copy` / `roll.select_all` to the page (see contract); construction site in the same file (`ApplicationSession.commandRouter`)
- src/checks/editorqml/tst_EditorDrawerEffectOutput.qml (new)
- `src/checks/editorqml/tst_ShellEffectOutput.qml` (new)

Registration (controller): `suiteSelectors` entry in `src/checks/editorqml/EditorQmlTests.swift` mapping the drawer file to its test functions (auto-discovery alone, `drawerSuites`, is not enough); a `ShellQmlEntries` entry `shell-effect-output` → `tst_ShellEffectOutput.qml` with `songs("mus_route101")` (arpeggiator precedent `ShellQmlEntries.swift:66-68`); `PorydawQmlTypes` / `qt_add_qml_module` file lists; `bridge:baseline` for the new bridged page.

# Prerequisites
Task 9 (`EffectOutputStore` + `EffectOutput`/`EffectOutputOrigin`, `TrackEffectsController.grabPlayed`/`render`, crash state and Reload, per-effect entries keyed by `EffectID`, cleared on removal/teardown). This task consumes that store and controller interface, plus the existing `DocumentViewport.camera`, `DocumentSession` and `GridClipboard`. Task 10 lands first (checkpoint C) because both edit `DocumentWorkspace.swift`; the shell check also requires task 11's `bootstrap.injectPluginFault(track:mode:)`.

# Interface contract
Exactly spec.md "Effect Output drawer section", plus the following (the spec leaves these open):
- **Kind and registration.** `DrawerSectionKind.effectOutput = 3` (automation 0, velocity 1, voiceChanges 2). Stack and toggle order place it last. Page presenter `EffectOutputPage: EditorDrawerPage` with `contentUrl` pointing at `EffectOutputPage.qml`, a `bodyPolicy` with the section minimum and no page maximum. `DocumentWorkspace` creates it with `baseFontPx`, attaches `viewport` + `grid.palette` like the sibling pages, passes it to `attachSections`, and connects `EffectOutputPage.onAddEffectRequested` to `midiEffects.open(track:)` for the selected track.
- **Section header controls.** The header carries a Live toggle, Render, Cancel Render with a determinate progress bar, Grab played, Open Editor, Copy and Clear for the selected track's effect, all driven through `TrackEffectsController`. On crash show `Reload Plug-in` (`effectOutputReload`), invoking the controller's manual Reload. Status and diagnostics lines live here. Status strings (exact): "Live — play the song; the plugin drives this track.", "Stop playback to render", "Rendering in real time (about N s)", "Rendered N notes.", "Grabbed N played notes.", "Nothing heard yet — play with Live on, then grab.", "No notes captured — try Realtime pacing.", "No source notes in range.", "Plugin unavailable: <reason>", "<name> stopped working." for unexpected exit, "<name> stopped responding." for a hang, plus the `NormalizationReport` diagnostics line. objectNames: `effectOutputLive`, `effectOutputRender`, `effectOutputCancelRender`, `effectOutputGrabPlayed`, `effectOutputOpenEditor`, `effectOutputCopy`, `effectOutputClear`, `effectOutputAddEffect`, `effectOutputReload`.
- **Publication.** The page publishes the selected track's store notes as note rectangles in viewport space: `viewport.camera.snapshot` positions them (the automation/velocity precedent: `AutomationContentPublication.swift`, `VelocityPublication.swift:refreshCamera` rebuilds viewport-space lists on every camera move). Pitch axis auto-fits the output's pitch span; a range band marks the store's `range`. Republish on store change, track switch and camera move. Geometry from the font-derived layout; colors from `GridPalette` pairs only.
- **Empty states** (exact): "No MIDI effect on this track" plus an "Add MIDI Effect..." button (`effectOutputAddEffect`) opening the panel for the selected track / "Render or grab played to see output here" (effect with no stored output).
- **Origin label** (exact): "Rendered" / "Played", plus "some notes were dropped" when `degraded`.
- **Selection.** Click, shift-click, box drag select output notes (page-held selection, never in the document). `selectAll` selects all stored notes. No selection copies everything.
- **Copy route — no second dispatcher.** The QML Copy button calls `page.copyOutput()` directly. The `roll.copy` (window scope) and `roll.select_all` (editor-routed) keybindings (`KeybindingRegistry.swift:156,162`) go through the existing `EditorCommandRouter`, the way the automation section's commands do: `isAvailable` consults `page.selectionCommandAvailable(command:)` and `perform` calls `page.consumeSelectionCommand(command:)` (`EditorCommandRouter.swift:47-52,86-93`; precedent `AutomationSelectionCommands.swift:12-66`). Ownership is keyboard focus: the Effect Output page owns `.copy` and `.selectAll` only while its section body holds active focus (`EffectOutputPage.qml` writes `page.bodyFocused` from the body's `activeFocus`; a press in the section takes focus like the other sections, `EditorDrawer.qml:98-118`) and no time selection is active. An active time selection keeps the automation route, and roll focus keeps the roll's note commands, so selected roll notes are never shadowed by an output selection. Paste is untouched: the normal roll paste at the edit cursor.
- **Copy semantics.** `copyOutput` writes a zero-span `PorydawClip` through `ClipboardSemantics.copyNotes` + `GridClipboard` (`Clipboard.swift:252-269`; roll precedent `NoteCommands.swift:121-127`). The source track is the selected track.
- **Clear.** `clearOutput()` empties the selected track effect's store entry (notes + selection). Session-only, no undo. (Spec names the action only; this is the decided meaning.)
- **QML surface.** `EffectOutputPage.qml` follows the `AutomationPage.qml:1-56` pattern (model from `applicationSession`, `GridPalette` from the grid, `pushBodyFacts`/`configureBody`, Escape only for an active gesture, modal layer + hint bindings from the `DrawerSection` loader). Its model is the `EffectOutputPage`.

# Implementation steps

1. Add the kind: case, orders, `name`/`keyName`/`toggleSlot`, layout section, chrome state + restore pair, QML switches + instance, workspace creation + attach + the `onAddEffectRequested` connection. An unattached kind contributes no height/handle/toggle/body (existing `isAvailable` rule); verify the drawer with no effect open is unchanged.
2. Page + publication + header controls: store notes → viewport-space rectangles, pitch auto-fit, range band, origin/degraded label, the two empty states, and the header Live/Render/Cancel/Grab/Open Editor/Copy/Clear/Reload driven through `TrackEffectsController` with the exact status strings. Republish on store/track/camera change without touching the document.
3. Selection + commands: pointer selection, Select All, Copy (button + router route with the precedence above), Clear. Copy with no selection copies all stored notes; Clear empties the entry.
4. `tst_EditorDrawerEffectOutput.qml` in the drawer lane pattern (`EditorQmlTests.swift:16-19`, file auto-discovered per `:169-173`): with a staged effect output, section mounts last with the roll-camera alignment; empty states show the exact strings; click/shift-click/box/select-all then Copy writes a zero-span clip that the normal roll paste inserts; Clear empties the pane; origin label flips Rendered/Played.
5. `tst_ShellEffectOutput.qml` on `mus_route101` (new `shell-effect-output` entry, registered by the controller in `ShellQmlEntries.swift`): with an effect added, the section header Live toggle arms (the header shows "Live"); Space plays; Render shows "Rendered N notes." and the notes appear; Grab after playing shows "Grabbed N played notes."; select + Copy + roll paste inserts notes, and Undo works; Clear empties; "Add MIDI Effect..." opens the panel when the track has no effect. With the real fixture helper armed, call `bootstrap.injectPluginFault(track, 1)` and assert audio and other tracks continue, the section shows "<name> stopped working.", the header says "Stopped", and `effectOutputReload` restores the last recorded state and re-arms. Repeat with mode 2 and "<name> stopped responding."; reload remains manual.
6. Contrast: every text in the section meets WCAG AA against its `GridPalette` pair.

# Acceptance predicate
NAMED CHECKS (controller):
- `uv run --no-sync dev build:checks`
- `uv run --no-sync dev checks:qml --filter editorqml-drawer`
- `uv run --no-sync dev checks:shell --filter shell-effect-output`
- `uv run --no-sync dev checks:shell --filter shell-text-contrast`
- `uv run --no-sync dev checks:bridge`

# Task-specific constraints
- Output is session-only: never in the document, never persisted, lost on close (D7/D1). No edits to `SongDocument`, Sequencer, export or backup paths.
- No second command dispatcher: `EditorCommandRouter` is the only key route.
- Escape cancels only an active box-drag; bare Space stays with transport.
