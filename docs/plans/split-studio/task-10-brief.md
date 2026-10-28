# Task 10 — App + QML: workflow, modeless window, editors, Tools action, routing gate, shell lane

## Context

Tenth task of the Split Studio plan; brings the studio to the user. The
window is the app's first modeless secondary window (all existing dialogs
are modal `DialogWindow`s, verified: `src/ui/shell/DialogWindow.qml` sets
`Qt.WindowModal`). Producers consumed: task 9's presenter (mounted,
closures wired), task 8's source session (rendered at save), task 6's
`MarkerWaveformModel` (constructed here with the session's `GridPalette`
and injected into the presenter), task 5's
`SampleLibraryModel`/`SampleLibraryPane`, task 4's
`DocumentSession.applyKitEdit`, task 3's
`registerBatch`/`KitUsageScanner`/validation, task 2's writer +
`createVoicegroup`/`appendIncludeLine` (new-kit creation at save). Focus
routing uses an explicit gate (R8), not an assumption about the existing
`activeFocusItem` check alone. This task is one behavior change over the
file cap (new window surface); the exception is named in the plan's task
table. Tasks 11–12 will re-edit this task's workflow/window files — M4
checkpoints the accepted result first.

## Exact write set

- Create `src/swift/app/kitstudio/KitStudioWorkflow.swift`
- Create `src/swift/app/kitstudio/KitStudioCloseGuard.swift` (close/retarget
  prompt state machine; tasks 11–12 call in)
- Edit `src/swift/app/ApplicationSession.swift` (lazy `kitStudio()` holder
  beside `sampleStudio()`; session-created sample registry —
  `recordCreatedSample(name:)` / `orphanSplitStudioSamples()` /
  `deleteOrphanSamples(_:)`, R6; release on dispose paths that clear
  `sampleStudioWorkflow`)
- Edit `src/swift/app/shell/ShellPresenter.swift` (activate case
  `tools.split_studio` → `session.kitStudio().requestOpen()`)
- Edit `src/swift/app/shell/ShellPresenter+ActionPolicy.swift` (policy case)
- Edit `src/swift/app/shell/ShellActionCatalog.swift` (action, `toolsIds`,
  `menuLabels` `"tools.split_studio": "Split Studio..."`)
- Edit `src/swift/app/commands/KeybindingRegistry.swift` (definition
  `.init("tools.split_studio", .window, "Split Studio")` after
  `tools.import_sample`)
- Edit `src/ui/shell/ShellContent.qml` (mount `KitStudioHost` beside
  `SampleStudioHost`; shortcut delegate `enabled` gains the
  `content.root.active &&` term — R8)
- Create `src/ui/shell/kitstudio/SplitStudioWindow.qml` (modeless
  ThemedWindow shell: title, splitters, shortcuts, prompts)
- Create `src/ui/shell/kitstudio/KitStudioHost.qml` (Loader host)
- Create `src/ui/shell/kitstudio/SliceEditorView.qml` (source tabs,
  waveform display, slice list, snap/rate controls)
- Create `src/ui/shell/kitstudio/ZoneEditorView.qml` (keyboard 0–127, zone
  blocks, drag/drop, strip)
- Create `src/ui/shell/kitstudio/KitSlotPicker.qml`
- Create `src/checks/editorqml/tst_ShellSplitStudio.qml`
- Edit `src/checks/editorqml/ShellQmlEntries.swift` (one lane entry
  `shell-split-studio`; plus the R19 text-contrast entries — see below)

Controller-owned: `src/swift/app/CMakeLists.txt` source lines,
`src/checks/CMakeLists.txt`, QML module registration, `PorydawQmlTypes`
rows (task 9), baselines.

## Prerequisites

Tasks 2–9 (interfaces only; implementations may still be in review).

## Interface contract

`spec.md → PorydawApp (task 10)` plus:

```swift
@MainActor @QtBridgeable
public final class KitStudioWorkflow: QmlUncreatable {
    public var windowOpen = false               // Bool: unannotated (R22)
    public var presenterRevision = 0            // Int: unannotated
    public func presenter() -> Optional<KitStudioPresenter>
    public func library() -> Optional<SampleLibraryModel>
    public func requestOpen()          // Tools action; binds/retargets (spec §2)
    public func saveToSong()           // ONE undo step (spec §20)
    public func closeRequested()       // window close path with prompt (spec §23)
    public func answerPrompt(answer: Int)  // 0 save, 1 discard, 2 cancel
    // Wiring for the presenter closures happens here (task 9's contract).
}
```

