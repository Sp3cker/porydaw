# Per-Song View Sidecar Removal — Implementation Plan

## Status

Normative implementation spec for this wave. It supersedes every conflicting sidecar clause in
`docs/old/projectio-dress-down-contract.md` and `docs/old/projectio-dress-down-plan.md`; those two
documents are mechanically reconciled in
P3e. `docs/time-ruler-loading-plan.md` is **reconciled now**, outside P3e: it no longer depends on
`SidecarStage`, persisted camera state, or a global camera. This plan neither changes nor accepts
static/pre-bind ruler behavior. Grounded line anchors below are pre-change locations; symbol names
remain authoritative after line drift.

This plan also supersedes the conflicting GlobalEditorSeam alternatives: there is no
`EditorPreferences` subset, no `editorGrid/*` keys, no `editorDrawer/laneRowHeight` key, and no
codec in `mainwindow.cpp`. The promoted preference is exactly the existing, complete
`EditorViewState`, including its row maps and ordered hidden lanes. No compatibility path remains.

## 1. Fixed decisions

1. The complete `EditorViewState` is one application-global persisted preference: flat drawer
   fields (`velocity`, `automation`, `voiceChanges`, `activePage`), `laneHeight`, `laneHeights`, `laneRanges`,
   `emptyLanes`, and ordered `hiddenLanes()`.
2. Every `SongView::ViewState` field remains transient and per tab: `pxPerBeat`, `keyHeight`,
   `scrollPx`, `scrollY`, `selectedTrack`, `editCursorTick`, `gridMinDenom`, `gridTriplet`, and
   `eventList`. No one persists or fans out any of them.
3. A ready-tab reload captures and reapplies the complete live `ViewState`. A fresh open or reopen
   after close starts the canonical defaults specified in §5.6.
4. `ViewSidecar` is deleted. There is no reader, writer, migration, replacement sidecar, shim,
   alias, or deprecated path. Legacy per-song `view`/`editor` JSON is ignored by the view path and
   never rewritten by it.
5. Existing `.porydaw` owners remain: `Sidecar::ensureDir`, registration metadata, sample
   provenance sidecars, previews, trash, and whole-file deletion on song deletion.
6. `WorkspaceUi::m_editorViewState` is the sole mutable in-memory global. `MainWindow` loads from
   and writes through exactly `*m_themeSettings`, with no mirror. Each `SongView` is a projection.
7. The seven existing `editorDrawer/*` entries keep their spelling and semantics. Former sidecar
   lane fields occupy one additional `QByteArray` entry, `editorDrawer/automationLanes`.

## 2. Ownership and invariants

| State | Mutable owner | Persistence |
|---|---|---|
| Complete `EditorViewState` | `WorkspaceUi::m_editorViewState` | global `QSettings`, exactly `*MainWindow::m_themeSettings` |
| Complete `SongView::ViewState` | its `SongView` | none; `SongTab` borrows one value snapshot only during ready reload |
| Drawer/page runtime caches | `EditorDrawer` and pages | none; silent projection caches |
| Selection, gesture state, mute/solo, event-list mirror | existing per-tab/UI owners | none |
| Registration/sample/preview/trash data | existing project owners | unchanged `.porydaw` paths |

- **I1 — single owner:** no second mutable `EditorViewState`, `EditorPreferences`, or MainWindow
  mirror exists.
- **I2 — synchronous projection:** after one semantic editor mutation, all open tabs and all later
  tabs equal the hub in one synchronous pass. No `ViewState` crosses tabs.
- **I3 — one store:** startup performs zero writes. Each later semantic editor change calls
  `saveEditorViewState(*m_themeSettings, state)` exactly once.
- **I4 — no project UI I/O:** open/save/close/reload/switch/quit do not read or write view/editor
  project JSON.
- **I5 — acyclic signals:** only an origin commit emits from `SongView`; projection is silent; the
  hub emits once after fan-out. Equality guards terminate no-ops.
- **I6 — GUI thread:** the hub, projections, and QSettings sink run synchronously on the GUI
  thread and never cross into the audio engine thread.

## 3. Global QSettings codec

### 3.1 Public seam and store

`src/ui/editorviewstate.h` adds only a forward declaration and two free functions; it does not
include `<QSettings>`:

```cpp
class QSettings;

EditorViewState loadEditorViewState(const QSettings &settings);
void saveEditorViewState(QSettings &settings, const EditorViewState &state);
```

`src/ui/editorviewstate.cpp` includes `<QSettings>` and owns every key literal and private codec
helper. `MainWindow` passes `*m_themeSettings`; no new QSettings instance, subgroup, prefix,
preferences object, or shadow value is allowed.

