# Sprint-3 plan: existing-surface parity after task 51

Status: **in execution.** Landed: 52 (32aa160d), 53 (e7c58e06) + 53b (342dc379), 54 (8d27003d),
55 (c34ccff6), 56 (92db95fc), 57 (153804d7), 58 (374bc21f), 59a (e833eaa6), 59b (3df72bba),
60 (df33f77e), 61 (089652fc), 62 (d4fd8b3b), 63 (83af818e), 64 (74134e8d), 65 (79c8d90e +
044bc3a6), 66 (8a6f2e21), 66b (f8b4dc68), 67 (1cbfa737), 68 (2c77b0de), 69 (6a963cb3),
71 (dcf6fdf3), 72 (62f58c98), 73 (62b12d40), 74 (ba09af7b), 75 (917dd499), 76 (dcad437b),
77a (4451e20a), 77b (2348b0b8); native Edit-menu titles (5481df9f); 600-line split merged
(9963c029); 78 (54c7f97a), 79 (64d1ec73), 80 (0d976b08), 81 (a23312fc + 4b3e72eb), 82
(436fb910), 83 (ad4acc9e), 84 (c96c7cc3), 85 (e13dd126), 86 (2eef29d9), 87 (43143ec6), 88
(7e87ae82), 89 (bec04d0f), 90 (85f5a931), 91 (1dd9b6cc), 92 (09b19bfb), 93 (58250a35), 94
(b516afee), 95 + 97 (28b4c04d), 96 (107297f6), 98 (759ee469), 99 (7e268ad3), 100 (ffa79554),
101 (1ec4681c), 102 (c9370c2a), 103 (cdf38968), 104 (2d12d967), 105 (d8557578), 106 (b18f81b8),
107 (f191a7e6), 108 (7847b5a6), 109 (a559cbad), 110 (84e346c6), 111 (13527590), 112
(9fe33068), 113 (0569546e), 114 (60b5784e), 115 (4c29c8de), 116 (9e1a2a3a), 117 (c86d72bf),
118 (75c352ca), 119 (2658dcc9), 120 (1fcb8d4e), 121 (ee7ef702), 122 (7a6a21ed), 123
(43cf03ec), 124 (cb00baf7), 125 (787d9bbc), 126 (d83ec31e), 127 (bd9958d9 + 487df50f), 128
(acdcd7e0), 129 (3b9bdd06), 130 (7c4f393b), 131 (236b8e7d), 132 (c9088d17), 133 (c2fe633e),
134 (df5d2c3c), 135 (99f51fb7), 136 (8b086787), 137 (97363697), 138 (e4aa0296); bank-edit
undo gate (3fbfe933). Resize sweep 9.9 s → 1.5–2.1 s with no per-resize or per-scroll scene
rebuild; user grid rework 7e292570. Wave 139–146 landed: 139 (e7e5cca9), 140 + 141
(a0175a60), 142 + 143 (9dd85c37), 144 (ab4f1ae5), 145 (4a8004bb), 146 (a74f402a). Wave
147–154 landed: 147 (efeb19a2), 148 (0e76e4e2), 149 (6b7a5777), 150 (d7cd2d64), 151
(5c3594ce), 152 (036e58d1), 153 (96cc9169), 154 (8f040917); editing-literal evidence fix
(0b12f4e7). Gate on 0b12f4e7: verify 36/36, verify:shell 75/75, verify:qml 1/1,
verify:qml-roll 1/1, verify:bridge 0 findings, `proof check --executed` 0 errors (0 not
executed). Wave 155–162 landed except 158 (in flight): 155 (3b268b98), 156 (4625fb42),
157 (57932bdc), 159 (bd2a11a9), 160 (db8e2fb3), 161 (d34169dd), 162 (07f1308d). Next:
wave 163–170 (§19). Census: proof files 155 → 63; open GAP+PARTIAL rows 3703 → ~1173
(wave-163 planning: 63 ledgers, strict-mapping debt 293). Wave 163–170 landed: 158
(4f8c16e7), 163 (21dd242f), 165 (2dc911ff), 166 (0cef1c3b), 167 (d3242623), 168 (4b49b544),
164 blocked on QtBridge QML→Swift object passing. Wave
171–174 landed: 171 (0c9f378d, New Song flow), 172 (2c2042c6), 173 (83e60dd7), 174
(487052d5); File-menu topology check follows the fork's New Song row (1364a2ac). Census:
62 ledgers; open GAP+PARTIAL rows 1132 (903 GAP + 229 PARTIAL); strict debt 286. Gate on
1364a2ac: verify 36/36, verify:qml 1/1, verify:qml-roll 1/1, bridge 0; verify:shell 74/76 —
shell-note-visuals is the rendering agent's in-progress test, shellwindow-label-commands
is an AutomationMenu focus race (Qt.callLater grab; fix pending foreign build). Wave
175–178 (§21) landed: 175 (a2e980cd), 177 (89ecda83), 176 + 178 (78af02d8); verify 37/37
on 78af02d8. Wave 179–187 (§22) landed, 181 completing it at 3c325bf1 + 85a806f9
(gesture ledgers deleted). Wave 188–193 (§23) landed: 188 (9ccb8d01, tab-close
exclusivity SIGABRT fixed), 189 (151dcfb4), 190 (ad0b7b1c), 191 (f4937597), 192
(461d81cb), 193 (30b8b356); 13 more closed ledgers deleted. Gate on b97c1c01: verify 37/37,
verify:shell 76/76, verify:qml 1/1, verify:qml-roll 1/1, bridge 0, `proof check --executed`
(b97c1c01). Census (per-area `proof list` sum): 47 ledgers; open rows 1034
(855 GAP + 179 PARTIAL); strict debt 235. Waves 194–199 (§24) landed
(432eaaa1). Wave 200–204 (§25) landed through 82ebde21 (205 skipped: its VG03 retirement
contradicts the wired creation ingress); hint text restores the fork's "⇧ Right-drag" spacing.
Gate on 82ebde21: verify 37/37, verify:shell 76/76, verify:qml 1/1, verify:qml-roll 1/1,
bridge 0, `proof check --executed` 0 not executed. Census: 42 ledgers; open rows 887 (762 GAP
+ 125 PARTIAL); strict debt 233. UX deviation awaiting the user: directional left/right resize
cursor art (rollcheck resize A002–A004/A027/A028; Swift shows one SizeHorCursor).
Wave 206–209 landed: 206 (fcecb8d4), 207 (77d8b50e), 209 New Voicegroup creation (b986ba08,
closes the sourceediting and save-presentation ledgers); 208 skipped (ledger-only mapping).
Gate on b986ba08: verify 37/37, verify:shell 76/76, verify:qml 1/1, verify:qml-roll 1/1,
bridge 0, `proof check --executed` 0 not executed. Census: 39 ledgers; open rows 871 (749 GAP
+ 122 PARTIAL); strict debt 215. Wave 210–212 (§28) feature ports landed: 210 New Song
label fold/filter + taken-name gate (41a7ebc4), 211 File → Register Song (8d338281), 212
rename returns roll focus (ae48c95d). Gate on 41a7ebc4: all lanes green, 0 not executed.
Known residues: QtBridge queues property notifications, so same-GUI-pass geometry clauses
(host A095) stay PARTIAL; lanes use the null audio backend, so physical-output conjuncts
stay PARTIAL.
User rulings this sprint: insert-cursor commits never seek or move the playhead in any
transport state (8f6d41d2, deliberate deviation from fork `mainwindow.cpp:520-528`; Go to
Start still rewinds); the ~115 ms anti-click settle hold on resume stays; blank-slot undo
tokens survive an external source refresh, matching the fork (78); a voicegroup switch is
an undoable edit (deliberate deviation: the fork switch is display-only); fork states that
Swift guards make unreachable close as RETIRED-REPRESENTATION with refusal predicates —
track beyond the used tracks (159), time-signature edit under Insert Time (168), null
voicegroup (166). Open decisions: catalog-outage status path (Swift scan has none);
pending-reload input gate. Fork oracle: `fceecd88`
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

## 12. Wave 107+

### Scope and selection

This wave follows the **entire accepted 99–106 wave**. It is not permission to
race its remaining writers. The planning census below was read with
`deno task proof list --area ...` while that wave was still landing:
**108 ledgers, 2,092 GAP + 698 PARTIAL = 2,790 open rows**. This is an
in-flight snapshot, not a settled post-106 baseline or an execution result.
The parked project/sample/onboarding/MIDI-export families account for
**1,232** of those rows; **1,558** are outside those parked families, before
other exclusions. Three zero-open ledgers remain in the census.

Select **354 rows: 160 GAP + 194 PARTIAL**, exactly 35–61 per brief. These
are eight user-visible surfaces, not eight arbitrary ledger partitions.
Sixteen ledgers are full-closure candidates, conditional on the stated
predecessor handoff and all retained obligations being resolved. No closed
ledger is deleted merely because its selected subset passed.

| Task | Surface / brief | GAP | PARTIAL | Open | Full-closure candidates |
|---|---|---:|---:|---:|---:|
| 107 | [Insertion value prompts and stable drawer geometry](task-107-brief.md) | 5 | 37 | 42 | 3 after 106 residue handoff |
| 108 | [Velocity raw detent/ramp transaction](task-108-brief.md) | 0 | 44 | 44 | 3 |
| 109 | [Ready ruler controls and bounded hover help](task-109-brief.md) | 55 | 6 | 61 | 1 |
| 110 | [Voice release, asynchronous save and Undo](task-110-brief.md) | 34 | 9 | 43 | 0 |
| 111 | [Automation lane/tab/ghost presentation](task-111-brief.md) | 20 | 35 | 55 | 2 |
| 112 | [Velocity selection, cancellation and roll handoff](task-112-brief.md) | 2 | 33 | 35 | 4 |
| 113 | [Drawer chrome keys and pitch-bend ownership](task-113-brief.md) | 12 | 23 | 35 | 3 |
| 114 | [Pointer-owned mouse hints across tabs](task-114-brief.md) | 32 | 7 | 39 | 0 |
| **Total** | | **160** | **194** | **354** | **16** |

Every task is SDD-track with `sdd-implementer`: each joins a mounted
Swift/QML surface, original assertion semantics and multi-boundary
evidence. The file-count exception is deliberate: one domain transaction
plus its actual mounted consumer must stay in one reviewable task.

Task 107 is the dedicated follow-up for the insertion residues:
`drawerpresentation/proof.valueprompt.txt` A014/A015/A020/A066/A069 and
`selectionkey/proof.localinputtier_text.txt` Original
332/345/357/359/361/380/385/390/397/399/402/405. The approved handoff also
includes **Original 574**, exact full-song bytes after velocity-prompt
Escape: add the Swift transaction on the same mounted Littleroot fixture
and pair it with 106's real Escape journey, without a QML byte getter.
These eighteen rows are the **only explicit row handoff from 106**, not
simultaneous ownership. Re-query after 106: if its final pass closes any,
update the selection/count before dispatch; do not claim it remains open
or silently replace it with unrelated rows. Task 107 also selects the
24 canvaslayout residues. Delete the scoped text ledger only after every
remaining row, including Original 574, closes.

The fork value-prompt check calls `openValuePromptForInsertion` directly.
There is no empty-space/menu insertion-prompt gesture to reproduce. Task
107 adds the equivalent **production presenter insertion API**, then opens
the actual mounted prompt through it and drives real text/clipboard/keys.
It must not invent a right-click row or double-click gesture. Preserve
104's AutomationInteraction/AutomationPage pointer semantics after it lands.
This resolves the ingress assumption in the earlier brief without
discarding the insertion behavior.

Task 109 couples a missing visible ruler tooltip with explicit retirement
of the old staged-native gate representation. Swift installs only loaded
tabs; ready tests do not magically prove an absent MIDI-only stage. Its
brief separates the 13 surviving ready/control/tooltip behavior rows from
48 native fixture/staged rows. Task 112 also resolves five existing
NATIVE-SETUP classifications before whole-ledger deletion; those five are
not added to the GAP+PARTIAL selection budget.

### Parallel groups, owners and checkpoints

| Group | Concurrent tasks | Selected rows | Start boundary |
|---|---|---:|---|
| A | 107, 108, 109, 110 | 190 (94 GAP + 96 PARTIAL) | All 99–106 accepted and checkpointed |
| B | 111, 112, 113, 114 | 164 (66 GAP + 98 PARTIAL) | Group A accepted and checkpointed |

Each brief's exact write set is closed, including conditional production
repairs and ledgers. **Within each group every pair is file-disjoint.**
Conditional ownership is still ownership; it is not an invitation for
another writer to borrow an apparently unused file. No shared registration
file, fixture content or production-observation test seam is authorized.
Existing registered check functions are extended in their current lanes.

Hot-file handoffs are explicit:

| Hot file / family | Group A owner | Group B owner |
|---|---|---|
| AutomationPage.swift; tst_EditorDrawer.qml | 107 | 111 |
| AutomationModal.swift; AutomationPrompt.qml; canvaslayout checks | 107 | none |
| EditorDrawerLayout.swift | 107 | none |
| EditorDrawer.qml; localinputtier_text.swift; tst_ShellWindow.qml | 107 | 113 |
| VelocityPage/Interaction/Transactions.swift | 108 | 112 |
| VelocityAxis.swift; detent check sources; tst_ShellDrawerParity.qml | 108 | none |
| PianoGrid.swift; tst_ShellGridInput.qml | 109 | 112 |
| EditorSurface.qml | 109 | 114 |
| RulerToolTip.qml; static/gate.swift | 109 | none |
| ShellPresenter.swift; ShellWindow.qml | 110 | 113 |
| DocumentSession/ApplicationSession; voice-editor owners; bank checks; tst_ShellVoicegroup.qml | 110 | none |
| AutomationContent/OverlayPublication; AutomationPage.qml; presentation checks | none | 111 |
| VelocityPublication; PianoGrid+Gestures/NoteCommands; velocity roll/click checks | none | 112 |
| EditKeyArbiter/EditorCommandRouter; PitchBendPresenter/Popup; pitch checks | none | 113 |
| MouseHints/HoverHint; scrollbar/header/transport hint bindings; tst_ShellTabs.qml | none | 114 |

The four Group B tasks do not share even their mounted lane files:
111 uses EditorDrawer, 112 ShellGridInput, 113 ShellWindow/ShellPitchBend,
and 114 ShellTabs. In Group A, 107 owns the shellwindow **check**, while 110
owns ShellWindow **production**; 107 consumes its existing key contract
without editing that production file.

Rebase dependencies on the prior wave:

| Prior writer | Required preservation / next owner |
|---|---|
| 99 | router, ShellWindow and shellwindow key/copy behavior → 107/110/113 |
| 100 | automation selection/publication/Page and EditorDrawer lane → 107/111 |
| 101 | velocity producers, drawer layout/QML, tst_velocityediting and drawer-parity lane → 107/108/112 |
| 102 | selected-note identities, NoteCommands/PianoGrid and shell-grid input → 109/112 |
| 103 | ApplicationSession/tab close lifecycle and ShellTabs → 110/114 |
| 104 | automation pointer/drawing/publication/QML and presentation checks → 107/111; preserve its ingress semantics |
| 105 | grid geometry/camera/gesture publication and shell-grid input → 109/112/114 |
| 106 | local-key arbiter, ShellWindow, numeric prompts/text checks and the explicit insertion residue handoff → 107/110/113 |

Only two new persistence milestones are needed: accepted Group A before
Group B reuses its files, and the final accepted Group B handoff. A prior
accepted checkpoint can satisfy a boundary; do not create empty commits.
Task review and bounded fixes precede persistence. If the actual settled
tree requires an undeclared owner, revise the group contract before editing;
do not silently overlap siblings.

### Evidence and execution contract

Sections 10 and 11 remain mandatory. The following lessons sharpen, not
replace, their contract:

- Proof rows are conjuncts, not approximate scenario names. Every selected
  missing clause and every named data instance gets executing evidence;
  nothing is left “implied” by an adjacent test. Preserve existing correct
  predicates and complete their consumer-visible residue. No standalone
  ledger reconciliation.
- Messages used as anchors are unique **complete string literals**.
  Interpolated program/phase text is not a literal anchor. Keep separate
  family/phase messages where their predicates differ; no generic-message
  reuse that makes proof ownership ambiguous.
- The editorqml drawer lane has **no ShellWindow key dispatcher**.
  Window-key claims belong in the shell lane named in the brief. A direct
  model command or a synthetic local key target is not window-delivery
  proof. Task 113's repeat flag is explicitly production event-metadata
  coverage paired with a mounted initial opener, not fabricated OS input.
- Raster claims need independently derived palette/oracle colors and exact
  scene-mapped target positions, including the required negative samples.
  Reading expected color back from the tested primitive or observing “some
  pixel changed” is not evidence of the claimed paint law.
- A DPR2 claim requires a **registered lane that actually executes at
  DPR2**. Configuring a Swift model with dpr=2 or running a normal shell
  lane proves neither. ShellQmlTests currently registers the extra DPR2
  process for shell-note-visuals, not every lane. These briefs do not
  authorize registration edits or silently borrow that evidence; an
  uncovered required DPR2 variant must be resolved at the task gate.
- Do not relabel native behavior as representation merely because it is
  hard to mount. Retire only the explicitly bounded obsolete fixture,
  pointer/action object or deleted staged architecture; retain real
  focus, exactly-once commands, transactions, pixels and lifecycle effects.
  Fully closed ledgers are deleted in the same change as proving code.
  Original C++ checks already deleted are not recreated.
- No new C++; Swift 6.4, visible/owned QtBridge declarations, no avoidable
  hot-path allocation, two-line comment limit, base-font geometry and
  WCAG-AA GridPalette text/surface pairs remain mandatory. No second key
  authority, fake modal, test-only observation API, new Qt.callLater or
  idempotence guard. Fixture content is immutable; normal editor actions
  may stage a scenario without rewriting shared fixture files.
- Preferences are staged and observed through CFPreferences/UserDefaults,
  synchronizing the domain rather than treating cached plist bytes as an
  oracle. Existing correct production may have no RED: report that
  honestly and add the genuinely missing consumer conjunct, not a defect
  or setup-only assertion.

The controller runs each brief's exact narrow commands on the settled
group, observes the actual mounted surface, and then runs these common
gates, serialized:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Every task requires the full shell sweep (all registered lanes) and full
verify, not only its narrow filter. Identical full commands may be
deduplicated on one accepted settled group; predicates, variants and smoke
journeys may not. Each invocation has the existing 175-second alarm and
must finish within 180 seconds **after** the lock is acquired. No concurrent
builds, mid-flight shared checks, timeout workarounds or silent narrowing.
Implementers use the recorded commands without rediscovery unless the
contract actually becomes stale. Read-only local inspection/proof queries
remain allowed while siblings write; shared verification is controller-owned.

Before dispatch, re-query selected dispositions and source owners after
all 99–106 settle. Before/after structural inspection, fresh execution
anchors, per-task review and bounded fixes follow the existing execution
loop. Model tests alone are not mounted smoke; offscreen Qt focus is not
physical macOS host evidence. Planning ran proof list/sites/show and
read-only row/count/ownership inspection only: no build, check suite,
formatter or commit.

### Exclusions and unresolved policy

Parked `project`, `samplecheck`, `onboardcheck` and
`midi/tst_midiexport` remain untouched; P3 WAV export awaits the user.
Deferred New Song, Import MIDI, Export WAV, Register Song, Import Sample
and Theme menu rows stay excluded. New Voicegroup presentation A032–A037
and corresponding voicegroup-source rows A086–A092 are not smuggled into
110's existing-voice edit surface.

`voicegroupsave/proof.savecore.txt` **A016–A026** remains the user decision
about status/error publication for unavailable sound-directory/catalog
state while retaining the last valid catalog.
`workspace/proof.tabs_transport.txt` **A062** remains blocked on real
applied-song-volume observation. No cfg proxy or test getter closes it.
No `host` row is selected. All other 99–106 row reservations remain in
force; their leftovers are not automatically eligible for this wave.

`drawerpresentation/proof.velocity.txt` **A075 is not selected**: its fork
context is programmable wave, and no square-overlap production repair is
requested. Keep the entire 101-owned velocity-presentation inventory out
of this wave.

### Recomputed per-ledger census

Paths are relative to `src/checks/`. This is the same in-flight snapshot
described above, including zero-open ledgers; “Open” is GAP + PARTIAL, not
eligibility or expected post-wave residue.

| Ledger | GAP | PARTIAL | Open |
|---|---:|---:|---:|
| `audio/proof.tst_audiobackend.txt` | 0 | 0 | 0 |
| `automation/hover/proof.tst_automationhover.txt` | 46 | 7 | 53 |
| `automation/presentation/proof.painting.txt` | 5 | 33 | 38 |
| `automation/presentation/proof.tst_automationpresentation.txt` | 15 | 2 | 17 |
| `automation/proof.automationcanvaslayout.txt` | 5 | 19 | 24 |
| `automation/proof.automationnodedrag.txt` | 12 | 1 | 13 |
| `automation/proof.automationownership.txt` | 0 | 15 | 15 |
| `automation/proof.automationpainting.txt` | 30 | 2 | 32 |
| `automation/proof.automationpencil.txt` | 5 | 8 | 13 |
| `automation/proof.automationselection.txt` | 0 | 4 | 4 |
| `automation/raster/proof.interaction.txt` | 33 | 0 | 33 |
| `automation/raster/proof.painting.txt` | 25 | 0 | 25 |
| `automationgesturecheck/proof.contract.txt` | 2 | 6 | 8 |
| `automationgesturecheck/proof.crosslane.txt` | 1 | 2 | 3 |
| `automationgesturecheck/proof.hover.txt` | 3 | 1 | 4 |
| `automationgesturecheck/proof.parity.txt` | 0 | 12 | 12 |
| `clipboard/proof.clipmime_test.txt` | 1 | 0 | 1 |
| `clipboard/proof.laneselection_test.txt` | 19 | 0 | 19 |
| `drawerpresentation/proof.valueprompt.txt` | 0 | 5 | 5 |
| `drawerpresentation/proof.velocity.txt` | 0 | 4 | 4 |
| `editorqml/proof.shell-theme.txt` | 0 | 0 | 0 |
| `eventviews/proof.chrome.txt` | 0 | 12 | 12 |
| `eventviews/proof.edits.txt` | 0 | 1 | 1 |
| `host/proof.tst_hostadapter.txt` | 49 | 17 | 66 |
| `host/proof.tst_hostintegration.txt` | 51 | 13 | 64 |
| `host/proof.tst_hostseams.txt` | 3 | 1 | 4 |
| `keyboard/proof.tst_velocitymodel.txt` | 27 | 0 | 27 |
| `mainwindowrouting/proof.tst_mainwindowrouting_input.txt` | 33 | 18 | 51 |
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
| `rollcheck/proof.keyboard.txt` | 4 | 2 | 6 |
| `rollcheck/proof.presentation.txt` | 11 | 4 | 15 |
| `rollcheck/proof.remap.txt` | 7 | 17 | 24 |
| `rollcheck/proof.resize.txt` | 0 | 6 | 6 |
| `rollcheck/proof.scale_editing.txt` | 0 | 3 | 3 |
| `rollcheck/proof.scale_projection.txt` | 0 | 3 | 3 |
| `rollcheck/proof.selection.txt` | 0 | 2 | 2 |
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
| `selectionkey/proof.gesturevelocity.txt` | 0 | 5 | 5 |
| `selectionkey/proof.localinputtier_pitchbend.txt` | 0 | 7 | 7 |
| `selectionkey/proof.localinputtier_text.txt` | 0 | 13 | 13 |
| `selectionkey/proof.windowtier_keyboard.txt` | 0 | 15 | 15 |
| `selectionkey/proof.windowtier_lifetime.txt` | 0 | 1 | 1 |
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
| **Total** | **2,092** | **698** | **2,790** |

## 13. Wave 115+

### Scope and selection

This wave follows the accepted 99–114 surface work, including the in-flight
111/112/114 writers and task 113's Volume clipboard follow-up. The supplied
baseline was `84e346c6`; the working tree continued changing during planning.
The first census contained **95 ledgers, 1,899 GAP + 551 PARTIAL = 2,450
open rows**. The final planning snapshot below contains **94 ledgers,
1,865 GAP + 519 PARTIAL = 2,384 open rows**. This change is concurrent
predecessor work, not a result claimed by these briefs. Three zero-open
ledgers remain. The parked project/sample/onboarding/MIDI-export inventory
is **1,232 open rows**; **1,152** are outside those families before other
reservations and exclusions.

