# Sprint-3 plan: existing-surface parity after task 51

Status: **planning evidence for the controller.** Ordered queue, tasks 52 onward, for the
authorized existing-surface scope. Individual briefs are frozen one at a time by the
controller. Fork oracle: `fceecd88` (`git show fceecd88:<path>`). In flight as of this
writing: task-41b (pitch-bend proof anchors; owns uncommitted `EditorSurface.qml`,
`PianoGrid.swift`, `AutomationPage.qml`/`AutomationMenu.qml` edits) and task-50a (menu
press ownership). Sprint-3 dispatch begins after both settle.

## 1. Objective and success criteria

Same contract as next-sprint.md §1: a mounted Swift/QML surface reproduces fork behavior,
its ledger rows move to MATCHED with executing predicates, covering lanes pass. Sprint-3
success: every authorized family above ~100 open rows has either landed surface tasks or
a named, evidenced deferral; at least one family (scrollbar, automation gestures,
velocity) reaches zero open rows and its ledgers are deleted with their C++ sources.

## 2. Open-row census (awk over `Disposition:` in `src/checks/**/proof.*.txt`)

Open = GAP+PARTIAL per row, per directory. B/R/Bl = sampled Behavior/Representation/
Blocked estimates (10 rows/family vs fork C++; scout evidence, medium-low confidence —
not a full row audit). Parked/out of scope: `project` 385 (swift-project-store worktree),
`samplecheck` 408, `onboardcheck` 426, `midi/tst_midiexport` 13 (P3).

| Family | Open | B/R/Bl | Highest-leverage theme |
| --- | ---: | --- | --- |
| mainwindowrouting | 610 | 52/25/23 | Cross-tab drawer fanout (A/V/P reach all tabs via shared view state), EditorViewState persistence, close-one/reopen; QAction pointer/focusWidget rows are R; sidecar snapshots Blocked (project-store) |
| automation + automationgesturecheck | 587 | 55/35/10 | Value-prompt commit path missing; rendered geometry/painting proofs; drag/hover/crosslane outcomes exist but unproved |
| rollcheck | 400 | 75/15/10 | Ruler live drag→time-selection + loop menu clicks; pencil velocity latch; note-menu retarget |
| drawerpresentation | 340 | 45/35/20 | valueprompt 65 (commit path) rides with automation; velocity page R-tail; voice insert pick |
| velocity | 325 | 75/20/5 | Predicates never rebuild the timeline projection after edits; detent axis/latch laws |
| voicegroupsave | 311 | 76/19/5 | VG04 save/synth/switching journey; VG02 picker remainder |
| selectionkey | 284 | 45/30/25 | Roll key-command outcomes (arrows/undo, lane-scoped Delete, gesture cancel/restart) |
| voicegroup | 269 | 79/14/7 | VG01 catalog defaults (110 GAP, counterpart "none identified"); loader contents/recovery |
| eventviews | 226 | 45/20/35 | SongViewModel strip/orphan bucket projection absent (viewbuckets Bl 50%); chrome live drag/double-click; remap selection |
| host | 198 | 65/25/10 | No executing lane; needs macOS host observation (controller-run) |
| scrollbar | 136 | 85/10/5 | Mounted but drag/rebase/paging/wheel laws unproved (stale preamble says "unmounted") |
| pitchbend | 127 | — | task-41b closes 108 proof-only; remainder re-baselines after it lands |
| workspace | 123 | 75/15/10 | Session restore + view-state persistence (no codec); rides with window-state task |
| trackheaders | 113 | 70/20/10 | Tooltip hover laws absent; mutation/menu real-surface proof |
| clipboard | 83 | — | Largely closed by task-49; residual rides with ruler/roll tasks |
| small families | ~330 | mixed | swiftqtml 78, swiftgridprototype 61 (deletion certificates), themelayout 50, swiftrollgated 46, visual 44, timelinepan 43, nativegraphics 35, keyboard 27, retained 18, polyphony 16 |

