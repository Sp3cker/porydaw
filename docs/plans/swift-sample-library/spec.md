# Spec: Swift Sample Library pane

Authoritative behavior = historical C++ at `897afc77` (sources listed in plan.md).
This document is the single statement of agreed behavior, vocabulary and interfaces;
briefs link here and carry only deltas.

## Vocabulary

- **Bookmark root** — a user-saved directory persisted under the preferences key
  `sampleLibraryFolders` (list of absolute, normalized paths).
- **Folder tree** — bookmark roots plus lazily revealed subdirectories; navigation
  only, descendants never escape their root (symlinked directories excluded).
- **Audio list** — flat, files-only listing of the current directory with the
  case-insensitive extension filter `wav, aif, aiff, mp3, flac, ogg` (not `sf2`).
- **Pane preview** — owner-gated audition of a *source file* (default-params render,
  see below). Never mutates the editor document.
- **Load** — replace the editor document from a source file inside one transaction.
- **Lane owner** — the object identity currently entitled to the app's sample
  audition output (`SampleAuditionArbiter`).

## Historical behavioral contract (ported verbatim unless listed under Deltas)

### Folders and tree

1. Roots persist across app restarts (historical `QSettings` key `sampleLibraryFolders`;
   port: `PreferencesStore` string-list API, synchronized after each mutation).
2. `setFolders` normalization: drop entries that are empty after trimming,
   `QDir::cleanPath(QDir(dir).absolutePath())`-normalize (resolve `.`/`..`,
   absolute, **no** symlink resolution), dedupe preserving first occurrence.
3. Tree rows show the directory's display name (`fileName`; for roots ending in a
   separator — the volume root case — the native full path). Tooltips carry the full
   normalized path. Only top-level rows are bookmarks.
4. Expanding a row reveals subdirectories exactly once: directories only, no
   `.`/`..`, **no symlinked directories**, no hidden entries, sorted
   name-ascending case-insensitive. Rows with no children show no disclosure
   control. There is **no parent-directory entry** anywhere.
5. Selecting a tree row navigates: it becomes the audio-list directory, the row's
   children are populated, and the row expands. Navigating clears the message and
   the audio-list selection. Selection — tree or file-list, pointer or keyboard —
   clears the error/status message but never auditions, previews or loads.
6. `Remove from Library` removes the bookmark root of the currently selected tree
   row (walk to top level). Enabled iff any tree row is selected. It never deletes
   files. After removal the first remaining root is selected/navigated; with none
   left, the audio list hides and the status shows the no-folders text.
7. `Add Folder…` appends the chosen directory (normalized, deduped), persists,
   selects and navigates the new root. Canceling the folder dialog is a no-op.
   QML stringifies the `FolderDialog` URL; `addFolder` normalizes a `file://` URL
   to its decoded local path before folder normalization (plain paths remain
   accepted). Paths with spaces and unicode survive round-trip.
8. A bookmark whose directory no longer exists still lists in the tree; selecting it
   hides the audio list and shows the missing-folder status.

### Audio list

9. Files only (never directories), not hidden, extension filter per Vocabulary,
   case-insensitive (historical check data: `tone.wav`, `tone.AIF`, `tone.aiff`,
   `tone.MP3`, `tone.flac`, `tone.ogg` all listed; `notes.txt`, `font.sf2`,
   directory `sub` never listed), sorted by name ascending.
10. Selection changes (pointer or keyboard) are **silent** — moving the current
    index never previews, loads, or auditions — but they clear the message (§5).
    `selectFile` (keyboard/current-index path) therefore clears the message while
    emitting no preview/load callback.
11. Pointer click on a row selects it **and requests a preview** — even while
    another preview sounds (a click replaces, not just stops).
12. `Enter`/`Return`/`Space` (no modifiers, not auto-repeat) inside the list toggle
    the preview: stop when one is active, else start for the selected file. The
    list consumes these keys itself (historical event filter on `sampleLibraryFiles`)
    — they never reach the dialog-wide Space toggle.
13. Double-click (platform activation) and the `Load` button load the selected file.
14. Button enablement: `Load` iff a file is selected; `Preview` iff a file is
    selected **or** a preview is active; preview button label `Preview` /
    `Stop Preview`.

### Status readouts (exact strings)