Select **345 currently open rows: 248 GAP + 97 PARTIAL**, across nineteen
ledgers. Every identity was checked against its live disposition and the
111/112/113/114 reservations; no reserved identity is selected. All exact
write paths exist. The source oracle remains `fceecd88`; each brief also
records its ledger's pinned original revision. `proof list`, `sites` and
`show`, original fork sources and current owners were inspected. No build,
suite, formatter or commit was run for planning.

| Task | Surface / brief | GAP | PARTIAL | Open | Full-closure candidates |
|---|---|---:|---:|---:|---:|
| 115 | [Automation pointer ownership, hover and stale-release recovery](task-115-brief.md) | 64 | 29 | 93 | 6 |
| 116 | [MIDI converter roundtrip, mapped events and linear pairing](task-116-brief.md) | 20 | 24 | 44 | 2 |
| 117 | [Polyphony tail-cut navigation and responsive panel](task-117-brief.md) | 8 | 8 | 16 | 2 |
| 118 | [Complete editor-state fanout and engine-track remapping](task-118-brief.md) | 60 | 11 | 71 | 0 |
| 119 | [Exact automation/voice framebuffer and half-open rings](task-119-brief.md) | 58 | 0 | 58 | 2 |
| 120 | [Event List filter/cell/editor transaction conjuncts](task-120-brief.md) | 0 | 13 | 13 | 2 |
| 121 | [Mounted fitted typography and italic transformation](task-121-brief.md) | 10 | 4 | 14 | 2 |
| 122 | [Roll ruler/header presentation and reveal navigation](task-122-brief.md) | 28 | 8 | 36 | 2 |
| **Total** | | **248** | **97** | **345** | **18** |

All eight route SDD-track to `sdd-implementer`: the work requires
original-clause interpretation, real production ownership and executing
consumer evidence. The file-count exceptions follow existing surfaces,
not arbitrary file quotas. Task 115 is the larger pointer-lifecycle family:
its hover, node-drag and gesture-contract rows share the same producer,
fixtures and shell-drawer lane, so splitting them would create overlapping
writers and duplicate builds. Task 118 is one state transaction spanning
origin, projection, remap and persistence. MIDI is a real load/save
consumer surface, verified through the actual external converter rather
than a new GUI command.

The strongest production divergence is task 118: the current application
retains an `EditorLaneState` but only fans out lane ranges. The fork's
`tst_mainwindowrouting_state.cpp::nonSelectedOriginFansCompleteStateOutAndNoopsStaySilent`
and `laneIdentityRemapPersistsAndQuietRemapStaysSilent` require complete
typed state, ordered hidden identities, atomic remapping and exactly-once
origin/hub/persistence notifications. The brief specifies the real
mechanism and its callers rather than asking an implementer to invent one.
Conversely, task 122's old "revealNote has no owner" preamble is stale:
`ApplicationSession.polyphony.onJump` already selects and reveals a note.
That task extends the actual consumer, not a duplicate implementation.

Full-closure counts are **conditional**, not deletion instructions.
The six task-115 inventories, two MIDI inventories, two polyphony
inventories, two raster inventories, two Event List inventories, two
typography inventories and two roll inventories may close only after
every retained behavioral and pre-existing native obligation is resolved.
Task 118 leaves its state ledger in place, including A164/A171/A178's
unselected sidecar snapshots. Do not delete a ledger merely because its
selected subset or a neighboring lane passes.

### Parallel groups, owners and checkpoints

| Group | Concurrent tasks | Selected rows | Start boundary |
|---|---|---:|---|
| A | 115, 116, 117, 118 | 224 (152 GAP + 72 PARTIAL) | All reserved predecessor work accepted and checkpointed |
| B | 119, 120, 121, 122 | 121 (96 GAP + 25 PARTIAL) | Group A accepted and checkpointed |

Every pair of exact write sets inside each group is file-disjoint,
including conditionally repaired production files, check files and the
separate ledger-writer paths. Conditional ownership still excludes
sibling writes. No implementer may borrow another task's unused owner.
Task 115 owns automation interaction/QML but not AutomationPage.swift;
118 owns the page's state integration. Task 121 reads ApplicationSession's
font maps but does not write it; 122 owns that file in Group B.

The exact cross-group hot-file reuse is:

| Existing path | Earlier owner | Later owner |
|---|---:|---:|
| `src/swift/app/drawer/automation/AutomationOverlayPublication.swift` | 115 | 119 |
| `src/ui/songview/quick/drawer/AutomationPage.qml` | 115 | 119 |
| `src/checks/automation/automationcanvasediting.swift` | 115 | 119 |
| `src/checks/editorqml/tst_ShellDrawerParity.qml` | 115 | 119 |
| `src/swift/app/drawer/automation/AutomationPage.swift` | 118 | 119 |
| `src/checks/editorqml/PolyphonyShellProbe.swift` | 117 | 122 |
| `src/checks/editorqml/tst_ShellPolyphony.qml` | 117 | 122 |
| `src/swift/app/ApplicationSession.swift` | 118 | 122 |

Required predecessor preservation:

| Reserved/prior writer | Next owner and contract |
|---|---|
| 111 | AutomationPage → 118/119; OverlayPublication and AutomationPage.qml → 115/119; ContentPublication, painting checks and tst_EditorDrawer → 119 |
| 112 | PianoGrid and tst_ShellGridInput → 122; preserve velocity selection/cancellation and all resulting identities |
| 114 | tst_ShellTabs → 118; EditorSurface and TrackHeaderBand → 122; preserve pointer-owned hint lifecycle |
| 113 follow-up | Finish windowtier A047/A048/A057 before either group; no row or hot shell/text file is reassigned here |
| 110/103 | DocumentSession, DocumentWorkspace and ApplicationSession → 118; preserve save/Undo, tab close and detach ownership |
| 108 | tst_ShellDrawerParity → 115/119; preserve all per-family detent and midpoint evidence |
| 105/109 | Grid/camera/ruler behavior → 122; preserve tick ceiling, ready-only installation and real tooltip |

Only the accepted Group A checkpoint and final Group B handoff are new
persistence milestones. Checkpoint accepted prior writers before any hot
file is reused; do not checkpoint unreviewed/failing work or create empty
commits. A changed ownership need revises the closed group contract before
an edit. There is no per-task commit requirement.

### Evidence and execution contract

The following applies to every linked brief and supersedes §12's
controller-only narrow-lane policy for this wave:

- **Real input only.** Use actual production pointer/key/menu/modal
  delivery for user-input claims. The fork's existing production API
  stimuli remain valid for model-only clauses, paired with mounted input
  where required. No fake popup, manual hint claim/clear, new gesture,
  second key dispatcher or test-only production observation API.
- **Independent expected values.** Derive literals, bytes, ordering,
  history counts, ticks, selection and geometry from the fork/fixture
  contract, never by reading Swift output back as its expected value.
  Converter equality compares original and rewritten inputs through the
  real converter. Full-song bytes are non-optional.
- **No setup-only assertions.** Retire only bounded obsolete fixture,
  pointer, stylesheet, handle or native signal representations. Real
  focus, grabs, exact transactions, pixel results and lifecycle
  consequences remain obligations. A missing owner is not retirement
  evidence; correct existing production need not have an invented RED.
- **Raster claims** require independently derived palette/oracle colors
  and exact scene-mapped physical positions, including negative samples.
  Arbitrary changed pixels and a tested item's own color are insufficient.
  **DPR2 claims require actual DPR2 execution and observation.** Task 119
  owns the declared shell-drawer DPR2 child; 122 extends the already-run
  note-visual DPR2 test. A Swift dpr=2 model is not framebuffer proof.
- **editorqml has no ShellWindow key dispatcher.** Place window shortcuts
  and Escape/Undo claims in the named real shell lane, not a local model
  command in EditorDrawer. Offscreen Qt observation is not physical
  macOS host evidence.
- **Messages and fixtures:** preserve existing assertion literals
  verbatim; each new literal is complete and unique in its function.
  Updating an exact fixture requires updating every consumer asserting
  its exact contents, indices or counts. These briefs authorize no
  checked-in project-fixture changes. Swiftcore fixtures share a bank
  lease: isolate mutations in copied fixtures, never dirty a shared bank
  and assume a fresh session is isolated. Preference evidence uses
  synchronized CFPreferences/UserDefaults, not cached plist bytes.
- **Execution ownership:** implementers run their own recorded narrow
  lanes under the exact build lock below, after their code/check changes
  settle; a lock serializes builds, not source edits. Coordinate a
  settled-source window before a lane, and never run against a sibling's
  half-written sources. Read-only inspection/proof queries may run during
  edits. No global suites, formatters or linters mid-flight.
- **Ledger ownership:** implementers do not edit proof files. A separate
  ledger writer receives settled code and executed evidence, edits only
  that surface's selected rows, and lands those edits with the proving
  surface. No standalone reconciliation, opportunistic closure, source
  repinning or bulk compaction wave.

Every brief records copyable narrow commands. Their common prefix is:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task …
```

The controller runs these once on each accepted settled group after the
implementer lanes and ledger writer finish:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Actual mounted smoke/converter execution is mandatory; merely compiling
checks is not proof. Each run retains the 175-second alarm and finishes
within 180 seconds after lock acquisition. Preserve native runtime/audio
prerequisites; no timeout workarounds, silent lane narrowing or claims
that a listed command was executed during planning. No new C++; Swift
ownership through visible QtBridge declarations, base-font sizing and
WCAG-AA real text/surface pairs remain mandatory.

### Exclusions and unresolved policy

Never select savecore A016–A026, presentation A032–A037 (New Voicegroup),
the corresponding voicegroup-source creation rows, P3 WAV export, or
lifecycle A041's Qt focus-ancestry obligation. No selected task adds a
user gesture absent from `fceecd88`. Sidecar-directory snapshots remain
excluded, explicitly state A164/A171/A178; task 118 proves only its
selected document/settings conjuncts, not a proxy snapshot.

All 111/112/114 selected rows and write sets, and the 113
windowtier A047/A048/A057 follow-up, stay reserved until accepted even if
their dispositions change during planning. No host, project, samplecheck,
onboardcheck or midi/tst_midiexport row is selected. Existing deferred
New Song/Import MIDI/Export WAV/Register Song/Import Sample/Theme actions
are not smuggled into another surface.

Themelayout color A038's unexecuted preset branch and A039's missing
sample-editor pairs are left open; no invented preset or partial
three-pair contrast check closes them. The bank-save unknown-synth
stimulus and viewcache pending-origin/dirty-close differences are not
selected: an immutable-file error is not the original invalid-synth
request, and pending-transition ownership is not a license to alter
bank-only close policy. Roll remap/identity work remains separate from
118's complete cosmetic-state producer; 122 does not claim raw engine
promotion. These are researched deferrals, not row-count padding.

### Recomputed per-ledger census

Paths are relative to `src/checks/`. This is the final in-flight snapshot
described above, not a post-wave forecast. Re-query selected dispositions
before dispatch; do not silently substitute unrelated rows if a
predecessor closes one.

| Ledger | GAP | PARTIAL | Open |
|---|---:|---:|---:|
| `audio/proof.tst_audiobackend.txt` | 0 | 0 | 0 |
| `automation/hover/proof.tst_automationhover.txt` | 46 | 7 | 53 |
| `automation/presentation/proof.painting.txt` | 5 | 33 | 38 |
| `automation/presentation/proof.tst_automationpresentation.txt` | 15 | 2 | 17 |
| `automation/proof.automationnodedrag.txt` | 12 | 1 | 13 |
| `automation/proof.automationownership.txt` | 0 | 15 | 15 |
| `automation/proof.automationpainting.txt` | 0 | 3 | 3 |
| `automation/proof.automationselection.txt` | 0 | 4 | 4 |
| `automation/raster/proof.interaction.txt` | 33 | 0 | 33 |
| `automation/raster/proof.painting.txt` | 25 | 0 | 25 |
| `automationgesturecheck/proof.contract.txt` | 2 | 6 | 8 |
| `automationgesturecheck/proof.crosslane.txt` | 1 | 2 | 3 |
| `automationgesturecheck/proof.hover.txt` | 3 | 1 | 4 |
| `automationgesturecheck/proof.parity.txt` | 0 | 12 | 12 |
| `clipboard/proof.clipmime_test.txt` | 1 | 0 | 1 |
| `clipboard/proof.laneselection_test.txt` | 19 | 0 | 19 |
| `drawerpresentation/proof.velocity.txt` | 0 | 4 | 4 |
| `editorqml/proof.shell-theme.txt` | 0 | 0 | 0 |
| `eventviews/proof.chrome.txt` | 0 | 12 | 12 |
| `eventviews/proof.edits.txt` | 0 | 1 | 1 |
| `host/proof.tst_hostadapter.txt` | 49 | 17 | 66 |
| `host/proof.tst_hostintegration.txt` | 51 | 13 | 64 |
| `host/proof.tst_hostseams.txt` | 3 | 1 | 4 |
| `keyboard/proof.tst_velocitymodel.txt` | 27 | 0 | 27 |
| `mainwindowrouting/proof.tst_mainwindowrouting_input.txt` | 21 | 20 | 41 |
| `mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` | 48 | 27 | 75 |
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
| `rollcheck/proof.keyboard.txt` | 4 | 2 | 6 |
| `rollcheck/proof.presentation.txt` | 11 | 4 | 15 |
| `rollcheck/proof.remap.txt` | 7 | 17 | 24 |
| `rollcheck/proof.resize.txt` | 0 | 6 | 6 |
| `rollcheck/proof.scale_editing.txt` | 0 | 3 | 3 |
| `rollcheck/proof.scale_projection.txt` | 0 | 3 | 3 |
| `rollcheck/proof.selection.txt` | 0 | 2 | 2 |
| `rollcheck/static/proof.geometry.txt` | 17 | 4 | 21 |
| `samplecheck/proof.analysis.txt` | 21 | 0 | 21 |
| `samplecheck/proof.decoder.txt` | 93 | 0 | 93 |
| `samplecheck/proof.dsp.txt` | 61 | 0 | 61 |
| `samplecheck/proof.editor.txt` | 80 | 0 | 80 |
| `samplecheck/proof.integration.txt` | 68 | 0 | 68 |
| `samplecheck/proof.project.txt` | 63 | 0 | 63 |
| `samplecheck/proof.soundfont.txt` | 22 | 0 | 22 |
| `selectionkey/proof.corearrows.txt` | 1 | 0 | 1 |
| `selectionkey/proof.gesturecommands.txt` | 0 | 4 | 4 |
| `selectionkey/proof.gesturevelocity.txt` | 0 | 5 | 5 |
| `selectionkey/proof.windowtier_keyboard.txt` | 0 | 1 | 1 |
| `selectionkey/proof.windowtier_lifetime.txt` | 0 | 1 | 1 |
| `support/corecheck/proof.tst_swiftcore.txt` | 0 | 0 | 0 |
| `swiftqtml/proof.tst_swiftqtml.txt` | 78 | 0 | 78 |
| `swiftrollbench/proof.tst_swiftrollbench.txt` | 6 | 0 | 6 |
| `swiftrollgated/proof.clipboardchecks.txt` | 2 | 0 | 2 |
| `themelayout/proof.tst_themelayout_color.txt` | 0 | 2 | 2 |
| `themelayout/proof.tst_themelayout_font.txt` | 7 | 4 | 11 |
| `themelayout/proof.tst_themelayout_scale.txt` | 3 | 0 | 3 |
| `themelayout/proof.tst_themelayout_settings.txt` | 33 | 1 | 34 |
| `velocity/proof.velocityclicks.txt` | 0 | 2 | 2 |
| `velocity/proof.velocityroll.txt` | 0 | 7 | 7 |
| `velocity/proof.velocityselection.txt` | 0 | 2 | 2 |
| `visual/proof.browsers.txt` | 5 | 3 | 8 |
| `visual/proof.chrome.txt` | 3 | 4 | 7 |
| `visual/proof.dialogs.txt` | 24 | 0 | 24 |
| `visual/proof.quick.txt` | 5 | 0 | 5 |
| `voicegroup/proof.tst_voicegroupbank.txt` | 0 | 15 | 15 |
| `voicegroup/proof.tst_voicegroupviewcache.txt` | 3 | 1 | 4 |
| `voicegroup/proof.voicegroupsourceediting.txt` | 7 | 0 | 7 |
| `voicegroupsave/proof.presentation.txt` | 6 | 0 | 6 |
| `voicegroupsave/proof.savecore.txt` | 11 | 0 | 11 |
| `workspace/proof.selftest_timeline.txt` | 13 | 0 | 13 |
| `workspace/proof.selftest_transport.txt` | 3 | 7 | 10 |
| `workspace/proof.session.txt` | 3 | 0 | 3 |
| `workspace/proof.tabs_scale.txt` | 2 | 4 | 6 |
| `workspace/proof.tabs_transport.txt` | 1 | 1 | 2 |
| **Total** | **1,865** | **519** | **2,384** |

## 14. Wave 123+

### Scope and selection

This wave uses the accepted 600-line split (`c271dd89`,
`split-600-wave.md`), not the former monolithic file names. Tasks 118 and
119 remain reserved. The first planning census contained **79 ledgers,
1,715 GAP + 421 PARTIAL = 2,136 open rows**. The final snapshot below is
**79 ledgers, 1,714 GAP + 421 PARTIAL = 2,135 open rows**: the state
ledger lost one GAP during concurrent task-118 work. Neither change is
claimed as work completed by these briefs. No zero-open ledger remains
in this inventory.

Select **351 currently open rows: 317 GAP + 34 PARTIAL**, across fifteen
ledgers. `proof list` was queried by area to avoid its 30-file display
cap; `sites` and `show` supplied the selected identities and original
clauses. Every selected identity was checked against its live open
disposition, including the reserved 118/119 identities. The source oracle
is still `fceecd88`, with each brief recording the ledger's pinned
revision. Existing write paths were checked against the split layout;
only three named song-registration check files are new. Planning ran no
build, test suite, formatter or commit.

| Task | Surface / brief | GAP | PARTIAL | Open | Full-closure candidates |
|---|---|---:|---:|---:|---:|
| 123 | [Velocity gesture validity and exact drawer consequences](task-123-brief.md) | 27 | 4 | 31 | 2 |
| 124 | [Automation lane ownership and malformed native clipboard](task-124-brief.md) | 20 | 0 | 20 | 2 |
| 125 | [Raw-event engine promotion and retained roll identity](task-125-brief.md) | 13 | 17 | 30 | 2 |
| 126 | [Existing Register Song transaction and source repair](task-126-brief.md) | 88 | 0 | 88 | 1 |
| 127 | [Existing Delete Song transaction and reference protection](task-127-brief.md) | 71 | 0 | 71 | 1 |
| 128 | [Regioned registration allocation and migration](task-128-brief.md) | 82 | 0 | 82 | 1 |
| 129 | [Live timeline edits and actual audio progress](task-129-brief.md) | 16 | 4 | 20 | 1 |
| 130 | [Exact roll ruler, selection and Highlight/Fold framebuffer](task-130-brief.md) | 0 | 9 | 9 | 2 |
| **Total** | | **317** | **34** | **351** | **12** |

All eight route SDD-track to `sdd-implementer`. Full ledgers are selected
before scattered partial residues; none is a ledger-only reconciliation.
The larger 126/127/128 selections are three independently runnable
families of the same existing registration service, separated at their
mutation boundaries to avoid conflicting writers. Their many original
assertions include prerequisite guards; those do not justify 241 new
setup-success assertions. Complete source bytes, allocation/removal
semantics and actual existing confirmation input supply the consumers.

The strongest inspected production divergences are task 123's unchecked
gesture seed/preview identities and task 125's raw-event engine promotion:
the raw edit paths currently commit without the before/after track remap
that the typed track operations already use. Task 124 also replaces
snapped-tick selection membership with the actual half-open displayed
interval and restores lane-stack endpoint semantics without adding a
stacked-lane UI. Task 125 consumes task 118's accepted remap/state contract;
it does not reopen that writer's scope.

Current source overrides stale ledger preambles. SongDockController and
the mounted ShellSongs suite already expose Register and Delete
confirmation transactions. Their supported allocation, repair, deletion
and regional-layout semantics are therefore eligible now, despite §13's
blanket onboardcheck parking. The source-creation voicegroup rows and
Import MIDI wizard rows are not similarly eligible.

### Parallel groups, owners and checkpoints

| Group | Concurrent tasks | Selected rows | Start boundary |
|---|---|---:|---|
| A | 123, 124, 126, 129 | 159 (151 GAP + 8 PARTIAL) | Accepted split and each brief's existing-surface prerequisite |
| B | 125, 127, 130 | 110 (84 GAP + 26 PARTIAL) | Group A accepted/checkpointed; task 118 accepted before 125 |
| C | 128 | 82 (82 GAP + 0 PARTIAL) | Group B accepted/checkpointed, including 126/127 registration ownership |

Exact write sets are file-disjoint inside each group, including conditional
production repairs and ledger-writer paths. Group A's four tasks leave
capacity for reserved 118/119 only as those writers' own dependencies
permit; never exceed six concurrent implementers. A conditional write
still reserves its file. No writer may borrow a sibling's unused path.

Reserved task 118 ownership includes its live post-split files:
`TabsDrawerProbe.swift`, `tst_ShellTabsDrawer.qml`,
`workspace/session_view_state.swift`, `ApplicationSession+Tabs.swift`,
`ApplicationSession.swift`, `DocumentSession+Internals.swift`,
`DocumentSession.swift`, `DocumentWorkspace.swift`,
`drawer/automation/AutomationPage.swift` and
`timeline/EditorViewStateCodec.swift`. Its selected state-ledger rows
remain reserved even if a disposition changes during planning.

Task 119 keeps both raster ledgers and its post-split automation/voice
raster surface: AutomationPage and its content/overlay publication,
AutomationPage.qml/AutomationPlot.qml, VoiceChangesInteraction and
VoiceChangesPage.qml, automation painting/canvas-editing checks, the
automation-hover/curves/presentation/preview and voice-input/transactions
drawer suites, shell drawer-parity suites/support, and
ShellQmlTests.swift/ShellQmlEntries.swift. This wave does not write those
files. Its distinct AutomationTransactions/AutomationLaneMenu suites are
task 124's model/clipboard consumers; VelocityRaster/VelocityEditing are
task 123's velocity consumers. No ownership claim extends to every split
descendant merely because the historical brief named tst_EditorDrawer.qml.

Cross-group hot-file reuse is confined to the registration family:

| Existing path | Earlier owner | Later owner |
|---|---:|---:|
| `src/swift/project/SongRegistration.swift` | 126 | 128 |
| `src/swift/project/SongRegistration+Writes.swift` | 126 | 128 |
| `src/swift/project/SongRegistration+Store.swift` | 126 | 127 |
| `src/swift/project/SongRegistration+Removal.swift` | 127 | 128 |
| `src/swift/app/ProjectService+Songs.swift` | 126 | 127 |
| `src/swift/app/songlist/SongDockController.swift` | 126 | 127 |
| `src/checks/songlist/songlist_service.swift` | 126 | 127, then 128 |
| `src/checks/editorqml/tst_ShellSongs.qml` | 126 | 127 |
| `src/checks/CMakeLists.txt` | 126 | 127, then 128 |

Take accepted Group A and Group B checkpoints before these files are
reused, then a final Group C handoff. These are sparse integration
milestones, not per-task commits. Never checkpoint unreviewed or failing
work. A discovered necessary write outside the closed set must revise the
group ownership contract before editing, not silently expand an agent's
territory. Task 125's accepted-118 prerequisite is semantic, not permission
to edit the reserved origin/hub files.

### Evidence and execution contract

This shared contract applies once to every linked brief:

- **Real input and authoritative state.** Pointer/key/menu/modal claims
  use the actual production surface. Model-only fork API stimuli remain
  valid, paired with mounted input where the original user consequence
  requires it. No fake popup, direct hint claim, new gesture, second
  dispatcher or test-only production observation API.
- **Independent full-state expectations.** Derive exact bytes, ordering,
  IDs, lane ownership, history, ticks and geometry from fork clauses and
  fixture inputs, not from the tested Swift output. Prove preview-time
  nonmutation, one release commit, cancellation/stale-release preservation
  and full Undo/Redo bytes where those are the original transaction.
  Cancellation must be exercised with a real staged draft, not an
  untouched document.
- **No setup-only or implementation-shape tests.** Retire only bounded
  obsolete pointer/signal/widget/fixture representations, with their
  behavioral consumers still proved. Missing UI is not retirement
  evidence. Delete incidental implementation/wording checks instead of
  re-pinning them; preserve retained behavioral assertion literals.
  New literals are complete and unique in their function.
- **Real framebuffer.** Expected pixels use independent oracle/palette
  arithmetic and scene-mapped physical coordinates, with negative samples.
  A tested item's own color, arbitrary changed pixels, a capture guard or
  a Swift dpr=2 argument does not prove the raster. Task 124's domain-edge
  and task 130's ring claims require observed DPR2 execution. Task 119
  retains its own raster child ownership. Offscreen Qt proof is not
  physical macOS host-window equivalence.
- **Existing boundaries.** editorqml has no ShellWindow key dispatcher;
  window shortcuts/Escape/Undo go through the named shell lanes.
  Registration, bank and preference mutations use isolated copied
  fixtures and the real service. Restore staged source files and compare
  full bytes. Never mutate the shared bank lease or checked-in fixtures.
  Use synchronized CFPreferences/UserDefaults for settings, not cached
  plist bytes.
- **Post-split ownership.** Extend existing one-concept owners; every
  Swift/QML file remains at most 600 lines. The existing single-domain
  `src/checks/CMakeLists.txt` source manifest is explicitly exempt; register
  the new checks there directly, with no manifest extraction. No new C++;
  visible QtBridge ownership, base-font sizing and WCAG-AA text/surface
  pairs stay mandatory. The only planned new files are the three named
  Swift registration check sources, registered by their respective tasks.
- **Execution ownership.** Implementers run their recorded narrow lanes
  after their code/check changes settle, under the exact lock below and
  in a coordinated settled-source window. The lock serializes builds,
  not source edits. No project-wide suites, formatters or linters
  mid-flight; read-only proof queries may run while others edit.
- **Separate ledger writer.** Implementers do not edit proof files.
  A separate writer receives settled proving code and executed evidence,
  updates only that surface's selected rows, and lands the update with
  the surface. No source repinning, bulk compaction, unrelated closure or
  standalone ledger reconciliation. A correct existing production path
  need not acquire an invented failing-before test.

Every brief contains copyable narrow commands using:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task …
```