Known-stale preamble hazard (observed twice this census): ledger preambles predate the
mounts — `TimelineScrollbar` IS mounted (`EditorSurface.qml:708,736`), ruler input/menu
IS mounted (`EditorSurface.qml:48-160`, `PianoGrid.swift` measures `rulerHeight`). Every
brief re-verifies its rows' mounts at freeze; no row is planned against a stale preamble.

## 3. Ordered queue, tasks 52–67

Hot files (serialize across all tasks): `ShellWindow.qml`, `ShellPresenter.swift`,
`ApplicationSession.swift`, `DocumentWorkspace.swift`, `EditorSurface.qml`,
`PianoGrid.swift`; shared check files `tst_EditorDrawer.qml` (tasks 55–60) and
`tst_ShellWindow.qml` (58, 65). Shared verify baseline (AGENTS.md):
`deno task build:checks`, `deno task verify:bridge`, `deno task proof check`,
`deno task format --check`. **Ready to brief immediately: 52, 53, 54, 55** (dispatch of
52–55 gates on task-41b settling `EditorSurface.qml`/`PianoGrid.swift`/`AutomationPage.qml`).

- **task-52 — scrollbar live drag/paging laws** *(ready)*
  Outcome: mounted horizontal/vertical `TimelineScrollbar` proves fork drag clamp/reverse,
  rebase-during-zoom, one-pixel displacement, canonical band geometry, track paging and
  scrollbar-targeted wheel. Ledgers: scrollbar drag 43, geometry 37, input 31, tst 25
  (136; ~85% behavior) — **deletable family**. Fork: `src/checks/scrollbar/drag.cpp:88,123,141`,
  `geometry.cpp:49`, `input.cpp:69`. Current: `src/swift/app/timeline/TimelineScrollbar.swift`
  + mounts `EditorSurface.qml:708,736`; checks `src/checks/scrollbar/ScrollbarChecks.swift`,
  `src/checks/rollqml/tst_TimelineScrollbar.qml`. Write-set: `TimelineScrollbar.swift`,
  `EditorSurface.qml`*, scrollbar checks/ledgers. Lanes: swiftroll-window, swiftcore,
  verify:qml-roll. Native host/window accessor rows in `tst_scrollbar` retire inside.
- **task-53 — ruler live input + loop commands** *(ready)*
  Outcome: real ruler-band drag creates the exact time selection with primary/derived
  track scope; rendered ruler/loop menu rows receive clicks, close on activation; loop
  ticks snap; keyboard ruler-scope rows (transpose/seed) execute on the mounted surface.
  Ledgers: ruler_loop_menu 61, timemenu 33, rollcheck keyboard ruler rows ~30 of 65.
  Fork: `src/checks/rollcheck/ruler_loop_menu.cpp:119-232`, `keyboard.cpp:140-256`.
  Current: `RulerMenuPresenter.swift` presenter policy; mounted `rulerInput`/
  `rulerMenu` at `EditorSurface.qml:48-160`; checks `ruler_loop_menu.swift`, `timemenu.swift`.
  Write-set: `EditorSurface.qml`*, `RulerMenuPresenter.swift`, `PianoGrid.swift`*,
  ruler checks. Lanes: shell-grid-menu, swiftcore, verify:qml-roll.
- **task-54 — pencil velocity latch + Set Velocity round-trip** *(ready)*
  Outcome: click on a note latches its velocity into the pencil (draw with latched value,
  free-cell guard, no-mutation case); the fork's `Set Velocity…` prompt round-trip
  (initial/selected literal, unchanged-accept no-op, close) and note-menu retarget land
  on the roll surface. Ledgers: pencil_velocity 39, velocity_prompt 44, pencil 10.
  Fork: `pencil_velocity.cpp:56-100`, `velocity_prompt.cpp:155-236`. Current:
  `PianoGrid.swift` draw path has no click-latch; menu row `edit.set_velocity` exists
  (`ShellPresenter.swift:49,113`); checks `pencil.swift`, `velocity_prompt.swift`.
  Write-set: `PianoGrid.swift`*, `ShellPresenter.swift`*, roll checks. Lanes:
  verify:qml-roll, shell-grid-menu, swiftcore. Popup-session observation rows (A016)
  retire inside.
