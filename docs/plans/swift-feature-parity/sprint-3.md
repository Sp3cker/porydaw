# Sprint-3 plan: existing-surface parity after task 51

Status: **in execution.** Landed: 52 (32aa160d), 53 (e7c58e06) + 53b (342dc379), 54 (8d27003d),
55 (c34ccff6), 56 (92db95fc), 57 (153804d7), 58 (374bc21f), 59a (e833eaa6), 59b (3df72bba),
60 (df33f77e), 61 (089652fc), 62 (d4fd8b3b), 63 (83af818e), 64 (74134e8d), 65 (79c8d90e +
044bc3a6), 66 (8a6f2e21), 66b (f8b4dc68), 67 (1cbfa737), 68 (2c77b0de), 69 (6a963cb3),
71 (dcf6fdf3), 72 (62f58c98), 73 (62b12d40), 74 (ba09af7b), 75 (917dd499), 76 (dcad437b),
77a (4451e20a), 77b (2348b0b8); native Edit-menu titles (5481df9f); 600-line split merged
(9963c029); 78 (54c7f97a), 79 (64d1ec73), 80 (0d976b08), 81 (a23312fc + 4b3e72eb), 82
(436fb910), 83 (ad4acc9e), 84 (c96c7cc3), 85 (e13dd126), 86 (2eef29d9), 87 (43143ec6), 88
(7e87ae82), 89 (bec04d0f), 90 (85f5a931). Resize sweep 9.9 s → 1.5–2.1 s with no per-resize
or per-scroll scene rebuild. Next: wave 91–98 (§10). Proof files: 155 → 112 (17 closed
ledgers deleted after wave 83–90); open GAP+PARTIAL rows 3703 → 3297.
User rulings this sprint: insert-cursor commits never seek or move the playhead in any
transport state (8f6d41d2, deliberate deviation from fork `mainwindow.cpp:520-528`; Go to
Start still rewinds); the ~115 ms anti-click settle hold on resume stays; blank-slot undo
tokens survive an external source refresh, matching the fork (78). Open decision:
catalog-outage status path (Swift scan has none). Fork oracle: `fceecd88`
(`git show fceecd88:<path>`).

## 1. Objective and success criteria

Contract: a mounted Swift/QML surface reproduces fork behavior,
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
- No new C++; comments at most 2 lines; one message-anchored predicate per fork clause; WCAG AA beats
  parity where they conflict; visual parity with `fceecd88`; base-font sizing only.

## 8. Wave 79+

Freeze: after the 600-line split and S-path repair (9963c029, 344b711b).
Counts below are exact selected GAP/PARTIAL sites from `deno task proof sites`,
not the stale §2 estimates. Oracle remains `fceecd88`.

| Task | Mounted surface and outcome | Selected open rows | Dependencies / group |
| --- | --- | ---: | --- |
| [79](task-79-brief.md) | Automation selected drag/Delete and single-node commit reach the playback timeline; preserve raw Tempo and same-tick CC order through undo/redo | 24 PARTIAL | Group A |
| [80](task-80-brief.md) | Velocity locked/unlocked relative drag proves square, wave and noise preview isolation, press-time latch and exact release values | 20 PARTIAL | Group A |
| [81](task-81-brief.md) | Window Insert Time opens the already-mounted bars/beats prompt without a range; active-song, zero/cancel/stale and undo laws | 7 PARTIAL + 20 GAP | Group A |
| [82](task-82-brief.md) | Roll keyboard shows real drum-pad names/fallbacks and preserves initial-program classification across cursor/playhead changes | 15 GAP | Group A |

All four are SDD-track, `sdd-implementer`: each is one behavior surface with
multiple production/check seams (the justified exception to the three-file
sizing default). **79 ∥ 80 ∥ 81 ∥ 82**: closed write sets are pairwise disjoint,
including ledgers and check files. No task consumes another wave task's new
interface. Land the settled split first; no task writes task-78's reserved
files or `voicegroupsave/proof.switching.txt` A030–A046.

Hot-file ownership: 81 alone owns `tst_ShellWindow.qml`; 82 alone owns
`DocumentWorkspace.swift`. `ShellWindow.qml`, `ShellPresenter.swift`,
`ApplicationSession.swift`, `EditorSurface.qml`, `PianoGrid.swift` and
`tst_EditorDrawer.qml` have **no writer in this wave**. 79 owns
`tst_ShellGridInput.qml`, 80 owns `tst_ShellDrawerParity.qml`, and 82 owns
`tst_TimelinePan.qml`. Do not silently grow
a write set; any later same-file writer waits for accepted work to be checkpointed.
One integration milestone follows Group A; shared builds/checks run after writers
settle, never concurrently with half-landed edits.

**Wave constraints (incorporated by every brief).** No new C++ outside native
boundaries; these four tasks require none. Touched Swift uses Swift 6.4 idioms:
Span/MutableSpan/RawSpan, InlineArray, ~Copyable and borrowing/consuming where
appropriate, typed throws and strict concurrency; no hot-path temporary
collections, copies or repeated font measurement. Comments are at most two lines.
All new geometry derives from the base font; WCAG AA with real GridPalette
surface/text pairs outranks pixel parity. Window shortcuts outrank incidental
chrome focus; no second dispatcher, synthetic forwarding or focus memory, and
persistent chrome never claims bare Space. One message-anchored predicate per
fork clause, existing messages verbatim, real fixtures and no test-only seams.
Delete an obsolete implementation-pinning assertion rather than rewording it;
repair its affected ledger anchor in that same surface change.
`Qt.callLater` coalescing and idempotence-guard workarounds are banned; any
workaround needs user approval. Deferred menu rows stay absent: New Song,
Import MIDI, Export WAV, Register Song, Import Sample, Theme. `project`,
`samplecheck`, `onboardcheck`, and `midi/tst_midiexport` remain parked.

