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

## 1. Current Test Architecture & Safety Boundary

### Current partition
`src/checks/checkcatalog.cpp` is the single catalog of 88 checks:

- **75 safe-lane rows:** 74 `Framework::QtTest` suites under
  `Windowing::Offscreen`, plus the `production-startup` `Framework::Process`
  smoke (`--version`).
- **13 native-only Qt Test suites:** `rollcheck`, `trackheaderquickcheck`,
  `rollwindowingcheck`, `timelinepan-native`, `rollcheck-static`,
  `automation-raster`, `mainwindow-routing-native`, `rendering-playhead`,
  `pitch-bend-raster`, `selectionkey-core`, `selectionkey-gesture`,
  `selectionkey-window`, and `selectionkey-local-input`, all
  `Windowing::WindowSystem`.

The authoritative safe command is `deno task verify --no-windowing-checks`.
It exercises the complete offscreen/process partition and intentionally skips
the thirteen native-only rows. The native boundary is evidence, not a missing
migration: offscreen Qt Quick uses a software scene-graph path that cannot
establish raster equivalence for porydaw's custom `QSGGeometryNode` timeline
layers. Offscreen nevertheless covers retained composition, document/undo,
input, modal menu/dialog routing, and the injected deactivation/playhead
seams; native rows retain only the window-system/raster contracts.

The selection-keyboard routing integration adds four genuine Qt suites under
`src/checks/selectionkey/`: 28 selectable slots and 56 case/data rows. Their
constructors only retain fixture arguments; offscreen `-functions` and
`-datatags` discovery succeeds without staged project contents or windows.
The keymap routed-command conflict matrix is independently selectable as 16
command-ID rows: each row binds and resets its command once and probes all
four routed contexts, so all 64 command×context behavioral expectations are
retained while each command is bound and reset once instead of four times.

Integration verification (pre-slimming receipt; historical counts, not
current measurements): `build:checks` and the safe gate passed **75/88**,
with 13 native rows intentionally excluded. Seventeen affected safe suites
passed all 516 case/data rows in both normal and exact reversed order.
With explicit native-execution permission, the supported Deno runner also
passed all six `selectionkey-gesture` cases in normal and exact reversed
order, with zero failures or skips inside the suite. The earlier standalone
probe failures did not recur; no assertions were weakened. The other twelve
native suites, including the three other new routing suites, were not run
in this integration verification.

Slimming verification (observed 2026-09-06, after the deduplication pass
recorded next): `build:checks` and clangd diagnostics pass on the slimmed
tree, and six affected suites re-ran in normal and exact reversed order for
112 case/data rows with zero failures: `keymapcheck` 50, `velocity-editing`
41, `selectionkey-gesture` 6, `selectionkey-core` 10 (incidental-band,
pencil-precedence, and rebound-delete slots), `selectionkey-window` 3
(scrollbar, resize, and lifetime slots), and `selectionkey-local-input` 2
(search and event-list slots). The final safe gate also passed **75/88**,
with 13 native suites intentionally excluded. Native execution above is
limited to the named cases, not the complete native partition.

One intermediate native run failed eligible pencil-hover Delete. Hover is
now established after mode, focus, selection, and coordinate staging; the
same ten core rows then passed ten consecutive runs (100 executions), and
the final 112-row normal/reverse run passed. The original intermittent
failure was not conclusively traced; no assertion or Delete binding was
weakened to obtain these results.

Thermo-nuclear review of the prospective merge against `2a9fcf0a` passed
both harness/tooling and production gates with no blockers. Stale theme
harness comments were corrected; the final safe rerun remained **75/88**
with 13 native suites excluded.

Post-landing verification exposed an uninitialized replacement voicegroup
in the host lifecycle case. The macOS crash stack confirmed invalid
ToneData access during drawer rebuild. Empty host and window lifecycle
banks are now value-initialized, with borrowed banks outliving their views.
The fixed host suite passed 30 repetitions; the full safe gate passed again.

Slimming pass (2026-09-06): the incidental-band click now proves the
eligible selection is preserved on every row, repairing outcome assertions
that were vacuous outside the two staged click kinds; the search line-edit
case drops typing guards because Copy and Solo were not bound to the typed
keys; duplicate cancellation coverage is consolidated — the
velocity roll-drag cancelled contract is one shared helper behind the
controller and Escape paths, the duplicate rollcheck velocity-cancel slot is
gone, and the window scrollbar-thumb case no longer repeats the post-cancel
proof owned by selectionkey-gesture's scrollbarThumbGuardsSharedCommands
(gesturethumbs.cpp, both bar rows); repeated setup is extracted
into one velocity roll-drag prologue, and the pencil-precedence matrix drives
the shipped Delete default instead of re-binding per case. The distinct
Escape contracts are retained: a roll note-drag Escape restores the captured
note selection, the automation pan keeps its idle-Escape time-selection
clear, and the canonical note-selection idle clear lives in the velocity and
window-resize cases.

