# Task 253 brief — Sample Studio mounted: Tools → Import Sample, editor window, commit, shell lane

# Context

SA01/SA05: Tools/Import Sample opens the file picker, decodes the chosen source, runs the
editor and commits (no destination slot). `tools.import_sample` is registered in
`KeybindingRegistry.swift:137` but absent from `ShellPresenter.actions`, so no route exists
(plan.md P1: "P4 mounts Import Sample … never mount a dead action"). The fork's Tools menu
held exactly "Import &Sample..." (`mainwindow.cpp` 385–390). This task delivers the first
complete mounted journey: workflow controller, the editor window QML (fork
`SampleEditorDialog` layout; ruling 10 allows brand-new QML for this family), the waveform
item, the Tools route and the `shell-sample-studio` lane. Voice-initiated routes, SoundFont
zones and edit-existing are 254 on the same host.

Fork flow oracle (`git show fceecd88:src/ui/workspaceui_samples.cpp`): `importSample` →
`runImportFlow(nullopt)` (gates: project open, not busy, no dialog open) → probe
(`ProbeSamplesInput`) → `continueImportFlow`: refusal → warning "Import Sample" +
`probe.refusal`; file dialog "Import Sample", start dir setting `lastSampleDir` (home when
unset), filter "Audio files (*.wav *.aif *.aiff *.mp3 *.flac *.ogg *.sf2);;All files (*)";
remember the chosen directory; unreadable → "Cannot read <path>."; decode failure → warning
"Import Sample" "<file>: <error>"; phase-cancelling stereo → question "The left and right
channels of <file> are phase-cancelling — the mono mix may sound hollow.\n\nImport the left
channel only instead?" (Yes re-decodes left-only); editor with `validateNewSampleName`
(`^[a-z0-9_]+$` else "use lowercase letters, digits, and '_'."; catalog symbol exists → "a
sample with that name already exists."); accept → commit (name, WAV bytes, sidecar {absolute
source path, SHA-256 of the source bytes, leftOnly, sf2Zone −1, params}) →
`handleSampleCommitted`: failure → warning "Sample" with the failure; sidecar failure →
status "Sample imported, but saving its edit history failed: <error>"; catalog refresh;
status "Imported <name> - DirectSoundWaveData_<name> is now available to voicegroups".
Editor oracle: `sampleeditordialog.cpp` constructor 175–540 (splitter 204–240, scroll column
241–260, control order, Advanced disclosure 445–506, button box 508–520, Undo/Redo shortcuts
522–527), Space handling 565–598.

Surface: Tools → Import Sample → Sample Editor window → Add to Project (mounted).
Ledger spec and rows (`proof.editor.txt`, after 252's commit; widget lookups retired as in
249; setup rows per the P4 scaffolding rule): editorDrag A037–A046 (NATIVE A040, A042–A046
ported with real pointer drags on the mounted waveform), editorScroll A096–A100 (A099
`QScrollArea` lookup retired; NATIVE A100 ported: at the short window height the control
column's `ScrollView` scrolls), editorSplitter A101–A105 (A104 retired; NATIVE A105 ported:
`SplitView` resize shrinks the waveform), spaceAudition A120 (Play enabled with audio;
lookup conjunct retired in wording), A126–A130 (Space with the name field focused toggles
audition without typing; Space on the key field stops; Ctrl+Space and auto-repeat ignored;
Play text) — each mapped to this task's routing S entry plus 252's PCM S entry.
Verify lanes: `shell-sample-studio`, `shell-sample-studio-refusal` (new), `shell-menus`,
`shell-text-contrast`.
Blocked rows left untouched: visual `proof.dialogs.txt` sample-editor rows (frozen
baselines, standing exclusion). After this task every `proof.editor.txt` row is closed
(249–253): delete the ledger in this commit once `--strict-mappings` lists none of its sites.

# Exact write set

Swift:
- `src/swift/app/samplestudio/SampleStudioWorkflow.swift` — NEW `@QtBridgeable` controller.
- `src/swift/app/ApplicationSession+Samples.swift` — NEW: workflow construction, `sampleStudio()`
  accessor, `closeSampleStudio()`.
- `src/swift/app/ApplicationSession.swift` — one stored property (hot; after 215).
- `src/swift/app/ApplicationSession+ProjectOpening.swift`, `ApplicationSession+Close.swift` —
  one `closeSampleStudio()` call each at the project switch/close points (after 215).
- `src/swift/app/ProjectService+Samples.swift` — add `probeSamples() async -> SampleRegistrar.Probe`.
- `src/swift/app/shell/ShellPresenter.swift` — `Action("tools.import_sample")`,
  `toolsActionIds`, enable (`session.projectOpen` and no Sample Studio open), activate →
  `session.sampleStudio().requestImport(slot: -1)`, label "Import Sample..." (hot).
