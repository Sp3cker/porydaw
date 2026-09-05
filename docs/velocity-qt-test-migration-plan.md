# Velocity Qt Test migration plan — `velocity-editing` pilot

Status: implementation, legacy trim, and final verification are complete.
`velocity-editing` is cataloged `Windowing::Offscreen` with `Framework::QtTest`; the
suite drives a real `SongTab` with synthetic `QTest` input delivered only to its own
offscreen `QQuickWindow` — no `QCursor` warping, native pointer reconciliation, or
`processEvents` spinning. All 26 test functions / 41 behavior executions pass
(43 Qt results including lifecycle hooks, 0 failures, 0 skips). Each function also
passes alone, an explicit Wave data row passes alone, and the reversed suite passes.
Per-step thermo-nuclear reviews, including isolation and the final cutover, returned
PASS after corrections, with no blocking findings.

**Do not run desktop-interacting checks or launch native app windows.** The user
authorized continuation only without taking over their mouse, so the original
WindowSystem, native-cursor, and native app-smoke requirements are eliminated from
this plan; surviving mentions below are historical record only. The supported whole
lane is `deno task verify --no-windowing-checks`: the final post-trim run passed
58 of 64 checks, with the 6 native-only checks skipped by that restriction — zero
failures (3.64 s). Native-only verification is paused, not red. Both velocity suites
also passed an offscreen AddressSanitizer + UndefinedBehaviorSanitizer run.

Section 15 records completed gates. Historical source references describe the
initial `feature/velocity-qt-tests` worktree, forked from `fork-main` at `e4a9b9b`;
they are not completion claims.

## 1. User goal and locked decisions

Migrate the **velocity-editing** coverage of `src/checks/rollcheckpsgvelocity.cpp`
(2103L, legacy `check(...)`/`fail(...)` harness) onto an idiomatic Qt Test suite driven
through a real `SongTab`, and wire that suite into the catalog/manifest/deno runner as a
first-class `qt-test` framework check, selected and invoked from the existing
`deno task verify` lane.

Scope is the discussed **editing behaviors** — transactions, cancellations,
selection/hit testing, paint/ramp gestures, roll drag, modifier/detent editing behavior,
keyboard routing — **not all 21 helpers**. Unrelated rendering/chrome/grid/axis/layout/
playhead checks keep running in the trimmed legacy `velocity-page` check (section 7
dispositions each helper explicitly). Mixed helpers split: the interaction contract
moves; the visual assertion is retained by a legacy owner that performs its own explicit
independent setup.

Locked decisions (from Main; not renegotiable in implementation):

- Normal `QObject` test class with **private test slots**, `QCOMPARE`/`QVERIFY`,
  `QTest` QWindow input, `QTRY_*` condition waits, `QSignalSpy`. No homemade assertion
  framework, no parsing of Qt's human output.
- Real `SongTab` owns document/view/history/timeline rebuild. Cases populate it via
  `applyMidiStage` / `applyBankView` / `applyVoicegroupBound`
  (existing: `src/ui/songtab.h:87,90,93`).
- **No test-built `documentChanged` connection** (the legacy check installs its own
  rebuild lambda at `rollcheckpsgvelocity.cpp:774-781` — that is what SongTab now owns)
  and **no manual `DrawerPageLiveState`/`refreshLiveState` bookkeeping anywhere in the
  new suite**. The playback/playhead seam is **not** migrated: the playhead performance
  contract stays in the legacy `velocity-page` check (section 7); the new editing suite
  contains no playhead case, no live-state code, and no performance exception.
- Borrowed bank declared **before** the tab: the bank objects backing the voicegroup
  lease `SongTab` adopts must outlive the tab (member-order contract,
  `src/ui/songtab.h:123-131`); the lease itself is the tab's member.
- `TimelineQuickView::quickWindow()` (existing:
  `src/ui/songview/quick/timelinequickview.h:144`) supplies the real `QQuickWindow`;
  `QTest` sends Qt events into that window, not OS events.
- Exposure, readiness, and focus are distinct states; core cases never `QSKIP` over a
  missing ready/window state.
- Domain numerical checks stay at their seam (`velocity-model`, existing catalog row
  `checkcatalog.cpp:372-377` — untouched). Rendering/layout/axis assertions are
  **retained in the legacy `velocity-page` owner** with independent explicit setup —
  neither migrated into the Qt suite nor silently discarded (section 7).
- Expected velocities in the new suite are literals/test data or simple spec arithmetic;
  production code (geometry helpers, `VelocityMap`) locates inputs only and never
  supplies expected answers (sections 6.4, 7).
- Pilot gate = one complete transaction family (drag preview/release/undo/redo/cancel/
  noop) end-to-end through runner and suite. Full completion = every disposition row of
  section 7 executed: editing rows migrated, retained rows repaired to self-contained
  legacy owners, retired rows dropped with rationale — plus the final legacy trim. The
  remainder is **included scope**, not a "maybe later".
- Legacy `velocity-page` row stays registered and green throughout; the final step
  **trims** the legacy file (retired editing helpers out, retained helpers repaired to
  own their setup) — it is never deleted wholesale and never marked `qt-test`.

## 2. Non-goals

- No universal test rig, scenario DSL, dashboard, or permanent JUnit/XML parsing for the
  pilot.
- No host extraction, no `EditorRig` adoption for this suite. This supersedes
  `docs/checks-health-plan.md` Step 4 item 1 (`checks-health-plan.md:122-127`) **for this
  pilot only**; Steps 2/2.5/3 of that plan (MainWindow member extraction, workspace
  split) are approved unrelated work and unaffected.
- No landed changes to production `src/ui/…` or `src/core/…` behavior. The gate's
  negative controls are temporary working-tree mutations used only to prove the tests
  can fail; each is reverted before the gate closes and none are committed. If the
  migration reveals a production bug, record it and stop for a Main decision; a check
  rewrite is not a license to change behavior.
- No migration of rendering/chrome/grid/axis/layout/playhead coverage into the new
  suite — that scope stays legacy by design (section 7).
- No migration of other WindowSystem checks (`rollcheck`, `automation-gestures`, …) in
  this effort.
- No committing/merging; worktree only.

## 3. Baseline (existing evidence)

- Legacy single runner: `runVelocityPageCheck`
  (`src/checks/rollcheckpsgvelocity.cpp:1818-2103`). Structure: scratch-project fixture
  phase (`:1825-1935`, loads `mus_route101` via `checks::LoadedSong`, wheel-zoom and
  marker assertions), in-memory synthetic SMF phase (`:1936-2029`), then **21 helper
  invocations at `:2042-2062`**, inline playhead performance probe `:2064-2077`, inline
  keyboard no-op probe `:2079-2098`, optional screenshot `:2099-2101`.
- Helper definitions (same file): `checkDrawerToggleGeometry` `:310`, `checkDrawerToggleInput`
  `:341`, `checkDirectSoundChromeAndFocus` `:377`, `checkContinuousGraduationDensity` `:398`,
  `checkGridContinuesPastSongEnd` `:425`, `checkPanClampAtTickZero` `:458`,
  `checkPsgAxisContexts` `:485`, `checkHoverAxisContext` `:530`, `checkVelocityRendering`
  `:581`, `checkEditCursorRepaint` `:700`, `checkDrawerContextTickRounding` `:731`,
  `checkRelativeDragDefersCommit` `:768`, `checkPointerUngrabCancelsProvisionalSelection`
  `:885`, `checkDragBandOverlay` `:908`, `checkStackedNodeHitPriority` `:978`,
  `checkPaintGestureDefersCommit` `:1136`, `checkRampGestureCommits` `:1178`,
  `checkBlankAndGraduationClicks` `:1249`, `checkRollVelocityDrag` `:1285`,
  `checkClickBelowSelectedNode` `:1407`, `checkDetentUnlockGestures` `:1451`.
- Cross-helper state coupling (each legacy helper reads state a previous helper wrote):
  `rig.nodeX` set at `:792`, consumed by `checkPointerUngrabCancelsProvisionalSelection:896`;
  `paintFirstBefore`/`paintThirdBefore` written at `:1144-1145`, read by paint/ramp/detent;
  `graduatedFirst`/`graduatedSecond` written by `checkBlankAndGraduationClicks:1277-1278`,
  consumed by `checkRollVelocityDrag:1304-1320`. The new suite: every test function builds
  its own state. The final legacy trim re-homes or eliminates every read a retained helper
  makes of a retired helper's writes (section 11).
