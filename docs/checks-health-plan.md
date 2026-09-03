# Checks health plan — modular, representative, focused

Goal: keep `src/checks/` healthy (every real user path owned by exactly one check),
representative (integration checks mirror production wiring, unit checks pin pure logic),
modular (one feature directory per ownership seam, small public surface),
focused (no grab-bag files, no duplicate scenarios).

Vocabulary: **Module** (interface + implementation), **Interface** (everything a caller
must know), **Seam** (where the interface lives), **Adapter** (what fills the slot),
**Depth** (behavior per unit of interface), **Leverage** (payback across callers),
**Locality** (fixes concentrate in one place). Review rule (`rule://keep-files-small`):
~600L is a review signal, never a split target — split only at real ownership
boundaries; prefer one feature directory with a small public surface
(`src/ui/editordrawer/` is the model).

## Verdict

One merge, one removal, one split. Everything else stays separate. Reasoning for each
below — each candidate was run through two tests:

- **Deletion test:** delete the module; if complexity vanishes it was pass-through,
  if it reappears across N callers it earns its keep.
- **One-vs-two Adapter test:** one adapter means a hypothetical seam, two means a real
  one. Merging two checks that need different harnesses creates a grab-bag, not a module.

## Rejected merges (keep separate)

- **selection + lane selection.** `selectioncheck.cpp` (475L, pure
  `songview/editorselectionmodel.h`, zero widgets) vs `laneselectioncheck.cpp` (245L,
  drawer projection view with its own 15L ProjectionRig). No shared logic (deletion
  fails), different harnesses (Adapter fails), merged 719L exceeds the review signal.
- **clipmime + clip.** Unit JSON codec (280L, no fixture) vs full GUI/undo integration
  (needs multi-doc, roll-input, QUndoStack harness). Independent reasons to change;
  merged 931L. Real cleanup instead: `clipmimecheck` should include
  `clipcheck_support.h` (~75L saved).
- **Activity trio.** `audiocheck` (packedActivity codec, hardware-dependent skip
  semantics) vs `trackactivitycheck` (ballistics math) vs `trackactivitymetercheck`
  (Qt Quick raster/DPR, 27 includes). Three distinct seams; fractional-DPR
  parameterization belongs to the meter alone.
- **Velocity pair.** `velocitymodelcheck` (296L headless math, no harness) vs
  `rollcheckpsgvelocity` (2141L QML integration with VelocityInputHost). Locality:
  quantization/gesture-transaction changes verify headlessly without the QML stack.
- **Automation sprawl.** `automationgesturecheck/` (17 files, `rig.h` + `support.h`
  internal seams) is already the exemplar module. `rollcheckautomation*` exercises a
  different seam (canvas impl + popup menus vs TimelineInputHost gestures). Note:
  `runAutomationCheck` / `runAutomationPopupMenuCheck` already share
  `runAutomationCheckImpl(..., popupMenus)` — merged in code, two catalog rows is
  intentional parameterization, same as `exportcheck`/`exportcheck-tail` and the
  layout/theme rows.
- **prime / loop / click.** All synth `TimelinePlayer` + `m4a_engine.h`, but distinct
  invariants (voice priming, loop-GOTO event ordering, cut-fade clicks). May group
  under `playback/` one day; never one file.

## Approved changes

### 1. DONE — remove `selftest-voicegroup` (commit `739f6ba`)

`src/checks/selftest/voicegroup.cpp` (185L: scalar + structural voice edits, bank
reload, undo, source-file identity) is fully subsumed by `vgsavecheck` (1821L); the
only delta (15L live-playback assertion) was intentionally dropped, not ported.
Removed: the file, `SelfTestScenario::Voicegroup` + decl (`harness.h`), descriptor
(`harness.cpp`, enum order still index-safe: Timeline=0, Transport=1, Workspace=2),
`CMakeLists.txt` source line, catalog entry (`checkcatalog.cpp`), wall entry
(`tools/checks_walls.ts`). 6 files, 192 deletions. Verified: `build:checks` ok,
`verify --filter vgsavecheck` PASS, zero live refs (only `docs/old/` history mentions
remain). Covering check untouched.

### 2. NEXT — merge host family into `src/checks/hostcheck/`