After all implementers and the separate ledger writer finish, the
controller runs the final project-wide gates once on settled sources:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

Mounted smoke and actual renderer/source-file behavior are mandatory;
compiling checks alone proves neither. Retain the 175-second alarm and
180-second post-lock bound, required native/audio prerequisites and exact
sample/raster clauses. No timeout workaround, silent narrowing or claim
that these commands were executed during planning.

### Conditional ledger and native retirement

The twelve whole-ledger candidates are velocitymodel/velocity (123),
clipmime/laneselection (124), identity/remap (125), registration (126),
deletion (127), regionedlayout (128), selftest_timeline (129), and
geometry/scale_projection (130). They contain **341** of the selected
open rows. The remaining ten selected rows belong to partially retained
transport, keyboard and selection ledgers.

**When a ledger fully closes, delete that ledger and every unbuilt C++
unit that no still-open ledger exercises in the same commit.** Selected
subset success is not full closure: resolve every retained/native
obligation first. Check the complete include/use graph and live build
targets before removing a production unit; direct original-check
references alone are insufficient.

| Conditional candidate | Owner / necessary gate | Known reason not to promise deletion yet |
|---|---|---|
| `src/core/velocitymodel.cpp`, `src/core/velocitymodel.h` | 123, only after both velocity ledgers close and all remaining callers/open-ledger uses clear | `songdocument.cpp` still includes velocitymodel.h; its other open-ledger consumers must be discharged, not ignored |
| `src/core/songdocument_range.cpp` | 125, after 124's lane/MIME closures and both identity/remap closures, plus exhaustive remaining-use audit | Other range/time-selection consumers may retain it transitively; the census's witness list is not exhaustive authorization |
| `src/core/mid2agbtables.h` | Not owned by this wave | velocitymodel.cpp includes it today; the earlier DELETE_NOW classification is unsafe while that blocker remains |
| miditimeline, songdocument_tempo, timelineplayer | No deletion assigned | Host, routing, transport and/or automation open ledgers still require them |
| timeeditor_insert, songdocument, workspace/onboarding native family | No deletion assigned | Unselected keyboard range rows and other project/workspace/onboarding obligations remain |

The selected original C++ check files are already absent; do not recreate
or count them as new deletions. There is **no unconditional C++ deletion
claim**. The first two rows are conditional write permissions only;
record any surviving blocker rather than treating proximity to a closed
ledger as proof of dead code.

### Exclusions and unresolved policy

Never select savecore A016–A026, presentation A032–A037 (New Voicegroup),
voicegroupsourceediting A086–A092 (creation/include insertion), P3 WAV
export, lifecycle A041's Qt focus ancestry, or the sidecar-directory
snapshots, explicitly state A164/A171/A178. All 118/119 selected rows and
post-split write sets stay reserved until accepted. No new user gesture
absent from `fceecd88` is authorized.

No host, project, samplecheck or MIDI-export ledger is selected.
Onboardcheck import A046–A096 remains the unsupported wizard, not the
already-proved converter core; action/debuglayout/support are also
unselected. Only the three inspected existing registration/removal
families supersede §13's onboarding deferral. No New Song, Import MIDI,
Import Sample, New Voicegroup, theme or export interface is smuggled in.

Keep bank unknown-synth-save and viewcache pending/dirty-close differences
open. An immutable-file failure is not the fork's invalid-synth stimulus.
Keep transport A009/A010/A013 open under the user's cursor-never-seeks
decision; do not silently restore the old seek or invent a retirement
label. Keyboard A077–A080 and selection A009 remain outside task 130.
The twelve conditional closures are not permission to claim unrelated
setup guards, a new creation API or a native-window substitute.

### Recomputed per-ledger census

Paths are relative to `src/checks/`. This is the final in-flight planning
snapshot, not a post-wave forecast. `proof list --area <area>` covered all
79 live ledgers; `--no-swift` is a filter, not a compact-output mode.
Re-query selected dispositions before dispatch. If a predecessor closes
a row, update the reservation/count explicitly rather than substitute
unrelated work.

| Ledger | GAP | PARTIAL | Open |
|---|---:|---:|---:|
| `automation/hover/proof.tst_automationhover.txt` | 0 | 7 | 7 |
| `automation/presentation/proof.tst_automationpresentation.txt` | 0 | 1 | 1 |
| `automation/proof.automationnodedrag.txt` | 0 | 3 | 3 |
| `automation/proof.automationownership.txt` | 0 | 15 | 15 |
| `automation/proof.automationpainting.txt` | 0 | 3 | 3 |
| `automation/proof.automationselection.txt` | 0 | 4 | 4 |
| `automation/raster/proof.interaction.txt` | 33 | 0 | 33 |
| `automation/raster/proof.painting.txt` | 25 | 0 | 25 |
| `automationgesturecheck/proof.contract.txt` | 0 | 2 | 2 |
| `automationgesturecheck/proof.crosslane.txt` | 0 | 2 | 2 |
| `automationgesturecheck/proof.hover.txt` | 0 | 2 | 2 |
| `automationgesturecheck/proof.parity.txt` | 0 | 7 | 7 |
| `clipboard/proof.clipmime_test.txt` | 1 | 0 | 1 |
| `clipboard/proof.laneselection_test.txt` | 19 | 0 | 19 |
| `drawerpresentation/proof.velocity.txt` | 0 | 4 | 4 |
| `host/proof.tst_hostadapter.txt` | 49 | 17 | 66 |
| `host/proof.tst_hostintegration.txt` | 51 | 13 | 64 |
| `host/proof.tst_hostseams.txt` | 3 | 1 | 4 |
| `keyboard/proof.tst_velocitymodel.txt` | 27 | 0 | 27 |
| `mainwindowrouting/proof.tst_mainwindowrouting_input.txt` | 21 | 20 | 41 |
| `mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` | 48 | 27 | 75 |
| `mainwindowrouting/proof.tst_mainwindowrouting_native.txt` | 28 | 1 | 29 |
| `mainwindowrouting/proof.tst_mainwindowrouting_state.txt` | 79 | 22 | 101 |
| `midi/proof.tst_midiexport.txt` | 0 | 13 | 13 |
| `nativegraphics/proof.tst_nativewindowing.txt` | 35 | 0 | 35 |
| `onboardcheck/proof.action.txt` | 40 | 9 | 49 |
| `onboardcheck/proof.debuglayout.txt` | 72 | 0 | 72 |
| `onboardcheck/proof.deletion.txt` | 71 | 0 | 71 |
| `onboardcheck/proof.import.txt` | 51 | 0 | 51 |
| `onboardcheck/proof.regionedlayout.txt` | 82 | 0 | 82 |
| `onboardcheck/proof.registration.txt` | 88 | 0 | 88 |
| `onboardcheck/proof.support.txt` | 13 | 0 | 13 |
| `project/proof.identity.txt` | 17 | 35 | 52 |
| `project/proof.ioflow.txt` | 49 | 16 | 65 |
| `project/proof.iomutations.txt` | 43 | 54 | 97 |
| `project/proof.mk.txt` | 36 | 0 | 36 |
| `project/proof.save.txt` | 1 | 34 | 35 |
| `project/proof.workspace.txt` | 83 | 17 | 100 |
| `retained/proof.tst_nativeboundaries.txt` | 18 | 0 | 18 |
| `rollcheck/proof.identity.txt` | 6 | 0 | 6 |
| `rollcheck/proof.keyboard.txt` | 4 | 2 | 6 |
| `rollcheck/proof.presentation.txt` | 0 | 7 | 7 |
| `rollcheck/proof.remap.txt` | 7 | 17 | 24 |
| `rollcheck/proof.resize.txt` | 0 | 6 | 6 |
| `rollcheck/proof.scale_editing.txt` | 0 | 3 | 3 |
| `rollcheck/proof.scale_projection.txt` | 0 | 3 | 3 |
| `rollcheck/proof.selection.txt` | 0 | 2 | 2 |
| `rollcheck/static/proof.geometry.txt` | 0 | 3 | 3 |
| `samplecheck/proof.analysis.txt` | 21 | 0 | 21 |
| `samplecheck/proof.decoder.txt` | 93 | 0 | 93 |
| `samplecheck/proof.dsp.txt` | 61 | 0 | 61 |
| `samplecheck/proof.editor.txt` | 80 | 0 | 80 |
| `samplecheck/proof.integration.txt` | 68 | 0 | 68 |
| `samplecheck/proof.project.txt` | 63 | 0 | 63 |
| `samplecheck/proof.soundfont.txt` | 22 | 0 | 22 |
| `selectionkey/proof.corearrows.txt` | 1 | 0 | 1 |
| `selectionkey/proof.gesturecommands.txt` | 0 | 4 | 4 |
| `selectionkey/proof.gesturevelocity.txt` | 0 | 5 | 5 |
| `selectionkey/proof.windowtier_keyboard.txt` | 0 | 1 | 1 |
| `selectionkey/proof.windowtier_lifetime.txt` | 0 | 1 | 1 |
| `swiftqtml/proof.tst_swiftqtml.txt` | 78 | 0 | 78 |
| `swiftrollbench/proof.tst_swiftrollbench.txt` | 6 | 0 | 6 |
| `swiftrollgated/proof.clipboardchecks.txt` | 2 | 0 | 2 |
| `themelayout/proof.tst_themelayout_color.txt` | 0 | 2 | 2 |
| `themelayout/proof.tst_themelayout_settings.txt` | 33 | 1 | 34 |
| `visual/proof.browsers.txt` | 5 | 3 | 8 |
| `visual/proof.chrome.txt` | 3 | 4 | 7 |
| `visual/proof.dialogs.txt` | 24 | 0 | 24 |
| `visual/proof.quick.txt` | 5 | 0 | 5 |
| `voicegroup/proof.tst_voicegroupbank.txt` | 0 | 15 | 15 |
| `voicegroup/proof.tst_voicegroupviewcache.txt` | 3 | 1 | 4 |
| `voicegroup/proof.voicegroupsourceediting.txt` | 7 | 0 | 7 |
| `voicegroupsave/proof.presentation.txt` | 6 | 0 | 6 |
| `voicegroupsave/proof.savecore.txt` | 11 | 0 | 11 |
| `workspace/proof.selftest_timeline.txt` | 13 | 0 | 13 |
| `workspace/proof.selftest_transport.txt` | 3 | 7 | 10 |
| `workspace/proof.session.txt` | 3 | 0 | 3 |
| `workspace/proof.tabs_scale.txt` | 2 | 4 | 6 |
| `workspace/proof.tabs_transport.txt` | 1 | 1 | 2 |
| **Total** | **1,714** | **421** | **2,135** |

## 15. Wave 131–138 — project persistence and remaining host consumers

### Scope and selection

This is the next wave, **after accepted/checkpointed 123–130, 118/119 and
bank-undo fix `3fbfe933`**, not permission to race their files. Planning used
`deno task proof list`, per-ledger `proof sites … --status GAP` and
`PARTIAL`, the live successor sources and `fceecd88` assertion locations.
The census is in-flight: re-query selected rows before dispatch; a row
closed by another accepted surface must not be reopened or double-owned.

Select **210 open rows: 103 GAP + 107 PARTIAL**. The largest eligible
clusters are project I/O/persistence, host composition and window lifecycle.
Break them at existing consumer boundaries, not arbitrary row quotas.
Smaller snapshot/recipe/history slices stay separate because they have
different owners and independently registered verification surfaces.
The 45-row geometry/tooltip composition task deliberately keeps its common
mounted band tree together.

| Task | Surface / brief | GAP | PARTIAL | Total | Route / seat |
|---|---|---:|---:|---:|---|
| 131 | [songs.mk-backed settings and byte-preserving removal](task-131-brief.md) | 36 | 0 | 36 | SDD-track / sdd-implementer — persisted recipe formatting and real reopen |
| 132 | [Exact Save/reopen and saved history point](task-132-brief.md) | 1 | 34 | 35 | SDD-track / sdd-implementer — disk/history/compiled-MIDI transaction |
| 133 | [Failed song I/O retains the live edit](task-133-brief.md) | 0 | 24 | 24 | SDD-track / sdd-implementer — four real failure/recovery paths |
| 134 | [Detached project snapshot and failed replacement](task-134-brief.md) | 0 | 16 | 16 | SDD-track / sdd-implementer — actor value and service adoption |
| 135 | [Startup recipe normalization reaches mounted tabs](task-135-brief.md) | 17 | 0 | 17 | SDD-track / sdd-implementer — existing value semantics plus preference/UI consumer |
| 136 | [Document gesture merge identities](task-136-brief.md) | 0 | 16 | 16 | SDD-track / sdd-implementer — saved-boundary and net-zero transitions |
| 137 | [Physical editor bands and Other Events tooltip](task-137-brief.md) | 29 | 16 | 45 | SDD-track / sdd-implementer — mounted cross-band geometry and input |
| 138 | [Atomic fresh/reloaded tab readiness](task-138-brief.md) | 20 | 1 | 21 | SDD-track / sdd-implementer — async readiness/retained-state publication |
| **Total** | | **103** | **107** | **210** | |

The exact row inventories and individual fork assertion-start lines live
only in the briefs. No source file or row outside those closed lists is
implicitly writable. All production and check files already exist; no
new source manifest, runner entry, C++ unit or test-only production API is
planned. More than three files in a brief is an explicit sizing exception
for one end-to-end surface, not permission to absorb adjacent work.

### Priority census and native retirement

| Inspected cluster | Current GAP / PARTIAL | Selected treatment |
|---|---:|---|
| project/workspace | 83 / 17 | Deferred worker event-order/catalog and startup-stage protocol; no invented replacement event bus |
| project/iomutations | 43 / 54 | 133 takes the complete failureStages consumer, A003–A026 |
| project/ioflow | 49 / 16 | 134 takes detached open and retained prior project; FIFO/catalog scheduling remains separate |
| mainwindowrouting/lifecycle | 48 / 27 | 138 takes freshBind and stagedReload together |
| host/hostadapter | 49 / 17 | 137 takes the physical band/tooltip composition surface |
| host/hostintegration | 51 / 13 | Not selected: velocity/audio/state consumers still reserved or require separate lifecycle ownership |
| project/identity | 17 / 35 | 135/136 take recipe and document-history consumers; identity construction A001–A019 remains |
| project/mk | 36 / 0 | 131 may close the complete ledger |
| project/save | 1 / 34 | 132 may close the complete ledger |

This prioritizes the `CppCensus` witnesses for unbuilt `src/core/songhistory`,
`songdocument`, `mainwindow` and `workspaceui*`: save, document history and
host/lifecycle consumers remove real blockers. The census is a blocker
list, not an exhaustive deletion certificate. In particular, its old
`mid2agbtables` DELETE_NOW claim is overridden by §14's retained
velocitymodel include blocker.

Only `project/proof.mk.txt` and `project/proof.save.txt` are whole-ledger
closure candidates. Their old C++ checks are already absent. Neither
closure alone frees an unbuilt production unit: SongDocument still has
host, automation, import, routing and excluded savecore witnesses;
SongHistory still has identity A001–A019, viewcache and transitive
SongDocument uses; mainwindow/workspace units retain other lifecycle,
input, onboarding and project-event obligations. Therefore **no C++
production deletion is in this wave's exact write sets**. Do not delete
native boundaries, remove includes opportunistically, or infer all users
are gone from one closed ledger.

### Write-set conflicts and execution order

`—` means the complete write sets are disjoint. `C` is shared code/check
ownership; `L` is only a shared ledger with disjoint A-row ownership.

| | 131 | 132 | 133 | 134 | 135 | 136 | 137 | 138 |
|---|---|---|---|---|---|---|---|---|
| 131 | — | — | — | — | — | — | — | — |
| 132 | — | — | — | — | — | — | — | C |
| 133 | — | — | — | C | — | — | — | — |
| 134 | — | — | C | — | — | — | — | — |
| 135 | — | — | — | — | — | L | — | — |
| 136 | — | — | — | — | L | — | — | — |
| 137 | — | — | — | — | — | — | — | — |
| 138 | — | C | — | — | — | — | — | — |

- 133 → 134: `src/checks/workspace/session_io.swift`.
- 132 → 138: `src/swift/app/DocumentSession.swift`.
- 135 / 136: `src/checks/project/proof.identity.txt`; a single ledger writer
  applies disjoint accepted row subsets serially, or in one accepted
  surface-code checkpoint. Their production/check work can run together.
- Semantic dependencies without shared writes: 131 → 132 (flags
  persistence); 135 → 138 (preserve startup normalization).
- Prior-wave reuse: 131 reuses 127/128's
  `SongRegistration+Removal.swift`; 134 reuses 126/127's
  `ProjectService+Songs.swift`; 137 reuses 130's
  `tst_SwiftRollPlots.qml`; 138 reuses 125's
  `tst_ShellTabsReload.qml`. 132/135/138 also wait for 118's complete
  document/view-state contract and released files.

Run code group A **131, 133, 135, 136, 137** concurrently after the prior-wave
gate. Run group B **132, 134** after their prerequisites are accepted;
checkpoint 133 before 134 reuses its file. Run **138** after 132 and 135;
checkpoint 132 before that reuse. Batch accepted work at those ownership
boundaries and final handoff, not one mandatory commit per task. No
unreviewed/failing writer may be checkpointed simply to unblock a successor.

### Shared constraints and verification

§14's real-input, independent full-state, no setup-only assertions,
isolated fixture/preferences, QtBridge ownership, font/contrast and
separate-ledger-writer contracts continue. Supersede its fixed 600-line
limit with the current keep-files-small rule: around 600 lines triggers
cohesion review, never a line-count-only split. This wave introduces no
new source files. Existing checks that pin incidental wording, forwarding
or obsolete representation must be removed rather than re-pinned.

Every brief names the narrow commands and their actual registered owner:
`checkcatalog.cpp` supplies projectstore-songsmk, projectstore-open,
projectidentitycheck, swiftcore-projectsession and
swiftcore-documenthistory; `ShellQmlEntries.swift` supplies the split shell
lanes. `RollQmlTests.swift` owns `PORYDAW_ROLL_QML_SUITE`. Reuse the recorded
commands; rediscover only on a concrete stale registration or changed
scope, never silently substitute a related passing lane.

Implementers run their narrow commands after edits settle, under the
recorded lock and 175-second alarm, in a coordinated settled-source window.
The lock serializes builds, not source edits. No project-wide tests,
formatters or linters mid-flight. Read-only proof queries are safe while
other writers work. Native mounted QML lanes need the existing macOS Qt
test environment; none of this wave's acceptance requires physical audio
output or ImageIO decoding. Geometry is not framebuffer/native-window
equivalence. Pure history and snapshot checks must exercise the actual
production document/store API, not mocks; mounted surfaces require real
input and observed state/file outcomes.

The separate ledger writer receives settled sources and executed evidence,
changes only selected rows, and lands them with their surface code.
Retiring a Qt pointer, stage envelope or setup guard never retires its
observable behavior. No fake stage injection, new event bus, source
repinning, standalone reconciliation or bulk compaction.