- Existing controller cancellation: `checkRollVelocityDrag` calls public
  `SongView::cancelActiveInteractions` (`:1337`); preserve that behavior in a
  dedicated controller-cancellation case. Add independent Escape routing coverage:
  `VelocityArea::keyPress` cancels on Escape
  (`src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp:455-460`).
  System grab loss uses `inputCancelled` (`:463-465`) and retains its own case.
- Catalog: `velocity-page` row `src/checks/checkcatalog.cpp:421-429`
  (`--check-velocity-page {scratch} mus_route101`, `ScratchKind::ExistingDirectory`,
  `FixtureRootKind::DecompProject`); dispatch decl `src/checks/fwd.hpp:61-62`.
- Registry/manifest: `manifestEntry` (`src/checks/checkregistry.cpp:83-99`) serializes
  name/argv/kinds/binary/windowing; `runRequested` (`:120-150`) matches `argv[0]`, slices
  `arguments.mid(commandIndex)` (`:128`), and for `StartupKind::Porydaw` redirects
  QSettings into a per-process temp dir and calls `initializePorydawApplication`
  (`:138-147`). `checks_main.cpp:8-23` owns the single `QApplication` and `--manifest`.
- CMake: `find_package(Qt6 REQUIRED COMPONENTS Qml Quick QuickWidgets Svg Widgets)` at
  `CMakeLists.txt:79` (no `Test`); checks target guarded by `PORYDAW_BUILD_CHECKS`
  (`:63`, `:481`), `qt_add_executable(porydaw_checks …)` `:482-636`, link
  `target_link_libraries(porydaw_checks PRIVATE porydaw_app Qt6::QuickWidgets)` `:645`.
- Deno lane: `deno.json:7` `verify` → `tools/cli.ts verify`. `runVerify`
  (`tools/cli.ts:124-173`) always builds porydaw+porydaw_checks+mid2agb (`:151`),
  rejects `--no-build` (`:125`), folds `--filter` into run_checks args, and strips the
  `--` delimiter, forwarding the rest (`:141-143`). No `--qt` today.
- Runner: `tools/run_checks.ts` pulls the JSON manifest from
  `porydaw_checks --manifest` (`:133-137`), validates windowing modes (`:158-172`),
  substring `--filter` over check names (`:377-384`, `:489-498`), skips WindowSystem under
  `--no-windowing-checks` (`:485-488`), splits offscreen vs window-system pools and
  serializes window-system checks (`:519-524`), and enforces per-check timeout
  (SIGTERM→SIGKILL, `:309-318`), exit code and signal capture (`:326-340`, `:457-460`).
- Reporter: `tools/checks_reporter.ts` — quiet mode prints nothing on pass except the
  summary (`onCheckPass` `:63-75`), failures print only the **last 40 output lines**
  (`:82-87`). Truncation is incompatible with Qt listing/verbose output and with
  multi-failure Qt diagnostics (section 5.4 lifts it for this framework).
- Walls: `tools/checks_walls.ts:28` (`velocity-page: 0.4`), `:47` (`velocity-model`).
- Input synthesis today: `checks::events::sendMouse/sendWheel/sendKey`
  (`src/checks/support/eventsynth.h:15-30`) — direct `QEvent` injection into items. The
  new suite replaces item-level injection with `QTest` at the QQuickWindow level for
  migrated cases; `eventsynth` remains for legacy suites only.
- Timeline assertion seam: `MidiTimeline::events` is a public
  `std::vector<TimelineEvent>` carrying `type`, `data0`, `data1`, and transient
  `noteId` (`src/core/miditimeline.h:18-26,87`). `type` stores MIDI **status nibbles**
  (`:11-16`), so note-on is `type == 0x9` — not `(type & 0xF0) == 0x90` — with
  `data0` = key, `data1` = velocity, and `noteId` valid only on note-ons (`:25`).
- Selection/preview seam: `SongView::previewVelocity` (~`src/ui/songview.h:400`) and
  `SongView::cancelActiveInteractions` (~`:482`) are public.
- Input-extent seam: `TimelineInputItem::bounds()` overrides to the zero-origin local
  extent `{0,0,width(),height()}` (`src/ui/songview/quick/timelineinputitem.cpp:127-130`)
  — the production local input extent, used for readiness gating and input location.
- Identity/lease/windowing seams: `SongTab(SongName, QWidget*)`
  (`src/ui/songtab.h:45`); `SongName` has a **private** constructor — the only
  construction path is the checked factory `SongName::create(QString)`
  (`src/project/projectidentity.h:19-30`), which rejects empty names
  (`src/project/projectidentity.cpp:8-15`). `VoicegroupLease` public surface is
  `get()` + `explicit operator bool` (`src/project/voicegroupsource.h:43,45`); `borrow()`
  is private, `AudioEngine`-only (`:48-58`). `CheckDefinition` defaults `windowing` to
  `Windowing::Offscreen` (`src/checks/checkcatalog.h:18,31`).

## 4. Runner contract (C++ side) — all `[new]` unless marked existing

1. **Framework metadata.** In `src/checks/checkcatalog.h`: add
   `enum class Framework { Legacy, QtTest };` and a defaulted field
   `Framework framework = Framework::Legacy;` to `CheckDefinition`
   (existing struct: `src/checks/checkcatalog.h:20-32`). Existing rows keep the default.
2. **Framework metadata on the wire.** `manifestEntry` (`checkregistry.cpp:83-99`)
   **always emits** `"framework"` with the pinned strings `"legacy"` / `"qt-test"`.
   No fallback default is wanted on the TypeScript side: `deno task verify` rebuilds
   `porydaw_checks` from the same revision before reading the manifest, so
   `tools/run_checks.ts` treats the field as **required and clean** — a missing or
   unknown value fails manifest validation like an unsupported windowing mode
   (`run_checks.ts:158-172`); the `CheckManifestEntry` type gains the required field
   (`:18-25`).
3. **Dispatch declaration.** `src/checks/fwd.hpp` gains
   `int runVelocityEditingCheck(const QStringList &qtArguments);` (frozen interface for
   the parallel units in section 8).
4. **Catalog row.** One entry in `checkcatalog.cpp` next to the velocity rows:
   `.name = "velocity-editing"`, `.argv = strings({"--velocity-editing"})` (unique flag),
   handler forwards the payload to `runVelocityEditingCheck`,
   `framework = Framework::QtTest`, and **`.windowing = Windowing::Offscreen` set
   explicitly** — it repeats the struct default (`checkcatalog.h:18,31`) so the row's
   scheduling class reads at the row itself. Startup is the default
   `StartupKind::Porydaw` — **never** `HandlerOwned`, so per-process QSettings isolation
   applies (`checkregistry.cpp:138-147`). `FixtureRootKind::None`, `ScratchKind::Unused`:
   the suite needs **no disk fixtures** (in-memory `SmfFile` via `applyMidiStage`), and
   the argv therefore contains **no placeholder tokens** — the expanded argv on the
   process command line is exactly `[--velocity-editing, ...qtPayload]`.
