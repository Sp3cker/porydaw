# Context

Task 65a — window state authority: one application-wide editor view state. The
drawer sections (A/V/P), their heights, the active page and the automation-lane
grammar become ONE shared state that every song tab projects, that persists to
the preferences store, and that survives close/reopen, reload, project switch
and quit. Task 65 was scoped at ~610 mainwindowrouting rows plus three
workspace ledgers; the census below splits it into **65a (this brief: the
shared-state surface)**, **65b (close-gate authority, named in ¶6)** and five
evidenced deferrals. Fork-main = `fceecd88` (`git show fceecd88:<path>`).

1. **Census (verified this freeze)**: mainwindowrouting state 267 rows/227 open,
   input 207/195, lifecycle 164/150, native 80/38 GAP = 610 open. Workspace:
   `proof.session.txt` 28 open (A002/A005 PARTIAL), `proof.selftest_workspace.txt`
   25 GAP, `proof.tabs_transport.txt` 42 open. Sprint-3's "state 227 + input 195
   + lifecycle 150" omits native's 38; the true family is 610.
2. **Fork architecture** (`git show fceecd88:src/ui/editorviewstate.h`,
   `editorviewstate.cpp`, `src/ui/songview.h`): two distinct state objects —
   * `EditorViewState` (editorviewstate.h:53-79) — **application-wide**
     ("MainWindow persists this application-wide", :43): three
     `DrawerSectionState{visible, height?}` (velocity/automation/voiceChanges),
     `activePage`, `laneHeight`, `laneHeights`, `laneRanges`, `emptyLanes`,
     ordered `hiddenLanes`. No camera, no per-song key. Persisted by
     `saveEditorViewState` to keys `editorDrawer/velocityVisible`,
     `/velocityHeight`, `/automationVisible`, `/automationHeight`,
     `/voiceChangesVisible`, `/voiceChangesHeight`, `editorDrawer/activePage`
     ("automations"/"velocity"/"voiceChanges"), plus the one
     `editorDrawer/automationLanes` compact-JSON blob (editorviewstate.cpp:
     124-131, 374-421). A missing/wrong-typed member defaults only that member.
   * `SongView::ViewState` (songview.h:163-176) — per-tab TRANSIENTS
     (pxPerBeat, keyHeight, scrollPx, scrollY, selectedTrack, editCursorTick,
     gridSelection, gridTriplet, eventList): never preference-persisted;
     retained across in-memory reload via `applyViewState`. This corrects the
     sprint phrasing "persists per song (camera…)": the camera is reload
     transient, only drawer+lane chrome persists.
   * Hub law (`tst_mainwindowrouting_state.cpp:282-334`, ledger A100–A120): an
     origin mutation emits origin `editorViewStateChanged` ×1, workspace-hub ×1,
     `editorViewStatePersisted` ×1; sibling tabs receive the state by SILENT
     projection (`applyEditorViewState`, songview.h — no receiver signal); a
     no-op `setEditorViewState` emits nothing anywhere.
   * Fanout law (`drawerFanout` :75-100, A013–A028): A/V/P window keys toggle
     the section AND make it the active page on BOTH tabs simultaneously;
     hiding all sections leaves `!hasVisibleDrawerSection()` on the sibling.
     Seed (mainwindowroutingfixture.h:101-106): velocity {true,173},
     automation/voiceChanges hidden, activePage velocity — i.e. new tabs start
     from the persisted state, and `a.drawerState()==b.drawerState()` (:69).
   * Gating law (`eventListGating` :106-120, A029–A036): while the selected tab
     shows the event list, the three drawer actions are disabled and V/P keys
     leave the complete state unchanged.
   * Retain laws: `hideRetains` (A049–A055) — hiding one section retains the
     others' heights and active page; `drawerFocusFollowsFallback` (A037–A048)
     — toggling a section focuses its band, falling back per drawer focus
     policy.
   * Lifecycle laws (`tst_mainwindowrouting_lifecycle.cpp`): close-one keeps
     the sibling (openTabCount 1, `songTabFor(name)==nullptr`, project bytes
     unchanged, :40-58 A001–A010); reopen restores the shared state
     (`editorViewState()==state`) on a fresh timeline with canonical fresh
     transients; `readyReloadPreservesTransients` (:99-139 A011–A031) keeps
     scroll/selection/grid/triplet/eventList across a reload with zero event-list
     traffic; `freshBind` (:169-204 A042–A054) — an UNREADY tab already carries
     `editorViewState()==global`; `stagedReload` (A055–A071) keeps ViewState
     across a timeline swap; `projectSwitchAndQuitPreserveState`
     (A091–A110, fork :364/:390 `loadEditorViewState(QSettings{})==state`)
     persists the state through project switch and quit.
