# Per-Song View Sidecar Removal — Implementation Plan

## Status

Normative implementation spec for this wave. It **supersedes every conflicting clause** in
`docs/projectio-dress-down-contract.md`, `docs/projectio-dress-down-plan.md`,
`docs/projectio-implementation-steps.md`, and `docs/time-ruler-loading-plan.md` (clause list in
§10; those docs are edited during Phase 3e, not before). It also supersedes the conflicting
parts of the GlobalEditorSeam design: grid `minDenom`/`gridTriplet` and a separate
`automationRowHeight` are **not** promoted; the promoted preference is exactly today's
`EditorViewState` value. Grounded in the current worktree sources; line anchors are
pre-change locations. No code is implemented by this document.

## 1. Problem and fixed decisions

Per-song UI state is persisted as a "view sidecar": `ViewSidecar::Snapshot{SongView::ViewState,
EditorViewState}` written to `<root>/.porydaw/<song>.json`, transported as `SidecarStage`
(loads) and `SaveSidecarInput`/`SaveSongInput::sidecarSnapshot` (saves), and flushed at close,
switch, and app exit. This couples cosmetic UI state to the project I/O worker, adds two
transport stages, and scatters ownership across `MainWindow` (mirror + codec), `WorkspaceUi`
(push-through), `SongTab` (two-phase apply), and per-song JSON.

Fixed product decisions (no implementation freedom):

1. The **complete `EditorViewState`** — drawer chrome (`velocity`, `automation`, `activePage`)
   plus `laneHeight`, `laneHeights`, `laneRanges`, `emptyLanes`, and the ordered
   `hiddenLanes()` sequence — is **one application-global persisted preference**.
2. **No `SongView::ViewState` field becomes global or persisted.** Camera, scroll, selected
   track, edit cursor, grid `minDenom`/feel, and event-list mode are transient per-tab state.
   `ViewState` survives only as the in-memory reload-continuation snapshot; it is never
   serialized anywhere.