5. **Handler argument protocol.** `runRequested` hands the handler
   `arguments.mid(commandIndex)` (`checkregistry.cpp:128`) — the flag plus everything
   after it. The wrapper takes `args.mid(1)` as the Qt payload and calls `QTest::qExec`
   exactly once per process with a dummy `argv[0]` (the suite's object name) followed by
   the payload verbatim. Once-per-process is guaranteed **by the dispatch structure** —
   the catalog enters the handler once per process and the wrapper is its only `qExec`
   site — so no static/assert guard is added. `qExec`'s non-zero return becomes the
   handler return — exit-code contract preserved. Unknown Qt case/function names make
   `qExec` fail non-zero natively; no extra validation needed.
6. **Scheduling.** `velocity-editing` rides the existing Offscreen class: the parallel
   LPT pool, `QT_QPA_PLATFORM=offscreen` forced by the runner, and `--no-windowing-checks`
   **includes** (never skips) the row — zero new scheduling code. The native-only
   serialized worker does not apply to it (existing `run_checks.ts` windowing
   selection and pools).
7. **Settings isolation.** Process-level isolation stays as today
   (`checkregistry.cpp:140-144`). That does **not** isolate case-to-case writes inside one
   process: the suite fixture snapshots and restores any `QSettings` keys a case writes
   with an RAII guard in `init()`/`cleanup()` (section 6.3).
8. **Walls.** `tools/checks_walls.ts` gains a named `"velocity-editing"` estimate row;
   the existing `"velocity-page"` row stays (section 11).

## 5. Deno runner contract — `[new]`

1. **Terminal `--qt` in BOTH parsers.** `tools/cli.ts` `runVerify`: on the bare token
   `--qt` the loop pushes it and forwards every following token **verbatim**, then
   breaks — Qt tokens such as `-functions`, `-v1`, or a `--filter`-looking string are
   never interpreted as runner options (this also stops the existing bare-passthrough
   fallthrough, `cli.ts:129-149`). `tools/run_checks.ts` parses the same way: a bare
   `--qt` arm captures the remainder of `Deno.args` verbatim and breaks; an `--qt=…`
   equals-form is a usage error (exit 2), as is an empty payload. Both usage texts are
   updated (`cli.ts:18-29`, `run_checks.ts:46-58`).
2. **Singleton selection gate.** In `--qt` mode the runnable set — manifest rows after
   `--filter`/`--exclude`/windowing selection (`run_checks.ts:485-512`) — must be
   **exactly one** entry, and that entry's `framework` must be `"qt-test"`; otherwise
   exit 2 naming the cause (zero selected, multiple selected, or a legacy selection).
   Canonical use: `--filter` selects, `--qt` only forwards. Because the row is
   cataloged Offscreen, `--no-windowing-checks` no longer empties the set for it —
   `verify --no-windowing-checks --filter velocity-editing --qt <payload>` selects the
   one offscreen qt-test row and runs it. A WindowSystem-only selection still exits 2
   under that flag (a future headless qt-test suite would work the same way).
3. **`tools/run_checks.ts` spawn.** Strips the marker and appends the Qt payload after
   the selected row's expanded argv: one foreground
   `porydaw_checks --velocity-editing <payload…>` process with the existing invariants —
   timeout SIGTERM→SIGKILL (`:309-318`), exit/signal capture (`:326-340`), native
   window-system serialization, per-process settings. Failure remains
   `result.code !== 0 || signal || timedOut` (`:457`).
4. **Output policy (as implemented).** For an explicit `--qt` invocation the suite's
   **complete raw output** is printed verbatim — success and failure alike
   (`-functions` listings, `-v1` runs, `function:row` runs are the point of the mode) —
   even in quiet reporter mode, driven purely by exit code. In ordinary `verify` mode
   (no `--qt`) every check keeps the quiet pass summary, and the old last-40-lines
   failure truncation was removed outright: any failing check now prints its complete
   output, so Qt multi-failure diagnostics are never clipped and legacy rows are
   unchanged except for that uncapped failure print. No JUnit/XML parsing, no homemade
   assertion aggregation, no dashboards; the framework never parses Qt's human output —
   selection is by name, verdict by exit code.
5. **Examples (target UX):**
   - `deno task verify --filter velocity-editing --qt -functions`
   - `deno task verify --filter velocity-editing --qt dragCommitsOnce`
   - `deno task verify --filter velocity-editing --qt unlockedRelativeKeepsOffsets:wave -v1`
   - `deno task verify --no-windowing-checks --filter velocity-editing --qt -functions`
   Plain `deno task verify` (no `--qt`) keeps running `velocity-editing` as one whole
   suite like every other check; under the standing no-desktop-takeover restriction,
   full-lane runs use `deno task verify --no-windowing-checks`.

## 6. Suite design — `src/checks/velocity/tst_velocityediting.cpp` `[new]`

### 6.1 Shape

- One `QObject` subclass `VelocityEditingTest` with **private slots**; `QCOMPARE`/
  `QVERIFY`/`QTRY_*` only. One catalog row, one `qExec`, data-driven cases use
  Qt `_data()` rows (native `function:row` selection comes free).
- Keep-files-small: the directory `src/checks/velocity/` is the ownership seam with a
  small public surface (the single `fwd.hpp` declaration). As landed: the shared
  `tst_velocityediting.{h,cpp}` fixture/pilot plus one cohesive TU per gesture family
  (selection, hit priority, painting, clicks, roll, detent painting, detent dragging;
  largest file 456L). Splits happened only at real seams, never to chase a line count.
  No predeclared final function count.

### 6.2 Fixture (per test function, built in `init()`)

- Order: borrowed bank objects first (`LoadedVoiceGroup` + `ToneData` values as needed by
  the case: DirectSound default, Square/ProgrammableWave/Noise for detent/graduation
  cases), then the tab:
  `std::optional<SongName> name = SongName::create(QStringLiteral("velocity"));`
  `QVERIFY(name.has_value()); SongTab tab{std::move(*name)};` — `SongTab(SongName,
  QWidget*)` (`src/ui/songtab.h:45`) and the **checked factory** (`projectidentity.h:19-30`;
  the constructor is private, so brace construction like `SongName{"velocity"}` does not
  compile). The bank objects outlive the tab by declaration order; the lease is the
  tab's member.
- Sample rate first: `tab.setSampleRate(48000.0)` on every fresh tab **before**
  `applyMidiStage`. The member defaults to 0.0 (`src/ui/songtab.h:76,133`) and
  `applyMidiStage` builds the timeline from it (`src/ui/songtab.cpp:154`); omitting it
  collapses every sample position to zero and can still pass tick/velocity-only
  assertions without reproducing the production projection (production parity:
  WorkspaceUi sets the audio rate before staging).
- Mandatory staging order: 1. `tab.applyMidiStage(songInfo, std::move(smf),
  trackBudget)` — controlled in-memory `SmfFile` (format 1, division 24, one track,
  `endTick` 84, the duplicate-note pattern from `rollcheckpsgvelocity.cpp:1938-1948`
  extended per case by `document().addNote`; no disk write, no `QTemporaryDir`, no
  `checks::LoadedSong`). 2. `tab.applyBankView(LoadedBankView{id,
  borrowVoicegroupLease(&bank), loadName})` (helpers:
  `src/project/voicegroupsource.h:31,89`, view shape `:448-451`; the routing check
  demonstrates the working order, `src/checks/mainwindowroutingcheck.cpp:384-388`).
  3. `tab.applyVoicegroupBound(id)`. The order is load-bearing: `isReady()` tracks only
  MIDI-bound + identity-bound (`src/ui/songtab.h:64-72`,
  `src/ui/songtab.cpp:180-194`), so binding identity before the bank transiently
  declares a bankless tab ready.
- Ready gate: `QTRY_VERIFY(tab.isReady())` **and** a non-empty bank lease —
  `QVERIFY(tab.voicegroupLease().get() != nullptr)` (lease accessor
  `src/ui/songtab.h:72`, returned by value; public `get()`
  `src/project/voicegroupsource.h:43`, explicit bool `:45`; `borrow()` is private,
  `AudioEngine`-only `:48-58`) — then show the tab's view and gate exposure separately
  (6.3).
- `cleanup()`: the RAII quiesce (6.3) runs even when the body failed midway or returned
  early on a `QVERIFY`, then destroys the tab before the bank (reverse declaration order
  does this).

### 6.3 Qt lifecycles, input, and failure-safe cleanup

- **Distinct gates, asserted in this order where a case needs them:**
  1. *Readiness* — `tab.isReady()` + non-empty bank lease (model/load fact; 6.2).
  2. *Exposure/input surface* — the tab shown; `QTRY_VERIFY(quickWindow->isVisible() &&
     quickWindow->isExposed())` on `TimelineQuickView::quickWindow()` (render fact);
     then `QTRY_VERIFY(!velocityInput->bounds().isEmpty())` (`TimelineInputItem::bounds()`
     is the production zero-origin local input extent, `timelineinputitem.cpp:127-130`)
     and `QTRY_COMPARE(velocityInput->window(), quickWindow)` — the item must live in
     that Quick window before any event is sent (exposure, band-geometry publication and
     input activation are asynchronous).
  3. *Focus* — keyboard cases call the production
     `quick->focusBand(TimelineBand::Velocity, reason)` and then wait for the async
     FocusIn to land: `QTRY_VERIFY(quick->focusedBand() ==
     TimelineBand::Velocity)` (`timelinequickview.h:155-161`,
     `timelinequickview.cpp:646-669` — `focusBand` returns on setup acceptance only;
     keys must hit live Quick focus). Tests that are **about** user focus routing
     establish focus by clicking the band instead of forcing it. Mouse-only cases need
     gate 2, not gate 3.
  4. *Offscreen delivery (replaces the retired native-activation gate)* — the suite
     runs under `QT_QPA_PLATFORM=offscreen` and never requires OS foreground state.
     Every input is synthetic and window-targeted: `QTest::mouseEvent`/`mousePress`/
     `mouseRelease`/`keyClick` on `quickWindow()` only. Keyboard delivery is gated on
     the live Quick seam — `focusedBand()` plus `activeFocusItem() ==` the targeted
     input — which establishes the actual delivery target. No `qWaitForWindowActive`,
     no `QCursor`, and no native reconciliation exists anywhere in the suite.
  Never conflate the gates; missing state is a **failure**, never `QSKIP`.
- **Input coordinates.** Test vectors are written in item-local logical
  `TimelineInputItem` coordinates — the handlers consume item-local
  `event.position()` (`timelineinputitem.cpp:15-26,196-230`) — and every `QTest` mouse
  call on `quickWindow()` converts them with
  `velocityInput->mapToScene(localPoint)`, because window coordinates are offset by the
  band/plot parents; the local vector stays the basis for expected gesture semantics.
  `QTest::mousePress/mouseMove/mouseRelease/mouseClick` and
  `QTest::keyClick/keyPress/keyRelease` aim at the `QQuickWindow`; wheel via the QTest
  wheel variant or a `QWheelEvent` posted to the window as today's `sendWheel` did.
  **Modifiers (as implemented):** the shared helpers never call the modifier-less
  `QTest::mouseMove` overload; modifier-bearing presses, moves, and releases go
  through window-level `QTest::mouseEvent(QTest::MouseMove, window, button, modifiers,
  pos)` calls that carry the explicit mask (config-bindable bindings are read from
  `keymap::Registry`, never assumed), and `QTest::keyClick` takes its explicit
  modifiers. Never fall back to sending directly to the chosen input item or assume
  native OS modifier state.
- **Cancellation paths:** Escape through the focused window exercises keyboard routing
  into `VelocityArea::keyPress` (`velocityarea_interaction.cpp:455-460`). Retain a
  separate controller-cancellation case through public `SongView::cancelActiveInteractions`;
  that production interface is a valid action, not test-built synchronization.
- **Failure-safe cleanup (scope-bound: lives in `cleanup()`, never in a destructor; no
  `QTRY_*`/assertions inside any destructor):**
  - The fixture **tracks every logical button and modifier key the body pressed**, even
    after Escape: Escape clears the item grab, but not the record of held QTest inputs.
  - Qt Test runs `cleanup()` after **every** test function — including an early
    `QVERIFY` return mid-body — so the unconditional best-effort sequence at the top of
    `cleanup()`, before the tab is destroyed, always runs: send Escape to the focused
    input (cancel any surviving interaction), release each tracked logical button via
    `QTest::mouseRelease` at the last known grabber/window, release each tracked
    modifier via `QTest::keyRelease`, then `ungrabMouse()` any residual grabber. No
    failing assertion may skip a later release step.
  - Verification sits **after** that unconditional sequence, at the tail of
    `cleanup()` (e.g. `QTRY_VERIFY(!window->mouseGrabberItem())`); body assertions and
    cleanup-tail assertions stay separate from the unconditional RAII work.
  - RAII `QSettings` guard: snapshot keys under the groups the suite can touch at
    `init()`, restore at scope exit (process-level isolation does not cover intra-process
    case writes; existing redirect: `checkregistry.cpp:140-144`).
  - Spy/output sanity: each `QSignalSpy` created in a body goes out of scope naturally;
    no global state survives because the fixture rebuilds tab+document per case.

### 6.4 From legacy env to suite vocabulary

Legacy `VelocityAreaEnv`/`VelocityAreaRig` (`rollcheckpsgvelocity.cpp:128-152,284-308`)
map to: `tab.document()` / `tab.view()` / `tab.history()` / `tab.timeline()` accessors
(`src/ui/songtab.h:50-62`), the drawer's `velocityArea()`/`chrome()` discovered once per
case from `tab.view().editorDrawer()`, and Quick items found via the window's root
object (`timelineVelocityInput`, `timelineVelocityGutterInput`, `drawerBarInput`,
`drawerDetentInput` — same objectNames as `:1993-2009`).

**No oracle porting.** `VelocityMap::resolve` and the legacy geometry oracle
`expectedVelocityGeometry` (`:111-126`) are **not** imported into the suite — not per
case, not into a fixture header. Expected velocities are literals/test data or simple
spec arithmetic (e.g. `clamp(v+Δ,1,127)`, `33+7 ⇒ 40`, midpoints of fixture velocities).
Production geometry (`velocityToY`, graduation rects, `TimelineInputItem::bounds()`) is
used only to **locate input points** and gate readiness — never to supply expected
answers. The fixture starts local to the single TU; extract a shared
`velocity/fixture.h` only when a genuine shared concept appears (6.1), never as a
pre-arranged oracle/header framework.

## 7. Case inventory and disposition table

Every legacy helper gets exactly one disposition:

- **Moved (editing):** transactions, cancellations, selection/hit testing, paint/ramp
  gestures, roll drag, modifier/detent editing behavior, keyboard routing.
- **Retained in legacy:** unrelated rendering/chrome/grid/axis/layout/playhead checks
  stay in the trimmed `velocity-page` check; every retained helper owns an explicit
  independent setup (no reads of retired helpers' state).
- **Split:** the interaction/transaction contract moves; its mixed *visual* assertion
  (ring/layer/pixel probes) is retained in a legacy owner with independent explicit
  setup. Never a ring/layer probe inside a migrated transaction test; never a
  drag/commit assertion inside a retained visual check.
- **Retired:** dropped, with rationale.

Pilot column: **P1** = step 1 vertical slice (sections 8-9); **P2+** = the cohesive
editing-owner steps (section 8). Migrated cases do **not** carry the legacy rig's
cross-helper reads; each builds its own state (section 3).

| Legacy source (rollcheckpsgvelocity.cpp) | Disposition | New test function(s) / legacy owner | Gate | Contracts |
|---|---|---|---|---|
| `checkRelativeDragDefersCommit` `:768-883` (rebuild lambda `:774-781` NOT carried) | Moved | `dragCommitsOnce` | **P1** | Select 2 nodes; press/move/hold ⇒ `previewVelocity` set for both NoteIds, `document().revision()` and `undoStack()->count()` unchanged, shared selection preserved **as selected NoteIds (model state — no ring/layer probe here)**; second move updates preview again, still deferred; release ⇒ exactly one commit: revision +1, undo count +1, previews cleared, committed velocities == fixture-literal expected values, selection preserved. `QSignalSpy` on `documentChanged` + `tab.edited()`: fires only on release. Timeline seam: reacquire `tab.timeline()`, note-on (`type == 0x9`) `data1` == expected **by NoteId** for both notes. Undo via `tab.history()` ⇒ velocities restored, timeline events restored after reacquire, selection identities of surviving notes preserved (`:862-869`); redo symmetric; click-collapse of shared selection after undo (`:877-881`). |
| — (new keyboard-routing coverage, separate from controller cancellation) | Moved | `escapeCancelsDrag` | **P1** | Mid-drag Escape through the focused window clears previews without revision/history changes; subsequent move/release must not commit. The velocity-area Escape restores the pre-press selection (asserted preserved) — the roll-layer Escape below is the contrasting contract. |
| — (new; press/release without drag from `:805-823` context) | Moved | `releaseWithoutMoveIsNoop` | **P1** | Press+release on a node with no drag ⇒ revision unchanged, undo count unchanged (selection semantics asserted explicitly, not skipped). |
| `checkPointerUngrabCancelsProvisionalSelection` `:885-906` | Moved | `pointerUngrabCancelsProvisionalSelection` | P2+ | Implicit grab via window-level press, then `ungrabMouse()`; provisional selection cancelled, no history residue. Uses its **own** `nodeX`. |
| `checkDragBandOverlay` `:908-976` | Split | moves: `bandSelectionExpandsAndContracts` + `bandUngrabRestoresSelection`; retained: legacy overlay-rendering owner | P2+ | Moved contract: right-drag selector lifecycle at model level — selection-area semantics, contracting clears the abandoned area, ungrab mid-gesture restores selection, release ends cleanly with legacy revision effects. Retained in legacy (independent setup): the translucent fill+edge painting on VelocityTransient (probe contains center). |
| `checkStackedNodeHitPriority` `:978-1134` | Split | moves: `selectedCircleWinsOverStem`, `unselectedCircleWinsOverSelectedStem`, `selectedStemWinsAtStackedStem`, `movedNodeDoesNotClickThrough`, `rightPressPreservesSelectedGroup`; retained: legacy ring-rendering owner | P2+ | Moved: hit priority — selected beats stacked click; overlapping circle beats duration stem (later-painted target, frozen through move, no click-through on moving release); right-press selects immediately (selection ids, incl. group). Retained in legacy (independent setup): node/group **ring rendering** assertions. Fixture adds then deletes its overlap note locally. |
| `checkPaintGestureDefersCommit` `:1136-1176` | Moved | `paintCommitsOnce` | P2+ | Held paint previews non-null with revision/undo frozen; expected velocities are fixture **literals** (blank-start 37/91 avoids pressing the stacked 70-velocity cap) — production `map.representative(...)` is never an oracle; release commits one batch (revision +1, undo count +1), previews cleared. |
| `checkRampGestureCommits` `:1178-1247` | Split | moves: `rampCommitsOnce`; retained: legacy preview-outline owner | P2+ | Moved: Shift-drag across 3 notes; mid preview == simple arithmetic midpoint of the fixture velocities (37/65/93 literals); one batch commit; selection retained. Adds/deletes its own mid note. Retained in legacy (independent setup): ramp-line preview outline probe on VelocityTransient (`song_view_edit_preview_outline`, quarter point). |
| `checkBlankAndGraduationClicks` `:1249-1283` | Moved | split: `blankClickDeselectsOnRelease` + `graduationClickEditsSelectedNotes` | P2+ | Blank press retains selection until mouse-up; mouse-up deselects only, no revision/undo change. Gutter graduation click (click point **located** via graduation geometry `:1271`) sets **both** selected notes' velocity to the **known literal velocity of that graduation level** (fixture spec), independent of any earlier case. |
| `checkRollVelocityDrag` `:1285-1405` | Split | moves: `controllerCancellationStopsRollDrag`, `escapeStopsRollDrag`, `rollDragCommitsOnce`; retained: legacy preview-y rendering owner | P2+ | Cancellation through public `SongView::cancelActiveInteractions` **preserves** the selection (asserted); roll Escape through the focused roll window **intentionally clears it** — production roll Escape is the editor's selection-dismiss command (cancel + clear note/time selection), whereas the velocity-area Escape restores `selectionBeforePress`; the suite pins each layer's own terminal state. Both paths clear staged previews without history changes and prevent a later release committing. Commit uses the configured modifier binding; expected velocities use independent `clamp(v+delta,1,127)` arithmetic. Retain the preview-y visual assertion separately in legacy rendering setup. |
| `checkClickBelowSelectedNode` `:1407-1449` | Moved | `clickBelowSelectedNodeChangesOnlySelection` | P2+ | DirectSound ⇒ Continuous axis; `velocityToY(40)` **locates** the click; expected 40 is a literal ⇒ only that node becomes 40; revision +1, undo +1; sibling untouched. |
| `checkDetentUnlockGestures` `:1451-1814` | Split | moves: `rulerUnlockKeepsRawVelocity` (2 modifier states × 3 voices), `lockedPaintUsesDetents`, `unlockedPaintKeepsRawVelocities`, `lateUnlockKeepsGestureSnapped`, `unlockedRelativeKeepsOffsets`, `unlockedRampInterpolates` (each 3 voice rows); retained: `detentChromeGeometry`, `detentHidesForDirectSound`, `detentToggleRedrawsRuler` stay legacy | P2+ | Moved (modifier/detent **editing**, data rows keyed square/wave/noise so each runs standalone): arrange/read the configured `velocity.detent_unlock` binding; do not pin the incidental default to Ctrl. Unlocked exact values as **literals** — ruler 73 (`:1566-1580`), paint 37/91 (`:1654-1682`); mid-gesture unlock stays snapped to **detent-level literals** (`:1690-1721`; `map.moveLevels` not used as an oracle); relative 33/87+7 ⇒ 40/94 (`:1729-1753`; the Wave half-step center needs the representable-press derivation, section 15); Shift-ramp 37/mid/93 (`:1773-1807`). Retained in legacy, each with independent setup: gutter placement/no-overlap (`:1506-1523`), hides+empties for DirectSound (`:1529-1532`), API-toggle icon/ruler **pixel** comparison (`:1548-1565`, `samePixels` semantics). |
| `checkDrawerToggleGeometry` `:310-339`, `checkDrawerToggleInput` `:341-375` | Retained legacy | — | — | Drawer chrome geometry + toggle input are chrome, not velocity editing; stay in the trimmed legacy check with self-contained setup. |
| `checkDirectSoundChromeAndFocus` `:377-396` | Retained legacy | — | — | Chrome/focus display stays legacy. |
| `checkContinuousGraduationDensity` `:398-424`, `checkGridContinuesPastSongEnd` `:425-457`, `checkPanClampAtTickZero` `:458-484` | Retained legacy | — | — | Axis/grid/layout rendering; the `expectedVelocityGeometry` oracle stays a legacy-local helper, never ported. |
| `checkPsgAxisContexts` `:485-529`, `checkHoverAxisContext` `:530-580` | Retained legacy | — | — | Axis/marker contexts incl. hover leave (`velocityLeave` ⇒ hover state cleared) stay legacy. |
| `checkVelocityRendering` `:581-699` | Retained legacy | — | — | Rendering seam stays legacy verbatim in values: node radius/dip widths, layer colors, graduation rendering. |
| `checkEditCursorRepaint` `:700-729`, `checkDrawerContextTickRounding` `:731-766` | Retained legacy | — | — | Rendering/rounding stay legacy; `drawerContextTick` (`:52-55`) stays a legacy-local oracle. |
| Inline playhead probe `:2064-2077` | Retained legacy | — | — | Playhead performance stays legacy via the `refreshLiveState` playback seam. The new editing suite has **no playhead/live-state case** and no performance exception. |
| Inline keyboard probe `:2079-2098` | Moved | `velocityFocusIgnoresPitchShortcut` | P2+ | Shift+Up on the focused velocity input ⇒ revision unchanged, selection unchanged, both notes' `key` unchanged; `QTest::keyClick` with an **explicit** `Qt::ShiftModifier` argument replaces `events::sendKey`. |
| Optional screenshot `:2099-2101` | Retained legacy | — | — | Keep the existing optional rendering diagnostic on `velocity-page`; the new editing suite needs no screenshot argument. |
| Fixture phase `:1825-1935` (scratch `mus_route101`, wheel zoom anchor `:1884-1895`, marker probe `:1916-1934`) | Retired (new suite) / Retained (legacy) | — | — | New suite: replaced by the in-memory SongTab fixture. Legacy: the trimmed check keeps its scratch-project phase for retained helpers and now owns zoom-anchor/marker setup explicitly (zoom-anchor camera contracts already live at their seam, `src/checks/rollcheck/camera.cpp`). |
| `velocitymodelcheck` (separate headless check, `checkcatalog.cpp:372-377`) | Untouched | — | — | Numerical seam stays where it is. |

## 8. Parallel work units and dependencies

Step 1 is one **vertical slice built in parallel by three units** that converge; no
artificial serial gate between runner and suite:

- **Unit A — C++ integration:** section 4 end-to-end (framework field, manifest
  framework string, catalog row with explicit `Windowing::Offscreen`, `fwd.hpp` decl,
  CMake `find_package(Qt6 REQUIRED COMPONENTS Test)` inside `PORYDAW_BUILD_CHECKS`, PRIVATE link +
  source entry).
- **Unit B — TS runner:** section 5 end-to-end (`cli.ts --qt` terminal marker,
  `run_checks.ts --qt` + singleton gate + spawn, reporter failure-cap lift for qt-test
  rows, walls row).
- **Unit C — suite fixture + pilot cases:** section 6 fixture/window/RAII policy plus
  the three P1 functions (`dragCommitsOnce`, `escapeCancelsDrag`,
  `releaseWithoutMoveIsNoop`) with real SongTab transactions. **No earlier build gate
  with an undefined `runVelocityEditingCheck` and no dummy scaffold**: the declaration
  (interface frozen in the step contract) plus Unit A land in the same step so the
  first build already runs real cases.
- Shared contract fixed up front: the `fwd.hpp` signature, the catalog row shape
  (including explicit windowing), the payload protocol of sections 4.3-4.5, and the
  reporter behavior of 5.4. Units edit disjoint files except `fwd.hpp`/`checkcatalog.cpp`
  (Unit A owns them; Unit C consumes).
- **Steps 2+ are cohesive editing steps, opened only after the Step 1
  fixture contract is proven:** cancellation/no-op completion if anything remains;
  selection gestures (ungrab / stacked hit / band-selector); paint/ramp/blank/
  graduation/click-below; roll drag + modifier routing; detent unlock editing; keyboard
  routing. Rendering/chrome/grid/axis/playhead families are **not** steps — they stay
  legacy (section 7). Each editing step closes with its own gate (section 9).
  Independent families within a step may use separate test translation units in
  parallel. One integration owner maintains the single QObject declaration and
  build entries against a frozen interface; this is not a new generic fixture
  framework. Every owner settles before that step's verification and review gate.

## 9. Staged implementation gates (mandatory per-step close)

For **every** implementation step, including the final legacy trim step:

1. Orchestrator runs scoped verification (subagents never do): `deno task build:checks`,
   then the step's targeted selection — step 1:
   `deno task verify --filter velocity-editing --qt -functions` followed by
   `--qt dragCommitsOnce`, `--qt escapeCancelsDrag`, and
   `--qt releaseWithoutMoveIsNoop`.
2. **Thermo-nuclear step-close review:** dispatch `thermo-nuclear-reviewer` on the
   step's diff. The reviewer skips builds/tests/formatters (orchestrator already ran
   them). Fix every concrete finding, re-run the scoped verification, re-review if the
   fix is non-trivial. Only then advance to the next step. Steps are sized so a review
   is meaningful (per section 8), not one mega-review at the end.
3. **Negative controls (pilot gate; temporary working-tree mutations, each reverted
   before the gate closes).** Deliberately mutate **real production behavior**, one at a
   time, and prove the matching test fails **for the intended reason**:
   - (a) commit during move — relocate the release-time commit into the move path;
     `dragCommitsOnce` must fail on "revision/undo unchanged while held / QSignalSpy
     fires only on release".
   - (b) suppress the release commit — `dragCommitsOnce` must fail on the post-release
     revision+undo assertions and the reacquired-timeline `data1`-by-NoteId assertions.
   - (c) break scene input routing — disconnect the input item from the window (or
     corrupt the window targeting); the mid-gesture positive probe (non-null
     `previewVelocity` while held) must fail, proving events land where the test aims.
   - (d) disconnect SongTab's timeline rebuild — the reacquired-timeline note-on
     `data1` assertions must fail against the stale timeline.
   Restore after each mutation; suite green. Expected-value corruption is **not** an
   acceptable negative control — it only exercises the logging path and cannot prove
   the tests pin behavior.
4. **Isolation proof (pilot gate):** each P1 function passes alone (`--qt dragCommitsOnce`,
   `--qt escapeCancelsDrag`, `--qt releaseWithoutMoveIsNoop`; later, each `function:row`
   alone). Order independence is proven by running the functions **individually and in
   reversed order** — list the function names in reverse in the Qt payload (named
   functions run in the order given). Repeating the same order twice proves nothing.
5. Gate recorded per step: commands run, findings raised/fixed, negative-control and
   isolation results.

Gate progression: **Step 1** pilot slice (A+B+C) → gate → **Steps 2..n** cohesive
editing owners (section 8) → each gate → verification + smoke (section 10) → **Step
final — legacy trim + docs** (section 11) → gate → **section 10 re-run: full verify
after the final trim**.

## 10. Verification and smoke

- Full suite: the user's standing no-desktop-takeover restriction makes
  `deno task verify --no-windowing-checks` the supported whole-lane command. It runs
  every offscreen check — `velocity-editing` whole and the legacy `velocity-page` —
  and skips only the 6 native-only checks, which stay paused by that restriction
  rather than by any failure. Pre-trim result: 58/64 passed, 6 native-only skipped,
  zero failures (3.63 s). The lane re-runs **after the final legacy trim** so the
  trim is proven against the whole non-windowing lane.
- Explicit-mode UX: `--qt -functions`, one `--qt function:row -v1` run, and one
  failure-diagnosis run (a negative-control red) all show full Qt output; an
  ordinary-mode (no `--qt`) forced failure of the qt-test row also shows the complete
  output (no 40-line cap).
- **Gesture smoke — replaced:** the retired "launch the real `porydaw` app binary
  once natively" smoke is superseded by the suite itself: every case drives a real
  `SongTab` through actual press/move/release/key gestures offscreen, which is the
  app-adjacent smoke that never touches the desktop. No native app window is launched
  anywhere in this migration.
- **Direct binary invocation is not a supported lane.** Running
  `build/porydaw_checks --velocity-editing …` (or any GUI check binary) outside the
  Deno lane forfeits the runner's guarantees: it does not set `QT_QPA_PLATFORM` (an
  offscreen-declared suite would then open a real window on a windowed host), skips
  the per-process QSettings redirect, and bypasses the scheduling/serialization
  policy — it is **not isolation-guaranteed; do not call it harmless**. Recommend the
  Deno offscreen lane for every invocation, including one-off `--qt` payloads.