- **Save pipeline** (single async task, generation-guarded exactly like
  `SampleStudioWorkflow.accept`, `SampleStudioWorkflow.swift:278-346` —
  the `sessionGeneration` pattern): render pending slices (task 8
  session) → `SampleRegistrar.registerBatch` for new/renamed slices
  (names validated through the R20 adapter:
  `existingSymbols = VoicegroupSource.directSoundSymbols(projectRoot)` ∪
  pending batch names ∪ current draft slice names — rename validation sees
  batch-local names) → [new kit only: `createVoicegroup` +
  `appendIncludeLine` for `<vg>_kit<N>`; Keysplit view saved:
  `KeysplitTableWriter.replace` for `keysplit_<vg>_kit<N>`; shared-kit
  copy default: snapshot sub-group + table under the fresh names] →
  `DocumentSession.applyKitEdit(KitEditValue, expected:)` →
  `session.recordCreatedSample(name)` for every written slice →
  `session.refreshVoicegroupCatalog()`
  (`ApplicationSession+Catalog.swift:9`) → presenter `markClean` path.
  Failure surfaces in the window's alert (title `Split Studio`) and leaves
  the draft dirty; a partial batch failure never applies the kit edit
  (register-then-apply only). The pipeline never deletes registrations
  (R4): undo'd or renamed-away names become orphan-eligible, nothing more.
- **Own-save suppression** (R5/F4): the save continuation installs the
  (generation token, expected after-state) tag BEFORE calling
  `DocumentSession.applyKitEdit` — both inputs are known pre-call, so not
  even a synchronously delivered bank-change notification can race the
  tag — clears the tag on throw, and marks the draft clean on success;
  the conflict observer drops any bank-change notification matching its
  own tag (no reload, no conflict bar).
- **Conflict observation**: bank-change notifications for the bound slot
  (reusing the voiceList bank-refresh callback seam) compare the slot's
  voicegroup/voice identity against the tag; unmatched notifications
  follow spec §21 (clean → silent reload; dirty → bar).
- **Session registry** (R6): `ApplicationSession` owns
  `recordCreatedSample`/`orphanSplitStudioSamples`/`deleteOrphanSamples`;
  the workflow only records. Closing the window never drops the registry.
- **Routing gate** (R8): `ShellContent.qml`'s shortcut delegate
  `enabled` becomes `actionState.enabled && content.root.active &&
  content.root.activeFocusItem !== null`; the window's own
  `StandardKey.Save`/`Undo`/`Redo`/`Close` `Shortcut`s are
  `Qt.WindowShortcut`-scoped. Cmd/Ctrl+Z and Cmd/Ctrl+S routing are
  verified by native smoke (gap named in plan.md; no lane row fits the
  budget).
- **QML**: `SplitStudioWindow` is a `ThemedWindow` with `flags:
  Qt.Window`, no modality, `transientParent` set; left pane = existing
  `SampleLibraryPane`; right = vertical split (SliceEditorView /
  ZoneEditorView); both splitters user-resizable; geometry restored from
  `splitStudioWindowSize` / `splitStudioSplitters` on open and written on
  splitter release / window close, but only when a value differs from the
  stored one (F7). All text via `colors` pairs;
  `objectName`s: `splitStudioWindow`, `splitStudioLibrary`,
  `splitStudioSliceEditor`, `splitStudioZoneEditor`,
  `splitStudioSlotPicker`, `splitStudioSave`, `splitStudioClose`,
  `splitStudioConflictBar`, `shellAction_tools.split_studio` (menu item,
  automatic).
- **Lane** `shell-split-studio` (one entry, `tst_ShellSplitStudio.qml`,
  fixtures `songs("mus_route101") + ["Makefile", "audio_rules.mk",
  "samplesources/hires_tone.wav"]`, budgeted 0.85 s): activate the Tools
  menu item (existing menu-trigger helpers from
  `tst_ShellSampleStudio.qml`: `menu.open(); mouseClick(child(
  "shellAction_tools.split_studio"), …)`); verify the modeless window
  opens bound to the song; drive the presenter to add a marker + Slice
  selection on the imported source; drop the slice on key 60 (drumkit);
  Save to Song; assert (R4): the session's `app.canUndo` flips false→true
  with exactly the kit action — one `app.requestUndo()` restores the
  original parent-slot voice — AND the slice `.wav` + registration still
  exist on disk after the undo AND `session.orphanSplitStudioSamples()`
  now lists the slice; no pre-save in-window edit added a history entry.
  The draft went clean; the window stays open; close it and assert a
  shell action still activates.
- **Text contrast** (R19): no inline contrast rows. Register the window in
  the audit: `textContrastEntries` in
  `src/checks/editorqml/ShellQmlEntries.swift:16-29` gains a
  `split-studio` state crossed with the two modes that differ most in
  contrast — `vanilla` and `dark-neutral-high` (F1; the `immaterial`
  entry is cut for budget and named as a gap in plan.md), and
  `tst_TextContrast.qml` gains the state that opens the window. The
  orphan dialog's opening path is smoke-verified in task 12 (named gap).

## Implementation steps

1. Write `KitStudioCloseGuard` (prompt state machine: sources = window
   close, tab/project close (tasks 11–12 call in), retarget; answers route
   to save/discard/cancel continuations; clean ⇒ immediate close). Save
   suspends the close until the save task settles; Cancel aborts;
   Discard proceeds (R23 — full sequencing wired in task 12 for the
   tab/project/quit paths; window close uses it now).