- **task-55 — automation value-prompt / CC-delete / tap-tempo journeys** *(ready)*
  Outcome: rendered numeric-prompt input writes the intended automation node
  (lane/tick/value mapping, clamp, commit, focus ingress and return), CC-delete
  confirmation accept/cancel through the mounted prompt with shared-session content,
  tap-tempo persistence. Ledgers: drawerpresentation valueprompt 65, ccdeleteconfirmation
  54, automationtaptempo 17, automationfixture 10 (~146; B~50/R~35/Bl~15). Fork:
  `drawerpresentation/valueprompt.cpp:131-148`, `automation/ccdeleteconfirmation.cpp:154-243`.
  Current: `AutomationPrompt.qml`, `AutomationPage.swift`; cancel-only proof in
  `localinputtier_text.swift`. Write-set: `AutomationPrompt.qml`, `AutomationPage.swift`,
  automation checks. Lanes: shell-drawer-parity (`tst_EditorDrawer.qml`), swiftcore.
- **task-56 — automation rendered geometry + previews/parity**
  Outcome: band/plot/tab/label geometry and painted previews proven on the mounted drawer
  (per-tab/per-row probes), preview edit-cursor/quick-view outcomes. Ledgers:
  automationcanvaslayout 99 (incl. 62 native-harness sites — **representation sweep inside
  this task**), previews 24, parity 16. Fork: `automationcanvaslayout.cpp:46-64`.
  Current: `AutomationPage.qml`, `AutomationScene.swift`, `AutomationProjectionCache.swift`;
  check `automationcanvaslayout.swift` is presenter-only. Write-set: automation QML +
  `tst_EditorDrawer.qml` geometry probes. Lanes: shell-drawer-parity, swiftcore.
- **task-57 — automation drag/gesture domain**
  Outcome: node-drag tick/count outcomes, drag-protects-selection, hover enter/move/leave,
  cross-lane no-write invariants, live-preview freeze, playback-timeline projection,
  selection rings and painted selection shifts. Ledgers: automationgesturecheck 85
  (contract 33, hover 20, crosslane 19, parity 13), nodedrag 33, ownership 37, selection
  28, painting 33, pencil 14 — **deletable family (gesturecheck)**. Fork:
  `automationgesturecheck/contract.cpp:120`, `crosslane.cpp:147`, `automationnodedrag.cpp:204-355`,
  `automationownership.cpp:64-156`, `automationselection.cpp:241-248`. Current:
  `AutomationInteraction.swift`, `AutomationNodeTransactions.swift`,
  `AutomationSelectionCommands.swift`, `AutomationLaneProjection.swift`; checks
  `src/checks/automation/domain/gesture*.swift`, `tst_EditorDrawer.qml` hover. Scene-graph
  mesh/ring identity rows retire inside. Lanes: swiftcore, shell-drawer-parity.
- **task-58 — roll key/gesture editing semantics (selectionkey core)**
  Outcome: focus-routed arrows move selected notes (cross-band round-trip + undo),
  Delete removes lane-scope automation points and note selections, Select-All/clear
  journeys, gesture cancel/restart, thumb grab laws. Ledgers: coreediting 48, corearrows
  15, gesturecommands 16, gesturevelocity 20, gesturethumbs 13, windowtier_gestures 14,
  localinput residue ~17, rollcheck keyboard non-ruler rows. Fork: `coreediting.cpp:67-132`,
  `corearrows.cpp:124-251`, `gesturecommands.cpp:63-157`, `gesturevelocity.cpp:57-186`,
  `gesturethumbs.cpp:33-119`, `windowtier_gestures.cpp:103-118`. Current:
  `NoteCommands.swift`, `GridGesture.swift`, `PianoGrid.swift`; partial mounted proof in
  `tst_ShellWindow.qml` (routed arrows), `tst_ShellGridInput.qml`. Write-set:
  `NoteCommands.swift`, `GridGesture.swift`, `PianoGrid.swift`*, grid-input checks.
  Lanes: shell-grid-input, shellwindow, swiftcore. Native grab/focus rows retire inside.