## 11. Step final — legacy trim (complete; thermo review PASS)

- **Trim, not delete** `src/checks/rollcheckpsgvelocity.cpp`. Remove the migrated
  editing helpers (`checkRelativeDragDefersCommit`, `checkPointerUngrabCancelsProvisionalSelection`,
  `checkDragBandOverlay`, `checkStackedNodeHitPriority`, `checkPaintGestureDefersCommit`,
  `checkRampGestureCommits`, `checkBlankAndGraduationClicks`, `checkRollVelocityDrag`,
  `checkClickBelowSelectedNode`, the editing halves of `checkDetentUnlockGestures`) and
  the inline keyboard probe. Keep the optional screenshot, `runVelocityPageCheck`, the
  `velocity-page` catalog row (`checkcatalog.cpp:421-429`), its `fwd.hpp:61-62`
  declaration, and the `checks_walls.ts:28` entry — the retained rendering/chrome/grid/
  axis/playhead helpers and the split rows' visual owners still run there.
- **Repair retained legacy state dependencies:** every retained helper builds its own
  state — re-home the writes retired helpers used to provide (`rig.nodeX`,
  `paintFirstBefore`/`paintThirdBefore`, `graduatedFirst`/`graduatedSecond`, section 3)
  or eliminate the reads. No retained helper may depend on a deleted one.
