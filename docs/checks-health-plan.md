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

---

## 1. Test Suite Architecture & Concurrency Reality

### The Real Scale & Coupling
- **Scale:** ~61,700 LOC of check code across ~131 files and 60+ check targets vs ~73,000 LOC
  of production code (near 1:1 ratio).
- **White-box coupling:** 51 check files include `ui/songview.h`; 289 call sites fish for
  private widgets via `findChild("...")`; 27 files re-derive canvas projection math via
  `layout::fontPx` rather than asserting domain/model state (`SongDocument`, `SmfEvent`).
- **Production class pollution:** Production `MainWindow` (`src/mainwindow.h`) declares 6
  check-runner methods on its interface, placing ~1,020L of check bodies directly inside the
  production class.

### Concurrency & Isolation Model
`tools/run_checks.ts` executes checks as independent OS processes orchestrated via a JSON
manifest (`porydaw_checks --manifest`):
1. **Manifest-Driven Partitioning:**
   - `Windowing::Offscreen` (~50 checks): Render headlessly (`QT_QPA_PLATFORM=offscreen`).
     Executed in a parallel LPT pool pinned to 6 workers by empirical benchmark on Apple Silicon
     (7+ workers cause thread/cache contention on CPU-saturating checks).
   - `Windowing::WindowSystem` (6 checks: `rollcheck`, `trackheaderquickcheck`,
     `rollwindowingcheck`, `automation-gestures`, `automation`, `rendering-playhead`):
     Require native Cocoa windows and native event dispatch. Serialized with worker count 1
     to prevent Cocoa window-activation and focus-stealing races.
2. **QSettings Sandboxing:**
   - `src/checks/checkregistry.cpp:139-144` redirects settings per-process via
     `QSettings::setPath(IniFormat, UserScope, tmpdir)` and `setDefaultFormat(IniFormat)` before
     every `StartupKind::Porydaw` check. Preferences do not leak or race across processes.
3. **Immediate Runner Concurrency Optimization:**
   - Today the runner drains the offscreen pool completely before starting the window-system
     worker. Because offscreen checks never create native Cocoa windows, **the single
     window-system worker can overlap concurrently alongside the offscreen pool from $t=0$**.
     This cuts total suite makespan at zero risk of focus-theft flakiness.

---

## 2. Verdict & Planned Steps

One removal (done), one structural extraction (next), one completion follow-up, and one split.
Everything else stays separate.

### Rejected merges (keep separate)

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
  (Update: the `rollcheckpsgvelocity` editing interactions have since migrated to the
  `velocity-editing` Qt Test suite — see `docs/velocity-qt-test-migration-plan.md`;
  the numerical seam stays headless.)
- **Automation sprawl.** `automationgesturecheck/` (17 files, `rig.h` + `support.h`
  internal seams) is already the exemplar module. `rollcheckautomation*` exercises a
  different seam (canvas impl + popup menus vs TimelineInputHost gestures).
  Transaction drag→commit coverage additionally lives in the `automation-editing`
  Qt suite (host-choice rule below); all legacy automation rows are unchanged. Note:
  `runAutomationCheck` / `runAutomationPopupMenuCheck` already share
  `runAutomationCheckImpl(..., popupMenus)` — merged in code, two catalog rows is
  intentional parameterization, same as `exportcheck`/`exportcheck-tail` and the
  layout/theme rows.
- **prime / loop / click.** All synth `TimelinePlayer` + `m4a_engine.h`, but distinct
  invariants (voice priming, loop-GOTO event ordering, cut-fade clicks). May group
  under `playback/` one day; never one file.

---

### Approved Changes

#### Step 1: DONE — remove `selftest-voicegroup` (commit `739f6ba`)
`src/checks/selftest/voicegroup.cpp` (185L) fully subsumed by `vgsavecheck` (1821L).
Removed: file, enum, descriptors, CMake entry, catalog entry, wall estimate. Verified clean.

#### Step 2: NEXT — Extract MainWindow Check Members & Modularize Host Family (`src/checks/hostcheck/`)
- **Primary goal:** Extract `MainWindow::runMainWindowRoutingCheck` (`mainwindow.h:78-79`) and
  `MainWindow::runPolyGateCheck` (`:98`) out of the production class.
- Converts both into free functions owning a local `MainWindow` and accessing privates via
  focused `friend` declarations (matching the existing `runHostIntegrationCheck` pattern).
- Modularizes `hostcheck.cpp` (1955L) + `mainwindowroutingcheck.cpp` (2215L) into
  `src/checks/hostcheck/` across 4 catalog rows (`host-seams`, `host-adapter`,
  `mainwindow-routing`, `host-integration`) with shared rigs (`host_quick_rig`,
  `host_workspace_rig`).
- **Diff safety:** Code bodies are moved *verbatim* at statement boundaries with pruned includes;
  no assertion rewriting in the same pass as relocation.

