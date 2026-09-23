# spec.md — Swift/QML dock lists (Songs + Voicegroup) conversion

Behavior, interfaces, and oracle inventory for the implementation plan in
this directory. This spec describes the current Swift rewrite and the
remaining port; it does not describe a clean-sheet presenter architecture.

## 1. Goal and current state

Build the Songs and Voicegroup surfaces into the Swift rewrite shell
(`RewriteWindow` + `SwiftRollOverlay.qml`) while preserving the behavior
of the retained native sources. The shell keeps a dock column beside the
song tabs. Song-list identity, voice edits, voicegroup changes, and bank
state must flow through the existing Swift session owners.

The song service and presenter already exist. Tasks 1 and 2 are not
implementation work for those types: task 1 is a pre-existing baseline;
task 2 wires that service and presenter into `ApplicationSession` and the
shell. The native widget and check sources are not to be added to a build
as a shortcut. They are source oracles until task 17 retires the explicitly
listed files.

## 2. Source-grounded findings

| Existing source | Current contract | Plan consequence |
|---|---|---|
| `src/project/swift_project_service.h` / `.cpp` | `PdSongListEntry`, `pd_service_list_songs`, registration/deletion plan and mutation operations, `pd_service_voicegroup_args` | Do not add a duplicate song-list or `groupArgs` bridge. |
| `src/swift/app/ProjectService.swift` | `SongListing`, `songs()`, song register/delete plan and mutation methods, `voicegroupArgs()`, `save(_:bank:)` | Reuse these service methods. New bridge work is limited to missing voicegroup/sample payloads and operations. |
| `src/swift/app/songlist/SongListPresenter.swift` | Existing `SongListRow.songId`, `setSongs(_:)`, `activateSelection()`, filter/category/sort and mutation intents | Task 2 integrates this presenter; do not create a replacement. |
| `src/swift/app/voicelist/VoiceListController.swift` | Existing 128-row controller, `refresh(from:)`, `setVoicegroupChoices`, `commitVoicegroupSelection`, `voiceDraft(_:)`, `requestVoiceEdit`, `applyVoiceEdit` | Task 6 integrates this owner; do not introduce `VoicegroupPresenter`. |
| `src/swift/app/ProjectService.swift` / `DocumentSession.swift` | `BankSlotView.tone` fallback, `DocumentSession.undo()`, `redo()`, `save()`, `applyBankEdit` | Preserve fallback tone data, undo semantics, and clean-save/no-receipt behavior. |
| `src/project/projectworkspace.*`, `projectio.*`, `src/ui/workspaceui_samples.cpp` | Uncompiled ProjectWorkspace/ProjectIo flows and QWidget behavior are historical oracles, not the live app service | Extend the compiled `PdProjectService` worker bridge; reuse compiled `SampleRegistrar` and the existing worker ownership. |

The `VoiceListController` callbacks already carry the structural-edit flag.
The `PdBankSlotView.tone` data covers parsed-voice gaps and must remain
visible when there is no `BankVoice`. A structural edit must keep its flag
through the QML/controller path so audio can rebind with
`NativeAudio.updateVoicegroup(_:)`.

The compiled `porydaw_app` source list in `CMakeLists.txt:178-234`
includes `swift_project_service.cpp`, `samplereg.cpp`, and
`voicegroupsource.cpp`. `ProjectWorkspace`/`ProjectIo` and their
`CreateVoicegroupInput`, `ProbeSamplesInput`, `ReadSampleInput`, and
`CommitSampleInput` flow are not compiled or exposed through that service.
Tasks 9 and 10 add the required commands/completions to the compiled
`PdProjectService` worker; task 9 calls existing
`VoicegroupSource::createVoicegroup` / `appendIncludeLine`, and task 10
calls existing `SampleRegistrar::registerSample` / `updateSample`.

`src/audio/{sampleimport,sampledsp,sampledoc,samplewav}.*` are not linked
into the current app target. Task 11 links the processing modules needed by
sample import/edit and establishes their Swift/backend predicates. Task 12
completes project/editor lifecycle parity using that contract.

The old samplecheck C++ suites are not compiled by
`src/checks/CMakeLists.txt` or registered in `src/checks/checkcatalog.cpp`.
Their seven retained proof inventories contain 418 GAP and 75 NATIVE
sites. Tasks 11 and 12 add the runnable Swift/backend parity; task 14 maps
each sample site; task 17 retires only the named uncompiled C++ check
sources. Do not describe a `samplecheck` C++ test target or treat a filter
for it as proof.