Use each brief's recorded commands without rediscovery. Each verification
invocation has a 180 s ceiling, on the controller's settled, built tree; shell
lanes are separate `deno task verify:shell --filter <entry> --verbose` calls.
No unfiltered shell aggregate. The controller builds once, executes the listed
lanes and mounted smoke journeys, then runs `deno task proof check --executed`.
Missing execution evidence leaves a row open; a green pre-change behavioral
baseline is reported honestly, never manufactured into RED.

Rejected for this wave: the remaining editor/picker voicegroupsave sample has
only seven coherent behavioral PARTIALs (editor A010/A021/A023; picker
A004/A017/A024/A038), not a 15-row task; do not pad it with pointer/file-staging
checks. Clipboard's combined Qt notification masks are not new behavior;
selection-owner work also collides with task 78's `DocumentSession.swift`.
Open user decisions stay out: `voicegroupsave/proof.savecore.txt` A016–A026
(especially A017: whether catalog outage gains a status/error path while
retaining the last valid catalog), and reserved `proof.switching.txt` A030–A046
(whether blank materialization tokens rebase across unrelated same-section
external edits or retain E10 blanket expiry). No brief resolves either policy.

## 9. Wave 83+

Planning baseline: HEAD `e334b318ecf391e3d4fac512c4a613303aff01e3`; fork oracle
`fceecd88`. This wave starts **after 79–82 land**. Counts are exact selected
GAP/PARTIAL A-sites queried with `deno task proof list|sites|show`, not the stale
§2 census or §6 estimates. Each brief records its selected IDs, existing mounted
owner, fork laws, closed write set and executing evidence lane. Rebase the
specific shared files named below after their earlier writer lands; do not
claim the 86 rows already assigned to 79–82 again.

### Tasks and selected census

| Task | Mounted surface and bounded change | GAP | PARTIAL | Target MATCHED / RETIRED |
|---|---|---:|---:|---:|
| [83](task-83-brief.md) | Cross-tab A/V/P drawer state and complete chrome/lane preference reload/poison boundaries | 25 | 6 | 29 / 2 |
| [84](task-84-brief.md) | Startup/legacy recipe restore, Opened status, real close/restart, fresh reopen versus in-place reload | 27 | 7 | 32 / 2 |
| [85](task-85-brief.md) | Drawer routing isolation, voice drag/cancel feedback, physical held-B pencil and rendered point-menu Delete | 14 | 25 | 35 / 4 |
| [86](task-86-brief.md) | Ruler/time/note command menus, exact history/clipboard clauses, latched pencil velocity and press-to-focus | 7 | 30 | 37 / 0 |
| [87](task-87-brief.md) | Physical two-note keyboard routing, chrome exclusion/focus retention, lane Copy/Delete/Paste and platform bindings | 0 | 50 | 38 / 12 |
| [88](task-88-brief.md) | Atomic range/note/track scope payloads and native clipboard displacement through the production song filter | 17 | 22 | 32 / 7 |
| [89](task-89-brief.md) | Voicegroup dock edit/save/reopen, completed-save receipts, engine-byte convergence, picker/synth residuals | 18 | 20 | 35 / 3 |
| [90](task-90-brief.md) | Camera/grid lattice and signature laws, mounted remap/resize survival, native ingress/order retirement | 14 | 41 | 28 / 27 |
| **Total** | **323 selected open rows; 266 behavior predicates and 57 bounded representation retirements** | **122** | **201** | **266 / 57** |

These are selected A-sites, not promises to close every ledger in each family.
Every representation retirement cites its exact fork expression and the fresh
owning-surface journey; counts never justify retiring an observable failure.

### Two parallel write groups

1. **Group A: 83, 85, 88, 90** — 164 selected rows. Their complete exact write
   sets, including conditional production repairs, are pairwise disjoint.
2. **Checkpoint A:** all four task evidence/review gates pass on the settled
   tree; make one accepted group checkpoint before any shared-file reuse.
3. **Group B: 84, 86, 87, 89** — 159 selected rows. Their complete exact write
   sets are also pairwise disjoint. 84 consumes 83; 86 consumes 85's QML-file
   handoff; 87 consumes 83's file plus 85/88's behavior contracts.
4. **Checkpoint B:** settle, build/verify once, finish each task's review gate
   and make the final group checkpoint. No per-task commit churn.

The controller owns integration. Per-task before/after structural inspection,
evidence/review gates and bounded fix loops follow `sdd-execution-loop`; no
writer silently enlarges its closed write set.

| Hot file | Group A owner | Group B owner |
|---|---|---|
| `ShellWindow.qml` | — | 84 |
| `ShellPresenter.swift` | — | 84 |
| `ApplicationSession.swift` | 83 | 84 |
| `DocumentWorkspace.swift` | — | 84 |
| `EditorSurface.qml` | — | 86 |
| `PianoGrid.swift` | unchanged | unchanged |
| `tst_ShellWindow.qml` | 83 | 87 |
| `tst_EditorDrawer.qml` | 85 | — |
| `EditorCommandRouter.swift` | unchanged | unchanged |
| `DocumentSession.swift` | — | 89, selected defect only |

Additional exact-file handoffs: **83 → 84**
`EditorViewStateCodec.swift` and `workspace/session_view_state.swift`;
**85 → 86** `tst_ShellGridMenu.qml`. There are no other cross-group write
intersections and no shared ledger writers.

Earlier-wave rebases are explicit in the briefs: **81 → 83/87**
`tst_ShellWindow.qml`; **81 → 86** `rollcheck/note_commands.swift`;
**82 → 84** `DocumentWorkspace.swift`; **79 → 85**
`AutomationInteraction.swift` if its selected-law repair is needed. Read
dependencies also rebase: 88 consumes 79/81 routing, 89 consumes 82's
`ProjectService.swift` engine boundary, and 90 consumes 82's
`GridScene+Rebuild.swift`. Preserve every 79–82 selected row and message.