- Drop only includes that truly lose their last consumer (verify with a symbol grep
  before removing; `eventsynth` stays for other legacy suites).
- `docs/checks-health-plan.md`: the Step 4 velocity note is **recorded** — the real
  `SongTab` pilot supersedes the EditorRig recommendation for velocity-editing only;
  host extraction steps remain authoritative; the reusable `qt-test` framework
  convention is documented there.
- `velocity-modelcheck` remains as-is (numerical seam).

## 12. Acceptance checklist

- [x] One catalog entry `velocity-editing`, argv exactly
      `[--velocity-editing, …qtPayload]`, `Framework::QtTest`, default Porydaw startup
      (never HandlerOwned), **`.windowing = Windowing::Offscreen` set explicitly**
      (repeating the struct default so the scheduling class reads at the row), no
      fixtures; manifest **always** carries `"framework"` with pinned
      `"legacy"`/`"qt-test"` and run_checks requires it; plain `verify` (or
      `verify --no-windowing-checks`) runs the suite whole.
- [x] `--qt` terminal marker in BOTH parsers: verbatim forwarding; `--qt=` and empty
      payload rejected; singleton qt-test gate after filters/exclusions/windowing;
      unknown Qt case exits non-zero; explicit `--qt` preserves complete output and
      listings on success and failure; ordinary-mode failures of a qt-test row print
      complete untruncated output; the framework never parses Qt's human output; usage
      texts updated.