3. **Classification of the 610 open rows** (fork evidence per group):
   - **65a behavior (172)**: state A007–A012 seed, A014–A028 fanout, A029–A036
     gating, A037–A048 focus-fallback, A049–A055 hide-retains, A094–A099
     no-workspace enablement, A100–A120 origin/silence/hub, A155–A171 view-only
     lane mutations (83); lifecycle A001–A110 minus retired rows (89: close/
     reopen 10, readyReload 19, selectionDuringReload 10, freshBind 13,
     stagedReload 17, projectSwitchAndQuit 20).
   - **65a representation retirements (inside this task, sprint-3 §4)**: state
     A001–A006 (fixture guard + QAction shortcut/objectName/shortcutContext —
     the key DELIVERY is the fanout behavior above), A013/A100/A121 fixture
     guards, A056–A066 (`QApplication::focusWidget` chains), A069–A072 and
     A082–A085 (QAction pointer identity — the Swift menu items are one
     shared window-action set already, `ShellWindow.qml` `shellShortcut_`
     (:233) + `shellAction_` (:258));
     native ledger rows whose reason pins Qt internals (signal counts,
     QAction identity/enablement lookups, widget visibility/pixel grabs).
   - **Deferred with named owners (438)**: input 195 (all eight functions are
     edit-command/focus/readiness journeys — copy/solo/insert/delete-time
     plus catalogue-view bindings and fresh-tab readiness, input.cpp:95-527 →
     edit-command routing task, following-sprint backlog); state A121–A154 +
     A172–A183 (42 — `remapEngineTracks` view-state hook; ledger preamble:
     "A182–A183 stay GAP (no Swift remapEngineTracks method)" → rides after a
     document engine-track remap ingress exists); mouse hints 71 (state
     A184–A267) + 43 (lifecycle A111–A164) = 114 → mouse-hints surface task
     (`src/swift/app/MouseHints.swift` exists; no mounted surface yet);
     lifecycle bankRebind A072–A081 (10) → task-63 VG04 switching; native
     splits three ways (constraints mapping): boundViewTeardown 12 retire
     inside 65a, failed-dialog A072/A078 → 65b, the Cocoa-platform remainder
     (real key injection with a foreign window, async activation) → task-67
     host observation, stay GAP named. Workspace
     tabs_transport 42 → transport chrome task (scale selector, time labels,
     dial raster, toolbar order — `TransportBarPresenter` surface, not window
     state).
