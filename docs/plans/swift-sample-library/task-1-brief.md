# Task 1 — SampleLibraryModel, preferences widening, unit checks

## Context

First task of the sample-library pane port (plan: `docs/plans/swift-sample-library/`).
Produces the pane's Swift model with typed QtBridge rows, persistence through the
existing preferences store, and pure-Swift unit checks. Consumers: task 2 wires the
model's four callbacks into `SampleStudioWorkflow` per the interfaces in
`spec.md → SampleLibraryModel`; task 3 mounts the QML pane against
`folders`/`files`/published state and the slot methods. The model itself performs no
audio, decode, or workflow calls.

## Exact write set (4 explicit paths; nothing else)

- Create `src/swift/app/samplestudio/SampleLibraryModel.swift`
  (row types + model in one file: one concept, small public surface)
- Edit `src/swift/app/presentation/shell/PreferencesStore.swift` — widen
  `strings(_:)` and `setStrings(_:_:)` to `@QtIgnored public` (declaration
  bodies unchanged; cross-module Swift consumers, not QML slots — no
  `Optional<[String]>` QML callable)
- Edit `src/swift/app/shell/PorydawQmlTypes.swift` — append
  `SampleLibraryFolderRow.self`, `SampleLibraryFileRow.self`, `SampleLibraryModel.self`
  to the uncreatable list (the "existing registrations, then alphabetical additions"
  section) only: no `extension` conformances (the classes carry inline
  `: QmlUncreatable` per the samplestudio precedent — duplicates won't compile)
- Create `src/checks/samplecheck/LibraryModelChecks.swift`

Controller-owned mechanical additions (NOT in this write set): the
`src/swift/app/CMakeLists.txt` source line, the `src/checks/CMakeLists.txt` lane
line, the `SampleChecks.swift` runner call, and all baseline files.

## Prerequisites

None (first task). Tasks 2 and 3 consume this task's interface contract only.

## Interface contract

Exact declarations and state-machine invariants: `spec.md → SampleLibraryModel`,
`PreferencesStore`. Behavioral contract for every method: `spec.md` §1–§19 (folders,
tree, audio list, status readouts, exact strings, objectNames are QML-side but the
strings originate here). Additional pinned details:

- Normalization: `URL(fileURLWithPath: dir).standardizedFileURL.path` semantics —
  absolute, `.`/`..` resolved, no symlink resolution, trailing separators removed.
  `addFolder` first decodes a `file://` URL string to its local path (QML passes
  the stringified `FolderDialog` URL); plain paths remain accepted. Spaces and
  unicode survive.
- Row/model classes carry inline `: QmlUncreatable`; registration is the type-list
  append only, with no duplicate extension conformance.
- Message lifecycle: `showMessage("")` clears. Selection clears old messages.
  `selectFile` and `selectFolder` never preview or load; `clickFile` previews,
  `activateFile` and `loadSelected` load, and `togglePreview` starts/stops.
  Checks assert silent selection and meaningful error clearing independently.
  `clearFileSelection` recomputes the consistent no-selection status (spec §15 order).

## Implementation steps

1. Widen the two `PreferencesStore` methods to `@QtIgnored public`; no other edit
   in that file. These are Swift-only cross-module APIs, not QML slots.
2. Write `SampleLibraryModel.swift`: row classes with inline `: QmlUncreatable`
   and model init `@QtIgnored public init(preferences:)` (samplestudio
   precedent for both), then the model. Keep the state machine in one private `refresh*`
   cluster mirroring the historical `refreshFolders`/`refreshFiles`/`updateState`
   split (tree publish, file publish, derived state). Folder rows carry the data
   QML needs to render depth, disclosure, and selection without a second query.
3. Tree representation: a private ordered `[FolderNode]` (path, depth, expanded,
   children-loaded) flattened into `folders` on publish; `selected` compares the
   current node identity. `files` republishes on navigation. Selection state lives
   in the model; QML renders it.
   Each node retains its unchanged immutable row snapshot; recreate it only when
   expansion or selection changes. Use the existing `syncModel` helper for
   incremental publication, not a whole-model reset.
4. Callbacks: the four `@QtIgnored` closures are Optional and unwrapped with
   `guard` at emission points (a `nil` callback is a no-op, not an error) — task 2
   wires them.
5. Register the three types in `PorydawQmlTypes` (uncreatable list append only).
6. Write `LibraryModelChecks.swift` as `internal func runLibraryModelChecks(_ report:
   CheckReport)` following `EditorPresenterChecks.swift`'s fixture style: stage
   `PreferencesStore.stageShared(plistPath:)` at a temp URL (already the shell-lane
   pattern; safe in this lane), build scratch directories under
   `FileManager.default.temporaryDirectory` + UUID, clean up with `defer`.
   `cppID` labels: `swiftcore/SampleLibraryModel::<behavior>`.

   Assert at least: normalization/dedupe/trim through seeded preferences at init
   (the historical `lib/.`, duplicate `lib`, `lib/sub/..` triple); persistence
   round-trip through a fresh model instance; persisted list read at init;
   the six-extension case-insensitive listing with `notes.txt`,
   `font.sf2` and a subdirectory excluded (write fixture files with bytes from
   `SampleFixtures` or plain `Data` — listing is name-driven, content irrelevant);
   hidden file/dir exclusion; missing-folder status and `filesVisible == false`;
   empty-folder status string; selection enablement matrix (`canLoad`/`canPreview`/
   `canRemove`); `togglePreview` label flip and stop emission only while
   previewing; silent `selectFile` (no callback fired) but message cleared;
   `clickFile` emits `onPreviewRequested` with the absolute path even while a
   preview is active (replace, not stop — capture emissions in a counter closure);
   `activateFile`/`loadSelected` emit `onLoadRequested`; `removeSelectedRoot`
   removes only the bookmark (fixture files still exist afterwards), resets to the
   first remaining root, and the empty case yields the no-folders status; status
   precedence chain of §15 including the message override; loaded/preview readout
   strings; symlink directory exclusion when
   `FileManager.createSymbolicLink` succeeds (skip the row when creation is denied
   — named platform gap).
## Acceptance predicate

NAMED CHECKS (controller-run; implementers reuse as recorded). Baseline: exact
`samplecheck-editor` passes (1/58 selected). No broad `swiftcore` regex is used
as fake coverage.

- `uv run --no-sync dev checks --filter samplecheck-editor`
  — runs `runSampleEditorChecks`, including the new `LibraryModelChecks` wired by
  the controller, with no regression in decoder/presenter/loop-tools/
  audition-strip/waveform suites.
  Covers: every §1–§19 behavior listed in step 6; preferences widening compiles.
- `uv run --no-sync dev checks --filter samplecheck-storage`
  — regression sweep over project sample registration and provenance storage.
- `uv run --no-sync dev checks:bridge` — validate rows, tracked published state,
  ignored Swift-only callbacks/preferences methods and supported QML slots.
  Controller observation: zero baselined findings; no rewrite is required.

Permanent checks assert consumer-visible behavior (state machine, callbacks,
strings); no duplicate exact-string implementation tests beyond the spec'd
readouts. Runtime prerequisites: none beyond the worktree's `uv sync --locked`
state (already performed in this worktree). No windowing: the lane is offscreen.

## Task-specific constraints

- Deltas on top of plan.md Global Constraints: none beyond the write set. Do not
  touch `SampleStudioWorkflow`, `SampleStudioPresenter`, `SampleStudioAudition`,
  `SampleWaveformModel`, `SampleLoopTools`, or any QML — those are tasks 2/3 even
  if a compile fix seems needed there (report instead).
- Do not add a `Listing…` state, async listing, or cancellation machinery.
- No JSON encoding of the folder list; the widened list API is the only persistence
  path.
- Strings are part of the contract: copy them verbatim from spec.md §15–18 (they are
  the historical `tr()` texts without the translation wrapper; `qsTr` wrapping
  happens QML-side in task 3 for labels the QML owns, while model-published strings
  ship as-is).

## Controller verification

After the writer settles (controller-owned, in order):

1. Wire the controller-owned registration: `src/swift/app/CMakeLists.txt` source
   line, `src/checks/CMakeLists.txt` lane line, `SampleChecks.swift` runner call.
2. `uv run --no-sync dev checks:bridge` (rewrite only a justified intended delta)
3. `uv run --no-sync dev checks --filter samplecheck-editor`
4. `uv run --no-sync dev checks --filter samplecheck-storage`
5. `uv run --no-sync dev format --check --base 834642b5` (changed-lines scope)
