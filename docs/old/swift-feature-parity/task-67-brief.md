# Context

Task 67 — host adapter/integration observation lanes. Close or explicitly
NATIVE-mark the host proof family (198 open rows across four ledgers) with
harness-side observation checks only; no production rewrite. Sprint-3 §task-67
outcome: note discovery / selected-notes / marker / playhead / band-geometry
contracts observed on the real macOS host (controller-run), or explicitly
NATIVE-marked where only the host can see them.

1. **Census (verified this freeze; implementer re-runs step 1 before any
   predicate)**:
   - `proof.tst_hostintegration.txt` — 185 rows: 89 RETIRED, 89 GAP, 7 PARTIAL.
     Open 96 = sprint's "hostintegration 96". GAP by function: `events::sendMouse`
     26, `documentMutationUndoRedoAndReloadPreemptPreview` 11,
     `nonSelectedEditorStateFansOutWithoutTouchingSongBytes` 10,
     `automationPanLifecycle` 9, `velocityEditCommitsOnceInvalidatesAndUndoes` 9,
     `projectSwitchAndClosePreserveProjectBoundaries` 5,
     `steadyPlaybackIsPresentationOnly` 4,
     `readySongTabVelocityTransactionRetainsHeldAndCommittedContracts` 4,
     `lifecycleTermination` 4, `songTabTeardownDestroysQuickWindowBeforeDocument` 3,
     `appearanceNotificationPreservesAutomationRaster` 2,
     `twoTabReadySessionWithTwoNoteSeed` 2. PARTIAL: `lifecycleTermination` 7
     (A114–A120 velocity-termination correspondence, unproved song-null /
     song-replacement / voice-replace / voice-null executions).
   - `proof.tst_hostadapter.txt` — 195 rows: 90 RETIRED, 65 GAP, 15 PARTIAL,
     25 MATCHED. Open 80 = sprint's "hostadapter 80". GAP by function:
     `canonicalGeometryProjectsToQuick` 10, `hiddenBandsClearEveryProjection` 10,
     `route101FixtureAttachesHostedVelocityMarker` 7,
     `drawerChromeAndQuickHeadersFollowCanonicalGeometry` 6,
     `eventListHidesOnlyRollProjection` 6, `bandGeometryPublishesWithTheChoreography`
     5, `events::sendMouse` 4, `drawerSoloAndTrackRemapReachTheHost` 4,
     `voiceChangesRefreshWithoutInvalidatingAutomationRaster` 4,
     `velocityVoiceRoutingUsesPresentationOnlyForSteadyContext` 3,
     `automationPanRoutesThroughQuickWindow` 2,
     `automationTempoRangeDelegatesTheSelectionScope` 2,
     `loopMarkersReachTimelineButNotTheOtherEventsRaster` 1,
     `syntheticFixtureConstructsHost` 1. PARTIAL: `canonicalGeometry…` 7
     (A027–A033 ruler/velocity plot-origin asserts lack message anchors),
     `otherEventsTooltipUsesTheQuickInputAndClearsOnLeave` 7 (A123/A128–A133),
     `loopMarkers…` 1 (A137). MATCHED anchors S001–S022 live in
     `tst_SwiftRollTrackHeaders.qml`, `tst_EditorDrawer.qml`,
     `tst_SwiftRollPlots.qml`, `drawerpresentation/other_events_band.swift`,
     `rollcheck/ruler_loop_menu.swift`.
   - `proof.tst_hostseams.txt` — 58 rows: 37 RETIRED, 21 GAP. Open 21.
     GAP: `editorEndpointsUpdateCameraAndResolveGridVoice` 11 (A012–A022),
     `automationPlotFillsHostViewport` 6 (A005–A010), `editorStateIsCosmeticOnly`
     3 (A024–A026), `documentChangedPreservesCosmetics` 1 (A028). Fully retired:
     `QObject::connect` 22, `embeddedWindowOwnershipTransfersToTheContainer` 3,
     `unhostedDetachEmitsOnceDestroysWindowAndClearsGetters` 5.
   - `proof.tst_rulergridmenu.txt` — 166 rows: 100 RETIRED, 65 MATCHED, 1 GAP.
     Open 1: A105 (`rulerGridClosePopupsCancelsOwnedNotForeignPopups:461`,
     `QVERIFY2(emptyKey >= 0, "the fixture left no empty roll row…")`).