The codec owns the eight key constants and drawer helpers moved from `mainwindow.cpp:62-66,81-119`.
It reuses the row grammar and validation from `viewsidecar.cpp:42-173,232-269`, replacing
`Geometry::resolve` bounds with `layout::fontPx(7.0 / 3.0)` and
`layout::fontPx(32.0 / 3.0)`. View/camera JSON helpers die with `ViewSidecar`.

### 3.2 Exact eight-entry schema

| Entry | Load | One save call |
|---|---|---|
| `editorDrawer/velocityVisible` | `value(key, false).toBool()` | one `setValue` |
| `editorDrawer/velocityHeight` | present, integer-convertible, and `> 0` → value; otherwise `nullopt` | exactly one `setValue` when present, otherwise one `remove` |
| `editorDrawer/automationVisible` | `value(key, true).toBool()` | one `setValue` |
| `editorDrawer/automationHeight` | same optional rule | exactly one `setValue` when present, otherwise one `remove` |
| `editorDrawer/voiceChangesVisible` | `value(key, false).toBool()` | one `setValue` |
| `editorDrawer/voiceChangesHeight` | same optional rule | exactly one `setValue` when present, otherwise one `remove` |
| `editorDrawer/activePage` | exact `"velocity"` → `Velocity`; exact `"voiceChanges"` → `VoiceChanges`; all other/missing values → `Automations` | one `setValue` of `"velocity"`, `"voiceChanges"`, or `"automations"` |
| `editorDrawer/automationLanes` | must be a `QByteArray` containing a JSON object; otherwise all lane fields default | one `setValue` of compact canonical JSON |

Thus each semantic change invokes `saveEditorViewState` once. That call touches only these eight
entries: five mandatory `setValue` operations and one `setValue`-or-`remove` operation for each of
the three optional heights. Optional height entries exist iff their state values exist. “All eight keys are
present” is not an acceptance condition.

### 3.3 Exact compact lane blob

The `automationLanes` value is `QJsonDocument(object).toJson(QJsonDocument::Compact)`, stored as a
`QByteArray`, with exactly these members and no `view`, zoom, grid, drawer, or registration data:

```json
{"laneHeight":0,"laneHeights":{"cc:0:74":37},"laneRanges":{"tempo":90},"emptyLanes":[{"track":0,"cc":1}],"hiddenLanes":[{"track":1,"cc":7}]}
```

- `laneHeight`: integer `0..INT_MAX`; `0` means layout default, otherwise clamp to
  `layout::fontPx(7.0 / 3.0)..layout::fontPx(32.0 / 3.0)`.
- `laneHeights`: object keyed by row ID; valid integers use the same clamp; invalid entries drop.
- `laneRanges`: object keyed by row ID; valid integer range is `0..127`; invalid entries drop.
- `emptyLanes` and `hiddenLanes`: arrays of `{track,cc}` with track `0..15` and a valid lane
  controller. Invalid elements drop. `hiddenLanes` preserves insertion order and drops later
  duplicates through `hideLane`.
- Row keys are exactly `tempo` or `cc:<track>:<cc>` with decimal integers, no leading zeroes,
  track `0..15`, cc `0..255`, and cc accepted by the existing controller predicate. Tempo rows
  remain valid in keyed maps and identity-fixed during remap; `voice:*` and other prefixes reject.
- Unknown JSON members are ignored. Duplicate object members use `QJsonObject` last-wins behavior.
- Missing blob, wrong QVariant type, empty bytes, invalid JSON, or a non-object defaults all lane
  fields while the five drawer fields still load. A later semantic mutation saves the defaulted
  in-memory state and overwrites the malformed blob with canonical compact JSON: QSettings
  self-heals without a startup write. This never touches per-song JSON.

The compact blob is intentional: it preserves the already-tested row grammar and ordered array in
one atomic QSettings entry. `EditorViewState` nevertheless keeps its existing **flat fields**;
`drawerState()`/`setDrawerState()` remain value adapters, not a second authority. A nested storage
object or JSON string wrapper would duplicate state and is forbidden. Expected growth is private
codec code in the cohesive `editorviewstate.cpp`; only the two free functions enlarge its public
surface.

## 4. Transport cutover

### 4.1 Exact type changes

In `src/project/projectworkspace.h`:

| Before | After |
|---|---|
| `SidecarStage` | deleted |
| `SongSaved{song,savedSnapshot,flagsWritten,sidecarSaved,sidecarError}` | `SongSaved{song,savedSnapshot,flagsWritten}` |
| `SongStage::{Midi,Voicegroup,Sidecar,Reconcile,Save}` | `SongStage::{Midi,Voicegroup,Reconcile,Save}` |
| payload includes `SidecarStage` | payload excludes it |
| `SaveSongInput{song,snapshot,sidecarSnapshot,voicegroup}` | `SaveSongInput{song,snapshot,voicegroup}` |
| `SaveSidecarInput` | deleted |
| sample `sidecarLoaded/sidecarSaved/sidecarError` fields | retained |