15. Status line shows the transient message when one is set (it survives until
    cleared), else the state: in order —
    - no bookmarks: `No library folders. Add a folder or open a file.`
    - current folder missing: `Library folder is missing: <current>`
    - listing (dropped in port — synchronous listing; a directory that exists
      immediately shows its terminal state)
    - empty after listing: `No supported audio files in this folder.`
    - nothing selected: `No file selected.`
    - else `Selected: <fileName>`
    Status tooltip = selected file path (empty when none).
16. `Loaded: none` / `Loaded: <fileName>`; tooltip = loaded path.
17. `Preview source: none` / `Preview source: <fileName>`; tooltip = previewing path.
18. Labels/labels: pane header `Library`, list header `Audio files`; buttons
    `Add Folder…`, `Open File…`, `Remove from Library` (tooltip: `Remove the
    selected saved root from the library. No files are deleted.`), `Preview`
    (tooltip: `Preview the selected source file (Enter or Space in the file list).`),
    `Load` (tooltip: `Replace the editor document with the selected file.`).
    Accessible names: `Library folders`, `Library audio files`.
19. objectNames (checks target them): `sampleLibraryPanel`, `sampleLibraryAdd`,
    `sampleLibraryOpen`, `sampleLibraryFolders`, `sampleLibraryRemove`,
    `sampleLibraryFiles`, `sampleLibraryPreview`, `sampleLibraryLoad`,
    `sampleLibraryStatus`, `sampleLibraryLoaded`, `sampleLibraryPreviewing`.

### Load transaction (historical `loadLibrarySample` + checks)

20. Read failure → message `Cannot read <path>.`; decode failure → the decoder's
    message. The prior document, its provenance inputs, the locked name and the
    undo history are fully preserved; the loaded readout keeps the old path.
21. Success stops the editor's audition and any pane preview, replaces the
    document, **resets the undo history**, refreshes source-derived readouts
    (source line, frame count, crop ranges, rate label), sets the loaded readout,
    and clears the message.
22. A locked edit target (registered sample being re-edited) keeps its name and
    read-only name field across loads.
23. A source-less (blank) studio disables every source-dependent control — name
    field, play, loop controls, crops, tuning, rate, normalize, advanced body,
    commit — while the pane stays fully browsable and loadable.

### Preview ownership (historical `SoundBrowser` arbitration)

24. One active owner on the sample audition lane. Publishing displaces the previous
    owner (release first, then publish). `stop(owner)` is a no-op unless `owner` is
    the active owner. A failed (Busy) publish leaves the lane released with no
    owner. Closing/releasing a displaced owner never cuts the newer owner's audio.
25. Pane preview and the editor's render audition are mutually exclusive: starting
    the editor audition clears the pane preview label; starting a pane preview
    resets the editor play state.
