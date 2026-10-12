# Task 3 — QML library pane, dialog docking, existing checks, user docs

## Context

Final task of the sample-library port: mounts the pane model (task 1) and the
workflow slots (task 2) as the production QML surface inside `SampleStudioDialog`,
retains the existing studio and populated-row contrast checks, and updates the
user doc. The dedicated library UI integration lane was later retired at the
user's request; added checks must stay below three seconds of execution.
Historical QML-side contract: spec.md §12–§19 (keys,
buttons, readouts, objectNames) and the sizing decision in plan.md (pane left,
`minimumWidth: 0`, `preferredWidth: 22 * unit`).

## Exact write set — bounded parallel sub-units (≤5 explicit paths each)

- **Task 3a — production surface** (4 paths):
  - Create `src/ui/shell/samplestudio/SampleLibraryPane.qml`
  - Edit `src/ui/shell/samplestudio/SampleStudioDialog.qml` — dock the pane
    (horizontal `SplitView`, objectName `sampleBrowserSplitter`) and gate
    source-dependent controls on `editor.hasSource`
  - Edit `src/ui/shell/samplestudio/SampleStudioHost.qml` — keep pre-editor errors
    shell-owned; the dialog owns its picker, stereo question, and editor alert.
    Stereo rejection calls `cancelStereoPrompt()` (No still means mono mix).
  - Edit `docsrc/manual/sample-studio.md` — fill the "Opening the sample editor"
    TODO section (menu route now lands in the studio with the library pane) and
    add a "Sample library" section: bookmark add/remove (no files deleted),
    browse, preview (click / Enter / Space), load (double-click / Load), the
    guarantee that a failed load never damages the current edit, and folder
    persistence (controller-trivial inline alternative allowed)
- **Task 3b — existing checks and probe**:
  - Edit `src/checks/editorqml/ImportWizardProbe.swift` — retain `makeDirectory`
    for the populated-library contrast fixture; no registration change
  - Edit `src/checks/editorqml/tst_TextContrast.qml` — populated-library row
    audit across theme roles (not just the empty pane)
  - Edit `src/checks/editorqml/tst_ShellSampleStudioVoice.qml` — only if
    genuinely needed for contract migration from root library-first UX/parenting
    (never blanket expectation rewrites; behavior assertions stay actual)

Controller-only companion edits (NOT in any sub-unit): the root `CMakeLists.txt`
QML module line and any justified `tools/qml_aot_baseline.json` update — see
Controller verification. No dedicated library test lane is registered.

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
objectNames of spec §19.

Retained `ImportWizardProbe` method for the existing contrast fixture:

```swift
public func makeDirectory(path: String) -> Bool
```

The original dedicated lane, registry entry, build-list entry, and exclusive
text/symlink/stereo fixture helpers were removed to meet the runtime budget.

## Implementation steps

1. `SampleLibraryPane.qml` (task 3a): a `ColumnLayout` pane per spec §18 — header `Library`;
   `Add Folder…` (`sampleLibraryAdd`, opens the pane's `FolderDialog`
   `sampleLibraryFolderPicker`; `onAccepted: library.addFolder(selectedFolder)` —
   the bridged `QString` parameter converts the URL without a JS `toString()` fallback) and
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
4. (3b) Extend `ImportWizardProbe` only with `makeDirectory` for the existing
   populated-library contrast fixture. Do not add a separate pane integration lane.
5. Preserve the existing studio journeys while adapting picker-first mechanics
   to the blank-studio-first contract. Swift component checks cover model state,
   source replacement and audition ownership; QML pane transaction routing needs
   targeted smoke rather than a new required integration journey.
6. (3a) Docs: fill the two `docsrc/manual/sample-studio.md` sections listed in the
   write set; keep the existing comment style; no new pages.

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded). Baseline: exact
`samplecheck-editor` passes (1/58 selected). No broad `swiftcore` regex is used
as fake coverage.

- `uv run --no-sync dev checks:shell --filter shell-sample-studio`
  — substring filter; runs the four existing studio lanes
  (`shell-sample-studio`, `-commit`, `-voice`, `-refusal`): proves the dialog
  changes and blank-open sequence preserved every existing journey (menu route,
  cancel teardown, splitter drag, Space handling, commit/collision, voice
  import/edit/undo/fallback, SF2 zone picker, refusal). Do NOT combine this broad
  filter with `--qt <fn>` (it matches four entries; the runner takes one harness —
  controller-verified constraint).
- `uv run --no-sync dev checks:shell --filter shell-text-contrast`
  — exact text-contrast gate, including the populated-library row audit across
  theme roles (not just the empty pane).
- `uv run --no-sync dev checks:bridge` — pane wiring adds no new bridged types;
  guard confirms the dialog's new required property and pane bindings stay legal.
- `uv run --no-sync dev checks:qml-aot` — inspect the actual ratchet first.
  Update its baseline only for reviewed, intentional pane additions; fix
  avoidable compilation regressions rather than pinning them.

Added-check budget: below three seconds, excluding compilation. The retained
Swift runners measured 1.44 seconds total in the development Mac's debug build.
Do not reintroduce the removed dedicated UI lane or its exclusive fixture helpers.

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

1. Wire the controller-owned root `CMakeLists.txt` production QML line.
   No dedicated library integration lane or check build-list entry is added.
2. `uv run --no-sync dev checks:qml-aot`; inspect new-file statistics and
   regressions. Only if warranted, update `tools/qml_aot_baseline.json` using
   `uv run --no-sync dev qml-aot:baseline`, then rerun the gate.
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