**Execution contract.** All tasks are SDD-track, `sdd-implementer`: each crosses
the production/check/ledger boundary for one mounted behavior family. That
cohesive acceptance surface justifies exceeding the three-file default; no
task is a standalone ledger reconciliation. The exact write sets are closed.
Rows move only with the surface code and executed checks in the same change.
Retirement is limited to fork-proven representation inside its owning surface.

The §8 Wave constraints remain mandatory, including no new C++, Swift 6.4
idioms on touched Swift, two-line comments, base-font geometry and WCAG AA over
pixel parity; the sole window shortcut authority, no synthetic forwarding,
focus memory or bare Space capture in chrome; no `Qt.callLater` coalescing or
idempotence guards; real fixtures, no test-only seams, one message-anchored
predicate per fork clause and existing messages verbatim. Workarounds need
user approval.

**Verification policy for this wave supersedes §8's no-aggregate-shell sentence.**
The controller builds the settled write group once and deduplicates its named
lanes. All shell lanes run together in about 40 s through
`deno task verify:shell --verbose`; a single lane uses
`deno task verify:shell --filter <entry> --verbose`. Both modes emit each lane's
`build/proof-evidence/<entry>.json`. Every invocation has a **180 s ceiling**.
Reuse the briefs' exact Swift/roll/shell commands without rediscovery unless
scope or registration changes. Parallel writers do not run shared builds,
checks or formatters against each other's partial edits. Read-only inspection
and proof queries remain available. Fresh mounted journey evidence is required,
then `deno task proof check --executed`; a green related test does not close an
unexecuted clause. No builds, checks, formatting or commits were run to author
this plan.

**Unchanged boundaries.** `project`, `samplecheck`, `onboardcheck`, and
`midi/tst_midiexport` remain parked (P3 WAV export still awaits the user).
Deferred menu rows stay out: New Song, Import MIDI, Export WAV, Register Song,
Import Sample and Theme. Sidecar-directory snapshot rows remain blocked on the
parked project-store boundary, not retired as representation.

The outstanding user-decision rows are
`voicegroupsave/proof.savecore.txt` **A016–A026**, especially A017: whether a
catalog outage must publish a production status/error path saying the sound
directory is unavailable while retaining the last valid catalog. They remain
unchanged. §8's blank-token decision wording is stale: task 78 records the
user's fork-matching ruling and `proof.switching.txt` A030 is now MATCHED.
Keep A030–A046 outside this wave and preserve the settled token-rebase contract;
do not present that policy as another unresolved user decision.

Other explicitly unselected technical work is not another user decision:
voicegroupsave savecore A003/A004/A015 (cohesive failed-rebind cfg/status/undo)
and A075 (deterministic mounted stale-save receipt), clipboard clipmime A017
(decode-failure announcement), the 19 laneselection rows, and unselected
camera/draw/remap/prompt rows. Tasks 85/86/83–84 do not implicitly own those
residuals merely because their surfaces are adjacent.

## 10. Wave 91+

This wave starts **after 84/86/87/89 land**, not alongside the current Group B.
It builds eight bounded user-visible surfaces, using their open proof rows as
acceptance specifications. `deno task proof sites` GAP/PARTIAL queries verified
**342 selected open rows: 134 GAP + 208 PARTIAL**, with 35–57 rows per task.
These are selected-row counts, not predictions that every row becomes MATCHED:
native representation retirements are explicitly bounded inside their owning
surface briefs. No dispositions changed while authoring this plan.

| Task | Surface and brief | Selected GAP / PARTIAL | Group | Route and sizing reason |
| --- | --- | ---: | --- | --- |
| 91 | [Active-tab range Insert/Delete Time during playback](task-91-brief.md) | 52: 7 / 45 | A | SDD-track: playback, selection scope, undo and inactive-document isolation cross the router and mounted shell. |
| 92 | [Mixed automation range drag/Delete and exact raw events](task-92-brief.md) | 45: 2 / 43 | A | SDD-track: one transaction spans Tempo, CC and logical XCMD occurrences; pure and mounted evidence are both required. |
| 93 | [Painted note frames and pre-roll/ruler raster](task-93-brief.md) | 41: 23 / 18 | A | SDD-track: scene values do not prove DPR/font-dependent pixels; representation retirements need sibling raster evidence. |
| 94 | [Velocity ruler/paint detents across instrument families](task-94-brief.md) | 57: 2 / 55 | A | SDD-track: square/wave/noise share press/move/release laws and one real program-flow verification surface. |
| 95 | [Local capture and routing after tab replacement](task-95-brief.md) | 35: 25 / 10 | B | SDD-track: captured input target, modal repeat, cancellation and document lifetime share keyboard authority. |
| 96 | [Automation hover topology and hint recovery](task-96-brief.md) | 36: 17 / 19 | B | SDD-track: pointer/render/hint ownership transitions need real mounted input and raster evidence. |
| 97 | [Roll band/modifier velocity/resize commit boundaries](task-97-brief.md) | 35: 20 / 15 | B | SDD-track: provisional presentation versus committed selection/history spans the same roll gesture surface. |
| 98 | [Transport toolbar volume isolation, raster and key priority](task-98-brief.md) | 41: 38 / 3 | B | SDD-track: persisted global output, per-song state and chrome input must agree in the mounted toolbar. |

All seats are `sdd-implementer`. The >3-file exceptions above are cohesive
surface/verification boundaries, not permission to expand scope. Exact A-row
lists, source provenance, symbol preservation and **closed write sets** live
in the linked briefs. Conditional production files count as owned files even
when existing behavior already passes. RED may be absent when production
already matches; then the new consumer-visible check is the deliverable.

### Two parallel write groups and hot-file ownership

**Group A: 91 + 92 + 93 + 94 — 195 rows (34 GAP + 161 PARTIAL).**
The four exact write sets are pairwise disjoint:

- **91** owns `EditorCommandRouter.swift`, `session_time_routing.swift`,
  `tst_ShellWindow.qml` and the selected mainwindowrouting input rows.
- **92** owns automation `AutomationEdits.swift`,
  `AutomationInteraction.swift`, `AutomationSelectionCommands.swift`;
  `gestureNodeDrag.swift`, `xcmd.swift`, `automationselection.swift`,
  `tst_ShellGridInput.qml`, and the contract/crosslane ledgers.
- **93** owns `GridScene+Notes.swift`, `GridScene+Primitives.swift`,
  `GridScene+Rebuild.swift`, the note border/ghost checks,
  `tst_ShellNoteVisuals.qml`, and its note-rendering/resize/camera/geometry rows.
- **94** owns `VelocityInteraction.swift`, `VelocityTransactions.swift`,
  both existing VelocityPaintDetent check files, `tst_ShellDrawerParity.qml`
  and the selected detent-painting rows.

Task 91 consumes the existing range transform but cannot edit task 92's
selection-command owner. No task in A writes `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `ShellWindow.qml`, `EditorSurface.qml` or fixtures.
Task 93's camera/geometry ledger edits rebase over accepted task 90.

**Group B: 95 + 96 + 97 + 98 — 147 rows (100 GAP + 47 PARTIAL).**
Start only after the accepted Group A checkpoint. Its exact write sets are
also pairwise disjoint:

- **95** exclusively owns `EditKeyArbiter.swift`, `ShellWindow.qml`,
  `VelocityInteraction.swift`, `localinputtier_text.swift`,
  `tst_ShellWindow.qml`, `tst_ShellTabs.qml`, `tst_ShellPitchBend.qml`,
  and the selected lifetime/pitch-bend/gesturevelocity ledgers.
- **96** exclusively owns automation `AutomationInteraction.swift`,
  `AutomationLifecycle.swift`, `AutomationOverlayPublication.swift`,
  `AutomationPage.qml`, the canvas-hover/phantom checks,
  `tst_EditorDrawer.qml` and the three selected hover/parity ledgers.
- **97** exclusively owns `PianoGrid.swift`, `PianoGrid+Gestures.swift`,
  `GridScene+Notes.swift`, `EditorSurface.qml`, the selection-band/audition/
  editing and resize checks, `tst_SwiftRollSelection.qml`,
  `tst_ShellGridInput.qml` and the selected selection/resize ledger rows.
- **98** exclusively owns `TransportBarPresenter.swift`,
  `src/ui/shell/TransportBar.qml`, `src/ui/shell/TransportOutputDial.qml`,
  `transport_checks.swift`, `tst_ShellTransport.qml` and selected
  `workspace/proof.tabs_transport.txt` rows.

The only cross-group file reuse is explicit:

| Earlier owner → later owner | Files requiring accepted checkpoint/rebase |
| --- | --- |
| 91 → 95 | `src/checks/editorqml/tst_ShellWindow.qml` |
| 92 → 96 | `src/swift/app/drawer/automation/AutomationInteraction.swift` |
| 92 → 97 | `src/checks/editorqml/tst_ShellGridInput.qml` |
| 93 → 97 | `src/swift/app/roll/GridScene+Notes.swift`, `src/checks/rollcheck/proof.resize.txt` |
| 94 → 95 | `src/swift/app/drawer/velocity/VelocityInteraction.swift` |

Incoming rebase boundaries from the active wave are equally binding:
84's `ShellWindow.qml`/`tst_ShellTabs.qml` → 95; 86's
`EditorSurface.qml`/`selection_editing.swift` → 97; 87's
`tst_ShellWindow.qml` → 91/95 and `localinputtier_text.swift` → 95.
Every brief names read dependencies on 84's workspace/session binding,
86's press-focus ingress, 87's key priority and 89's document/voice binding.
Task 89's write set and selected rows are not reused concurrently.

Checkpoint accepted 83–90 work before this wave; checkpoint accepted Group A
before B reuses its files; checkpoint remaining accepted work at final handoff.
There are no per-task commit milestones. A failing/unreviewed task is repaired
before its files pass to the next owner. A root-cause repair outside a closed
set requires revising ownership and checking disjointness, not a workaround
or a silent file-set expansion.

### Wave constraints and verification

Preserve §6/§8/§9 boundaries. No new C++; touched Swift follows Swift 6.4
idioms, with no avoidable hot-path allocation/copy/computation. Comments are
at most two lines; geometry derives from the base font; WCAG AA through
GridPalette beats pixel parity. Keep a single keyboard authority: no second
dispatcher, synthetic forwarding or focus memory; persistent chrome never
claims bare Space. `Qt.callLater` coalescing and new idempotence guards are
banned. Workarounds need user approval, not an implementer's local exception.

One literal message-anchored predicate per fork clause; preserve existing
messages verbatim. Prove real behavior using the real staged project and
existing production interfaces, never mock echoes, source-text assertions,
test-only probes or a new observation API just to close a row. Retire only
the specifically named native prerequisites alongside their executing sibling
surface laws. Delete obsolete implementation/wording checks rather than
re-pinning them. Rows change only with their proving code/checks; no standalone
ledger reconciliation, broad re-anchoring or ledger deletion.

**Fixture and preferences lessons are mandatory.** Checked-in fixture content
is outside all eight closed write sets. Existing runtime fixture builders may
stage notes/events through real document APIs. If an approved repair genuinely
requires a fixture edit, first grep/read every consumer asserting its exact
contents and put **all** those checks in the revised write set; reschedule
owners before editing. Task 81 demonstrated why a locally green lane is not
enough. Preferences are CFPreferences/UserDefaults-backed: stage poisoned or
persisted state through that domain and synchronize it, never by plist bytes.

The controller owns settled-group builds/checks/formatting; parallel writers
perform read-only inspection and proof queries, not mid-flight shared checks.
Reuse the exact commands in each brief; reassess only for a concrete scope or
registration change. Deduplicate identical commands across accepted tasks in
a settled group, not their predicates. Every task's acceptance includes both:

- **Full `deno task verify:shell --verbose`**, all 26 lanes (~40 s warm).
- **Full `deno task verify`** (~10 s warm).

Narrow `swiftcore-projectsession` and mounted shell/editor/roll lanes still
establish the task's actual surface. A passing full suite does not excuse a
missing mounted journey. All builds and verification serialize as:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task ...
```