Frozen visual source oracles already exist under
`src/checks/fixtures/visual/macos-dpr2-font12/` and
`macos-dpr2-font16/`. The visual comparator and `visual-swift-12` /
`visual-swift-16` lanes already exist. Task 4 registers production Songs QML
capture in those lanes. Visual runs require a native desktop and a
connected 2x display; the captures are separate from retired widget checks.

## 3. Scope decisions

### 3.1 Included flows and explicit exclusion

The dock migration includes song registration/deletion confirmation,
voicegroup creation and undoable assignment, sample creation/editing with
native import/edit semantics, and picker audition for Sample, Wave, and
Keysplit voices. These actions must be functional through the existing
session owners and new operations on the compiled `PdProjectService`; no
disabled controls or fake fallback flows.

The unrelated new-song wizard is excluded. Do not broaden this plan to
that wizard or other legacy-shell retirement.

### 3.2 Keysplit audition

For the native row-browse path, resolve a keysplit through `table[60]`.
Reject invalid or nested targets; do not recurse or invent a fallback.
Audition only a valid direct Sample/Wave leaf: a Sample leaf plays MIDI 60
with the leaf `ToneData.key` as `toneKey` and the leaf ADSR; a Wave leaf
plays MIDI 60 with the leaf ADSR and no `toneKey`. Square/noise and
invalid/nested targets retain the native silent-refusal behavior. This is
not permission to make valid Sample/Wave leaves intentionally silent.

### 3.3 Reuse existing Swift owners

`SongListPresenter` owns song-list state and identity. `VoiceListController`
owns the voice list and existing draft/edit requests. `DocumentSession`
owns undoable document/bank changes and `NativeAudio` owns bank playback
rebinding. QML renders and forwards user actions; it does not duplicate
these business rules in a second presenter.

### 3.4 Visual scope

Task 4 registers production Songs QML capture with the existing comparator
and visual lanes. Tasks 7 and 8 add only their scenario-specific editor and
picker pins. Task 10 completes the voicegroup-browser vanilla/dark pins,
including new/edit sample controls, and the sample-editor vanilla/dark pins.
The shared full vanilla/dark voicegroup pin is not complete before task 10.

## 4. Interface and behavior contracts

### 4.1 Songs

- Baseline service: `PdSongListEntry`, `pd_service_list_songs()`, and
  `ProjectService.songs()` already exist. The service returns playable
  entries including registered, partial, and unregistered songs, with
  `songId`, registration gaps, and their display metadata.
- Task 2 wires `SongListPresenter.setSongs(_:)` from
  `ApplicationSession` and uses `SongListRow.songId` as selection and
  navigation identity. At the existing `openSong(label:)` boundary, resolve
  that ID through the current listing; never capture a row index or use the
  display label as identity. It migrates the QML drawer diagnostic to
  `songList.rows`, but retains the legacy `songCount()` /
  `songLabel(index:)` / cache bridge and `chooseSong` until task 3's shell
  cutover.
- Task 3 replaces Open Song with Find Song, installs the `songs.find`
  `QAction`, and calls the existing presenter's `focusSearch()`; QML handles
  `searchFocusRequest`. It also removes `chooseSong` and the legacy
  count/label/cache bridge, and exposes the existing register/delete intents
  as functional QML confirmation flows. Cancel performs no mutation;
  confirmation uses the existing plan/mutation APIs, reports conflicts and
  errors, and refreshes the listing after success.

### 4.2 Voicegroup data and `-G` rebind

- Reuse `pd_service_voicegroup_args` and
  `ProjectService.voicegroupArgs()` as the canonical sorted argument list;
  do not add a second `groupArgs` query.
- Task 5 adds missing catalog/sample data and bank-load bridge operations
  to the compiled `PdProjectService` worker. Reuse
  `pd_service_voicegroup_args`/`ProjectService.voicegroupArgs()`; do not
  duplicate `groupArgs`. The new
  `sampleBrowseData(symbol:auditionKey:)` resolves the native keysplit
  lookup (`table[60]` for row browse) to a direct Sample/Wave leaf and
  returns that leaf's payload and tone metadata. Invalid/nested/non-leaf
  targets are refused, not recursively or audibly fabricated.