The only two files violating the size rule at genuinely related seams:
`hostcheck.cpp` (54 includes: `runHostSeamsCheck`, `runHostAdapterCheck`) +
`mainwindowroutingcheck.cpp` (61 includes: `runMainWindowRoutingCheck`,
`runHostIntegrationCheck`). Public `hostcheck.h` exposes the four `run*` signatures;
private internal seams `host_quick_rig` (QML band helpers, adapter only) +
`host_workspace_rig` (async readiness, routing + integration); ~12-include budget per
file. Forces curing the member-check anti-pattern: `MainWindow::runMainWindowRoutingCheck`
(`mainwindow.h:78`) + `runPolyGateCheck` (`:98`) are production members consumed only
by checks (~1020L out, plus the 17L forwarding shim). Fold `polycheck` Stage C's
MainWindow solo-overflow gate into routing. Medium risk (friendship rewiring, catalog
+ `fwd.hpp` updates). Verify: `build:checks` + `verify --filter
host-seams,host-adapter,mainwindow-routing,host-integration`.

### 3. LATER — split `selftest/workspace.cpp`

~300L pure `EditorViewState` QSettings codec → headless `editorviewstatecheck`;
MainWindow-coupled smoke (dialog construction, playhead-timer teardown) stays, timer
assertion moves to `tabcheck`. Verify: `editorviewstatecheck + tabcheck`.

## Coverage map (each path has exactly one owner when the above lands)

MIDI import/edit/undo: roundtrip, editcheck, smfcheck. Voicegroup: vgload, vgsave, vg,
vgbank. Playback: transport, loop, prime, click, poly, selftest-transport.
Selection/clip: selection, laneselection, clipmime, clip. Automation/velocity:
automation, automation-gestures, automation-popup-menus, velocity-page, velocity-model,
editor-drawer. Tabs/session/workspace/switch: tab, session, projectworkspace,
projectio, selftest-workspace. Close boundary: tab timer + workspace dialog smoke.
Theme/layout: theme, font, darkbase, editor-layout-12/16/18.

## Step 2 mechanical spec — host merge (sonic-ready)

Target: `src/checks/hostcheck.cpp` (1955L) + `src/checks/mainwindowroutingcheck.cpp`
(2129L) → `src/checks/hostcheck/`. No signature changes: `fwd.hpp` and
`checkcatalog.cpp` stay byte-identical (same 4 `run*` names/args). `mainwindow.h`
gains two friend decls (B1/B2 below) and loses two member decls. Orchestrator owns
the `CMakeLists.txt` edit inline after both units land: remove the 2 old `.cpp`
entries, add 6 new implementation files (+ their headers per project convention).

### Unit 2A — split `hostcheck.cpp` (files: hostcheck.cpp)

- New `hostcheck/hostcheck.h`: public interface only — copy these 4 decls BY SYMBOL
  NAME from `fwd.hpp` (`runHostSeamsCheck`, `runHostAdapterCheck`,
  `runMainWindowRoutingCheck`, `runHostIntegrationCheck`). WARNING: the span around
  them also contains unrelated `runRenderingPlayheadCheck` — do NOT copy it.
  Also declare the free poly-gate replacement defined in Unit 2B. Narrow includes only.
- New `hostcheck/host_quick_rig.h/.cpp`: move `hostcheck.cpp:101-369`
  (`pumpZeroDelayTimers`, `QmlBandPropertyNames` + table, `describeRect*`,
  `describeSize*`, `quickHostGeometryDetails`, `describeRectDelta`,
  `canonicalInputFailureDetails`, `otherEventsHoverCandidateDetails`, `imageDetails`,
  `publishedQmlRectsMatchCanonical`, `inputMatchesCanonical`,
  `trackHeadersInputMatchesCanonical`, `inputMatchesDrawerChrome`).
- New `hostcheck/host_shared.h`: move `noteEvent` (`:60-68`) marked explicitly
  `inline`. Do NOT move or unify `nodePosition` (`:93-100`): the seams click
  calculation (`:1856-1858`, live zoom 48 / h-scroll 0, no subtraction) is a
  different transform from the adapter helper (camera zoom minus camera scroll,
  `:96-99`) — leave the seams formula exactly as is.
- New `hostcheck/host_adapter_check.cpp`: `hostcheck.cpp:371-1679` verbatim, includes
  pruned to adapter-only + rig headers (drop `<QPointer>`; keep the adapter-only
  includes minus those that moved to `host_quick_rig`). The body directly uses all
  15 current UI headers — do NOT chase a count by relying on transitive includes;
  the rule is include-what-you-use, count may stay where it lands.
- New `hostcheck/host_seams_check.cpp`: `hostcheck.cpp:1681-1955` verbatim, includes
  pruned to seams needs + rig headers (only seams-only include is `<QPointer>`).
- Adapter-only drawer accessors stay local to the adapter file: `drawerContextTick`
  (begins `:70`), `editorDrawer` (begins `:75`), `velocityArea` (begins `:80`),
  `automationCanvas` (begins `:86`).