The integration also repairs cross-window grab cancellation: Qt can return a
device-global grabber from `mouseGrabberItem()`. Timeline cancellation now
checks window ownership before releasing it. This keeps a live pitch-bend
preview from committing reentrantly during another document edit; the real
external-edit regression verifies exact-byte undo, redo, and live-preview
preservation.

### Runner and fixture contract

- `Framework` is exactly `QtTest` or `Process`; the legacy assertion framework
  and its `check(...)`/`fail(...)` harness are removed.
- Every in-process catalog runner accepts `const QStringList &qtArguments` and
  passes the terminal payload after `--qt` to one `QTest::qExec`. Public Qt
  arguments remain verbatim: `--filter` selects the catalog row, while `--qt`
  addresses that selected suite.
- Catalog fixture declarations own scratch and source material. Project-backed
  Qt suites create fresh fixtures in their lifecycle hooks; isolation evidence
  is suite isolation and the explicitly exercised reversed selector/data order,
  not a claim that every data row receives a separate process.
- The offscreen pool remains bounded to six workers; native checks remain
  serialized to avoid Cocoa activation/focus races. `QSettings` is redirected
  to each runner's temporary path before Porydaw startup.

### Historical audit, not current measurement
The LOC, white-box-coupling, and `MainWindow` member counts in the original
2026-09 planning audit were useful prioritization evidence, but are **not**
fresh measurements of this tree. The remaining historical receipts below are
preserved as dated observations; current guidance is this section and the
completed record in §2.

---

## 2. Completed Migration Record & Current Ownership

The migration is complete. The catalog, runner, and source were frozen after
the migration's final safe and sanitizer gates; those receipts below are
historical, and the current post-migration slimming pass is recorded in §1.
`src/mainwindow.h` has no `run*Check`
member declarations: host and routing coverage now lives in
`src/checks/host/` and `src/checks/mainwindowrouting/`, with their local
fixtures and focused Qt suites.

The former proposed workspace split is also complete, but not in the proposed
`editorviewstatecheck.cpp` shape. `src/checks/workspace/` owns the actual
workspace seam: `fixture.*`, `tst_workspacesessions.*`, `session.cpp`,
`tabs_lifecycle.cpp`, `tabs_persistence.cpp`, `tabs_scale.cpp`,
`tabs_transport.cpp`, and the three `selftest_*.cpp` suites. This is the
current home for workspace/session, persistence, scale, transport, and
self-test behavior.

Useful ownership boundaries in the current catalog are:

- `workspace/`, `host/`, and `mainwindowrouting/`: production startup,
  sessions/tabs, host wiring, and routing lifecycle.
- `project/`, `midi/`, `editcheck/`, `eventviews/`, `playback/`, `audio/`,
  `keyboard/`, `polyphony/`, and `clipboard/`: domain, persistence, codec,
  playback, DSP, and selection contracts.
- `velocity/`, `automation/`, `scrollbar/`, `drawerpresentation/`,
  `trackheaders/`, `timelinepan/`, `pitchbend/`, and `nativegraphics/`:
  editor interaction/presentation; their native residuals are catalogued
  explicitly rather than hidden in offscreen suites.

Production repairs found by the migration are retained: Stop holds output at
zero until the driver/frontend queues drain, then resets its resonance
suppressor and discards the already-filtered chunk remainder before fade-up.
Velocity refresh preserves the previous axis while its input host remains
attached, so the canonical rebuild detects and publishes the PSG-to-DirectSound
context transition instead of hiding it behind an early axis reset.

Pre-integration verification record (historical receipt; not current
counts): the safe gate passed **75/84**, with nine native
rows intentionally skipped and zero failures. The 74 Qt offscreen suites were
also exercised as 824 listed slots and 1,632 case/data rows in ordinary and
exact reversed selector/data order; `samplecheck` alone reported its documented
optional-corpus skip when no corpus was supplied. Three production negative
controls were detected and restored: popup reset commit, premature
all-sound-off audio cut, and SMF VLQ continuation. Combined ASan+UBSan
full-safe verification passed; LeakSanitizer is disabled on macOS. The normal
full-safe gate passed again after sanitizer flags and the original
`CMakeCache.txt` were restored.

