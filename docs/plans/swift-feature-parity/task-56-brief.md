# Context

Task 56 — automation rendered geometry + previews/parity. Prove band/plot/tab/
label geometry and painted previews on the mounted automation drawer
(per-tab/per-row probes), preview edit-cursor/quick-view outcomes, then close
all three ledgers (139 open rows). Proof completion + representation sweep,
not a build: every GAP reason already names the converted-window lane
(`deno task verify:qml`), and that lane hosts the full production
`EditorSurface.qml` (`tst_EditorDrawer.qml:1-16` header) — roll band, ruler,
track headers, `SharedPlayhead` guides and `timelineSplitX` all reachable.

1. **Census (verified this freeze)**:
   - `proof.automationcanvaslayout.txt` — 128 sites: 22 MATCHED, 37 PARTIAL, 62 GAP,
     7 RETIRED-REPRESENTATION (open 99 = the 62 native-harness GAP sites + 37
     PARTIAL rendered halves). Header tally line ("GAP 7, NATIVE 62") is stale;
     body rows carry the truth.
   - `proof.automationpreviews.txt` — 49 sites: 20 MATCHED, 24 GAP, 5 RETIRED.
   - `proof.automationparity.txt` — 73 sites: 56 MATCHED, 16 GAP, 1 RETIRED.
   - Pinned revisions `f3069ef6` (canvaslayout) and `c17d966f` (previews/parity)
     are byte-identical to oracle `fceecd88` for all three sources (blob hashes
     re-verified at freeze). All three C++ sources are already deleted from the
     tree (previews/parity headers record `Deleted in: 31ea635f`;
     `automationcanvaslayout.cpp` likewise absent) — ledger deletion needs no C++
     removal.
2. **Fork laws** (`git show fceecd88:src/checks/automation/…`):
   - `automationcanvaslayout.cpp` — `verifyActivePlot` :42-64: band geometry
     present (automation + roll), lane body origin {0,0}, body size == viewport
     size == plotRect size, no `drawerAutomationScrollBar`, both plots' left ==
     `timelineSplitX`, every `automationParameterTab{i}` visible with non-empty
     scene rect inside the gutter. `automationBandAndInputsExposed` :70-89.
     `sectionResizeKeepsLabels…` :91-170: at minimum/maximum section height —
     viewport height == section height, split unchanged, no scrollbar, tab
     scroller (`clip`) `contentHeight` overflows at the minimum, first tab at
     content top, per-tab scroll-into-view + real activation (plot still
     canonical), document/cursor/split frozen. `layoutAlignsPlotGutterAndRollGrid`
     :172-219: gutter inside window, input/gutter scene rects == canonical rects
     (qRound widths, gutter height == band height), per-tab containment.
     `middleMousePanSurvivesRefresh` :221-244: middle press/move −48 px →
     closed-hand cursor, camera displayX moves exactly 48 (±0.5).
     `primaryTrackSwitchRebuildsRowsDuringPan` :252-284: mid-pan track switch →
     rows rebuild (new body non-empty, old invalid), gesture ends, frozen.
     `emptyParameterSwitchPreservesGridResolution` :286-317: empty-lane (LFO,
     controller 21) activation preserves grid ticks/snap resolution (roundings
     at +0.1/+0.4/+1.1 spacing), split, cursor, document.
     `viewStateSwitchPreservesAutomationState` :319-354: lane range 64 +
     resize; Velocity page round trip preserves automation state/viewport/
     active parameter/laneRanges. `wheelZoomAndSectionResize…` :356-397: wheel
     at anchor grows pxPerBeat, anchor tick preserved (<0.001), drawer page
     state preserved; resize extreme re-verifies the plot.
   - `automationpreviews.cpp` — per tempo+cc lane: `singleNodeDragPreview`
     :147-194 and `multiNodeDragPreview` :202-261 (selection-scoped): held drag
     past `nodeDragActivationDistance` paints the preview outline at the target
     node probe (`hoverRingRadius`), document frozen; `sweepPreview` :269-310;
     `shiftRampPreview` :318-355 (line probe 3×3 at mid);
     `pencilPreviewAndValueLabel` :356-392 (preview line + value-label record
     at the font-derived probe: gap `space(One)`, half `space(Half)`, size
     `fontPx(2)×fontPx(1)`, clamped into the plot); `editCursorTracksQuickView`
     :393-415 (edit cursor visible; guide x moves by the camera displayX
     difference, ±0.5).
   - `automationparity.cpp` — the 16 GAP rows are each gesture journey's
     construction pair (`findRow` valid + `activateParameter`) for hover
     :126-146, stationary :154-189, double-click :197-230, sweep+ramp
     :238-300, pencil :308-344 (its transient pair pins the preview-layer
     revision/triangles mid-stroke), lane-band :352-387, blank :395-426;
     outcome halves are MATCHED presenter-side (56 MATCHED rows).