`src/project/projectworkspace.cpp` deletes both corresponding visitor/publication paths: publishing
`SidecarStage` around line 112 and mapping/enqueuing `SaveSidecarInput` around line 296. This file
is an explicit production owner; deleting only the header is incomplete.

`src/project/projectio.h` removes `SidecarWriteResult`, `ReadSidecarCommand`, `SaveSidecarInput`,
and their variant alternatives. `src/project/projectio.cpp` removes their visitors, song-sidecar
read/write helpers and calls, and returns bare `SongSaved`. It retains registration, sample,
preview, trash, `.gitignore`, and song-deletion behavior.

A successful load publishes `MidiStage`, then any keyed `LoadedBankView`, then terminal
`VoicegroupBound`. A failure publishes exactly one terminal `SongFailed`. A semantic save performs
optional bank, MIDI, and flags work, then publishes one terminal bare `SongSaved` or `SongFailed`.
There is no cosmetic tail operation.

## 5. UI state transitions

### 5.1 Constructor-injected initial state

Startup is construction, not a signal transaction:

```text
MainWindow constructor:
  initial = loadEditorViewState(*m_themeSettings)
  buildUi(initial)
    WorkspaceUi(..., const EditorViewState &initial) initializes
      m_editorViewState(initial) before creating recipe/session placeholder tabs
    each created tab silently applies m_editorViewState
  connect WorkspaceUi::editorViewStateChanged to MainWindow::persistEditorViewState
```

There is no startup call to the mutating hub setter, no blocker flag, and no reliance on a
connection being temporarily absent to suppress a write. `WorkspaceUi` receives its initial state
through its constructor and emits nothing. `MainWindow` retains no copy after construction.

### 5.2 New tab projection

`WorkspaceUi::createTab` (`workspaceui_tabs.cpp:37`) calls
`tab->view().applyEditorViewState(m_editorViewState)`. Projection is silent. A new tab cannot retain
per-tab defaults for global fields.

### 5.3 Origin, projection, and all-tab hub

```text
SongView::setEditorViewState(next)                 // origin commit only
  if m_editorViewState == next: return
  m_editorViewState = next
  update drawer/pages/widgets once
  emit editorViewStateChanged(next)                // only SongView emission point

WorkspaceUi::wireTab connection (workspaceui.cpp:231-232)
  accepts editorViewStateChanged from every tab, selected or not
  calls WorkspaceUi::setEditorViewState(next)

WorkspaceUi::setEditorViewState(next)              // sole hub
  if m_editorViewState == next: return
  m_editorViewState = next                         // assign before fan-out
  for every open tab: tab->view().applyEditorViewState(next)
  emit editorViewStateChanged(next)                // exactly once, after fan-out

SongView::applyEditorViewState(next)               // projection only
  if m_editorViewState == next: return
  m_editorViewState = next
  silently update drawer/pages/widgets once
  never emit editorViewStateChanged

MainWindow::persistEditorViewState(next)
  saveEditorViewState(*m_themeSettings, next)
```

`EditorDrawer::setViewState` and page sync remain silent. Origin-tab equality prevents projection
churn and `cancelActiveInteractions`; other tabs receive one silent refresh. Selecting a tab is
irrelevant to propagation. One origin change yields one hub emission and one codec call.

### 5.4 Candidate mutations and remap

No mutator may edit `m_editorViewState` and then call an equality-guarded commit with the same
object. `addEmptyLane`, `removeEmptyLane`, and `setLaneDisplayRange` each:

1. copies `m_editorViewState` to `next`;
2. validates and mutates `next` only;
3. returns if the requested semantic value is unchanged;
4. performs its existing origin-side cache/widget update once through `setEditorViewState(next)`.

Drawer toggles, page cache edits, lane height/range, empty/hide/unhide operations follow the same
candidate rule. Projection never invokes an origin mutator.

`SongView::onTracksRemapped` (`songview/trackvoiceops.cpp:414-421`) copies the complete state to
`next` and calls `next.remapEngineTracks(map)`. If it returns false, reject the whole operation and
publish nothing. If true, commit the other remapped SongView members, then call
`setEditorViewState(next)` **without first assigning `m_editorViewState`**. Tempo identities stay
fixed and duplicate destinations reject atomically. A valid remap that does not change editor state
is suppressed by the origin equality guard. A changed remap from a non-selected ready tab reaches
the hub, every tab, and QSettings once.

