# Task 222 brief — File → Export WAV: options dialog, save picker, app-modal render with progress and Cancel

# Context

This is draft P3-T4, the only user-visible mount of P3. It consumes 220
(`WavExportOptions`, `WavExportTotals.previewSeconds`/`clockText`,
`WavExportError.message`) and 221 (`DocumentSession.wavExportCapture`,
`NativeAudio.songSettings(for:)`, `WavExportJob.run`, `WavExportOutcome`).

Fork counterpart, `fceecd88:src/mainwindow.cpp`, the visual and behavioral reference:
- Menu row and enablement: `Export &WAV...`, between two separators after Close Tab
  and before Quit (`:312-316`, full File menu `:289-319`). Enabled when
  `ready && m_audioOk && m_audio.songLoaded()` (`:964`).
- `exportWav` (`:1188-1328`):
  - Guard `:1190-1192`.
  - `QDialog` "Export WAV" with a `QFormLayout`:
    - "Sample rate:" combo, 32000/44100/48000 Hz, index 2 (`:1203-1207`).
    - Looping songs: "Loop count:" spin 1–99, default 2 (`:1213-1216`), and
      "Fadeout:" double spin 0–60, 1 decimal, default 5.0, suffix " s"
      (`:1217-1222`).
    - Non-looping songs: "Tail (no loop markers):" 0–60, default 3.0 (`:1224-1229`).
    - "Duration:" label, live m:ss (`:1232-1271`).
    - Ok/Cancel (`:1273-1278`).
  - Save picker titled "Export WAV", filter "WAV files (*.wav)". Start
    `lastWavExportDir`, falling back to the song's MIDI directory, with suggested
    name `<label>.wav` (`:1281-1290`). The picker stores the chosen directory
    (`:1291`).
  - `stopPlayback()` only after the path is accepted (`:1293`).
  - `QProgressDialog` "Rendering <label>...", Cancel, 0–1000, modal (`:1295-1298`).
  - Render with suppression read at accept (`:1238`, `:1303-1311`).
  - Error → warning box titled "Export WAV" (`:1315`). Cancel → status
    "Export cancelled." (`:1317`). Success → "Exported <path> (m:ss @ <rate> Hz)"
    with truncated seconds (`:1320-1327`).
  - QDialog/QFileDialog `exec()` and the modal progress block the app. User ruling
    of 2026-09-29: export is modal to the whole application. No input until done or
    cancelled; Cancel is the only exit.

Registry comparison (plan.md P1 note):
- `KeybindingRegistry.swift:106-114` defines `file.import_midi` and
  `file.export_wav`. `ShellPresenter.actions` mounts neither.
- This task mounts `file.export_wav` only. `file.import_midi` stays P2 (its planner
  was notified of the File-menu grouping below).
- No other fork File row is unmounted. Import Sample is a Tools row
  (`mainwindow.cpp:386`), P4.

Delivery evidence (r22 landed notes, `repairs/r22-command-authority.md`):
declarative `Connections` targeting a presenter returned from an `ApplicationSession`
slot proved undeliverable under QtBridge. So the QML reacts to presenter state
through **bindings plus item-local change handlers**, never `Connections` or
presenter signals.

- Surface: File → Export WAV (menu row, options window, save picker, progress window,
  error box, status feedback).
- Spec ledger: none. No open ledger row pins the dialog. midiexport closed in 220.
  Retained A015/A016 stay under the standing native-boundary exclusion.
- Verify lanes: new `shell-export-options` and `shell-export-render`, plus
  `shell-menus`, the three `shell-text-contrast-song-*` entries and `shellwindow`.

# Exact write set

Production:
- `src/swift/app/export/WavExportPresenter.swift` (new, `PorydawApp`, beside 221's
  job).
- `src/swift/app/ApplicationSession.swift`:
  - stored `@QtIgnored let wavExport = WavExportPresenter()`;
  - slot `public func wavExportPresenter() -> WavExportPresenter`, next to
    `transportBarPresenter()` (`:347`);
  - `wavExport.attach(session: self)` at the end of `init`.
  (**hot shared**)