3. **Swift current state — no production law gap identified at freeze.** The page
   renders everything the fork probed: `automationGutter` (x 0, width
   `plotOrigin`, clip) `AutomationPage.qml:243-248`, `automationPlot`
   (:277-283), `automationPlotInput` (middle button accepted; `cursorShape`
   binds `cursorKind` → ClosedHand :505-511), `automationPreviewRects`
   :420-424, `automationPreviewLabel` :448-464, tab strip
   `automationTabsScroller` (Flickable, clip, `ensureVisible`) +
   `automationParameterTab{i}` `AutomationTabs.qml:18-65`; preview publication
   `AutomationOverlayPublication.publishPreview` (:87-135) + `labelRect`; the
   edit cursor over the automation band is `sharedPlayheadEditAutomationGuide`
   (`SharedPlayhead.qml:390-397`). Presenter halves already execute
   (`automationcanvaslayout.swift` S001-S050, `presentation/painting.swift`
   S037-S038, `automationmenus.swift` S039, `automationcanvasediting.swift`
   S040/S152/S153, `rollcheck/static/camera.swift` S041). Drawer-lane helpers
   reused unchanged: `mountProductionAutomation` `tst_EditorDrawer.qml:3424`,
   `automationTab` :3470, `revealAutomationTab` :3605, `clickAutomationTab`
   :3619, `dragAutomationPlot` :3754, `writeVolumeLanePoints` :3713,
   `automationFreePoint`/`automationFreeColumn` :3686-3711,
   `verifyRect`/`renderedRect`/`verifySurfaceRect` :657-688,
   `bootstrap.automationDocumentRevision()` (`EditorQmlTests.swift:880`),
   `bootstrap.automationPanIndex()` :1000 (references are at this freeze;
   re-snapshot after task-54 settles). Fixture `mus_route101` stages ≥2
   tracks — the track-switch probe needs no track staging.
4. **Dependencies — consume, never duplicate.** Task-54 finisher (in flight) owns
   uncommitted `tst_EditorDrawer.qml` edits (`velocityPromptChild` helper +
   velocity-prompt functions) plus `EditorSurface.qml`/`PianoGrid.qml`-side roll
   files — read-only here. Task-59b (queued after 54) owns drawer velocity ink in
   the same file. The `tst_EditorDrawer.qml` chain is serial (sprint §5:
   55 → 56 → 57 → 59 → 60): this task appends only new functions and touches no
   54/59b region; the controller checkpoints 54 (and sequences against 59b)
   before dispatch. Task-55's prompt/tap functions and task-52's scrollbar
   absence anchors are consumed as landed, not re-proved.

# Exact write set

- `src/checks/editorqml/tst_EditorDrawer.qml` — append the functions in the
  Interface contract; existing anchor messages verbatim.