### 5.5 Borrow-safe MIDI adoption and complete EditorViewState preservation

`SongTab::applyMidiStage` captures `std::optional<SongView::ViewState> restored` only when the tab
was ready, and does so **before** `prepareForSongReplacement`. After successful SMF adoption:

```text
newTimeline = buildTimeline(...)                   // local shared_ptr owns new timeline
m_view->setDocument(&m_document)                   // old m_timeline still owns old borrow
m_view->setSong(newTimeline.get(), nullptr)         // local owns new; drops old voicegroup borrow
m_timeline = std::move(newTimeline)                 // member now owns new borrow
m_voicegroup.reset()                                // only after setSong(..., nullptr)
apply restored or canonical ViewState              // only after m_timeline owns new timeline
updateReadiness()
```

Do not assign `m_timeline` before `setDocument`/`setSong`; that would leave `SongView` borrowing a
destroyed old timeline during intermediate drawer/header work. Adoption failure leaves the tab
unready without a partial bind. Tombstone, unmatched-result, and rebind-skip behavior remains.
Readiness is exactly `m_midiBound && m_voicegroupBound`; `m_sidecarBound`, `PendingLoad`,
`ScrollPosition`, `m_pendingLoad`, and `applySidecarStage` are deleted.

`SongView::setSong` (`songview.cpp:196-241`) removes the default-construction plus drawer-only
restore at lines 208-210. It preserves the **complete** already-applied `m_editorViewState` and
rebuilds the drawer/pages from that value. Its comments say song attachment preserves the global
editor projection. No fresh bind or ready reload can erase lane maps.

### 5.6 Exact fresh and ready-reload ViewState

A ready reload reapplies, once, all captured fields after the ownership sequence in §5.5:
`pxPerBeat`, `keyHeight`, both scroll axes, selected track, edit cursor, denominator, feel, and
event-list mode. Existing `SongView::applyViewState` clamps at `songview.cpp:418-449`: zoom and key
height to geometry, denominator to `0/4/8/16/32`, cursor to timeline length, selection to a used
track, and both scroll axes to their legal ranges.

A fresh open/reopen applies these exact final defaults before readiness:

- `pxPerBeat = Geometry::resolve().editorDefaultPixelsPerBeat`;
- `keyHeight = Geometry::resolve().velocityHandleMinimumKeyHeight`;
- horizontal scroll = `minHScroll()` (pre-roll home) and vertical scroll =
  `defaultVerticalScroll()` via `resetScrollPosition()` after the default state apply;
- selected track = the first used track selected by `setSong` (0 only when no used track exists);
- `editCursorTick = 0`;
- `gridMinDenom = 0`, `gridTriplet = false` (straight);
- `eventList = false`.

Do not establish an intermediate fresh/default `ViewState` on a ready reload. State is finalized
while the view remains disabled for binding. Applying event-list visibility in that disabled path
must not call `focusContent`; if final visibility changes, update the MainWindow checkbox through
exactly one final `eventListVisibilityChanged` emission, with no intermediate false/true traffic.
Then `updateReadiness` enables interaction at the existing readiness point.

### 5.7 Save, close, switch, and quit

- `submitSaveForTab` creates `SaveSongInput{name, captureSaveSnapshot(), std::nullopt}`; there is
  no view snapshot.
- `SongSaved` handling removes only the sidecar-error status branch at
  `workspaceui_tabs.cpp:286-291`; it retains the close-after-save flow.
- `closeTabNow` removes the `persistViewSidecar` else arm at
  `workspaceui_tabs.cpp:515-516`; the in-flight tombstone path remains.
- `beginProjectSwitch` removes `persistSessionViews`; preview cleanup remains.
- `MainWindow::closeEvent` removes `persistSessionViews`; normal session/theme persistence remains.

These boundaries perform zero view/editor project I/O.

## 6. File/action map