#### Step 2.5: FOLLOW-UP — Complete MainWindow Member Extraction
Step 2 cures 2 of the 6 `MainWindow` check members. To complete the architectural decoupling,
a follow-up pass converts the remaining 4 members into free functions with focused friendship:
- `MainWindow::runTabCheck` (`mainwindow.h:70`, defined in `tabcheck.cpp:54`)
- `MainWindow::runVgSaveCheck` (`mainwindow.h:64`, defined in `vgsavecheck.cpp:97`)
- `MainWindow::runRegisterActionCheck` (`mainwindow.h:85`, defined in `onboardcheck.cpp:224`)
- `MainWindow::runDeleteActionCheck` (`mainwindow.h:92`, defined in `onboardcheck.cpp:382`)
**Acceptance:** `src/mainwindow.h` contains zero `run*Check` member function declarations.

#### Step 3: LATER — Split `selftest/workspace.cpp` into Headless Codec & UI Smoke
- ~300L pure `EditorViewState` QSettings/JSON codec extracted to headless
  `src/checks/editorviewstatecheck.cpp` using an isolated `QTemporaryDir`.
- Retains the existing check assertion idiom (`check(...)` / `fail(...)`) to maintain
  clean integration with `tools/run_checks.ts` and the shared fixture header.
- MainWindow-coupled smoke stays in `workspace.cpp`; timer assertions move to `tabcheck.cpp`.

#### Step 4: FUTURE ROADMAP — Check Quality & Idiomatic Qt Testing

**Host-choice rule (recorded 2026-09):** pick the host by what a check asserts,
not by suite size. *Transaction* coverage — gestures that must drive real
document→timeline rebuilding, undo entries, and commit signals — runs on a
production `SongTab`; `checks/support/editorrig.h` hosts *static presentation*
checks (assembled widget stacks, chrome, geometry without gestures); GUI-free
domain tests (codecs, model math, `SongDocument`/`SmfEvent` invariants) need no
host. EditorRig is no longer mandated for velocity/automation transaction
suites; the host-extraction roadmap (Steps 2/2.5/3) is unaffected. Recorded
`SongTab` Qt Test suites, both `Framework::QtTest` + `Windowing::Offscreen`:

- `velocity-editing` (`src/checks/velocity/`): the migrated
  `rollcheckpsgvelocity` editing interactions (full record:
  `docs/velocity-qt-test-migration-plan.md`; the trimmed legacy file keeps only
  rendering/chrome/grid/axis/playhead helpers).
- `automation-editing` (`src/checks/automation/`, argv `--automation-editing`):
  exactly three behaviors, delivered through the real `timelineAutomationInput`
  item over a real CC lane. (1) A left-button drag commits exactly once —
  one document transaction, one undo entry, undo/redo symmetric, reacquired
  timeline updated. (2) Escape cancels the armed drag; later move/release
  commits nothing. (3) A stationary press/release on **blank** lane space is
  the only no-op — cursor placement (`editCursorTick`) with zero document
  transactions, because a stationary click on an existing node intentionally
  deletes it. Positive previews are observed via the public retained
  `AutomationTransient` scene triangles, not pixel capture. No universal
  fixture and no wheel/chord coverage; the legacy `automationgesturecheck/` and
  `rollcheckautomation*` rows are unchanged.

1. **Canonical Assembly:** Host *static presentation* checks on
   `checks/support/editorrig.h` instead of hand-assembling widget stacks and
   fishing for QML items via `findChild`. Transaction coverage follows the
   host-choice rule above (production-`SongTab` Qt suites, not EditorRig); the
   legacy automation rows keep their current scope, and `rollcheckpsgvelocity`
   retains only rendering/chrome/grid/axis/playhead helpers after its
   completed trim.
2. **Domain-Level Assertions:** Replace pixel-offset checks (`layout::fontPx`) with model
   invariants (`SongDocument`, `SmfEvent`, `QUndoStack`).
3. **Idiomatic Qt Testing (`Qt6::Test`):** the framework convention is established and
   reusable, proven by the `velocity-editing` and `automation-editing` suites:
   - `CheckDefinition::framework` (`Framework::Legacy`/`QtTest`), serialized as
     `"framework": "legacy"|"qt-test"` in the manifest; `tools/run_checks.ts` requires
     the field like any other manifest invariant.
   - `Qt6::Test` linked PRIVATE to `porydaw_checks` only, inside
     `PORYDAW_BUILD_CHECKS`; app target untouched.
   - `--qt` terminal marker in both `tools/cli.ts` and `tools/run_checks.ts` forwards
     everything after it verbatim to the one selected qt-test harness (`--filter`
     selects, `--qt` forwards; unknown Qt case names fail non-zero natively).
   - Explicit `--qt` runs print the complete raw Qt output; failure output is never
     line-capped for any check.
   - Still open: pilot `QTest` on newly added headless domain logic and pure
     algorithms (`porydaw_scale`, `DecompProject`, `keymap::Registry`). The retired
     "reporter adapter" idea is superseded by the raw-output policy above.