2. Write `KitStudioWorkflow` per contract: presenter + library + waveform
   construction (GridPalette lives here), closure wiring (validate via the
   R20 adapter, load via lease + `VoicegroupLocator` reads through the
   session's services, usage via `KitUsageScanner`, publish via
   `AudioAudition`, playPcm via `PcmAuditionPlayer`), open/retarget, save
   pipeline with the R5 tag, conflict observation, registry recording.
3. Register the action (four Swift files above) — one-line-each mechanical
   additions; the menu renders it automatically through `toolsActionIds`.
4. Edit `ShellContent.qml`: mount the host AND add the `content.root.active
   &&` term to the shortcut gate (R8).
5. Write the QML: window + host + three views + picker per contract; drag
   and drop from the slice list onto keys uses the presenter's
   `dropSample`; zone drags call `moveZone`/`resizeZone`; keyboard zoom/
   scroll on the zone editor; strip editors bind the selected zone row.
6. Write `tst_ShellSplitStudio.qml` + the lane entry + the audit state per
   contract; follow `ShellLaneSupport`'s helpers (`waitForNative`,
   `child(name)`, `ImportWizardProbe` as `disk`).
7. Geometry persistence: read on `Component.onCompleted`, write on close
   via `PreferencesStore` through the workflow (no QML settings access).

## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded):

- `uv run --no-sync dev checks:shell --filter shell-split-studio`
  — the plan's ONE new shell QML lane. Covers: Tools entry opens the
  modeless window; slice → zone → Save to Song = exactly one song undo
  step; files survive undo; orphan query lists the slice; draft-clean
  close; shell interop after close.
- `uv run --no-sync dev checks:shell --filter shell-text-contrast-split-studio-vanilla`
  and `uv run --no-sync dev checks:shell --filter shell-text-contrast-split-studio-dark-neutral-high`
  — the R19 audit entries for the new window (two themes; the
  `immaterial` entry is cut for budget — plan.md named gap).
- `uv run --no-sync dev checks:bridge`
  — workflow + presenter bridged surface legal; baseline updated only for
  the intended additions.
- `uv run --no-sync dev checks:shell --filter shell-startup`
  — regression: shell action catalog/order changes and the gate edit don't
  disturb startup lanes.
- `uv run --no-sync dev checks:qml-aot`
  — new QML compiles; rejections justified via controller-reviewed
  baseline.

Runtime prerequisites: the lane runs offscreen; budgeted 0.85 s + 0.70 s
audit (plan.md table). NOT covered here (named gaps/smoke): Cmd/Ctrl+Z
and Cmd/Ctrl+S routing with a live window manager (native smoke), dropdown
guard, tab/project close prompts, orphan checklist UX, geometry
persistence across relaunch, audible output.

## Task-specific constraints

- Modeless contract: never `DialogWindow`, never `Qt.ApplicationModal`; the
  main window must stay interactive while Split Studio is open (do not
  steal activation back on a timer).
- `rule://text-contrast` is hard: every label uses an allowed role pair;
  contrast lives in the audit entries, not the lane.
- The gate edit is exactly one `&&` term (`content.root.active`) plus the
  existing check — no second dispatcher, no focus memory (AGENTS.md
  keyboard priority).
- The lane must not depend on window-system focus delivery (windowing
  `offscreen`) — objectName lookups and presenter calls only.
- Everything tasks 11–12 own (dropdown guard, tab/project/quit close
  integration, orphan dialog, switch-back bar wiring) stays out:
  `KitStudioCloseGuard` exposes the API; the session integration points
  are theirs.

## Controller verification

1. Wire CMake/QML registration: app sources, QML module files list, checks
   sources; the `ShellQmlEntries` lane + audit entries are in this task's
   write set.
2. `uv run --no-sync dev build:checks` then
   `uv run --no-sync dev checks:shell --filter shell-split-studio`
3. `uv run --no-sync dev checks:shell --filter shell-text-contrast-split-studio-vanilla`
   and `uv run --no-sync dev checks:shell --filter shell-text-contrast-split-studio-dark-neutral-high`
4. `uv run --no-sync dev checks:bridge`
5. `uv run --no-sync dev checks:shell --filter shell-startup`
6. `uv run --no-sync dev checks:qml-aot`
7. Temporary native smoke (removed after), on a real desktop session:
   modeless interaction (main window editable while open); Cmd+Z routes to
   the focused window (draft undo in Split Studio, song undo in the shell)
   over the R8 gate; Cmd+S in Split Studio saves to song while the song's
   own Cmd+S still saves the song; audible slice/key audition; window
   geometry persisting across relaunch; screenshots.
8. Measure the added lane + audit entry runtimes (`--verbose`) against the
   plan budget; report overshoot instead of trimming silently.
9. `uv run --no-sync dev format --check` on changed lines.