- **task-59 — velocity surface: detents + timeline projection**
  Outcome: detent gesture axis/context/latch laws on the real delegate, and every edit
  predicate rebuilds the timeline projection and reads velocity events back (the single
  most repeated PARTIAL cause: `velocitydetentdragging.cpp:47`, `tst_velocityediting.cpp:214`,
  `velocityhitpriority.cpp:28`); zero-`documentChanged` deferred-paint, track-switch
  cancellation axis, blank-click containment. Ledgers: velocitydetentdragging 116,
  detentpainting 68, tst_velocityediting 43, velocityroll 28, velocitypainting 25,
  velocityselection 18, velocityclicks 17, hitpriority 10, drawerpresentation velocity 96
  — **deletable family (velocity/)**. Current owners: `src/swift/app/drawer/velocity/`
  (Page/Projection/Interaction/Transactions/Context), `VelocityPage.qml`; checks
  `Velocity*Checks.swift`, `drawerpresentation/velocity.swift`. Native input-bounds
  preconditions retire inside. Lanes: swiftcore, shell-drawer-parity. May brief as 59a
  (projection proof) / 59b (detent input) sharing the surface.
- **task-60 — voice-changes page: insert pick + rendered rows**
  Outcome: rendered Insert row delegate pick (not just Delete), voice-lane edit → used-mark
  transition, hover/press survival across rebuild; image-capture rows either proven or
  retired as native. Ledgers: drawerpresentation voice 50, voicemenus 43. Fork:
  `voice.cpp:146`, `voicemenus.cpp:112`. Current: `VoiceChangesPage.swift`,
  `VoiceChangesInteraction.swift`, `VoiceChangeMenu.qml`; checks `voice_interaction.swift`,
  `voicemenus.swift`. Lanes: shell-drawer-parity, swiftcore.
