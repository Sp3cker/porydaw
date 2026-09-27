# Sprint-3 plan: existing-surface parity after task 51

Status: **in execution.** Landed: 52 (32aa160d), 53 (e7c58e06) + 53b (342dc379), 54 (8d27003d),
55 (c34ccff6), 56 (92db95fc), 57 (153804d7), 58 (374bc21f), 59a (e833eaa6), 59b (3df72bba),
60 (df33f77e), 61 (089652fc), 62 (d4fd8b3b), 63 (83af818e), 64 (74134e8d), 65 (79c8d90e +
044bc3a6), 66 (8a6f2e21), 66b (f8b4dc68), 67 (1cbfa737), 68 (2c77b0de), 69 (6a963cb3),
71 (dcf6fdf3), 72 (62f58c98), 73 (62b12d40), 74 (ba09af7b), 75 (917dd499), 76 (dcad437b),
77a (4451e20a), 77b (2348b0b8); native Edit-menu titles (5481df9f). Resize sweep 9.9 s →
1.5–2.1 s with no per-resize or per-scroll scene rebuild. Next: pick from §6. Proof files:
155 → 129.
User rulings this sprint: insert-cursor commits never seek or move the playhead in any
transport state (8f6d41d2, deliberate deviation from fork `mainwindow.cpp:520-528`; Go to
Start still rewinds); the ~115 ms anti-click settle hold on resume stays. Open decisions:
blank-token rebase across external same-section source edits (conflicts with tested E10
blanket token expiry); catalog-outage status path (Swift scan has none). Fork oracle:
`fceecd88` (`git show fceecd88:<path>`).

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