---

## 3. Step 2 Mechanical Spec — Host Merge & Extraction (Sonic-Ready)

Target: `src/checks/hostcheck.cpp` (1955L) + `src/checks/mainwindowroutingcheck.cpp`
(2215L) → `src/checks/hostcheck/`. No signature changes: `fwd.hpp` and
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

---

## 4. Step 3 Mechanical Spec — Workspace Split (Sonic-Ready)

Contract first: 3A creates `src/checks/editorviewstatecheck.h` declaring the runner
`int runEditorViewStateCheck()` PLUS the shared fixture/helper contract both halves
use: `StoreShape`, `keyGroup`, `storeShape`, `laneBlobKey`, `storeLaneBlob`,
`poisonLaneBlob`, `isCompactJsonObject`, `laneRowsDefaulted`, `lanesDefaulted`, and
the `full`/`bare` fixture builders. 3B includes this header instead of duplicating.

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
  no MainWindow/SongView/WorkspaceUi includes.
- Add `int runEditorViewStateCheck();` to `src/checks/fwd.hpp` (catalog dispatches
  through globals declared there — without this the new row has no callable).
- Register `editorviewstatecheck` in `checkcatalog.cpp` next to the selftest rows
  (no fixture, no scratch dir — headless).
- Add a `checks_walls.ts` row for the new check: mirror the `selftest-workspace`
  entry's estimate format with a named estimate.
- Report the new files (`editorviewstatecheck.cpp` + `.h`) for `CMakeLists.txt`.
- Acceptance: new files compile with zero `mainwindow.h|songtab.h|songview.h|
  workspaceui.h` includes; all 5 codec invariants present and named; braces balanced.

### Unit 3B — trim workspace smoke + move timer (files: selftest/workspace.cpp, tabcheck.cpp)

- In `workspace.cpp` keep: startup precondition (`:122-127`), dialog smoke
  (`:129-141`, `NewSongWizard` + `SettingsDialog`), capture (`:142`), live sidecar
  (`:303-365`), clean close (`:366-398`). Delete the codec blocks moved to 3A
  (through `:301`); replace deleted helpers/fixtures with
  `#include "checks/editorviewstatecheck.h"`.
- Grep `m_playheadTimer` in `workspace.cpp`; move those assertions to `tabcheck.cpp`
  `MainWindow::runTabCheck` beside the existing `m_uiTimer` cadence assertions
  (`tabcheck.cpp:726-734`). Delete from `workspace.cpp`.
- Acceptance: `workspace.cpp` ~130L, no codec invariant blocks remain;
  `m_playheadTimer` asserted in `tabcheck.cpp`, zero hits in `workspace.cpp`.

### Step 3 verify (orchestrator)

Land 3A's `CMakeLists.txt` addition FIRST, then `deno task build:checks`, then
`verify --filter editorviewstatecheck --filter tabcheck --filter selftest-workspace`.

---

## 5. Acceptance record — `automation-editing`

Established (2026-09, this worktree): the full suite passes — 5 Qt results
(3 behaviors plus lifecycle hooks) in 97 ms; suite source, header, and catalog
row carry clean LSP diagnostics.

Final verification after review corrections:
- Each of the three functions passes alone; `--qt -functions` lists all three.
  Reversed execution passes all 5 Qt results, zero failures/skips, in 52 ms.
- Real production negative controls were caught: suppressing the node-move commit
  failed the expected single `documentChanged` assertion; finishing during held
  movement failed the actual preview-target assertion; disconnecting Quick release
  routing failed the single-commit assertion. All mutations were restored.
- Both Qt suites passed together in ordinary runner mode (2/65 selected, 0.73 s),
  then with AddressSanitizer and UndefinedBehaviorSanitizer enabled (1.72 s).
  Leak detection was disabled; the temporary compiler flags were restored.
- Final normal `deno task verify --no-windowing-checks`: 59/65 checks passed,
  zero failures, 6 native-only rows intentionally skipped, 3.79 s (build 36.37 s).
- Thermo-nuclear review: PASS after extracting the repeated drag-arm geometry into
  one local helper and checking that post-Escape movement cannot revive preview.
  Source/header/catalog and timing-registry diagnostics are clean.

The input correction is fixture geometry, not a changed CC oracle: the default row
could not represent the requested 40→84 drag through integral QTest coordinates.
The test uses the supported maximum row height and preserves the delivered integer
delta across the activation-reset move. Literal document/timeline expectations stay
40→84, with the independent point at 100 unchanged.

The three-case slice is complete; the remaining legacy automation families have
not been migrated or removed. No production behavior changed, no wheel/chord or
pixel-capture capability was claimed, and no desktop interaction was used.