- `DocumentSession.setVoicegroupArgument(_:)` records an undoable cfg
  edit, loads a fresh bank for the requested argument, adopts it, and
  publishes document/bank/history/dirty changes. Undo and redo rebind to
  the restored argument before publication. A failed rebind keeps the
  previous bank lease and reports the failure; catalog outage does not
  fabricate choices or replace the existing bank view.
- Rebind resolves from the current source, not a stale bank lease. A
  changed-on-disk source is reloaded for the requested `-G`; failure leaves
  the prior binding intact. Saving a clean session remains a no-op with no
  save receipt.

### 4.3 Voice list and editor

- Task 6 integrates the existing `VoiceListController` into the QML panel:
  128 stable rows, selector choices, icon rendering, reveal/scroll, and
  audio refresh. Preserve `BankSlotView.tone` when a parsed `BankVoice` is
  absent, including read-only/broken/uncovered slots.
- Task 7 completes the editor decision tree through existing
  `voiceDraft(_:)`, `requestVoiceEdit(slot:voice:)`, and
  `applyVoiceEdit(slot:voice:)`. Keep the editor draft attached to the
  current controller/session path; do not drop the `structural` callback
  flag. Preserve blank materialization, readonly/broken notices,
  family-specific controls, keysplit/drumkit handling, ADSR family history,
  and edit conflict/undo behavior from the native oracle.
- The task 7 visual scope is limited to the frozen `editor-square1` and
  `editor-readonly` variants; it does not close the full vanilla/dark
  voicegroup pin.

### 4.4 Picker and synth persistence

- Task 8 preserves Sample/Wave/Keysplit browse audition and the exact
  samplepicker pins, including `vgSamplePickerList`. Picker selection
  changes the pending draft; commit remains the existing
  `applyBankEdit` path.
- Synth minting remains session-scoped and does not write files until
  save. Extend `PdSaveRequest`/`ProjectService.save(_:bank:)` only for
  bank-referenced synth definitions; the current bridge's synth-definition
  list is hard-empty. A clean save remains receipt-free.

### 4.5 Voicegroup creation and sample workflows

- Task 9 adds a command/completion to the compiled `PdProjectService`
  worker that calls existing `VoicegroupSource::createVoicegroup` and
  `appendIncludeLine`; the uncompiled `CreateVoicegroupInput` /
  `ProjectWorkspace` path is a source oracle, not the live service. Assign
  the new `-G` through task 5's undoable `DocumentSession` path. Undo
  restores the previous assignment; it does not pretend the created
  project asset was never written.
- Task 10 adds compiled-service sample probe/read/commit operations that
  call existing `SampleRegistrar` registration/update and sidecar
  semantics. The uncompiled `ProjectWorkspace`/`ProjectIo` commands are
  behavior references only. Task 10 depends on task 11's linked processing
  backend. Its acceptance proves the New/Edit workflow/runtime and the
  full visual pins; task 12 completes the sample project/editor lifecycle
  method parity.
- New accepts imported audio or an SF2 zone; preserve the phase-cancelling
  stereo left-channel choice, validate names against `^[a-z0-9_]+$` and
  existing symbols, and store source hash/import parameters in the
  sidecar. On commit, refresh the catalog and assign the new sample through
  one `applyBankEdit`: retain an existing DirectSound voice's other fields,
  or materialize DirectSound at key 60/pan 0 with the native default ADSR.
- Edit requires a voice referencing a project sample and keeps its
  registered name read-only. Re-decode the sidecar source and restore its
  parameters only when the source hash matches; otherwise use the committed
  WAV and remove stale provenance on commit. Update the existing sample
  without changing its registration, then refresh the catalog. Cancellation
  creates no project mutation. A sidecar write failure remains distinct
  from the WAV commit result, as in the native operation.
- The QML controls retain the frozen names `vgNewSampleButton`,
  `vgEditSampleButton`, `editor.sample.new`, and `editor.sample.edit`.

- The New sample name field is prefilled from its source and performs live
  collision/grammar validation: an existing name shows status and disables
  commit, a fresh valid name enables it, and invalid grammar disables it.
  The editable custom target-rate text is deferred input: typing never runs
  the processing pipeline; Return, focus-out, or a preset selection commits
  the rate. Verify the exact custom-rate commit in one-shot mode: it updates
  `targetRate` and processed `declaredRate` and clears the exact-pitch
  override. In loop-preserving mode the pipeline may adjust its exact output
  rate to land the loop length on an integer sample. Task 12 verifies these
  controls in production QML; `pipelinePrefillCollision` and
  `pipelineRateCommit` are not SwiftCore predicates.