4. **Swift current state — the gaps are fanout and drawer persistence**: the
   codec exists but persists only the lane blob + tab recipe
   (`EditorViewStateCodec.loadTabs/saveTabs/loadLanes/saveLanes`); it has NO
   drawer-section keys. `ApplicationSession` already models the exact pattern
   to extend: lane ranges fan out to all tabs and save
   (`updateEditorLaneRange`), new workspaces receive persisted lane ranges and
   display modes at open (`openTab` workspace application), display modes are
   app-wide+persisted (`setVelocityColorMode`/`setNoteNameMode`), startup
   restores the tab recipe (`configurePersistence`/`restoreStartup`).
   `ShellPresenter.activate` toggles A/V/P on the SELECTED page only
   (`ShellPresenter.swift:344-352`); `actionEnabled` for the three drawer
   ids is just `selectedPage != nil` (:267-269) — no event-list gate. Each
   `DocumentWorkspace` owns its own drawer presenter
   (`DocumentWorkspace.swift:44`). Close gate (dirty Save/Discard/
   Cancel + in-flight guard) exists (`SongTabsController.requestClose`);
   `ReloadedTab` retains camera/track/cursor/grid/showsEvents. Window
   shortcuts A/V/P are registered (`KeybindingRegistry.swift:134-136`).
5. **Deferrals inherited from other tasks**:
   - eventviews `proof.chrome.txt` A048/A050 (PARTIAL): "no predicate applies
     a seeded view state whose event-list flag is false/true (the fork's
     applyViewState path); the persistence/apply wiring is task 65's"
     (fork chrome.cpp:274-289). Landed in 65a: the seeded-restore ingress.
   - voicegroup `proof.tst_voicegroupviewcache.txt` A046/A047/A068 (GAP):
     origin-tab close gate — `!bankActionsEnabled && pendingOrigin()==tab &&
     !closeEnabledFor(tab) && closeEnabledFor(otherTab)` (fork
     voicegroupviewcache.cpp:278), and resolveConflict/resolveApplied/
     resolveHardError for ANOTHER voicegroup must not clear the pending origin
     (:282, :318). Registered divergence: Swift prompts on bank-only dirt
     where the fork closes a document-clean tab immediately
     (`workspaceui_tabs.cpp:485-500`). These are 65b (close-gate authority),
     not 65a.
6. **65b (separate brief, controller freezes later)**: tab close authority —
   bank-dirty close divergence + pending-origin gating (viewcache
   A046/A047/A068), failedOpenPreservesLiveTab (lifecycle A082–A090, 8 open)
   plus the native failed-dialog pair (A072/A078). Consumes
   task-63's bank-transition state; write-set `SongTabsController.swift` + a
   read-only pending-origin query on the bank coordinator + viewcache checks.
   Do NOT build it inside 65a: different behavior, and it must not block on
   task-63's landing.

# Exact write set

- `src/swift/app/timeline/EditorViewStateCodec.swift` — add
  `EditorDrawerChromeState` + load/save over the seven fork keys.
- `src/swift/app/ApplicationSession.swift` — own the application-wide state:
  load full state at `configurePersistence`, apply to every new workspace,
  fan out every drawer/lane mutation to all workspaces, persist once.
- `src/swift/app/DocumentWorkspace.swift` — route drawer presenter mutations
  (section visibility/height, active page) to the session hub.
- `src/swift/app/shell/ShellPresenter.swift` — drawer ids dispatch through the
  hub; `actionEnabled` adds the event-list gate.
- `src/checks/workspace/editor_view_state_checks.swift` — chrome codec
  predicates (selftest_workspace ledger).
- `src/checks/workspace/session_view_state.swift` — **new** session-level
  fanout/persistence/restore predicates; one registration line in
  `src/checks/workspace/SessionChecks.swift` + the source list in
  `src/checks/CMakeLists.txt`.
- `src/checks/editorqml/tst_ShellWindow.qml` — mounted journeys (fanout,
  gating, seeded apply, hide-retains, focus fallback).
- `src/checks/editorqml/tst_ShellTabs.qml` — mounted close-one + reopen
  journey (shared drawer state on a fresh timeline).