| File | Required action |
|---|---|
| `src/ui/viewsidecar.{h,cpp}` | delete |
| `src/project/projectworkspace.h` | exact §4 sums/structs |
| `src/project/projectworkspace.cpp` | delete SidecarStage publication and SaveSidecarInput visitor/enqueue paths |
| `src/project/projectio.{h,cpp}` | exact §4 command/result and I/O deletion |
| `src/ui/songtab.{h,cpp}` | §5.5/5.6 one-stage, borrow-safe adoption; remove pending sidecar state |
| `src/ui/editorviewstate.{h,cpp}` | exact two-function codec; header forward declaration |
| `src/ui/songview.h` | rename sole signal; remove drawer-only apply API; mark all `ViewState` fields transient |
| `src/ui/songview.cpp` | preserve complete EditorViewState in `setSong`; exact fresh/reload ViewState application behavior |
| `src/ui/songview/viewstate.cpp` | origin/silent projection split and candidate lane mutations |
| `src/ui/songview/trackvoiceops.cpp` | candidate remap publication |
| `src/ui/songview/drawercoordination.cpp` | candidate drawer/page origin mutations through the sole hub |
| `src/ui/workspaceui.{h,cpp}` | constructor injection, sole hub, all-tab wire at `workspaceui.cpp:231-232`; delete persistence APIs |
| `src/ui/workspaceui_tabs.cpp` | creation projection, no SidecarStage, bare save at §5.7 anchors; `destroyAllTabs` keeps QTabWidget selection signals blocked across page detachment/destruction so synchronous hub/selection teardown cannot republish a dying tab after the null selection/engine-unload boundary — a necessary lifecycle side effect discovered by the project-switch boundary check, not a new feature |
| `src/ui/workspaceui_project.cpp` | no switch persistence |
| `src/mainwindow.{h,cpp}` | codec removal, constructor load/injection, exact store sink, no mirror, no close flush |
| `src/checks/sidecarcheck.cpp` | delete |
| `src/checks/checkcatalog.cpp`, `src/checks/fwd.hpp` | delete sidecar registration/declaration |
| `CMakeLists.txt:319-320,526` | INT removes viewsidecar source entries after P2d at INT-PROD and the sidecarcheck entry after P3d at INT-CHECKS |

Retained registration read/merge behavior is unchanged and may pass through unrelated legacy bytes
when registration itself changes; the removed **view path** never triggers such a rewrite.

## 7. Workflowz execution graph, roles, and integration ownership

Execution uses workflowz. Every editing slice has one explicit implementation owner. Shared-file
integration, every `deno task` command, end-state tooling, and native smoke belong only to INT.
Slice agents do not build, format, lint, run checks, or edit `CMakeLists.txt`.

| Slice | Role | Exclusive files (count) | Change |
|---|---|---|---|
| P1a transport | `task` implementation agent | `src/project/projectworkspace.h`, `src/project/projectworkspace.cpp`, `src/project/projectio.h`, `src/project/projectio.cpp` (4) | §4 transport deletion |
| P1b adoption | `task` implementation agent | `src/ui/songtab.h`, `src/ui/songtab.cpp` (2) | §5.5/5.6 |
| P2a codec/store | `task` implementation agent | `src/ui/editorviewstate.h`, `src/ui/editorviewstate.cpp`, `src/mainwindow.h`, `src/mainwindow.cpp` (4) | §3, §5.1, MainWindow sink |
| P2b hub | `task` implementation agent | `src/ui/workspaceui.h`, `src/ui/workspaceui.cpp`, `src/ui/workspaceui_tabs.cpp`, `src/ui/workspaceui_project.cpp` (4) | §5.1-5.3, §5.7 |
| P2c view | `task` implementation agent | `src/ui/songview.h`, `src/ui/songview.cpp`, `src/ui/songview/viewstate.cpp`, `src/ui/songview/trackvoiceops.cpp`, `src/ui/songview/drawercoordination.cpp` (5) | §5.3-5.6 |
| P2d obsolete UI | `task` implementation agent | `src/ui/viewsidecar.h`, `src/ui/viewsidecar.cpp` (2) | delete files |
| P3a transport checks | `task` implementation agent | `src/checks/projectiocheck.cpp`, `src/checks/projectworkspacecheck.cpp`, `src/checks/tabcheck.cpp`, `src/checks/hostcheck.cpp` (4) | transport/order checks and compile repairs |
| P3b UI checks | `task` implementation agent | `src/checks/mainwindowroutingcheck.cpp`, `src/checks/sessioncheck.cpp` (2) | §8 rows A/C/D-F |
| P3c codec checks | `task` implementation agent | `src/checks/selftest.cpp`, `src/checks/selftest/workspace.cpp` (2) | codec round trip/malformed/default coverage and workspace harness compile repair |
| P3d obsolete check | `task` implementation agent | `src/checks/sidecarcheck.cpp`, `src/checks/checkcatalog.cpp`, `src/checks/fwd.hpp` (3) | delete harness and registration |
| P3e docs | `task` implementation agent | `docs/old/projectio-dress-down-contract.md`, `docs/old/projectio-dress-down-plan.md` (2) | mechanical supersession only; no time-ruler edit |
| INT integration | `task` integration owner | `CMakeLists.txt` only (1) | merge every slice, own all gates, remove source entries after P2d and the check entry after P3d |

