# Task 3 — QML library pane, dialog docking, shell lane coverage, user docs

## Context

Final task of the sample-library port: mounts the pane model (task 1) and the
workflow slots (task 2) as the production QML surface inside `SampleStudioDialog`,
adds the shell QML lane that pins the pane's pointer/keyboard/status contract
plus transaction/cancellation coverage through the production lanes, extends the
checks probe for file fixtures, audits populated rows for text contrast, and
updates the user doc. Historical QML-side contract: spec.md §12–§19 (keys,
buttons, readouts, objectNames) and the sizing decision in plan.md (pane left,
`minimumWidth: 0`, `preferredWidth: 22 * unit`).

## Exact write set — bounded parallel sub-units (≤5 explicit paths each)

- **Task 3a — production surface** (5 paths):
  - Create `src/ui/shell/samplestudio/SampleLibraryPane.qml`
  - Edit `src/ui/shell/samplestudio/SampleStudioDialog.qml` — dock the pane
    (horizontal `SplitView`, objectName `sampleBrowserSplitter`) and gate
    source-dependent controls on `editor.hasSource`
  - Edit `src/ui/shell/samplestudio/SampleStudioHost.qml` — only if dialog
    parenting genuinely requires it (otherwise untouched)
  - Edit `docsrc/manual/sample-studio.md` — fill the "Opening the sample editor"
    TODO section (menu route now lands in the studio with the library pane) and
    add a "Sample library" section: bookmark add/remove (no files deleted),
    browse, preview (click / Enter / Space), load (double-click / Load), the
    guarantee that a failed load never damages the current edit, and folder
    persistence (controller-trivial inline alternative allowed)
- **Task 3b — lanes and probes** (5 paths):
  - Edit `src/checks/editorqml/ImportWizardProbe.swift` — add the three probe
    methods below; no registration change (already registered in the shell lane)
  - Edit `src/checks/editorqml/ShellQmlEntries.swift` — new entry below
  - Create `src/checks/editorqml/tst_ShellSampleStudioLibrary.qml`
  - Edit `src/checks/editorqml/tst_TextContrast.qml` — populated-library row
    audit across theme roles (not just the empty pane)
  - Edit `src/checks/editorqml/tst_ShellSampleStudioVoice.qml` — only if
    genuinely needed for contract migration from root library-first UX/parenting
    (never blanket expectation rewrites; behavior assertions stay actual)

Controller-only companion edits (NOT in any sub-unit): the root `CMakeLists.txt`
QML module line, the `src/checks/CMakeLists.txt` lane line, regenerate
`tools/qml_aot_baseline.json` (`qml-aot:baseline`) — see Controller verification.

## Prerequisites

Task 1 (model rows + published state) and task 2 (workflow slots) interfaces, frozen
per spec.md. This task is QML + checks only; a Swift-side defect found while testing
is reported to the owning task's fix loop, not edited here.

## Interface contract (consumed)

`spec.md → SampleLibraryModel` (rows, published state, slots, callbacks),
`SampleStudioWorkflow.library()/requestOpenFile()/loadLibrarySample()/
previewLibrarySample()` as reachable through the workflow object the dialog already
holds (`SampleStudioHost` passes `workflow`; the pane gets
`library: workflow.library() as SampleLibraryModel` as a dialog required property —
mirror how `Sf2ZonePickerDialog` receives `picker`). Produced: the QML surface with
objectNames of spec §19 and the lane entry name `shell-sample-studio-library`.

New `ImportWizardProbe` methods (exact):

```swift
public func writeTextFile(path: String, text: String) -> Bool
public func makeDirectory(path: String) -> Bool
public func makeSymbolicLink(linkPath: String, targetPath: String) -> Bool
public func writePhaseCancellingWav(path: String) -> Bool
```

New `ShellQmlRegistry.Entry` (exact):

```swift
Entry(
    name: "shell-sample-studio-library", inputFileName: "tst_ShellSampleStudioLibrary.qml",
    fixtureFiles: songs("mus_route101") + [
        "Makefile", "audio_rules.mk", "samplesources/hires_tone.wav",
        "samplesources/tone.flac", "samplesources/zones.sf2",
    ]),
```