### Historical decisions and receipts (superseded as guidance)

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
  Transaction drag→commit coverage additionally lived in the `automation-editing`
  Qt suite (host-choice rule below); the whole legacy family was migrated and
  removed in the 2026-09-05 cutover (the former `automation` /
  `automation-gestures` / `automation-popup-menus` rows are gone;
  `runAutomationCheck` / `runAutomationPopupMenuCheck` shared
  `runAutomationCheckImpl(..., popupMenus)` until removal — merged in code,
  two catalog rows was intentional parameterization, same as
  `exportcheck`/`exportcheck-tail` and the layout/theme rows).
  Full-migration ledger for the family (every `automationgesturecheck/` and
  `rollcheckautomation*` contract row, duplicate crosslinks, cutover gates,
  native-evidence register): `docs/automation-qt-test-migration-plan.md`.
- **prime / loop / click.** All synth `TimelinePlayer` + `m4a_engine.h`, but distinct
  invariants (voice priming, loop-GOTO event ordering, cut-fade clicks). May group
  under `playback/` one day; never one file.

---

### Completed roadmap

1. `selftest-voicegroup` was removed when `vgsavecheck` subsumed its coverage
   (commit `739f6ba`).
2. The `MainWindow` test-member extraction and host/routing modularization are
   complete. The old `hostcheck.cpp` and `mainwindowroutingcheck.cpp` plan is
   superseded by `src/checks/host/` and `src/checks/mainwindowrouting/`.
3. The workspace/self-test split is complete in `src/checks/workspace/`; no
   proposed `editorviewstatecheck` file exists or is required.
4. Qt Test migration is complete for the domain and algorithm suites, including
   scale, SMF, keymap, and project identity. New checks follow the current
   catalog/Qt Test contract rather than introducing a legacy default or adapter.

**Host-choice rule:** choose the host for the asserted contract, not suite
size. Gesture transactions that require document→timeline rebuilding, undo, and
commit signals use a production `SongTab`; static presentation checks use
`checks/support/editorrig.h`; GUI-free domain invariants use no UI host.

### Dated automation and scrollbar receipts
The following 2026-09-05 receipts are historical migration evidence. Their
61/66 and 62/68 gates are intermediate catalog sizes, not current results.

Three further automation-family Qt Test runners are registered, all
`Framework::QtTest` + `Windowing::Offscreen`: `automation-domain` (GUI-free),
`automation-presentation` (EditorRig static), `automation-hover` (own QObject +
real `QQuickWindow` input). Coverage state lives in
`docs/automation-qt-test-migration-plan.md`. Observed: `automation-domain`
passed its full set (26 Qt results) before its readback additions;
`automation-editing` re-ran its pilot green (5 Qt results) and its first full
offscreen run split 6 passed / 19 failed exactly along the offscreen
software-backend boundary — custom-geometry pixel oracles are the
retained-native residual (ledger §4.7/§9). What followed, all observed
2026-09-05: the shared-fixture root fixes and the double-click production
guard repair (ledger §6.4 note); the full safe automation gate; every one of
the 182 rows passing when individually selected (editing 131 / domain 24 /
presentation 16 / hover 11), followed by all four suites passing with reversed
data-row order (133/26/18/13 Qt results); and two targeted production mutation
controls failed the expected slots and passed after restore; and the cutover
batch, which removed all 22 legacy automation files plus the three legacy
catalog rows and registered ONE `automation-raster` `Windowing::WindowSystem`
row carrying the two raster exports. Final gates: `deno task verify
--no-windowing-checks --verbose` 61/66 ok, 5 native skips, 0 fail (build
32.48s, suite 4.01s); ASAN+UBSAN automation filter 4/66 ok, 0 fail with
flags verified and restored exactly; the modal menu driver demonstrably
works offscreen. The 5 skips are the `WindowSystem` rows — native execution
is the deliberate ledger §9 boundary, not an incomplete migration.