- Repair-only, RED-gated: `src/ui/songview/quick/drawer/AutomationPage.qml`,
   `src/ui/songview/quick/AutomationTabs.qml`,
   `src/swift/app/drawer/automation/AutomationOverlayPublication.swift` — only if
   a new predicate exposes a real divergence; no planned change.
- Ledgers (controller-delegated ledger agent, this task's commit scope): flip
  then delete `src/checks/automation/proof.automationcanvaslayout.txt`,
  `proof.automationpreviews.txt`, `proof.automationparity.txt`.

No CMake changes, no `EditorSurface.qml`, `PianoGrid.swift`, `ShellWindow.qml`,
`AutomationPrompt.qml`, `AutomationMenu.qml`, roll-lane files, no presenter check
files (`automationcanvaslayout.swift`, `AutomationPageChecks.swift` stay).
Sizing exception: one proof family over 1 check file + ledgers, one verification
surface — named for the dispatch table.

# Prerequisites

Task-54 settled and checkpointed (owns uncommitted `tst_EditorDrawer.qml` edits;
the sprint's "54 + 56" dispatch pairing is file-serial in practice). Nothing
consumed from 59b; if 59b lands first, re-snapshot function indices only.

# Interface contract

New message-anchored drawer-lane functions (one anchor per fork clause family;
anchors stay verbatim once written). Real pointer/keyboard delivery throughout;
mid-drag holds use raw `mousePress`/`mouseMove` on `automationPlotInput`
(`dragAutomationPlot`'s release path is the commit route). Frozen-document reads
use `bootstrap.automationDocumentRevision()`; expectations read published facts
(`section.bodyHeight`, `surface.timelineSplitX`, node `model.x/y/ringRadius`,
`previewLabelRect`) — never restated policy.

- `test_productionAutomationBandGeometry`: "the automation plot and the roll
  plot share the split origin" (plot and `timelineQuickRollPlot` x ==
  `surface.timelineSplitX`; plot width == surface width − split; input fills
  the plot exactly); "the selector gutter hosts every parameter tab inside its
  rect" (per index: exists, visible, non-empty scene rect inside
  `automationGutter` after `revealAutomationTab`; real `clickAutomationTab`
  sets `bootstrap.automationActiveParameterIndex()`); "the gutter input covers
  the gutter rect" (`AutomationTabs` child fills it); "the automation drawer
  mounts no scrollbar" (`drawerAutomationScrollBar` null, both resize
  extremes).
- `test_productionAutomationSectionResizeKeepsTabsClickable`: "the clamped body
  extremes follow the drawer's own policy" (`setSectionBodyHeight(0, 0)` then
  `(0, 100000)`; published `bodyHeight` is the clamp; viewport height ==
  body height); "at the minimum body the tab stack overflows the scroller"
  (`contentHeight > height`; first tab at content top, `contentY` 0); "every
  parameter tab activates after its reveal at both body extremes" (reveal →
  containment → real click → active index; plot still canonical); "resizing
  the automation section writes nothing" (revision, cursor, split; restore).
- `test_productionAutomationMiddlePanAndTrackSwitch`: "a middle drag pans the
  shared camera by its travel" (press lane-body center, move −24 then −48;
  camera scroll delta == 48 ±0.5; release ends it); "the pan shows the closed
  hand" (`automationPlotInput.cursorShape == Qt.ClosedHandCursor` mid-gesture);
  "a mid-pan track switch rebuilds the lane rows and ends the pan" (second
  track's header click mid-gesture; tab catalog/labels rebuild; rebuilt lane
  body non-empty); "the interrupted pan writes nothing".
- `test_productionAutomationEmptySwitchPreservesGrid`: "activating an empty
  lane preserves the grid resolution" (real activation of an events-less tab —
  LFO speed; `gridModel.snapTickDown(30)` and `gridModel.gridCell(48)`
  unchanged); "the empty activation writes nothing" (revision, cursor, split).