`windowing` stays the default `offscreen`; no `testFunctions` filter (the file has
one test function per journey, sized like the existing studio lanes).

## Implementation steps

1. `SampleLibraryPane.qml` (task 3a): a `ColumnLayout` pane per spec §18 — header `Library`;
   `Add Folder…` (`sampleLibraryAdd`, opens the pane's `FolderDialog`
   `sampleLibraryFolderPicker`; `onAccepted: library.addFolder(selectedFolder.toString())` —
   QML passes a `String`, never a `QUrl`) and
   `Open File…` (`sampleLibraryOpen` → `library.requestOpenFile()`) row; folders
   `ListView` (`sampleLibraryFolders`, accessible name `Library folders`) with a
   delegate binding `required property` row fields, left indent `depth * unit`,
   disclosure indicator shown when `hasChildren` (rotate on `expanded`), row click →
   `selectFolder(index)`, indicator click → `toggleFolder(index)`, selected
   highlight from `selected`; `Remove from Library` (`sampleLibraryRemove`, enabled
   `canRemove`, tooltip per §18); header `Audio files`; files `ListView`
   (`sampleLibraryFiles`, accessible name `Library audio files`, `visible:
   library.filesVisible`) with delegate highlighting `selected`, pointer
   `MouseArea` `onClicked: library.clickFile(index)` /
   `onDoubleClicked: library.activateFile(index)`, and view-level
   `onCurrentIndexChanged` → `library.selectFile(currentIndex)` (silent);
   Preview (`sampleLibraryPreview`, text `previewButtonLabel`, enabled `canPreview`,
   tooltip §18, `onClicked: library.togglePreview()`) and Load (`sampleLibraryLoad`,
   enabled `canLoad`, tooltip §18, `onClicked: library.loadSelected()`) row; status
   labels `sampleLibraryStatus` (text `statusText`, wrap, tooltip `statusToolTip`),
   `sampleLibraryLoaded` (`loadedText`/`loadedToolTip`),
   `sampleLibraryPreviewing` (`previewText`/`previewToolTip`). Root `objectName:
   "sampleLibraryPanel"`.
2. Keyboard contract in the files list: the `ListView` (focusable) installs
   `Keys.priority: Keys.BeforeItem` and handles plain (no-modifier, non-autorepeat)
   `Key_Space`/`Key_Return`/`Key_Enter` → `library.togglePreview()` with
   `event.accepted = true`; arrow keys keep default behavior (silent selection).
   This mirrors the historical `sampleLibraryFiles` event filter and takes
   precedence over the dialog-wide Space handler (the dialog's focus `Item`
   filter only sees unhandled keys). Plain Space elsewhere in the dialog keeps the
   existing editor-audition toggle — do not change `handleSpace` or the
   `Audition*` components.
3. `SampleStudioDialog.qml` (task 3a): wrap the existing vertical `SplitView`
   (`sampleStudioSplitter`) in a horizontal `SplitView`
   (`sampleBrowserSplitter`): pane item `SplitView.preferredWidth: 22 * unit`,
   `SplitView.minimumWidth: 0` (drag to 0 is the collapse; the existing splitter
   drags it back — no `collapsible` attached property exists on `SplitView` in
   Qt 6.11, none is set); editor item `SplitView.fillWidth: true` with a
   positive font-derived `SplitView.minimumWidth` sufficient for the existing
   control column. Gate on `editor.hasSource`: name field
   (`readOnly: editor.nameReadOnly || !editor.hasSource`), Play button
   (`enabled: audition.available && editor.hasSource`), Loop checkbox + loop body,
   crop/rate/normalize/advanced body (`enabled` bindings), commit button
   (`enabled: editor.canCommit` already carries the gate from task 2 — leave the
   single binding). Do not reorder or restyle existing controls.
4. (3b) Extend `ImportWizardProbe` with the four methods (`FileManager` writes;
   use the existing decoder-check PCM fixture pattern for phase cancellation;
   `makeSymbolicLink` returns success so tests can skip on denial). Wire the lane
   entry in `ShellQmlEntries.swift`. (Controller adds the root `CMakeLists.txt`
   QML line and the `src/checks/CMakeLists.txt` lane line.)