- Ledgers (controller-delegated ledger agent, this task's commit): flip
  65a rows in `proof.tst_mainwindowrouting_state.txt`,
  `proof.tst_mainwindowrouting_lifecycle.txt`,
  `proof.tst_mainwindowrouting_native.txt`, `proof.session.txt`,
  `proof.selftest_workspace.txt`, `proof.chrome.txt`; delete
  `proof.session.txt` and `proof.selftest_workspace.txt` when fully closed.

`ShellWindow.qml`, `SongTabsController.swift`, `PianoGrid.swift`,
`EditorSurface.qml`, `tst_EditorDrawer.qml` are NOT edited (menu/shortcut
plumbing already reaches the presenter — this deviates from sprint-3 §5's
`ShellWindow.qml`* write-set entry deliberately; reload retention already
exists). Sizing exception: one surface over 8 files (4 production) + ledgers
— named for the dispatch table. `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `SessionChecks.swift` are hot (see
Prerequisites).

# Prerequisites

Hot files (dirty in this freeze by in-flight 56/60/62/66 — re-read before
editing; checkpoint their owners first): `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `workspace/SessionChecks.swift`. Sprint-3 §5 names
`DocumentWorkspace`/`ApplicationSession`/`ShellWindow` as "65 alone" — that
was written for a settled tree; at dispatch the first two are shared, so 65a
serializes with the in-flight owners rather than assuming exclusivity. Gate:
sprint-3 §5 "50a settles → 65" bites only on QML chrome this write set
otherwise avoids (`ShellWindow.qml` untouched); `tst_ShellWindow.qml` and
`tst_ShellTabs.qml` additions serialize with task-58's if 58 dispatches
first. No interface consumed from 63; 65b (not this brief) consumes 63's
bank-transition state.

# Interface contract

- `EditorViewStateCodec.EditorDrawerChromeState`: `velocity`, `automation`,
  `voiceChanges: DrawerChromeSection{visible: Bool, height: Int?}`,
  `activePage: DrawerPage` (`.automation|.velocity|.voiceChanges`);
  Equatable/Sendable; fork struct defaults (velocity hidden, automation
  visible, voiceChanges hidden, activePage automations — the fixture seed
  differs: velocity {true,173}, activePage velocity; the seed is check
  stimulus, not the default). `loadChrome(store:)` / `saveChrome(_:store:)`
  over the seven fork members with per-member default on missing/wrong-typed
  value; optional heights per fork `loadDrawerHeight`/`saveDrawerHeight`
  semantics (editorviewstate.cpp); `activePage` accepts only the three fork
  strings, else defaults. Existing `EditorLaneState`,
  `loadTabs/saveTabs/loadLanes/saveLanes` unchanged.
- `ApplicationSession` hub (reuse the `updateEditorLaneRange` fanout shape):
  a drawer or lane mutation from ANY workspace updates the shared state,
  applies it to every open workspace WITHOUT re-entering the hub (silent
  projection — receivers must not trigger persistence), and writes the store
  exactly once; an unchanged state mutates nothing and writes nothing. New
  workspaces receive the full shared state at construction (before readiness).
  Preference reset clears the seven chrome keys with the lane blob and recipe
  keys.
- `ShellPresenter`: `activate` drawer ids call the session hub; `actionEnabled`
  for `view.automation_drawer`, `view.velocity_drawer`,
  `view.voice_changes_drawer` is `selectedPage != nil && !
  selectedTabShowsEvents` (fork eventListGating); `view.event_list` unchanged.
- Message-anchored predicates (swiftcore): "one automation key shows the
  section on every open tab"; "the velocity drawer becomes the active page on
  every tab"; "a hidden section stays hidden on the sibling tab"; "the event
  list gates the drawer keys on the selected tab"; "the shared view state
  persists once per change"; "an unchanged view state writes nothing"; "a
  fresh tab carries the shared view state before it is ready"; "the shared
  view state survives close and reopen"; "a reloaded tab keeps its camera,
  selection and grid"; "the shared view state survives a project switch and
  quit"; "hiding one section retains the other sections and the active page";
  "a non-selected tab's mutation reaches the selected tab silently"; codec:
  "missing drawer members default without losing the lane members"; "the
  active page string round-trips"; "the combined chrome and lane state
  round-trips through preferences"; "a wrong-typed height defaults to the
  layout default".
- Mounted anchors (`tst_ShellWindow.qml`): "the A key toggles the automation
  drawer on both song tabs"; "the V and P keys fan out the same way"; "drawer
  menu items disable while the event list shows"; "the gated keys leave the
  drawer state unchanged"; "a seeded hidden event list restores hidden"; "a
  seeded visible event list restores visible" (chrome A048/A050); "toggling a
  section focuses its band". Mounted anchors (`tst_ShellTabs.qml`, where the
  close-one precedent lives): "closing one tab keeps its sibling and the
  project bytes"; "reopening restores the shared drawer state on a fresh
  timeline".