2. **Fork laws** (Reference revisions; implementer re-verifies every row with
   `git show <ref>:<path>` before writing its predicate):
   - Ruler `a1244957:tst_rulergridmenu.cpp:440-480` — A105 seeds a real
     time-selection range and scans 128 roll rows for an empty key; the probe
     exists only to open a *foreign* roll menu whose terminal assertions
     (A106+: `closePopups` cancels foreign-owned session, Escape on the foreign
     window) are already RETIRED-REPRESENTATION. Scaffold of retired rows.
   - Seams `c17d966f:tst_hostseams.cpp:41-62` — automation tempo-index lookup,
     band-geometry presence, plot-x equals split, viewport-size equals plot-size,
     viewport non-empty, lane-body equals viewport. `:69-88` — camera endpoints
     (scroll 96.0, zoom `1.75 * fontPx(8/3)`, `gridTicksAt(12) > 0`,
     `snapTicksAt(12) > 0`, voice slot 0, `drawerContextTick` rounding
     0.49→0 / 0.5→1). `:95-109` — editor state round-trips cosmetically with
     revision/history unchanged. All deleted at 31ea635f; no CMake target, no
     `checkcatalog.cpp` host entry.
   - Adapter/integration `c17d966f` (ledger-quoted expressions, same deletion) —
     velocity preview stage/commit with revision/history invariance
     (`previewVelocity`, `document.revision()`, `undoStack()->index()/count()`),
     click selection size, playhead tick following, two-note/route101 fixture
     discovery, band presence/tiling, tooltip content, teardown order.
3. **Swift current state**: owners named in the GAP mappings exist and execute
   today — `DocumentSession`/`SongDocument`/`SongTabsController`
   (`src/swift/app/`), `VelocityPage` (`drawer/velocity/`),
   `AutomationPage` (`drawer/automation/`), `EditorCamera` value type
   (`timeline/EditorCamera.swift:92`), `DocumentWorkspace`,
   `ApplicationSession.handleGridEscape` (`ApplicationSession.swift:544`).
   Executing counterparts: velocity suites (`VelocityClickSelectionChecks.swift`,
   `VelocityPageChecks.swift`, `tst_ShellWindow.qml test_kVelocityGestureTermination`),
   roll lanes (`tst_SwiftRollTrackHeaders/Plots/Automation.qml`), drawer lane
   (`tst_EditorDrawer.qml`), grid-menu lane (`tst_ShellGridMenu.qml`).
   No executing lane in `src/checks/host/`.
4. **Classification rule (scope = user-visible behavior)**: a row is BEHAVIOR if
   a user can observe it on the production surface (selection, preview, playhead,
   geometry, camera, cosmetic invariance, teardown order); it is
   NATIVE-HOST REPRESENTATION if only the deleted harness could see it (raster
   captures, framebuffer, `quickWindow` delivery, embedding/ownership,
   signal-wiring, harness scaffolding). Representation rows are never proved —
   they flip to RETIRED-REPRESENTATION. §Classification adjudicates every open
   function; sprint B~65 estimate confirmed in shape (implementer tallies exact).

# Exact write set

- `src/checks/host/HostBehaviorChecks.swift` — **new**: presenter/document-level
  observation predicates for every §Classification BEHAVIOR cluster, one
  message-anchored predicate per fork clause; stimuli are production calls
  (presenter methods, document/session APIs), never a synthetic harness.
- Owner-suite call-list registration for the new file (same pattern as
  `VelocityPageChecks.swift` call-list entry); no new C++, no `src/project/`,
  no `external/`.