### 4.6 Shared dock layout and editor sizing

Native `WorkspaceUi` creates `songsDock` and `voicegroupDock` in the
`LeftDockWidgetArea` (`src/ui/workspaceui.cpp:112-143`). The rewrite uses
one shared left dock column beside the song tabs. Task 3 owns the outer
column-width boundary and persisted `columnWidth` preference at
`swiftDock/columnWidth` (280 logical pixels by default, clamped to 200–480).
Task 3 must not implement the internal Songs/Voicegroup split.

Task 6 owns one inner vertical `SplitView`: Songs above Voicegroup, with
one horizontal drag handle. `songsRatio` is the normalized fraction of the
inner split height assigned to Songs; initialize it to 0.5 and persist it
as `swiftDock/songsRatio`. Clamp the restored ratio and each drag so both
panes retain their fixed controls and at least one complete list row; the
host minimum height must accommodate both minima. Keep both list areas
independently scrollable. Task 6 must not create a second dock column,
another divider, or duplicate the outer width preference.

Task 7's isolated visual capture uses the 420×680 logical baseline; those
dimensions are not live dock minimums. Native `VoicegroupBrowser` gives the
editor `QSizePolicy::Ignored` (`src/ui/voicegroupbrowser.cpp:304-310`) and
does not force the dock wider. Task 7 adapts within the persisted dock width
(280 logical pixels by default, clamped to 200–480); editor fields may
shrink/clip as in the native UI. Do not add a transient width request or
change the saved dock width when the editor opens.

In the live dock, the editor body scrolls when the Voicegroup pane is
shorter. Native QML checks exercise CGB and DirectSound editor selections
at the default 280-pixel width and a constrained split height; selection
must not widen the dock, and every editor control must remain reachable
through scrolling.

## 5. Exact visual and check surfaces

### 5.1 Frozen visual pins

- Songs: `songlist/vanilla` and `songlist/darkneutralhigh` under both
  `macos-dpr2-font12` and `macos-dpr2-font16`, at their frozen logical
  sizes: 280×480 for font12 and 348×480 for font16. Preserve every frozen
  region; named regions include `songList`, `songListCategory`,
  `songListCount`, `songListSearch`, `songListSort`, `songs.search`,
  `songs.category`, `songs.sort`, `songs.list`, `songs.count`,
  `songs.row.first`, `songs.row.second`, `songs.row.unregistered`, and
  `songs.row.partial`.
- Voicegroup browser: `voicegroupbrowser/vanilla` and
  `voicegroupbrowser/darkneutralhigh` under both 2x profiles, preserving
  the full frozen region set including `selector`, `vgArgCombo`, `tree`,
  `tree.header`, `tree.row.NNN`, `tree.row.NNN.type-icon`,
  `tree.row.NNN.adsr`, `voicegroupEditorNotice`,
  `listPositionIndicator`, `vgNewSampleButton`, `vgEditSampleButton`,
  `editor.sample.new`, and `editor.sample.edit`.
- Task 7 editor variants: `voicegroupbrowser/editor-square1` and
  `voicegroupbrowser/editor-readonly`; task 8 picker:
  `samplepicker/vanilla` and `samplepicker/darkneutralhigh`, including
  `vgSamplePickerList`.
- Task 10 sample editor: `sample-editor/dialog-vanilla` and
  `sample-editor/dialog-darkneutralhigh` under both 2x profiles, retaining
  waveform, handles, seam, and splitter regions. The source cases are
  `src/checks/visual/dialogs.cpp:555-590` and proof sites A010-A015 in
  `src/checks/visual/proof.dialogs.txt`.
- Run visual predicates in both `visual-swift-12` and `visual-swift-16`
  with native desktop + 2x display. QML behavior checks use the native
  `swiftrollgated` surface; Swift/backend checks use the registered Swift
  check lane. Exact commands and runnable predicates are owned by briefs.

### 5.2 Existing Swift check conventions

The song and voice checks live under `src/checks/songlist/` and
`src/checks/voicelist/`. New backend checks follow these Swift check
conventions and assert observable results, boundaries, transitions, and
errors. Do not revive the uncompiled samplecheck C++ target.

### 5.3 Keyboard and search focus

