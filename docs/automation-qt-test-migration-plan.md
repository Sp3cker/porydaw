# Automation Qt Test migration — coverage ledger

Permanent old→new ledger for **every** legacy automation assertion contract:
`src/checks/automationgesturecheck/` (12 check modules + harness infra) and
`src/checks/rollcheckautomation*.cpp` (5 files). The parent plan (Main) owns the
migration decision: **all** automation families migrate to Qt Test; replaced
legacy is trimmed only after its replacement is proven; anything genuinely
native after evidence is explicitly retained in §9 — §4.7/§9 now record the
first confirmed residuals (the custom-geometry raster rows).

Inputs consolidated here: transactions-module audit (agent://MapAutomationTransactions),
gesture-module and canvas inventories (`automation-gesture-inventory.md`,
`automation-canvas-inventory.md`), implementing owners' declared and updated
mappings (Pencil/Selection/Parity/Paint/Chrome/Popups/Routing/Ownership/
CanvasEditing/Domain/Hover), and the landed shared fixture header
`src/checks/automation/tst_automationediting.h`. Architecture evidence:
agent://AutomationArchitecture.

**Source line ranges are inventory hints for orientation only.** They already
drift (inventories record `action.cpp` at 143L; it is 151L; parity function
ranges moved vs. the first audit). Ranges below are owner-declared from live
source where available. Definitive removal requires re-reading live source at
trim time plus the proof gates in §10 — a range in this file is never, by
itself, authority to delete.

Deliberately out of scope: the MainWindow check-member extraction roadmap
(checks-health-plan Steps 2/2.5/3). This ledger only covers automation families.

Sister docs: `docs/checks-health-plan.md` (host-choice rule, suite architecture,
historical `automation-editing` acceptance record — that record is historical
and remains untouched), `docs/velocity-qt-test-migration-plan.md` (precedent).

Legacy inventory (measured): gesturecheck 5,088L modules + 1,287L infra
(`rig.h` 268, `rig.cpp` 801, `runner.cpp` 75, `domains.h` 25, `support.h` 118);
rollcheckautomation family 3,741L (`rollcheckautomation.cpp` 1,818,
`_tempo` 248, `_paint` 735, `_tempo_paint` 549, `_popup` 391). Total 10,116L.

## 1. Hosts and suites

| Suite | Host | Header owner | Sources (landed) |
|---|---|---|---|
| `AutomationEditingTest` (AET) | Real `SongTab` + `QQuickWindow`, offscreen — transactions, strokes, selection, parity, paint previews, menus/clipboard, voice/routing, ownership, projection | AutomationFixture (sole editor of `tst_automationediting.h` + original cpp) | `automationpencil.cpp`, `automationstroke.cpp`, `automationpainting.cpp`, `automationpreviews.cpp`, `automationselection.cpp`, `automationmenus.cpp`, `automationclipboard.cpp`, `automationvoice.cpp`, `automationrouting.cpp`, `automationownership.cpp`, `automationactions.cpp`, `automationparity.cpp`, `automationnodedrag.cpp`, `automationcanvasediting.cpp`, `automationcanvaslayout.cpp` |
| `AutomationPresentationTest` | Existing EditorRig, static (quickRoot) — chrome, geometry, tempo lane, cursors, gutter text | AutomationChrome | `src/checks/automation/presentation/`: `tst_automationpresentation.h`, `tst_automationpresentation.cpp`, `painting.cpp` |
| AutomationHover suite | Independent QObject; EditorRig + actual `QQuickWindow` input; direct canvas cancellation API only for the cancellation contract | AutomationHover | `src/checks/automation/hover/`: `tst_automationhover.h`, `tst_automationhover.cpp`, `hoverfixture.h`, `hoverfixture.cpp` |
| `AutomationDomainTest` | GUI-free QObject; `runAutomationDomainCheck(const QStringList&)`, one `qExec`; `SongDocument`/`RangeEdit`/SMF byte-stream | AutomationDomain | `src/checks/automation/domain/tst_automationdomain.h/.cpp`, `xcmd.cpp`, `gestures.cpp` |
| `automation-raster` (retained-native Qt Test suite) | Real native `WindowSystem` window + `captureQuickBand` — the §9 raster residual only; `AutomationRasterTest` executes once through `QTest::qExec` | — (private fixture `automation/raster/rasterfixture.h`) | `src/checks/automation/raster/`: `tst_automationraster.h`, `painting.cpp`, `interaction.cpp`, `rasterfixture.h`, `rasterfixture.cpp` |

Fixture discipline (landed contract): helpers contain no Qt assertions — Qt
macros live at slot level; fresh fixture state per slot; `stage(SmfFile)`
rebuilds a **fresh** `SongTab` (non-canonical slots must `QVERIFY(stage(...))`
before arranging); no manual `documentChanged` refresh; all pointer/key/wheel
input goes through the real `TimelineInputItem`/`QQuickWindow` delivery
(physical-item mouse overloads, `mouseDClick`, `wheel`, `sendWindowDeactivate`,
`keyEvent(..., autoRepeat)`); no native window activation, no physical cursor.
Member definitions spread across per-behavior cpp files; every owner sends slot
declarations to AutomationFixture; no universal rig (EditorRig quickRoot is the
static seam). Registration landed in Main's batch: catalog rows `automation-domain`, `automation-presentation`, `automation-hover` (`Framework::QtTest` + `Windowing::Offscreen`), `fwd.hpp` decls, and CMake sources; the legacy catalog rows (`automation`, `automation-gestures`, `automation-popup-menus`) were removed in the 2026-09-05 cutover batch. The current `automation-raster` `Windowing::WindowSystem` row runs `AutomationRasterTest` through one `QTest::qExec`.

## 2. Status vocabulary

- **P — proven offscreen** — implementation landed, isolated and reordered
  suites pass, representative mutation controls reject broken production
  paths, oracle parity is confirmed (§5), and host evidence is recorded (§9).
  Promoted 2026-09-05 across the replacement
  rows by the 2026-09-05 per-row isolation run: all 182 rows PASS individually
  (editing 131 / domain 24 / presentation 16 / hover 11), all four suites
  PASS with reversed data-row order (133/26/18/13 Qt results, wall 469.96s),
  and two targeted production mutation controls failed the expected slots
  and passed after restore (`commitNodePointMoves` → `ccDragCommitsOnce`
  documentChanged 0≠1; `pointSelected` half-open boundary `<`→`<=` →
  `halfOpenTimeSelectionComposesNodeRings` excluded-second ring; sources
  restored to exact snapshots `3A4C`/`3805`; baseline citations `7430fb4`).
  P is a completed-cutover status for everything except the pixel halves:
  those stay with the `automation-raster` `WindowSystem` row — compiled and
  source-reviewed, deliberately not executed natively (§9 boundary).
- **N — retained native** — original pixel oracle preserved, source-reviewed,
  compiled and linked in `automation-raster`; deliberately not executed.
- **P / N** — the offscreen portion is proven and the pixel portion is retained
  natively. This is a completed split contract, not a pending migration.
- **—** — fixture precondition, not a separate behavior case.

## 3. Verified pilot baseline (existing coverage — do not re-plan)

All three in AET, asserted against a real CC lane over the real
`timelineAutomationInput` item (source-verified, `tst_automationediting.cpp`):

1. `ccDragCommitsOnce` — armed drag shows the retained `AutomationTransient`
   node at its provisional target while SMF/revision/undo/signal counts stay
   frozen; release commits **exactly one** transaction (1 `documentChanged`,
   1 `edited`, revision +1, undo count/index +1); an independent control point
   proves the edit is not a broad replacement; undo/redo round-trip symmetric
   through the retained timeline. Overlaps: parity `nodeDragCommits` CC
   plain-drag subset, paint single-node transient preview. Does **not** cover:
   Tempo adapter, shift axis locks, microsecond preservation, same-tick group
   ordering, multi-node drag.
2. `escapeCancelsCcDrag` — Escape empties the transient layer (rects and
   triangles), later pointer traffic cannot revive it, release commits nothing.
   Overlaps: parity `escapeCancelsAdapterDrag` CC row, roll `1733` route 5.
   Does **not** cover: Tempo adapter, pencil-mode routes, hide/deactivate/
   documentChanged routes, voice-lane escape.
3. `releaseWithoutActivationDoesNotCommit` — stationary press/release on blank
   lane space parks `editCursorTick` with zero document mutations or signals.
   Exact match for roll `769-771`. It does **not** cover sub-threshold jitter
   or activation-slop consumption (see §4 corrections).

## 4. Corrections to inventory claims (authoritative over the inventories)

1. **Sub-threshold / activation-slop are NOT pilot-covered.** The pilot's
   `armCcDrag` moves *beyond* activation distance as drag setup and asserts
   nothing at the boundary. Canvas inventory rows `784-786` ("covered by pilot
   activation invariant") and `797-800` ("covered by pilot armCcDrag") are
   wrong. They are asserted by parity `blankAndSubThresholdNoOps` and
   CanvasEditing `activationSlopDoesNotCommit` respectively.
2. **Offscreen compatibility required evidence.** The inventories initially
   assumed universal compatibility. At baseline `7430fb4`, `automation` and
   `automation-gestures` were classified `Windowing::WindowSystem`. The
   completed probes (§4.7/§9) established the actual boundary: custom-geometry
   framebuffer oracles remain native; modal `QInputDialog`/queued `QMenu`
   drivers, real-window input, and the host-injected DPR seam work offscreen.
   The current catalog contains four offscreen Qt suites and one retained
   `automation-raster` native row, not the removed legacy registrations.
3. **Pixel-specific oracles are preserved.** An actual-pixel contract is not
   replaced by retained-layer data alone. Standard-QML/text capture oracles
   remain offscreen; the custom-geometry pixel oracles are preserved in
   `automation-raster`: gutter-hover equality, Tempo/CC curve and node colors,
   selected/half-open rings, hover ghost/repeat/annulus/clear, and the voice
   preview difference (§9). Capture validity or dimensions alone do not
   establish a pixel oracle. Tempo occlusion and reticle rows were already
   retained-geometry checks, not additional native framebuffer requirements.
4. **Pilot overlap is per-assertion, not per-file.** e.g. roll `769` is the
   only exact pilot match; `927`/`954` (click delete, double click) were
   described as pilot-adjacent but are uncovered; `runLfoTitle` has no pilot
   coverage at all.
5. **Suite structure.** The canvas inventory's "6-7 new files under one
   harness" is superseded by the fixture contract: one shared AET for all
   transaction/interaction cases plus independent QObject suites
   (presentation, hover, domain) that own their headers. No legacy-rig
   replacement, no universal fixture.
6. **"100% removable" claims** (both inventories) are per-file hypotheses that
   hold only after §10 gates; §9 may retain rows.
7. **Offscreen capability boundary — observed 2026-09-05, no longer a
   hypothesis (completes §4.2).** The offscreen runner (`tools/run_checks.ts`)
   sets `QT_QPA_PLATFORM=offscreen`; `QOffscreenIntegration` hard-rejects
   `RhiBasedRendering`
   ([qtbase 6.11 qoffscreenintegration.cpp](https://raw.githubusercontent.com/qt/qtbase/6.11/src/plugins/platforms/offscreen/qoffscreenintegration.cpp)),
   so `QSGContextPlugin::contextFactory()` falls back to the built-in
   **software** adaptation and logs `qt.scenegraph.general: Loading backend
   software`
   ([qtdeclarative 6.11 qsgcontextplugin.cpp](https://raw.githubusercontent.com/qt/qtdeclarative/6.11/src/quick/scenegraph/qsgcontextplugin.cpp);
   observed in artifact://286). There,
   `QSGSoftwareRenderableNodeUpdater::visit(QSGGeometryNode*)` recognizes only
   SimpleRect/SimpleTexture/NinePatch/Rectangle/Image nodes and **skips every
   arbitrary custom geometry node** (`return false`)
   ([qsgsoftwarerenderablenodeupdater.cpp](https://raw.githubusercontent.com/qt/qtdeclarative/6.11/src/quick/scenegraph/adaptations/software/qsgsoftwarerenderablenodeupdater.cpp)).
   Porydaw's paint layers — `TimelineQuickGeometryChunkNode`
   (`timelinequickscene.cpp`), `TimelineChromeNode` (`timelinequickchrome.cpp`),
   `PlayheadNode` (`playheadquick.cpp`); all `QSGGeometryNode` +
   `ColoredPoint2D` + `QSGVertexColorMaterial` — are therefore never
   rasterized offscreen. **A non-null `grabWindow()` image is not proof that
   custom geometry drew**: the software renderer fills the background and
   paints standard QML items, so the capture stays valid and well-dimensioned
   with zero custom primitives. artifact://286 recorded exactly this split on
   the first full AET offscreen run (6 passed / 19 failed): retained-layer,
   document/undo, input, and domain cases passed; every custom-geometry pixel
   oracle failed (`framebufferHasColorNear`, `framebufferHasColorInRingBand`,
   before/after `captureQuickBand` inequality, hover pixel-change), and the
   pencil/stroke arrange failures traced to a separate input-fixture defect,
   since fixed in the shared fixture helpers (§6 status). Consequences:
   (a) CPU retained composition (`TimelineQuickLayerData` rects/triangles),
   text records, document/undo, and real-window input
   contracts stay offscreen — "composed"/"retained", not "rendered", is their
   honest oracle; (b) framebuffer pixel oracles over custom geometry are
   provable only under `Windowing::WindowSystem`, so their rows keep the
   source-verified legacy native raster ranges — `rollcheckautomation.cpp`
   1427-1508 (half-open ring: three positive framebuffer probes, no negative
   pixel-B probe) + 963-970 (gutter-boundary no-paint),
   `rollcheckautomation_paint.cpp` 509-517 (curve/node colors) + 541-547
   (selection ring), `automationgesturecheck/hover.cpp` 498-565
   (ghost/repeat/ring/clear), `routing.cpp` 140-150 (voice preview diff) —
   now carried by the registered `automation/raster/` residual sources
   (§9, §10), whose native execution is the deliberate §9 boundary;
   `rollcheckautomation_tempo_paint.cpp` contains retained layers/text only
   and contributes no native residual; (c) no headless
   hardware-render seam exists —
   `Windowing` is `Offscreen|WindowSystem` only, and CI intentionally runs
   offscreen GUI checks on the software backend (`.github/workflows/build.yml`);
   (d) real-window input delivery, the host-injected DPR seam (§6.6), and the
   public retained-layer seam are **not** native (§9).

## 5. Oracle and evidence rules for every case

- Original observable retained: same document/undo/selection/transient/pixel
  assertions as the legacy check (weaker oracles prohibited). Owner-proposed
  reductions are quarantined in §8 until Main adjudicates.
- Negative controls are targeted, not per-case (Main's approved gate): break
  the production path and watch the case fail only for genuinely uncertain
  behaviors and representative boundaries (pilot precedent: suppressed
  node-move commit, held-movement finish, disconnected Quick release routing).
  Every function and data row still runs isolated and reordered, and oracle
  parity review is still required for every case.
- Offscreen claims are proven by running the case under
  `QT_QPA_PLATFORM=offscreen` inside the observed §4.7 capability boundary
  (offscreen never rasterizes custom `QSGGeometryNode`s); anything that needs
  real activation/modal behavior or custom-geometry raster output and cannot
  be proven lands in §9 as retained-native residual. DPR is not in that set:
  the legacy DPR row rides a host-injected seam (§6.6, §9 closed).
- Duplicate contracts: exactly one implementing owner; everyone else
  crosslinks (§8). No boolean-callback legacy wrappers; no assertion-free test
  bodies.
- Paint oracle parity: offscreen cases assert retained curves/nodes,
  revisions, text records, and frozen documents. The separate native runner
  preserves the original curve/node framebuffer colors and selection-ring
  pixels. Previews assert `AutomationTransient` + frozen document, pencil via
  its transient text-record rectangle (not row-count), and edit cursor via
  `editRootContentX`/`editVisible` + frozen document.

## 6. Contract ledger — `src/checks/automationgesturecheck/`

Status: P = proven offscreen; N = retained native; P / N = split contract (§2). After the
root review fixes (real adapters, common `automation_test` transforms,
`FrozenDocumentState`, shared retained color/ring probes, modal menu driver)
and the double-click guard repair (§6.4 note), the full safe gate passes —
recorded PASS 5/68: the four new Qt suites plus the legacy popup harness,
every verify with `--no-windowing-checks`. Main's 2026-09-05 per-row
isolation run then completed the
replacement proof gates: all 182 rows PASS individually (editing 131 / domain
24 / presentation 16 / hover 11), all four suites PASS with reversed data-row
order (133/26/18/13 Qt results, wall 469.96s), targeted production mutation
controls failed the expected slots and passed after restore (§2; §7.4
half-open row), and root Qt + thermo-nuclear source rechecks PASS (baseline
citations `7430fb4`). **The `St` cells record the final status. P / N marks
a proven offscreen portion plus an original pixel oracle preserved in the
compiled, source-reviewed `automation-raster` runner, deliberately not
executed natively (§9).** Main's cutover batch then removed the
legacy family and registered `automation-raster` (§10/§11); the cutover
compile + safe lane and the restored-normal final gate both PASS
(`deno task verify --no-windowing-checks --verbose`: 61/66 ok, 5 native
skips, 0 fail; final run build 32.48s, suite 4.01s), and ASAN+UBSAN passed
the automation filter (4/66 ok, 0 fail; flags verified, then restored
exactly). The 5 skips are the `WindowSystem` rows: native execution is the
deliberate §9 boundary, not an incomplete migration.

### 6.1 `transactions.cpp` (425L) — AutomationPencil (automationpencil.cpp)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `77-108` `runEmptyLane` | Add empty CC11 lane → valid row; pencil stroke over 3 cells commits exactly 1 SMF revision + 1 undo step and inserts lane points | `pencilStrokeOnEmptyLaneCommitsOnce` (Pencil) | P |
| `110-148` `runLfoTitle` | Adding an empty lane preserves the existing LFO gutter title (exact before/after crop equality on the LFO title — `transactions.cpp:153-156`, a text/standard-QML render that holds offscreen, not a §9 native residual; plus exact label/placement); all row IDs stay strictly unique | `addingEmptyLanePreservesLfoSemanticTitleAndUniqueRows` (Chrome, presentation) | P |
| `150-176` `runPreview` | Pencil press+drag renders live transient preview while SMF/revision/undo/points stay frozen; release commits exactly one edit | `pencilPreviewDoesNotMutateUntilRelease` (Pencil) | P |
| `178-202` `runRestore` | Stroke across a held value terminating at a cell boundary restores the held baseline at `cell.tickEnd` in 1 edit | `pencilStrokeRestoresHeldEndpointValue` (Pencil) | P |
| `204-250` `runTempoTailRestore` | Pencil click (200 BPM) on empty Tempo lane paints a node at `cell.tickBegin` plus an automatic restoration node at `cell.tickEnd` at default 120 BPM, 1 edit | `pencilSingleClickOnTempoLaneRestoresDefaultTempoAtCellEnd` (Pencil) | P |
| `252-288` `runBendTailRestore` | Pencil click (4096) on empty Pitch Bend lane paints at `tickBegin` + restores center 0 at `tickEnd`, 1 edit | `pencilSingleClickOnPitchBendLaneRestoresCenterAtCellEnd` (Pencil) | P |
| `291-314` `runFlat` | Stroke along an already-held value, or a stationary click on one, produces zero SMF/revision/undo/point mutation (semantic no-op on existing value) | `pencilFlatStrokeAndRedundantClickAreNoOps` (Pencil) | P |
| `316-350` `runDelete` | Stationary click on an excursion node (spike back to held) deletes the excursion in 1 edit, baseline kept | `pencilClickOnExcursionNodeDeletesExcursion` (Pencil) | P |
| `352-398` `runCancellations` | In-flight pencil stroke cancelled via Escape / SongView hide / WindowDeactivate / `documentChanged` commits 0 edits at release — 4 data rows | `pencilCancellationRoutesAbortGestureWithoutCommit_data` + slot (Pencil) | P |

### 6.2 `stroke.cpp` (526L) — AutomationPencil (automationstroke.cpp)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `112-146` `runJitter` | Sub-cell horizontal jitter (< activation distance) during a stroke creates no false steps and does not alter held values across 3 snap cells | `pencilSubCellHorizontalJitterDoesNotAlterStroke` | P |
| `148-185` `runZigzag` | Fast 6-cell zigzag preserves directional peaks/valleys within ±1 quantization | `pencilZigzagStrokePreservesDirectionalExtrema` | P |
| `187-208` `runVertical` | Vertical scrub inside one snap cell retains the latest vertical position at release | `pencilVerticalMotionInSingleCellRetainsFinalValue` | P |
| `210-332` `runDiagonal` | Diagonal stroke yields identical held values for sparse vs dense pointer streams at zooms 96/256/512 plus the canonical 96x staircase — data rows | `pencilDiagonalStrokeEventDensityInvariance_data` + slot | P |
| `334-361` `runRevisit` | Backtracking stroke (A→C→A) retains the furthest value in C, overwrites A with the latest value, keeps monotonic tick order | `pencilBacktrackingStrokeRetainsExtremaAndLatestRevisit` | P |
| `363-408` `runShift` | Shift mid-stroke locks the value dimension at the moment Shift engaged | `pencilShiftModifierLocksValueDimension` | P |
| `410-474` `runCommand` | Ctrl/Cmd bypasses cell snap, places events at raw clock ticks; forward/reverse sparse+dense streams converge | `pencilControlModifierDrawsUnsnappedClockQuantizedPoints` | P |
| `476-508` `runMixed` | Releasing Ctrl mid-stroke composes seamlessly: freehand detail then snapped cells | `pencilMixedModifierComposesFreehandAndSnappedSegments` | P |
| `510-525` `runAlt` | Alt stroke output identical to unmodified stroke | `pencilAltModifierIsIgnoredDuringStroke` | P |

### 6.3 `crosslane.cpp` (650L) — AutomationSelection (UI) / AutomationDomain (XCMD)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `173-238` `runBandIsolation` | Right-drag marquee from Tempo lane selects only Tempo and edits only Tempo; right-drag in a CC lane selects only that CC, excluding Tempo | `bandSelectionIsolatesTempoAndControlChangeRows` (Selection) | P |
| `279-346` `runTempoPanLfo` | Tempo+Pan+LFO selection: Shift-drag moves all 3 by shared delta in 1 edit; Tempo microseconds exact; Pan overwrites destination occupant and keeps same-tick order {10,20}; Delete removes selected points in 1 edit; Delete over empty range is a no-op | `multiLaneSelectionDragPreservesTempoAndCcOrder` + `multiLaneSelectionDeleteAndEmptyDeleteNoop` (Selection) | P |
| `348-383` `runStaleBatch` | `documentChanged` during in-flight multi-lane drag aborts it: release commits 0 edits, document unchanged, selection range preserved | `multiLaneSelectionDragAbortsOnDocumentRebuild` (Selection) | P |
| `385-418` `runPanLfoRangeEdit` | Pan+LFO-only selection (`tempo = false`): Tempo untouched, both lanes move by shared delta in 1 edit, occupant overwritten, Volume untouched | `multiCcLaneSelectionDragExcludesTempoAndVolume` (Selection) | P |
| `496-532` `runXcmdRemoveOnly` | `applyRangeEdit` removing XCMD descriptor points (echo volume/length) commits 1 edit, keeps survivors, rebuilds the raw CC stream with no dead selector bytes | `xcmdRangeRemoveOnly` (Domain) | P |
| `534-593` `runXcmdRangeMoves` | `moveRange`: move into the length epoch rebuilds both epochs as explicit pairs; move onto a payload tick rebuilds the destination without duplicate selectors | `xcmdRangeMoves` (Domain) | P |
| `595-618` `runXcmdExpansionPaste` | `RangeEdit` with `minimumEngineTrackCount` expansion creates the new track and builds a canonical selector/payload epoch from scratch | `xcmdExpansionPaste` (Domain) | P |

### 6.4 `parity.cpp` (560L) — AutomationParity (automationparity.cpp / automationnodedrag.cpp) — owner-declared live ranges; every case is Tempo **and** CC data rows unless noted

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `196-203` `runHoverInsertion` | Pointer hover over empty plot mutates nothing (SMF/revision/undo frozen), both adapters | `hoverInsertionDoesNotMutateDocument_data` + slot | P |
| `205-222` `runClickDelete` | Stationary click on a node deletes it in 1 edit; double-click after delete commits 0 and opens no dialog; Shift+click does not delete. Ownership split (review-corrected): `stationaryNodeInteractions_data` + slot owns the single-click delete (revision/undo +1, remaining fixture intact) and the Shift+click frozen-document half; `doubleClickDeletesOnceWithoutValueDialog_data` + slot owns the double-click half — a complete two-click `mouseDClick` sequence on a fresh node deletes exactly once (1 `documentChanged`/`edited`, revision/undo/count +1) and opens no dialog; `independentDoubleClickAfterDeleteOpensValueDialog_data` + slot is the added inverse guard — a later double-click on the vacated spot opens the valid insertion `QInputDialog`, and Cancel leaves the document frozen (all three Tempo + CC) | three Parity slots (see note below) | P |
| `224-280` `runNodeDrag` | Plain drag moves node in time+value in 1 edit; Shift-drag axis locks (H locks value, V locks time); Tempo microseconds exact; CC same-tick group keeps event order {10,20}. Axis rows: four exact adapter/axis rows | `nodeDragCommits_data` + slot, `nodeDragShiftAxisLocks_data` + slot | P |
| `282-299` `runSelection` | Dragging a selected range shifts all selected nodes by delta in 1 edit and updates the selection model; Delete removes the range in 1 edit | `selectedRangeDragAndDelete_data` + slot | P |
| `301-326` `runSweepRamp` | Freehand sweep across empty area inserts points along the path in 1 edit; Shift-drag creates a linear ramp in 1 edit; sweep activates only beyond the activation distance (roll `817-820` boundary retained here) | `sweepAndRampCommit_data` + slot | P |
| `328-345` `runPencil` | Persistent-pencil stroke preview freezes the document; release commits 1 edit creating the points | `pencilPreviewCommits_data` + slot | P |
| `347-371` `runBandSelect` | Right-click band drag publishes a time selection scoped to Lanes with snapped start/end (tempo flag / track-controller per adapter); roll `1292-1295` commit semantics retained here | `laneBandSelectsRange_data` + slot | P |
| `373-388` `runEscapeCancel` | Escape during node drag cancels: document unchanged, rig idle, post-escape release commits nothing | `escapeCancelsAdapterDrag_data` + slot | P |
| `390-424` `runRebuildCancel` | `documentChanged` or a viewport-geometry rebuild cancels an in-flight drag; roll `1733` documentChanged route retained here; a subsequent drag commits normally in 1 edit | `rebuildCancelsAdapterDragAndRecovers_data` + slot | P |
| `426-441` `runSemanticNoOp` | Click on empty lane space commits 0 edits; sub-threshold drag (`slop - 1` px) commits 0 edits and alters no points — **not pilot-covered** (§4.1); roll `784-786` retained here | `blankAndSubThresholdNoOps_data` + slot | P |
| `443-498` `runOriginPhantom` | Scrolled-past origin: hover at x=0 keeps the real `TimelineInputItem` ArrowCursor; drag from x=0 shows positive transient spans; release commits 1 edit to the offscreen origin node | `scrolledOriginPhantomCommits_data` + slot | P |

Parity double-click note (review-corrected, source-verified): Qt 6.11
`QTest::mouseDClick` on a `QWindow` sends **two complete clicks** — press,
release, then a second press delivered as `MouseButtonDblClick` with its
release (qtestmouse.h 69-119: `case MouseDClick:` emits a press/release pair
and falls through to the second press/release pair) — and the default-delay
tail bumps the injected timestamp past `mouseDoubleClickInterval` after each
sequence, so a **later** click sequence starts clean instead of chaining
(the QTest default release separates later sequences). The AET fixture
replays this through `mouseDClick` → `QTest::mouseDClick(m_quickWindow, …)`
(automationfixture.cpp:504-511); legacy asserted the same contract with a
raw `MouseButtonDblClick`+release pair (rollcheckautomation.cpp:949-952). The
full sequence is what exposed a real production bug, proven fail-before /
pass-after (not an inverted oracle): before the repair, the fresh-node
full-sequence slot failed its no-dialog assertion in **both** Tempo and CC —
the second press of the same double-click cleared the just-marked
`NodeDoubleClickGuard`, so the value `QInputDialog` opened — while the
independent later double-click slot (single-click delete, then a separate
double-click on the vacated spot that must open the insertion dialog) passed
in the same pre-fix runs. The repair moved `NodeDoubleClickGuard::clear()`
from press to release-before-finish (`AutomationCanvas::pointerRelease`
clears on entry, `finishActiveGesture` re-marks on a stationary delete,
`pointerDoubleClick` consumes — automationcanvas_input.cpp:380-382/:477,
automationcanvas_gesture.cpp:297); the same two focused slots × Tempo/CC
then PASS 6/0 — four body rows plus `initTestCase` and `cleanupTestCase`.
Legacy itself only ever asserted this click-sequence contract;
no native double-click requirement is inferred.

### 6.5 `action.cpp` (151L) — AutomationOwnership (automationactions.cpp)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `37-51,67-99` | Pencil `QAction` checkable, starts unchecked, trigger toggles; shortcut press latches ON (release stays), second press clears — legacy asserted both view-target and window-target routes and the hard-coded `Key_B` default/wording; owner routes both through the single real-window path and drops the default-binding/wording assertions (**§8 approved**: configured-shortcut behavior replaces incidental defaults; the real-window route exercises the application route — **not a two-target proof**) | `actionShortcutLatching` | P |
| `55-64` | Typing 'B' into a focused `QLineEdit` enters text and does not trigger the action | `actionTextInputImmunity` | P |
| `100-109` | Auto-repeat press/release does not re-trigger or alter state — uses the landed `keyEvent(..., autoRepeat)` seam | `actionRepeatImmunity` | P |
| `110-127` | ~510 ms hold then release does not revert the toggle; a mouse gesture while held does not revert on key release | `actionHeldKeyGestures` | P |
| `129-133` | Programmatic `QAction::trigger()` persistently toggles — discarded as implementation-only duplicate of the state effect (**§8 approved**: the real-window route exercises the application route; **not a two-target proof**) | folded into `actionShortcutLatching` | P |
| `134-150` | Custom `Ctrl+B` binding activates and toggles | `actionCustomBinding` | P |

### 6.6 `cursor.cpp` (97L) — AutomationChrome (presentation suite)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `19-23` | Fixture exposes pan handle + non-empty body | setup precondition (fixture note, no slot) | — |
| `35-71` | Pencil mode over editable CC plot installs the bitmap pencil cursor; gutter, row boundary (`SplitVCursor`), add-lane strip, and tempo header keep standard cursors; expanded tempo plot shows the bitmap cursor too | `pencilCursorUsesPlotGutterBoundaryAndTempoPrecedence` | P |
| `78-90` | Doubling the host DPR must double the pencil cursor pixmap `devicePixelRatio`, and restoring the host DPR restores the original ratio (1→2→1). Legacy asserts **only this ratio** through the `TimelineInputHost::devicePixelRatio` seam (`cursor.cpp:78-90`: ratio doubled, `canvasHostAppearanceChanged`, re-move, ratio restored) — a host-interface seam, **no OS involved**. Earlier extent (`qRound(16*dpr)`) and logical-hotspot claims were false — legacy asserts neither — and are removed. Split: real-path installation at DPR 1 → `pencilCursorUsesInputDevicePixelRatio` (Chrome; pixmap DPR == input DPR; pins wiring, does NOT cover the scaling law); scaling law → `pencilCursorScalesWithInjectedDevicePixelRatio` (Chrome, presentation suite): test-local `CursorDprHost` + RAII `ScopedAutomationInputHost` swap, DPR 1→2→1 driven through the public `canvas->pointerMove` path; pixmap `devicePixelRatio` follows 1.0→2.0→1.0. Executed green in Main's offscreen isolated gate — host-injected seam, **not native**; §9 row closed; still a §10 gate matter, never coverable by the DPR-1 row (§8) | `pencilCursorUsesInputDevicePixelRatio` + `pencilCursorScalesWithInjectedDevicePixelRatio` | P |
| `83-87` | Pencil off restores `ArrowCursor` over the plot | `pencilCursorTurnsOffToArrow` | P |

Crosslink: `ownership.cpp:158-170` (SplitVCursor precedence under pencil mode)
is covered by `pencilCursorUsesPlotGutterBoundaryAndTempoPrecedence` — Ownership
does not duplicate it.

### 6.7 `mapping.cpp` (127L) — AutomationOwnership

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `17-26` | Snap grid keeps the final partial cell at timeline end (`tickBegin < tickEnd == lengthTicks`) | `projectionPartialCell` | P |
| `27-44` | CC value bounds 0/127 map exactly to `mapped.point.value`; `valueAtY` inverts | `projectionValueBounds` | P |
| `45-59` | CC row 0 body begins at `top() == 0`; pointer y in `[top,bottom)` resolves onto row 0 | `projectionCanvasOrigin` | P |
| `64-85` | Fine-grid insertion indicator sits between tick boundaries; `insertionTick(true)` = mapped point tick, `insertionTick(false)` = caret snap tick | `projectionInsertionTiming` | P |
| `87-126` | Pencil click quantizes to the mapped cell `tickBegin`/value; an exact cell boundary commits to the following cell without altering the preceding one | `pencilClickHalfOpenQuantization` | P |

Architecture flag: `projectionPartialCell`/`ValueBounds`/`InsertionTiming` (and
the threshold half of §6.8's precedence case) are GUI-free — keep the AET slot
as declared but crosslink to AutomationDomainTest coverage; never cover the same
assertion twice.

### 6.8 `ownership.cpp` (349L) — AutomationOwnership

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `60-110` | Tracks-scope selection paints rings on nodes 48/96/144 in `[24,192)`; endpoint 192 gets none (half-open). Legacy framebuffer-capture availability checks are setup, not the oracle — retained Quick ring geometry is | `tracksSelectionRings` | P |
| `112-155` | Alt-drag moves the selected set together (48→72, 96→120, 144→168), node 192 intact, 1 edit, selection time range shifts, undo/redo restores | `tracksSelectionGroupDragUndo` | P |
| `158-170` | Gutter row-boundary `SplitVCursor` precedence under pencil mode | covered by Chrome `pencilCursorUsesPlotGutterBoundaryAndTempoPrecedence` (crosslink) | P |
| `172-193` | Toggling pencil mode via 'B' during a held pencil stroke does not drop ownership; stroke commits | `pencilModeChangeRetainsPencilGesture` | P |
| `194-238` | Same during a held normal node drag; drag commits | `pencilModeChangeRetainsNodeGesture` | P |
| `240-256` | Pencil stroke starting outside the active time selection clears the selection | `pencilStrokeOutsideSelectionClearsSelection` | P |
| `258-348` | Node markers hidden below `pointDetailThreshold`, visible at/above; hidden nodes pass through (no grab, pencil strokes through); visible nodes take drag precedence over pencil drawing; visible click takes delete precedence over insertion | `detailThresholdHiddenVisibleNodePrecedence` | P |

### 6.9 `contract.cpp` (1013L) — AutomationDomainTest (AutomationDomain; domain/tst_automationdomain.*, xcmd.cpp, gestures.cpp)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `226-248` `checkEffectivePoints` | Empty lane → empty points; Tempo points tick-sorted; CC keeps same-tick raw order and exposes the effective last value — data rows | `effectivePoints_data`/`effectivePoints` | P |
| `250-323` `checkRangesTextSelection` | Translated title; min/max ranges incl. pitch bend; `valueText()` formats; fractional tempo BPM rounds; `LaneSelection` tracks active tick range and `coversLane()` — data rows | `rangesAndSelection_data`/`rangesAndSelection` | P |
| `325-365` `checkDelete` | Empty/unknown-tick delete are no-ops; deleting a point removes 1 point in 1 edit; CC same-tick delete removes all raw events; undo/redo restores — data rows | `deletes_data`/`deletes` | P |
| `367-424` `checkMove` | Empty/unknown move no-ops; Tempo move with unchanged value preserves exact microseconds, new value recalculates; CC same-tick move relocates the whole ordered group; undo/redo — data rows | `moves_data`/`moves` | P |
| `472-510` `checkMoveCollision` | Tempo move onto an occupied tick replaces it and keeps source microseconds; CC move replaces destination events with the moved group, no duplicates; undo/redo — data rows | `moveCollisions_data`/`moveCollisions` | P |
| `426-470` `checkReplaceSpan` | Empty replaceSpan no-op; span replace 1 edit; identical replace no-op; multi-point/clearing 1 edit; fractional tempo microseconds; undo/redo — data rows | `replaceSpans_data`/`replaceSpans` | P |
| `513-572` `checkEngineDefaultNodes` | Empty Volume lane synthesizes default node {0,127}; Pan {0,64}; other lanes none; Modulation/Bend expose implicit held lead-in 0; moving a synthetic default promotes it to a real point in 1 edit; undo restores the synthetic default | `defaultNodePromotion` | P |
| `620-756` `checkLogicalXcmdOccurrences` | Explicit selector+payload pair for every echo point (0x08/0x09); deleting one rebuilds the survivor; deleting the last leaves no protocol bytes; moves rebuild survivor+destination; disjoint-epoch moves rebuild both; writes inside an opaque epoch span rejected atomically; malformed/multi-byte fragments preserved byte-identically; stray-payload consumption rejected | `xcmdOccurrencesAndOpaqueProtection` | P |
| `758-819` | Lane-scoped time cut removes only the targeted echo lane point; whole-song cut rebuilds shifted survivors as explicit pairs; undo byte-identical | `xcmdTimeRangeCuts` | P |
| `822-867` `checkLogicalXcmdEdits` | Multi-lane echo writes emit canonical ordered XCMD pairs; moving a logical echo lane preserves framing; undo restores SMF | `xcmdCanonicalEdits` | P |
| `870-911` `checkXcmdSweepPreservesNotes` | Cross-measure `replaceSpan` on Echo Volume across Note-On/Off preserves every note event | `xcmdSweepPreservesNotes` | P |

Excluded from Domain by owner: `checkRowRebuildHandles` (GUI static — Hover, §6.10)
and all crosslane GUI selection scenarios (Selection, §6.3). Crosslink:
`crosslane.cpp:496-618` (§6.3) exercises the same XCMD protocol through the
document `applyRangeEdit`/`moveRange`/expansion APIs and raw SMF rebuild —
related seam, distinct oracles; both stay, crosslinked.

### 6.10 `hover.cpp` (610L) — AutomationHover suite (hover/tst_automationhover.cpp) — owner-declared live ranges

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `331-339` | Native Quick host input flags (transport plumbing) + input-host accessibility description. Input flags dropped (**§8 approved**: consumer-visible behavior is asserted by `directInputHostRouting` through a real `QQuickWindow` move — chrome, root coordinate, retained layer, held ghost, viewport-clipped value text, no mutation). Accessibility description: metadata-only legacy check, **not** functional accessibility proof — dropping it changes no user-facing accessibility behavior, and this makes **no** claim that the new suite replaces accessibility testing (§8) | dropped (input flags) / metadata-only legacy check (accessibility) | — |
| `345-375` | Direct pointer input publishes the hover guide (visible, x within 1px), rebuilds the hover layer with held-value insertion point + value text, mutates nothing | `directInputHostRouting` | P |
| `377-388` | Pointer leave clears the hover layer completely and resets the cursor through the host | `leaveClearsRetainedHover` | P |
| `390-413` | FocusLost while pressed does not release the pointer grab (menu interaction preserved) | `focusLostKeepsGrab` | P |
| `415-432` | WindowDeactivated releases the grab, clears hover chrome, rig idle, document untouched. §9 gate closed — not native: legacy drives the injected `inputCancelled(TimelineInputCancelReason::WindowDeactivated)` route directly (hover.cpp:417); the replacement uses the identical seam (tst_automationhover.cpp:126-127), so parity is by construction and no OS focus equivalence is claimed | `deactivationClears` | P |
| `434-447` | Cancellation does not latch hover off; a later move restores the guide | `hoverRevivesAfterCancellation` | P |
| `449-457` | Hidden/PointerUngrabbed cancellations while idle are clean no-ops | `idleCancellationsDoNotMutate` | P |
| `460-507` | Inter-node hover (Tempo/CC): insertion line + held-value ghost node + value text; document untouched — data rows; pixel half §9-gated (retained half proven) | `guideGhostTextAndRing_data` + slot | P / N |
| `509-515` | Repeated moves at the same coordinate do not churn Quick state | `repeatHoverDoesNotChurn` | P / N |
| `517-542` | Existing-node hover: node ring + value text; insertion ghost suppressed — data rows; pixel half §9-gated (retained half proven) | `guideGhostTextAndRing_data` + slot | P / N |
| `544-565` | Lane transition and canvas leave fully clear the dirty hover layer and framebuffer pixels — pixel half is a retained-native residual (§4.7/§9): the software backend never rasterizes the hover chrome, and a non-null capture without it proves nothing | `leaveClearsRetainedHover` (fka `leaveClearsHoverPixels`, declared) | P / N |
| `569-609` | Tempo and CC hover topology match | `tempoAndCcTopologyMatch` | P |

### 6.11 `lifecycle.cpp` (60L) — AutomationRouting

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `17-23,28-54` | CC row 0 owns the canvas origin (`body.top() == 0`) after voice-strip extraction; top-of-row pencil click (tick 240) commits exactly 1 point + 1 undo step; a document rebuild preserves the origin; undo restores SMF and the origin | `firstCcRowOriginRebuildAndUndo` | P |

Crosslink: `mapping.cpp:45-59` (`projectionCanvasOrigin`, §6.7).

### 6.12 `routing.cpp` (520L) — AutomationRouting (automationvoice.cpp / automationrouting.cpp)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `133-165` | Voice-change horizontal drag: preview updates, `SizeHorCursor`, release commits 1 "change voice" edit moving the marker (24 → target); undo restores the document byte-for-byte (revision + undo-stack index/count asserted). Only the undo-command-text string is dropped (**§8 approved**: the byte-for-byte undo oracle is the consumer contract; the command label was incidental) | `voiceHorizontalPreviewCommitsAndUndoes` | P / N |
| `166-194` | Stationary voice-marker click is a no-op; vertical movement within `startDragDistance` neither activates nor retimes; drag in empty voice space never arms | `voiceStationaryVerticalJitterAndEmptySpaceDoNotCommit` | P |
| `195-226` | Alt voice drag uses fine snapping (`fineTick != normalTick`) | `voiceAltDragUsesFineSnap` | P |
| `227-256` | Voice destination collision replaces the destination marker; stale revision (external mutation mid-drag) makes release reject the commit | `voiceCollisionAndStaleRevision` | P |
| `257-282` | Escape and PointerUngrabbed each cancel the voice gesture completely (Arrow cursor, no mutation) | `voiceEscapeAndUngrabCancel` | P |
| `283-350` | Two voice events at tick 48: dragging moves exactly one occurrence; undo restores both | `voiceDuplicateOccurrenceMovesSingleIdentity` | P |
| `352-369` | Middle-button press enters pan state exclusively; no document mutation, no edit-cursor move; release restores idle | `middlePanIsolated` | P |
| `370-384` | Voice press stops at the voice lane (tempo body and lane heights untouched) | `voicePressIsolated` | P |
| `385-400` | Tempo gutter header press toggles expansion exclusively; no document/cursor mutation | `tempoHeaderExpansionIsolated` | P |
| `403-432` | Dragging a gutter boundary resizes only the targeted row; no document/cursor mutation; release restores idle | `rowResizeChangesOnlyTarget` | P |
| `433-453` | Body-right click enters band preview state only; no mutation; cancel restores idle | `rightBandPreviewIsolated` | P |
| `454-494` | Pencil click commits only to the target CC lane; LFO/Volume/Voice/Tempo untouched; heights and cursor unchanged | `pencilEditTargetsOnlyItsLane` | P |
| `495-519` | Default body click sets the edit cursor to the snapped tick; no mutation | `defaultBodyClickSetsCursorOnly` | P |

### 6.13 `contract.cpp` row handles (`913-971`) — AutomationHover

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `913-971` `checkRowRebuildHandles` | Initial handles resolve Tempo/Pan/LFO identities; arming a gesture on a stale handle mutates nothing; adding an empty lane mid-gesture updates handle ordering (LFO index bumped) and preserves the Tempo body; invalid handles resolve empty; release after the rebuild commits no stale handle; removing the lane restores the original mapping | `rowRebuildStaleReleaseDoesNotMutate` (Hover) | P |

## 7. Contract ledger — `rollcheckautomation*.cpp`

Removed 2026-09-05 in Main's cutover batch (22 legacy files total across
§6+§7); the rows below remain the historical contract record (baseline
`7430fb4`), now carried by the replacement suites and the `automation-raster`
residual row.

### 7.1 `rollcheckautomation.cpp` (1,818L) — mixed owners

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `313-467` | Automation band published in `timelineBandLayout()`, input items + `TimelineQuickScene` exposed; scrollbar chrome rect valid/Two-wide/in Quick host, item visible; zero-range viewport fills thumb == track == viewport == content and survives resize; Quick host contains the gutter unclipped; plotRect starts at `timelineSplitX`, excludes the left scrollbar, aligns with the roll grid; input items match physical spans and scene rects | `automationBandAndInputsExposed` + `scrollbarChromeTracksZeroRangeResize` + `layoutAlignsPlotGutterAndRollGrid` (CanvasEditing) | P |
| `481-482` | Middle-mouse pan on the plot: ClosedHand cursor, pans display x by 48px, survives scroll refresh | `middleMousePanSurvivesRefresh` (CanvasEditing; crosslink §6.12 `middlePanIsolated`) | P |
| `494-523` | Domain sweep: `extendSweepPoints` interpolates 0..10→0..100 without `std::function`; `SweepGesture::update` forwards; `Mode::Ramp` finish steps via `nextGridTick` | `sweepSteppingAndRampFinish` (Domain) | P |
| `527-573` | Domain neutral snap: `updateValuePoint(snapValue)` snaps pan values within `neutralSnapRadius` to 64, preserving tick/value at neutral | `panNeutralSnap` (Domain) | P |
| `582-650` | Domain gesture outcomes: empty finish NoOp; Shift stationary NoOp; non-shift stationary StationaryDelete; move past slop Move with `dTick`; multi-node shared delta; PhantomGesture reset restores source, drag clamps [0,127] preserving tick | `nodeDragAndPhantomOutcomes` (Domain) | P |
| `656-700` | Domain `NodeLaneEdit`: identical range unchanged; different changed; `replaceHeldSpan` restores boundary endpoint; `AutomationPencilGesture` restores held value; flat replacement no-op; empty deletion changed | `pointRangeAndPencilReplacements` (Domain) | P |
| `705-749` | Row stack: first CC row at top 0, no voice inset, voice changes omitted, Tempo row not in generic rows, hidden Volume omitted, Pan/LFO present (LFO range 91), Bend last; grid `gridTicks/snapTicks > 0`, hover snaps 0.1–0.4 within cell, 1.1 to next tick | `rowStackAndGridResolution` (CanvasEditing) | P |
| `769-771` | Stationary click on empty lane parks the edit cursor; SMF/revision/undo unchanged | **verified pilot** `releaseWithoutActivationDoesNotCommit` | P |
| `776-786` | Sub-threshold jitter (slop−1 px) leaves SMF/revision/undo unchanged — **NOT pilot-covered** (§4.1) | `blankAndSubThresholdNoOps_data` (Parity — single asserting owner) | P |
| `790-800` | Moving exactly `activationDistance` consumes the slop without applying movement | `activationSlopDoesNotCommit` (CanvasEditing) | P |
| `801-820` | Moving 1px beyond slop starts a sweep; commits at snapped tick + projected value; revision/undo +1 | `sweepAndRampCommit_data` (Parity — duplicate slot removed; boundary assertion retained there) | P |
| `850-924, 1087-1132` | Point popup `["Set Value","Delete"]`; "Set Value" opens a modal `QInputDialog` parented to SongView; accepted value updates only the clicked same-tick occurrence — modal proven offscreen (§9 modal row: the legacy popup harness passes offscreen driving this exact queued-menu → dialog flow; the replacement shares the driver shape) | `pointMenuNumericDialogUpdatesOneDuplicateOccurrence` (Popups; joint migration — real menu selection, dialog discovery/parentage) | P |
| `927-955` | Left-click deletes a node (count−1, revision/undo +1, no dialog, :910-939); double-click after delete opens no value dialog and bumps nothing (legacy drives a raw `MouseButtonDblClick`+release pair, :940-955) | single-click + Shift halves → `stationaryNodeInteractions_data`; double-click half → `doubleClickDeletesOnceWithoutValueDialog_data` (full real-window two-click sequence: one delete, no dialog); added inverse guard `independentDoubleClickAfterDeleteOpensValueDialog` (later insertion dialog opens; Cancel leaves state unchanged) — all Parity, proven (§6.4 note) | P |
| `967-992` | Row-boundary hover sets `SplitVCursor` with no insertion preview painted — **pixel half gated (§9)**; add empty lane preserves existing title, publishes new title in `TimelineQuickTextModel`, rebuilds `AutomationGrid`, keeps row IDs unique | `boundaryHoverAndEmptyLaneUpdateTextAndGrid` (CanvasEditing; crosslink Chrome cursor precedence + LFO-title case) | P / N |
| `1010-1028` | Point-menu "Delete" removes the point in 1 undoable edit | `pointMenuDeleteCommitsEdit` (Popups) | P |
| `1047-1059` | Same-tick duplicate drag moves BOTH points as a group to the new tick, values preserved | `nodeDragCommits_data` (Parity — CC same-tick order rows; single asserting owner) | P |
| `1145-1218` | Right-click outside dismisses the point menu; the targeted action still deletes only its designated point | `outsideRightClickDismissesPointMenu` (Popups) | P |
| `1221-1248` | Drawer page switch Velocity→automation and back preserves `emptyLanes`, `laneHeights`, `laneRanges`, `hiddenLanes` | `viewStateSwitchPreservesAutomationState` (CanvasEditing) | P |
| `1260-1278` | Plain wheel zooms time (`pxPerBeat` up) preserving the tick under the cursor; Ctrl-wheel in the gutter grows `laneHeight` leaving other view state untouched | `wheelZoomAndCtrlWheelRowHeightPreserveDrawerState` (CanvasEditing) | P |
| `1292-1295` | Right-drag commits an active half-open time selection (`scope == Lanes`, one lane) | `laneBandSelectsRange_data` (Parity — single asserting owner) | P |
| `1308-1314` | Right-click inside an active selection opens the menu with "Clear time selection" | `selectionContextMenuRoutesInsideActiveSelection` (Popups) | P |
| `1318-1378` | Left/right click outside, lane-header click, and Escape clear a steady-state selection; row rebuild does not resurrect it; non-contiguous lane selection (pan, bend) is retained; Escape clears to tracks scope | `selectionClearingAndMultilaneReplacement` (CanvasEditing; crosslink Ownership stroke-clears-selection) | P |
| `1380-1507` | Half-open selection rings: `[A,B)` highlights only A; `[A,B+1)` both; `AutomationNodes` revision advances. Exact raster evidence (source-verified :1424-1505): two captures — excluded `[A,B)` framebuffer (:1428), included `[A,B+1)` framebuffer (:1433); the closing check (:1495-1505) asserts retained-layer negatives for excluded B/C plus exactly THREE positive framebuffer probes — A in the excluded capture, A in the included capture, B in the included capture. **No negative framebuffer probe exists** (B/C exclusion is retained-layer only; the earlier scout's claimed negative pixel-B test was false) — pixel half owned by the `automation-raster` row. Replacement negative control (2026-09-05 isolation run): production `pointSelected` boundary `<lastTick`→`<=lastTick` failed this slot (excluded-second ring appeared) and passed again after restore | `halfOpenTimeSelectionComposesNodeRings` (fka `halfOpenTimeSelectionRendersNodeRings`, declared) (Paint; crosslink `selectionRingsAndReticlesComposed`) — proven on the retained/CPU half; pixel half carried by the compiled, source-reviewed, deliberately-unexecuted `automation-raster` row | P / N |
| `1518-1608` | Multi-node group drag shifts all selected nodes by the shared delta, unselected untouched, 1 edit, selection follows, undo restores; Delete/Backspace delete selected nodes as one edit; undo restores | `selectedRangeDragAndDelete_data` (Parity — single asserting owner) | P |
| `1676-1712` | Shift axis-lock: horizontal travel shifts ticks preserving exact values; vertical changes values keeping ticks; undo restores | `nodeDragShiftAxisLocks_data` (Parity — single asserting owner; pencil variant is Pencil's `pencilShiftModifierLocksValueDimension`) | P |
| `1733-1753` | Six cancellation routes discard an in-progress drag with no document/undo mutation — data rows: explicit `cancelInteraction`, UngrabMouse, WindowDeactivated, page hide → new slot; Key_Escape → pilot (V); `documentChanged` → parity `rebuildCancelsAdapterDragAndRecovers` | `additionalDragCancellationRoutesLeaveDocumentUntouched_data`/slot (CanvasEditing, 4 rows) | P |
| `1764-1775` | Voice context: playback follows the rounded playhead (slot 0); stopped playback uses the edit cursor (slot 3). §9 gate closed — not native: legacy drives injected transport state (`live.playback = {playhead, true}` + `page.refreshLiveState`, :1758-1770); the replacement drives the same seams (`DrawerPageLiveState.playback` + `VelocityArea::refreshLiveState`, `view.setPlayheadSample`, automationcanvasediting.cpp:220-243) | `voiceContextFollowsPlaybackOrEditCursor` (CanvasEditing) | P |
| `1782-1787` | Teardown restores the SMF baseline; clearing undo preserves configured `laneRanges`/hidden state | fixture `cleanup()` discipline (no slot) | — |

### 7.2 `rollcheckautomation_tempo.cpp` (248L) — AutomationChrome (presentation)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `116-121` | Collapsed Tempo lane: `LaneHandle{0}` body empty; `pinnedTempoRect().height() == addLaneStripHeight`; pinned to viewport bottom | `collapsedTempoGeometryIsPinned` | P |
| `129-134` | Clicking the collapsed header expands Tempo to the configured height, matching the pinned rect, raising `minimumContentHeight()` | `headerClickExpandsTempoToConfiguredHeight` | P |
| `150-163` | Wheel scroll to max shifts content under a pinned tempo (content page y invariant; CC lanes scroll beneath). Source-verified: the legacy capture check (`rollcheckautomation_tempo.cpp:179-180`) is a non-null + inequality viewport-update sanity over standard QML content — not a custom-geometry raster oracle, not a §9 residual | `verticalScrollPinsTempoOverCcContent` | P |
| `179-191` | Shrinking the drawer height re-pins tempo without a scroll gesture; `body.top()` delta matches the viewport delta | `viewportResizeKeepsTempoPinned` | P |
| `199-216` | Clicking the expanded header recollapses (body empties, minimum height recovers); re-expanding restores configured height/pinned rect | `headerClickRecollapsesTempoAndRecoversCanvasSpace` + `headerReexpansionRestoresConfiguredTempoHeight` | P |
| `224-226` | Teardown resets the temporary expansion | fixture `cleanup()` discipline | — |

### 7.3 `rollcheckautomation_tempo_paint.cpp` (549L) — AutomationChrome (presentation)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `212,233-234` | Retained scene available; expanded tempo body overlaps a visible CC lane | setup precondition | — |
| `261-292` | Expanded tempo occludes: CC curves clipped out of the covered region, visible in uncovered body; CC mutation bumps `AutomationCurves` revision; tempo selection reticle composed inside the covered body and bumps `AutomationSelection`. Source-verified: `rollcheckautomation_tempo_paint.cpp` had **zero framebuffer/pixel oracles** — retained `quickScene->layer()` geometry + `TimelineQuickTextModel` assertions only; no native residual; retired whole in the 2026-09-05 cutover (18/18 green offscreen; per-row isolation + source reviews complete in the 2026-09-05 runs) | `expandedTempoClipsCoveredCcCurves` + `tempoSelectionReticleComposedInCoveredBody` (fka `…RemainsVisibleInCoveredBody`, declared) | P |
| `303-340` | Collapsed pinned header over a CC lane clips curves out of the header rect — same retained-layer proof (`tempo_paint` is CPU-only, source-verified; no framebuffer oracle) | `collapsedTempoHeaderClipsCoveredCcCurves` | P |
| `405-502` | Gutter text model populated; tempo title "Tempo (BPM)" + summary, per-row `CCLanes::laneLabel` titles, and the "Add automation lane" strip all present within gutter bounds — **exact-label assertions retained (§8 resolved in favor of retention)** | `gutterTextRecordsUseSemanticLabelsAndBounds` | P |
| `507-510` | Hovering a tempo node populates `automationHoverTextModel()` with a non-empty alpha>0 record | `tempoHoverValueHasVisibleTextRecord` | P |
| `512-514` | Teardown restores SMF/revision/undo baseline | fixture `cleanup()` discipline | — |

### 7.4 `rollcheckautomation_paint.cpp` (735L) — AutomationPaint (AET slots; automationpainting.cpp / automationpreviews.cpp)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `352-411` | Preconditions: tempo expanded, Quick scene/view available, band capture valid | setup precondition | — |
| `416-463` | Empty tempo storage composes NO default 120 BPM lead-in curve/node; first nonzero point composes the implicit lead-in 0→96 without a tick-0 node; explicit tick-0 suppresses the lead-in and composes its node; document untouched (retained layers + frozen document, per legacy) | `emptyTempoStorageComposesNoLeadIn` + `firstNonzeroTempoPointComposesImplicitLeadInCurve` + `explicitTickZeroTempoPointSuppressesLeadInCurve` | P |
| `464-538` | Step curves + nodes composed in `AutomationCurves`/`AutomationNodes`, rendered in the framebuffer (colors asserted), revisions advance (Tempo + CC rows) — **pixel half gated (§9)** | `stepCurvesAndNodesComposed_data`/slot (fka `stepCurvesAndNodesComposedInLayersAndFramebuffer`, declared) | P / N |
| `510-564` | Selected node renders nodes + selection reticle layers/revisions; framebuffer asserted for the selection ring exactly where legacy captured it (Tempo + CC) — **pixel gated** | `selectionRingsAndReticlesComposed_data`/slot (fka `selectionRingsAndReticlesRendered`, declared) | P / N |
| `547-558` | Single-node drag past threshold previews in `AutomationTransient` (`edit_preview_outline`), revision advances, document frozen (Tempo + CC) | `singleNodeDragPreview_data`/slot | P |
| `571-603` | Multi-node drag previews all selected outlines at shifted positions; freehand sweep previews the target node (Tempo + CC) | `multiNodeDragPreview_data`/slot + `sweepPreview_data`/slot | P |
| `615-626` | Shift+drag previews the ramp line/rect between start and end (Tempo + CC) | `shiftRampPreview_data`/slot | P |
| `630-658` | Pencil drag previews the curve + value label via the transient text-record rectangle; document frozen | `pencilPreviewAndValueLabel` | P |
| `664-678` | Edit cursor at 24/96 moves `editRootContentX()` by the camera-projected delta; cursor visible; document frozen | `editCursorTracksQuickView` | P |
| `690-694` | Teardown restores SMF/undo/tempo baseline | fixture `cleanup()` discipline | — |

### 7.5 `rollcheckautomation_popup.cpp` (391L) — AutomationPopups (automationmenus.cpp / automationclipboard.cpp)

| Legacy range (hint) | Original contract | New case (owner) | St |
|---|---|---|---|
| `75-78` | Every SongView popup menu is parented to SongView | `contextMenuRoutingAndAvailableLanes` | P |
| `150-152` | Left-click in a CC gutter header opens no menu | `contextMenuRoutingAndAvailableLanes` | P |
| `160-194` | Add-lane strip menu: "Hidden CC lanes" heading, `Show: <Label> (hidden)` entries, occupied lanes omitted, each available lane exactly once; every code-path candidate exercised via `QAction::data` controller identities (available row added, hidden lane unhidden). Textual heading/label/order removal **Main-approved (§8)**: identity routing + real effects replace incidental wording | `contextMenuRoutingAndAvailableLanes` | P |
| `194-246` | CC header menu offers Copy/Hide/Delete CC lane; Tempo header menu offers Copy/Paste/Clear Tempo; tempo node menu is exactly `["Set Value","Delete"]` | `contextMenuRoutingAndAvailableLanes` | P |
| `260-285` | Node menu precedence over a mixed time selection still `["Set Value","Delete"]`; CC gutter body routes to the lane menu | `contextMenuRoutingAndAvailableLanes` | P |
| `294-324` | Clipboard: 300 BPM tempo point pasted into CC lands at tick 96 clamped to 127; value-0 CC pasted into Tempo lands at tick 144 clamped to `kMinTempoBpm` | `clipboardCrossLanePasteClamps` | P |
| `326-337` | "Clear Tempo" empties tempo points; "Clear events" empties that controller's points | `contextMenuActionsApplyEffects` | P |

## 8. Duplicate/crosslink register and adjudication items

Duplicates resolved — single asserting owner each:

1. **Sub-threshold** — parity `blankAndSubThresholdNoOps` owns CC empty-lane
   sub-threshold (roll `776-786` + parity `426-441`); CanvasEditing's duplicate
   slot removed.
2. **Activation slop boundary** — CanvasEditing `activationSlopDoesNotCommit`
   (roll `790-800`).
3. **Sweep activation boundary** — parity `sweepAndRampCommit` owns roll
   `817-820` (beyond-slop start assertion retained there); duplicate
   `sweepStartsBeyondActivationDistance` removed.
4. **Click delete / double click** — parity split (review-corrected):
   `stationaryNodeInteractions` owns the single-click-delete and
   Shift-immunity halves of roll `927-955`;
   `doubleClickDeletesOnceWithoutValueDialog` owns the double-click half
   (complete two-click sequence on a fresh node: deletes exactly once, no
   dialog); `independentDoubleClickAfterDeleteOpensValueDialog` adds the
   inverse protection — the later valid insertion dialog must still open and
   Cancel must leave the document frozen — guarding against over-suppression
   rather than duplicating a legacy row (delivery semantics and the
   fail-before/pass-after guard repair: §6.4 note). Delete-precedence half of
   Ownership `detailThresholdHiddenVisibleNodePrecedence` covers the
   pencil-conflict aspect; menu-route delete (`pointMenuDeleteCommitsEdit`)
   and excursion delete (`pencilClickOnExcursionNodeDeletesExcursion`) stay
   distinct.
5. **Right-drag band commit** — parity `laneBandSelectsRange` owns roll
   `1292-1295`.
6. **Group drag + key delete** — parity `selectedRangeDragAndDelete` owns roll
   `1518-1608`; Ownership `tracksSelectionGroupDragUndo` keeps the Alt-drag
   variant; Selection cross-lane slots keep the multi-lane variant.
7. **Same-tick duplicate group order** — parity `nodeDragCommits` owns roll
   `1047-1059`.
8. **Shift axis lock (node drag)** — parity `nodeDragShiftAxisLocks` owns roll
   `1676-1712`; Pencil's `pencilShiftModifierLocksValueDimension` is the
   distinct pencil-stroke contract.
9. **documentChanged cancellation (node drag)** — parity
   `rebuildCancelsAdapterDragAndRecovers` owns roll `1733` route 2; CanvasEditing
   keeps the other four routes; pilot keeps Escape; pencil/voice keep their
   interaction-local routes.
10. **Middle pan** — `middlePanIsolated` (Routing, isolation oracle) ≙
    `middleMousePanSurvivesRefresh` (CanvasEditing, pan delta + refresh).
11. **Boundary cursor** — Chrome cursor precedence absorbs `cursor.cpp` +
    `ownership.cpp:158-170`; CanvasEditing's `boundaryHover…` keeps the
    no-insertion-preview oracle.
12. **Add-empty-lane text** — Chrome LFO-title case (preserve + unique IDs) ≙
    CanvasEditing `boundaryHoverAndEmptyLaneUpdateTextAndGrid` (new title +
    grid revision). Crosslinked.
13. **Escape cancel** — pilot (CC, V) ≙ parity `escapeCancelsAdapterDrag` ≙
    pencil routes row ≙ `voiceEscapeAndUngrabCancel` — each keeps only its
    non-duplicated axis.
14. **Row handles** — `contract.cpp:913-971` → Hover
    `rowRebuildStaleReleaseDoesNotMutate` (Domain excluded it as GUI-static).
15. **Projection trio** — `projectionPartialCell`/`ValueBounds`/`InsertionTiming`
    + the threshold half of the precedence case are GUI-free: AET slots stay as
    declared, crosslinked to domain coverage; one asserting owner per assertion.

Adjudications (Main ruled; approved removals stand because consumer behavior
replaces incidental defaults):

- **Approved** — Popups: exact menu heading/label/order wording dropped
  (`rollcheckautomation_popup:160-194`); `QAction::data` identity routing +
  effect assertions are the consumer contract.
- **Approved** — Hover: input-flag plumbing dropped (`hover.cpp:331-339`);
  `directInputHostRouting` asserts the consumer-visible contract. The
  accessibility description is flagged, not silently dropped: a metadata-only
  legacy check, never functional accessibility proof; user-facing
  accessibility is unchanged and this is **no** claim that the new suite
  replaces accessibility testing.
- **Approved** — Ownership: hard-coded `Key_B` default binding/wording dropped
  (configured-shortcut behavior replaces incidental defaults);
  programmatic-trigger row folded as duplicate; legacy view/window dual-target
  split collapsed to the single real-window route — approved **only because**
  that route exercises the application route; the suite must not claim
  two-target proof.
- **Approved** — Routing: undo-command-text assertion at `routing.cpp:157`
  dropped; the byte-for-byte undo oracle (revision, undo index/count) is
  retained in `voiceHorizontalPreviewCommitsAndUndoes`.
- Resolved: Chrome retains framebuffer proofs alongside layer checks (no
  layer-only substitution); Paint retains pixel assertions exactly where legacy
  had them.
- Cursor DPR: legacy 2x row (`cursor.cpp:78-90`) split (§6.6) — Chrome's DPR-1
  installation row does not cover the scaling law. Corrective slot
  `pencilCursorScalesWithInjectedDevicePixelRatio` (presentation suite,
  injected host DPR 1→2→1 via public `pointerMove`) has **executed green** in
  Main's offscreen isolated gate. The legacy row asserts only the ratio — the
  earlier extent/hotspot claims were false and are removed; the seam is
  host-injected, so this row is **not native** and its §9 entry is closed.
  Coverage in the §10 sense still follows the gates; claiming DPR-1 coverage
  for the scaling law remains wrong.
- Modal `QInputDialog` evidence gate applies to
  `pointMenuNumericDialogUpdatesOneDuplicateOccurrence` (jointly migrates roll
  `850-924` + `1087-1132`) — satisfied at the driver level: modal
  demonstrably works offscreen (§9 modal row); the slot is proven with the
  isolation receipt.
- Pilot re-run on the shared fixture (tracked-button movement semantics) —
  done: 5 Qt results green. Domain suite: full set (26 Qt results) green
  before its readback additions. Superseded 2026-09-05: the isolation receipt
  (§2/§6) promotes replacement rows to P, and the cutover has since completed
  (§10/§11); the `Windowing::WindowSystem` rows were deliberately not
  executed — claiming native execution is banned outright.
- Approved, not coverage-weakening — projection quantization + lane-body
  guards: mapping/projection cases resolve geometry through the production
  `AutomationProjection` (`snapCellAt`/`rawTickAt`/`valueAtY`) and guard lane
  bodies with `!isEmpty()` instead of re-deriving legacy hand-computed rect
  math; the quantization contracts themselves stay asserted (e.g.
  `pencilClickHalfOpenQuantization` asserts both boundary cells and values).
- Outstanding: none — all suite filenames recorded.

## 9. Native-evidence register (observed proofs → retained-native residual or closed)

| Claim (legacy assumption) | Affected cases | Proof required | Residual if unproven |
|---|---|---|---|
| Offscreen `grabWindow` framebuffer capture (`captureQuickBand`, `quickframebuffer.cpp:191`) | paint curve/node colors (509-517) + selection ring (541-547), half-open rings (rollcheckautomation.cpp 1427-1508 — retained B/C exclusion negatives plus exactly three positive framebuffer probes at 1495-1505: A in the excluded capture, A in the included capture, B in the included capture; **no negative pixel-B probe exists**, the earlier scout claim was false), gutter-boundary no-paint (963-970), hover ghost/repeat/ring/clear (hover.cpp 498-565), voice preview diff (routing.cpp 140-150) — source-verified full table: agent://MapNativeRasterExtraction | **Probe complete (§4.7, artifact://286)**: offscreen loads the software adaptation, which skips custom `QSGGeometryNode`s; a non-null capture is background + standard QML only — never proof that custom geometry drew | Retained-native: those verified raster ranges are carried by `src/checks/automation/raster/` (`painting.cpp` exporting `runAutomationPaintRasterCheck`, `interaction.cpp` + `rasterfixture.h/.cpp` exporting `runAutomationInteractionRasterCheck`; maps agent://ExtractAutomationPaintRaster + agent://ExtractAutomationInteractionRaster; independent Qt + thermo-nuclear source reviews PASS, no blockers) — landed as the single registered `automation-raster` `WindowSystem` row (`checkcatalog.cpp:387-395`), compiled and source-reviewed, deliberately not executed natively (the §9 boundary) — never silently converted to layer-only. Not residuals: `rollcheckautomation_tempo_paint.cpp` (zero pixel oracles — retained layers/text only; retired whole in the 2026-09-05 cutover; 18/18 green offscreen, isolation + reviews complete); `routing.cpp:304-323` (non-null/same-size capture validity, not a pixel-change oracle); LFO title crop equality (`transactions.cpp:153-156`) and tempo scroll viewport sanity (`tempo.cpp:179-180`) are text/standard-QML oracles that hold offscreen |
| Modal `QInputDialog` / queued `QMenu` driver offscreen | `pointMenuNumericDialogUpdatesOneDuplicateOccurrence`, `pointMenuDeleteCommitsEdit`, context-menu/clipboard cases | case passes offscreen with programmatically dismissed dialog | **Demonstrated — no residual (2026-09-05)**: modal demonstrably works offscreen. The legacy popup harness (`automation-popup-menus`, no windowing override → default `Windowing::Offscreen`, checkcatalog.h:32) passes in the safe gate and drives exactly the queued-`QMenu` → "Set Value" → modal-`QInputDialog` discovery/parentage/reject flow (rollcheckautomation.cpp:865-908); the replacement slots share the same driver shape (`automation_modal::scheduleMenuInteraction`/`scheduleInputDialogInteraction`/`clickMenuAction` + 1 s watchdog, `automationmodalguard.h`) and ran green in the same gate and the isolation receipt. Proven; no native requirement |
| Synthetic WindowDeactivate == real deactivation semantics | `deactivationClears`, pencil/parity/additional-routes deactivation rows | `sendWindowDeactivate()` parity evidence | **Closed — not native (source-verified 2026-09-05)**: legacy never asserted OS-generated focus equivalence; it drives injected routes only — direct `inputCancelled(TimelineInputCancelReason::WindowDeactivated)` (hover.cpp:417, rollcheckautomation.cpp:1746) or a synthetic `QEvent(WindowDeactivate)` to the view (transactions.cpp:397-398). The replacements claim exactly that: hover `deactivationClears` uses the identical `inputCancelled(WindowDeactivated)` seam (tst_automationhover.cpp:126-127), AET rows use `sendWindowDeactivate()` → synthetic `WindowDeactivate` on the real quick window (automationfixture.cpp:551-557). Parity is by construction; proven with the isolation receipt; no residual |
| Transport/playback clock control | `voiceContextFollowsPlaybackOrEditCursor` | deterministic playhead drive offscreen | **Closed — not native (source-verified 2026-09-05)**: legacy drives injected transport state (`live.playback = {playhead, true}` + `page.refreshLiveState`, rollcheckautomation.cpp:1758-1770), never an OS audio/timer clock; the replacement slot drives the same injected seams (`DrawerPageLiveState.playback = {-3.0, true}` + `VelocityArea::refreshLiveState`, `view.setPlayheadSample(sample, true)` — automationcanvasediting.cpp:220-243). Only the original injected behavior is claimed; no OS-generated timer equivalence. Proven with the isolation receipt; no residual |
| Cursor DPR scaling law (legacy 2x row) | `pencilCursorScalesWithInjectedDevicePixelRatio` (Chrome) | **Closed**: executed green offscreen (host-injected DPR 1→2→1, isolated gate) — not native | none — host-injected seam; the scaling law is never claimed via the DPR-1 installation row |

Catalog reality after Main's 2026-09-05 cutover: the legacy rows `automation`,
`automation-gestures`, and `automation-popup-menus` are removed;
`automation-editing` and the three runners (`automation-domain`,
`automation-presentation`, `automation-hover`) are registered
`Offscreen`+`QtTest`; and ONE `automation-raster` `Windowing::WindowSystem`
row invokes `runAutomationRasterCheck`, which executes `AutomationRasterTest`
once through `QTest::qExec`. Native execution is deliberately not performed:
the `WindowSystem` rows are exactly the 5 skips of the standard verify lane,
and no ledger entry may claim native execution — the ban is absolute; what is
recorded is the native raster evidence in the removed legacy files (baseline
`7430fb4`) and its compiled, source-reviewed residual suite, not a native run.
Not native, and never re-added here: real `QQuickWindow` input delivery
offscreen (AET/hover input rows), the host-injected DPR seam (§6.6, closed),
the public retained-layer seam `TimelineQuickScene::layer(TimelineQuickLayer)`
→ `TimelineQuickLayerData` rects/triangles (proves composition or absence
without framebuffer pixels), and the public negative playhead seam:
`VelocityArea::refreshLiveState` driven with a negative playback tick and
observed through the `VelocityAxis` context clamp at -3.0
(`automationcanvasediting.cpp:219-221`, restored automation-canvas oracles);
the offscreen-proven modal `QMenu`/`QInputDialog` driver (§9 modal row); and
the injected deactivation routes — direct
`inputCancelled(TimelineInputCancelReason::WindowDeactivated)` or a synthetic
`QEvent(WindowDeactivate)` — which both old and new suites drive, never an
OS-generated focus change (§9 deactivation row). Every native residual's
original counterpart is a legacy file only (`rollcheckautomation*.cpp`,
`automationgesturecheck/hover.cpp`, `routing.cpp`); nothing under the new
`automation/` suites is native.

## 10. Cutover map (trim gates — Main executes)

A legacy file (or range) is trimmed only when **every** contract row that cites
it is proven (§2), the live source range is re-read and matches the trimmed
code, and the suite still passes after removal. A row explicitly recorded in
§9 as a retained-native residual keeps its legacy range until its evidence
gate closes — an explicitly permitted residual, not scope-finish fraud.

The native original pixel assertions lived in the legacy files removed by the
2026-09-05 cutover (baseline `7430fb4`); their replacement is the extracted
residual. The source-verified raster ranges — `rollcheckautomation.cpp`
1427-1508 (retained B/C exclusion negatives at 1495-1502 plus exactly three
positive framebuffer probes at 1503-1505 — A in the excluded capture, A in
the included capture, B in the included capture; **no negative pixel-B probe
exists**, the earlier scout claim was false) + 963-970,
`rollcheckautomation_paint.cpp` 509-517 + 541-547,
`automationgesturecheck/hover.cpp` 498-565, `routing.cpp` 140-150 — are
carried by `src/checks/automation/raster/`, whose
`AutomationRasterTest` (`tst_automationraster.h`) owns the painting and
interaction slots with `rasterfixture.h/.cpp`; source-parity maps
agent://ExtractAutomationPaintRaster and
agent://ExtractAutomationInteractionRaster; independent Qt + thermo-nuclear
source reviews PASS, no blockers). The residual is registered as the ONE
`automation-raster` `Windowing::WindowSystem` catalog row. Its current handler,
`runAutomationRasterCheck`, executes that one suite through `QTest::qExec`; it
compiles and links and is deliberately not executed in the standard verify
lane — native raster execution is the documented §9 boundary, not an open
migration gate.
`rollcheckautomation_tempo_paint.cpp` carried no native residual (zero pixel
oracles, source-verified) and was retired whole in the cutover like any
CPU-only legacy file.

Cutover status (2026-09-05, Main's batch — complete): all 22 legacy
automation files are removed (19 `.cpp` + 3 headers: the 12
`automationgesturecheck/` modules + harness infra and the 5
`rollcheckautomation*.cpp` files); the three legacy catalog rows
(`automation`, `automation-gestures`, `automation-popup-menus`) and their
`fwd.hpp` declarations are gone; old timing keys are removed
(`checks_walls.ts` keeps the four Qt-suite walls); the single
`automation-raster` Qt Test suite is registered with its `Windowing::WindowSystem`
catalog row and raster sources.
Verification: `deno task verify --no-windowing-checks --verbose` 61/66 ok,
5 native skips, 0 fail (final restored-normal run: build 32.48s, suite
4.01s); ASAN+UBSAN passed the automation filter (4/66 ok, 0 fail; flags
verified, then restored exactly). All 34 automation files plus shared
helpers, the production double-click guard, catalog, and `fwd.hpp` carry
clean LSP diagnostics. The 5 skips are the `WindowSystem` rows: native
execution is the deliberate §9 boundary, not an incomplete migration.

1. **Domain cutover** — AutomationDomainTest proven for `contract.cpp`
   E.2-E.4, `crosslane.cpp:496-618`, roll domain rows `494-700` → trim those
   ranges.
2. **Transaction cutover** — AET slots proven for transactions/stroke/crosslane
   UI/parity/routing/lifecycle/ownership/menu/voice and roll interaction rows →
   trim the corresponding ranges.
3. **Chrome/hover cutover** — presentation + hover suites proven → trim
   `cursor.cpp`, `hover.cpp`, tempo/tempo-paint/popup files, and
   `contract.cpp:913-971`.
4. **Harness deletion** — after all 12 modules are trimmed: delete `runner.cpp`
   (domain registry `kDomains` + loop), `domains.h`, `rig.h`/`rig.cpp`
   (AutomationInputHost/CheckRig), and `support.h` (its snapshot/one-edit
   helpers live on as assertion-free suite support, not boolean-callback
   wrappers); remove the `automation-gestures` catalog row. `eventsynth.cpp`
   stays — other legacy suites still use it.
5. **Final state** — zero `automationgesturecheck/` files and
   `rollcheckautomation*.cpp` gone apart from any range a closed §9 residual
   genuinely keeps native; AET + presentation + hover + domain suites carry
   every recorded contract not explicitly retained in §9, each residual row
   evidence-backed. An explicitly permitted residual is a legitimate finish,
   not scope-finish fraud — no absolute-zero claim outranks recorded evidence.

## 11. Registration checklist (complete — new rows + 2026-09-05 legacy cutover)

- Landed: catalog rows `automation-editing` / `automation-domain` /
  `automation-presentation` / `automation-hover`, all `Framework::QtTest` +
  `Windowing::Offscreen` (`checkcatalog.cpp`), with `fwd.hpp` decls
  `runAutomationEditingCheck` / `runAutomationDomainCheck` /
  `runAutomationPresentationCheck` / `runAutomationHoverCheck`.
- Landed: `CMakeLists.txt` sources — AET behavior files per §1 (pencil, stroke,
  painting, previews, selection, menus, clipboard, voice, routing, ownership,
  actions, parity, nodedrag, canvas-editing) + `automation/domain/*` +
  `automation/hover/*` + `automation/presentation/*`, plus the shared fixture
  header; AET slot declarations flow only through AutomationFixture.
- Windowing `Offscreen` is the landed classification with observed evidence
  (§4.7/§9): CPU retained/input/domain contracts run there; custom-geometry
  pixel contracts are native-bound.
- Removed (Main's cutover batch, 2026-09-05): legacy rows `automation` /
  `automation-gestures` / `automation-popup-menus` and their `fwd.hpp`
  declarations; all 22 legacy files (19 `.cpp` + 3 headers); old
  `checks_walls.ts` automation keys (the four Qt-suite walls remain; the
  native `automation-raster` row has no wall estimate).
- Landed: `automation-raster` (`Windowing::WindowSystem`, ExistingDirectory
  scratch + `DecompProject`/route101 fixtures) — `runAutomationRasterCheck`
  executes the single `AutomationRasterTest` suite through `QTest::qExec`;
  its raster sources are listed in `CMakeLists.txt`; final registration Qt
  review PASS. Compiled and source-reviewed; deliberately not executed
  natively (§9 boundary).
- Final verification (2026-09-05): `deno task verify --no-windowing-checks
  --verbose` 61/66 ok, 5 native skips, 0 fail (build 32.48s, suite 4.01s);
  ASAN+UBSAN automation filter 4/66 ok, 0 fail with flags verified and
  restored exactly; all 34 automation files plus shared helpers, the
  production double-click guard, catalog, and `fwd.hpp` carry clean LSP
  diagnostics.