- `src/swift/app/shell/ShellPresenter.swift`: action row, File groups, label,
  enable/activate, modal gate, close refusal (**hot shared**). It is already 620
  lines; net growth ≤ 12 lines, and no split in this task.
- `src/swift/app/CMakeLists.txt`: add `export/WavExportPresenter.swift` to
  `PorydawApp` (**shared** 220/221).
- `src/ui/shell/WavExportSurface.qml` (new): one composition with the options
  window, save picker, progress window and error box.
- `src/ui/shell/ShellWindow.qml`: mount `WavExportSurface` (**hot shared**).
- `src/ui/shell/ShellMenuBar.qml`: File groups and separators (**menu registry, hot
  shared**).
- `CMakeLists.txt`: add `src/ui/shell/WavExportSurface.qml` to `porydaw_app`
  `QML_FILES` (**hot shared**).
- `docsrc/manual/export-audio.md`: replace both TODO comments with the shipped
  behavior.

Checks:
- `src/checks/editorqml/tst_ShellExport.qml` (new, `TestCase { name: "ShellExport" }`).
- `src/checks/editorqml/WavFileProbe.swift` (new check-side decoder, module
  `ShellQmlCheck`).
- `src/checks/editorqml/ShellQmlTests.swift`: `WavFileProbe.registerQmlElement()`
  beside the other probes (`:70-73`).
- `src/checks/editorqml/ShellQmlEntries.swift`: two entries (**registration, hot
  shared**).
- `src/checks/CMakeLists.txt`: add `editorqml/WavFileProbe.swift` to `shell_qml_lane`
  (`:532-541`) (**hot shared**). Like `tst_ShellSongs.qml`/`tst_ShellMenus.qml`, the
  new tst file needs no `add_executable` listing.
- `src/checks/editorqml/tst_ShellMenus.qml`: only the File-menu pin at `:88-89`.
- `src/checks/editorqml/tst_TextContrast.qml`: `auditWavExport(context)`, called from
  `test_songShellText` after `auditSettings`.

Ledgers: none.

# Prerequisites

Tasks 220 and 221 accepted and checkpointed. This task shares
`src/swift/app/CMakeLists.txt` with them. Serialize against the other tracks'
writers of the flagged hot files; see the sprint-4 conflict matrix.

# Interface contract

## `WavExportPresenter`

`@MainActor @QtBridgeable public final class WavExportPresenter`, declared like
`TransportBarPresenter`: a plain bridged class holding
`private weak var session: ApplicationSession?`.

QML-facing stored members (class body):

| Member | Values |
|---|---|
| `active: Bool` | true from `open()` until options reject, picker reject or outcome handled |
| `optionsVisible: Bool` | |
| `choosingFile: Bool` | |
| `rendering: Bool` | |
| `hasLoop: Bool` | |
| `rateLabels: [String]` | `["32000 Hz","44100 Hz","48000 Hz"]` |
| `rateIndex: Int` | default 2 |
| `loopCount: Int` | default 2 |
| `fadeTenths: Int` | 0…600, default 50 |
| `tailTenths: Int` | 0…600, default 30 |
| `durationText: String` | |
| `startFolder: String` | file URL |
| `suggestedFile: String` | file URL |
| `progress: Int` | 0…1000 |
| `renderText: String` | |
| `failureMessage: String` | |
| `failureRevision: Int` | |

Swift-only:
- `func attach(session:)`.
- `@QtIgnored var exportAvailable: Bool`: `session.songOpen` and
  `session.audio?.songLoaded == true` (fork `:964`).

Slots:
- `open()`: no-op unless `exportAvailable`.
  - Resets the defaults and reads `hasLoop` from `selectedDocument.timeline`.
  - Sets `durationText` through `WavExportTotals.clockText(seconds: previewSeconds(timeline:options:))`.
  - Sets `active`/`optionsVisible`.