The `songs.find` keymap registry entry defines the action ID but does not
already focus the presenter. Task 3 installs the Find Song `QAction` in
`RewriteWindow`, calls `SongListPresenter.focusSearch()`, and lets QML
consume `searchFocusRequest` to focus and select the search text. In the
Songs search field, bare Space propagates to the transport, while
Up/Down/PageUp/PageDown forward selection to the list. The modal sample
editor is the deliberate local exception: its focused audition control
consumes Space to audition, matching
`src/ui/sampleeditordialog.cpp:574-594`. No other panel control claims bare
Space.


## 6. Proof inventories and correspondence gates

Task 11 ports sample processing behavior from `analysis.cpp`,
`decoder.cpp`, `dsp.cpp`, and `soundfont.cpp`: 229 sites across 30 methods.
It establishes the backend contract consumed by task 12.

Task 12 ports sample project/editor lifecycle behavior from `editor.cpp`,
`integration.cpp`, and `project.cpp`: 264 sites across 32 methods, with
exactly 18 SwiftCore predicates and 14 SwiftRollGated predicates. It depends
on task 11's processing contract and completes the sample workflows before
sample proof correspondence begins. `engineLoop` is the headless NativeAudio
integration predicate and belongs in SwiftCore. `pipelinePrefillCollision`
and `pipelineRateCommit` exercise production QML controls and therefore
belong to SwiftRollGated, not a SwiftCore approximation.

Task 13 updates per-assertion correspondence in all seven
`src/checks/voicegroupsave/proof.*.txt` inventories: `editor` (32),
`fixture` (4), `picker` (47), `presentation` (80), `savecore` (81),
`switching` (46), and `synth` (42). It also maps all sites in the
historical browser proof, `src/checks/visual/proof.browsers.txt`, to named
runnable QML/visual predicates.

Task 14 updates per-assertion correspondence in the seven samplecheck
inventories, which currently record 418 GAP + 75 NATIVE sites:

| Inventory | Source suite |
|---|---|
| `src/checks/samplecheck/proof.analysis.txt` | `analysis.cpp` |
| `src/checks/samplecheck/proof.decoder.txt` | `decoder.cpp` |
| `src/checks/samplecheck/proof.dsp.txt` | `dsp.cpp` |
| `src/checks/samplecheck/proof.editor.txt` | `editor.cpp` |
| `src/checks/samplecheck/proof.integration.txt` | `integration.cpp` |
| `src/checks/samplecheck/proof.project.txt` | `project.cpp` |
| `src/checks/samplecheck/proof.soundfont.txt` | `soundfont.cpp` |

It also maps the sample-editor visual sites A010-A015 in
`src/checks/visual/proof.dialogs.txt` to task 10's runnable visual
predicates. Each NATIVE setup site must name the Swift/QML fixture or
predicate it supports. Every original behavior assertion must map to a
named runnable predicate; a non-behavior site requires an explicit
rationale. No unmatched site or behavior-level GAP/NATIVE exception may
remain at retirement.

Task 15 adds Swift history parity and completes the runnable coverage for
the retained viewcache oracle, `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt`
(A001–A070):

- A001–A032, `historyLifecycleAndStaleTransitions`: document and bank
  history lifecycle, blank-slot materialization/revert/rematerialization,
  and stale undo/redo conflict behavior.
- A033–A039, `mergeRules`: same-slot scalar edit merging and inverse
  annihilation; no merge across slot/materialization/attack/structural
  differences; saving the document must not seal an adjacent bank edit's
  merge (A038), while the explicit bank merge boundary must seal it (A039).
- A040–A070, `coordinatorRoutesTransitionsAndGates`: transition routing,
  identity/tab rejection, pending-action and close gates, and conflict,
  applied, hard-error, and clear resolution paths.

Existing `historyTransitionRegressions`, `bankMergeSealing`, and
`bankCoordinatorGate` are partial starting points, not evidence for all 70
sites. Task 15 keeps its production and runtime-check changes in one
cohesive history seam: `src/swift/core/SongHistory.swift`,
`src/swift/app/DocumentSession.swift`,
`src/checks/workspace/bank_history_probes.swift`,
`src/checks/workspace/bank_edits.swift`,
`src/checks/workspace/bank_sharing.swift`, and
`src/checks/workspace/SessionChecks.swift`. It adds
`viewcacheHistoryLifecycleParity`, `viewcacheMergeRulesParity`, and
`viewcacheCoordinatorRoutesParity`.