- `src/swift/app/CMakeLists.txt` — add the two files (hot).
- `tools/qtbridge_surface_baseline.json` — via `deno task bridge:baseline`.

QML:
- `src/ui/shell/samplestudio/SampleStudioHost.qml` — NEW: `FileDialog`
  (`shellImportSamplePicker`), `MessageDialog` alert (`shellSampleStudioAlert`), stereo
  question (`shellSampleStudioStereoPrompt`), Loader for the editor window.
- `src/ui/shell/samplestudio/SampleStudioDialog.qml` — NEW `DialogWindow`.
- `src/ui/shell/samplestudio/SampleWaveform.qml` — NEW: two `DisplayList` items + pointer.
- `src/ui/shell/ShellMenuBar.qml` — "&Tools" menu (`shellToolsMenu`) between View and Help.
- `src/ui/shell/ShellWindow.qml` — one `SampleStudioHost` element beside `SettingsDialog`
  (hot).
- `CMakeLists.txt` (root) — the three QML files in the shell QML block (hot).

Checks/fixtures:
- `src/checks/fixtures/decompproject/Makefile`, `src/checks/fixtures/decompproject/audio_rules.mk`
  — NEW (wav2agb rule, as `writeWav2AgbProject`), declared only by the new entries.
- `src/checks/fixtures/decompproject/samplesources/hires_tone.wav` — NEW binary equal to
  `SampleFixtures.hiResSampleWav()` (throwaway generator, not committed).
- `src/checks/editorqml/tst_ShellSampleStudio.qml` — NEW.
- `src/checks/editorqml/ShellQmlEntries.swift` — `shell-sample-studio` entry (fixtures:
  `songs("mus_route101")` + the two make files + `samplesources/hires_tone.wav`,
  `samplesources/tone.flac`) and `shell-sample-studio-refusal` (input
  `tst_ShellSampleStudioRefusal.qml`; fixtures `songs("mus_route101")` only — no make files,
  so the probe refuses); append the two make files and `samplesources/hires_tone.wav` to
  `textContrastEntries`' `fixtureFiles` (shared with the MIDI track's addition).
- `src/checks/editorqml/tst_ShellSampleStudioRefusal.qml` — NEW (refusal leg).
- `src/checks/editorqml/tst_ShellMenus.qml` — add the Tools menu / "Import Sample..." pins
  and the `menuOrder` entry (lane `shell-menus`; shared with the MIDI and WAV tracks).
- `src/checks/editorqml/tst_TextContrast.qml` — `auditSampleStudio` (shared).
- `src/checks/CMakeLists.txt` — the two new tst files.
- Ledger `proof.editor.txt` rows above.

# Prerequisites

215 (`ApplicationSession.refreshVoicegroupCatalog()`; landed first — shared files), 248
(`ProjectService.commitSample`), 249, 250, 251, 252 (presenter, loop tools, waveform,
audition), 241 (compressed sources for the FLAC leg).

# Interface contract

`@QtBridgeable @MainActor public final class SampleStudioWorkflow` (owned by
`ApplicationSession`, reached from QML via `applicationSession.sampleStudio()`):

- Tracked: `editorOpen`, `editorRevision` (bumps per opened editor), `pickerRequested`
  (QML opens the FileDialog when true), `pickerFolder` (URL string of `lastSampleDir`),
  `alertTitle`, `alertText`, `alertRevision`, `stereoPromptText`, `stereoPromptOpen`.