- Message-anchor additions to existing mounted asserts for the adapter PARTIAL
  blocks (canonicalGeometry ruler/velocity plot origins, tooltip hidden-state,
  loop-marker raster-guard replacement) — controller serializes these after
  in-flight Task59b/Task66 land; new-file predicates stay free-parallel.
- Ledgers (controller-delegated ledger agent, this task's commit scope): row
  flips only in the three surviving ledgers; delete
  `proof.tst_rulergridmenu.txt` iff A105 retires (§Open questions Q1).

No production Swift/QML changes (contingent RED→GREEN fixes only, recorded per
fix); hot files (`ShellWindow.qml`, `ApplicationSession.swift`,
`DocumentWorkspace.swift`, `EditorSurface.qml`, `PianoGrid.swift`) untouched;
Task59b-owned velocity files + `tst_ShellWindow.qml` journey and Task63-owned
projectstore/voicelist files untouched — coordinate, do not collide.

# Prerequisites

None. Free-parallel for the new-file predicates; anchor additions serialize
after Task59b (velocity/`tst_EditorDrawer.qml`/`tst_ShellWindow.qml` + the ONE
`handleGridEscape` branch) and Task66 (track-header/roll lanes) settle.

# Interface contract

- New check anchors (message-anchored, one per fork clause; `what:`/`message:`
  strings are the ledger anchors and stay verbatim once written):
  - `HostBehaviorChecks::noteDiscovery` — "route101 fixture notes resolve from
    the loaded document with timeline note-on events"; "track zero projects two
    seeded notes".
  - `::velocityMarker` — "the selected note publishes one axis marker";
    "the marker value equals the fixture velocity".
  - `::velocityGestureContracts` — "a drag move stages a preview without
    advancing revision or history"; "committing advances revision once and
    invalidates"; "a click press selects one note without touching song bytes".
  - `::lifecycleTermination` — "song-null, song-replacement, voice-replace and
    voice-null teardown clear the preview without mutating the song" (closes the
    A114–A120 unproved conditions); "track-replace teardown clears the selection".
  - `::playheadFollowing` — "the playhead tick follows the played sample";
    "steady context resolves through presentation voice, not the bank".
  - `::bandGeometry` — "hidden bands clear every projection"; "event-list hides
    only the roll projection"; "plot origins sit at the split and right edges
    meet band edges".
  - `::cameraEndpoints` — "scroll 96 and the zoom law publish through the camera";
    "grid and snap ticks stay positive"; "voice context resolves slot zero";
    "context-tick rounding splits at the half tick".
  - `::cosmeticOnly` — "editor view-state round-trips without advancing revision
    or history"; "non-selected editor fanout and pan attempts leave song bytes,
    revision and undo depth untouched"; "project switch/close preserves project
    boundaries".
  - `::automationTempo` — "the tempo parameter index resolves"; "the automation
    plot fills the viewport at the split".
- Preservation contract: production behavior unchanged; every existing check
  message in touched files stays verbatim.

# Implementation steps

1. Census first: re-run the §Context counts per ledger and per function with an
   exact script; confirm 198 open (96+80+21+1) at freeze. Any drift stops the
   task — report, do not silently re-scope.
2. Classify row-by-row per §Classification against `git show <ref>:<path>`;
   representation rows flip to RETIRED-REPRESENTATION with the fork citation,
   never gain predicates.
3. Add `HostBehaviorChecks.swift` cluster-by-cluster per the contract; stimuli
   through production APIs (presenter/document/session), real fixture data
   (`mus_route101`, two-note seed), no synthetic window/input harness.
4. After 59b/66 settle, add the message anchors for the adapter PARTIAL blocks.
5. Run the lanes below; per-lane evidence JSONs under `build/proof-evidence/`
   feed the ledger agent.

# Acceptance predicate

- `deno task build:checks`
- New host-behavior lane PASS (filter named at implementation; predicates above
  all executing, evidence JSON emitted).