- [x] Suite builds only when `PORYDAW_BUILD_CHECKS`;
      `find_package(Qt6 REQUIRED COMPONENTS Test)` inside that guard; `Qt6::Test` linked PRIVATE to
      `porydaw_checks` only; app target untouched.
- [x] One `qExec` per process by dispatch structure — catalog dispatch enters the
      handler once and the wrapper is its only `qExec` site; no static/assert guard.
- [x] Fixture: bank objects before tab; `SongName::create` checked factory (no brace
      construction); `setSampleRate(48000.0)` before `applyMidiStage`; staging order
      applyMidiStage → applyBankView → applyVoicegroupBound; asserts `isReady()`
      **and** `voicegroupLease().get() == &m_bank`; exposure gate includes nonempty
      input `bounds()` and `input->window() == quickWindow`; keyboard cases wait
      `focusedBand()==Velocity` **and** `activeFocusItem()==` the targeted input after
      `focusBand` — offscreen delivery, so no native activation exists anywhere in
      the suite; input points mapped `mapToScene` to window coordinates;
      modifier-bearing input uses window-level `QTest::mouseEvent` calls with
      explicit masks; no QSKIP in core cases.
- [x] Cleanup: tracked held button released even after Escape cleared the grab;
      cleanup cancels (Escape) then releases inputs **before** destroying the tab and
      runs on early `QVERIFY` return; unconditional RAII sequence kept separate from
      the tail verification (`qWaitFor` grab-clear assert); no `QTRY_*`/assertions in
      destructors; the suite performs **no `QSettings` writes** (the detent toggle is
      in-memory chrome state), so no intra-process restore guard is needed.