- Delete `src/checks/hostcheck.cpp`.
- Acceptance: `hostcheck.cpp` gone; both new files include `hostcheck/hostcheck.h`
  + their rig; no `ui/*` include added that the source body did not already use;
  `build:checks` ok (orchestrator verifies).

### Unit 2B — split routing file + MainWindow extraction (files: mainwindowroutingcheck.cpp, mainwindow.h, polycheck.cpp)

- Shared `hostcheck/host_workspace_rig.h/.cpp`: move `mainwindowroutingcheck.cpp:72-76`
  (`fileContents`), `:99-125` (`waitForTabReady`), `:129-135` (`waitForProjectReady`),
  `:157-178` (`porydawSnapshot`). Both halves include it. (Candidates are stateless
  free functions; the recursive visitor inside is a call-local lambda — safe to move.)
- New `hostcheck/mainwindow_routing_check.cpp`: helpers `:66-70` (`sendKeyStroke`),
  `:78-86` (`descendant`), `:142-151` (`waitForNativeActivation`), `:183-203`
  (`freshViewStateAtCanonicalDefaults`), `:209-242` (`checkFreshBind`), `:246-253`
  (`sameViewState`), `:264-359` (`checkStagedFullReload`), `:365-410`
  (`checkBankOnlyRebind`) + body `:413-1431` converted to a free
  `int runMainWindowRoutingCheck(same args as fwd.hpp)` that OWNS a local
  `MainWindow window`: merge the QSettings seed + construction from the shim
  (`:1433-1450`, 18 lines) into the top of the free function, rewrite every former
  `this`/member/inherited call (`this` at 443, 497, 507, 570, 610, 662, 871, 1413;
  private `stopPlayback()` at 469, 478) through `window`. Touched privates, all via
  the new friendship: `m_audioOk`, `m_workspace`, `m_audio`, `m_copyAction`,
  `m_automationDrawerAction`, `m_insertTimeAction`, `m_velocityDrawerAction`,
  `m_voiceChangesDrawerAction`, `m_closeAccepted`.
- In `mainwindow.h`: ADD `friend int runMainWindowRoutingCheck(...)` with the exact
  signature BEFORE removing the member decl (`:78-79`). Keep the `:52-53` friend
  lines for `runHostIntegrationCheck`.
- Delete the member body qualifier and the shim file range (shim merged, not dropped).
- New `hostcheck/host_integration_check.cpp`: helper `:88-95`
  (`velocityNodePosition`) + body `:1452-2129` as free `runHostIntegrationCheck`
  (friendship already at `mainwindow.h:52-53` — keep). Only private accesses:
  `window.m_audioOk`, `window.m_workspace`, `window.m_closeAccepted`.
- Poly gate: move the FULL `MainWindow::runPolyGateCheck` body
  (`polycheck.cpp:508-552`, note 546-551 hold the final assertion, reset, return)
  into `mainwindow_routing_check.cpp` as a NON-static free function declared in
  `hostcheck/hostcheck.h`; ADD exact matching friendship in `mainwindow.h` (needed
  privates: `m_audioOk`, `m_polyDock`, `m_audio`, `m_polyPanel`); update the existing
  caller `runPolyCheck()` (`polycheck.cpp:559-561`) to call it; delete the member
  body + `mainwindow.h:98` decl. (A `static` helper is WRONG: internal linkage
  hides it from the polycheck caller, and routing-function friendship does not
  transfer to callees.)
- Delete `src/checks/mainwindowroutingcheck.cpp`.
- Acceptance: `grep MainWindow::runMainWindowRoutingCheck|MainWindow::runPolyGateCheck
  src/` zero hits; `mainwindow.h` keeps `:52-53` friend lines, gains 2 exact friend
  decls, loses `:78-79,:98`; routing/integration halves include
  `host_workspace_rig`; no new `ui/*` includes beyond what the moved bodies use.

### Step 2 verify (orchestrator)

`deno task build:checks`, then `verify --filter host-seams --filter host-adapter
--filter mainwindow-routing --filter host-integration`.

## Step 3 mechanical spec — workspace split (sonic-ready)

Contract first: 3A creates `src/checks/editorviewstatecheck.h` declaring the runner
`int runEditorViewStateCheck()` PLUS the shared fixture/helper contract both halves
use: `StoreShape`, `keyGroup`, `storeShape`, `laneBlobKey`, `storeLaneBlob`,
`poisonLaneBlob`, `isCompactJsonObject`, `laneRowsDefaulted`, `lanesDefaulted`, and
the `full`/`bare` fixture builders. 3B includes this header instead of duplicating.
(Fixes the retained-helper gap: the live smoke needs all of these, not ~5 one-liners.)