- `test_productionAutomationViewStateAcrossDrawerPages`: "a drawer page switch
  preserves the automation view state" (lane range via the real parameter menu
  `range64` route, section resized; real switch to Velocity + hide + resize:
  active parameter, lane range, body height unchanged); "returning to
  automation restores the canonical plot" (real switch back; plot/gutter/tabs
  re-verified; range retained).
- `test_productionAutomationWheelZoomPreservesDrawerState`: "wheel zoom keeps
  the anchor tick under the pointer" (angle wheel (0,120) on the plot input at
  a written node; camera px-per-beat grows; anchor tick preserved <0.001);
  "the zoom preserves the drawer's page state" (all three sections'
  visible/height facts and active page unchanged; resize extreme re-verifies
  the canonical plot; revision/cursor unchanged).
- `test_productionAutomationDragPreviews` (tempo and cc sub-cases, the fork's
  `_data` split): "a held node drag paints its preview at the target" (stage a
  written lane through real input; press the drawn node, move
  activation+distance; held: `automationPreviewRects` non-empty, a rect
  centered on the pointer-mapped target covers the node probe at
  `model.ringRadius`; empty again after release); "a selection drag previews
  every moved node" (lane-scoped time selection via the real band press; both
  targets probed); "a sweep drag paints its preview at the target" and "a
  shift ramp paints its preview line" (line probe half-width 3 at the
  mid-point, check-side); "the live preview writes nothing" (revision while
  held).
- `test_productionAutomationPencilPreviewAndLabel`: "the pencil stroke paints
  its preview line" (`pageModel.isPencilMode = true` — the published arming
  property, the roll-lane precedent `tst_SwiftRollAutomation.qml:287`; held
  stroke paints preview rects on the traversed line, half-width 8, height the
  fork's `max(singlePixel, hoverPaintPadding + 1)` extent, check-side); "the
  pencil preview labels the drafted value" (`automationPreviewLabel` visible
  mid-stroke, non-empty text, rect == published `previewLabelRect`, inside the
  plot); "the pencil commit lands one edit" (release: +1 revision, lane
  non-empty).
- `test_productionAutomationEditGuideTracksCursor`: "the edit guide over the
  automation band follows the cursor" (park a press to move the edit cursor,
  then again further right; `sharedPlayheadEditAutomationGuide` visible both
  times; its guide x advances by the camera display-X difference of the two
  ticks, ±0.5); "the moving guide writes nothing".

Non-goals: no gesture-domain outcomes (57), no velocity ink (59b), no prompt/
menu/tap journeys (55, landed), no roll-lane files, no new production behavior.

# Implementation steps

1. Re-verify mounts at freeze (stale-preamble hazard): confirm each mapped row's
   cited anchor still executes and the three sources at the pinned revisions
   hash to the ledger's recorded SHA-256s.
2. Add the geometry functions first (expected GREEN — proof, not fix); a failing
   predicate is a discovered defect: repair only in the contingent files and
   record RED→GREEN for that fix.
3. Add the preview/pencil/edit-guide functions; mid-drag observations ride
   `waitForNative`/`tryVerify` on published facts, never fixed sleeps.
4. Ledger mapping per Task-specific constraints, in the same commit as the
   predicates that prove each row; evidence feeds from
   `build/proof-evidence/editorqml-drawer.json`.

# Acceptance predicate

- `deno task build:checks`
- `deno task verify:qml --verbose` — the drawer lane: all new geometry/preview/
  guide predicates plus every existing automation, prompt, tap-tempo and
  scrollbar-absence anchor green verbatim.
- `deno task verify --filter swiftcore-projectsession --verbose` — regression
  only (S001-S050 untouched); confirms the presenter halves the PARTIAL rows
  cite still execute.
- Runtime prerequisite: the drawer lane's usual offscreen-capable Qt windowing;
  no native audio, no desktop access beyond the lane's own window.

# Task-specific constraints