After all writers settle, the controller runs the project-wide gates once:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task proof check --executed
```

These are future execution requirements, not planning results. Planning
validation checks the eight briefs' links, selected IDs/dispositions,
fork citations, existing write paths and conflict matrix; no application
build or behavioral suite is run for this documentation-only commit.

### Deferred and excluded

- All 123–130 selected rows: velocity model/drawer; automation lane/MIME;
  roll identity/remap; registration/deletion/regioned layout (including
  not-yet-dispatched 127/128); workspace timeline/transport; roll
  raster/selection/scale. All 119 automation raster interaction/painting
  and ownership rows remain reserved. Bank-undo `3fbfe933` is preserved.
- `voicegroupsave/savecore` A016–A026: catalog-outage status/path policy
  still requires the user. New Voicegroup presentation A032–A037 and
  sourceediting A086–A092 remain excluded creation surfaces.
- **P3 WAV export and P4 sample studio await user decisions.** Sample
  decoder 93 GAP, DSP 61 GAP, editor 80 GAP, integration 68 GAP, project
  63 GAP, soundfont 22 GAP and analysis 21 GAP are larger than several
  selected slices but are not permission to implement that studio.
  ImageIO decode and physical audio-output observations are additionally
  unavailable-infrastructure exclusions. Consequently `src/audio/sample*`,
  `sf2reader`, `sampleeditordialog`, `sf2zonepicker` and `waveformview`
  remain blocked, including visual/dialogs consumers.
- Project workspace event/FIFO/catalog-preemption protocol, ioflow
  A013–A032/A039–A065, iomutations outside A003–A026 (including creation
  collision and closed-worker shutdown), onboarding action/debuglayout/
  support and import wizard A046–A096 are unselected follow-on surfaces.
  Native envelope retirement is bounded to selected consumer clauses;
  this is not a whole-project protocol retirement pass.
- Native focus/activation/clipboard-host ancestry, lifecycle A041,
  state A164/A171/A178 sidecar snapshots, hostadapter A079 drawer-toggle
  centring, unknown-synth-save and viewcache pending/dirty-close differences
  remain open. Transport A009/A010/A013 retain the user's cursor-never-seeks
  decision. Roll keyboard A077–A080 and selection A009 remain outside this
  wave. No silent parity-policy reversal.

## 16. Wave 139–146 — remaining project/host consumers and bounded mapping debt

### Selection and bounded briefs

Waves 123–138 are landed. This wave selects from the current 69-ledger
census, not the historical §14/15 counts. Planning executed
`deno task proof list`, per-ledger `proof sites <ledger> --status GAP`
and `PARTIAL`, and `deno task proof check --strict-mappings`. The strict
command currently exits 1 with **485 missing message-anchor errors**;
that is measured debt, not a passing verification result.

Select **168 open rows (134 GAP + 34 PARTIAL)** on seven existing consumer
surfaces, plus **295 already-MATCHED rows** for the explicitly requested
strict-mapping exception. A selected setup/envelope row is not a mandate
to add a setup-only assertion: classify its representation separately
from its consumer outcome. Complete row inventories and individual fork
citations live only in the briefs.

| Task | Surface / brief | GAP | PARTIAL | Mapping debt | Route / seat |
|---|---|---:|---:|---:|---|
| 139 | [Failed project open retains live state and persisted path](task-139-brief.md) | 13 | 0 | 0 | SDD-track / sdd-implementer — async replacement and isolated preferences |
| 140 | [Legacy sidecar bytes survive bare/recipe save and reopen](task-140-brief.md) | 0 | 15 | 0 | SDD-track / sdd-implementer — real file preservation through save variants |
| 141 | [Missing edit basis conflicts; matching bank edit applies](task-141-brief.md) | 0 | 15 | 0 | SDD-track / sdd-implementer — conflict, immutable identity and history |
| 142 | [Velocity commit values, stale rejection and axis voice context](task-142-brief.md) | 20 | 4 | 0 | SDD-track / sdd-implementer — gesture preview/commit state machine |
| 143 | [Drawer track commands and tempo-range selection](task-143-brief.md) | 14 | 0 | 0 | SDD-track / sdd-implementer — input routing and track/lane remap |
| 144 | [Background-tab isolation and fresh-tab identity](task-144-brief.md) | 15 | 0 | 0 | SDD-track / sdd-implementer — cross-tab publication and non-interference |
| 145 | [Byte-preserving debug sound-list registration](task-145-brief.md) | 72 | 0 | 0 | SDD-track / sdd-implementer — six file-format journeys, one owner |
| 146 | [Message-anchored predicates in four largest debt ledgers](task-146-brief.md) | 0 | 0 | 295 | SDD-track / sdd-implementer — mechanical shape, but clause-level evidence audit across four surfaces |
| **Total** | | **134** | **34** | **295** | |

Tasks larger than three files are explicit cohesive-surface sizing
exceptions: 143 spans the existing drawer command boundary; 144 spans
tab publication; 145 adds one cohesive scenario file and its manifest/caller;
146 is the requested bounded four-ledger exception. No open-ended file
ownership is implied by a conditional production repair: the closed path
and named declaration limits in each brief still apply.

### Priority census and retirement consequences

| Inspected cluster | Current GAP / PARTIAL | Treatment |
|---|---:|---|
| project/workspace | 83 / 17 | 139 takes failed-open/path-retention consumers; loading-refusal and worker protocol deferred |
| project/iomutations | 48 / 30 | 140/141 take sidecar save preservation and conflict/applied consumers |
| project/ioflow | 49 / 8 | FIFO/catalog-preemption protocol deferred; no replacement event bus |
| host/hostintegration | 51 / 13 | 142/144 take gesture and cross-tab/fresh identity consumers |
| host/hostadapter | 31 / 19 | 142/143 take exact velocity voice context and drawer commands |
| host/hostseams | 3 / 1 | 143/144 select all three GAPs; remaining PARTIAL is not implicitly closed |
| mainwindowrouting/lifecycle | 28 / 35 | Preserve landed 138; remaining native/window/policy clauses deferred |
| onboardcheck/debuglayout | 72 / 0 | 145 takes the full coherent six-scenario cluster |
| onboardcheck/import | 51 / 0 | Wizard UI is a separate unbuilt surface, not registration proof |
| onboardcheck/action | 40 / 9 | New-song action surface deferred |
| samplecheck decoder/editor/integration/project/DSP | 93/0, 80/0, 68/0, 63/0, 61/0 | Larger, but excluded P4 sample studio; no scope expansion |

This favors the project/document/host consumers that remain witnesses for
`src/core/*`, `src/mainwindow.*` and `src/ui/workspaceui*`, while closing a
whole eligible 72-row registration cluster. It does **not** pretend the
largest raw sample counts are authorized. `workspaceui_samples.cpp`
directly includes sample import/data, sf2reader, sampleeditordialog and
sf2zonepicker; the deferred sample surfaces therefore remain real
transitive blockers for `src/audio/sample*`, `sf2reader`, `sampleeditordialog`,
`sf2zonepicker`, `waveformview` and workspace composition.

Only debuglayout is a planned whole-ledger closure candidate. Its old C++
check is already absent. Core SongDocument/SongHistory retain project,
automation, routing and excluded savecore witnesses; mainwindow/workspace
retain window-close, onboarding and native obligations. Playhead sample
position/axis model checks do not certify native
`src/ui/playheadrenderer_macos.mm` rendering or lifetime. The available
native census is a blocker list, **not a transitive deletion certificate**.
Accordingly no production C++ deletion is in these eight write sets. Do not
delete a unit merely because one consumer ledger closes; any later deletion
must also discharge every remaining open direct/transitive witness and
respect the retained native boundaries.

Strict debt selected by 146 is 88 sourceediting + 78 clipboardchecks +
70 voicegroupbank + 59 windowtier-keyboard = 295; the other 190 planning
errors remain out of scope. This is a one-off user-requested exception to
the surface-first rule, not authority for general reconciliation. Existing
checks gain stable message anchors or clause splits only where they really
prove the fork clause. Uncovered selected clauses retain debt with explicit
reasons; all four ledgers must show a real reduction. The clipboard source
is post-fork and absent at `fceecd88`; its brief explicitly cites the ledger's
`68209547` pin instead of inventing a fork citation.

### Conflict matrix and execution order

`C` = shared production/check file. `L` = shared ledger, disjoint selected
A-rows. `—` = disjoint complete write sets (including conditional paths).
Read-only use of the same verification lane is not a write conflict.

| | 139 | 140 | 141 | 142 | 143 | 144 | 145 | 146 |
|---|---|---|---|---|---|---|---|---|
| 139 | — | — | — | — | — | — | — | C |
| 140 | — | — | L | — | — | — | — | C |
| 141 | — | L | — | — | — | C | — | C |
| 142 | — | — | — | — | L | L | — | — |
| 143 | — | — | — | L | — | L | — | — |
| 144 | — | — | C | L | L | — | — | — |
| 145 | — | — | — | — | — | — | — | — |
| 146 | C | C | C | — | — | — | — | — |

- 141 → 144: `src/swift/app/DocumentSession.swift`; checkpoint accepted 141
  before 144 reuses it. 144 also consumes the accepted project-session
  contracts of 139/140.
- 139/140/141 → 146: `session_io.swift`, `session_save.swift`, `bank_edits.swift`.
  Checkpoint their accepted writers before 146 anchors those files.
- 140/141 share `project/proof.iomutations.txt`.
- 142/143 share `host/proof.tst_hostadapter.txt`; 142/144 share
  `host/proof.tst_hostintegration.txt`; 143/144 share `host/proof.tst_hostseams.txt`.
  A single ledger writer applies disjoint accepted subsets serially.
- 145 alone owns the new `SongDebugLayoutChecks.swift` source-list addition
  in `src/checks/CMakeLists.txt`; it does not grant another manifest writer.
- 146 uses one implementer for all four debt surfaces; shared
  VoicegroupEditingChecks/ShellQmlTests/ShellWindow files are not separate
  concurrently writable slices.

Run group A **139, 140, 141, 142, 143, 145** after the landed-wave gate.
Run **144** after accepted/checkpointed 139–141. Run **146** after accepted
139–145, capturing a fresh strict inventory so legitimate earlier
surface changes are not confused with mapping-only work. Batch checkpoints
at those ownership boundaries and final handoff, not one commit per brief.
Never checkpoint failing or unreviewed work just to unblock a successor.

### Shared constraints and verification ownership

The §14/15 contracts continue: fork clauses win; one predicate per clause
and each A-id on exactly one predicate; independent literal expected
values rather than runtime read-back replacements; fail-closed fixture
setup; real production entry points; no copied implementations or mock
echoes; isolated files/preferences; Swift/QtBridge owns behavior and QML
owns presentation. Expected identity continuity may compare against the
identity captured before a transaction, never against the mutated result
itself. Do not add setup-only, incidental wording or bare not-throw tests.
Retire only representation, never its observable consumer obligation.
Setup/failure guards, including `report.fail` messages, carry no A-ids.
A-ids belong only to behavior predicates; report setup-only guards separately
for ledger classification.
DPR2 claims gate on the lane's declared DPR. QtBridge queued notifications
cannot prove same-GUI-pass geometry: those clauses stay PARTIAL.

Reuse the exact commands in the briefs; rediscover only on a concrete
registration mismatch or scope change, recording the replacement coverage.
Each implementer runs its brief's focused lanes under the existing
lock/175-second alarm before reporting, listing its predicate PASS lines.
Failures attributable to a sibling are acceptable for that scoped report
only when every owned predicate passes and each foreign failure is named;
they do not waive the controller's final integration gate. No project-wide
build/test suite, formatter or linter runs mid-flight. Read-only queries and
isolated source-level inspection remain safe while peers edit.
Mounted QML lanes require the existing macOS Qt desktop/test environment.
Pure service/file changes must execute actual production APIs and observe
state/disk outcomes; mounted changes require actual input and observed
surface state. No null-audio result proves physical output.

After accepted source changes settle, the controller owns the project-wide
gate; focused-lane execution remains each implementer's responsibility.
The live additional owners for 146 are projectstore-editing, bankleases,
swiftcore-bankhistory, shell-clipboard and shellwindow. The controller runs
these integration gates once:

```sh
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify --verbose
/usr/bin/lockf -t 1200 /tmp/porydaw-build.lock /usr/bin/perl -e 'alarm 175; exec @ARGV' deno task verify:shell --verbose
deno task proof check --executed
deno task proof check --strict-mappings
```

The strict gate's expected nonzero exit is accounted for by an exact
before/after `(ledger, A-id)` inventory, as specified in 146; do not pipe
away errors or call remaining debt a pass. The separate ledger writer
receives settled checks and fresh executed evidence, updates only selected
rows, and lands those rows with their proving source/check changes.

These are execution requirements, not planning results. This documentation
commit runs no application build or behavior suite. Planning validation
checks selected dispositions, fork assertion-start citations, all closed
write paths, brief links/headings and the computed conflict matrix.

### Deferred and excluded

- **P3 WAV export and P4 sample studio remain user-decision exclusions.**
  Decoder 93, editor 80, integration 68, project 63, DSP 61, soundfont 22 and
  analysis 21 GAPs are not permission to build those surfaces. ImageIO and
  physical audio-output clauses remain unavailable-infrastructure exclusions.
- Savecore A016–A026 catalog-outage status/path policy; transport
  A009/A010/A013 cursor-never-seeks ruling; unknown-synth-save and
  viewcache pending/dirty-close differences remain untouched.
- Workspace A003/A004 loading refusal has no Swift equivalent: deliberate
  project opening and startup priority are preserved, not silently reversed.
  Workspace startup terminal order, catalog-once/duplicate/refresh, plan
  keying, silent completions, reload phase protocol and remaining bank receipt
  clauses are deferred. Ioflow FIFO/catalog preemption and bank shadow/view
  sequences are deferred; no fake worker or stage-injection architecture.
- Iomutations A057–A072 receipt flags/identity, A073–A076 preview cleanup,
  A077–A087 creation collisions and A088+ closed-worker shutdown remain
  outside these bounded consumers.
- Onboarding action/import/support and remaining regioned-layout rows,
  New Voicegroup presentation/source-creation clauses and remaining
  mainwindow lifecycle/state/input/native surfaces are deferred.
- Hostintegration A174/A176/A177 require actual **window** close acceptance
  and both-song byte preservation. A tab disappearing is not that clause;
  no current selected lane delivers a real close to its own harness window.
  Native focus/grabber/teardown, 120-tick steady-context search, hostadapter
  A079 centring, A140 loop-marker raster, same-GUI-pass geometry and
  unselected mutation/signal/sidecar clauses remain open.
- The 190 strict-mapping errors outside the four named ledgers and any
  explicitly unproved selected clauses are deferred, not silently upgraded.

## 17. Wave 147–154 — registration closure and remaining project consumers

### Selection and bounded briefs

Planning baseline: `deno task proof list` reports **68 ledgers** while
144/146 are still in flight. Counts below are the selected rows' live
dispositions, not historical header tallies. Planning used per-area and
per-file `proof sites ... --status GAP` / `PARTIAL`, inspected current
Swift/QML owners and check registration, and read fork source with
`git show fceecd88:<path>`. The unscoped `proof sites --status GAP` form is
invalid; use `--area` or a source path.

Select **165 open rows (141 GAP + 24 PARTIAL)** across eight bounded
surfaces. Prioritize three whole-ledger candidates (action, support,
regionedlayout: 97 open rows) without pretending every remaining project
worker protocol or native raster clause is portable owner behavior.
Each brief contains the exact A-id/fork-line inventory and setup-only
classification; these tables intentionally do not repeat it.

| Task | Surface / brief | GAP | PARTIAL | Group | Route / seat |
|---|---|---:|---:|---|---|
| 147 | [Charmap-only Register repair, clean open-song deletion and fallback refusal](task-147-brief.md) | 40 | 9 | B | SDD-track / sdd-implementer — mounted confirmation, disk and tab outcomes |
| 148 | [Music-player limits reach opened project metadata](task-148-brief.md) | 13 | 0 | A | SDD-track / sdd-implementer — symbolic parser and effective-budget boundary |
| 149 | [Persisted MIDI import discovery and real compiler roundtrip](task-149-brief.md) | 18 | 0 | A | SDD-track / sdd-implementer — file/project/compiler boundary, not wizard UI |
| 150 | [Regioned remove/re-register marker repair and exact bytes](task-150-brief.md) | 35 | 0 | A | SDD-track / sdd-implementer — numeric/alias/migration/overflow invariants |
| 151 | [Song identity in registration/deletion plans and catalog reads](task-151-brief.md) | 12 | 0 | A | SDD-track / sdd-implementer — plan consumers without a fake FIFO |
| 152 | [Coherent workspace bank view and applied receipt](task-152-brief.md) | 0 | 15 | B | SDD-track / sdd-implementer — conflict and publication identity |
| 153 | [Bare and bank-recipe save flags and refreshed identity](task-153-brief.md) | 16 | 0 | B | SDD-track / sdd-implementer — ordered persistence and receipt semantics |
| 154 | [Mounted header voice-picker filter, reveal and Escape](task-154-brief.md) | 7 | 0 | A | SDD-track / sdd-implementer — actual header prompt, not request-only coverage |
| **Total** | | **141** | **24** | | |

The four-to-six-file write sets are explicit cohesive-surface exceptions:
each contains its real owner, existing check host and one ledger, with no
new manifest or runner registration. None is a standalone mapping/debt pass.
Already-proven clauses reuse their existing predicates; do not duplicate
journeys merely to attach IDs. Setup guards are not new passing assertions.

### Conflict matrix and dispatch groups

`—` means disjoint complete write sets, including conditional production
repairs and ledgers. There are **no intra-wave C or L conflicts**. Read-only
consumption of another task's owner and use of a common lane are not writes.
The complete closed paths live in each brief.

| | 147 | 148 | 149 | 150 | 151 | 152 | 153 | 154 |
|---|---|---|---|---|---|---|---|---|
| 147 | — | — | — | — | — | — | — | — |
| 148 | — | — | — | — | — | — | — | — |
| 149 | — | — | — | — | — | — | — | — |
| 150 | — | — | — | — | — | — | — | — |
| 151 | — | — | — | — | — | — | — | — |
| 152 | — | — | — | — | — | — | — | — |
| 153 | — | — | — | — | — | — | — | — |
| 154 | — | — | — | — | — | — | — | — |

| Group | Tasks | Prior-wave ownership gate / checkpoint |
|---|---|---|
| A | 148, 149, 150, 151, 154 | Accepted/checkpointed 139–143 and 145; no interface waits for 144/146. All five are independent writers. |
| B | 147, 152, 153 | Accepted/checkpointed 144 and 146 before file reuse. B may overlap unfinished A because its complete write sets are disjoint; it does not consume new A interfaces. |

Prior-wave reuse is concrete: 147 reuses `ShellQmlTests.swift` after 146;
152 reuses `DocumentSession.swift` after 144 and `bank_edits.swift` after
141/146; 153 reuses `session_save.swift` after 140/146. Neither group touches
`session_view_state_fanout.swift`, `tst_ShellTabsClose.qml`, host ledgers,
Task146's four debt ledgers, or its in-flight clipboard/focus/parameter/
label QML files. Do not reset or restage a sibling's edits.

Single-owner boundaries: 150 owns region algorithms; 151 owns service/store
plan adapters; 148 owns catalog/open budget mapping; 149 owns import/codec/
flags-writing checks; 153 alone owns `ProjectService+Bank.swift` (save methods
only); 152 consumes its edit methods read-only. No shared CMake,
`ShellQmlEntries.swift`, `SessionChecks.swift` or other runner-manifest writes.
If a demonstrated defect falls outside a closed set, stop for rebriefing
instead of creating an undeclared second writer.

Checkpoint accepted prior writers once at the B ownership gate, batching
other accepted A work when ready; persist remaining accepted work at final
handoff. There is no per-task commit requirement or A→B dependency added
merely for bookkeeping.

### Shared constraints and verification ownership

The fork/independent-literal/fail-closed rules in §16 continue. Setup and
error-buffer mechanics are classified separately, never mapped to a bare
successful call. Retire only representation, not visible behavior. Fresh
executed message predicates are required for every upgraded behavior row;
the separate ledger writer updates only that task's rows with the proving
source/check change. Whole-ledger deletion requires every row closed and
the corresponding old check source removed if still present. The three
candidate onboarding `.cpp` sources are already absent from the live tree.
No production C++ deletion is authorized by this wave.

For this wave, writers perform read-only/local structural inspection while
parallel edits are active; the controller runs the exact brief commands
once their shared compiled sources settle, under the lock/alarm policy.
This supersedes §16's implementer-owned focused-run timing for this wave,
not its evidence requirement. Deduplicate identical lane commands across
tasks, retain each task's named predicate evidence and hand settled checks
to the ledger writer. Do not run project-wide builds/tests, lint or
formatters mid-flight. Reuse the brief commands without rediscovery unless
a concrete registration mismatch or scope change is documented.

Covering lanes are `shell-songs`, `projectstore-open`,
`swiftcore-midiimport`, `swiftcore-projectsession`,
`swiftcore-bankhistory` and `verify:qml-roll`; their exact locked commands
are in the briefs. Important registration distinctions: bank receipt checks
run from `runBankHistorySuite`, not `runProjectSessionSuite`; import's
compiler seam only discovers registered song-table entries, so its two
compiler variants are registered while the roundtrip/discovery label stays
unregistered; the header picker mounts `VoicePickerPrompt.qml`, not the
drawer `VoicePicker.qml`. Native QML lanes require the macOS Qt desktop.
No null-backend result proves physical audio.

After all accepted sources settle, the controller owns the project-wide
integration gate once, using §16's locked `verify --verbose` and
`verify:shell --verbose`, plus the focused roll lane above and
`deno task proof check --executed`. Run `deno task proof check
--strict-mappings` only as an exact debt inventory: remaining out-of-scope
errors are not a pass and this wave does not renew 146's mechanical
exception. Planning checks validate documentation paths, headings, links,
selected dispositions, fork assertion-start citations and the computed
write-set intersections; this docs-only commit runs no application suite.

### Retirement flags and retained boundaries

**Whole-ledger candidates:** action (49), support (13), regionedlayout
(35 remaining) can be deleted after their selected surface passes and all
setup/representation rows are disposed alongside the proving change.
Their current GAP preambles are stale; that is not permission for a
ledger-only cleanup.

**No all-nonportable remainder was evidence-certified among the inspected
retirement candidates.** Do not delete a ledger merely because its original
C++ harness no longer builds. The following negative flags are deliberate:

| Ledger / remaining obligation | Evidence against blanket nonportable retirement |
|---|---|
| `retained/proof.tst_nativeboundaries.txt` (18 GAP) | Fork `tst_nativeboundaries.cpp:157–249` checks project open/song/bank publication, compiler/save, bank identity and loop/player progression through old C ABI units. A015–A019 (`:266–294`) include excluded export/audio. API-specific setup is representation; portable publication/save obligations and exclusions are not whole-ledger retirement evidence. |
| `nativegraphics/proof.tst_nativewindowing.txt` (35 GAP before 154) | A002/A008 (`:130,164`) are Win32 `WM_ERASEBKGND` representation candidates. A030–A036 are the live picker consumer selected by 154; A047 (`:304`) is persisted contrast 100; A055–A078 (`:405–460`) retain real rendered shrink/clear/reactivation outcomes. The removed chunk-store implementation alone cannot retire those pixels. |
| `swiftrollbench/proof.tst_swiftrollbench.txt` (6 GAP) | A009–A014 require published roll geometry, actual frames and moved scroll/zoom viewports. A dead timing harness does not make the viewport/render outcomes obsolete. |
| `swiftqtml/proof.tst_swiftqtml.txt` (78 GAP) | Synthetic BridgeProbe rows include live QtBridge model/replacement/delegate behaviors; a prototype-only fixture label is insufficient evidence that every framework contract is dead. No retirement certificate is claimed without a consumer audit. |
| Small PARTIAL tails | Automation presentation A037 still lacks a permanent physical DPR2 pencil-ink predicate; roll selection A009 retains audition sample-duration; windowtier lifetime A054 retains mounted in-memory song-byte isolation. These are coverage/infrastructure gaps, not all-representation tails. |

These are flags, not ledger edits. Native poryaaaa, clipboard/font and
`src/project/` boundaries remain retained under AGENTS.md; neither a
service test nor a screenshot authorizes deleting their implementation.

### Deferred and excluded

Only this wave's exact selected rows supersede §16 deferrals. In particular:

- Import wizard A046–A078 remains unbuilt; model/file compilation is not
  evidence for its controls, name sanitization, overflow refusal or accept.
- Project FIFO/result-count/catalog-preemption/stage-order protocols remain
  open. Swift's awaited value APIs are not a replacement event log.
  Workspace A003/A004 loading refusal and the pending-reload input gate
  stay deferred; workspace A099/A100 ghost-ID edit remains PARTIAL, not
  substituted with a foreign lease or arbitrary filesystem failure.
- Iomutations preview cleanup, creation-collision and shutdown rows remain
  open. A registration method that preserves an existing MIDI is not proof
  of an unbuilt New Song creation collision.
- Mainwindowrouting open clusters were inspected but not selected ahead of
  three eligible onboarding ledger closures. Whole-project view-only byte
  snapshots (`state` A164/A171) and actual native/window close and routing
  observations still need their own consumer evidence; Task144's tab-close
  lane must not be relabeled as window-close proof.
- Savecore A016–A026 catalog-outage policy; P3 WAV export; P4 sample studio;
  transport A009/A010/A013; physical audio output; ImageIO decoding; and
  pending-reload input gating remain excluded. No strict-mapping debt
  outside Task146's approved exception is selected.

## 18. Wave 155–162 — hygiene, ledger closures and remaining evidenced consumers

### Selection and bounded briefs

Planning baseline: `deno task proof list` reports **65 ledgers** with Task 152 in
flight (it is live-editing `project/proof.workspace.txt` rows A084–A098; counts drift
until it lands). Strict-mapping debt is **293**, Task 146's measured remainder; this
wave selects none of it. Planning ran per-ledger `proof sites ... --status GAP`/
`PARTIAL`, read fork sources at each ledger's pinned revision, and dispatched three
read-only scouts whose row classifications were re-verified against the live tree
before freezing. `proof check --executed` currently exits 1 with 70
voicegroupsourceediting "no executed predicate" errors and 71 "not executed" lines;
the voicegroupsourceediting half is owned by a parallel fix outside this plan, and
this wave owns only the themelayout S020 line.

Select **50 open rows (40 GAP + 10 PARTIAL)** plus the Review146 hygiene inventory,
two of them whole-ledger closures:

| Task | Surface / brief | GAP | PARTIAL | Group | Route / seat |
|---|---|---:|---:|---|---|
| 155 | [Review146 numbered-literal repair and themelayout S020 re-anchor](task-155-brief.md) | 0 | 0 | A | SDD-track / sdd-implementer — anchor/literal hygiene across five committed checks |
| 156 | [Drawer-band resize, hide and restore geometry on the mounted roll](task-156-brief.md) | 3 | 6 | A | SDD-track / sdd-implementer — mounted band lifecycle with queued-notification limits |
| 157 | [Startup restores the saved tab recipe through the real session path](task-157-brief.md) | 12 | 0 | A* | SDD-track / sdd-implementer — consumer restore semantics, deque ordering retired |
| 158 | [Mounted band plot/visibility projection completes canonical geometry](task-158-brief.md) | 3 | 4 | B | SDD-track / sdd-implementer — per-band projection residues on the roll lane |
| 159 | [Refused Insert Time on an unresolvable scope closes the keyboard ledger](task-159-brief.md) | 4 | 0 | A | SDD-track / sdd-implementer — production refusal path; whole-ledger deletion |
| 160 | [Mounted scroll/zoom frame cadence closes the swiftrollbench ledger](task-160-brief.md) | 6 | 0 | A | SDD-track / sdd-implementer — render-liveness proof on the roll lane; whole-ledger deletion |
| 161 | [Document mutation, undo and redo transitions around a live velocity gesture](task-161-brief.md) | 7 | 0 | A | SDD-track / sdd-implementer — service-level history contract |
| 162 | [Raster interaction residue: repeat leaves, hover clears, voice cursor](task-162-brief.md) | 5 | 0 | A | SDD-track / sdd-implementer — model-state clauses, pixel residue left open |
| **Total** | | **40** | **10** | | |

Write sets over four files (155) or three files (157) are explicit sizing exceptions
for one cohesive hygiene surface and one restore scenario; 159/160 add one call line
and one auto-enumerated suite file respectively. None is a standalone mapping pass:
every selected GAP row gets a real Swift/QML owner predicate, and the two closures
delete their ledgers only alongside the proving checks.

### Priority census and rejection evidence

| Inspected cluster | Current GAP / PARTIAL | Treatment |
|---|---:|---|
| project/workspace | 70 / 2 (live) | 157 takes the consumer-visible startup restore A018–A029 and retires the deque-ordering representation; A030–A083 protocol deferrals stand; A084–A098 belong to in-flight 152 |
| project/ioflow | 37 / 8 | Rejected: FIFO/catalog-preemption/stage-tag rows are the §16 protocol deferral; A051–A065 bank-view envelopes and preview shadow paths have no established consumer check (scout + §16) |
| project/iomutations | 32 / 0 | Rejected: A073–A097 preview cleanup, creation collision and shutdown stay deferred; no evidenced consumer |
| retained/tst_nativeboundaries | 18 / 0 | Rejected: A002–A005 duplicate executing session predicates; A006–A014 are five distinct consumers; A015–A019 excluded export/audio — no bounded single-surface brief is honest |
| nativegraphics/tst_nativewindowing | 28 / 0 | Rejected for this wave: A055–A078 are real rendered outcomes whose original stimulus current inputs do not produce (no invented harness stimulus); A047 needs a theme dialog the Swift shell does not have (`restoreAppearance` is startup-only); A002/A008 Win32 retirement rides with a future consumer |
| mainwindowrouting (4 ledgers) | 105 / 67 | Rejected: input GAPs are fixture guards/Qt wiring; lifecycle close/reopen already matched with sidecar-snapshot residues blocked; native foreign-window cluster A031–A058 has no proven Cocoa second-window lane; state whole-project snapshots blocked |
| host/hostintegration | 23 / 10 | 161 takes the mutation/undo/redo cluster; A162/A174–A185 (window close, teardown ordering) stay blocked |
| automation/raster interaction | 7 / 6 | 162 takes the five model-state rows; A025/A033 pixel probes stay GAP (no framebuffer readback) |

This favors clusters with verified owners, existing lanes and executable journeys —
including the only two honest whole-ledger closures found — over larger raw counts
whose rows are protocol machinery, native-window delivery or excluded surfaces.

### Conflict matrix and dispatch groups

`—` means disjoint complete write sets, including conditional production repairs.
`L` = shared ledger with disjoint accepted A-row subsets applied serially by one
writer. Read-only lane sharing is not a write conflict.

| | 155 | 156 | 157 | 158 | 159 | 160 | 161 | 162 |
|---|---|---|---|---|---|---|---|---|
| 155 | — | — | — | — | — | — | — | — |
| 156 | — | — | — | L | — | — | — | — |
| 157 | — | — | — | — | — | — | — | — |
| 158 | — | L | — | — | — | — | — | — |
| 159 | — | — | — | — | — | — | — | — |
| 160 | — | — | — | — | — | — | — | — |
| 161 | — | — | — | — | — | — | — | — |
| 162 | — | — | — | — | — | — | — | — |

| Group | Tasks | Gate |
|---|---|---|
| A | 155, 156, 159, 160, 161, 162 | After the landed-wave gate; all six are independent writers. |
| A* | 157 | Same parallelism as A, but dispatch only after in-flight **Task 152 is accepted/checkpointed** (it owns `proof.workspace.txt` and the session/bank files 157 must not disturb). |
| B | 158 | After 156's accepted `proof.tst_hostadapter.txt` rows are checkpointed (single ledger writer, disjoint subsets). Its QML work may proceed in parallel. |

Cross-wave boundaries: 155 re-points only `proof.windowtier_keyboard.txt` anchors and
`proof.tst_themelayout_color.txt` S020; neither 152 nor the parallel
voicegroupsourceediting fix owns those. 156/158 share the `swiftroll-window` lane
read-only and own different suite files (`tst_SwiftRollPlots.qml` vs
`tst_SwiftRollTrackHeaders.qml`); 160 adds `tst_SwiftRollCadence.qml`, which
`RollQmlTests.swift` enumerates automatically — no manifest edits anywhere in this
wave. 157/159/161/162 all execute under `swiftcore-projectsession` through different
check files. Do not reset or restage a sibling's edits; a demonstrated defect outside a
closed set stops for rebriefing.

### Shared constraints and verification ownership

The §16/§17 contracts continue unchanged: fork clauses win; one predicate per clause
and each A-id on exactly one predicate; independent literal expected values;
fail-closed fixture setup; real production entry points (staging through
`applyTimeSelection`/`restoreStartup`/page gesture APIs is real-input staging, not
mocking); no copied implementations; expected-identity comparisons only against
pre-transaction captures; setup guards carry no A-ids (NATIVE-SETUP disposition for
selected setup rows); retire only representation, never the observable consumer
obligation; DPR2 claims gate on the lane's declared DPR; QtBridge queued notifications
keep same-GUI-pass clauses PARTIAL (A095 deliberately stays PARTIAL in 156).

Writers run their brief's focused lanes under the existing lock/175-second alarm and
hand settled checks plus executed message evidence to the separate ledger writer, who
updates only that task's rows in the same commit as the proving change. The two
whole-ledger deletions (159, 160) also record their pinned-revision citations and the
absence of the old C++ sources. No project-wide builds, tests, formatters or linters
run mid-flight; native mounted lanes (156, 158, 160, and 155's shell lanes) require the
macOS Qt desktop environment.

After all accepted sources settle, the controller owns the project-wide gate once,
using §16's locked `verify --verbose`, `verify:shell --verbose`, plus
`deno task proof check --executed`; `proof check --strict-mappings` runs only as the
exact debt inventory (expected residue: the unchanged 293 minus any rows the parallel
voicegroupsourceediting fix retires, which is not this wave's claim). Planning
validation for this docs-only commit checked brief links/headings, selected
dispositions, fork assertion-start citations at pinned revisions, lane registrations
and the computed write-set intersections; no application suite was run.

### Deferred and excluded

- The voicegroupsourceediting S092–S161 executed-anchor repair (helper message
  emission) and the A001/A015 fixture-predicate hygiene are owned by the parallel fix
  outside this plan; no brief in this wave touches
  `VoicegroupEditingChecks.swift` or `proof.voicegroupsourceediting.txt`.
- Retained `tst_nativeboundaries`, nativewindowing A002/A008/A047/A055–A078,
  ioflow A039–A065, iomutations A073–A097, mainwindowrouting native/window-close/
  snapshot clusters and hostintegration A162/A174–A185 remain open with the rejection
  evidence above; a dead harness is not a retirement certificate.
- Workspace protocol deferrals (A003/A004 loading refusal, pending-reload input gate,
  catalog-once/plan-keying/silent completions) stand; 157 supersedes only the
  consumer-visible restore half of the startup-terminal-order deferral.
- Savecore A016–A026 catalog-outage policy; P3 WAV export; P4 sample studio; transport
  A009/A010/A013; physical audio output; ImageIO decoding; strict-mapping debt outside
  Task146's exception: all unchanged.

## 19. Wave 163–170 — Review159 fix and seven surface-first completions

### Selection and bounded briefs

Planning baseline: `deno task proof list` reports **63 ledgers** with Task 158 in
flight; strict-mapping debt is **293 sites**. A first draft of this section proposed
ledger-only mapping batches; it was rejected against
`.omp/rules/proof-ledger-workflow.md` (no reconciliation waves; a brief naming only
ledgers or disposition targets is invalid) and is superseded by this surface-first
plan. Strict-mapping debt is now addressed only incidentally: a closed row's
message anchor lands in the same commit as the code and checks that prove it, and no
task targets disposition counts.

Each brief below names a user-visible surface whose behavior is missing or divergent,
verified against the fork (each ledger's pinned revision) and the current Swift/QML
code at planning time:

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 163 | [Reload drops a stale primary track instead of installing it](task-163-brief.md) | 1 fix + regression | A |
| 164 | [Activating a polyphony event row reveals its note in the roll](task-164-brief.md) | presentation A018–A024 (7 PARTIAL; ledger closes whole) | A |
| 165 | [Deleting a track remaps SongView-owned state atomically](task-165-brief.md) | remap A044/A045/A048/A049/A056–A058 (7 PARTIAL; ledger closes whole) | B |
| 166 | [Voicegroup switch/null terminates an active velocity gesture](task-166-brief.md) | hostintegration A114–A120; hostseams A017 (ledger closes whole) | A |
| 167 | [Physical B-key mode switch retains a held stroke at its snapped cell](task-167-brief.md) | automationownership 15 PARTIAL | A |
| 168 | [A stale time-signature form accepts typed edits and closes harmlessly](task-168-brief.md) | routing input A092 + A113–A115 | A |
| 169 | [Grid contrast becomes a real setting in the mounted settings dialog](task-169-brief.md) | nativewindowing A047 | A |
| 170 | [A reloaded song presents its resolved bank identity to the voicegroup dock](task-170-brief.md) | ioflow A051–A054 | A |

Evidence for the missing behaviors: `EventListTable.qml` row clicks only select the
table row (no roll reveal); `DocumentSession+Selection.swift:13,47` and
`DocumentSession.swift:96-98` structurally forbid the note+time selection coexistence
the remap clauses stage; the hostintegration ledger states voice-replace/null has "no
voicegroup-switch cancel plumbing"; the ownership rows' landed predicates accept
loose endpoints (ticks 166–168 vs the fork's exact `endCell.tickBegin`) and never
deliver the physical B key; the stale-form mounted delivery clauses are named unproved
in the routing input ledger; `ShellPresenter.gridLineContrast` has a restore path but
no writing surface; and the ioflow ledger records that only the timeline callback —
never the bank view identity — is observed.

### Conflict matrix and dispatch groups

All eight complete write sets are pairwise disjoint, including conditional repairs
(163 `ApplicationSession+Tabs.swift`; 164 `EventListTable.qml` + eventlist presenter;
165 `DocumentSession+Selection.swift` + the delete-track command seam; 166 the
velocity cancellation seam + `VelocityClickCancellationChecks.swift` +
`tst_ShellWindow.qml`; 167 `automationcanvasediting.swift` + `tst_EditorDrawer.qml`;
168 `tst_ShellGridMenuRulerLifecycle.qml` + `session_time_routing.swift`; 169
`SettingsDialog.qml` + `ShellPresenter.swift`; 170 `tst_ShellVoicegroup.qml` + the
bank check file). Lane sharing is read-only. Task 158's write set
(`tst_SwiftRollTrackHeaders.qml`, `proof.tst_hostadapter.txt`,
`TrackHeadersGeometry.swift`) is excluded from everything; 165's production seam must
not land in `TrackHeadersGeometry.swift` — if the delete-track command lives there,
165 sequences after 158's checkpoint.

| | 163 | 164 | 165 | 166 | 167 | 168 | 169 | 170 |
|---|---|---|---|---|---|---|---|---|
| each | — | — | — | — | — | — | — | — |

| Group | Tasks | Note |
|---|---|---|
| A | 163, 164, 166, 167, 168, 169, 170 | Independent writers; dispatch immediately after the landed-wave gate. |
| B | 165 | Parallel-safe (no write conflicts) but grouped alone: the selection-coexistence edit is the wave's riskiest change and carries its own preservation list of landed clearing predicates that must stay green. |

### Shared constraints and verification ownership

The §16–§18 contracts continue: fork clauses win; one predicate per clause;
independent literal expectations; fail-closed staging; real production entry points
and real input on mounted surfaces; expected identities compared only against
pre-transaction captures; WCAG AA beats parity; DPR claims gate on the lane's
declared DPR; queued QtBridge notifications keep same-GUI-pass clauses PARTIAL.

Ledger instructions for every task: rows are edited only in the commit whose code and
checks prove them; closed rows use the compact form — header + `Disposition` + one
S-citing mapping line, no pasted C++/Swift code (cite the pinned revision for
originals); whole-ledger deletion (164, 165, 166's hostseams) also records the
already-absent C++ source. Under the standing protocol the separate ledger writer
applies each task's accepted rows from the implementer's evidence.

Writers run their brief's focused lanes under the lock/175-second alarm; no
project-wide builds, tests, formatters or linters mid-flight; mounted lanes need the
macOS Qt desktop. After accepted sources settle, the controller owns the project-wide
gate once (§16's locked `verify --verbose`, `verify:shell --verbose`,
`proof check --executed`) and reads `proof check --strict-mappings` as the exact debt
inventory — incidental reductions from these surfaces are welcome, targeted
reductions are not. Planning validation for this docs-only commit checked brief
links/headings, fork citations at pinned revisions, lane registrations
(`shell-tabs-reload`, `shell-event-list`, `shellwindow`, `editorqml-drawer`,
`shell-grid-menu-ruler-lifecycle`, `shell-settings`, `shell-theme`,
`shell-voicegroup`, `swiftcore-projectsession`, `swiftcore-bankhistory`), the cited
missing-behavior evidence, and pairwise write-set disjointness; no application suite
was run.

### Deferred and excluded

- Strict-mapping debt (293 sites) has no dedicated tasks in this wave: clipboard
  checks' helper-anchored sites, midiexport's literal-less evidence, hostadapter's
  in-flight ledger, samplecheck's P4 rows and the small tails keep their debt until
  a surface task's commit touches their rows incidentally.
- Remaining GAP clusters keep their standing rejection evidence: workspace/ioflow/
  iomutations protocol deferrals, retained's duplicate consumers, nativewindowing
  A055–A078 (rendered stimulus) and A002/A008 (Win32), routing fixture guards and
  snapshot/foreign-window blocks, hostintegration A162/A174–A185, the import wizard,
  ED11 clipboard text ownership.
- Review159's neighboring restore fields stay as designed; only the unfiltered
  primary changes. All standing exclusions (savecore A016–A026, P3 WAV, P4 sample
  studio, transport A009/A010/A013, physical audio, ImageIO, pending-reload gate)
  are unchanged.

## 20. Wave 171–174 — the four surfaces that survive the constraints

### Selection and bounded briefs

Planning baseline: `deno task proof list` reports **61 ledgers**; 167/168 are in
flight and 164 is blocked on QtBridge QML→Swift object passing. Hard write-set
exclusions for this wave (the note-rendering performance agent's territory):
`GridScene*`, `PianoGrid*`, `PianoRollCanvas.qml`, `TimelineQuickItem.qml`,
`src/ui/songview/quick/swiftroll/*.qml`, `QuickDisplayListItem`,
`cmake/patches/qtbridge/*`, `src/swift/app/CMakeLists.txt`,
`src/checks/CMakeLists.txt` and `ShellQmlEntries.swift` — so no new check files and
no new lane entries anywhere in this wave; every predicate extends an existing host.
Three read-only scouts audited the preferred areas (shell chrome, project/songs/
voicegroup services, drawer pages outside the roll bands, Swift core
document/history) plus my own verification of each surviving candidate against the
live tree and each ledger's pinned fork revision.

Eight briefs were requested; **four survive the evidence**. Every other audited
cluster is blocked, representation, owner-decision or excluded — padding the wave
with ledger-only work would repeat the §19 rejection.

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 171 | [New Song creates from the current song and refuses MIDI collisions](task-171-brief.md) | iomutations A077–A087 (11 GAP) | A |
| 172 | [Repeated hover/leave transitions leave the document byte-identical](task-172-brief.md) | interaction A013/A021 (2 PARTIAL) | A |
| 173 | [Showing the Event List removes the roll band from the published set](task-173-brief.md) | hostadapter A113/A114/A117/A118 | A |
| 174 | [Band geometry exists and survives appearance changes](task-174-brief.md) | hostintegration A008/A142 (2 GAP) | A |

171 is the only brief that builds a missing flow (the registered-but-dead
`file.new_song` command is the surface); it carries an explicit controller scope flag.
173/174 observe published layout state, never rendering output.

### Blocked-cluster census (why the wave is four)

| Cluster | Blocker |
|---|---|
| Event-list polyphony reveal (164) | QtBridge cannot pass objects QML→Swift; needs the user's bridge work or a check-only seam |
| mainwindowrouting lifecycle/state/input remainder | project-store snapshots and multi-song fixtures (`swift-project-store`), sidecar equality, native window close, `rebind(null)` seam absent, QAction/focusWidget representation |
| Theme dialog (themelayout settings + visual dialogs A009) | owner decision: a separate ThemeDialog would duplicate the landed settings contrast control |
| visual dialogs remainder | frozen QWidget pixel baselines; sample editor/sf2/wizard rows are P4-excluded |
| transport tabs A062 | physical audio output readback (excluded infrastructure) |
| iomutations A073–A076, ioflow A061–A065 | private preview-cleanup/result contracts and preview-plan paths — internal, no consumer |
| workspace A030–A083 | standing protocol deferrals (event bus absence), unchanged |
| retained, nativewindowing A055–A078/A002/A008 | duplication with executing checks; rendered stimulus current inputs cannot produce; Win32 internals |
| hostintegration A162/A174–A185, A083–A098 | fixture fingerprint, real window close/teardown ordering, grabber identity |
| midi/tst_midiexport PARTIALs | setup/guard classification tails over already-executing export predicates — no missing behavior |
| project/identity A001–A019 | value-level predicates already execute under `projectidentitycheck`; any disposition change would be reconciliation, which §19's rejection forbids |

### Conflict matrix and dispatch groups

All four write sets are pairwise disjoint and touch no forbidden file: 171 owns
`ProjectService+Songs.swift`/`SongDockController.swift`/`ShellPresenter.swift`/the
dock prompt/`SongRegistrationChecks.swift`/`tst_ShellSongs.qml`; 172 owns
`painting_raster.swift`; 173 owns `tst_SwiftRollPlots.qml` (Event List leg) with a
conditional `EditorDrawerLayout.swift` repair; 174 owns `HostBehaviorChecks.swift`.
173 and 174 both conditionally touch `EditorDrawerLayout.swift` — 173's condition is
the published band set, 174's is geometry preservation; if both repairs trigger,
sequence the second after the first's checkpoint (single owner per accepted change).

| | 171 | 172 | 173 | 174 |
|---|---|---|---|---|
| each | — | — | — | — |

| Group | Tasks | Note |
|---|---|---|
| A | 171, 172, 173, 174 | Independent writers; 171 dispatches only after the controller accepts its scope flag. |

### Shared constraints and verification ownership

The §16–§19 contracts continue unchanged, plus this wave's hard exclusions: no
roll/grid rendering files, no CMake/manifest/registration edits, no new check files
or lanes, 167/168's in-flight files untouched, and no QtBridge object passing. Ledger
instructions: rows are edited only in the commit whose code and checks prove them;
closed rows use the compact form (header + `Disposition` + one S-citing mapping line,
no pasted code); the separate ledger writer applies each task's accepted rows from
the implementer's evidence. Writers run their focused lanes under the lock/175-second
alarm; mounted lanes need the macOS Qt desktop; no project-wide builds, tests,
formatters or linters mid-flight. The controller owns the project-wide gate once
after sources settle. Planning validation for this docs-only commit checked brief
links/headings, fork citations at pinned revisions, lane registrations
(`projectstore-songsmk`, `shell-songs`, `swiftcore-projectsession`,
`swiftroll-window`), the dead `file.new_song` command, existing predicate coverage in
`tst_ShellRollPlots.qml`/`painting_raster.swift`/`HostBehaviorChecks.swift`, and
pairwise write-set disjointness; no application suite was run.

### Deferred and excluded

- Unlock paths for future waves: the user's QtBridge object passing (unblocks 164),
  `swift-project-store` landing (lifecycle/state sidecar rows), the theme-dialog and
  drawer-toggle-centring owner decisions (A079), and a verified real window-close
  harness pattern (hostintegration A174–A177).
- Strict-mapping debt remains untouched by design; reductions only ride incidentally
  with these surfaces' commits.
- All standing exclusions unchanged: savecore A016–A026, P3 WAV, P4 sample studio,
  transport A009/A010/A013, physical audio, ImageIO, pending-reload gate, ED11
  clipboard text ownership, New Voicegroup creation surfaces.

## 21. Wave 175–178 — unreachable-state rulings and the clean-file remainder

### Selection and bounded briefs

Planning baseline: 62 ledgers, 1132 open rows (903 GAP + 229 PARTIAL), strict debt
286. HEAD `f20232a0`. The foreign QML-performance work owns 88 dirty files,
including nearly every `tst_Shell*.qml` support test, the rollqml tests, several
rollcheck files, the whole velocity/OtherEvents drawer, the roll rendering set, both
CMakeLists, `ShellQmlEntries.swift`, `checkcatalog.cpp` and `fwd.hpp`. Every brief
below was verified to touch only files clean in `git status`. The two new user
rulings apply: unreachable fork states close as RETIRED-REPRESENTATION with refusal
predicates (159/166/168 precedent), and a voicegroup switch stays an undoable edit.

Six tasks were requested; **four survive** the clean-file and surface-first filters:

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 175 | [Command enablement refuses the unbound-with-selection state](task-175-brief.md) | state A087–A091 (5 GAP; ruling) | A |
| 176 | [A pending reload never exposes a partially bound tab](task-176-brief.md) | lifecycle A076–A079, A081 (5 GAP; ruling) | A |
| 177 | [The track-header input binds to the published headers geometry](task-177-brief.md) | hostadapter A080/A082 (2 GAP) | A |
| 178 | [Switching projects empties the tab set before the new project lands](task-178-brief.md) | lifecycle A091–A093 (3 GAP) | A |

### Why not six — census evidence

- Every remaining open cluster's check hosts, production owners, or both are dirty
  (foreign): the Event List reveal family beyond blocked 164, the automation raster
  pixel rows, the clipboardchecks ledger (foreign-modified), `tst_ShellTabsReload`,
  `tst_SwiftRollPlots`, `tst_ShellGridMenu*`, pitch-bend and note-visuals tests.
- The remaining lifecycle/state/input GAPs are fixture guards,
  `swift-project-store`-classified (sidecar snapshots, project view-state settings,
  failed-switch retention), native window close, QAction/focusWidget identity, or
  the excluded pending-reload gate; iomutations/ioflow/workspace protocol
  deferrals stand; retained/nativewindowing keep their standing rejection evidence;
  midiexport and project-identity PARTIALs are guard/value tails over executing
  predicates (reconciliation is forbidden by §19's rejection).
- hostadapter's remainder after 177: A079 (owner decision), A098 (staging row),
  A118 (foreign host), A140 (foreign OtherEvents raster). hostintegration's
  remainder: A162 fixture fingerprint, A174–A185 real-window close/teardown, and
  focus/grabber rows whose velocity half is foreign.
- The import wizard stays a separately-deferred unbuilt surface; savecore A016–A026
  and the pending-reload gate stay open user decisions; P3/P4 unchanged.

### Conflict matrix and dispatch groups

All four write sets are pairwise disjoint and clean: 175 owns
`session_edit_routing.swift` + the state ledger; 176 owns `session_io.swift` + the
lifecycle ledger's staged-readiness rows; 177 owns `tst_SwiftRollTrackHeaders.qml` +
conditional `TrackHeadersGeometry.swift` + the hostadapter ledger; 178 owns
`tst_ShellWindow.qml` + the lifecycle ledger's project-switch rows. 176 and 178
share the lifecycle ledger over disjoint A-row subsets applied serially by the
single ledger writer.

| | 175 | 176 | 177 | 178 |
|---|---|---|---|---|
| each | — | — | — | — |

| Group | Tasks | Note |
|---|---|---|
| A | 175, 176, 177, 178 | Independent writers; all four may dispatch together once 167/168 land (their files are already free). |

### Shared constraints and verification ownership

The §16–§20 contracts continue, plus this wave's foreign-file ban (velocity drawer,
OtherEvents, AutomationMenu, roll rendering, cmake patches, both CMakeLists,
`ShellQmlEntries.swift`, `checkcatalog.cpp`, `fwd.hpp`, and every test dirty in
`git status`) — if a brief's file becomes dirty before dispatch, stop for rebriefing
rather than editing foreign territory. The unreachable-state ruling applies only
where a named Swift guard makes the fork state unreachable, with an executed refusal
predicate in the closing commit; the voicegroup-undoable ruling changes no row here
(its deviating behaviors already landed with 166). Ledger instructions: rows edited
only in the proving commit; compact form (header + `Disposition` + one S-citing
mapping line, no pasted code); the separate ledger writer applies accepted rows.
Writers run their focused lanes under the lock/175-second alarm (macOS Qt desktop
for 177/178); no project-wide builds, tests, formatters or linters mid-flight; the
controller owns the project-wide gate once after sources settle. Planning validation
for this docs-only commit checked brief links/headings, pinned fork citations, row
statuses (A076–A093/A080/A082/A087–A091 verified GAP), file cleanliness against
`git status`, lane registrations, and pairwise disjointness; no application suite
was run.

### Deferred and excluded

- Unlock paths: the user's QtBridge object passing (164), `swift-project-store`
  (lifecycle sidecar/view-state families), the theme-dialog and A079 centring
  decisions, a real window-close harness pattern (A174–A177), and the foreign
  performance work landing (frees the dirty test hosts).
- Strict-mapping debt untouched by design. Standing exclusions unchanged: savecore
  A016–A026, pending-reload input gate, P3 WAV, P4 sample studio, transport
  A009/A010/A013, physical audio, ImageIO, ED11 clipboard text ownership.


## 22. Wave 179–187 — the freed drawer, raster and roll surfaces

### Selection and bounded briefs

Planning baseline: 62 ledgers; HEAD `0504b68b` (the QML-performance wave landed
the velocity drawer, OtherEvents, roll rendering, the shell test hosts and the
registration files; full gate green: verify 36/36 → verify:shell 76/76,
verify:qml, verify:qml-roll, `proof check --executed` clean). Every file §20/§21
excluded as foreign is now free; nothing is dirty except the user's untracked
`docs/plans/swift-clipboard-cutover/`, `docs/plans/swift-keybindings-integration/`,
`.omp/rules/swift-typecheck-complexity.md` and `profiler/`.

The wave has one lane-red fix task plus eight surface tasks, each verified
against the live tree and each ledger's pinned fork revision:

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 179 | [Menu focus is synchronous and survives dismissal arbitration](task-179-brief.md) | check fix only (no ledger rows) | A — dispatches first |
| 180 | [The automation drawer pan owns band focus, the input grab and shared commands](task-180-brief.md) | hostintegration A083/A085/A087/A089/A091/A098 (6 GAP); gesturecommands A016/A017 (2 PARTIAL) | A |
| 181 | [Velocity gestures are byte/history-invariant on cancel, and handles track scroll in the same frame](task-181-brief.md) | gesturevelocity A005/A006/A017–A019 (5 PARTIAL); gesturecommands A005–A007 (3 PARTIAL); hostintegration A119/A122 (1 PARTIAL + 1 GAP); scroll-lag fix | A |
| 182 | [Every drawer band publishes its geometry through show, hide and Event List swap](task-182-brief.md) | hostadapter A098/A118/A140 (3 GAP) + A113 (1 PARTIAL) + tooltip anchors A123/A129/A131–A133 | A |
| 183 | [Mounted automation raster completes the pointer-visible pixel contract](task-183-brief.md) | raster interaction A012/A032/A037/A044 (4 PARTIAL) + A025/A033 (2 GAP); raster painting A018/A027 (2 PARTIAL) + A023/A024/A026 (3 GAP); nodedrag A056/A057/A067; ownership A103/A104; painting A018/A038/A048; presentation A037 | A |
| 184 | [Automation gestures compare the full document snapshot at every staged mid-point](task-184-brief.md) | automationgesturecheck contract A063, crosslane A001/A011, hover A013, parity A007/A010/A011/A015/A016; automationselection A124/A131–A133; hover A017 | A |
| 185 | [A pending bank transition gates close and bank actions on its origin tab only](task-185-brief.md) | voicegroupviewcache A046/A047/A068 (3 GAP; registered divergence flagged) | A |
| 186 | [An incidental band or chrome press preserves an eligible note selection](task-186-brief.md) | corearrows A007 (1 GAP) | A |
| 187 | [The songs surface keeps its category list through close and reopen](task-187-brief.md) | workspace/session A017 (1 GAP) | A |

### What was excluded and why

- Automation raster was previously assessed as "no Swift framebuffer readback";
  that is stale: the mounted drawer lane already raster-proves ink via
  `grabImage` (`tst_EditorDrawerAutomationCurves.qml`/`Preview`/`Hover`), so the
  raster ledgers' surviving pixel tails are task 183, not a standing block.
- Mouse-grabber identity (`quickWindow->mouseGrabberItem()`) has no direct QML
  counterpart; 180 proves the observable contract (events keep reaching the
  grabbing item outside its bounds, grab ends on release/ungrab/page switch)
  and the focused-band publication. If that proves truly unobservable the rows
  close as RETIRED-REPRESENTATION with refusal predicates per the standing
  ruling — the brief carries both paths.
- velocity-context scroll-alignment: no dedicated ledger row covers same-turn
  scroll alignment; `hostadapter` A095's same-GUI-pass conjunct stays PARTIAL
  (QtBridge queues notifications — standing residue). 181 carries the
  `handlesOriginX` container-translate fix per the controller ruling, proven by
  a mounted scroll-alignment predicate, not a ledger row.
- 164 stays blocked on QtBridge QML→Swift object passing; its
  `rollcheck/presentation` A018–A024 conjuncts remain untouched.
- Ledger-only closures stay forbidden: rollcheck/resize cursor-bitmap
  conjuncts (A002–A004/A020/A027/A028) and rollcheck/identity A014 are
  representation/anchor tails with no missing behavior; they ride only
  incidentally inside a surface commit. Same for hostintegration A003/A004/A007
  fixture-context tails.
- Unchanged blocks: automation raster's `interaction` A025 second-leave needs
  no new ingress beyond 183's added second-leave predicate; automationhover
  MouseHints source-token rows (A108/A121/A123/A126/A133/A143) name a native
  pointer-token identity that has no observable Swift surface; mainwindowrouting
  input/state/lifecycle/native remainders (fixture guards, `swift-project-store`
  sidecars, native window close, QAction/focusWidget); workspace session
  A024/A042 (sidecar path, no Swift owner) and tabs_transport A062 (physical
  audio readback); project ioflow/iomutations/workspace protocol deferrals;
  themelayout settings (owner decision); onboardcheck import wizard; native
  boundaries; voicegroup source creation (VG03); voicegroupbank tails
  (savecore family A087–A093 pending user decision); samplecheck (P4);
  swiftrollgated ED11 text ownership; visual browsers/dialogs/quick/chrome
  baselines. All standing exclusions are unchanged.

### Conflict matrix and dispatch groups

Write sets are pairwise disjoint (each brief lists its exact set). Two pairs
share ledgers over disjoint A-row subsets — hostintegration (180: A083–A098;
181: A119/A122) and gesturecommands (180: A016/A017; 181: A005–A007) — applied
serially by the single ledger writer. Conditional production repairs stay in
the owning file set; no two tasks write the same file.

| Group | Tasks | Note |
|---|---|---|
| A | 180, 181, 182, 183, 184, 185, 186, 187 | Independent writers; 179 dispatches first (it fixes a red-check root cause and touches `AutomationMenu.qml`/`EditorSurface*.qml` that 180/183's mounted probes drive). Ledger rows serialized through the ledger writer. |

### Shared constraints and verification ownership

The §16–§21 contracts continue: fork clauses win; one predicate per clause with
its unique complete literal; each A-id on exactly one predicate; independent
literal expectations; fail-closed staging; real production ingress and real
input; no Qt.callLater, no focus memory, no second dispatcher, no test-only
ingress/API, no idempotence guards; WCAG AA beats parity; DPR claims gate on
the lane's declared DPR; queued QtBridge notifications keep same-GUI-pass
clauses PARTIAL. Ledger rows are edited only in the commit whose code and
checks prove them; closed rows use the compact form. Writers run their brief's
focused lanes under the lock/175-second alarm (macOS Qt desktop for mounted
lanes); no project-wide builds, tests, formatters or linters mid-flight; the
controller owns the project-wide gate once after sources settle. Planning
validation for this docs-only commit checked brief links/headings, pinned fork
citations, row statuses (`proof sites` per area), lane registrations
(`shellwindow-label-commands`, `shell-grid-menu-automation`, `editorqml-drawer`,
`swiftroll-window`, `shell-grid-input`, `shellwindow`, `shellwindow-velocity`,
`shell-songs`, `swiftcore`, `swiftcore-projectsession`, `swiftcore-bankhistory`),
and pairwise write-set disjointness; no application suite was run.

### Deferred and excluded

- Unlock paths: the user's QtBridge object passing (164 and rollcheck
  presentation A018–A024), `swift-project-store` (lifecycle sidecar/view-state
  families), the theme-dialog and hostadapter A079 centring decisions, a real
  window-close harness (hostintegration A174–A185, A162), the catalog-outage
  savecore rows, and the hostadapter A095 same-GUI-pass residue.
- Strict-mapping debt untouched by design; reductions only ride incidentally
  inside 182/183's surface commits (their tooltip/anchor landings).
- Standing exclusions unchanged: savecore A016–A026, pending-reload input gate,
  P3 WAV, P4 sample studio, transport A009/A010/A013, physical audio, ImageIO,
  ED11 clipboard text ownership, New Voicegroup creation surfaces, visual
  baselines.

## 23. Wave 188–193 — the tab-close exclusivity fix and the last reachable tails

### Selection and bounded briefs

Planning baseline: 53 ledgers; open rows 747 (604 GAP + 143 PARTIAL); strict
debt 286. HEAD `85a806f9` — wave 179–187 landed in full (181 closed A122 plus
the gesturevelocity/gesturecommands rows at `3c325bf1`/`85a806f9`; corearrows
A007 did not land and is re-planned as 190). Working tree is clean except the
user's untracked docs/profiler items.

The wave is one mandatory crash fix plus five surface tasks, each verified
against the live tree and each ledger's pinned fork revision:

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 188 | [Closing a tab must not teardown inside the `tabs` mutation](task-188-brief.md) | hostintegration A119 (1 PARTIAL) + SIGABRT fix | A |
| 189 | [The scale bar's Fold/Highlight state is per-tab and survives every toggle path](task-189-brief.md) | tabs_scale A021/A023 (2 GAP) + A027/A033/A050/A054 (4 PARTIAL) | A |
| 190 | [An incidental band or chrome press preserves an eligible note selection](task-190-brief.md) | corearrows A007 (1 GAP; 186 re-plan) | A |
| 191 | [Selection and byte invariance across the mounted tab lifecycle](task-191-brief.md) | windowtier_lifetime A054, windowtier_keyboard A103 (2 PARTIAL); tabs_transport A050 (1 PARTIAL) | A |
| 192 | [The automation drawer's second leave clears hover completely; point equality covers Tempo/CC](task-192-brief.md) | automationgesturecheck hover A030, contract A001 (2 PARTIAL); parity A001/A002 ride-along only if discharged | A |
| 193 | [A rejected track remap is a total no-op; view-only mutations touch no sidecar bytes](task-193-brief.md) | state A164/A171 + A173–A181 (11 GAP) | A |

### What was excluded and why — census evidence

- **188's root cause** is given by the controller: `closeTab`'s
  `tabs.remove(at:)` removes the QML row while the model's storage access is
  active; the delegate's synchronous destruction runs
  `pageReleased`→`retire`→`teardown`→`VelocityPage.detach`, and restoring the
  velocity-selection clear (A119's missing conjunct) publishes through
  `PianoGrid.publishOutputs` → `selectedWorkspace` → `tabs` — a reentrant read
  under `modify`. The fix finishes the row mutation before any teardown; no
  deferral.
- **project/proof.identity (19 PARTIAL)** and **voicegroupbank's label-guard
  conjuncts (A003/A015/A017/A022/A044)**: executing predicates already exist
  in `ProjectIdentityChecks.swift` (A001–A019 by message anchor); closing them
  is a standalone reconciliation, which §19/§21 forbid — they ride only
  inside a future identity-surface change. midiexport's 13 PARTIALs are the
  same QTest-guard/scratch-fixture tails, additionally parked with P3.
- **mainwindowrouting remainder**: input 20G/17P, lifecycle 20G/35P, native
  28G/1P, state beyond 193's rows — fixture guards, `swift-project-store`
  sidecar/view-state families, native window close, QAction/focusWidget
  identity, WindowDeactivate routes (no mounted ingress). Unchanged.
- **Closed but parked**: swiftqtml 78 GAP (retired native BridgeProbe lane —
  prototype-fixture observation rows, §13 audit deferred), onboardcheck 33
  (import wizard surface), samplecheck ~390 (P4), nativegraphics 27 +
  retained 18 (native boundaries), project ioflow/iomutations/workspace
  protocol deferrals, themelayout settings (owner decision), voicegroupsave
  presentation A032–A037 (VG03 create flow), voicegroupsave savecore +
  voicegroupbank A087–A093 (pending user decision), voicegroupsourceediting
  A086–A092 (retired creation flow), session A024/A042 (sidecar, no owner),
  tabs_transport A062 (physical audio), selftest_* physical-output conjuncts,
  visual baselines, swiftrollgated A017/A023 (ED11 clipboard text ownership),
  hostintegration A162/A174–A185 (real window-close harness), hostadapter
  A079 (centring decision) and A095 (same-GUI-pass residue),
  automationhover source-token rows, physical DPR-2 pixels in the drawer
  lane (presentation A037), task 164 (QtBridge object passing).

### Conflict matrix and dispatch groups

Write sets are pairwise disjoint (each brief lists its exact set). Two tasks
share the workspace check directory over disjoint files (189:
`session_editor_semantics.swift` + `tst_ShellTransportSession.qml`; 191:
`session_edit_routing.swift` + `tst_ShellTabsDrawer.qml` +
`tst_ShellWindowParameterKeys.qml` + `tst_ShellTransportVolume.qml`; 193:
`session_view_state_fanout.swift`). Ledgers are per-task disjoint — no two
tasks write the same ledger, so the single ledger writer applies each set
serially without row-level arbitration. 188 owns `VelocityPage.swift`,
`SongTabsController.swift`/`+Close.swift`, `tst_ShellTabsClose.qml` and the
hostintegration ledger; 190 owns `tst_ShellGridInputEditing.qml` and
corearrows; 192 owns `tst_EditorDrawerAutomationHover.qml`, the automation
domain checks and the three automationgesturecheck ledgers.

| Group | Tasks | Note |
|---|---|---|
| A | 188, 189, 190, 191, 192, 193 | Independent writers; 188 dispatches first (it is the lane-red crash fix and sits under 181's review fallout). Ledger rows serialized through the ledger writer. |

### Shared constraints and verification ownership

The §16–§22 contracts continue: fork clauses win; one predicate per clause
with its unique complete literal; each A-id on exactly one predicate;
independent literal expectations; fail-closed staging; real production
ingress and real input; no Qt.callLater, no focus memory, no test-only
ingress/API, no idempotence guards; opaque pre-stimulus snapshots allowed
(188's document bytes, 193's directory snapshot); WCAG AA beats parity;
queued QtBridge notifications keep same-GUI-pass clauses PARTIAL. Ledger rows
are edited only in the commit whose code and checks prove them; closed rows
use the compact form. Writers run their brief's focused lanes under the
lock/175-second alarm; no project-wide builds, tests, formatters or linters
mid-flight; the controller owns the project-wide gate once after sources
settle. Planning validation for this docs-only commit checked brief
links/headings, pinned fork citations, row statuses (`proof sites` per area:
hostintegration A119 PARTIAL; tabs_scale A021/A023 GAP + 4 PARTIAL;
corearrows A007 GAP; windowtier A054/A103 PARTIAL; tabs_transport A050
PARTIAL; automationgesturecheck A030/A001 PARTIAL; state A164–A181 GAP), lane
registrations (`shell-tabs-*`, `shellwindow-velocity`,
`shell-transport-session`, `shell-grid-input-editing`, `shell-tabs-drawer`,
`shellwindow-parameter-keys`, `shell-transport-volume`, `editorqml-drawer`,
`swiftcore`), and pairwise write-set disjointness; no application suite was
run.

### Deferred and excluded

- Unlock paths: the user's QtBridge object passing (164), `swift-project-store`
  (sidecar/view-state families), the theme-dialog and A079 centring decisions,
  a real window-close harness (hostintegration A162/A174–A185), the
  catalog-outage savecore rows, the hostadapter A095 same-GUI-pass residue,
  and the identity/midiexport guard-tail reconciliation gate.
- Strict-mapping debt (286) untouched by design.
- Standing exclusions unchanged: savecore A016–A026, pending-reload input
  gate, P3 WAV, P4 sample studio, transport A009/A010/A013, physical audio,
  ImageIO, ED11 clipboard text ownership, New Voicegroup creation surfaces,
  visual baselines, WindowDeactivate ingress, physical DPR-2 pixels.

## 24. Wave 194–199 — representation retirements and the mounted residuals

### Selection and bounded briefs

Planning baseline: 47 ledgers; open rows 1034 (855 GAP + 179 PARTIAL); strict
debt 235; `proof check` 0 errors. HEAD `b97c1c01` — wave 188–193 landed in
full and its six closed ledgers (corearrows, tabs_scale, windowtier_lifetime,
windowtier_keyboard, automationgesturecheck hover/contract) are deleted.
Working tree is clean except the user's untracked docs/profiler items
(`docs/plans/swift-clipboard-cutover/`, `swift-keybindings-integration/`,
`.omp/rules/swift-typecheck-complexity.md`, `profiler/`).

The surviving open inventory is dominated by families that stay excluded:
samplecheck 408 (P4), swiftqtml 78 (retired prototype fixture), visual 46
(frozen baselines), onboardcheck 45 (import wizard), themelayout 36
(theme-dialog/header-rule owner decisions), nativegraphics 27 + retained 18
(native boundaries), mainwindowrouting native 29 (Cocoa/QAction/focusWidget),
project ioflow/iomutations/workspace ~140 (`swift-project-store` and
backend-protocol representation), voicegroup bank/savecore guard tails
(pending user decision), identity/midiexport guard reconciliation, savecore
A016–A026, session A024/A042 sidecars, tabs_transport A062 physical audio,
selftest physical-output conjuncts, hostintegration A162/A174–A185 real
window close, hostadapter A079/A095 decisions/residue, task 164's
presentation A018–A024 conjuncts (QtBridge object passing), swiftrollgated
A017/A023 (ED11 text ownership), input/lifecycle/state PARTIALs that name
user-ruled deviations or parked sidecar guards.

What remains reachable is exactly the class the prompt asks about: ledgers
whose open rows are all blocked or representation-only, closable by a
surface task that proves refusal, plus mounted-shell residual conjuncts
whose executed predicates already exist but lack the message-anchored proof
each fork clause requires. The wave is six surface tasks:

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 194 | [The automation drawer's hint and gesture invariants retire their native-token tails](task-194-brief.md) | automation/hover A108/A121/A123/A126/A133/A143 (6 PARTIAL → RETIRED-REPRESENTATION or MATCHED); automationgesturecheck parity A001/A002 (2 PARTIAL); ledgers deleted on zero | A |
| 195 | [The mounted host surfaces close the fixture, grabber and null-timeline tails](task-195-brief.md) | hostintegration A003/A004/A007 (fixture representation) + A087/A091 (mouseGrabberItem identity); hostadapter A137 (non-optional timeline build); all 6 PARTIAL | A |
| 196 | [The voicegroup coordinator and the retired creation flow close their ledgers](task-196-brief.md) | voicegroupviewcache A046/A069 (2 PARTIAL); voicegroupsourceediting A086–A092 (7 GAP → RETIRED-REPRESENTATION); both ledgers deleted on zero | A |
| 197 | [The ruler Insert Time route and the velocity-toggle focus pin their residuals](task-197-brief.md) | mainwindowrouting input A154–A165 (12 PARTIAL) + A036/A037 (2 PARTIAL); A152 if its snap observation proves mounted | A |
| 198 | [The track-header menu, rename and status-hint footer pin every residual conjunct](task-198-brief.md) | mainwindowrouting state A188/A204/A208/A217/A224/A227/A250/A253/A255/A258/A260 (11 PARTIAL) + A262–A267 (6 GAP) | A |
| 199 | [Tab readiness and reload staging close as retired signal-count representation](task-199-brief.md) | mainwindowrouting lifecycle A033/A034/A041/A046/A047/A051–A054/A064/A068/A071 (11 PARTIAL → MATCHED or RETIRED-REPRESENTATION) | A |

### What was excluded and why — census evidence

- **Ledger closure criteria**: 194's hover ledger reaches zero open rows if
  all six source-token PARTIALs retire (§23 already names them "a native
  pointer-token identity that has no observable Swift surface"); each brief
  carries the refusal-predicate path and, where a clause is observable,
  MATCHED. 196's two ledgers reach zero for the same reason; their C++
  sources are uncompiled in every target, so the ledgers and sources delete
  in the task's commit. 194 likewise deletes `tst_automationhover.cpp` and
  `parity.cpp` (both uncompiled) with their ledgers. hostintegration keeps
  its excluded GAPs (A162/A174–A185), so its ledger stays; the input and
  lifecycle ledgers keep their `swift-project-store`/fixture-guard and
  ruled-deviation rows.
- **Parked clusters (unchanged from §23)**: project identity 19P and
  voicegroupbank label-guard tails A001/A003/A014/A015/A017/A022/A044/
  A048–A050 — reconciliation over already-executing predicates, riding only
  in a future bank/identity surface change; midiexport 13P same class plus
  P3; voicegroupbank A087–A093 savecore decision; voicegroupsave
  presentation A032–A037 + savecore A016–A025/A026 GAPs (VG03 create flow,
  catalog-outage decision); workspace session A024/A042, tabs_transport
  A062, selftest physical-output conjuncts; automation presentation A037
  (DPR-2 pixels); rollcheck identity A014, presentation A018–A024 (164),
  resize A002–A004/A020/A027/A028 (cursor-bitmap representation), selection
  A009, scale_editing A017/A027/A030 (QFAIL undo-count representation) —
  representation tails that §19/§21/§23 forbid closing outside a real
  surface change; hostseams has zero open rows and its ledger is a cleanup
  candidate for the controller, not a wave task.
- **Ruled deviations stay PARTIAL** per the transport A009/A010/A013
  precedent: input A015 (deliberate text-chrome focus retention), A017/A019
  (cursor commits never seek), lifecycle A025/A033/A034 focus-retention
  conjuncts that name the deviation, themelayout_color A038/A039 (unshipped
  branch/sample-editor roles), hostadapter A079/A095.
- **194's parity rows**: A001/A002 are helper guards (`isOneEdit`,
  `isUnchanged`) whose per-gesture predicates exist but are unlabelled; the
  brief adds the executed, message-anchored law predicates on the mounted
  gesture lanes rather than re-citing neighbours.
- **198's GAPs**: A263–A267 are native status-bar geometry clauses whose
  mounted equivalent is the ShellWindow hint footer (S237–S239 partial
  coverage); the task pins caption identity, meter x-offset, bar height and
  centred-elision invariants on that footer, or retires each clause as
  representation when no footer counterpart exists. A262 (hint-source
  identity) follows 194's source-token retirement ruling.
- Unchanged unlock paths: task 164 (QtBridge QML→Swift object passing),
  `swift-project-store`, theme-dialog/A079 centring, real window-close
  harness, catalog-outage savecore rows, savecore A016–A026, pending-reload
  input gate, P3 WAV, P4 sample studio, WindowDeactivate ingress, physical
  DPR-2 pixels, physical audio readback.

### Conflict matrix and dispatch groups

Write sets are pairwise disjoint (each brief lists its exact set). All six
tasks write distinct ledger files and distinct check sources; the single
ledger writer applies each set serially without row-level arbitration. The
three `Shell*Support.qml` shared files stay out of every write set — a task
that truly needs one messages the controller first.

| Task | Ledger files | Check/predicate files |
|---|---|---|
| 194 | `automation/hover/proof.tst_automationhover.txt`, `automationgesturecheck/proof.parity.txt` | `editorqml/tst_EditorDrawerAutomationHover.qml`, `automation/domain/tst_automationdomain.swift`, `automation/AutomationPageChecks.swift`; deletes `automation/hover/tst_automationhover.cpp`, `automationgesturecheck/parity.cpp` |
| 195 | `host/proof.tst_hostintegration.txt`, `host/proof.tst_hostadapter.txt` | `host/HostBehaviorChecks.swift`, `editorqml/tst_ShellWindowVelocity.qml`, `rollcheck/ruler_loop_menu.swift` |
| 196 | `voicegroup/proof.tst_voicegroupviewcache.txt`, `voicegroup/proof.voicegroupsourceediting.txt` | `workspace/bank_undo_publication.swift`, `workspace/bank_history_probes.swift`, `voicelist/VoiceListChecks.swift`; deletes `voicegroup/tst_voicegroupviewcache.cpp`, `voicegroup/voicegroupsourceediting.cpp` |
| 197 | `mainwindowrouting/proof.tst_mainwindowrouting_input.txt` | `workspace/session_edit_routing.swift`, `editorqml/tst_ShellWindowFocus.qml`, `editorqml/tst_ShellWindowPrompts.qml`, `editorqml/tst_ShellWindowTimeEditing.qml` |
| 198 | `mainwindowrouting/proof.tst_mainwindowrouting_state.txt` | `editorqml/tst_ShellWindowHints.qml`, `trackheaders/trackheaderinput.swift` |
| 199 | `mainwindowrouting/proof.tst_mainwindowrouting_lifecycle.txt` | `workspace/session_view_state.swift`, `editorqml/tst_ShellTabsReload.qml` |

| Group | Tasks | Note |
|---|---|---|
| A | 194, 195, 196, 197, 198, 199 | Independent writers. Ledger rows serialized through the single ledger writer; ledgers are per-task disjoint. |

### Shared constraints and verification ownership

The §16–§23 contracts continue: fork clauses win; **one predicate per fork
clause** — a fork require/QVERIFY with conjuncts, even inside a loop over
surfaces/routes, is ONE predicate executed per iteration; never split one
clause across several predicates and never fold a clause into another row's
predicate; each A-id on exactly one predicate; **expectations independent of
production projections** (independent literals, not read-back computed
state); **a fork state unreachable in Swift closes as
RETIRED-REPRESENTATION with executed refusal predicates** (the ruled
precedent: track beyond used tracks, time-signature under Insert Time, null
voicegroup); **no test-only APIs or ingress** — production entry points
only; fail-closed staging; no Qt.callLater, no focus memory, no second
dispatcher, no idempotence guards; opaque pre-stimulus snapshots allowed;
WCAG AA beats parity; queued QtBridge notifications keep same-GUI-pass
clauses PARTIAL. Ledger rows are edited only in the commit whose code and
checks prove them; closed rows use the compact form. Writers run their
brief's focused lanes under the lock/175-second alarm; no project-wide
builds, tests, formatters or linters mid-flight; the controller owns the
project-wide gate once after sources settle. Planning validation for this
docs-only commit checked brief links/headings, pinned fork citations, row
statuses (`proof sites` per area: hover 6P, parity 2P, hostintegration 5P/7G,
hostadapter 2P/1G, viewcache 2P, sourceediting 7G, input 17P/20G, state
11P/12G, lifecycle 35P/20G), lane registrations (`editorqml-drawer`,
`shellwindow-velocity`, `shellwindow-hints`, `shellwindow-focus`,
`shellwindow-prompts`, `shellwindow-time-editing`, `shell-tabs-reload`,
`swiftcore`, `swiftcore-projectsession`, `swiftcore-bankhistory`), and
pairwise write-set disjointness; no application suite was run.

### Deferred and excluded

- Unlock paths: the user's QtBridge object passing (164 + rollcheck
  presentation A018–A024), `swift-project-store` (sidecar/view-state
  families), theme-dialog and hostadapter A079 centring, real window-close
  harness (hostintegration A162/A174–A185), catalog-outage savecore rows,
  hostadapter A095 same-GUI-pass residue, the identity/midiexport/
  voicegroupbank guard-tail reconciliation gate.
- Strict-mapping debt (235) untouched by design.
- Standing exclusions unchanged: savecore A016–A026, pending-reload input
  gate, P3 WAV, P4 sample studio, transport A009/A010/A013, physical audio,
  ImageIO, ED11 clipboard text ownership, New Voicegroup creation surfaces
  (the §23 VG03 presentation A032–A037 rows stay; only the retired
  source-editing flow in voicegroupsourceediting is closed by 196), visual
  baselines, WindowDeactivate ingress, physical DPR-2 pixels, ruled-deviation
  conjuncts (input A015/A017/A019, selftest transport A009–A013).

## 25. Wave 200–205 — the bridge-probe remount, wording parity and the retired-flow tails

### Selection and bounded briefs

Planning baseline: 46 ledgers; `proof check` 0 errors; strict-mapping debt
235. HEAD `432eaaa1` — wave 194–199 landed in full, and its two closed
ledgers (automationgesturecheck parity, hostseams is likewise clean) deleted
their C++ sources. Working tree is clean except the user's untracked
`docs/plans/swift-clipboard-cutover/`, `swift-keybindings-integration/`,
`.omp/rules/swift-typecheck-complexity.md` and `profiler/`.

Re-examining the parked/blocked clusters with fresh eyes:

- **midi/midiexport 13 PARTIAL** (`proof.tst_midiexport.txt`): every residual
  is a QTest-fixture guard tail — staged-root directory check (A001), song
  label guard (A002), `fixture` open value + `qPrintable(error)` error-string
  propagation (A003/A005/A024/A032), `QTemporaryDir` scratch validity
  (A006/A025/A033), `readFile` predicates (A009/A027/A029) and empty-error
  (A035). `KeybindingRegistry.swift:113` registers `file.export_wav` but no
  production handler or export surface exists in the Swift shell, so there is
  no user-visible surface change that can carry these rows. **Stay parked**
  with the P3 WAV bundle.
- **project/identity 19 PARTIAL** (`project/proof.identity.txt`): the
  residuals are `SongName::create`/`VoicegroupId::create` value-law
  conjuncts (empty-label rejection, equality/inequality, `qHash`,
  `sectionLabel`, `sourceRelativePath`) whose "unproved" note is uniformly
  "the value type has no Swift ingress". No user-visible label-construction
  surface is named; closing is a reconciliation over already-executing
  service predicates, which §19/§21 forbid outside a real surface change.
  **Stay parked** for the identity surface.
- **rollcheck 18 PARTIAL** is closable: 11 of the 15 non-164 rows are pure
  native representation (resize cursor pixmaps A002–A004/A020/A027/A028 —
  Swift publishes a named cursor shape, never a `Qt::BitmapCursor` pixmap;
  identity A014 — the QFAIL names Qt's ViewState capture/apply pair; the
  scale_editing QFAILs A017/A027/A030 count Qt undo-stack commands, a
  representation Swift's `undoDocument` guard has no counterpart of).
  `selection` A009 (band-sweep audition duration not exposed by `onAudition`)
  adjudicates per clause. Presentation A018–A024 stay blocked on 164's
  QtBridge object passing. Task 201.
- **voicegroupbank 15 PARTIAL** splits: label-guard tails A001/A003/A014/
  A015/A017/A022/A044/A048–A050 share identity's "no Swift ingress" ruling —
  parked; the savecore write-failure family A089–A093 stays parked on the
  standing savecore decision. No surface task in this wave.
- **mainwindowrouting remainders**: input A091/A150 (`m_insertTimeAction`
  QAction identity, ruler-input bounds containment) and A152
  (grid/time-signature/camera observation) are reachable on the mounted
  ruler-menu lanes — task 204. Native A069's named-lookup conjunct
  adjudicates on `tst_ShellTabs.qml` — task 204. State A094–A099
  (`editActionsStartUnboundWithNoWorkspace`, `m_editActions` QAction-set
  identity) adjudicate on the mounted no-tab shell — task 200, which already
  owns the state ledger for its anchor edits. Input A015/A017/A019 ruled
  deviations, the input fixture-seed GAPs (A088–A090/A120/A123–A125/
  A146/A147/A166/A169–A174/A191), lifecycle's sidecar/`swift-project-store`
  tails and native's Cocoa/QAction/signal-count GAPs stay parked.
- **swiftqtml 78 GAP**: the §17 flag demanded a consumer audit before
  retirement. The audit: `BridgeProbe.qml` imports `SwiftQtMlCheck 1.0`, a
  module that no longer registers (the C++ lane deleted at `67544720`;
  `sqpRegisterProbeTypes` is dead code), and `tst_SwiftRoll.qml` never mounts
  it — only `BridgeProbeLifetimeChecks` run, from `cleanupTestCase`. The
  surface these rows map to is the QtBridge QML↔Swift contract itself:
  presenter property binding, `QListModel` row mutation/replacement/reset
  delegate-identity, returned/selected object lifetime, and the null
  selection. Task 202 remounts `BridgeProbe` inside the rollqml lane —
  registering `BridgeProbe` in `runSuite` and driving the fixture with real
  QML — proving the bridge law per clause (MATCHED) or closing the
  prototype-only conjuncts as RETIRED-REPRESENTATION with executed refusal
  predicates on the mounted probe. `actViaRow` object-argument invocations
  stay out of the lane (the pinned QtBridge cannot pass objects into slots;
  the harness calls the same contract through `actViaSelectedRow`, as the
  fixture already does).
- **swiftrollgated** A017: the only open row, ED11 clipboard text ownership —
  standing exclusion unchanged. Not in the wave.
- **workspace**: selftest_timeline A020 (`previewWhileStoppedDoesNotStartTransport`
  already-stopped Stop before the stopped audition) is reachable on the
  mounted transport lane — task 203; its Null-backend physical-output
  residuals (A006/A009/A011/A014) and selftest_transport's (A005/A007/A011/
  A015) stay PARTIAL per the standing rule, and A009/A010/A013 stay
  ruled-deviation PARTIAL. `tabs_transport` A062 ("NativeAudio
  `updateSettings(config:)` publication of the song volume") is reachable on
  the mounted `shell-transport-volume` lane — the task adds a small
  production `songVolume` publication on `NativeAudio` if the applied setting
  is not already observable. `session` A024/A042 keep the `swift-project-store`
  sidecar exclusion.
- **hostintegration/hostadapter**: A004's `session->active` two-note context
  is observable on a mounted two-tab shell — task 203 pins it from
  `HostBehaviorChecks.swift` (the file 195 already wrote). A087/A091 stay
  PARTIAL (WindowDeactivate has no mounted ingress — a real runtime event we
  cannot synthesize). Hostadapter A079 (centring decision), A095
  (same-GUI-pass queued-notification residue) and its NATIVE-SETUP row stay
  parked. Hostintegration A162/A174–A185 stay parked on the real
  window-close harness.
- **viewcache/sourceediting (196 residue)**: 196 landed `S038` but left
  viewcache A046's pending-origin conjunct, A069's coordinator-gate conjuncts
  and all seven voicegroupsourceediting GAPs (A086–A092, the retired
  createVoicegroup/appendIncludeLine flow that spec.md:63 lists as dead
  surface). Task 205 finishes the retirement the §24 brief described.
- **MouseHints wording residual (state A250 note)**: the fork's `fragment()`
  renders `label + separator + ' ' + action` — "⇧ Right-drag", "⌘ Wheel" —
  while `MouseHints.swift` concatenates the glyph directly ("⇧Right-drag").
  The fork wording is the intended UI text (§54's house-style comment calls
  the leading space deliberate); task 200 restores it across the three lanes
  that pin the literals and refreshes the A250 mapping note.

The wave is six tasks, each on a mounted surface or an already-executing
check surface:

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 200 | [Mouse hints render the fork's modifier-fragment spacing and the unloaded edit actions stay bound](task-200-brief.md) | state A094–A099 (6 GAP) + the A250 wording residual (anchor/note refresh only) | A |
| 201 | [The mounted roll retires the cursor-bitmap, view-state and undo-count representations](task-201-brief.md) | rollcheck identity A014, resize A002–A004/A020/A027/A028, scale_editing A017/A027/A030, selection A009 (11 PARTIAL → RR or MATCHED); identity/resize/scale_editing ledgers delete on zero | A |
| 202 | [The bridge probe remounts inside the roll lane and audits the QtBridge contract](task-202-brief.md) | swiftqtml A004–A097 (78 GAP → MATCHED or RR per clause); ledger deletes on zero | A |
| 203 | [The mounted session and transport lanes pin the already-stopped Stop, song-volume and active-tab residuals](task-203-brief.md) | selftest_timeline A020, tabs_transport A062 (2 PARTIAL… A062 GAP), hostintegration A004 (1 PARTIAL) | A |
| 204 | [The mounted ruler menu and tab strip adjudicate the action-identity and named-lookup tails](task-204-brief.md) | input A091/A150/A152 (3 GAP), native A069 (1 PARTIAL → MATCHED or RR) | A |
| 205 | [The voicegroup coordinator and the retired creation flow close their ledgers](task-205-brief.md) | viewcache A046 residual conjunct + A069 (2 PARTIAL), voicegroupsourceediting A086–A092 (7 GAP → RR); sourceediting ledger deletes on zero | A |

### What was excluded and why — census evidence

- **200 owns the state ledger alone** this wave: its literal refresh must
  rewrite the two `Anchor: message` lines in `proof.tst_mainwindowrouting_
  state.txt` that pin `tst_ShellWindowHints.qml`, and the A094–A099
  adjudication rides the same ledger; no other task may touch that file.
- **201's ledger deletions**: `rollcheck/identity.cpp`, `resize.cpp` and
  `scale_editing.cpp` are already deleted sources (headers carry `Deleted
  in:` `67544720`); once their open rows close, the ledger files delete in
  the task's commit. `selection` keeps no other open rows — A009 is its last
  PARTIAL — so its ledger deletes too if A009 closes; the brief carries both
  dispositions.
- **202 is the §17 "consumer audit" made a task**: the prototype fixture is
  dead and its presenter is still live Swift production code of the rollqml
  lane, so the correct move is a surface task proving the replacement (the
  mounted probe inside `roll_qml_tests`), not a blanket retirement. Clauses
  that are prototype-harness artefacts (delegate serial counters, probe
  diagnostics helpers) close RR with executed refusal predicates on the
  mounted bridge guards; bridge-law clauses close MATCHED.
- **203's A062**: the mounted `shell-transport-volume` lane already types a
  master-volume edit through `setMasterVolume` → `updateSettings(config:)`;
  the task adds an observable applied-song-volume publication on
  `NativeAudio` only if no existing surface reads the applied setting, and
  pins it with an independent literal.
- **204's fixture rows stay open**: input A088–A090/A120/A123–A125/
  A146/A147/A166/A169–A174/A191 are fixture-open/seed guards with no
  SessionChecks counterpart — reconciliation-only, parked per §19/§21.
- **Parked, unchanged**: midiexport 13P (no export surface; P3), project
  identity 19P + voicegroupbank label-guard + A089–A093 savecore tails (no
  value-type ingress surface; savecore decision), lifecycle sidecar/store
  tails and session A024/A042 (`swift-project-store`), rollcheck presentation
  A018–A024 (164/QtBridge object passing), swiftrollgated A017 (ED11),
  selftest physical-output conjuncts and ruled deviations (transport
  A009/A010/A013, input A015/A017/A019), voicegroupsave presentation
  A032–A037 + savecore GAPs (VG03 create flow, catalog outage), onboardcheck
  import wizard, samplecheck (P4), nativegraphics + retained + mainwindow-
  routing native 28G (native boundaries/Cocoa/QAction/signal counts),
  visual 46 (frozen baselines), themelayout 36 (owner decisions), hostadapter
  A079/A095/NATIVE-SETUP, hostintegration A087/A091 (WindowDeactivate
  ingress) + A162/A174–A185 (window-close harness), automation presentation
  A037 (physical DPR-2), automation hover A133 (in flight separately).

### Conflict matrix and dispatch groups

Write sets are pairwise disjoint (each brief lists its exact set). Six tasks,
five independent writers; ledgers are per-task disjoint so the single ledger
writer applies each set serially without row-level arbitration. `tst_ShellTabs.qml`
is written only by 204; `tst_ShellWindowHints.qml`, `tst_ShellTabsMouseHints.qml`
and `tst_ShellDrawerParityAutomation.qml` only by 200. `RollQmlTests.swift`
and `BridgeProbe.qml`/`BridgeProbeCheck.swift` are 202's alone. No task
touches a `Shell*Support.qml` shared file.

| Task | Ledger files | Check/predicate files |
|---|---|---|
| 200 | `mainwindowrouting/proof.tst_mainwindowrouting_state.txt` | `src/swift/app/MouseHints.swift`, `editorqml/tst_ShellWindowHints.qml`, `editorqml/tst_ShellTabsMouseHints.qml`, `editorqml/tst_ShellDrawerParityAutomation.qml`, `editorqml/tst_ShellWindowShortcuts.qml` |
| 201 | `rollcheck/proof.identity.txt`, `proof.resize.txt`, `proof.scale_editing.txt`, `proof.selection.txt` | `rollqml/tst_SwiftRollSelection.qml`, `editorqml/tst_ShellNoteVisuals.qml`, `rollcheck/scale_editing.swift`, `rollcheck/identity.swift` |
| 202 | `swiftqtml/proof.tst_swiftqtml.txt` | `rollqml/RollQmlTests.swift` (registration), `swiftqtml/BridgeProbe.qml` (module retarget), `rollqml/tst_SwiftRollBridge.qml` (new), `swiftqtml/BridgeProbeCheck.swift` (fixture slots only) |
| 203 | `workspace/proof.selftest_timeline.txt`, `workspace/proof.tabs_transport.txt`, `host/proof.tst_hostintegration.txt` | `editorqml/tst_ShellTransportSession.qml`, `editorqml/tst_ShellTransportVolume.qml`, `host/HostBehaviorChecks.swift`, `src/swift/app/NativeAudio.swift` (observability only if needed) |
| 204 | `mainwindowrouting/proof.tst_mainwindowrouting_input.txt`, `proof.tst_mainwindowrouting_native.txt` | `editorqml/tst_ShellWindowPrompts.qml`, `editorqml/tst_ShellGridMenuRulerLifecycle.qml`, `editorqml/tst_ShellTabs.qml` |
| 205 | `voicegroup/proof.tst_voicegroupviewcache.txt`, `voicegroup/proof.voicegroupsourceediting.txt` | `workspace/bank_history_probes.swift`, `workspace/bank_undo_publication.swift`, `voicelist/VoiceListChecks.swift` |

| Group | Tasks | Note |
|---|---|---|
| A | 200, 201, 202, 203, 204, 205 | Independent writers. Ledger rows serialized through the single ledger writer; ledgers are per-task disjoint. 200's QML literal edits are evidence-breaking for the lanes it touches; siblings must not cite the old literals. |

### Shared constraints and verification ownership

The §16–§24 contracts continue: fork clauses win; one predicate per fork
clause with its unique complete literal; each A-id on exactly one predicate;
a fork require/QVERIFY with conjuncts is ONE predicate per iteration even
inside a loop; expectations independent of production projections; a fork
state unreachable in Swift closes as RETIRED-REPRESENTATION with executed
refusal predicates; no test-only APIs or ingress — real production entry
points only; fail-closed staging; no Qt.callLater, no focus memory, no second
dispatcher, no idempotence guards; opaque pre-stimulus snapshots allowed;
WCAG AA beats parity; queued QtBridge notifications keep same-GUI-pass
clauses PARTIAL. Ledger rows are edited only in the commit whose code and
checks prove them; closed rows use the compact form. Writers run their
brief's focused lanes under the lock/175-second alarm; no project-wide
builds, tests, formatters or linters mid-flight; the controller owns the
project-wide gate once after sources settle. Planning validation for this
docs-only commit checked brief links/headings, pinned fork citations, row
statuses (`proof sites` per area: state 0P/6G, input 3P/20G, native 1P/28G,
rollcheck identity 1P/resize 6P/scale_editing 3P/selection 1P, swiftqtml
78G, selftest_timeline 5P, tabs_transport 1G, hostintegration 3P/7G,
viewcache 2P, sourceediting 7G), lane registrations (`shellwindow-hints`,
`shell-tabs-mouse-hints`, `shell-drawer-parity-automation`,
`shellwindow-shortcuts`, `shell-transport-session`,
`shell-transport-volume`, `shellwindow-prompts`,
`shell-grid-menu-ruler-lifecycle`, `shell-tabs-*`, `swiftroll-window`,
`swiftcore`, `swiftcore-projectsession`, `swiftcore-bankhistory`), and
pairwise write-set disjointness; no application suite was run.

### Deferred and excluded

- Unlock paths: the user's QtBridge object passing (164 + rollcheck
  presentation A018–A024), `swift-project-store` (sidecar/view-state
  families), theme-dialog and hostadapter A079 centring, a real window-close
  harness (hostintegration A162/A174–A185), catalog-outage savecore rows,
  the hostadapter A095 same-GUI-pass residue, the identity/midiexport/
  voicegroupbank guard-tail reconciliation gate, WindowDeactivate ingress
  (A087/A091), physical audio (selftest physical-output conjuncts,
  tabs_transport physical rows), and the P3/P4 features.
- Strict-mapping debt (235) untouched by design.
- Standing exclusions unchanged: savecore A016–A026, pending-reload input
  gate, transport A009/A010/A013, ImageIO, ED11 clipboard text ownership,
  New Voicegroup creation surfaces, visual baselines, physical DPR-2 pixels,
  ruled-deviation conjuncts (input A015/A017/A019, viewcache A046's
  bank-only-dirt close refusal, selftest transport A009–A013).

## 26. Wave 206–208 — the mounted coordinator gate, view-state and item-alternate residuals

### Selection and bounded briefs

Planning baseline: 42 ledgers; `proof check` 0 errors; strict-mapping debt
233; open rows 887 (762 GAP + 125 PARTIAL). HEAD `82ebde21` — wave 200–204
landed, 205 skipped (its VG03 retirement contradicts the wired creation
ingress; VoiceEditor.qml:320 → requestNewVoicegroup keeps
voicegroupsourceediting A086–A092 and viewcache A069's siblings GAP), and
the closed state/swiftqtml/rollcheck-selection/scale_editing/automationgesturecheck
ledgers deleted. Working tree carries the user's untracked
`docs/plans/swift-clipboard-cutover/`, `swift-keybindings-integration/`,
`.omp/rules/swift-typecheck-complexity.md` and `profiler/`.

New controller rulings applied to this census: directional resize cursor
art (rollcheck resize A002–A004/A027/A028) is a UX deviation pending the
user, not a retirement; a `!("prop" in obj)` refusal on a never-existing
property is tautological and banned — retirement predicates must
positively observe the real replacement surface; a production property
added only for a check is banned even when renderer precedent exists
(tabs_transport A062 stays GAP); a real runtime event the lanes cannot
synthesize (WindowDeactivate, foreign-app window) stays open.

Row-level census of every remaining open site (`proof sites --area <dir>`
for all 42 ledgers; per-ledger tallies under the table):

| Area / ledger | Open | Status |
|---|---|---|
| automation hover | 1P | A133 in flight separately |
| automation presentation | 1P | physical DPR-2 pixels |
| host adapter | 1G + 1P + 1NS | A079 parity decision pending user; A095 queued-notification residue |
| host integration | 7G + 3P | window-close harness (A162/A174–A185); WindowDeactivate ingress (A087/A091); A004 fixture-parity residue |
| host seams | 0 | closed; ledger file `proof.tst_hostseams.txt` still present — deletion owed with C++ sources already gone |
| mainwindowrouting input | 17G + 3P | fixture-seed guards parked; ruled deviations A015/A017/A019 |
| mainwindowrouting lifecycle | 20G + 23P | swift-project-store (sidecars, view-state, reopen); window-close A106–A108; pending-reload gate A025; representation residuals |
| mainwindowrouting native | 28G | Cocoa/QAction/signal-count/focus/native-delivery; A047/A048 keep the foreign-window ingress block (their "no byte surface" note is stale: `document.state.file.encoded()` exists, but the foreign-app window is unsynthesizable) |
| midi export | 13P | P3 WAV bundle; no export surface |
| nativegraphics | 27G | native windowing boundary |
| onboardcheck import | 33G + 12NS | MIDI-import wizard unported (P4) |
| project identity | 19P | no Swift value-type ingress |
| project ioflow | 25G + 8P + 2NS | swift-project-store command envelope |
| project iomutations | 21G + 10NS | swift-project-store fixture/teardown guards; ghost-ID ingress ban (workspace A099/A100) |
| project workspace | 58G + 11NS | swift-project-store session store |
| retained | 18G | native boundaries harness |
| rollcheck identity | 1P | A014 residual — task 208 |
| rollcheck presentation | 7P | QtBridge object passing (164/A018–A024) |
| rollcheck resize | 5P | directional cursors — user decision pending |
| samplecheck | 387G + 74N | P4 sample studio |
| swiftrollgated | 2G | ED11 clipboard text ownership |
| themelayout color | 2P | A038 — task 206; A039 sample editor (P4) |
| themelayout settings | 33G + 1P | theme dialog / QHeaderView (owner decisions, native); A019 — task 206 |
| visual | 37G + 7P | unported dialogs/pickers + frozen baselines |
| voicegroup bank | 15P | no value-type ingress + savecore write-failure family |
| voicegroup viewcache | 2P | A046 ruled deviation stays; A069 — task 207 |
| voicegroup sourceediting | 7G | VG03 open decision (creation ingress wired) |
| voicegroupsave presentation | 6G | VG03 create flow |
| voicegroupsave savecore | 11G | catalog-outage decision |
| workspace session | 2G | swift-project-store sidecars |
| workspace selftest timeline | 4P | Null-backend physical output |
| workspace selftest transport | 7P | Null-backend physical output + ruled deviations |
| workspace tabs_transport | 1G | A062 — banned test-only read |

Under the new rulings only three residuals can close honestly:

- **themelayout settings A019** (`tst_themelayout_settings.cpp:178` at
  `97dc7fea`): the parked note says GridPalette exposes no alternate
  surface — stale. `EventListCell.qml:72` renders odd rows in
  `page.tableAlternateBackground`, a real mounted surface already
  reachable on `tst_ShellEventListPresentation.qml`. One predicate
  observes the mounted second-row delegate's background color —
  MATCHED. The cell background Rectangle needs an id so the lane can
  read it (a production handle, not a test-only property: it names the
  existing rendered stripe).
- **themelayout color A038** (`tst_themelayout_color.cpp:205`): S020 is
  the fork's else branch (contrast-100 grid luminance above the default
  when the default sits above the roll surface) that no shipped preset
  reaches. The banned-tautology ruling does not apply: the enumeration
  over shipped themes IS the real replacement surface — an executed
  predicate asserting every shipped preset's default grid luminance sits
  at-or-below its roll surface positively observes real theme data.
  Closes RETIRED-REPRESENTATION with that executed refusal in
  `ThemeColorChecks.swift`.
- **viewcache A069** (`tst_voicegroupviewcache.cpp:320` at `a7fcaa3e`):
  `SongTabsController.pendingBankTabId` and `closeEnabled(tabId:)` are
  published production values (SongTabs.qml close gate reads them), so
  `cache.bankActionsEnabled() && !cache.pendingOrigin()` after the
  origin's own hard error IS observable: `pendingBankTabId == -1`,
  `closeEnabled(originID)` restored, and a follow-on `applyBankEdit`
  succeeds (the re-enabled bank actions). `bank_undo_publication.swift`
  already mounts `app.songTabs` through a two-tab fixture; extend it
  with the own-identity hard failure — MATCHED.
- **rollcheck identity A014** (`identity.cpp:223`): the residual claimed
  no predicate observes cosmetics retained together with runtime fields
  across the restore — stale. `identity.swift:205-215` (S021) asserts
  exactly that conjunct (`session.editorViewState == cosmetics` AND all
  runtime fields AND document state) on the mounted session, a real
  production read on the real replacement surface. Close MATCHED; the
  task re-verifies S021's executed evidence and refreshes the mapping —
  a mapping correction riding the same commit that already owns this
  ledger, not a standalone reconciliation.

Everything else in the open inventory is excluded: parked on
user/owner decisions (directional cursors, theme dialog, drawer-toggle
centring, catalog outage, pending-reload gate, VG03), swift-project-store,
QtBridge object passing, window-close harness, WindowDeactivate/
foreign-window ingress, native/Cocoa/QAction boundaries, physical
audio/DPR-2, ED11, frozen visual baselines, fixture-parity residues, the
P3 WAV bundle and the P4 wizard/sample-studio families, and the banned
test-only read (tabs_transport A062). The inventory is otherwise
excluded — three tasks, no padding:

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 206 | [The mounted event-list stripe and the shipped-theme enumeration close the themelayout residuals](task-206-brief.md) | settings A019 (1 PARTIAL → MATCHED), color A038 (1 PARTIAL → RR) | A |
| 207 | [The mounted tab coordinator proves the hard-error gate release](task-207-brief.md) | viewcache A069 (1 PARTIAL → MATCHED) | A |
| 208 | [The view-state round trip closes on its already-executing joint predicate](task-208-brief.md) | rollcheck identity A014 (1 PARTIAL → MATCHED); identity ledger deletes on zero | A |

### What was excluded and why — census evidence

- **207 keeps A046 PARTIAL**: the peer-immediate-close conjunct under
  bank-only dirt is a user-ruled deviation (Swift refuses close on
  bank-only dirt to protect unsaved edits); the standing ruled-deviation
  exclusion list carries it and this wave does not re-litigate.
- **208 is a mapping correction, not reconciliation**: S021 already
  discharges the joint clause; nothing else in the identity ledger is
  open, so the ledger file deletes in the same commit per the closed-
  ledger rule (identity.cpp's `Deleted in:` header stands).
- **No task touches an excluded family**: the VG03 rows stay GAP,
  tabs_transport A062 stays GAP (test-only read banned), resize
  directionals stay PARTIAL pending the user, and no predicate asserts
  `!("prop" in obj)` on a never-existing property anywhere — every
  closure above observes a mounted, existing surface.
- **`proof.tst_hostseams.txt` still ships** at zero open rows with its
  C++ source deleted; no task claims the deletion — it rides with the
  controller's housekeeping since nothing in the wave edits that file's
  row dispositions.

### User-visible Swift feature gaps needing a decision (for the controller)

- Directional left/right note-edge resize cursors: Swift publishes one
  named SizeHorCursor for both edges (rollcheck resize
  A002–A004/A027/A028, 5 PARTIAL).
- MIDI-import wizard surface unported (onboardcheck import, 33G + 12NS).
- Settings/theme/sample-editor/sf2-zone-picker dialogs and the sample
  picker browser unported (visual dialogs/browsers, themelayout
  settings theme-dialog family, color A039, host adapter A079's
  toggle-centring variant).
- WAV export: `file.export_wav` registers a keybinding
  (KeybindingRegistry.swift:113) with no production handler or surface
  (midiexport 13P).
- Song-label validation has no Swift ingress: Swift song labels are
  plain Strings, so `SongName::create` spelling validation
  (visual chrome A007, voicegroupbank label guards, project identity)
  has no mounted law; whether the Swift shell should adopt the
  validation or treat it as fork-representation is a user call.
- New Voicegroup creation (VG03): the ingress is wired
  (VoiceEditor.qml:320 → requestNewVoicegroup) but
  `onNewVoicegroupRequested` is unassigned — the create dialog/flow is a
  user-visible hole holding voicegroupsourceediting A086–A092,
  voicegroupsave presentation A032–A037 and viewcache A069's sibling
  rows open.
- Sample studio (P4): pitch/loop/DSP surfaces unported (samplecheck
  387G + 74N).

### Conflict matrix and dispatch groups

Write sets are pairwise disjoint; ledgers are per-task disjoint so the
single ledger writer applies each set serially.

| Task | Ledger files | Check/predicate files |
|---|---|---|
| 206 | `themelayout/proof.tst_themelayout_settings.txt`, `themelayout/proof.tst_themelayout_color.txt` | `src/ui/songview/quick/EventListCell.qml` (stripe id), `src/checks/editorqml/tst_ShellEventListPresentation.qml`, `src/checks/themecolor/ThemeColorChecks.swift` |
| 207 | `voicegroup/proof.tst_voicegroupviewcache.txt` | `src/checks/workspace/bank_undo_publication.swift` |
| 208 | `rollcheck/proof.identity.txt` (deletes on close) | mapping correction only; `src/checks/rollcheck/identity.swift` referenced, edits only if execution evidence is missing |

| Group | Tasks | Note |
|---|---|---|
| A | 206, 207, 208 | Independent writers. 206 owns both themelayout ledgers; no sibling touches `tst_ShellEventListPresentation.qml` or `ThemeColorChecks.swift`. |

### Shared constraints and verification ownership

The §16–§25 contracts continue: fork clauses win; one predicate per fork
clause with its unique complete literal; each A-id on exactly one
predicate; expectations independent of production projections; a fork
state unreachable in Swift closes as RETIRED-REPRESENTATION with
executed refusal predicates that positively observe the real replacement
surface — `!("prop" in obj)`-style refusals on never-existing properties
are banned; no test-only APIs or ingress — real production entry points
and real published values only (`pendingBankTabId`/`closeEnabled` are
published; the EventListCell stripe id names an existing rendered
surface); fail-closed staging; no Qt.callLater, no focus memory, no
second dispatcher; queued QtBridge notifications keep same-GUI-pass
clauses PARTIAL. Ledger rows are edited only in the commit whose code
and checks prove them; closed rows use the compact form. Writers run
their brief's focused lanes under the lock/175-second alarm; no
project-wide builds, tests, formatters or linters mid-flight; the
controller owns the project-wide gate once after sources settle.
Planning validation for this docs-only commit checked brief
links/headings, pinned fork citations, row statuses (`proof sites` per
area: themelayout settings 33G/1P + color 2P, viewcache 2P, rollcheck
identity 1P), lane registrations (`shell-event-list-presentation`,
`swiftcore`/`swiftcore-bankhistory` for the probe files), production
observability (`SongTabsController.swift:318-328`,
`EventListCell.qml:72`, `identity.swift:205-215`), and pairwise
write-set disjointness; no application suite was run.

### Deferred and excluded

- Unlock paths unchanged: the user's QtBridge object passing (164 +
  rollcheck presentation A018–A024), `swift-project-store` (sidecar/
  view-state/session families), theme-dialog and hostadapter A079
  centring, a real window-close harness (hostintegration A162/A174–A185),
  catalog-outage savecore rows, the hostadapter A095 same-GUI-pass
  residue, the identity/voicegroupbank guard-tail reconciliation gate,
  WindowDeactivate and foreign-window ingress (A087/A091, native
  A047/A048 context), physical audio (selftest conjuncts,
  tabs_transport physical rows), directional resize cursors, the
  wizard/sample-studio/import families, and the P3 WAV export surface.
- Strict-mapping debt (233) untouched by design.
- Standing exclusions unchanged: savecore A016–A026, pending-reload
  input gate, transport A009/A010/A013, ImageIO, ED11 clipboard text
  ownership, VG03 create-flow rows (voicegroupsourceediting A086–A092,
  voicegroupsave A032–A037), visual baselines, physical DPR-2 pixels,
  banned test-only reads (tabs_transport A062), ruled-deviation
  conjuncts (input A015/A017/A019, viewcache A046's bank-only-dirt close
  refusal, selftest transport A009–A013). VG03 create-flow rows promote
  to task 209 in §27.

## 27. Task 209 — the wired New Voicegroup creation flow (VG03)

### Selection and brief

Planning baseline unchanged from §26: 42 ledgers; open rows 887 (762 GAP
+ 125 PARTIAL). Wave 206–208 is in flight on independent write sets; this
task is user-dispatched and disjoint.

VoiceEditor.qml:320 already calls `requestNewVoicegroup`, but
`VoiceListController.onNewVoicegroupRequested` (`VoiceListController.
swift:148`) is assigned by nobody — the mounted "New..." button is a
user-visible dead end. This is the completion of what task 205 refused
to retire: the fork's whole create flow survives in the oracle — guarded
name/source dialog (`workspaceui_project.cpp:597-654`), fail-closed
project op writing `sound/voicegroups/<name>.inc` plus the hub include
(`projectio.cpp:389-406`, `voicegroupsource.cpp:1797-1932`), catalog
rebuild, and `_<name>` assigned as an undoable cfg edit that rebinds the
bank (`workspaceui_project.cpp:206-216`). Task 171's New Song layering
(0c9f378d) is the model: `ProjectService` op behind the store writer,
controller-owned prompt state, SongConfirmDialog-idiom QML, undoable
assignment through `session.selectVoicegroup`, collision refusal that
reads before it writes.

Every Swift piece except the file writer and the prompt exists:
`selectVoicegroup` is the undoable -G + rebind seam, `bankLease.
sourcePath`/`sectionLabel` carry the copy source, `RegistrationLines`
is byte-faithful hub editing, `voicegroupArgs()` rescans on call, and
`setVoicegroupChoices`/`refresh(from:)` republish the selector. The
missing hub (`sound/voice_groups.inc` absent) is a success no-op per
the fork; a missing `sound/voicegroups/` directory refuses at the
service — the per-file layout refusal maps there, not to a prompt probe.

Both spec ledgers carry only these rows as GAP, so both hit zero open
rows and delete in the proving commit (C++ sources already deleted).
The fork's second New-Voicegroup ingress (`CreateSongInput.newVoicegroup`
inside the New Song flow) has no open row pinning it and stays out.

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 209 | [The mounted New Voicegroup prompt creates a per-file group and assigns it undoably](task-209-brief.md) | sourceediting A086–A092 (7 GAP → MATCHED, ledger deletes), voicegroupsave presentation A032–A037 (6 GAP → MATCHED, ledger deletes) | B |

### Excluded and blocked — census evidence

- savecore A016–A026 (catalog outage) stays GAP — standing user decision.
- voicegroupbank (15P) and viewcache (A046 ruled deviation; A069 owned by
  task 207) untouched — different ledgers, different rows.
- The sourceediting GAP block is creation-only: A086–A092 close on the
  written file, the hub line, `voicegroup_load` fidelity, resolved-tone
  equality and `voicegroupArgs` membership — no test-only ingress.

### Conflict matrix

| Task | Ledger files | Check/predicate files | Production files |
|---|---|---|---|
| 209 | `voicegroup/proof.voicegroupsourceediting.txt`, `voicegroupsave/proof.presentation.txt` (both delete on zero) | `src/checks/workspace/voicegroup_creation.swift` (new), `SessionChecks.swift` (one call line), `src/checks/voicelist/voicelist_session.swift`, `src/checks/editorqml/tst_ShellVoicegroup.qml`, `src/checks/CMakeLists.txt` | `src/swift/project/VoicegroupSource+Create.swift` (new) + `src/swift/project/CMakeLists.txt`, `src/swift/app/ProjectService+Bank.swift`, `src/swift/app/voicelist/VoiceListController.swift`, `src/swift/app/ApplicationSession{,+Audio}.swift`, `src/ui/songview/quick/docks/VoicegroupNewDialog.qml` (new) + `VoicegroupPanel.qml` + `VoiceEditor.qml` (objectName), `src/ui/shell/ShellWindow.qml`, root `CMakeLists.txt` |

| Group | Tasks | Note |
|---|---|---|
| A | 206, 207, 208 | In flight; their write sets share no file or ledger with 209 (207's SessionChecks row is a bank_undo_publication extension — 209 appends one unrelated call line). |
| B | 209 | Independent writer; only conflict surface is `SessionChecks.swift`'s bankhistory call list, disjoint by line. |

### Shared constraints and verification ownership

The §16–§26 contracts continue; the §26 banned-pattern list applies
verbatim (no `!("prop" in obj)` refusals, no test-only reads, real
ingress only — `requestNewVoicegroup` + `selectVoicegroup`, no
Qt.callLater, fail-closed staging). Verify lanes:
`deno task verify --filter swiftcore-bankhistory --verbose`,
`deno task verify --filter swiftcore-projectsession --verbose`,
`deno task verify:shell --filter shell-voicegroup --verbose`, then
`deno task proof check --executed`. Planning validation for this
docs-only commit checked the wired ingress (VoiceEditor.qml:320 →
`VoiceListController.swift:148,388-390` with no assignee), the fork
clauses at the ledger pins (`voicegroupsourceediting.cpp:337-353` at
`fbe1015a`; `presentation.cpp:239-255` at `4346c26a`; `voicegroupsource.
cpp:1797-1932`, `projectio.cpp:389-406`, `workspaceui_project.cpp:
597-654,206-216` at `fbe1015a`), row statuses (`proof sites`:
sourceediting 7G = A086–A092 exactly, presentation 6G = A032–A037
exactly), lane registrations (`swiftcore-bankhistory`,
`swiftcore-projectsession`, `shell-voicegroup`), and write-set
disjointness against §26 tasks; no application suite was run.

## 28. Wave 210–212 — the feature-gap residue: song-label input laws, the dead Register action and the rename focus restore

### Selection and bounded briefs

Planning baseline unchanged from §26–§27 (wave 209 landed at `b986ba08`:
39 ledgers, 871 open rows, strict debt 215). This wave answers the two
feature-gap questions §26 parked for the controller — song-label
validation and dead ingress — and briefs every resulting honest surface
task. No ledger row is claimed: none of the three behaviors carries an
open assertion in a surviving ledger, so all three follow the task-171
pattern of a feature port proven by service/controller predicates and
mounted journeys, with no ledger edits.

### Feature-gap finding 1 — song-label validation

The suspected gap inverts. Swift's `isValidSongLabel`
(`ProjectService+Songs.swift:81-84`) refuses strictly more spellings than
the fork's accepted set, not fewer: `SongName::create` is an empty-only
gate (`projectidentity.cpp:8-13` at `fceecd88`; the mounted service guard
`projectio.cpp:366-368`), and the wizard's accepted set is *folded*
`^[a-z_][a-z0-9_]*$` — the `LowercaseNameValidator` folds typed capitals
and drops non-name characters per keystroke (`newsongwizard.cpp:78-88,
102-105`). Swift accepts nothing the fork refused, but refuses "Mus_X"
the fork folded to "mus_x", lets invalid characters sit in the field
until Create instead of dropping them live, and refuses a same-name
collision only after accept where the fork gates completion on it
(`isComplete` + red hint, `newsongwizard.cpp:134-149`). The fork has no
song-rename flow at all (only `beginRename` on track headers), so the
New Song prompt is the only song-label ingress — task-210 territory.

### Feature-gap finding 2 — dead-ingress audit

Every declared `on*` callback and `@QtSignal` in `src/swift` was checked
for a production assignee, every `KeybindingRegistry` id for a reachable
handler (`ShellPresenter.actions` → `activate`, the `command` path, or a
hold-chord consumer), and every QML menu/actionId for dispatch:

| Ingress | State | Disposition |
|---|---|---|
| `file.register_song` (`KeybindingRegistry.swift:111`) | Not in `ShellPresenter.actions` — dead keybinding; dock context menu carries the flow | **task-211** (fork File-menu ingress, `mainwindow.cpp:304-307`, gate `:966`) |
| `TrackHeadersPresenter.onRestoreRollFocus` (`TrackHeaders.swift:67,311`) | Unassigned in production — mounted `finishRename(commit, entered=true)` loses the fork's `focusContent` | **task-212** |
| `file.import_midi` (`:109`) | Registered, no action | Excluded: P4 import wizard |
| `file.export_wav` (`:113`) | Registered, no action | Excluded: P3 WAV export |
| `view.theme` (`:130`) | Registered, no action | Excluded: theme-dialog user decision |
| `tools.import_sample` (`:138`) | Registered, no action | Excluded: P4 sample studio |
| VoiceEditor "New Sample"/"Edit Sample" (`VoiceEditor.qml:163,172` → `onNewSampleRequested`/`onEditSampleRequested`) | Buttons fire into unassigned callbacks | Excluded: P4 sample studio |
| `roll.velocity_drag` (`:170`, holdChord) | Entry only labels the fixed Ctrl chord (`QtFact.controlModifier`); holdChord value unread | Dead registry metadata — no consumer |
| `VoiceListController.requestVoiceEdit`/`onVoiceEditRequested` (`:366-372`) | Dead method: never called; the real path is `VoiceEditorController` → `applyVoiceEdit` | Dead code — no task |
| `ApplicationSession.onEditorViewStatePersisted` (`ApplicationSession+Tabs.swift:352`) | Harness-only completion seam (fork `editorViewStatePersisted`, `mainwindow.cpp:943-951`) | No task — intended |
| All other `on*` callbacks / `@QtSignal`s | Assigned in `DocumentWorkspace`/`ApplicationSession+Audio` or connected in QML | Clean |
| SongsPanel/QuickMenuPanel/EditorSurfaceMenus/AutomationMenu/EventListMenu actionIds | All dispatch to mounted handlers | Clean |

### Tasks

| Task | Surface / brief | Rows | Group |
|---|---|---|---|
| 210 | [The New Song name field takes only the fork's accepted labels](task-210-brief.md) | none — feature port | A |
| 211 | [File → Register Song restores the dead registry action on the selected tab](task-211-brief.md) | none — feature port | A |
| 212 | [Rename commit/cancel restores roll focus through a real signal](task-212-brief.md) | none — feature port | A |

### Excluded and deferred — census evidence

- Project identity A001–A008 (`SongName::create` accept/reject/hash):
  already discharged by executing predicates in
  `src/checks/projectstore/ProjectIdentityChecks.swift` (A001–A008 named
  in the messages) — a stale-disposition reconciliation for the
  ledger-agent gate, not a surface task.
- visual chrome A007 stays GAP with its family (unported dialog
  baselines): it pins a `QVERIFY(name)` construction, not the wizard's
  input mechanics, and its ledger is otherwise parked.
- voicegroupbank label-guard PARTIALs and lifecycle A714/A715's
  `SongName::create` conjuncts: same value-type reconciliation gate;
  `SongName`/`VoicegroupId` exist in `ProjectIdentity.swift`.
- Standing exclusions unchanged: directional resize cursors, theme
  dialog/owner rows, drawer-toggle centring (host A079), catalog outage
  (savecore A016–A026), pending-reload input gate, P3 WAV export
  (`file.export_wav`), P4 sample studio/import wizard
  (`tools.import_sample`, `file.import_midi`, the two VoiceEditor sample
  buttons), Task 164 QtBridge object passing.

### Conflict matrix and dispatch groups

Write sets are pairwise disjoint; no ledger file is touched by any task.

| Task | Production files | Check files |
|---|---|---|
| 210 | `src/swift/app/songlist/SongListPresenter.swift`, `src/swift/app/ProjectService+Songs.swift` (normalize the accepted label), `src/ui/songview/quick/docks/SongConfirmDialog.qml` | `src/checks/songlist/songlist_checks.swift`, `src/checks/editorqml/tst_ShellSongs.qml` |
| 211 | `src/swift/app/shell/ShellPresenter.swift`, `src/swift/app/songlist/SongDockController.swift` | `src/checks/workspace/session_io.swift`, `src/checks/editorqml/tst_ShellMenus.qml` |
| 212 | `src/swift/app/headers/TrackHeaders.swift`, `src/ui/songview/quick/swiftroll/EditorSurface.qml` | `src/checks/trackheaders/trackheadermutations.swift`, `src/checks/rollqml/tst_SwiftRollTrackHeaderInput.qml` |

| Group | Tasks | Note |
|---|---|---|
| A | 210, 211, 212 | Independent writers: no shared file or ledger anywhere; 210 keeps presenter-level laws out of `SongDockController` so 211 owns it alone; 211's mounted journey lives in `tst_ShellMenus` so 210 owns `tst_ShellSongs`. |

### Shared constraints and verification ownership

The §16–§27 contracts continue: fork clauses win; real production
ingress only (keyTyped/shortcut/menu click, `finishRename` through the
mounted editor); no test-only properties, no `Qt.callLater` in
production code; fail-closed staging; independent literals. Ledger rows
stay untouched — nothing here has an open row to close. Writers run
their brief's focused lanes under the lock/175-second alarm; the
controller owns the project-wide gate once after sources settle.
Planning validation for this docs-only commit checked fork sources at
`fceecd88` (`newsongwizard.cpp:78-149`, `projectidentity.cpp:8-13`,
`mainwindow.cpp:304-307,966-981`, `workspaceui_project.cpp:420-428`,
`trackheadermodel.cpp:514-530`, `songview.cpp:833-843`), Swift ingress
points (`ShellPresenter.swift:18-81,250-368`,
`SongDockController.swift:60-135`, `SongListPresenter.swift:115-259`,
`TrackHeaders.swift:290-312`, `KeybindingRegistry.swift:106-177`), lane
registrations (`swiftcore-projectsession`, `shell-songs`,
`shell-menus`, `verify:qml-roll`'s `swiftroll-window`), and pairwise
write-set disjointness; no application suite was run.