5. `tst_ShellSampleStudioLibrary.qml` (`ShellLaneSupport` + `ShellQmlBootstrap` +
   `ImportWizardProbe`, modeled on `tst_ShellSampleStudio.qml`'s
   `openProject`/`child`/`waitForNative` helpers). Journey (single
   `function test_libraryBrowsePreviewAndLoad()` or split if the harness timeout
   demands — keep every assertion below):
   - Menu `tools.import_sample` opens the blank studio (`sampleStudioDialog`
     visible) AND the picker (`shellImportSamplePicker` visible) over it; blank
     state: `sampleStudioName` read-only, `sampleStudioPlay` disabled,
     `sampleStudioCommit` disabled, `sampleLibraryLoaded` text `Loaded: none`,
     `sampleLibraryStatus` `No library folders. Add a folder or open a file.`.
   - Cancel the picker; the blank studio stays and browses: inject the
     `sampleLibraryFolderPicker` (`selectedFolder = "file://" + projectRoot +
     "/samplesources"` — the `file://` scheme is required, cf. the voice lane's
     `selectSource` — then `accept()`) → tree lists `samplesources`; audio list
     eventually shows `hires_tone.wav` and `tone.flac` (tryCompare on the ListView
     `count`/rows), `sampleLibraryRemove` enabled, `sampleLibraryLoad`/
     `sampleLibraryPreview` disabled (nothing selected).
   - Keyboard selection is silent: key-click Down arrows on the files list change
     selection (`Selected:` status flips) without `sampleLibraryPreviewing`
     changing from `Preview source: none`.
   - Pointer click on `hires_tone.wav` previews: `sampleLibraryPreviewing`
     tooltip = the file URL path; `sampleLibraryPreview` label `Stop Preview`;
     editor Play stays `Play` (mutual exclusion of state); Space in the list stops
     (label back to `Preview`, tooltip empty). Audibility under the null backend
     is unproven statically — assert the label state machine only (audibility is
     pinned deterministically by task 2a's real-engine checks and covered finally
     by native smoke).
   - Double-click loads: name prefills `hires_tone`, source label contains
     `PCM WAV`, `sampleLibraryLoaded` tooltip = path, commit enabled, undo reset
     (`workflow.editor().canUndo === false`). Edit something (`setLoopStart`),
     then Load a corrupt file (`disk.writeTextFile(rootPath + "/bad.wav", "not
     audio bytes")` after adding its directory as a folder): pane status shows the
     decode message, the document keeps its params/name/undo count, loaded tooltip
     unchanged (spec §20).
   - Case-insensitive listing + exclusions: write `tone.MP3` (valid WAV bytes are
     not required for listing — name-driven), `notes.txt`, `font.sf2` into a probe
     `makeDirectory` folder, add it, assert the exact row set (uppercase listed;
     txt/sf2 absent). If `makeSymbolicLink` succeeds, link a directory under the
     root and assert it never appears (skipped when denied — named gap).
   - Remove bookmark: click `sampleLibraryRemove` → tree empty, status back to the
     no-folders text, fixture files still on disk (`disk.exists`), audio list
     hidden.
   - Transaction + cancellation through the production lane (task 2c coverage):
     replacing-SF2-zone cancel and stereo-prompt cancel leave the existing
     editor, document, provenance and undo history untouched; blank-chooser
     cancel leaves the browsable blank studio; locked-edit loads keep the name
     and read-only field; a no-source-open asserts the `hasSource` gating.
   - Exercise the real stereo phase-cancellation prompt through pane Load using
     `writePhaseCancellingWav`; cancel preserves the old edit, while accepting
     commits the left-only source. Stage `zones.sf2` for replacement cancellation.
6. (3a) Docs: fill the two `docsrc/manual/sample-studio.md` sections listed in the
   write set; keep the existing comment style; no new pages.

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded). Baseline: exact
`samplecheck-editor` passes (1/58 selected). No broad `swiftcore` regex is used
as fake coverage.