**Scrollbar migration — complete (2026-09-05; legacy originals audited at
`fork-main` `51a07a1`).** The `WindowSystem` Legacy row `scrollbarquickcheck`
and its two sources (`src/checks/scrollbarquickcheck.cpp`,
`scrollbarquickcheck_songview.cpp`) are removed, replaced by the `scrollbar`
row (`Framework::QtTest` + `Windowing::Offscreen`, Route 101 project fixture)
in `src/checks/scrollbar/`: `tst_scrollbar.h/.cpp` (lifecycle, automation
drawer and standalone signed-range slots), `control.cpp` (press/move/release/
drag/wheel primitives, `withinTrack`), `geometry.cpp`, `drag.cpp`, `input.cpp`.
Coverage by legacy group: automation drawer → `automationTrackPages`,
`automationDragClampsAndReverses`, `automationZeroRangeIgnoresDrag`;
standalone signed `TimelineScrollbar` → `signedRangeDragRebasesAndTracksModel`;
SongView geometry → `layoutFollowsCanonicalBands`,
`scrollbarHostContainsBothTracks`, `drawerResizeFollowsRollBand`,
`eventListHidesOnlyRollScrollbar`; drag → `dragClampsAndReverses` (2 rows),
`dragRebasesAfterZoom`, `dragRebasesAfterResize`,
`foldingDisablesAndRestoresRollDrag`, `externalCameraMovesReleasedThumb`
(2 rows); input → `trackPaging` (4), `wheelScrolling` (15),
`keyboardNavigation` (6). From source: 16 test slots (5 data-driven) plus the
`init`/`cleanup` fixture pair and 29 data rows — 40 behavior/data rows total.
Every slot and data row runs against a fresh project-backed Route 101 `SongTab`
+ `QQuickWindow` (the value-owned voice bank outlives the tab by declaration
order; `cleanup` cancels wheel sessions on both axes, releases grabs and held
buttons, clears item caches); synthetic mouse/wheel/key input drives the
QWindow with QTRY conditions on `QQuickWindow::isVisible()` instead of the
legacy native-exposure `msleep` loops. The legacy non-null `captureQuickBand`
framebuffer assertions are replaced by QQuickWindow host-containment geometry —
a containment oracle, not pixel equivalence; no native pixel evidence is
claimed. All legacy contracts are preserved: automation paging/clamping/
zero-range (released-thumb model tracking lives in the automation slot itself —
after release `setVerticalScroll` repositions the released thumb, QTRY-verified),
generic geometry, signed-range initial proportion, held-drag resize-rebasing
arithmetic and external model tracking, paging/wheel/keyboard input, drag
clamp/reverse, mid-drag zoom/resize rebasing, pitch fold, event-list toggle,
drawer resize.

Measured receipts (2026-09-05): the first full offscreen run passed 37/40
rows; all 3 failures were fixture defects, fixed — the automation drag pressed
the roll thumb instead of `drawerAutomationScrollThumb` (`beginAutomationDrag`
now targets the drawer thumb with QTRY waits on its QML `maximum`/`height`
bindings), and the horizontal paging rows failed the
`span > page + kWheelMargin` fixture guard (the slot doubles `pxPerBeat`
locally and QTRY-synchronizes the QML scrollbar bindings); the follow-up full
offscreen run passed all 40 rows. Isolation and controls: all 40 rows passed
when individually selected and in exact reversed row order; negative control
removing `TouchPad` from both QML wheel handlers failed exactly the
`horizontal-touchpad`/`vertical-touchpad` rows and
`dragBaseTranslation = 0` failed exactly `dragRebasesAfterZoom`/
`dragRebasesAfterResize`, both restored and passing; `TimelineScrollbar.qml`
is byte-identical before/after (SHA-256
`0c5a2232dc38228e035000808664dea2cccea7701bb7239fa40966b3245e59f2`). Final
gate: `deno task verify --no-windowing-checks --verbose` 62/68 ok, 6 native
skips, 0 fail (build 2.14s, suite 4.13s). At that historical cutover point,
`timelinepancheck` remained native and was outside its scope.

### Current Qt Test guidance

Use canonical production fixtures for transaction coverage, `EditorRig` for
static presentation, and model/domain assertions where no UI contract is under
test. Prefer document, undo, and retained-scene contracts over pixel offsets;
keep pixel/raster assertions only in the explicit native residual rows.

`Qt6::Test` is linked only into `porydaw_checks` under
`PORYDAW_BUILD_CHECKS`; the application target remains independent. The
manifest emits `"qt-test"` or `"process"` only. Explicit `--qt` invocations
retain complete raw Qt output, including failures.

The deleted `rollcheckpsgvelocity` and legacy automation files are not current
extension points. Velocity editing belongs in `src/checks/velocity/`;
automation coverage belongs in `src/checks/automation/`; velocity-page
presentation is in `src/checks/drawerpresentation/velocity.cpp`.

### Earlier pilot receipt (historical)

The following pre-completion automation receipt is retained for chronology, not
as current scope or gate guidance. At that point the three-case
`automation-editing` slice passed 5 Qt results, each function also passed when
selected alone, and reversed execution passed 5 results without failures or
skips. Its three production controls (node-move commit, held-movement preview
target, and Quick release routing) failed their intended assertions and passed
after restoration. The then-current combined run selected 2/65 rows and the
normal safe gate was 59/65 with six native skips; ASan+UBSan passed with leak
detection disabled and temporary flags restored. The later full-migration
record in §2 supersedes that pilot state: the remaining legacy automation
families were subsequently migrated and removed.