- Preservation contract: existing predicate messages in touched check files
  stay verbatim; `WorkspaceTabRecipe` behavior, lane-blob grammar, dirty close
  gate, `ReloadedTab` retention, display-mode fanout, and every existing
  objectName are unchanged. Keyboard priority rulings stand — no second
  dispatcher, no synthetic forwarding, no focus memory.

# Implementation steps

1. Codec extension (`EditorViewStateCodec`) + `editor_view_state_checks`
   predicates. GREEN expected against the fork's per-member default law.
2. Session hub: load full state in `configurePersistence`; extend the
   new-workspace application in `openTab` to chrome; extend the
   `updateEditorLaneRange` fanout site to all drawer mutations; wire
   `DocumentWorkspace`'s drawer presenter mutations to the hub (RED first:
   today a V toggle on tab A does not reach tab B's presenter and writes
   nothing).
3. `ShellPresenter` routing + event-list gate (RED first: enabled is
   `selectedPage != nil` today; the menu items stay enabled under the event
   list).
4. `session_view_state.swift`: two-workspace session predicates per the
   contract (fanout, silence, persist-once, fresh-tab carry, close/reopen,
   reload retention via the existing reload path, project-switch/quit).
5. Mounted journeys: fanout/gating/seeded-apply in `tst_ShellWindow.qml` on
   the two-tab fixture (real A/V/P key delivery through the window shortcuts,
   View-menu gating, seeded event-list restore — an
   `openTab(restoring:)`-shaped ingress is the applyViewState port);
   close-one + reopen in `tst_ShellTabs.qml` through `file.close_tab`/song
   open, where the tab-close precedent lives.
6. Run the lanes; report GREEN with predicate messages + file:line for the
   controller's ledger handoff.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify --filter swiftcore --verbose` — session suite:
  `session_view_state` + codec + existing session regressions (evidence
  `build/proof-evidence/swiftcore-projectsession.json`).
- `deno task verify:shell --filter shellwindow --verbose` — mounted fanout/
  gating/seeded-apply journeys + regressions.
- `deno task verify:shell --filter shell-tabs --verbose` — mounted close-one/
  reopen-restore journey + regressions (evidence `build/proof-evidence/
  shell-tabs.json` feeds the session ledger handoff).
- `deno task verify:bridge`, `deno task format --check`.
- RED evidence for the three production gaps (no fanout, no chrome
  persistence, no event-list gate) before their predicates pass.

# Task-specific constraints

- No new C++; no code comments (delete stale ones in touched regions); no
  pixel constants; one message-anchored predicate per fork clause; mounted
  proof for key/menu delivery; no test-only bridge seams — the hub is
  production behavior, predicates only observe.
- Signal-count fork rows (origin ×1 / hub ×1 / persisted ×1, silent
  projection, ready ×0/×1) port as change-notification counts observed on the
  real presenters — never as re-emit shims.
- The seven chrome keys keep the fork's member spellings mapped through the
  PreferencesStore dot-joined convention (`editorDrawer.velocityVisible`,
  … — the `lanesKey` precedent is `editorDrawer.automationLanes`, and
  `tst_ShellWindow.qml:237` pins dot-joined on-disk spellings over the
  QSettings slash form).