- [x] No test-built `documentChanged` connection; no manual live-state bookkeeping and
      no playhead/performance case in the new suite (playhead stays legacy); Escape is
      tested alongside the distinct controller-cancellation contract, and the two roll
      cancellation paths pin their different terminal selections (section 7).
- [x] Commit-path P1 case asserts: preview-deferred → single commit → undo/redo
      symmetric → timeline `type == 0x9` `data1` per NoteId after reacquiring
      `tab.timeline()`. Cancel/no-op cases assert the frozen no-commit contract; they
      are never required to assert a commit.
- [x] Every legacy helper has exactly one disposition (moved / retained-legacy with
      independent explicit setup / retired with rationale); no ring/layer probes inside
      migrated transaction tests; no drag/commit assertions inside retained visual
      checks; expected velocities are literals or simple spec arithmetic — no
      `VelocityMap::resolve`/`expectedVelocityGeometry` oracles in the new suite;
      `velocity-model` untouched.
- [x] Negative controls: real production-behavior mutations (commit during move,
      suppressed commit, broken scene input routing, disconnected SongTab timeline
      rebuild) each make the named test fail for the named reason, then restore →
      green; recorded at the pilot gate.
- [x] Isolation: all 26 test functions pass in separate processes, including every
      data family's rows; `unlockedRelativeKeepsOffsets:wave` also passes as an
      explicit single-row invocation. Reversing all 26 functions passes all 41
      behavior executions (43 Qt results, 0 failures/skips, 583 ms). Function listing
      and complete failure diagnostics are verified through the offscreen Deno lane.
- [x] Per-step thermo reviews completed with findings fixed and re-verified,
      including the final trim; gate records are in section 15.
- [x] Full non-windowing lane `deno task verify --no-windowing-checks` is green after
      the final legacy trim and include cleanup: 58/64 passed, 6 native-only checks
      skipped by the user restriction, zero failures, 3.64 s. The legacy file is
      trimmed, not deleted, with retained helpers self-contained; docs are updated.
      The offscreen SongTab gesture suite replaces the native app smoke.

## 13. Risks and mitigations

- **QTest/QQuickWindow delivery differences** vs item-level `eventsynth` injection
  (implicit grabs, hover synthesis, wheel phases; async FocusIn): pilot P1 is exactly
  the risky surface — if window-level delivery diverges from the item-level semantics
  the legacy checks pinned, the pilot surfaces it before more cases are migrated.
  Mitigate by asserting the same observable contracts, not the same event sequences,
  and by the exposure/geometry/`focusedBand`/activation gates (6.3).
- **Input silently landing nowhere** (a wrong coordinate space targets a dead point, and
  a noop can look like a pass): every gesture case contains a mid-gesture **positive
  probe** — e.g. `dragCommitsOnce` asserts non-null `previewVelocity` while the button
  is held — so a mis-mapped point fails loudly instead of vacuously; the routing
  negative control (section 9.3c) proves the probe has teeth.
- **Modifier state assumptions:** the convenient `QTest::mouseMove` overload has no
  modifier parameter. Verify modifier-bearing movement with a supported window-level
  event facility; never silently replace it with an unmodified move (6.3).
- **Desktop takeover (retired risk):** the suite no longer touches the native window
  server at all — Offscreen catalog row, synthetic window-targeted input, zero
  `QCursor`/`setPos`/`processEvents` calls (thermo-verified). The 6 native-only checks
  remain serialized worker=1 for whenever the user lifts the restriction; until then
  `--no-windowing-checks` skips them. Direct binary invocation outside the Deno lane
  is not isolation-guaranteed (section 10) — always go through `deno task verify`.
- **Exposure flakiness:** all window state waits are `QTRY_*` with generous timeouts;
  never `processEvents`-spin loops; never assert on the first frame.
- **Vacuous negative controls:** an expected-value corruption only proves the logging
  path works. The gate's controls mutate real behavior (commit timing, commit
  suppression, input routing, timeline rebuild) and name the assertion that must catch
  each (section 9.3).
- **`qExec` misuse** (program-name argument forgotten, accidental second invocation):
  once-per-process holds by dispatch structure (section 4.5) — there is no guard to
  forget and nothing to double-invoke; unknown function names fail natively non-zero.
- **State coupling regressions (the legacy disease):** per-case fixture rebuild is the
  structural fix; individually-run plus reversed-order runs at the gate keep it honest;
  the final trim re-homes state that retired helpers used to provide (section 11).
- **QSettings intra-process leakage:** RAII restore in `cleanup()`; only groups the suite
  writes are snapshotted.
- **Retained rendering contracts lost in the trim:** the disposition table names a
  legacy owner and an independent explicit setup for every split/retained visual
  assertion (`samePixels` ruler comparison, layer probes, ring rendering, preview
  outlines); the trim-step review checks the table against the diff.

## 14. Primary Qt documentation

- Qt Test overview and `QTest` namespace (macros, `QTRY_*`, mouse/key helpers, `qExec`):
  https://doc.qt.io/qt-6/qttest.html — https://doc.qt.io/qt-6/qtest.html
- Data-driven testing (`_data()` rows, `function:row` selection):
  https://doc.qt.io/qt-6/qtestdata.html
- `QSignalSpy`: https://doc.qt.io/qt-6/qsignalspy.html
- `QQuickWindow` (exposure, `mouseGrabberItem`, event delivery):
  https://doc.qt.io/qt-6/qquickwindow.html
- `QQuickItem::mapToScene` / grab semantics: https://doc.qt.io/qt-6/qquickitem.html

## 15. Implementation gate evidence

### Step 1 — complete (native-window era)

- C++ integration, runner forwarding/reporting, and the production-backed pilot
  were implemented by three disjoint owners. `deno task verify --filter
  velocity-editing` builds and runs all three pilot cases successfully.
- `--qt -functions` lists the cases. `dragCommitsOnce`, `escapeCancelsDrag`, and
  `releaseWithoutMoveIsNoop` each passed alone. The explicit reversed payload
  `--qt releaseWithoutMoveIsNoop escapeCancelsDrag dragCommitsOnce -v1` passed:
  five Qt passes including lifecycle hooks, zero failures or skips.
- Fifteen actual CLI smoke scenarios passed: listing, isolated/reversed execution,
  empty/equals marker rejection, legacy/multiple/empty/excluded/native-filtered
  selection rejection, unknown Qt function propagation, runner-like tokens after
  the terminal marker, and the existing bare `--` separator.
- `thermo-nuclear-reviewer` reviewed the step and corrected handoffs: final verdict
  **PASS, no findings**. Repairs covered guarded optional previews, unconditional
  teardown before cleanup assertions, valid signal spies, and actual Quick focus
  routing. No-op press accepts an unchanged provisional preview without an edit.
- The pilot now explicitly checks document and reacquired timeline velocities
  remain original while held, not only revision/history counters.

| Temporary production defect | Observed failure in `dragCommitsOnce` |
|---|---|
| Commit from `VelocityArea::pointerMove` | Held document revision 2, expected 1 |
| Cancel instead of committing on relative release | Post-release document signal count 0, expected 1 |
| Ignore `TimelineInputItem::mousePressEvent` | Positive dragged-note preview missing |
| Omit SongTab's document-change `rebuildTimeline()` | Committed timeline velocity 20, expected 16 |

Each mutation was restored independently and the whole pilot returned green after
each restoration. All production files returned to their original snapshots.
The early-commit run with `-v2` retained its complete output beyond forty lines;
the stale-timeline failure also retained full diagnostics in ordinary, no-`--qt` mode.

The CLI smoke exposed one resource-lifetime defect: invalid selections allocated
scratch before exiting outside `finally`. Moving allocation after all validation
fixed it. An isolated `TMPDIR` reproduction created a scratch directory before the
fix and none afterward; the same corrected runner also passed the reversed suite.
The thermo reviewer verified this final lifetime correction.

### Step 2 — complete (native-window era)

- Added eight independent selection/hit cases: provisional ungrab, band
  expansion/contraction, band ungrab, two circle/stem priorities, selected-stem
  priority, moved-pointer identity, and selected-group right click.
- One QObject declaration is shared by the fixture/pilot, selection, and hit
  translation units. Stem-overlap cases arrange their fourth note locally through
  the real document API; no setup depends on a preceding case.
- The first integrated run exposed four failures, including the pilot no-op.
  Isolated diagnostics showed stable geometry. The helper gained an unheld
  synthetic preposition before pressing. This passed the checks below, but did
  not completely synchronize native pointer state; Step 3 caught the remaining
  divergence. No expected behavior or production code was changed.