- `setRateIndex(index:)`, `setLoopCount(count:)`, `setFadeTenths(tenths:)`,
  `setTailTenths(tenths:)`: clamp to the fork ranges and recompute `durationText`.
- `acceptOptions()`:
  - `startFolder` = `PreferencesStore().string(key: "lastWavExportDir", fallback: <midi dir>)`.
    `<midi dir>` is the parent of `document.source.midiPath` resolved against
    `session.projectRoot` when relative.
  - `suggestedFile` = `startFolder/<document.source.label>.wav`.
  - `optionsVisible = false`, `choosingFile = true`.
- `rejectOptions()`, `rejectPath()`: close everything and set `active = false`. No
  stop, capture or preference write.
- `choosePath(fileURL:)`:
  1. Decode the URL as `ShellPresenter.chooseProject` does (`ShellPresenter.swift:477-482`).
  2. Write `lastWavExportDir` = the path's parent (`setString` + `synchronize`).
  3. `session.stop()` (`:1293`).
  4. Build the capture:
     `selectedDocument.wavExportCapture(settings: audio.songSettings(for: document.state.config), options:)`.
     Options: seconds = tenths/10 and `resonanceSuppression: audio.resonanceSuppression`.
  5. `renderText` = `Rendering <label>...`, `progress = 0`, `choosingFile = false`,
     `rendering = true`.
  6. Start the job.
- `cancelRender()`: cancels the job's `Task`.

## Job wiring

- `AsyncStream.makeStream(of: Double.self, bufferingPolicy: .bufferingNewest(1))`.
- `let job = Task { @concurrent in await WavExportJob.run(capture, to: path, progress: continuation) }`.
- A main-actor `Task` drains the stream into `progress = Int(fraction × 1000)`. It
  then awaits `job.value` and handles the outcome:
  - `.completed(totalFrames)` → `session.statusMessage(message: "Exported <path> (<clockText(totalFrames / rate)> @ <rate> Hz)")`.
  - `.cancelled` → `statusMessage("Export cancelled.")`.
  - `.failed(message)` → `failureMessage = message`, `failureRevision += 1`.
  - Then `rendering = false`, `active = false`.
- Keep the `job` handle for `cancelRender()`. No `Task.detached`, GCD or locks.

## `ShellPresenter`

- `Action("file.export_wav")` after `file.close_tab`.
- `menuLabels["file.export_wav"] = "Export WAV..."`; `actionLabel` stays the keymap
  "Export WAV".
- `fileActionIds` is the head group: the file ids without export/quit. New published
  `fileExportActionIds = ["file.export_wav"]` and `fileQuitActionIds = ["file.quit"]`
  (class body, set in `init`).
- `actionEnabled`: first, `if session.wavExportPresenter().active { return false }`,
  covering every id including the always-true ones and Quit. Then
  `case "file.export_wav": return session.wavExportPresenter().exportAvailable`.
- `activate`: `case "file.export_wav": session.wavExportPresenter().open()`.
- `beginClose()` returns false while `active`. Cancel is the only exit.

## `WavExportSurface.qml`

Required: `presenter`, `colors`, `windowRoot`, `typography`.

- `readonly property bool exportActive: presenter.active` and
  `onExportActiveChanged: ++windowRoot.actionRevision`.
- `readonly property bool choosing: presenter.choosingFile`, whose handler opens the
  picker.
- `readonly property int failureRevision: presenter.failureRevision`, whose handler
  opens the error box.