All slices are contract-pinned and file-disjoint. Every production slice owns at most five files.
P1a/P1b/P2a-P2d are parallel editing slices but deliberately are not independently buildable.
P3a-P3e start only after G1 approves the combined production result. `CMakeLists.txt` belongs only
to INT; no other slice edits it.

The named graph is:

```text
(P1a || P1b || P2a || P2b || P2c || P2d)
  -> INT-PROD
  -> G1
  -> (P3a || P3b || P3c || P3d || P3e)
  -> INT-CHECKS
  -> G2
  -> G3
  -> INT-FINAL
```

### INT-PROD — combined production merge and first build

**Role:** `task` integration owner

INT merges P1a/P1b/P2a-P2d as one observable behavior cutover. It removes only the two
`viewsidecar` source entries from `CMakeLists.txt`, then runs:

```sh
deno task build:app
```

No green intermediate may delete `ViewSidecar` while `setSong` still erases lanes.

### G1 — production Qt/C++ review

**Role:** `qt-cpp-reviewer`

Review the combined production result after `build:app`: signal origin/projection acyclicity,
all-tab propagation, QSettings GUI-thread affinity and single-store semantics, focus behavior,
complete `EditorViewState` preservation, ready/fresh `ViewState` ordering, and timeline/voicegroup
borrow lifetime. Any blocker returns to its named P1/P2 owner. INT re-merges, reruns
`deno task build:app`, and reruns G1. P3 does not start until G1 reports PASS.

### INT-CHECKS — check/doc merge and focused verification

**Role:** `task` integration owner

After G1, INT merges P3a-P3e, removes the `sidecarcheck` entry from `CMakeLists.txt`, and runs these
commands in order:

```sh
deno task build:checks
deno task format --check src/project/projectworkspace.h src/project/projectworkspace.cpp src/project/projectio.h src/project/projectio.cpp src/ui/songtab.h src/ui/songtab.cpp src/ui/editorviewstate.h src/ui/editorviewstate.cpp src/mainwindow.h src/mainwindow.cpp src/ui/workspaceui.h src/ui/workspaceui.cpp src/ui/workspaceui_tabs.cpp src/ui/workspaceui_project.cpp src/ui/songview.h src/ui/songview.cpp src/ui/songview/viewstate.cpp src/ui/songview/trackvoiceops.cpp src/checks/projectiocheck.cpp src/checks/projectworkspacecheck.cpp src/checks/tabcheck.cpp src/checks/hostcheck.cpp src/checks/mainwindowroutingcheck.cpp src/checks/sessioncheck.cpp src/checks/selftest.cpp src/checks/selftest/workspace.cpp src/checks/checkcatalog.cpp src/checks/fwd.hpp
deno task verify --filter projectiocheck --verbose
deno task verify --filter projectworkspacecheck --verbose
deno task verify --filter tabcheck --verbose
deno task verify --filter mainwindow-routing --verbose
deno task verify --filter sessioncheck --verbose
deno task verify --filter selftest --verbose
deno task verify --filter ignorecheck --verbose
deno task verify --filter onboardcheck --verbose
deno task verify --filter samplecheck --verbose
```

If P3a changes `src/checks/hostcheck.cpp`, INT also runs both registered filters:

```sh
deno task verify --filter host-seams --verbose
deno task verify --filter host-adapter --verbose
```

`projectiocheck`, `projectworkspacecheck`, and `tabcheck` cover rows B/H;
`mainwindow-routing`, `sessioncheck`, and `tabcheck` cover rows A/C/D/F; `selftest` covers rows
E/G. `ignorecheck`, `onboardcheck`, and `samplecheck` protect retained `.porydaw` directory,
registration/trash, and sample-sidecar behavior. A failure returns to the exclusive owning slice;
INT re-merges and reruns `build:checks`, the format check, and every affected focused filter.

### G2 — focused-evidence and Qt lifecycle review

**Role:** `qt-cpp-reviewer`

Review the integrated diff together with the focused results and §8 row coverage. Recheck QObject
ownership, signal counts/order, GUI-thread QSettings access, focus suppression, staged adoption,
and borrow release order against the actual checks. Any blocker returns to its exclusive owner.
INT repeats the INT-CHECKS commands affected by the fix, then G2 reruns. G3 does not start until G2
reports PASS.

### G3 — final architecture and complexity review

**Role:** `thermo-nuclear-reviewer`

Review the complete change for contract alignment, deletion-test depth, duplicate stores/codecs,
compatibility residue, conditional growth, cross-file cohesion, and test coupling to observable
behavior. Any blocker returns to its exclusive owner. INT reruns the affected INT-CHECKS commands
and G2 whenever the fix touches Qt lifecycle or behavior, then reruns G3. INT-FINAL does not start
until G3 reports PASS.