- QML-callable: `requestImport(slot: Int)` (−1 = Tools; ≥ 0 is 254's destination slot),
  `chooseSource(fileURL: String)`, `cancelSource()`, `answerStereoPrompt(leftOnly: Bool)`,
  `accept()` (Add to Project / Save Sample), `cancel()`; object accessors valid while
  `editorOpen`: `editor()`, `loopTools()`, `waveform()`, `audition()`. Opening an editor
  builds the four objects over one `SampleStudioPresenter` (audition output =
  `ApplicationSession.audio`, nil when audio is unavailable) and wires
  `audition.onPlayhead` to `waveform.setPlayhead(sourceFrame:)`.
- Gates (fork `runImportFlow`): project open with a catalog service, no editor or prompt open,
  no commit in flight; a gated request is silent.
- `accept()`: stops/closes audition, commits via `ProjectService.commitSample`, publishes the
  fork status/alert texts through `ApplicationSession.statusMessage(message:)` and the alert
  properties, then `await refreshVoicegroupCatalog()` (215's single refresh API; its `false`
  already reported the outage — no second message), closes the editor. A thrown commit shows
  the alert "Sample" with the thrown message and keeps nothing open.
- `closeSampleStudio()` (project switch/close, window close via the Loader's teardown):
  closes audition and the editor without committing.
- `lastSampleDir` persists through `PreferencesStore.setString(key:value:)` (canonical
  settings owner).

QML: `SampleStudioDialog` — `DialogWindow` (`src/ui/shell/DialogWindow.qml`, the base Settings uses: native `Qt.Dialog` window with the platform open animation, focus return to `transientParent`, `present()` to open, Escape → `close()` unless `escapeCloses: false`; do not redeclare `flags`, the focus-return handler or an Escape shortcut), `modality:
Qt.ApplicationModal` (fork `exec()`), title from the presenter, initial size 75 × 53.33
`baseFontPx` (fork 900 × 640 at 12 px), minimum 40 × 23.33 `baseFontPx`; vertical
`SplitView` (waveform + seam inset / scrollable control column in fork order: name field +
status, loop checkbox, loop body [seam badge (text color by severity: `windowText`,
`warningText`, `errorText`), Try another loop, Refine, suggest status, loop range, Smooth
seam], Source, Base key + adopt-pitch button, Target rate editable combo (commit on Return,
focus-out or preset), audition strip [Play/Stop, Key, Use destination voice ADSR], output
summary, Advanced disclosure [Format, Crop range, Fine tune, Normalize + gain, technical
detail]); a button row outside the scroll (Cancel, commit label); Undo/Redo shortcuts local
to the window; `Keys`/`Shortcut` Space handling per AGENTS.md "explicit audition surfaces":
unmodified non-auto-repeat Space toggles `audition.toggle()` from any focused control without
typing into it; Ctrl+Space and auto-repeat are ignored; a `Timer` (33 ms) runs
`audition.tick()` while playing. Colors only from `GridPalette` pairs; geometry from
`baseFontPx`/layout spaces. `SampleWaveform` binds `waveform()` display lists 0/1, forwards
press/drag/release, wheel (zoom anchored), double-click (fit) and shows the horizontal
resize cursor over handles via the existing item-cursor path.

# Implementation steps

1. Workflow + ApplicationSession wiring + service probe + ShellPresenter/menu route.
2. QML host, dialog and waveform; register QML files.
3. Fixtures, entries and journeys. `tst_ShellSampleStudioRefusal.qml`: Tools → Import
   Sample on a project with no wav2agb rule shows the fork "cannot find a wav2agb build rule
   …" alert and never opens the picker. `tst_ShellSampleStudio.qml`: Tools item enabled only
   with a project; picker → `hires_tone.wav` → editor title "Sample Editor", source line,
   name prefill `hires_tone`; typing `fixture_loop` disables commit with the fork message;
   drag the loop-start handle to the fork target (±40 samples, one undo entry, undo/redo);
   short-height window scrolls; splitter drag shrinks the waveform; Space routing rows; Add
   to Project → WAV + `.inc` block on disk, status text, `sampleChoices` contains the new
   symbol (215 refresh); Cancel leaves the project untouched; a FLAC source opens with its
   source line.
4. Menus/contrast pins; `deno task bridge:baseline`; ledger edits.

# Acceptance predicate

From the real Tools menu a user picks a source, edits it in the mounted Sample Editor
(handles, scroll, splitter, Space audition) and commits it into the project, which then lists
the new sample; refusals and cancel paths write nothing.

```sh
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-sample-studio --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-menus --verbose
/usr/bin/lockf -t 1800 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task checks:shell --filter shell-text-contrast --verbose
deno task checks:bridge
deno task proof check --executed --strict-mappings
```

`--filter shell-sample-studio` also runs `shell-sample-studio-refusal` (substring match);
`--filter shell-menus` covers `shell-menus`, `shell-menus-commands`, `shell-menus-loop`.
Gap: physical audio (null backend).

# Controller verification

Visual parity (plan.md Global constraints): capture the mounted Sample Editor for
`hires_tone.wav` and the fork's dialog for the same file from the reference build
(`build-asan/porydaw.app` in the main checkout) with the `capture-macos-app-window` skill;
compare control types, order, labels, grouping and relative sizes; record differences.

# Task-specific constraints

Checks drive only production ingress (menu, FileDialog `selectedFile` + `accept()`, pointer
and key events); no test-only properties or reads. Space never leaks to window shortcuts
while the editor window is active, and bare Space elsewhere in the app is unchanged.
`ShellPresenter.swift` is above 600 lines: add only the table/case lines, no refactor.