26. Preview never touches the edited document, its params, or provenance.
27. Busy preview → pane message `The audition engine is busy.` (no retry from the
    pane; the editor render's existing tick retry is unchanged).

### Preview render semantics (pinned to historical `auditionExternalFile`)

28. Preview decodes the file with the default stereo handling (mono mix, no stereo
    prompt), builds `SampleDocument.defaultParams`, forces `loopOn = false`, and
    auditions `processed()` with: `loopStart = 0`, `looped = false`, ADSR = default,
    `key` = the editor audition key, `toneKey = unityNote` clamped to 0…127.
    Empty render → message `"<fileName>" renders no audio.` Decode failure → the
    decoder message; audio output unavailable → message `Audio is unavailable.`

## Interfaces (exact; produced by the tasks)

### `PreferencesStore` (widened, task 1)

```swift
@QtIgnored public func strings(_ key: String) -> [String]?          // was internal
@QtIgnored public func setStrings(_ key: String, _ strings: [String]?)  // was internal
```

The widening serves cross-module Swift consumers, not QML slots: the explicit
`@QtIgnored` keeps `Optional<[String]>` out of the QML-callable surface (no such
callable is needed). Bodies unchanged.

### `SampleLibraryModel` + rows (task 1; `src/swift/app/samplestudio/SampleLibraryModel.swift`)

```swift
@MainActor @QtBridgeable public final class SampleLibraryFolderRow: QmlUncreatable {
    public let path: String; public let title: String; public let depth: Int
    public let expanded: Bool; public let hasChildren: Bool; public let selected: Bool
}
@MainActor @QtBridgeable public final class SampleLibraryFileRow: QmlUncreatable {
    public let path: String; public let name: String; public var selected: Bool
}

@MainActor @QtBridgeable public final class SampleLibraryModel: QmlUncreatable {
    public var folders: QListModel<SampleLibraryFolderRow>   // supported type, no @QtTracked
    public var files: QListModel<SampleLibraryFileRow>
    @QtTracked public var statusText = ""
    @QtTracked public var statusToolTip = ""
    @QtTracked public var loadedText = "Loaded: none"
    @QtTracked public var loadedToolTip = ""
    @QtTracked public var previewText = "Preview source: none"
    @QtTracked public var previewToolTip = ""
    @QtTracked public var previewButtonLabel = "Preview"
    @QtTracked public var canLoad = false
    @QtTracked public var canPreview = false
    @QtTracked public var canRemove = false
    @QtTracked public var filesVisible = false
    @QtIgnored public var onPreviewRequested: ((String) -> Void)?
    @QtIgnored public var onPreviewStopRequested: (() -> Void)?
    @QtIgnored public var onLoadRequested: ((String) -> Void)?
    @QtIgnored public var onOpenFileRequested: (() -> Void)?
    @QtIgnored public init(preferences: PreferencesStore)
    public func addFolder(path: String)          // dialog accepted path
    public func removeSelectedRoot()
    public func selectFolder(row: Int)           // navigate (clears message + file selection)
    public func selectedFolderRow() -> Int       // derived visible-row cursor; -1 without selection
    public func parentFolderRow(row: Int) -> Int // parent row, or same row for a root
    public func toggleFolder(row: Int)           // expand/collapse lazily
    public func selectFile(row: Int)             // silent selection (keyboard/current-index)
    public func clickFile(row: Int)              // pointer: select + onPreviewRequested
    public func activateFile(row: Int)           // activation: select + onLoadRequested
    public func togglePreview()                  // Stop Preview → onPreviewStopRequested; else preview selected
    public func loadSelected()                   // onLoadRequested(selected)
    public func requestOpenFile()                // onOpenFileRequested()
    public func showMessage(text: String)        // "" clears
    public func setLoadedPath(path: String)      // "" → none; clears message
    public func setPreviewingPath(path: String)
    public func clearFileSelection()             // studio close: match fresh-panel state
    // Private normalization is exercised through seeded preferences at init
    // and public add/remove actions; no test-only public API is required.
}
```

State machine invariants: `canLoad` ⇔ file selection exists; `canPreview` ⇔ file
selection or preview active; `canRemove` ⇔ folder row selected; `filesVisible` ⇔
current folder exists; status text/message precedence per §15.
Removal/initialization select the first root; `addFolder` selects the chosen root.
`clearFileSelection` drops the file selection and
recomputes the status line to the consistent no-selection state (per §15 order).
All strings per §15–18. Hidden entries excluded (§4/§9). The model performs no
audio, decode or workflow calls — it only emits the four callbacks.
Conformance follows the samplestudio precedent: inline `: QmlUncreatable` in the
class bodies (all five existing samplestudio classes do this), registration via
the `uncreatableTypes` list append only — no redundant `extension`
conformances. The init takes a non-bridged `PreferencesStore`, so it is
`@QtIgnored` (same precedent as the other samplestudio inits).

### `SampleAuditionArbiter` (task 2a; `src/swift/app/samplestudio/SampleAuditionArbiter.swift`)

```swift
@MainActor public final class SampleAuditionArbiter {   // Swift-only, not bridged
    public init(output: (any SampleAuditionOutput)?)
    public var isAvailable: Bool
    /// Historical SoundBrowser publish: clear+release the active owner first, then
    /// publish; a false (Busy) result leaves the lane released with no owner.
    public func publish(owner: AnyObject, samples: [Int8], frequency: UInt32,
                        loopStart: UInt32, looped: Bool, key: UInt8,
                        adsr: AudioADSR, toneKey: UInt8) -> Bool
    /// Owner-gated stop: no-op unless `owner` is the active owner.
    public func stop(owner: AnyObject)
}
```

`activeOwner` is a weak reference; the two production owners (the workflow for
previews, the live `SampleStudioAudition` for renders) both have deterministic
stop paths (`workflow.close()`, `player.close()`), so no destroy-callback is added.

### `SampleStudioAudition` (task 2a edits)

- `init(presenter:lane:destinationAdsr:)` — takes `SampleAuditionArbiter?`; the
  direct `output` dependency is removed; `available = lane?.isAvailable ?? false`.
  All construction sites migrate, including `src/checks/samplecheck/
  AuditionStripChecks.swift` (lines 28, 44, 101): no compatibility shim.
- `start` publishes through `lane.publish(owner: self, …)`; `stop` routes through
  `lane.stop(owner: self)` then resets local state (no unconditional global off);
  `close` additionally drops the lane. Existing tick/republish-pending semantics
  unchanged.
- New `@QtIgnored public var onStarted: (() -> Void)?` — invoked after a successful
  publish (the workflow clears the pane preview label).

### `SampleStudioPresenter` (task 2b edits)

```swift
@QtTracked public var hasSource: Bool          // source.frameCount > 0
private(set) var sourceRevision = 0            // Swift-only, internal; NOT a QML baseline addition
@QtIgnored public func replaceSource(_ sample: ImportedSample,
                                     restoredParams: SampleEditParams? = nil)
```

- `hasSource == false` gates `canCommit` in `refreshName()` and the QML
  source-dependent controls (task 3). The name field is read-only while locked
  (`editName`) or blank. A zero-frame decode leaves `hasSource == false`, so
  `canCommit` is never true for an empty source.
- `replaceSource` rebuilds the document (`SampleDocument(source:)`, then
  `restoredParams` if given), resets history and gesture state, recomputes
  `sourceCents`, rebuilds the source-derived readouts (source line, frame count,
  rate choices — shared with `init`), keeps `editName`/locked name when set (else
  prefills `suggestedName`), bumps `sourceRevision` before render-observer
  notification, then `sync()`/`refreshName()`.
- `SampleWaveformModel` refresh detects the revision and rebuilds its peak
  pyramid / resets fit, drag, playhead and seam state once; parameter edits keep
  the existing `renderRevision` path and never rebuild the pyramid.
  `SampleLoopTools` detects the revision and clears pitch/candidates/status,
  then reanalyzes.

### `SampleStudioWorkflow` (task 2c edits)

```swift
public func library() -> Optional<SampleLibraryModel>   // lazy, workflow-owned
public func requestOpenFile()                           // pane "Open File…": pickerFolder + pickerRequested
public func loadLibrarySample(path: String)             // pane Load (transactional)
public func previewLibrarySample(path: String)          // pane preview (§28 semantics)
public func stopLibraryPreview()
public func cancelStereoPrompt()                       // rejection, distinct from No = mono mix
private struct PendingSource { var path: String; var bytes: Data; var leftOnly: Bool; var zone: Int }
```

- **Transaction**: `chooseSource`, `loadLibrarySample` and `requestEdit`'s resolved
  source stage into `pendingSource`; the `sourcePath`/`sourceBytes`/`leftOnly`/
  `selectedZone` fields are written only when `open(_:)` accepts (decode done;
  stereo/zone resolved). `open` on an already-open studio calls
  `presenter.replaceSource`; on a closed studio it builds presenter/wave/tools/
  player as today. Decode/stereo errors surface to the pane message when the
  request came from the pane, else to the existing alert. Provenance
  (`sourcePath`, committed inputs) commits at this same single point — no
  earlier write.
- **Async session guard**: any async source/probe continuation validates its task
  identity (session/generation) at each await before touching the studio: a
  result racing `close()` is dropped and never reopens the studio.
- `requestImport` keeps its probe gate and picker sequence; after a successful
  probe it first opens the studio blank (§23) when closed, then sets
  `pickerFolder`/`pickerRequested` exactly as today. Blank open wires
  `player.onStarted` to clear the pane preview label.
- The source picker, stereo prompt, and editor error alert share the studio
  Window's lifetime and parent; they are recreated when the studio reopens.
  Errors outside an editor session use a separate shell-owned, shell-parented
  alert. Picker visibility reads the current request state when the studio
  appears, independent of queued QtBridge notification order.
  The picker assigns its initial folder before `open()`, not through a live
  binding that can overwrite the user's selection after a queued flush.
- `previewLibrarySample`: `player?.stop()` first; guard audio; read + decode +
  render per §28; publish through the lane with `owner: self` (workflow); success →
  `library.setPreviewingPath(path)`, else pane message per §27/§28.
- **Path acceptance**: `chooseSource` keeps its `file://` URL handling and gains
  a plain-local-path fallback (the current `guard isFileURL … return` silently
  drops plain paths; R5 requires them accepted).
- `stopLibraryPreview`: `lane.stop(owner: self)` + clear the pane preview label.
- `close()`: additionally stops the pane preview (owner-gated) and resets the pane
  (message, loaded/preview readouts, file selection; bookmark list persists).
- Pane callbacks wired once at lazy creation: preview → `previewLibrarySample`,
  stop → `stopLibraryPreview`, load → `loadLibrarySample`, open-file →
  `requestOpenFile`. `loadLibrarySample` guards `committing`,
  `stereoPromptOpen`, `zonePickerOpen` exactly like `requestImport`.
- **Cancellation**: canceling the SF2 zone picker or the stereo prompt aborts the
  pending replacement and leaves the existing editor, document, provenance and
  undo history untouched; canceling the blank-studio chooser (menu route) leaves
  the browsable blank studio open.
- The stereo prompt retains Yes = left channel and No = mono mix. Native dialog
  rejection calls `cancelStereoPrompt()` instead; it never re-decodes or commits.
  Cancellation after an already-processed button is inert when no source is pending.

### QML (task 3; `src/ui/shell/samplestudio/SampleLibraryPane.qml`)

Pane column per §18 with the objectNames of §19; `FolderDialog`
(`sampleLibraryFolderPicker`) for `Add Folder…` — QML passes the selected URL
stringified, Swift `addFolder` decodes `file://` to a local path (§7); folders
`ListView` with depth-indented rows (disclosure when `hasChildren`, click
navigates, disclosure toggles); files `ListView` (visible `filesVisible`,
selected highlight, pointer click → `clickFile`, double-click → `activateFile`,
`Keys.priority: Keys.BeforeItem` consuming plain Space/Return/Enter →
`togglePreview`, current-index changes → silent `selectFile`); Preview/Load
buttons per §14. Docked into `SampleStudioDialog.qml` as the left item of a new
horizontal `SplitView` (objectName `sampleBrowserSplitter`) using existing
standard sizing only: pane `SplitView.minimumWidth: 0`,
`SplitView.preferredWidth: 22 * unit` (drag to 0 is the collapse; the existing
splitter drags it back), editor item with positive font-derived minimum width
and `SplitView.fillWidth: true`. No `collapsible` attached property exists on
`SplitView` in Qt 6.11 — none is set. Source-dependent controls additionally
gated on `editor.hasSource`. The existing dialog Space/undo handling is
untouched.

## Deltas from the historical implementation (deliberate, all named)

1. Synchronous directory listing; no `Listing audio files…` state (§15).
2. Pane Load may raise the existing stereo phase-cancellation prompt (shared decode
   pipeline; history mixed silently). Preview never prompts (§28).
3. Preferences via `PreferencesStore` plist domain instead of `QSettings`; the pane
  model is workflow-owned and survives studio close (bookmarks and the current
  folder kept; message, loaded/preview readouts and file selection reset on
  `close()` per the workflow section; history destroyed the panel on each open).
4. `FolderDialog` replaces `QFileDialog::getExistingDirectory`; `FileDialog`
   replaces `QFileDialog::getOpenFileName` (already true today). "Open File…"
   keeps the current picker's filter including `*.sf2` (SF2 import preserved);
   the pane audio list still excludes SF2 (§9).
5. One studio instance per session: the historical two-dialog displaced-owner case
   maps to (a) presenter replacement keeping a stable owner set, and (b) arbiter
   owner-gated stops; both are unit-checked (task 2).
6. Menu import (`tools.import_sample` / `requestImport`) opens the blank studio
   before the picker; historical had no menu route into the pane at all.
7. Flat `QListModel` rows with depth indentation replace `QTreeWidget`;
   `QFileSystemModel` is replaced by direct listing (filter/sort parity above).

## Non-goals (do not add)

- Save-as-New (historical `librarySaveAsNew` / `setEditTarget` + validator
  overload, `_copy` suggestion): adjacent feature, excluded. The locked-name
  `setEditTarget(name:)` single-argument flow is untouched.
- New audio engine lanes, voice-list picker audition changes, JSON preference
  encodings, second dispatchers, focus memory, proof ledgers, new modules, CMake
  options, telemetry.
- Renaming/moving existing samplestudio files beyond the edits listed in briefs.