### INT-FINAL — full verification and native smoke

**Role:** `task` integration owner

Run:

```sh
deno task verify
```

Then perform the native smoke in §12. The native observations cover rows A/C/D/E/F; rows B/G/H
remain covered by their focused filters. Any failure returns to its exclusive owner; INT reruns
the affected focused commands, G2 or G3 when their reviewed surface changed, the full verify, and
the native smoke until all are green.

## 8. Observable check contract

| Row | Scenario and required observation |
|---|---|
| A fresh bind | Seed the complete global EditorViewState. After MidiStage, binding is swapped and every editor field remains equal. Assert every canonical fresh ViewState default from §5.6, not scroll alone; readiness waits for VoicegroupBound. |
| B transport/save | Ordered load has no SidecarStage; semantic save yields bare SongSaved and leaves seeded registration + stale view/editor file byte-identical. |
| C ready reload/reopen | Seed all nine ViewState fields with distinctive values on a ready tab. Reload preserves all nine and swaps binding. Close/reopen asserts every §5.6 default and no leakage. |
| D all-tab origin | Seed all EditorViewState fields. Mutate tab B while non-selected, including lane identity remap. Assert one SongView origin emission, one hub emission after fan-out, zero projection-origin emissions, every existing/new tab equal, and one QSettings codec invocation. Rejected and editor-unchanged remaps publish nothing. |
| E relaunch/store | Save chrome, optional heights, active page, lane height/maps/sets/ordered hidden lanes; construct a fresh MainWindow and restore all fields. Optional keys exist iff optional values do. No startup write. |
| F boundary absence | `.porydaw` listing and file bytes are identical across close, reload, switch, and quit; a song with no JSON gains none. Existing registration-only JSON stays byte-identical. |
| G legacy/malformed | Per-song malformed view/editor never loads or rewrites. QSettings wrong-type/invalid lane blob defaults only lanes; the next semantic editor save writes canonical compact JSON. Codec checks use the public functions, not duplicate key literals. |
| H readiness/FIFO | Readiness is MIDI plus terminal voicegroup. Replace the old keyless sidecar FIFO probe with another existing keyless command; exhaustive visitors contain no deleted alternative. |

`rollcheck` and all other per-tab `ViewState` consumers remain unchanged. Tests must use public
accessors and observable stores, not source text or private-member access.

## 9. Documentation reconciliation

P3e edits only the three project-I/O documents. Each replacement cites this plan and states:

- no SidecarStage, SaveSidecarInput, SidecarWriteResult, SongStage::Sidecar, or sidecar fields on
  SongSaved/SaveSongInput;
- load is MidiStage → optional keyed bank view → terminal VoicegroupBound;
- save ends after MIDI/flags with bare SongSaved/SongFailed;
- missing/corrupt legacy view/editor JSON is not a load stage and is never rewritten by view code;
- no independent close/switch/quit cosmetic operation exists.

`docs/time-ruler-loading-plan.md` is already reconciled now: ready reload captures `viewState()`
**before** `prepareForSongReplacement` and reapplies it after `setSong`; fresh MidiStage uses
canonical defaults rather than camera continuity. It contains no sidecar dependency or global
camera claim. P3e must not edit it. Its fallback axis, paint layers, `setInteractionEnabled`, and
pre-setSong ruler work are a separate deliverable and are absent from this plan's checks,
acceptance, and smoke.

## 10. Exact end-state harness queries

INT runs these repository-scoped harness tools after integration. Shell `grep` and `rg` are
forbidden.