- No regressions in owner lanes: `verify:qml-roll --filter swiftroll-window`,
  `verify:shell --filter shell-grid-menu`, `verify:qml` editorqml-drawer,
  `verify --filter swiftcore`.
- `deno task verify:bridge`, `deno task format --check`, `deno task proof check`
  (structure only).
- Runtime prerequisite: macOS; native audio not required (no playback asserts).

# Task-specific constraints

- No new C++ (harness sources stay deleted); never `src/project/`/`external/`.
- No code comments; no pixel constants (base-font sizing via existing
  `fontPx`/typography helpers); GridPalette colors; WCAG AA where a QML surface
  is touched.
- No test-only seams: ex-`sendMouse` rows are behavior assertions whose stimulus
  moves to production calls/QML input — the helper itself is never resurrected,
  and no production API is added to satisfy a predicate.
- Raster/pixel assertions are never re-proved (representation by rule); the
  loop-marker leak guard becomes a projection predicate, not a capture.
- One message-anchored predicate per fork clause; implementers never edit
  ledgers.
- Sizing: one observation family in one new check file plus serialized anchor
  additions — named for the dispatch table.

# Classification

- BEHAVIOR (prove): adapter route101 7G + syntheticFixture 1G; canonicalGeometry
  10G + 7P; hiddenBands 10G; eventList 6G; drawerChrome 6G; bandGeometry 5G;
  drawerSolo 4G; voiceChanges 4G; velocityVoice 3G; automationPan 2G; tempoRange
  2G; loopMarkers 1G + 1P; tooltip 7P; integration sendMouse-behavior 26G;
  velocityEdit 9G; documentMutation 11G; nonSelected 10G; automationPan 9G;
  projectSwitch 5G; steadyPlayback 4G; readySongTab 4G; lifecycle 4G + 7P;
  songTabTeardown 3G; appearance 2G; twoTab 2G; seams editorEndpoints 11G;
  automationPlot 6G; editorState 3G; documentChanged 1G.
- REPRESENTATION (stay/turn retired, never proved): all 90+89+37+100+22 already
  retired (rasters, framebuffer, `quickWindow` delivery, `sharedPopup`,
  `quickInputsOwnTheirInteractions`, `embeddedWindowOwnership`,
  `unhostedDetach`, `QObject::connect`, fixture-harness scaffolding) plus
  reclassification candidates Q1–Q2 below. `sendMouse` the mechanism retires
  everywhere; the assertions it drove are BEHAVIOR and move stimulus.

# Open questions

1. Ruler A105: scaffold probe whose terminal assertions (A106+) are already
   RETIRED — recommend RETIRED-REPRESENTATION, which fully closes the ruler
   ledger for deletion. Ledger agent adjudicates at the fork citation.
2. Seams A012 `runtime.valid`: `EditorCamera` is a value type with no validity
   field — recommend RETIRED-REPRESENTATION (adding one for proof alone is a
   test-only seam). Same adjudication path.
3. Automation GAPs (seams A005–A010, adapter A146/A147/A160/A161) prove here via
   `AutomationPage` + roll automation lane, or route to the automation-lane
   owner? Recommend prove here; flag if the lane overlaps in-flight work.
4. Ex-`sendMouse` stimulus split: presenter-level for document contracts,
   mounted QML input for selection/focus behavior — confirm per cluster during
   implementation; default presenter-level unless the clause names a surface.
5. Serialization: anchor additions wait for 59b/66; if they slip, the new-file
   predicates still land and PARTIALs stay open with a named deferral.

# Controller verification

1. Shared baseline after the writer settles: `verify:bridge`, `format --check`,
   `proof check`, `proof check --executed`, then `proof sites --area host`
   confirms the ruler deletion and the surviving open rows only where §Behavior
   predicates are not yet executing.
2. Confirm no hot-file or sibling-owned diffs in the task commit.
3. Headless smoke: new lane verbose output shows each contract message; no owner
   lane regresses against the pre-task run.