- Options window, `DialogWindow` (`src/ui/shell/DialogWindow.qml`, the base Settings uses: native `Qt.Dialog` window with the platform open animation, focus return to `transientParent`, `present()` to open, Escape → `close()` unless `escapeCloses: false`; do not redeclare `flags`, the focus-return handler or an Escape shortcut), `shellWavExportDialog`:
  - Title "Export WAV", `modality: Qt.ApplicationModal`,
    `transientParent: windowRoot`, `visible: presenter.optionsVisible`.
  - `GridLayout` of 2 columns mirroring the `QFormLayout` rows, in fork order with
    fork labels:
    - `wavExportRate`: ComboBox.
    - `wavExportLoopCount`: SpinBox 1–99, looping only.
    - `wavExportFade`: SpinBox in tenths, `stepSize: 10` (QDoubleSpinBox
      `singleStep` 1.0), text `%1 s` with one decimal, looping only.
    - `wavExportTail`: same shape, non-looping only.
    - `wavExportDuration`: Text.
  - `wavExportOk`/`wavExportCancel` in `SettingsDialog`'s button order
    (`SettingsDialog.qml:176-200`). Return accepts, Escape rejects.
  - `onClosing`: refuse the close and call `rejectOptions()`.
- Save picker, `FileDialog` `shellWavExportFileDialog`: title "Export WAV",
  `fileMode: FileDialog.SaveFile`, `nameFilters: ["WAV files (*.wav)"]`,
  `currentFolder`/`selectedFile` from the presenter, `modality: Qt.ApplicationModal`.
  `onAccepted` → `choosePath(selectedFile.toString())`; `onRejected` →
  `rejectPath()`.