- All four formerly failing cases passed together, then the complete eleven-case
  suite passed via `deno task verify --filter velocity-editing --verbose`.
- `thermo-nuclear-reviewer` reviewed the settled step: **PASS, no findings**.
  Setup-only add-note history assertions were removed; the actual hit, no-op,
  selection, and projection contracts remain.

### Step 3 — complete (native-window era)

- Added separate paint, ramp, blank-release, graduation, and selected-node click
  cases. Pointer helpers now consume native window `QPoint`s; callers explicitly
  map velocity-item or gutter-item geometry. The gutter is resolved through the
  actual `TimelineQuickView` root, not assumed to be a child of the window content.
- The first ramp run caught a real input-oracle mismatch: rounding both endpoint
  x coordinates shifted the native line away from the rendered middle note.
  Inward integral endpoints now balance around that note, with fail-fast geometry
  assertions. The independently specified velocities remain **37 / 65 / 93**.
- The full sixteen-case run exposed residual earlier-case failures: a preview
  off by one and two no-movement commits. An ordered diagnostic prefix also
  caught a no-op preview changing from 20 to 12. Event traces distinguished
  synthetic timestamps/positions from physical macOS moves arriving during a
  press; geometry stayed constant. Quick hover dispatch can update an active
  gesture even when the physical move reports no button.
- *Historical, superseded:* the shared press helper then synchronized `QCursor` to
  the requested global position and processed native events before a gesture
  existed. The Step 4 offscreen correction deleted this workaround entirely — no
  `QCursor`, no native `setPos` reconciliation, no `processEvents` calls remain
  (`grep QCursor|setPos|processEvents src/checks/velocity/` → zero matches); pressed
  gesture determinism now comes from the offscreen platform itself. No event was
  suppressed then or now.
- `thermo-nuclear-reviewer` approved the ramp and settled shared correction:
  **PASS, no findings**. Two complete invocations of
  `deno task verify --filter velocity-editing --qt -v1` then passed: sixteen case
  bodies plus the two lifecycle results in each run, with zero failures
  (1465 ms and 1511 ms).

### Step 4 — complete (settled after the offscreen correction)

Implementation contract as written at step open (historical record):

- Keep the native-window pointer API unchanged. The shared fixture owns one
  additional `timelineRollInput` pointer for the three real roll gestures.
- Initialize immutable bank metadata before `SongTab` borrows it: program 0
  DirectSound, 1 Square 1, 2 Wave, 3 Noise. Select PSG voices through
  `SongDocument::addLanePoint(0, DOC_CC_VOICE, 0, program)`, not by mutating a live
  bank or manually rebuilding projections.
- Separate roll/keyboard, absolute detent editing, and relative/ramp detent
  editing into cohesive translation units. One integration owner changes the
  shared declaration, setup/teardown, and CMake list.
- Use ordinary `_data` rows for Square/Wave/Noise, with independent literal
  outcomes. Ruler rows also distinguish modifier unlock from disabling detents.
  Do not pin the configured unlock binding to an incidental default.
- Locked paint at raw 73 expects 76/64/76. A locked one-level move from stored
  33/87 expects 44/92 for Square/Noise and 64/127 for Wave. Unlocked relative
  motion expects 40/94; unlocked paint 37/91; unlocked ramp 37/65/93.
  Blank-start paint avoids accidentally pressing the stacked 70-velocity cap.

Implementation outcome (all translation units landed; `src/checks/velocity/` is the
8-file feature directory, largest file 456L):

- **Offscreen correction.** The catalog row moved `Windowing::WindowSystem` →
  explicit `Windowing::Offscreen` (repeating the struct default so the scheduling
  class reads at the row), and the Step 3 `QCursor`-synchronization workaround was
  deleted. All delivery is synthetic and window-targeted; the press helper performs a
  hover `QTest::mouseEvent` move before pressing, with an explicit comment disclaiming
  desktop-cursor warping. No behavior assertion was weakened.
- **25 new executions.** Roll drag commit, controller cancellation, roll Escape, and
  velocity-focus keyboard routing (4 plain functions), plus six data-driven detent
  families with 21 rows: ruler unlock vs detents-disabled (2×3), locked paint
  73⇒76/64/76 (3), unlocked paint 37/91 (3), late unlock 33/87⇒44/92 and 64/127 for
  Wave (3), unlocked relative 33/87+7⇒40/94 (3), unlocked ramp 37/65/93 (3). The
  suite now totals 26 test functions / 41 behavior executions.
- **Rolled viewport correction.** The roll helpers first `ensureRangeVisible` +
  `ensureKeyVisible`, resolve the drag target, `scrollRollBy` the note row to the
  roll input's vertical center, and then **re-resolve** — the first resolution is
  stale once the viewport rolls.
- **Wave input rasterization.** QTest delivers integral window coordinates; the Wave
  voice's detent center sits on a half velocity step and can round to its lower
  neighbor through the window→item mapping. The continuous target is derived from the
  representable press (fail-fast arithmetic pins the +7 raw delta), so all three
  voice rows preserve the independent literal outcomes 40/94.
- **Roll Escape vs controller cancellation.** `controllerCancellationStopsRollDrag`
  ends with the selection preserved; `escapeStopsRollDrag` intentionally asserts an
  **empty** selection — production roll Escape is the editor's selection-dismiss
  command (cancel + clear note/time selection), while the velocity-area Escape
  restores `selectionBeforePress`. The suite respects that layer boundary.
- **Full-suite pass (offscreen).** 41/41 behavior executions, 43 Qt results including
  the lifecycle hooks, 0 failures, 0 skips, 601 ms. The thermo-nuclear isolation
  review (catalog row, fixture/cleanup, input helpers, qExec dispatch, runner
  platform mapping) returned **PASS, no blocking findings**, including the corrected
  roll Escape empty-selection assertion checked against production
  (`pianoroll_commands.cpp:91-100`).
- **Pre-trim lane.** `deno task verify --no-windowing-checks`: 58/64 checks passed,
  6 native-only checks skipped by the user restriction, zero failures, 3.63 s.
  The final cutover and post-trim verification are recorded below.

### Final cutover — complete

- **Legacy trim:** `rollcheckpsgvelocity.cpp` fell from 2,103 to 1,295 lines
  (808 removed). Migrated editing helpers, the shared `VelocityAreaRig`, its
  cross-helper state, and obsolete includes are gone. Eleven retained helpers and
  five explicit visual owners preserve rendering/chrome/grid/axis/layout/playhead/
  performance coverage, the optional screenshot, and the `velocity-page` entry.
  The visual owners establish their own state; none depends on a retired helper.
- **Review:** the final thermo-nuclear review returned PASS, no blocking findings.
  The review also approved the final unused-include cleanup and floating-point
  selector-probe midpoint correction. No velocity oracle or behavior assertion was
  weakened. The health plan's stale “until the planned trim lands” note is removed.
- **CLI isolation:** `--qt -functions` lists 26 functions; each function passes in
  its own Deno process. `--qt unlockedRelativeKeepsOffsets:wave -v1` passes alone.
  Passing all 26 names in reverse order produces 43 passing Qt results, zero
  failures/skips, in 583 ms. An intentionally invalid `-not-a-qt-option` returns
  the expected exit 1 with all 72 diagnostic lines, rather than a capped summary.
  Every invocation used `--no-windowing-checks --filter velocity-editing`.
- **Sanitizers:** with temporary C++ build-cache flags
  `-fsanitize=address,undefined -fno-omit-frame-pointer`, the offscreen
  `velocity-editing` and `velocity-page` checks both passed (2 selected, 1.63 s).
  AddressSanitizer runtime linkage was confirmed; leak detection was disabled and
  both sanitizers were configured to halt on errors. The original empty compiler
  flags were restored and the normal build rebuilt afterward. No permanent
  sanitizer configuration or throwaway script was added to the repository.
- **Final normal lane:** after the final include cleanup (the implementation now
  directly includes `voicegroupsource.h` rather than exporting it from the header),
  `deno task verify --no-windowing-checks` passed 58/64 checks in 3.64 s
  (build 8.83 s), with zero failures and the same 6 native-only checks excluded.
  All new suite C++ files/header and the retained legacy file have clean LSP
  diagnostics; the changed Deno runner files were also checked. Full rebuilds
  still emit unrelated existing warnings in vendored stb, `roundtrip.cpp`, and
  `automationgesturecheck/action.cpp`; no warning was suppressed.
- **Desktop boundary:** the completion proof is synthetic input into offscreen
  production SongTab/QQuickWindow instances. No native app smoke, physical cursor
  movement, or OS input injection was used for the final verification.