3. **Ready-tab reload** (re-open of a loaded tab's song) captures and reapplies the complete
   live `SongView::ViewState`. **Fresh open / reopen after close** starts canonical defaults
   (`resetScrollPosition()` home, default zoom/key height, clock-grid floor, straight feel,
   event list off).
4. **`ViewSidecar` is deleted outright**: no reader, writer, migration, replacement
   editor-only sidecar, compatibility shim, or deprecated alias. Legacy `view`/`editor` JSON
   already on disk is ignored on load and never rewritten by the view path.
5. `.porydaw` ownership retained: `Sidecar::ensureDir` (+ `.gitignore` append), song
   registration meta, sample provenance sidecars, `.porydaw/vgpreview/`, `.porydaw/trash/`.
6. **Ownership split**: `WorkspaceUi` is the sole mutable in-memory owner of the global
   `EditorViewState` and fans out to tabs; `MainWindow` owns only QSettings load-once and
   write-through, and keeps **no mirror member**. Each `SongView` is an applied projection.
7. **QSettings schema**: the five existing `editorDrawer/*` keys keep their exact spelling and
   semantics; the former sidecar `editor` lane fields move to one canonical JSON key
   `editorDrawer/automationLanes` (QByteArray). The codec is two deep functions in the
   existing `src/ui/editorviewstate.{h,cpp}`.

## 2. State ownership

| State | Owner (in memory) | Persisted? | Store |
|---|---|---|---|
| `EditorViewState` (chrome + all lane fields, ordered `hiddenLanes`) | `WorkspaceUi::m_editorViewState` (sole mutable) | Yes, global | `QSettings` (see §3) |
| `SongView::ViewState` (camera, scroll, selected track, edit cursor, grid, event list) | each `SongView` member state | No | — (reload: `SongTab` in-memory capture) |
| Drawer/page runtime caches (`EditorDrawer::m_viewState`, page caches) | `EditorDrawer`/pages, adopted via silent `setViewState` | No | — |
| Selection, mute/solo, page gesture caches, per-tab event-list mirror | `SongView` / `MainWindow` checkbox | No | — |
| Geometry, session recipe, filters, theme, DSP, volumes, follow-playhead | unchanged (MainWindow / WorkspaceUi) | Yes | existing `QSettings` keys |
| `.porydaw/<song>.json` registration, sample sidecars, previews, trash | `SongRegistry` / `SampleRegistrar` / `ProjectIo` | Yes | unchanged |

Invariants:

- I1 Exactly one mutable global `EditorViewState` (`WorkspaceUi::m_editorViewState`).
- I2 After any mutation, every open tab and every tab created later holds an identical
  `EditorViewState` within one synchronous pass; per-tab state never crosses tabs.
- I3 `QSettings` is the only persisted home; a change writes all six keys exactly once
  through one codec; no second observable store, no shadow struct.
- I4 No per-song view/editor state reaches disk; legacy per-song JSON is never read or
  written by the view path.
- I5 The preference flow is acyclic and terminates: every echo passes an equality guard
  (hub §5.3, view §5.4, drawer diff) and converges in one pass.
- I6 Row identities (`EditorAutomationRowId`) are serialized only inside the global codec,
  never per song.

## 3. Global settings codec (exact)

`src/ui/editorviewstate.{h,cpp}` gains (public, declared in the header):

```cpp
#include <QSettings>
EditorViewState loadEditorViewState(const QSettings &settings);
void saveEditorViewState(QSettings &settings, const EditorViewState &state);
```

Implementation moves today's `MainWindow` anonymous-namespace helpers
(`mainwindow.cpp:81-119`: `loadDrawerHeight`, `loadEditorDrawerState`,
`saveEditorDrawerState`) and the five key constants (`mainwindow.cpp:62-66`) into
`editorviewstate.cpp`'s anonymous namespace, plus the row codec transplanted verbatim from
`viewsidecar.cpp:42-173,232-269` (`decodeInteger`, `decodeRowNumber`, `isControllerNumber`,
`decodeRowId`, `isValidRowId`, `encodeRowId`, `decodeLane`, `encodeLane`, `encodeRows`,
`encodeLanes`, `encodeHiddenLanes`, `Geometry::resolve` → `layout::fontPx(7/3)` min,
`layout::fontPx(32/3)` max, `clampAutomationRowHeight`). The `view`-object helpers
(`decodeNumber`, `decodeTick`, `finiteOrDefault`, `existingRoot`) die with the sidecar.

Keys (all under the default `QSettings` scope; `MainWindow` passes `*m_themeSettings`):

| Key | Type | Load rule | Save rule |
|---|---|---|---|
| `editorDrawer/velocityVisible` | bool | `value(key, true).toBool()` | always `setValue` |
| `editorDrawer/velocityHeight` | int | `contains` && `toInt` ok && > 0, else `nullopt` | set if present, else `remove` |
| `editorDrawer/automationVisible` | bool | `value(key, true).toBool()` | always `setValue` |
| `editorDrawer/automationHeight` | int | same as velocityHeight | same |
| `editorDrawer/activePage` | string | `"velocity"` → `Velocity`, else `Automations` | `"velocity"` / `"automations"` |
| `editorDrawer/automationLanes` | QByteArray | canonical JSON below; malformed ⇒ lane defaults | always `setValue` of compact JSON |

`editorDrawer/automationLanes` canonical value
(`QJsonDocument::toJson(QJsonDocument::Compact)` of exactly):

```json
{"laneHeight":0,
 "laneHeights":{"cc:0:74":37},
 "laneRanges":{"tempo":90},
 "emptyLanes":[{"track":0,"cc":1}],
 "hiddenLanes":[{"track":1,"cc":7}]}
```

- `laneHeight`: `decodeInteger(_, 0, INT_MAX)`; `0` keeps the layout default; otherwise
  `clampAutomationRowHeight` (values below min clamp **up**, above max clamp **down**).
- `laneHeights`: object keyed by row key; each valid entry clamped like `laneHeight`;
  invalid entries dropped silently.
- `laneRanges`: object keyed by row key; `decodeInteger(_, 0, 127)`; invalid dropped.
- `emptyLanes` / `hiddenLanes`: arrays of `{"track":0..15,"cc":<controller number>}`;
  invalid entries dropped; `hiddenLanes` preserves array order via `hideLane()` appends
  (duplicates rejected by `hideLane`).
- Row key grammar (verbatim from `viewsidecar.cpp:90-119`): `"tempo"`, or
  `"cc:<track>:<cc>"` with decimal integers, no leading zeros, `track` ≤ 15, `cc` ≤ 255 and
  a controller number (`0..127`, `CoreTimeDefaults::kLaneCcBend`, or `xcmd::isLaneController`);
  `"voice:*"` and every other prefix are rejected.

Malformed-value behavior (normative):

| Input | Result |
|---|---|
| Key missing | that field keeps its `EditorViewState{}` default |
| `automationLanes` not parseable JSON / not an object / wrong QVariant type | all lane fields default; the five drawer keys still load |
| Unrecognized object key inside the JSON | ignored |
| Invalid row key, out-of-range integer, non-integer | that entry dropped (objects) / dropped (array element) |
| Duplicate row key in a JSON object | `QJsonObject` semantics: last wins |
| Duplicate lane in `hiddenLanes` | second occurrence dropped (`hideLane` returns false) |

`saveEditorViewState` always writes all six keys (an empty lane state serializes as
`"laneHeight":0` + empty objects/arrays; the key is never removed).

## 4. Transport sums and structs (exact before → after)

`src/project/projectworkspace.h`:

| Symbol (today) | After |
|---|---|
| `#include "ui/viewsidecar.h"` (:19) | deleted |
| `struct SidecarStage { song; loaded; snapshot; }` (:161-165) | deleted |
| `struct SongSaved { song; savedSnapshot; flagsWritten; sidecarSaved; sidecarError; }` (:170-176) | `{ SongName song; SongSaveSnapshot savedSnapshot; bool flagsWritten = false; }` |
| `enum class SongStage { Midi, Voicegroup, Sidecar, Reconcile, Save }` (:178) | `{ Midi, Voicegroup, Reconcile, Save }` — `Sidecar` enumerator deleted |
| `SongPayload = variant<MidiStage, SidecarStage, VoicegroupBound, SongSaved, SongFailed>` (:185) | `variant<MidiStage, VoicegroupBound, SongSaved, SongFailed>` |
| `SaveSongInput { song; snapshot; sidecarSnapshot; voicegroup; }` (:205-210) | `{ SongName song; SongSaveSnapshot snapshot; std::optional<SaveVoicegroupInput> voicegroup; }` |
| `SaveSidecarInput` (:211-216) | deleted |
| `SampleRead::sidecarLoaded/sidecar`, `SampleCommitted::sidecarSaved/sidecarError` (:115-126) | retained (sample sidecar) |

`src/project/projectio.h`: `SidecarWriteResult` (:40-45) deleted; `ProjectCommand`
(:52-58) drops `ReadSidecarCommand` and `SaveSidecarInput`; `ProjectResult` (:73-78) drops
`SidecarStage` and `SidecarWriteResult`. `src/project/projectio.cpp`: visitor arms
`ReadSidecarCommand` (:101-103) and `SaveSidecarInput` (:108-110) deleted; `loadSong` drops
the sidecar load/stage (:205-207) and its comment (:185-188) is rewritten; `readSidecar`
(:266-271), `writeSidecar` (:322-331) deleted; `saveSong` ends
`return SongSaved{input.song, std::move(input.snapshot), flagsWritten};` (sidecar write and
comment :277-280, :312-319 removed); `Sidecar::ensureDir` trash path (:511-520) and
`SongRegistry::removeSongSidecar` (:527) retained; sample sidecar paths (:648-680) retained.

Publication order after cutover — successful load: `MidiStage` → (keyed `LoadedBankView`
when a bank binds) → terminal `VoicegroupBound`; a failure publishes exactly one terminal
`SongFailed`. Semantic save: optional bank view, then MIDI, then flags, then one terminal
`SongSaved`/`SongFailed` — no trailing cosmetic write, no sidecar fields on `SongSaved`.

## 5. State transitions (normative pseudocode)

### 5.1 Startup load

```
MainWindow ctor:  (no member, no mirror)
  buildUi() → constructs WorkspaceUi (recipe placeholder tabs get EditorViewState{} defaults)
            → immediately after m_workspace construction:
                m_workspace->setEditorViewState(loadEditorViewState(*m_themeSettings));
  later connect(m_workspace, &WorkspaceUi::editorViewStateChanged,
                this, &MainWindow::persistEditorViewState);
```
The initial push happens before the connect exists, so startup never writes `QSettings`
(guard I3; the push also cannot differ from the store it read).

### 5.2 Tab creation (`WorkspaceUi::createTab`, today `workspaceui_tabs.cpp:37`)

```
tab->view().applyEditorViewState(m_editorViewState);   // was applyEditorDrawerState
```
A new tab is born as an applied projection; no per-tab defaults survive for global fields.

### 5.3 Editor mutation (any source: drawer toggles, page cache edits, lane menus)

```
SongView mutator / drawer cache → SongView::setEditorViewState(state)      (the one-way sink)
  guard: m_editorViewState == state → return
  assign; emit editorViewStateChanged(state)
WorkspaceUi::wireTab lambda (selected tab only):
  WorkspaceUi::setEditorViewState(state)                                   (the hub seam)
    guard: m_editorViewState == state → return            // echo + no-op terminator
    m_editorViewState = state                             // assign BEFORE fan-out
    for each open tab: tab->view().applyEditorViewState(state)
    emit editorViewStateChanged(state)                    // exactly once, after fan-out
MainWindow::persistEditorViewState(state):
    saveEditorViewState(*m_themeSettings, state);         // QSettings write-through, nothing else
```
`SongView::applyEditorViewState(state)` early-returns when `m_editorViewState == state`
(preserves today's origin-tab behavior: no `cancelActiveInteractions` churn). Emission
points are exactly `SongView::setEditorViewState` and `SongView::applyEditorViewState` (on
change); `EditorDrawer::setViewState`/`syncViewState` remain silent adopters.

### 5.4 Track remap (`SongView::onTracksRemapped`, `trackvoiceops.cpp:414-421`)

After the deliberate silent batch commits `remapEngineTracks`, call
`setEditorViewState(m_editorViewState)` so remapped lane maps reach the hub and the store;
`remapEngineTracks() == false` (rejected remap) leaves the state unchanged and the guards
suppress everything.

### 5.5 Fresh song load (new tab, or open of a song with no ready tab)

```
WorkspaceUi::applyStagedUpdate(MidiStage):           // tombstone / unmatched / rebindSkip rules unchanged
  tab->applyMidiStage(info, smf, trackBudget):
    restored = nullopt                                // m_ready was false → nothing to keep
    reset stage flags; m_voicegroupId.reset()
    m_view->prepareForSongReplacement(); m_view->setEnabled(false)
    adoptSmf failure → m_presentationError = error; return   // tab stays unready, no partial bind
    setTrackBudget; m_midiBound = true
    m_timeline = buildTimeline; m_view->setDocument(&m_document); m_view->setSong(timeline, nullptr)
    m_voicegroup = {}
    m_view->resetScrollPosition()                     // canonical home (decision 3)
    updateReadiness()
```
Global `EditorViewState` is untouched at bind: the view's projection already matches the hub
(§5.2), and `setSong` rebuilds drawer pages from it. `PendingLoad`, `ScrollPosition`,
`m_pendingLoad`, and `applySidecarStage` are deleted; readiness is
`m_midiBound && m_voicegroupBound` (`m_sidecarBound` deleted, `songtab.h:66-67,137-139`,
`songtab.cpp:142-148`).

### 5.6 Ready-tab reload (re-open of the selected/any ready tab's song)

Same as §5.5 except the head:
```
restored = m_view->viewState()      // captured BEFORE prepareForSongReplacement; complete
                                    // live ViewState, not only scroll (decision 3)
...
if (restored) m_view->applyViewState(*restored)       // full camera/grid/cursor restore
```
`applyViewState` keeps its existing clamping (`viewstate.cpp`/`songview.cpp:418-449`):
zoom clamp, key-height clamp, denominator whitelist, cursor ≤ length, used-track check,
scroll clamp, event-list apply. A rebind-skip reload (`m_rebindSkip`, cfg change) still
drops `MidiStage` in `WorkspaceUi` and keeps the live tab untouched.

### 5.7 Semantic save

`WorkspaceUi::submitSaveForTab` (`workspaceui_tabs.cpp:440`):
`SaveSongInput input{name, tab->captureSaveSnapshot(), std::nullopt};` — no
`captureViewSnapshot()`. `SongSaved` handling (`workspaceui_tabs.cpp:285-304`) drops the
`sidecarError` branch; the status message is plain `tr("Saved %1")`. Save ends at flags;
`.porydaw/<song>.json` is not touched by the save path.

### 5.8 Tab close and project switch

`closeTabNow` (`workspaceui_tabs.cpp:503-521`): the in-flight-load tombstone branch stays;
the `else persistViewSidecar(tab)` arm is deleted. `beginProjectSwitch`
(`workspaceui_project.cpp:283-286`): the sidecar comment and `persistSessionViews()` are
deleted; `cleanupPreview()` stays. Closing or switching performs **zero** view/editor I/O.

### 5.9 Application close

`MainWindow::closeEvent` (`mainwindow.cpp:1441-1474`): `m_workspace->persistSessionViews()`
(:1461) deleted; `cleanupPreview()` and the `m_persistSession` geometry/filters block stay.
Tab switch (selection change) remains a no-op for the preference (no traffic, no writes).

## 6. Deletion map

| File | Action |
|---|---|
| `src/ui/viewsidecar.h`, `src/ui/viewsidecar.cpp` | delete files |
| `CMakeLists.txt:319-320` | drop both entries |
| `src/checks/sidecarcheck.cpp` | delete file |
| `src/checks/checkcatalog.cpp:393-401` | delete the `sidecar` catalog entry |
| `src/checks/fwd.hpp:61` | delete `runViewSidecarCheck` declaration |
| `CMakeLists.txt:526` | drop `src/checks/sidecarcheck.cpp` |
| `src/ui/songtab.{h,cpp}` | `#include "ui/viewsidecar.h"`; class comment staged-load story; `applySidecarStage`; `captureViewSnapshot`; `PendingLoad`/`ScrollPosition`/`m_pendingLoad`; `m_sidecarBound` (header + `updateReadiness`) |
| `src/ui/workspaceui.h` | `#include "ui/viewsidecar.h"` (:22); `persistSessionViews` (:149-150); `persistViewSidecar` (:334); `setEditorDrawerState` → `setEditorViewState(const EditorViewState&)` (:192); `editorDrawerStateEdited` → `editorViewStateChanged(const EditorViewState&)` (:242); `applyStagedUpdate(SidecarStage&)` overload (:278); `EditorDrawerState m_editorDrawerState` → `EditorViewState m_editorViewState` (:386) |
| `src/ui/workspaceui.cpp` | `setEditorDrawerState` body → guarded `setEditorViewState` (:382-388, §5.3); `persistViewSidecar` (:422-432); `persistSessionViews` (:475-479); `wireTab` connection retarget (:328-329) |
| `src/ui/workspaceui_tabs.cpp` | `createTab` push (:37); `applyStagedUpdate(SidecarStage&)` (:246-256); `SongSaved` sidecar branch (:293-298); `submitSaveForTab` snapshot arg (:440); `closeTabNow` else-arm (:508-511) |
| `src/ui/workspaceui_project.cpp` | switch comment + `persistSessionViews()` (:283-285) |
| `src/mainwindow.h` | `setEditorDrawerState` (:155) → `void persistEditorViewState(const EditorViewState &);` `EditorDrawerState m_editorDrawerState` (:201) deleted |
| `src/mainwindow.cpp` | key constants + codec (:62-66, :81-119); ctor load (:163); push (:438-439 → §5.1); connect (:531-532); `setEditorDrawerState` (:1000-1007); `closeEvent` call (:1461) |
| `src/ui/songview.h` | `ViewState` comment (:119-120) → "per-tab reload-continuation snapshot; never persisted" (fields unchanged); `applyEditorDrawerState` (:144-145) deleted; `editorDrawerStateChanged` → `editorViewStateChanged(const EditorViewState&)` (:560); sink comment (:146-147) |
| `src/ui/songview/viewstate.cpp` | `applyEditorDrawerState` (:233-240) deleted; `setEditorViewState` emits on any change (:226-232); `applyEditorViewState` equality early-return + new signal (:241-252); `addEmptyLane`/`removeEmptyLane`/`setLaneDisplayRange` unchanged callers |
| `src/project/projectworkspace.h`, `src/project/projectio.{h,cpp}` | §4 table |
| `src/ui/songview/trackvoiceops.cpp` | §5.4 sink call |

## 7. Retained sidecar responsibilities (unchanged, verified anchors)

| Responsibility | Owner | Evidence |
|---|---|---|
| `.porydaw/` creation + `.gitignore` append | `src/project/sidecar.{h,cpp}` `Sidecar::ensureDir` | `projectio.cpp:512`, `mainwindowroutingcheck.cpp:550` |
| Registration meta in `.porydaw/<song>.json` | `SongRegistry::saveRegistrationMeta/loadRegistrationMeta/clearRegistrationMeta` | `songregistry.cpp` (registration functions) |
| Whole-file removal on song delete | `SongRegistry::removeSongSidecar` | `projectio.cpp:527` |
| Sample provenance `.porydaw/samples/` | `SampleRegistrar::read/write/removeSampleSidecar`; `SampleRead::sidecarLoaded`; `SampleCommitted::sidecarSaved/sidecarError` | `projectio.cpp:648-680` |
| Voicegroup previews `.porydaw/vgpreview/` | `ProjectIo` preview flow | unchanged |
| Trash `.porydaw/trash/` | `ProjectIo` delete | `projectio.cpp:511-520` |

Legacy `.porydaw/<song>.json` files with stale `view`/`editor` objects: never read, never
rewritten by the view path; the registration codec inside `SongRegistry` keeps its existing
read/merge behavior and is out of scope.

## 8. Phases, roles, and file ownership

Rules for every step: contract-pinned (transcribe §3-§7; no design decisions at
implementation time); compile-gated (exhaustive visitors turn any missed arm into an error);
verification ownership — slice agents run no formatters, linters, or suites; the integration
owner runs the named gates once per integration point.

```
P1 (transport) ─┐
                ├─► [G1 qt-cpp-reviewer] ─► P3a ─┐
P2 (UI seam)  ──┘                               ├─► integrate ─► [G2 qt-cpp-reviewer]
                                                ├─► P3b ─┤       ─► [G3 thermo-nuclear-reviewer]
                                                ├─► P3c ─┤       ─► final verify + smoke
                                                ├─► P3d ─┘
                                                └─► P3e (docs)
```

| Step | Role | Exclusive files | Change |
|---|---|---|---|
| P1 | `task` | `src/project/projectworkspace.h`, `src/project/projectio.h`, `src/project/projectio.cpp`, `src/ui/songtab.h`, `src/ui/songtab.cpp` | §4 struct/sum cutover + §5.5/5.6 single-stage `applyMidiStage`; update staged-load comments (`songtab.h:29-40`, `projectio.cpp:185-188,277-280,322-323`) |
| P2 | `task` | `src/ui/editorviewstate.{h,cpp}`, `src/ui/workspaceui.h`, `src/ui/workspaceui.cpp`, `src/ui/workspaceui_tabs.cpp`, `src/ui/workspaceui_project.cpp`, `src/mainwindow.h`, `src/mainwindow.cpp`, `src/ui/songview.h` (comment + signal + `applyEditorDrawerState` removal), `src/ui/songview/viewstate.cpp`, `src/ui/songview/trackvoiceops.cpp`, `src/ui/viewsidecar.{h,cpp}` (delete), `CMakeLists.txt` (sources block :319-320 only) | §3 codec; §5.1-5.4, 5.7-5.9; §6 UI rows; `QSettings` write-through (I1-I6) |
| P3a | `sonic` | `src/checks/projectiocheck.cpp`, `src/checks/projectworkspacecheck.cpp`, `src/checks/tabcheck.cpp`, `src/checks/sessioncheck.cpp`, `src/checks/hostcheck.cpp` (compile repairs only) | §9 matrix rows B/E/H + in-code comments (`sessioncheck.cpp:31-33`, `tabcheck.cpp:47-49`) |
| P3b | `task` | `src/checks/mainwindowroutingcheck.cpp` | §9 rows A/C/D/F/G scenario rewrites |
| P3c | `task` | `src/checks/selftest.cpp` | §9 row G selftest block |
| P3d | `sonic` | `src/checks/sidecarcheck.cpp` (delete), `src/checks/checkcatalog.cpp`, `src/checks/fwd.hpp`, `CMakeLists.txt:526` | §6 check rows |
| P3e | `task` | `docs/projectio-dress-down-contract.md`, `docs/projectio-dress-down-plan.md`, `docs/projectio-implementation-steps.md`, `docs/time-ruler-loading-plan.md` | §10 supersession edits, each citing this plan |
| INT | integration owner | serialization only | merges P1+P2, then P3a-P3e; runs gates; owns `CMakeLists.txt` sequencing (:319-320 in P2, :526 in P3d — never concurrent) |

File ownership is disjoint across P1/P2 and across P3a-P3e; `workspaceui.*` +
`mainwindow.cpp` stay in the single P2 owner (no internal split). P1 and P2 compile
independently against the app target only after both land (`workspaceui_tabs.cpp` calls
`applySidecarStage` until P2); INT builds the app target at the G1 point.

Review gates:

- **G1 [qt-cpp-reviewer]** after P1+P2: single-stage adoption (no dangling timeline borrow,
  viewState captured before `prepareForSongReplacement`), echo termination per I5, one
  `QSettings` write per change with no mirror member, readiness = Midi+VoicegroupBound,
  tombstone/rebindSkip behavior unchanged. Blocking: any reachable per-song view writer.
- **G2 [qt-cpp-reviewer]** after P3 integration: `QSettings` is the single store; fan-out
  covers every open tab, future tabs, and relaunch; boundary I/O absence scenarios real
  (byte-identity, not weakened barriers); `waitForTabReady`/`waitForProjectReady` drains kept.
- **G3 [thermo-nuclear-reviewer]** after G2: deletion-test depth — removal forces default
  application at exactly one seam (the codec load); reject compat readers, migration,
  shims, second stores, extra guards, source-text-coupled tests, new harness files, or net
  growth of `mainwindowroutingcheck.cpp` (deleted persistence assertions must pay for the
  new ones).

## 9. Check rewrite matrix

| # | Harness / anchor (today) | Action | Step |
|---|---|---|---|
| A | `mainwindowroutingcheck.cpp:141-254` `checkStagedLoadCoalescing` (include :52; probe calls :160,:170,:220,:232; staged snapshot :193-218; assertions :235-254) | Rewrite: drop `applySidecarStage` and the staged snapshot. After `applyMidiStage` alone assert: timeline binding swapped, `view().document() == &tab->document()`, camera equals canonical fresh-open defaults (zoom home, clock-grid floor, straight feel, event list off), drawer/lane state equals the seeded global state, `!isReady()` until `applyVoicegroupBound`. Re-delivering the same `MidiStage` rebinds cleanly (no residue). Probe seeding `applyEditorDrawerState` (:160) becomes `applyEditorViewState` | P3b |
| B | `projectiocheck.cpp` ordered-result expectation (:326-330); sidecar-read scenario (:377-384); save block (:442-443, :451-500, :560-561, :578-581) | Drop `SidecarStage` from the ordered result; delete the standalone sidecar-read scenario; rewrite :451-500 as: seed `.porydaw/<song>.json` with `registration` + stale `view`/`editor`, run the semantic save, assert `SongSaved` with no sidecar fields and the file byte-identical afterwards | P3a |
| C | `mainwindowroutingcheck.cpp` reload coverage (host-integration block, today :1090-1152) | Set distinctive scroll + zoom + grid + cursor on the ready tab, `requestSongOpen`, await ready, assert the **complete** `ViewState` returned and the binding swapped; fresh tab open after close asserts `resetScrollPosition()` home (no cross-tab/cross-reopen leakage) | P3b |
| D | `mainwindowroutingcheck.cpp` drawer fan-out (:341-470 pattern; seeding :658-663) | Generalize to the full global state: drawer chrome **and** lane state (`laneHeight`, a row height, a range, an empty lane, an ordered hidden lane). Mutate on tab B → visible on tab A without reload → survives `selectSongTab` round-trip → adopted by a newly opened tab; assert `QSettings` holds the exact six keys | P3b |
| E | `sessioncheck.cpp` relaunch block (today ends ~:171); header comment :31-33 | New block after relaunch: seed distinctive global state (incl. lanes), close, construct fresh `MainWindow`, assert every value restored; delete the "closing writes view sidecars" comment | P3a |
| F | `mainwindowroutingcheck.cpp` boundary blocks (:548-608 close; :1105-1237 replacement/switch/app-close) | Invert every `ViewSidecar::load`/`sameLaneState` persistence assertion (:543-546, :586-608, :1115-1119, :1144-1152, :1164-1169, :1223-1237) into: `.porydaw/` listing + file bytes identical across tab close, song replacement, project switch, and app close; no `<song>.json` created for a song that never had one; MIDI bytes, revision, undo count unchanged. Keep a seeded `registration`-only `<songB>.json` byte-identical | P3b |
| G | `mainwindowroutingcheck.cpp:549-556` seeding; `selftest.cpp:454-497` | Legacy-ignore scenario: seed well-formed `registration` + stale/malformed `view`/`editor` (incl. `"view": "not-an-object"`, `"editor": 7`); open → ready with global/default editor state, no `96`/`999` leakage, close leaves bytes identical. `selftest`: replace the `ViewSidecar` round trip with `saveRegistrationMeta`/`loadRegistrationMeta` round trip + a `QSettings` codec round trip (`saveEditorViewState` → mutate → `loadEditorViewState` → equality, incl. clamping and malformed-JSON defaults) | P3b / P3c |
| H | `projectworkspacecheck.cpp`: include :16; silent-completion chain :334-337 (`SaveSidecarInput` at :335); reload order :355-362; visitor arms | Replace the `SaveSidecarInput` FIFO probe with a second `CleanupPreviewInput` (still proves silent FIFO advance); drop the `SidecarStage`-second expectation (MidiStage then terminal); delete sidecar arms from exhaustive visitors | P3a |
| I | `tabcheck.cpp:47-49` | Delete the "view sidecars are written into the project on tab close" comment | P3a |
| J | `hostcheck.cpp` | Compile repairs only (renamed signal/sink, `SaveSongInput` arity); behavior assertions unchanged | P3a |
| K | Deletion surface | `sidecarcheck.cpp`, catalog entry, `fwd.hpp` decl, `CMakeLists.txt:526` | P3d |

`rollcheck/` (camera, identity), `pitchbendcheck`, and every other `ViewState` consumer are
**unchanged**: `ViewState` keeps all fields (decision 3 reverses any slimming).

## 10. Documentation supersession (P3e edits, each citing this plan)

Each doc is edited in place; every edited clause gains a pointer to this plan. Locate
clauses by content (today's line anchors in parentheses).

### `projectio-dress-down-contract.md`

- `SidecarStage` struct (:569-573); `SongSaved::sidecarSaved`/`sidecarError` +
  `SongStage::Sidecar` (:581-586); `SongPayload` listing (:592-593) — types/stages deleted;
  payload is `MidiStage | VoicegroupBound | SongSaved | SongFailed`.
- "Missing sidecar is `SidecarStage{loaded:false}`… corrupt entry rewritten fresh"
  (:605-609) — no view sidecar is read; legacy `view`/`editor` JSON is ignored, never
  rewritten; registration-sidecar tolerance stays `SongRegistry` behavior.
- "Publishes MidiStage, then SidecarStage, then terminal VoicegroupBound" (:612-613) —
  load publishes `MidiStage` → (keyed bank view) → terminal `VoicegroupBound`.
- `SaveSongInput::sidecarSnapshot` and the snapshot-recipe sentence (:630-637, :723-727) —
  the recipe is snapshot + optional voicegroup only.
- `SaveSidecarInput` struct and the standalone fire-and-forget paragraph
  (:634-637, :717-721); its `ProjectOperation` slot and fixed `CommandFailure` mapping —
  deleted.
- Cosmetic-sidecar-write stage and its nonfatal status (:729-738) — save ends after MIDI
  and flags; `SongSaved` carries no sidecar fields.
- `SidecarWriteResult` completion (:817-821) and the keyless-operation listing including
  `SaveSidecarInput` (:832-840) — deleted.

### `projectio-dress-down-plan.md`

- `SaveSidecarInput` independent operation (:308-311) and independent submission
  (:495-497) — deleted.
- Worker duty "sidecar load and save" (:356) — duties reduce to registration, sample,
  preview, and trash I/O.
- Staged order (:436-438) and ordered-publication restatement (:547-549) —
  `MidiStage` then terminal `VoicegroupBound`.
- `SidecarWriteResult` completion (:871-875) and workflow-2 sidecar capture (:889-896) —
  deleted; a save captures `SongSaveSnapshot` (+ optional voicegroup) only.
- Acceptance rows *Semantic save*, *Independent sidecar*, *Song failures* (:1021-1026) —
  rewritten: save ends at flags; no independent cosmetic operation; no view stage exists.

### `projectio-implementation-steps.md`

- "Cosmetic sidecar last / nonfatal" contract citations (:153-159) — semantic save ends at
  flags.
- Keyless-operation list including `SaveSidecarInput` and its acceptance ref (:248-252) —
  removed from the list.
- Step 8.2 in full (:283-292) — loses the `SaveSidecarInput` target, the
  `MidiStage → SidecarStage → VoicegroupBound` contract, and the corrupt-sidecar clause;
  the load contract becomes single-stage adoption per §5.5.

### `time-ruler-loading-plan.md`

- Invariant "until the replacement timeline and sidecar are applied" — "until the
  replacement timeline is applied".
- Invariant "loading state is not persisted as a song sidecar snapshot" — superseded by
  the stronger global rule: no per-song view/editor state persists anywhere; loading and
  camera state never reach disk.
- Fresh-load section (:158-163) — "while MIDI and voicegroup stages arrive"; the MIDI bind
  applies application-global preferences and the canonical camera home atomically.
- Reload section (:165-170) — bind the replacement timeline and restore the retained
  in-memory `ViewState` at the existing staged-load seam.
- Close-and-reopen (:172-175) — always the normal pre-roll home with current
  application-global preferences.
- Step 3 acceptance "sidecar zoom semantics" (:243-248) — the per-tab zoom preference
  remains pixels per beat and is never persisted.
- Non-goals naming sidecar schema / persisting placeholder camera (:381-389) — there is no
  sidecar schema; preferences persist once, globally, via `QSettings`; placeholder camera
  state still never persists.
- Verification-matrix row "reload retains current ruler and camera" is retained verbatim;
  its backing scenario is §9 row C.

In-code comment supersessions ride with P3a (`sessioncheck.cpp:31-33`, `tabcheck.cpp:47-49`).

## 11. Required negative-scan outcomes

Stated as required end-state properties (any search method may demonstrate them); all must
hold over `src/` and `CMakeLists.txt` after P3 integration:

1. The token `ViewSidecar` appears nowhere; `src/ui/viewsidecar.h`, `src/ui/viewsidecar.cpp`,
   `src/checks/sidecarcheck.cpp` do not exist; `viewsidecar`/`sidecarcheck` appear nowhere in
   `CMakeLists.txt`.
2. `SidecarStage`, `SaveSidecarInput`, `SidecarWriteResult`, `SongStage::Sidecar`,
   `ReadSidecarCommand` appear nowhere.
3. `persistViewSidecar`, `persistSessionViews`, `captureViewSnapshot`, `applySidecarStage`,
   `applyEditorDrawerState`, `editorDrawerStateChanged`, `editorDrawerStateEdited`,
   `setEditorDrawerState`, `m_editorDrawerState`, `loadEditorDrawerState`,
   `saveEditorDrawerState`, `check-sidecar`, `runViewSidecarCheck` appear nowhere.
4. `sidecarSnapshot`, `sidecarSaved`, `sidecarError` appear only inside the retained sample
   sidecar surface (`SampleRead`, `SampleCommitted`, `SampleRegistrar`).
5. Retained tokens survive and are untouched: `Sidecar::ensureDir`, `SampleSidecar`,
   `saveRegistrationMeta`, `loadRegistrationMeta`, `clearRegistrationMeta`,
   `removeSongSidecar`.
6. The only `editorDrawer/` QSettings key strings in `src/` are the six keys inside
   `editorviewstate.cpp`; `deno task checks --filter sidecar` reports an unknown filter
   rather than a passing harness.
7. No new `*check.cpp` file exists; `src/` top-level still holds exactly `main.cpp`,
   `mainwindow.cpp`, `porydaw_scale.cpp`.

## 12. Forbidden alternatives

- Any reader/writer/migration for legacy `view`/`editor` JSON, a replacement editor-only
  sidecar, an `EditorSidecar` type, a compat shim, or a deprecated alias.
- A second mutable global store, a `MainWindow` mirror member, an `EditorPreferencesStore`
  abstraction, or renaming existing `editorDrawer/*` keys.
- Persisting any `SongView::ViewState` field (grid, zoom, event list included) or
  globalizing per-row state beyond `EditorViewState`.
- Keeping `SaveSidecarInput`, `SidecarStage`, `SongStage::Sidecar`, or a no-op
  `applySidecarStage` stub "temporarily".
- Moving sidecarcheck scenarios into `ignorecheck`/`samplecheck`, creating a new harness
  file, or tests asserting private members (`m_pxPerBeat`, …) instead of the `QSettings`
  store and public accessors.
- Weakening `waitForTabReady`/`waitForProjectReady` drains, or keeping scroll-exclusion
  persistence tests (scroll retention is now a positive in-memory reload assertion, §9 row C).

## 13. Acceptance matrix

| Contract item | Observable acceptance |
|---|---|
| Global persistence | Mutating any global field writes all six keys exactly once; relaunch restores them without a project (§9 E) |
| Fan-out | Every open tab, a tab switched away and back, and a newly created tab show identical state within one pass (§9 D) |
| Reload continuity | In-place reload preserves the complete live `ViewState`; fresh open/reopen starts canonical home (§9 C) |
| Boundary absence | `.porydaw/` listing + bytes identical across close, replacement, switch, app close; saves leave `<song>.json` untouched (§9 B/F) |
| Legacy ignore | Stale or malformed `view`/`editor` JSON neither loads nor breaks open; registration behavior intact; bytes never rewritten (§9 G) |
| Ordering | Load publishes `MidiStage` → (bank view) → terminal `VoicegroupBound`; failure = one `SongFailed`; save ends at flags with bare `SongSaved` (§9 B/H) |
| Readiness | `isReady()` exactly after Midi+VoicegroupBound; interaction gate unchanged (§9 A) |
| Retained sidecars | `ignorecheck`, `samplecheck`, `onboardcheck`, `vgcheck`, `vgbankcheck`, `rollcheck` pass unmodified |
| Codec | Round trip, clamping (row heights to `fontPx(7/3)..fontPx(32/3)`), ordered `hiddenLanes`, malformed defaults (§9 G, §3) |
| Deletion | §11 scans hold; no new harness; `mainwindowroutingcheck.cpp` does not net-grow |

## 14. Final verification (integration owner only)

```sh
deno task build:checks
deno task verify --filter projectiocheck --verbose
deno task verify --filter projectworkspacecheck
deno task verify --filter tabcheck
deno task verify --filter mainwindow-routing
deno task verify --filter host-integration
deno task verify --filter sessioncheck
deno task verify --filter selftest
deno task verify --filter ignorecheck
deno task verify --filter samplecheck
deno task verify --filter onboardcheck
deno task verify --filter vgcheck
deno task verify --filter vgbankcheck
deno task verify --filter rollcheck
deno task verify
deno task format --check <changed files>
```

Native smoke (built app, scratch decomp project): open two songs as tabs — both render the
ordinary ruler immediately; `.porydaw/` gains no files. Change drawer page/height, lane
height, a hidden lane on tab B → tab A reflects it live; a third tab adopts it; `QSettings`
shows the six keys. In-place reload keeps camera and scroll; closing and reopening the song
starts at the pre-roll home. Quit and relaunch → every editor preference returns. Delete a
song → `.mid` lands in `.porydaw/trash/`; register a song → `registration` appears in its
`.porydaw/<song>.json`.

## 15. Completion criteria

1. §11 negative scans all hold; §6 deletions are complete with no forwarding remnants.
2. §13 acceptance rows are observably satisfied by the named checks, and the full
   `deno task verify` suite is green with the sidecar harness absent.
3. G1-G3 reviewer gates closed with no blocking findings.
4. §10 doc edits landed; no clause in the four authoritative documents contradicts this plan.
5. No TBDs, no temporarily-stubbed symbols, no compatibility code anywhere in the diff.