The lock may wait for another owner; the invoked verification process has a
175 s alarm and must complete within **180 s**. Never launch competing builds
or silently narrow a timed-out full suite. Require fresh per-lane function
evidence under `build/proof-evidence`, then serialized
`deno task proof check --executed`. Use `deno task proof sites` GAP/PARTIAL to
confirm only the selected rows moved. Offscreen raster/focus and null-backend
audio observations do not establish physical macOS host/cursor/audio behavior.
No builds, test suites, formatters or commits were run to author this wave.

### Explicit exclusions and unresolved decisions

`project`, `samplecheck`, `onboardcheck` and `midi/tst_midiexport` remain
parked; P3 WAV export awaits the user. Deferred menu rows remain out: New Song,
Import MIDI, Export WAV, Register Song, Import Sample and Theme. Native `host`
rows requiring physical macOS observation stay out unless a mounted QML lane
can actually observe the selected behavior.

The unresolved catalog-outage policy is still
`voicegroupsave/proof.savecore.txt` **A016–A026**: whether a production
status/error must report unavailable sound-directory state while retaining
the last valid catalog. This wave does not decide it. Switching A030–A046
were settled by task 78; blank-token rebasing is not a new user decision.

Technical residuals, not new policy questions: roll custom left/right
cursor-image rows (resize A002–A004/A027/A028); unselected camera/geometry and
raw-event conductor-remap rows; velocity's six native geometry prerequisites;
unselected prompt/clipboard/lane-selection and native-host rows; and
workspace tabs_transport A062, whose applied-song-volume engine readback
cannot be replaced by a cfg-value check or a test-only getter. Other
`selftest_transport` seek/cursor rows are not implicitly owned by toolbar 98.
No task absorbs these residuals merely because it edits an adjacent surface.

## 11. Wave 99+

### Scope and dispatch gate

Eight surface-first tasks select **367 currently open rows: 178 GAP + 189
PARTIAL**, each within 35–70 rows. Thirteen scoped ledgers can close completely.
This is the successor to **all** of 91–98, not an alternative dispatch while
91–94 implement or 95–97 wait. Task 98's accepted checkpoint is `759ee469`;
the remaining predecessors must land before any task below starts.

The census below is a **live working-tree planning snapshot**, not the tree
at `759ee469`: 91–94's proving sources/ledger updates were in flight while it
was collected. Final read-only queries found **112 ledgers, 108 nonempty,
2,246 GAP + 834 PARTIAL = 3,080 open rows**. The parked project/sample/onboarding
families plus MIDI export account for **1,232**; **1,848** are outside those
parked families, not all immediately eligible. Earlier in-flight counts are
superseded by this table, not represented as completed/committed work.

Discovery used `deno task proof list --area <area>` for all 31 current areas,
then paged `proof sites <ledger> --status GAP|PARTIAL --offset <n>` and
`proof show` for source contexts/provenance. All 367 selected identities were
rechecked against current open dispositions; none overlaps a selected 91–98
row. Camera A093 remains GAP and was explicitly confirmed unowned by 93,
despite the older brief's “already closed” sentence. Source line citations
are this planning snapshot's navigation aids: refresh them after rebasing.

### Tasks and parallel groups

| Task | Surface | GAP | PARTIAL | Total | Whole-ledger closures |
|---|---|---:|---:|---:|---:|
| [99](task-99-brief.md) | Fresh-tab focus, complete Copy payload, exactly-once Solo | 34 | 14 | 48 | 0 |
| [100](task-100-brief.md) | Automation selection, captured tool mode and ghost ownership | 19 | 28 | 47 | 2 |
| [101](task-101-brief.md) | Velocity drawer painted context, ruler and stable chrome | 3 | 54 | 57 | 1 |
| [102](task-102-brief.md) | Track/time selection through remap and real keyboard edits | 26 | 18 | 44 | 1 |
| [103](task-103-brief.md) | Complete retained drawer state, reload and final-close transport | 32 | 15 | 47 | 1 |
| [104](task-104-brief.md) | Automation lead-in/step/range raster and pencil commit/undo | 35 | 10 | 45 | 2 |
| [105](task-105-brief.md) | Exact roll lattice, end draw and synchronized keyboard context | 20 | 16 | 36 | 2 |
| [106](task-106-brief.md) | Numeric/Event List local keys, cancellation and resumed commands | 9 | 34 | 43 | 4 |
| **Total** | | **178** | **189** | **367** | **13** |

- **Group A:** 99, 100, 101, 102 — **196 rows**.
- **Checkpoint A:** accepted sources, fresh verification, task reviews and
  surface-owned ledger changes land together before any shared file is reused.
- **Group B:** 103, 104, 105, 106 — **171 rows**, rebased on Checkpoint A.
- **Checkpoint B:** integrated acceptance and review; no per-task Git churn.

The expanded exact write sets contain 81 existing paths, including every
conditional production repair and selected ledger. They are pairwise
disjoint **within each group**. “Conditional” does not exempt a file from
ownership. No shared fixture, registration, CMake, check-bootstrap or helper
file is implicitly writable. The controller alone updates this section's
accepted status alongside the proving group checkpoint; implementers do not
edit one another's briefs or broaden their write sets.