- `uv run --no-sync dev checks:shell --filter shell-sample-studio-library`
  — the new lane: blank-open + browse + silent selection + preview toggle +
  transactional load + corrupt-preserve + listing filter + bookmark removal +
  transaction/cancellation coverage.
- `uv run --no-sync dev checks:shell --filter shell-sample-studio`
  — substring filter; runs the new lane AND the four existing studio lanes
  (`shell-sample-studio`, `-commit`, `-voice`, `-refusal`): proves the dialog
  changes and blank-open sequence preserved every existing journey (menu route,
  cancel teardown, splitter drag, Space handling, commit/collision, voice
  import/edit/undo/fallback, SF2 zone picker, refusal). Do NOT combine this broad
  filter with `--qt <fn>` (it matches five entries; the runner takes one harness —
  controller-verified constraint).
- `uv run --no-sync dev checks:shell --filter shell-text-contrast`
  — exact text-contrast gate, including the populated-library row audit across
  theme roles (not just the empty pane).
- `uv run --no-sync dev checks:bridge` — pane wiring adds no new bridged types;
  guard confirms the dialog's new required property and pane bindings stay legal.
- `uv run --no-sync dev checks:qml-aot` — after the controller rewrites the
  baseline with `uv run --no-sync dev qml-aot:baseline` (new QML file = intended
  surface change); ratchet must pass with the pane compiled.

Runtime prerequisites: the shell lane runs offscreen with
`PORYDAW_AUDIO_BACKEND=null` (runner-set); no window-system requirement. Native
desktop is NOT required for these commands.

## Task-specific constraints

- Deltas on top of plan.md Global Constraints:
  - QML conventions per Global Constraints; additionally `model.X` reads only
    inside the two row delegates, and every delegate input is a
    `required property`. Text colors from `dialog.colors` (`GridPalette`) only —
    every QML text meets WCAG AA against its real surface.
  - No context properties: the pane reaches the model through the dialog's
    required property from `workflow.library()`.
  - Existing studio test files keep their behavior assertions; contract migration
    is allowed only where root library-first UX or dialog parenting genuinely
    requires a mechanics change (picker-first mechanics may move) — never blanket
    expectation rewrites. If a lane fails, that is a defect in tasks 1–3
    implementation first — report and fix at the cause.
  - `qsTr` wraps only literal QML label strings; model-published strings arrive
    localized-ready as-is (spec §15–18).
  - Geometry from `unit`/`spacing` only; no pixel literals.
- Coverage gaps: live acoustic audibility, platform-denied symlink creation, and
  native folder-dialog UX require honest runtime evidence. No synthetic
  production fallbacks or test-only host: mount the production `ShellWindow`.

## Controller verification

After the writer settles (controller-owned, in order):

1. Wire the controller-owned registration: root `CMakeLists.txt` QML line,
   `src/checks/CMakeLists.txt` lane line.
2. `uv run --no-sync dev qml-aot:baseline` (rewrites `tools/qml_aot_baseline.json`
   — controller-only edit) then `uv run --no-sync dev checks:qml-aot`
3. `uv run --no-sync dev checks:bridge`
4. `uv run --no-sync dev checks:shell --filter shell-sample-studio`
5. `uv run --no-sync dev checks:shell --filter shell-text-contrast`
6. `uv run --no-sync dev checks --filter samplecheck-editor` (final no-regression
   sweep of tasks 1–2 check files in the same tree)
7. `uv run --no-sync dev format --check --base 834642b5`
8. Native smoke (controller-run real app with live audio; screenshot capture where
   available — mandatory, with honest blockers; no claimed keyboard observation
   without tools): build `uv run --no-sync dev build:app`, launch
   `build/debug/porydaw.app/Contents/MacOS/porydaw --project <staged-or-fixture decomp project> --song mus_route101`,
   then: Tools → Import Sample (studio opens blank, picker over it), cancel picker,
   Add Folder… (real dialog), click a WAV (audible preview; label flips), Space
   (stops), double-click (document loads; audition audible from the editor side),
   corrupt-file load attempt (message only), Remove from Library (files remain on
   disk). Also `uv run --no-sync dev checks --filter production-startup` as the
   production-binary boot check.