| Query | Harness invocation | Expected result |
|---|---|---|
| 1 deleted transport/UI types | Grep with pattern `\b(ViewSidecar|SidecarStage|SaveSidecarInput|SidecarWriteResult|ReadSidecarCommand)\b` and path `src;CMakeLists.txt` | empty |
| 2 deleted paths | Grep with pattern `SongStage::Sidecar|persistViewSidecar|persistSessionViews|captureViewSnapshot|applySidecarStage` and path `src` | empty |
| 3 deleted drawer API/check names | Grep with pattern `applyEditorDrawerState|editorDrawerStateChanged|editorDrawerStateEdited|setEditorDrawerState|m_editorDrawerState|loadEditorDrawerState|saveEditorDrawerState|runViewSidecarCheck` and path `src` | empty |
| 4 ambiguous sidecar result fields | Grep with pattern `\b(sidecarSnapshot|sidecarSaved|sidecarError)\b` and path `src` | exactly the retained sample-provenance flow: the `SampleCommitted` declaration in `src/project/projectworkspace.h`, its commit path in `src/project/projectio.cpp`, and the sample-status consumer in `src/ui/workspaceui_samples.cpp`; no song transport, SongTab, SongView, MainWindow, or non-sample WorkspaceUi match, and `sidecarSnapshot` has no match |
| 5 deleted build entries | Grep with pattern `viewsidecar|sidecarcheck` and path `CMakeLists.txt` | empty |
| 6 exact settings literals | Grep with pattern `editorDrawer/` and path `src` | exactly the eight literals in `src/ui/editorviewstate.cpp`; checks contain none |
| 7 retained owners | Grep with pattern `Sidecar::ensureDir|SampleSidecar|saveRegistrationMeta|loadRegistrationMeta|clearRegistrationMeta|removeSongSidecar` and path `src` | every named retained identifier has at least one production match |
| 8 deleted files | Glob the exact paths `src/ui/viewsidecar.h;src/ui/viewsidecar.cpp;src/checks/sidecarcheck.cpp` | empty |
| 9 harness placement | Glob `src/**/*check.cpp`, then Read the `src/` directory | no added `*check.cpp` anywhere, so `src/checks/` stays the sole harness root; the only check outside it is the pre-existing `src/ui/theme/themecheck.cpp`, unchanged; the three `src/` top-level `.cpp` sources remain exactly `main.cpp`, `mainwindow.cpp`, and `porydaw_scale.cpp` — Read shows no new top-level check beside them and their normal headers/pch; the `git status --porcelain -- src/checks/` fact below shows only the named check modifications plus the `sidecarcheck.cpp` deletion |
| 10 CMake ownership | Read `CMakeLists.txt` around the application source and check registration lists | only INT's removal of the two viewsidecar source entries and one sidecarcheck entry |

Each Grep call is case-sensitive, respects gitignore, and names the path shown in the table. INT
also runs the non-search ownership fact command `git status --porcelain -- src/checks/`; it must
show deletion of `src/checks/sidecarcheck.cpp` and modifications only to the named existing check
files, with no added `*check.cpp`.

## 11. Forbidden alternatives

- Any legacy view/editor reader, writer, migration, compatibility alias, replacement sidecar, or
  no-op transport stub.
- Any second global store, MainWindow mirror, `EditorPreferencesStore`, renamed key, extra key, or
  persisted/global `SongView::ViewState` field.
- Any in-place lane mutation followed by an equality-guarded self-commit; any selected-tab filter;
  any projection emission.
- Any early destruction of the old timeline/voicegroup owner; any `setSong` reset of complete
  EditorViewState; any scroll-only reload snapshot.
- Any new harness, moved sidecar scenario, source-text-coupled behavior test, weakened readiness
  drain, or CMake edit outside INT.
- Any static/pre-bind ruler, TimeAxis, fallback-axis, paint-layer, or global-camera acceptance in
  this sidecar-removal wave.

## 12. Acceptance

- Every EditorViewState origin, including a non-selected tab lane/remap origin, fans out once and
  persists once through the exact eight-entry codec; future tabs and relaunch restore it.
- Ready reload preserves all nine transient ViewState fields. Fresh/reopen establishes all exact
  canonical defaults without focus theft or intermediate event-list traffic.
- `setSong` preserves complete global lane state. Timeline and voicegroup borrows remain valid
  throughout MIDI adoption.
- Project open/save/close/reload/switch/quit performs no view/editor project I/O; legacy bytes remain
  untouched by those paths.
- Transport order, readiness, bare save completion, retained registration/sample/preview/trash
  behavior, deletions, and exact harness queries match §§4, 8, and 10.
- The three project-I/O docs cite this plan; the time-ruler doc remains marked reconciled now.
- No unresolved implementation choice, temporary symbol, compatibility code, or cross-slice file
  overlap remains.

Native smoke is limited to delivered sidecar-removal behavior and records these row-mapped
observations:

- **A:** open two bound songs and verify complete global editor state plus every canonical fresh
  `ViewState` default;
- **D:** mutate drawer and lane state in the non-selected tab, observe synchronous propagation and
  one QSettings update, then open a third tab and verify its projection;
- **C:** reload one ready tab and verify all nine transient fields, then close/reopen it and verify
  canonical defaults with no leakage;
- **E:** quit and relaunch, then verify the complete global state restored from QSettings with no
  startup write;
- **F:** byte-snapshot `.porydaw` before the reload, close, project switch, and quit boundaries,
  then verify the listing and bytes remain identical after each boundary and after relaunch.

Focused filters cover rows B/G/H and retained registration, sample, preview, trash, and song
deletion behavior. Ruler behavior is not a predicate of this smoke.