- No new C++; no code comments — delete stale ones inside edited regions; no
  pixel constants in production (fork probe half-widths 3/8 and paddings stay
  check-side, as in the fork's own block); geometry stays base-font multiples;
  existing anchor messages verbatim; one message-anchored predicate per fork
  clause. WCAG AA: the extended functions keep the page's `auditVisibleTextInk`
  pass (the label/readout items are in their paths).
- Implementers never edit ledgers; the controller delegates per-commit. Ledger
  mapping (agent; re-verify each row against the evidence JSON and the fork
  sources cited above):
  - automationcanvaslayout: A001-A003 → band/present + origin anchors;
    A004/A012 → clamped-extremes viewport anchor; A005-A011 → split/
    no-scrollbar/tab-visibility anchors; A013-A019 → mount anchors for the
    observable halves, `RETIRED-REPRESENTATION` for the native identity pins
    (`m_automationInput->window() == m_quickWindow`, `TimelineInputItem*`/
    `TimelineQuickScene*` pointer lookups — verify at Reference revision
    f3069ef6); A021-A049 → resize anchors (PARTIAL rows keep their
    S001/S004/S037 citations); A050 → `RETIRED-REPRESENTATION` (native
    `TimelineQuickView` existence; the mounted `swiftRollOverlay` surface is
    the converted scene, asserted by the lane's own mount guard); A053-A071 →
    band-geometry anchors (scene-rect equalities, qRound widths → 0.01,
    gutter height == band height, per-tab containment); A072-A074 → pan
    anchors; A076-A085 → track-switch anchors (keep S031-S036); A087-A101 →
    empty-switch anchors (keep their grid S citations); A102-A109 →
    page-switch anchors (keep S042-S050); A113-A126 → wheel/resize anchors
    (keep S041 where cited).
  - automationpreviews: construction rows (A001, A003-A005, A011, A013, A020,
    A027, A035, A042) → the staging + real-activation anchors of the
    corresponding function; revision rows (A008, A016, A024, A031, A038) →
    "paints its preview" anchors (the live-preview-appears-while-held law is
    the user-visible equivalent of the transient-layer revision);
    colour/text rows (A009, A017, A018, A025, A032, A039, A040) →
    probe-coverage and preview-label anchors; A045/A046 → edit-guide anchors.
  - automationparity: construction pairs (A001/A002, A006/A007, A015/A016,
    A026/A027, A046/A047, A057/A058, A069/A070) → the mounted journeys' staging/
    real-activation anchors (their outcome rows are already MATCHED
    presenter-side and stay); A051/A052 → pencil live-preview + commit anchors.
  - All three ledgers are deletion candidates: every row must land MATCHED or
    RETIRED-*; delete the proof files in this task's closing commit (no C++
    sources remain to remove). If any row cannot close, leave it open with its
    reason; do not force a mapping.

# Controller verification

1. Shared baseline after the writer settles: `deno task verify:bridge`,
   `deno task format --check`, `deno task proof check`,
   `deno task proof check --executed`,
   `deno task proof check --strict-mappings` (pre-deletion state shows all
   three ledgers fully closed with executing message anchors), then
   `deno task proof sites --area automation` no longer lists the three files.
2. Confirm `deno task verify:qml --verbose` includes the nine new functions by
   name in its verbose output and no drawer-lane regression against the
   pre-task run.
3. Visual/native smoke (desktop): open the automation drawer; drag the section
   between its clamp extremes — tabs scroll, reveal and click at both; middle-
   drag the plot (closed hand, camera pans); click another track header mid-drag
   (rows rebuild, no write); drag a node past slop and hold (outline preview at
   the target, no write; release commits); shift-drag a ramp and hold (line
   preview); pencil-stroke and hold (preview line + value label); park presses —
   the edit guide over the automation band moves with the cursor; wheel-zoom
   with the pointer on a node (it stays under the pointer).