| Hot write set | Group A owner | Group B owner / handoff |
|---|---|---|
| `ShellWindow.qml`, `tst_ShellWindow.qml` | 99 | 106; preserve 99's selected-tab command laws |
| `AutomationInteraction.swift`, `AutomationContentPublication.swift`, `AutomationOverlayPublication.swift`, `AutomationPage.qml`, `automationselection.swift`, `tst_EditorDrawer.qml` | 100 | 104; preserve 100's captured selection/tool ownership |
| `PianoGrid.swift`, `keyboard.swift`, `tst_ShellGridInput.qml` | 102 | 105; preserve 102's key/history/ruler laws |
| Velocity page/context/publication/scene, `EditorDrawerLayout.swift`, `EditorDrawer.qml`, `tst_ShellDrawerParity.qml` | 101 | No Group B writer |
| Application/tab lifecycle, state codec, `tst_ShellTabs.qml` | None | 103 only |
| Prompt QML, `DragInput.qml`, key arbiter and Event List sources/checks | None | 106 only |

Incoming rebase dependencies include the actual hot files, not only task
numbers:

- **91 → 99/106:** input ledger, command router and mounted ShellWindow check.
  The new rows are Copy/Solo/fresh-tab rows, never 91's range-time rows.
- **92 → 100/102/104/105:** automation interaction/selection checks and
  `tst_ShellGridInput.qml`. Preserve fractional Tempo and raw-event identity.
- **93 → 102/105:** note scene, ruler scene, camera/geometry ledgers and raster
  contracts. Camera A092/A094–A098 and geometry A020–A026 remain 93's rows.
- **94 → 101:** `tst_ShellDrawerParity.qml` and the accepted velocity
  detent/commit behavior. 101 does not take its interaction/transaction owner.
- **95 → 99/103/106:** ShellWindow, ShellTabs, localinputtier_text and key
  arbiter; preserve retiring-page and captured-target lifetime laws.
- **96 → 100/104:** automation interaction/overlay, page QML and drawer checks;
  preserve hover/hint recovery. Other consumers retain its published behavior.
- **97 → 102/105/106:** grid/note scene/input and local key outcomes; preserve
  provisional pointer selection and history commit boundaries.
- **98 → all:** no overlapping write file, but its accepted toolbar,
  per-song/global volume split and Space priority are required baseline laws.

### Whole-ledger cutovers

These are deletions **with their proving surface**, after all selected rows
and retained anchors pass. Original C++ sources are already absent; do not
recreate them or delete unrelated sources.

| Task | Completed ledgers beneath `src/checks/` |
|---|---|
| 100 | `automation/proof.automationownership.txt`, `automation/proof.automationselection.txt` |
| 101 | `drawerpresentation/proof.velocity.txt` |
| 102 | `clipboard/proof.selectioncheck_tracks.txt` |
| 103 | `workspace/proof.selftest_workspace.txt` |
| 104 | `automation/proof.automationpainting.txt`, `automation/proof.automationpencil.txt` |
| 105 | `rollcheck/static/proof.camera.txt`, `timelinepan/proof.tst_timelinepan.txt` |
| 106 | `selectionkey/proof.localinputtier_text.txt`, `selectionkey/proof.localinput.txt`, `selectionkey/proof.localinputtier_eventlist.txt`, `drawerpresentation/proof.valueprompt.txt` |

The text-input ledger uses `Original <line>` identities and covers two named
methods, not every method from the historical C++ file. Its deletion is a
closed **scoped ledger**, not a whole-file port certificate. Other ledgers
move only the exact rows named in their briefs. Native fixture prerequisites
are individually identified in the briefs and retire only alongside executed
surface behavior, never as a standalone reconciliation sweep.

### Inherited constraints and verification

**All §10 “Wave constraints and verification,” its fixture/preferences
lessons, and the preserved §6/§8/§9 boundaries apply verbatim.** Every brief
links this policy as part of its contract; no omission of a repeated sentence
grants an exception. In particular:

- No new C++; Swift 6.4 conventions and no avoidable hot-path allocation,
  copying or computation. Comments are at most two lines. Geometry derives
  from base font; WCAG AA via GridPalette outranks pixel parity.
- One keyboard authority. No synthetic forwarding, second dispatcher or
  focus memory; persistent chrome never claims bare Space. No new
  `Qt.callLater` coalescing or idempotence guards. Existing touched defects
  must be repaired at their actual ownership/lifecycle boundary, not hidden
  by a workaround; workarounds require user approval.
- Preserve old predicate messages; new anchors are unique complete literals,
  not interpolated phases. Assert each original behavioral conjunct.
  Setup/identity/wording checks do not become new permanent behavior tests.
  Delete obsolete checks rather than re-pin them. No mocks, test-only seams
  or observation APIs manufactured to close rows.
- Checked-in fixture content is outside every write set. Runtime builders may
  use real document APIs. An approved fixture change first requires every
  exact-content consumer to be found/read, included in the revised write set,
  and rescheduled. No local-green exception to full consumer verification.
- Stage and observe preferences through CFPreferences/UserDefaults and
  synchronize the domain, not plist bytes or a cached plist oracle.
- RED may be absent: name the already-correct production law, add its missing
  meaningful consumer conjunct and report that fact honestly. Do not induce a
  defect, fake RED or add a setup-only assertion to make a ledger move.