### Unit 3A — new `editorviewstatecheck` (files: +editorviewstatecheck.h/.cpp, fwd.hpp, checkcatalog.cpp, checks_walls.ts)

- New `src/checks/editorviewstatecheck.cpp`: global (outside any namespace `checks`
  block — own anonymous namespace for file-local helpers) `int
  runEditorViewStateCheck()` using a `QTemporaryDir` isolated store. Move the pure
  codec coverage from `selftest/workspace.cpp`, CUT AT STATEMENT BOUNDARIES through
  `:301`: store/blob helpers (`StoreShape`, `keyGroup`, `laneBlobKey`, `storeShape`,
  `storeLaneBlob`, `poisonLaneBlob`, `isCompactJsonObject`, `laneRowsDefaulted`,
  `lanesDefaulted` — opened namespace context starts `:24-26`, closes `:119`; move
  whole declarations, never partial braces), fixtures incl. empty-store `if`
  (begins `:180`), invariants: defaults + 3-page round-trip, optional heights
  (`:204-212`), poison recovery (begins `:214`), row grammar (begins `:241`),
  lane-height clamping (`:288-301`). STOP at `:301` — the live-store smoke starts
  at `:303` and stays in 3B.
- The shared helpers + `full`/`bare` fixture builders go in / behind
  `editorviewstatecheck.h` per the contract above (declare in header, define once
  in the new `.cpp`).
- Deps: `<QSettings>`, `<QTemporaryDir>`, `<QJsonDocument>`, `<QJsonObject>`,
  `<QJsonArray>`, `<QJsonParseError>`, `<QVariant>`/`<QMetaType>`, `<map>`/`<set>` (or
  Qt equivalents as used by the moved code), `ui/editorviewstate.h`, `ui/layout.h` —
  no MainWindow/SongView/WorkspaceUi includes. (List is per moved code; if the moved
  code uses more, follow include-what-you-use rather than this list.)
- Add `int runEditorViewStateCheck();` to `src/checks/fwd.hpp` (catalog dispatches
  through globals declared there — without this the new row has no callable).
- Register `editorviewstatecheck` in `checkcatalog.cpp` next to the selftest rows
  (no fixture, no scratch dir — headless).
- Add a `checks_walls.ts` row for the new check: mirror the `selftest-workspace`
  entry's estimate format with a named estimate (do not invent a bare number and do
  not rely silently on the 0.3 fallback).
- Report the new files (`editorviewstatecheck.cpp` + `.h` per project convention
  of listing headers) for the orchestrator's `CMakeLists.txt` addition — Step 3 is
  an ADDITION (`workspace.cpp` stays), and no Step 3 build/verify runs until the
  orchestrator lands the CMake edit.
- Acceptance: new files compile with zero `mainwindow.h|songtab.h|songview.h|
  workspaceui.h` includes; all 5 codec invariants present and named; braces
  balanced (build proves it).

### Unit 3B — trim workspace smoke + move timer (files: selftest/workspace.cpp, tabcheck.cpp)

- In `workspace.cpp` keep: startup precondition (`:122-127`), dialog smoke
  (`:129-141`, `NewSongWizard` + `SettingsDialog`), capture (`:142`), live sidecar
  (`:303-365`, starts at 303 not 311), clean close (`:366-398`). Delete the codec
  blocks moved to 3A (through `:301`); replace ALL deleted helpers/fixtures with
  `#include "checks/editorviewstatecheck.h"` — do not hand-duplicate any of them.
- Grep `m_playheadTimer` in `workspace.cpp`; move those assertions to `tabcheck.cpp`
  `MainWindow::runTabCheck` beside the existing `m_uiTimer` cadence assertions
  (final-playing-tab section is `tabcheck.cpp:726-734`; assert playing: 100ms
  cadence + playhead active; after close: 500ms cadence + playhead inactive + zero
  tabs — direct `m_playheadTimer` access is available there). Delete from
  `workspace.cpp`.
- Acceptance: `workspace.cpp` ~130L, no codec invariant blocks remain;
  `m_playheadTimer` asserted in `tabcheck.cpp`, zero hits in `workspace.cpp`.

### Step 3 verify (orchestrator)

Land 3A's `CMakeLists.txt` addition FIRST, then `deno task build:checks`, then
`verify --filter editorviewstatecheck --filter tabcheck --filter selftest-workspace`.