- Progress window, `DialogWindow` `shellWavExportProgress`:
  - `visible: presenter.rendering`, app-modal, title
    `Qt.application.name` (QProgressDialog's untitled default).
  - `wavExportProgressLabel` shows `renderText`.
  - `wavExportProgressBar` has `from: 0`, `to: 1000`, `value: presenter.progress`.
  - `wavExportProgressCancel` shows "Cancel" and calls `cancelRender()`.
  - Escape and `onClosing` (refused) also call `cancelRender()`, as
    `QProgressDialog` cancels on close.
- Error box, `MessageDialog` `shellWavExportErrorDialog`: title "Export WAV",
  `text: presenter.failureMessage`, Ok only.

Geometry and colors:
- Sizes derive from `FontMetrics` of `typography.body`, as `AboutDialog.qml` does.
  No px literals.
- Text uses `colors.windowText`. Labels of hidden rows are not rendered.

## `ShellMenuBar.qml` File menu

1. Instantiator over `fileActionIds`, inserting at `index`.
2. `MenuSeparator { objectName: "shellFileExportSeparator" }`.
3. Instantiator over `fileExportActionIds`, anchored after that separator. Same
   anchor idiom as the Edit menu, `ShellMenuBar.qml:61-83`.
4. `MenuSeparator { objectName: "shellFileQuitSeparator" }`.
5. Instantiator over `fileQuitActionIds`, anchored the same way.

# Implementation steps

1. Presenter and `ApplicationSession` attach/slot, per the contract.
2. `ShellPresenter` edits, then the `ShellMenuBar` File groups.
3. `WavExportSurface.qml`, mounted in `ShellWindow.qml` after `AboutDialog` with
   `presenter: shell.session.wavExportPresenter()`, `colors: root.colors`,
   `windowRoot: root`, `typography: root.chromeTypography`. Add it to `QML_FILES`.
   - Bare Space: the options and progress windows are modal prompts, the AGENTS.md
     local-Space exception. `ShellWindow`/persistent chrome gains no key handler.
4. `WavFileProbe` (`@MainActor @QtBridgeable`, `QmlInstantiableStatus`, like
   `PolyphonyShellProbe`). It decodes with Foundation only and never calls
   `WavExport`.
   - `inspect(path:) -> Bool` fills `valid`, `sampleRate`, `channels`,
     `bitsPerSample`, `frameCount`, `peak`.
   - `exists(path:) -> Bool`.
   - `digest(path:) -> String`: FNV-1a 64-bit hex of the file bytes.
5. `ShellQmlEntries`: both entries use `inputFileName: "tst_ShellExport.qml"` and
   `fixtureFiles: songs("mus_route101", "mus_route102")`.
   - `shell-export-options`, with `testFunctions`:
     `ShellExport::test_menuRow`, `ShellExport::test_loopOptions`,
     `ShellExport::test_tailOptions`, `ShellExport::test_fileDialogMemory`.
   - `shell-export-render`, with `testFunctions`:
     `ShellExport::test_exportRendersLiveSessionAndStopsPlayback`,
     `ShellExport::test_modalRenderBlocksInputAndCancels`,
     `ShellExport::test_writeFailureReportsAndLeavesNoFile`.
6. `tst_ShellExport.qml`. Drive the mounted controls with real input: keyboard on
   the focused SpinBox/ComboBox, mouse on buttons, and `presenter.activate` for menu
   rows as `tst_ShellMenus` does. The picker is driven through
   `fileDialog.selectedFile = …; fileDialog.accept()`, which runs the production
   `onAccepted`. Outputs go under `<projectRoot>/sound/`. Every assertion has a
   message.
   - `test_menuRow`:
     - Row text starts with "Export WAV...".
     - Disabled with no song; enabled once `mus_route101` is open.
     - Activation shows `shellWavExportDialog`.
   - `test_loopOptions` (`mus_route101`):
     - Title and labels as the fork; the Tail row is absent.
     - Rate model is the 3 labels at index 2; loop count 2 and clamps at 1/99; fade
       "5.0 s" and clamps at 0/60.
     - Loop Up/Down: the durations for 1/2/3 loops step equally (±1 s) and
       increase.
     - Fade Up adds 1 s (±1).
     - The 48000→32000 rate change keeps the duration (±1 s).
     - While open, `actionEnabled` is false for `transport.play_pause`,
       `file.save_song`, `edit.preferences`, `file.quit`.
     - Start playback first. Cancel (click) and Escape each close the dialog with
       `active` false, no picker, and playback still playing.
   - `test_tailOptions` (`mus_route102`): Tail row "3.0 s", loop and fade rows
     absent, Up adds 1 s (±1).
   - `test_fileDialogMemory`:
     - With no preference, OK opens the picker at `<root>/sound/songs/midi` with
       `…/mus_route101.wav`.
     - Picker reject: no render, no stop, the preference is unwritten.
     - An accepted export to `<root>/sound/first.wav` (32000 Hz, 1 loop, fade 0)
       completes and writes `lastWavExportDir == <root>/sound`.
     - The next open starts in `<root>/sound` with `…/sound/mus_route101.wav`.
   - `test_exportRendersLiveSessionAndStopsPlayback` (`mus_route102`, 32000 Hz,
     tail 0.0):
     - Export `before.wav`.
       - Status equals `Exported <path> (<m:ss> @ 32000 Hz)` with m:ss from
         `frameCount / 32000` truncated.
       - The probe shows a valid RIFF, 32000 Hz, 2 channels, 16 bits and
         `frameCount > 0`.
       - `round(frameCount / 32000)` equals the dialog's seconds.
     - Transpose: `roll.select_all` + `roll.transpose_up`. Start playback. Export
       `after.wav`.
       - Transport is still playing through options accept and picker open, and
         stopped once `rendering` is true.
       - The digests of `before.wav` and `after.wav` differ.
       - The document stays dirty and Undo still reverts the transpose.
       - The staged `.mid` digest is unchanged.
   - `test_modalRenderBlocksInputAndCancels` (`mus_route101`, 48000 Hz, loop count
     99):
     - Once `progress > 0`, the output exists (streamed). Progress label
       "Rendering mus_route101...", bar value equals `presenter.progress`.
     - `actionEnabled` is false for every `presenter.actionIds` entry.
     - The Space keyClick on the shell and a transport Play click both leave the
       transport stopped.
     - `shell.close()` leaves the shell visible.
     - A Cancel click leads to `active` false, the file removed, status
       "Export cancelled." and `actionEnabled("transport.play_pause")` restored.
     - A second 99-loop export cancelled with Escape gives the same result.
   - `test_writeFailureReportsAndLeavesNoFile`: a path under `<root>/missing-dir/`
     shows `shellWavExportErrorDialog` titled "Export WAV", text starting
     `Cannot write <path>: `, no file and `active` false.
7. `tst_ShellMenus.qml:88-89`: compare `file` item objectNames to
   `[open_project, new_song, save_song, register_song, close_tab rows,
   shellFileExportSeparator, shellAction_file.export_wav, shellFileQuitSeparator,
   shellAction_file.quit]` with the file's existing JSON idiom. `file.count == 9`,
   message "the File menu keeps the fork rows and separators". No ledger anchors
   these messages.
8. `tst_TextContrast.qml`, `auditWavExport(context)`:
   - Activate `file.export_wav` and audit `shellWavExportDialog.contentItem`, then
     reject.
   - Start a 99-loop export to `<root>/sound/contrast.wav`, audit
     `shellWavExportProgress.contentItem` once visible, then cancel. The audit
     follows the `auditSettings` pattern (`:151-166`).
9. Manual page: File → Export WAV, the options with ranges and defaults, loop vs
   tail, duration, the remembered folder, app-modal progress/Cancel, and that export
   renders the unsaved song and bank as heard. The second section ("What export is
   for") stays as the TODO describes: sharing previews, and not how music reaches
   the game.

# Acceptance predicate

File → Export WAV mounts in the fork position. It exports what the user hears:
- unsaved edit buffer and current bank;
- playback stopped only after the path is accepted;
- the fork's options, duration preview, remembered folder, progress, Cancel, error
  and status feedback.

The whole app accepts no other input for the span of the export, and a cancelled or
failed export leaves no file.

Implementer runs, under the build lock:
```sh
deno task build:app
deno task build:checks
deno task checks:shell --filter shell-export-options --verbose
deno task checks:shell --filter shell-export-render --verbose
deno task checks:shell --filter shell-menus --verbose
deno task checks:bridge
```

Coverage:
- The two new entries cover every step-6 predicate.
- `shell-menus` covers the File topology.
- `checks:bridge` covers presenter/QML declarations.

# Controller verification

After the writer settles:
```sh
deno task checks:shell --filter shell-text-contrast-song-vanilla --verbose
deno task checks:shell --filter shell-text-contrast-song-dark-neutral-high --verbose
deno task checks:shell --filter shell-text-contrast-song-immaterial --verbose
deno task checks:shell --filter shellwindow --verbose
deno task proof check --executed
```

Visual parity (plan.md Global constraints) needs a native macOS desktop:
- Capture the Swift options window (loop and tail songs) and the progress window.
- Capture the fork reference `build-asan/porydaw.app` (main checkout) for the same
  songs.
- List every deviation with a reason. Known ones: a QML SpinBox for QDoubleSpinBox,
  and a persistent status message (the Swift status bar has no timed messages; the
  fork cleared after 5/8 s).

Gaps:
- Native save-panel delivery is unproved offscreen (verification.md SHELL row).
- 4 GB and empty-render refusals cannot be reached with fixtures; they are proven
  in 220.
- Mid-write I/O failure is not synthesizable.
- The native macOS menu bar during app modality is covered by the authority gate,
  not by a native menu lane.

# Task-specific constraints

- No `Connections` or `@QtSignal` on the presenter (r22 delivery evidence). No
  context properties. No `Qt.callLater`.
- No second dispatcher. Every activation goes through `ShellPresenter.activate`.
- No new key handling in persistent chrome.
- Do not edit `DocumentSession.swift`, `NativeAudio.swift` or `WavExport.swift`.
  Their contracts are frozen by 220/221.
- Contrast: WCAG AA through GridPalette pairs, audited by step 8.
- Existing `tst_ShellMenus` predicates other than `:88-89` must not be re-pinned.