The controller waits for settled writers, inspects before/after structure and
then runs each brief's narrow domain/mounted commands and review gate.
Every task requires **full `deno task verify:shell --verbose` (all 26 lanes)**
and **full `deno task verify --verbose`**, plus fresh per-lane execution
evidence and **`deno task proof check --executed`**. Identical commands may be
deduplicated across an accepted settled group; predicates, data rows and
mounted journeys may not. Task 105 also selects `tst_TimelinePan.qml` through
the existing per-process roll-suite environment.

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task ...
```

The lock may wait; after acquisition each invoked command must finish within
**180 seconds**, with the existing 175-second alarm. No concurrent builds,
mid-flight shared checks, silent suite narrowing or unapproved timeout
workarounds. Fresh mounted smoke is mandatory: direct presenter checks alone
do not prove raster, focus or key delivery. Offscreen Qt window activation
does not claim physical macOS host behavior. Parallel implementers inspect
and query proofs; controller-owned verification starts only when the group
is stable. No builds, tests, formatters or commits were run to author this
wave; planning validation was read-only proof queries and ownership/count
inspection.

At dispatch, re-query the selected dispositions after all 91–98 land. If a
predecessor or user change alters a selected identity or necessary owner,
resolve the brief and group contract before edits; never silently substitute
unrelated rows. Bounded task reviews precede the two group checkpoints, and
proof ledgers change in the same accepted change as the proving sources.

### Explicit exclusions and remaining decisions

Unchanged: parked `project`, `samplecheck`, `onboardcheck` and
`midi/tst_midiexport`; P3 WAV export awaits the user. Deferred New Song,
Import MIDI, Export WAV, Register Song, Import Sample and Theme menu rows are
not selected. No `host` row is selected; physical host/cursor/audio claims
remain outside mounted offscreen evidence.

The user decision is still `voicegroupsave/proof.savecore.txt` **A016–A026**:
whether unavailable sound-directory/catalog state must publish a production
status/error while retaining the last valid catalog. Do not decide it in a
nearby surface. `workspace/proof.tabs_transport.txt` **A062** remains blocked
on real applied-song-volume observation, not a cfg proxy or test-only getter.

Technical residuals are not new policy questions: keyboard A077–A080's
invalid-unused-track Insert Time refusal, roll custom cursor images,
raw-event conductor promotion and per-owner cosmetics, unselected empty-view
geometry, endpoint-stack lane selection, corrupt-MIME failure routing and
the six velocity-detent fixture-geometry rows. Lifecycle sidecar snapshots
A004/A010/A031 and session A024/A042 still depend on project-store. Event
view chrome, remaining native/window lifecycle, MIDI, voicegroup and visual
families stay unselected where they do not fit these bounded mounted
surfaces; do not pad tasks merely to consume adjacent open rows.

### Recomputed per-ledger census

Paths below are relative to `src/checks/`. “Open” is GAP + PARTIAL, not a
claim that all those rows are eligible. Zero-row ledgers are included to make
the 112-file census complete; deleting unrelated closed inventories is not
part of this wave.

| Ledger | GAP | PARTIAL | Open |
|---|---:|---:|---:|
| `audio/proof.tst_audiobackend.txt` | 0 | 0 | 0 |
| `automation/hover/proof.tst_automationhover.txt` | 46 | 17 | 63 |
| `automation/presentation/proof.painting.txt` | 5 | 33 | 38 |
| `automation/presentation/proof.tst_automationpresentation.txt` | 15 | 2 | 17 |
| `automation/proof.automationcanvaslayout.txt` | 5 | 19 | 24 |
| `automation/proof.automationnodedrag.txt` | 12 | 1 | 13 |
| `automation/proof.automationownership.txt` | 16 | 21 | 37 |
| `automation/proof.automationpainting.txt` | 30 | 2 | 32 |
| `automation/proof.automationpencil.txt` | 5 | 8 | 13 |
| `automation/proof.automationselection.txt` | 3 | 7 | 10 |
| `automation/raster/proof.interaction.txt` | 33 | 0 | 33 |
| `automation/raster/proof.painting.txt` | 25 | 0 | 25 |
| `automationgesturecheck/proof.contract.txt` | 3 | 13 | 16 |
| `automationgesturecheck/proof.crosslane.txt` | 1 | 8 | 9 |
| `automationgesturecheck/proof.hover.txt` | 18 | 2 | 20 |
| `automationgesturecheck/proof.parity.txt` | 2 | 11 | 13 |
| `clipboard/proof.clipmime_test.txt` | 1 | 0 | 1 |
| `clipboard/proof.laneselection_test.txt` | 19 | 0 | 19 |
| `clipboard/proof.selectioncheck_tracks.txt` | 16 | 8 | 24 |
| `drawerpresentation/proof.valueprompt.txt` | 0 | 5 | 5 |
| `drawerpresentation/proof.velocity.txt` | 3 | 54 | 57 |
| `editorqml/proof.shell-theme.txt` | 0 | 0 | 0 |
| `eventviews/proof.chrome.txt` | 0 | 12 | 12 |
| `eventviews/proof.edits.txt` | 0 | 1 | 1 |
| `host/proof.tst_hostadapter.txt` | 49 | 17 | 66 |
| `host/proof.tst_hostintegration.txt` | 51 | 13 | 64 |
| `host/proof.tst_hostseams.txt` | 3 | 1 | 4 |
| `keyboard/proof.tst_velocitymodel.txt` | 27 | 0 | 27 |
| `mainwindowrouting/proof.tst_mainwindowrouting_input.txt` | 67 | 31 | 98 |
| `mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` | 94 | 45 | 139 |
| `mainwindowrouting/proof.tst_mainwindowrouting_native.txt` | 28 | 1 | 29 |
| `mainwindowrouting/proof.tst_mainwindowrouting_state.txt` | 80 | 22 | 102 |
| `midi/proof.tst_midiexport.txt` | 0 | 13 | 13 |
| `midi/proof.tst_midiroundtrip.txt` | 0 | 21 | 21 |
| `midi/proof.tst_midismf.txt` | 20 | 3 | 23 |
| `nativegraphics/proof.tst_nativewindowing.txt` | 35 | 0 | 35 |
| `onboardcheck/proof.action.txt` | 40 | 9 | 49 |
| `onboardcheck/proof.debuglayout.txt` | 72 | 0 | 72 |
| `onboardcheck/proof.deletion.txt` | 71 | 0 | 71 |
| `onboardcheck/proof.import.txt` | 51 | 0 | 51 |
| `onboardcheck/proof.regionedlayout.txt` | 82 | 0 | 82 |
| `onboardcheck/proof.registration.txt` | 88 | 0 | 88 |
| `onboardcheck/proof.support.txt` | 13 | 0 | 13 |
| `pitchbend/proof.curve.txt` | 0 | 1 | 1 |
| `polyphony/proof.polyphonygate.txt` | 4 | 0 | 4 |
| `polyphony/proof.polyphonypanel.txt` | 4 | 8 | 12 |
| `project/proof.identity.txt` | 17 | 35 | 52 |
| `project/proof.ioflow.txt` | 49 | 16 | 65 |
| `project/proof.iomutations.txt` | 43 | 54 | 97 |
| `project/proof.mk.txt` | 36 | 0 | 36 |
| `project/proof.save.txt` | 1 | 34 | 35 |
| `project/proof.workspace.txt` | 83 | 17 | 100 |
| `retained/proof.tst_nativeboundaries.txt` | 18 | 0 | 18 |
| `rollcheck/proof.identity.txt` | 6 | 0 | 6 |
| `rollcheck/proof.keyboard.txt` | 14 | 10 | 24 |
| `rollcheck/proof.note_rendering.txt` | 0 | 0 | 0 |
| `rollcheck/proof.presentation.txt` | 11 | 4 | 15 |
| `rollcheck/proof.remap.txt` | 7 | 17 | 24 |
| `rollcheck/proof.resize.txt` | 7 | 7 | 14 |
| `rollcheck/proof.scale_editing.txt` | 0 | 3 | 3 |
| `rollcheck/proof.scale_projection.txt` | 0 | 3 | 3 |
| `rollcheck/proof.selection.txt` | 13 | 13 | 26 |
| `rollcheck/static/proof.camera.txt` | 3 | 16 | 19 |
| `rollcheck/static/proof.gate.txt` | 55 | 6 | 61 |
| `rollcheck/static/proof.geometry.txt` | 19 | 4 | 23 |
| `samplecheck/proof.analysis.txt` | 21 | 0 | 21 |
| `samplecheck/proof.decoder.txt` | 93 | 0 | 93 |
| `samplecheck/proof.dsp.txt` | 61 | 0 | 61 |
| `samplecheck/proof.editor.txt` | 80 | 0 | 80 |
| `samplecheck/proof.integration.txt` | 68 | 0 | 68 |
| `samplecheck/proof.project.txt` | 63 | 0 | 63 |
| `samplecheck/proof.soundfont.txt` | 22 | 0 | 22 |
| `selectionkey/proof.corearrows.txt` | 1 | 0 | 1 |
| `selectionkey/proof.gesturecommands.txt` | 0 | 4 | 4 |
| `selectionkey/proof.gesturevelocity.txt` | 4 | 3 | 7 |
| `selectionkey/proof.localinput.txt` | 7 | 0 | 7 |
| `selectionkey/proof.localinputtier_eventlist.txt` | 2 | 2 | 4 |
| `selectionkey/proof.localinputtier_pitchbend.txt` | 4 | 6 | 10 |
| `selectionkey/proof.localinputtier_text.txt` | 0 | 27 | 27 |
| `selectionkey/proof.windowtier_keyboard.txt` | 0 | 15 | 15 |
| `selectionkey/proof.windowtier_lifetime.txt` | 17 | 1 | 18 |
| `support/corecheck/proof.tst_swiftcore.txt` | 0 | 0 | 0 |
| `swiftqtml/proof.tst_swiftqtml.txt` | 78 | 0 | 78 |
| `swiftrollbench/proof.tst_swiftrollbench.txt` | 6 | 0 | 6 |
| `swiftrollgated/proof.clipboardchecks.txt` | 2 | 0 | 2 |
| `themelayout/proof.tst_themelayout_color.txt` | 0 | 2 | 2 |
| `themelayout/proof.tst_themelayout_font.txt` | 7 | 4 | 11 |
| `themelayout/proof.tst_themelayout_scale.txt` | 3 | 0 | 3 |
| `themelayout/proof.tst_themelayout_settings.txt` | 33 | 1 | 34 |
| `timelinepan/proof.tst_timelinepan.txt` | 15 | 0 | 15 |
| `velocity/proof.tst_velocityediting.txt` | 0 | 5 | 5 |
| `velocity/proof.velocityclicks.txt` | 0 | 4 | 4 |
| `velocity/proof.velocitydetentdragging.txt` | 0 | 35 | 35 |
| `velocity/proof.velocitydetentpainting.txt` | 0 | 6 | 6 |
| `velocity/proof.velocitypainting.txt` | 0 | 3 | 3 |
| `velocity/proof.velocityroll.txt` | 0 | 18 | 18 |
| `velocity/proof.velocityselection.txt` | 2 | 6 | 8 |
| `visual/proof.browsers.txt` | 5 | 3 | 8 |
| `visual/proof.chrome.txt` | 3 | 4 | 7 |
| `visual/proof.dialogs.txt` | 24 | 0 | 24 |
| `visual/proof.quick.txt` | 5 | 0 | 5 |
| `voicegroup/proof.tst_voicegroupbank.txt` | 0 | 15 | 15 |
| `voicegroup/proof.tst_voicegroupviewcache.txt` | 3 | 1 | 4 |
| `voicegroup/proof.voicegroupsourceediting.txt` | 7 | 0 | 7 |
| `voicegroupsave/proof.presentation.txt` | 6 | 7 | 13 |
| `voicegroupsave/proof.savecore.txt` | 45 | 2 | 47 |
| `workspace/proof.selftest_timeline.txt` | 13 | 0 | 13 |
| `workspace/proof.selftest_transport.txt` | 3 | 7 | 10 |
| `workspace/proof.selftest_workspace.txt` | 13 | 0 | 13 |
| `workspace/proof.session.txt` | 8 | 0 | 8 |
| `workspace/proof.tabs_scale.txt` | 2 | 4 | 6 |
| `workspace/proof.tabs_transport.txt` | 1 | 1 | 2 |
| **Total** | **2,246** | **834** | **3,080** |