In `src/swift/core/SongHistory.swift`, `markSaved(_:)` seals an adjacent
document entry but not a bank entry; public `sealBankMerge()` seals only
the top bank entry and has no effect on document entries or empty history.
In `src/swift/app/DocumentSession.swift`,
`applyBankEdit(slot:value:expected:)` calls `sealBankMerge()` when
`bankDirty == false`, after admission guards and immediately before
`beginBankTransition()`. Do not seal on dirty-bank edits; a failed
application must not record its candidate.

The runtime contract is observable at both owners: two same-field bank
edits separated only by `markSaved(currentIdentity)` remain one undo step;
an explicit `sealBankMerge()` before the next edit creates a second step
(A038–A039). Separately, after a real service save, the first subsequent
clean-bank edit seals the prior command so undo reaches the saved bank
view. Saving a document still seals its document merge boundary. A038 and
A039 require runnable core and real-session predicates for these distinct
boundaries.

Task 16 updates every A001–A070 record in
`src/checks/voicegroup/proof.tst_voicegroupviewcache.txt` to the exact
runnable Swift predicate or a justified non-behavior rationale. No
unjustified `GAP` may remain. Preserve the original source context,
assertion identity, reference revision, and SHA-256 fields.

The correspondence check is **STRUCTURE ONLY**. It verifies ledger grammar
and site coverage, not parity or runtime behavior. Runtime proof comes from
the named Swift/QML predicates and visual lanes. For every ledger, preserve
its `Reference revision`, `Original SHA-256`, original source context, and
assertion identity while updating disposition/mapping/evidence.

Keep `src/checks/voicegroup/proof.tst_voicegroupviewcache.txt` as a
historical source-oracle inventory. Keep `src/checks/visual/proof.dialogs.txt`
as well; unrelated dialog proof sites remain outside this plan.

## 7. Task 17 source retirement

Only after tasks 1–15 behavior and visual gates are green and tasks 13, 14,
and 16 correspondence gates pass—including task 15's viewcache/history
predicates—does task 17 directly remove only these uncompiled widget/check
sources:

- `src/ui/songlistpanel.{h,cpp}`, `voicegroupbrowser.{h,cpp}`,
  `voicegroupviewcache.{h,cpp}`, `samplepicker.{h,cpp}`,
  `sampleeditordialog.{h,cpp}`, and `dragspinbox.{h,cpp}`.
- `src/checks/support/voicegroupbrowserdriver.{h,cpp}`,
  `src/checks/voicegroupsave/{editor,fixture,picker,presentation,savecore,switching,synth}.cpp`,
  `src/checks/voicegroupsave/tst_voicegroupsave.h`,
  `src/checks/visual/browsers.cpp`, and
  `src/checks/voicegroup/tst_voicegroupviewcache.cpp`.
- `src/checks/samplecheck/{analysis,decoder,dsp,editor,fixtures,integration,project,soundfont}.cpp`,
  `src/checks/samplecheck/{fixtures,samplecheck}.h`, and
  `src/checks/samplecheck_fixtures.h` (the latter is included only by the
  retiring decoder check).

Do not remove any `proof.*.txt` inventory, frozen fixture, or retained
visual baseline. Keep the production modules
`src/audio/{sampleimport,sampledsp,sampledoc,samplewav}.*` and
`src/project/samplereg.*`; they implement behavior reused by the port.
`src/ui/voicetypeicons.*`, `src/checks/visual/chrome.cpp`, unrelated
dialog sources, and the wider dead shell (`workspaceui*`, `mainwindow.*`)
are not in this retirement list. No build target should be added for the
retired C++ sources.

## 8. Vocabulary

- **Song ID** — stable `SongListRow.songId` identity; not a row index or
  label.
- **Voicegroup argument** — song cfg `voicegroupArgument` (`-G`); choices
  come from existing `ProjectService.voicegroupArgs()`.
- **Bank view** — `BankSlotView` rows, retaining optional parsed
  `BankVoice` and the `tone` fallback.
- **Structural edit** — controller callback state requiring bank/audio
  rebind; it must not be discarded by QML.
- **Frozen pin** — reviewed `fixtures/visual/<profile>/<id>.{json,png}`
  pair compared by the native visual lane.
- **Proof correspondence** — per-source-assertion mapping to a named,
  runnable Swift/QML predicate, not merely a well-formed ledger.