- Implementers never edit ledgers; the controller's ledger agent updates the
  proof files in the same commit:
  - state: A001–A006/A013/A100/A121 → RETIRED-REPRESENTATION (fixture guards,
    QAction shortcut/objectName/shortcutContext observations); A056–A066 →
    RETIRED-REPRESENTATION (`QApplication::focusWidget` chains; the refocus
    behavior is the mounted key-routing proof); A069–A072/A082–A085 →
    RETIRED-REPRESENTATION (QAction pointer identity; the QML window actions
    are one shared `shellAction_*` set); A007–A012 → seed anchors; A014–A028 →
    fanout anchors; A029–A036 → gating anchors; A037–A048 → focus-fallback
    anchors; A049–A055 → hide-retains anchors; A094–A099 → no-workspace
    enablement anchors; A101–A120 → origin/silence/persist anchors; A155–A171
    → view-only lane-mutation anchors. A121–A154/A172–A183 and A184–A267 stay
    open with the ¶3 deferrals named; ledger NOT deleted.
  - lifecycle: A001–A031 → close/reopen + readyReload anchors (focusWidget
    rows inside retire representation); A032–A041 → selection-during-reload
    anchors (A035/A037/A038 already PARTIAL — flip only with executed
    predicates); A042–A054 → freshBind anchors; A055–A071 → stagedReload
    anchors; A091–A110 → project-switch/quit persistence anchors; A072–A081
    stay GAP named to task-63; A111–A164 stay GAP named to the mouse-hints
    task; ledger NOT deleted.
  - native: `nativeBoundViewTeardownUnbindsActions` GAP rows (12, A059–A071
    open) → RETIRED-REPRESENTATION (native Qt action/menu wiring, shortcut
    projection and enablement identity — sprint-3 §4 names these routing
    QAction rows for 65); `nativeFailedProjectDialogPreservesLiveTab`
    A072/A078 → 65b with the lifecycle failedOpen rows; the
    `nativeMenuAndWindowShortcutRouting` + `nativeForeignWindowKeepsLocalKeys`
    rows stay GAP named to task-67 (Cocoa platform gate / real key injection
    with a foreign window); ledger NOT deleted.
  - workspace: all `proof.session.txt` open rows (A002/A005 title-restore
    PARTIALs included — the restore journeys close them) and all
    `proof.selftest_workspace.txt` rows map to the codec/session anchors;
    DELETE both files when every row is MATCHED/RETIRED.
    `proof.tabs_transport.txt` untouched: all 73 rows are the single
    `transportVolumesAndRaster` function (transport chrome surface), so the
    sprint's "tabs_transport residue" is nil for window state.
  - eventviews: `proof.chrome.txt` A048/A050 → the seeded-apply anchors
    (MATCHED); the ledger is then fully closed and deletable per task-64's
    closure rule.
- If a row resists (e.g. a quit-journey clause needs app teardown the lane
  cannot observe), leave it PARTIAL with the deferral named — never force a
  flip.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`, `deno task proof check
   --executed`, `deno task proof check --strict-mappings`, then
   `deno task proof sites --area workspace` (session + selftest_workspace
   gone; tabs_transport intact) and `--area mainwindowrouting` (state/
   lifecycle/native reduced to the named deferrals) and `--area eventviews`
   (chrome closed or deleted).
2. Two-tab smoke on the mounted lanes: open two songs, press V — both tabs'
   velocity sections report visible with velocity the active page; toggle the
   event list — the View-menu drawer items disable; close and reopen a tab —
   drawer state restored.
3. 65b remains queued: close-gate authority (viewcache A046/A047/A068 +
   lifecycle failedOpen A082–A090 + native failed-dialog A072/A078) consumes
   task-63's landed bank-transition state; brief it separately after 63
   lands.