- **task-61 — VG01 source catalog + loader defaults**
  Outcome: per-symbol ADSR family defaults for the synthetic bank, unknown/unusable symbol
  exclusion, loaded bank/sample contents and failure recovery — the catalog the editor's
  typed fields default from. Ledgers: voicegroupsourcecatalog 110 (counterpart "none
  identified"), tst_voicegrouploader 55, loadfixture 14, bank 21, sourceediting 10.
  Fork: `voicegroupsourcecatalog.cpp:35-67`, `tst_voicegrouploader.cpp`. Current:
  `src/swift/project/VoicegroupStore.swift` + catalog paths (MintedSynths/SynthCatalog);
  projectstore checks (`VoicegroupEditingChecks.swift`, `SaveCoreChecks.swift`) already
  carry 90 ported editing rows per the ledger's retirement record. Write-set: catalog
  Swift + projectstore checks — **no `src/project/` C++ changes**. Lanes: bankleases,
  vgbankcheck, swiftcore, shell-voicegroup. Loader batching internals stay Blocked unless
  a resource contract is named.
- **task-62 — VG01/VG02 editor presentation + picker journeys**
  Outcome: used marks match assigned programs, track→program reveal unhides/selects,
  press survives panel rebuild; picker category/filter/search, dismissal/stop, undo
  restore, no-song-dirty invariant on the mounted dock. Ledgers: voicegroupsave
  presentation 80, editor 28, viewcache 59, picker 44 (~211; B~78). Fork:
  `presentation.cpp:64-119`, `picker.cpp:41-95`. Current: `VoicegroupPanel.qml`,
  `VoiceEditor.qml`, `SamplePicker.qml`, `VoiceListController.swift`,
  `SharedBankState.swift`; `tst_ShellVoicegroup.qml` covers audition/commit/save partially.
  Write-set: voicegroup QML + `VoiceListController.swift`, shell-voicegroup fixtures.
  Lanes: shell-voicegroup, bankleases, swiftcore. Cache/lease identity rows retire inside.
- **task-63 — VG04 save/synth/switching journey**
  Outcome: end-to-end dock edit → save (referenced definitions only, deterministic dedup,
  in-memory synth materialization on save) → reopen/refresh clean; failed rebind and
  catalog-outage persistence; `-G` switching keeps bank bytes per the handoff's
  bank-close policy. Ledgers: savecore 80, switching 40, synth 39 (159). Fork: pinned
  revisions in those ledgers. Current: `VoicegroupStore.swift`, `DocumentSession.adoptBank`,
  `ServiceBankHistory.swift`; checks `SaveCoreChecks.swift`, `ProjectStoreSaveChecks.swift`,
  workspace `bank_*.swift`. Lanes: shell-voicegroup, bankleases, swiftcore. Store-level
  rows already covered are re-anchored, not rebuilt.
- **task-64 — event views: bucket projection + chrome/edits/remap**
  Outcome: SongViewModel strip/orphan-bucket composition + grid-lattice quirk projection
  (absent today — `GridGeometry.swift` is geometry-only); live column-resize drag,
  double-click cell-open, rendered track-remap selection; raw-tempo tick-zero atomicity
  and journey-isolated fixtures. Ledgers: viewbuckets_grid 26, chrome 117, edits 56,
  remap 27 (226). Fork: `viewbuckets_grid.cpp:105-145`, `chrome.cpp:69-178`,
  `edits.cpp:137-377`, `remap.cpp:57-159`. Current: `src/swift/app/eventlist/*`
  (Presenter/Editing/Selection/Model/Projection), `EventListPage.qml`; checks
  `EventListPageChecks.swift`, `EventListPlayheadChecks.swift`, `tst_ShellEventList.qml`,
  `EventViewsRemapBucketsParity.swift` (constituent counts only). Write-set: eventlist
  projection + QML. Lanes: shell-event-list, swiftcore. Fixture/font-object and
  signal-order rows retire inside.
- **task-65 — window state authority: cross-tab fanout + persistence**
  Outcome: drawer-section state fans out across tabs (A/V/P act on every tab through one
  shared view state); EditorViewState persists and restores per song (camera, drawer,
  active page) through the existing preferences store; close-one-tab with sibling
  survival, reopen readiness. Ledgers: mainwindowrouting state 227 + input 195 +
  lifecycle 150 behavior rows (~200 after R/Bl), workspace session 28 + selftest_workspace
  25 + tabs_transport residue. Fork: `tst_mainwindowrouting_state.cpp:52-93`,
  `lifecycle.cpp:40-58`, `input.cpp:101-135`. Current: `DocumentWorkspace.swift`,
  `SongTabsController.swift`, `EditorViewStateCodec.swift` (codec exists, no
  persistence/fanout wiring), `ShellWindow.qml`. Write-set: `DocumentWorkspace.swift`*,
  `ApplicationSession.swift`*, `ShellWindow.qml`*, SessionChecks. Lanes: shellwindow,
  shell-tabs, swiftcore. QAction pointer-identity (A069–A072, A082–A085), focusWidget
  chains and pixel-grab rows retire inside; sidecar byte snapshots stay Blocked
  (project-store). After 50a settles `ShellWindow.qml`/`tst_ShellWindow.qml`.
- **task-66 — track-header tooltips + mutation/menu proof**
  Outcome: hover lookup drives fork tooltip presence/absence; over-budget dimming
  residual; all five context-menu actions, role/dataChanged mutations and activity-meter
  geometry proven on the converted surface. Ledgers: trackheadermutations 45,
  activitymeter 29, menu 18, input 11, raster 10 (113). Fork: `trackheaderinput.cpp:86-342`,
  mutation/menu/activitymeter ledgers' pinned sources. Current: `src/swift/app/headers/`
  (TrackHeaders, TrackHeadersInput, TrackHeadersGeometry, TrackActivity); checks
  `TrackHeadersChecks.swift`, `tst_SwiftRollTrackHeaders.qml`. Write-set: headers Swift +
  `TrackHeaderBand.qml`. Lanes: swiftroll-window, swiftcore. Raster/native-harness rows
  retire inside.
- **task-67 — host adapter/integration observation lanes**
  Outcome: note discovery/selected-notes/marker/playhead/band-geometry contracts observed
  on the real macOS host (controller-run), or explicitly NATIVE-marked where only the
  host can see them. Ledgers: hostintegration 96, hostadapter 80, hostseams 21,
  rulergridmenu 1 (198; B~65). Fork: `tst_hostadapter.cpp:68-173` + pinned revisions.
  Current: no executing lane in `src/checks/host/`; owners `DocumentWorkspace.swift`,
  `ApplicationSession.swift`, `NativeAudio.swift`. Write-set: new host observation checks
  (harness-side only, no production rewrite). Lanes: controller-run native observation;
  `verify:bridge`. Free-parallel anytime; lowest user-visible risk (proof, not feature).

## 4. Representation sweeps inside surface tasks (never standalone)

Per proof-ledger-workflow POLICY, these retire only inside the task that owns the surface:
canvaslayout native-harness sites (56); ownership/nodedrag mesh-ring identity rows (57);
gesturethumbs/corearrows grab-and-focus rows, pencil popup-session rows (54/58);
velocitydetentdragging input-bounds preconditions (59); voice image-capture rows (60);
viewcache cache-lease identity, picker popup-object probes (62); chrome font-object and
remap signal-order rows (64); routing QAction/focusWidget/pixel-grab rows (65);
trackheaderraster (66); scrollbar native accessors (52). No standalone reconciliation
wave exists in this sprint.

## 5. Sequencing and parallelism

Gates: 41b settles → 52, 53, 54, 55 briefs freeze. 50a settles → 65 (and 58's
`tst_ShellWindow.qml` additions). Hot-file chains: `EditorSurface.qml`+`PianoGrid.swift`:
52 → 53 → 54 → 58 (serial); `tst_EditorDrawer.qml`: 55 → 56 → 57 → 59 → 60 (serial or
checkpoint between); `DocumentWorkspace`/`ApplicationSession`/`ShellWindow`: 65 alone.
Free-parallel: 61 (store/catalog), 64 (eventlist), 66 (headers), 67 (host) at any point.
Voicegroup chain: 61 ∥ (62 → 63). Recommended dispatch: 52 immediately after 41b; then
53 + 55 in parallel; then 54 + 56; then 57/58/59 by implementer availability; 61–63 and
64/66/67 fill parallel slots; 65 last among shell work.

## 6. Following-sprint backlog (authorized, not queued)

Automation command long tail (routing 33, voice 31, actions 17, tst_automationediting 22,
menus 12, clipboard 7, stroke 7, pointmenus 2, canvasediting 6 ≈ 137) — closes the
automation family after 55–57; drawerpresentation drawer.txt chrome/resize PARTIALs (86);
pitchbend post-41b re-baseline; timelinepan 43 (maps to `tst_TimelinePan.qml`);
swiftgridprototype/swiftrollgated deletion certificates (~107); themelayout/visual/
nativegraphics/retained/swiftrollbench (~170); swiftqtml 78; PJ05 project ledgers remain
parked for the swift-project-store worktree.

## 7. Assumptions

- Tasks 41b and 50a land as briefed; 52–55's write-sets re-snapshot after they settle.
- B/R/Bl splits are 10-row sampled estimates, not audits; each brief re-verifies its full
  row set at freeze (stale-preamble hazard documented in §2).
- "workspace" means `src/checks/workspace/` session predicates; `src/checks/project/`
  stays parked. Task-61 touches `src/swift/project/` Swift catalog code only, never
  `src/project/` C++ or ProjectService.
- No new C++; no comments; one message-anchored predicate per fork clause; WCAG AA beats
  parity where they conflict; visual parity with `fceecd88`; base-font sizing only.
