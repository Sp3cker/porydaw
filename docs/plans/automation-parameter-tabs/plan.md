# Automation parameter tabs implementation plan

> **Execution:** Use Porydaw's local rule://sdd-execution-loop, not a new orchestration framework. Dispatch one numbered brief to a fresh brief-first implementer, then apply the task-scoped spec/quality review gate. Implementers never commit or run project-wide validation.

**Goal:** Replace the vertical automation stack with all nine selectable labels in the existing gutter and one parameter plot, while preserving every existing node behavior—including the origin phantom—and shared selection semantics.

**Architecture:** AutomationCanvas owns the transient active controller/Tempo identity; Qt controls/layout/text own the selector presentation. Its existing minimumContentHeight API bridges the grid intrinsic height to the C++ drawer allocator. CCLanes retains the complete supported catalog; Tempo and all CC adapters remain in the logical node table. Real Qt Quick labels change only which logical lane is painted/hit-tested. Existing NodeLane, gesture, projection, shared selection and transaction machinery remains authoritative. DrawerSections applies an automation-only label minimum. Remove the old live stack/visibility/scroll/header UI contract; preserve the existing settings schema.

**Technology:** C++20, Qt 6 Quick/QML plus Qt Quick Controls 2 in the current window, existing QtTest/WindowSystem harnesses, Deno build/verify/format tasks.

**Agreed specification:** [spec.md](spec.md). **Reference inventory:** [reference-map.md](reference-map.md). The spec records the user's approved choices and overrides incidental old layout expectations.

**Status:** Feature implementation is partially landed through `0b432f0c`; the bounded audit repairs are complete and verified. The `plan` agent double-checked both the initial corrections and the subsequently measured Voice-readiness repair before their document edits. The user authorized these code/plan corrections and their commit and push, not unrelated implementation. Targeted repair proof is recorded below; pending feature/full-suite/native-smoke gates are not claimed complete. Source line numbers are navigation evidence, never patch anchors.

## Global Constraints

1. Preserve all automation-node semantics and existing musical assertions. An origin phantom remains a view of its source event and edits that original event/tick; no synthetic storage at the viewport edge.
2. Keep all nine logical adapters. Active-tab filtering applies to drawing/ordinary hits, not explicit shared multi-lane command or drag scope.
3. Switching is view-only: no document revision/dirty/undo/cursor/selection/track change. Cancel unfinished owned gestures/forms before switching; foreign popup ownership survives.
4. Include song-global Tempo in the same selector/plot. All labels remain available even empty. Default Volume; retain parameter type in each open SongTab and across primary-track changes.
5. Existing gutter only. At most three measured columns, full labels, smaller typography permitted. Derive automation's minimum from the grid without changing shared minimums, Voice Changes/Velocity rules or the canonical split.
6. Preserve shared keyboard routing; labels consume only advertised activation keys. Active parameter, shared-selection inclusion and focus are distinct states visually and accessibly.
7. Clean cutover: remove Add/Show/Hide, empty/hidden-row registration, individual heights, Tempo pin/collapse, automation scrollbar. Keep EditorViewState storage, codec, remapping and persistence tests unchanged; old row settings no longer drive this UI. Preserve laneRanges, outer drawer state, every event and unrelated scrolling.
8. No unrelated core/audio/QWidget/shared-key refactor, fake fallback or compatibility shim. Refresh LSP references before public API changes. Preserve concurrent user work.
9. Use deno task only. Writers skip format/build/lint/tests; the controller owns settled-tree verification. Native/default-backend evidence is required for node/phantom pixels. Never ignore or hand off check failures.
10. The current request authorizes the audited code repairs and plan corrections. Commit actions require separate explicit authorization and belong to the controller; push every commit made per repository policy. Implementers never commit.
11. Prefer built-in Qt behavior over custom controls and their checks. Adding Qt modules is approved where it removes implementation/test burden. Task 5 uses native TabButton checking/input, GridLayout, Text.HorizontalFit, FontMetrics, Binding and ContextMenu. Local code supplies only styling, the three-column policy, domain/menu wiring and a narrow Enter/Return extension.
12. The controller tracks new or materially rewritten production lines across the entire plan (C++, headers, QML, build declarations and all properties/signals/adapters/glue), reported separately from verified unchanged moves, deletions and test churn. This is accounting, not a limit: there is no numeric cap and no approval step tied to the count.
13. A production helper must name a real product consumer, including a concrete planned QML consumer. Fixture-only navigation stays in existing check support. Reuse a canonical implementation before adding another; never add helper-plumbing checks to justify unnecessary code.
14. Preserve observable behavior, not incidental containers, dead wrappers or copied fixture assumptions. Refresh liveness before preserving/renaming a helper. File-count targets must not force duplicate implementations or leave callers broken.

## Production line accounting — controller owned

This is primarily a presentation refactor and removal of obsolete code, not an opportunity to add another automation subsystem. The 35-task breakdown does not justify a larger implementation. Prefer reuse and simple, boring code over new subsystems.

- **Fixed baseline:** before implementation, record one baseline of the actual starting tree, including the user's existing uncommitted work. Track the aggregate change against that baseline; do not sum successive revisions of the same lines.
- **Count:** new or materially rewritten production code lines, measured as nonblank, non-comment physical lines in normal project formatting. Include C++, headers, QML, build declarations, properties, signals, adapters, cancellation/selection wiring and other glue in both new and existing files. A changed line counts; unchanged surrounding lines do not.
- **Separate accounting:** report verified unchanged code moves, formatting-only changes, production deletions, and test additions/modifications/deletions separately. Unchanged moves require source/destination evidence. Never use net LOC or relocate logic elsewhere to make additions look smaller, and never weaken tests or behavior for size.
- **No cap:** there is no numeric limit, approval threshold or halt condition anywhere in the plan. The tracked count informs controller bookkeeping and the final report; it never gates dispatch, escalates, or changes acceptance.
- **At every settled task and fix/review gate:** the implementer reports its approximate production contribution and any claimed move/format exclusions. The controller verifies them against the fixed baseline, updates the aggregate in the existing task/review record, and gives the reviewer the same count.
- **Final report:** after fixes and cleanup, report the tracked production total and the separate move/deletion/test counts; do not create a new tracking subsystem for this.

**Settled accounting after audit repairs** (nonblank, non-comment physical diff lines; same method as the initial audit):

| Scope / comparison baseline | Production added / deleted | Check code added / deleted |
| --- | --- | --- |
| Landed implementation plus repairs vs `af6befba` | 440 / 748 in 17 files | 1482 / 1198 in 37 files |
| This bounded repair vs `0b432f0c` | 21 / 40 in 3 files | 187 / 169 in 22 files |

Raw line counts including comments/blanks: aggregate production +633/-800 and checks +1782/-1289; repair-only production +21/-44 and checks +208/-202. These figures include extraction and formatting churn; no unchanged-move or formatting-only discounts are claimed. No new permanent test cases accompany the repair.

## File map and ownership

- Catalog/adapters: src/ui/editordrawer/cclanes.h/.cpp; existing core/timedefaults.h and core/xcmd.h supply identities, not new supported controller policy.
- Active identity, cancellation and minimal presentation bindings: automationcanvas.h and new automationcanvas_tabs.cpp. No custom layout/fit cache.
- Plot/input: automationcanvas.cpp and automationcanvas_input.cpp. automationcanvas_gesture.cpp remains the authoritative unchanged phantom/multi-lane algorithm.
- Rendering: src/ui/songview/quick/automationquick.cpp; keep existing NodeLaneQuickPaint paths.
- Labels/context: new AutomationTabs.qml, TimelineCanvas.qml, timelinequickview.cpp and CMakeLists.txt.
- Allocation/scrollbar: drawersections, editordrawer, drawerchrome and DrawerChromeLayer.qml; piano-roll vertical scrollbar APIs are out of scope.
- Old interfaces: AutomationPage, TempoLane, AutomationGeometry, SongView viewstate facades and TimelineQuickScene Tempo header publication.
- Checks: adapt existing automation editing/presentation/hover/raster, selectionkey, host, drawer, scrollbar and native graphics fixtures only where the UI contract changes. Workspace, mainwindow-routing and rollcheck persistence/identity/remap coverage runs unchanged. Briefs give exact write sets.
- Event algorithms, NodeLane adapters/paint, shared key dispatch, playback/audio are non-goals. Domain tests run unchanged; any compile fallout must be reviewed against the spec.

Only two new production files: automationcanvas_tabs.cpp and AutomationTabs.qml. Everything else updates/removes existing cohesive code. No generic tab framework or second state model.

### Qt-owned behavior versus application-owned behavior

| Concern | Decision |
| --- | --- |
| Button input/checking/exclusivity/focus/accessibility action | Native Controls Basic TabButton; bind checked to domain identity, no second selection model or custom press lifecycle |
| Text fitting | Text.HorizontalFit/minimumPixelSize; no C++ or JavaScript font-size search or fitting cache |
| Compact grid and height | FontMetrics plus one at-most-three-column binding; GridLayout handles placement/implicitHeight; one Qt Binding publishes the minimum |
| Context-menu detection | ContextMenu.onRequested, including platform context-menu events; remove the right-button TapHandler |
| Active identity, selection, cancellation and existing menus | Existing AutomationCanvas/selection/QuickPopupSession; no Qt models/actions/menu framework introduced just for nine labels |
| C++ drawer allocation | Reuse minimumContentHeight; one equality-guarded size bridge and existing geometry signal, no second sizing authority or scheduler |
| Nodes, phantom, musical undo/transactions | Keep the existing NodeLane/adapters/paint/gesture code and regression expectations |
| Settings | Leave EditorViewState/codec/remap and their tests unchanged; no schema cleanup bundled with the UI feature |

Task 5 adds QuickControls2 and declares Qt 6.9, matching existing build/release CI. Import Basic locally and QtQuick.Layouts through the existing QML module; verify packaged imports. Do not migrate existing menus/value forms to another Qt subsystem as collateral work. Task 27 owns the small application key-routing integration scenario, not a unit suite for Qt controls.

### Audit decisions and evidence

- Removed the custom nested font-fitting solver, measurement cache and hand-calculated grid minimum. Per-label font fitting is acceptable: a uniform fitted font was the old plan's choice, not the user's requirement.
- Reuse minimumContentHeight rather than add minimumParameterHeight and then delete the old method. Its meaning remains the minimum required canvas content height; only its source changes from stacked rows to the selector.
- Removed settings-schema cleanup and the dependent workspace/main-window/remap test rewrites (old tasks 24, 25, 36). Retaining an existing storage contract is not a new compatibility wrapper for obsolete UI APIs. Old task 26 is reassigned to the missing stroke consumer and main-fixture helper closure.
- Fixed the orphan automationstroke.cpp caller and removed the task-30/35 declared-but-undefined AutomationPage window. Task 4 migrates allocation/callback callers before task 32 removes them.
- A throwaway Qt 6.11.0 offscreen experiment exercised native TabButton click -> checked/model changes -> programmatic reselection, Qt fitting in three/one/two-column layouts, enlarged font, and implicitHeight bound to a C++ QQuickWindow minimumHeight property. All eight reported states had no assertion failures; height-only resize produced no additional minimum notification. This supports native checked bindings and the acyclic intrinsic-size design. It does not prove Porydaw drawer allocation, Qt 6.9 deployment, native pixels or pointer/key integration; those remain implementation gates. Offscreen propagateSizeHints and startup font-alias diagnostics are not native-layout proof.

Primary references: [Qt Text fitting](https://doc.qt.io/qt-6/qml-qtquick-text.html#fontSizeMode-prop), [GridLayout](https://doc.qt.io/qt-6/qml-qtquick-layouts-gridlayout.html), [ContextMenu](https://doc.qt.io/qt-6/qml-qtquick-controls-contextmenu.html), [TabButton](https://doc.qt.io/qt-6/qml-qtquick-controls-tabbutton.html), [Binding](https://doc.qt.io/qt-6/qml-qtqml-binding.html), and [Fowler's small behavior-preserving transformations](https://refactoring.com/).

### Implementation-audit correction gate

The plan prescribed the test-only inverse method, incorrect QObject lookup and unconditional helper renames. Correct those producer instructions and every affected consumer brief, not just the final review checklist. The existing task IDs remain; this is a bounded repair group for already-landed code, not a new orchestration system.

| Prescribing defect | Owner and correction | Existing proof |
| --- | --- | --- |
| Task 2 exposed a fixture-only inverse; task 8 copied a QObject lookup and deferred behavioral proof | Tasks 2/8 own removal and one shared test seam; migrate all landed consumers in the reference-map repair set atomically | Checks build, automation-presentation, and `parameterTabsPreserveDocumentAndSelection` must reach their bodies and pass |
| Task 3's broad renderer-preservation wording retained a zero-or-one vector/loops/search | Task 3 removes collection overhead while preserving compositor/phantom calls and all logical adapters | Existing hover and native raster cases at the renderer repair boundary; no allocation/source-text test |
| Task 29 ordered renames without checking liveness | Delete the dead raster helper; hover helper is already absent; live main-fixture cleanup stays task 26 | LSP caller closure and existing checks; no rename-plumbing tests |
| Task 19 omitted active-parameter consumers and first-frame fixture readiness | Activate Pan explicitly; factor the existing frame wait and reuse it before shown fixtures publish geometry | Both Pan cases and all Voice pixel cases pass; existing minimum/voice-cap/handoff checks pass at normal font; enlarged-font proof remains open |

**Shared seam:** relocate the existing `quick_popup::visualDescendant` traversal into `checks::support` in timelinequickcheck.h and remove the old implementation and six local copies. Do not add another canonical traversal or compatibility alias. One new test-only `automationParameterIndex(canvas, row)` scans validated `parameterRow(index)` until no row exists; it does not reconstruct a catalog or allocate a label list. Keep suite-specific real pointer/key delivery and readiness checks. Coordinate queries never activate a parameter.

**Atomic recovery:** helpers and their popup callers migrate together; migrate all current inverse/lookup consumers, then remove the production inverse declaration/body and its inverse-roundtrip assertion in the same settled change. Task 8 owns the seam; the controller owns the cross-task integration, using the exact repair write set in reference-map.md. The corrected blueprint adds task 8 prerequisites below; it does not claim the historical implementation used that order.

**Pre-repair evidence at `0b432f0c`:** domain/presentation/hover/native raster passed; the focused editing case failed in fixture initialization; drawer had two missed Pan activations and three unresolved Voice pixel failures. The scrollbar absence assertion is explicitly deferred until task 31. Enlarged-font/minimum proof and final full-suite/native smoke remain separate obligations. Never report these deferred or failing cases as green.

**Measured readiness cause:** in the full drawer suite, the first Voice crop was requested at `QRect(0,325 1000x102)` but the band was at `QRect(0,369 1000x102)` after capture processed exposure/rendering. The isolated case began at y=369 and passed; captured PNGs showed displacement. No drawer fixture changes the application font. Task 19 owns the seven-file repair: reuse the existing exposure/afterRendering wait, with its original deadlines and explicit-show precondition, before shown rigs and drawer fixtures return ready. No new retry loop, discarded frame capture or changed Voice pixel tolerance.

**Post-repair proof, Qt 6.11.0/macOS:** domain, presentation, hover, native/default-backend raster and the full editor-drawer suite pass. The focused `parameterTabsPreserveDocumentAndSelection` body and native `automationHoverDecor` scenario pass. Final runs exclude temporary diagnostics. The diagnostic idle/stopped Voice PNGs were byte-identical after the repair. Removed only inverse-roundtrip, obsolete row-height and incidental prompt-wording/initial-number assertions; musical, range, undo, selection, focus and pixel checks remain. No new permanent test cases were added. Local clang-format is 21 while CI pins 22; local formatting is not a CI-version claim.

**Still deferred:** the scrollbar absence assertion awaits task 31; complete editing-suite migration awaits task 26. Full-suite, enlarged-font/minimum and complete native app-smoke obligations remain. None is represented by the targeted green runs above.

## Numbered execution tasks

Aim for at most three files, five steps and one acceptance predicate per brief. Named cohesive exceptions are task 8's six-file shared seam and task 19's seven-file measured drawer-readiness repair; complete caller closure and one canonical implementation take priority over file-count targets. Task 29 has only two potential deletion files, not a rename exception. Binding constraints repeat because each implementer starts without conversation history.

| Task | Brief | Files | Prerequisites |
| --- | --- | --- | --- |
| 1 | [Canonicalize the supported parameter catalog](task-1-brief.md) | 3 | — |
| 2 | [Add view-local parameter identity and Qt presentation bindings](task-2-brief.md) | 3 | 1 |
| 3 | [Replace stacked geometry and drawing with one parameter plot](task-3-brief.md) | 3 | 2 |
| 4 | [Route parameter input and expose the canvas to Quick](task-4-brief.md) | 3 | 3 |
| 5 | [Install accessible compact parameter labels in the gutter](task-5-brief.md) | 3 | 4 |
| 6 | [Honor the automation-only label minimum and full plot width](task-6-brief.md) | 3 | 5 |
| 7 | [Retire lane visibility actions without changing event deletion](task-7-brief.md) | 3 | 5 |
| 8 | [Give the editing fixture real parameter activation](task-8-brief.md) | 6 | 5, 6 |
| 9 | [Preserve phantom source editing and normal node gestures](task-9-brief.md) | 3 | 8 |
| 10 | [Preserve shared multi-lane edits behind the single visible plot](task-10-brief.md) | 3 | 8, 9 |
| 11 | [Prove parameter switches invalidate stale forms and gestures](task-11-brief.md) | 3 | 8 |
| 12 | [Migrate parameter menus and clipboard surface tests](task-12-brief.md) | 3 | 7, 8, 11 |
| 13 | [Replace pinned Tempo presentation tests with tab presentation](task-13-brief.md) | 3 | 5, 6, 8 |
| 14 | [Adapt hover fixtures to parameter activation](task-14-brief.md) | 3 | 5, 6, 8 |
| 15 | [Adapt raster fixture identity and preserve native node pixels](task-15-brief.md) | 3 | 5, 6, 8 |
| 16 | [Preserve raster interaction and native playhead alignment](task-16-brief.md) | 3 | 9, 15 |
| 17 | [Remove automation-scrollbar tests without weakening remaining scrollbars](task-17-brief.md) | 2 | 6, 8 |
| 18 | [Retire stacked-layout editing cases while retaining input routing](task-18-brief.md) | 3 | 8, 13, 17 |
| 19 | [Verify automation minimum without changing other drawer sections](task-19-brief.md) | 7 | 6, 13 |
| 20 | [Migrate shared-selection probe and core fixtures](task-20-brief.md) | 3 | 5, 6, 10 |
| 21 | [Preserve shared gesture arbitration after removing the automation thumb](task-21-brief.md) | 3 | 20 |
| 22 | [Preserve window-tier selection and SongTab lifetime behavior](task-22-brief.md) | 3 | 20, 21 |
| 23 | [Preserve host seams and cancellation transactions](task-23-brief.md) | 3 | 6, 20, 22 |
| 27 | [Preserve label-local activation and shared keyboard fallback](task-27-brief.md) | 2 | 22 |
| 28 | [Preserve pencil edits on empty supported parameters](task-28-brief.md) | 1 | 8, 9, 10, 12, 18 |
| 26 | [Complete stroke activation and editing fixture cutover](task-26-brief.md) | 3 | 8, 9, 10, 12, 18, 28 |
| 29 | [Audit obsolete expansion helpers after semantic migrations](task-29-brief.md) | 2 | 14, 15, 16, 26, 28 |
| 30 | [Remove obsolete SongView lane-visibility facades](task-30-brief.md) | 2 | 7, 12, 23, 26, 28, 29 |
| 31 | [Remove automation scrollbar chrome end to end](task-31-brief.md) | 3 | 4, 6, 17, 19, 21, 22, 27, 30 |
| 32 | [Remove canvas row-resize and pinned-Tempo machinery](task-32-brief.md) | 2 | 18, 28, 29, 30, 31 |
| 33 | [Reduce TempoLane to its unchanged musical adapter](task-33-brief.md) | 3 | 3, 13, 16, 29, 32 |
| 34 | [Remove CC stack metrics and default-visible presentation constants](task-34-brief.md) | 3 | 1, 3, 7, 18, 30, 32, 33 |
| 35 | [Remove automation page scroll and per-row sizing state](task-35-brief.md) | 3 | 30, 31, 32, 33, 34 |
| 37 | [Remove obsolete Tempo header scene publication](task-37-brief.md) | 3 | 3, 5, 13, 16, 33 |
| 38 | [Remove unused lane-stack geometry constants](task-38-brief.md) | 2 | 18, 28, 32, 33, 34, 35, 37 |

The table order is the safe default; task 26 now follows task 28. Withdrawn numbers 24, 25 and 36 are intentionally not dispatched. Production tasks share canvas/scene/header ownership; do not run those writers concurrently. Independent suite migrations may be batched only after prerequisites exist and their exact write sets are disjoint. The controller owns integration, shared headers and proof. No worker validates while another writer is active.

Tasks 1–2 are additive preparation; 3–7 make the intentional UI feature change; the active tasks through 29 adapt only affected consumers; 30 onward remove unused UI interfaces after callers move. Do not describe the new UI behavior as a pure refactoring. Preserve musical behavior throughout.

After every settled task, the controller builds the checks target before closing its compile gate. Keep declarations, definitions and callers together; do not accept broken compilation until the end. Build success is compile-complete only. Run focused behavioral coverage at coherent checkpoints: unchanged domain coverage after preparation; actual selector/allocation smoke after tasks 5–7; task 8's existing all-label case immediately before dependent fixture migrations; each migrated suite when its fixtures are complete (the full editing suite closes at task 26); relevant suites after every API removal or renderer repair. Do not run obsolete stacked-layout assertions against an intentionally changed surface and call their failure a regression fix; migrate those named cases without weakening musical assertions. The final full-suite/native gate remains mandatory.

Refactoring guard: retain method names and signatures only while they express a live responsibility (rows, laneBody, coordinate queries, minimumContentHeight). No wholesale renderer rewrite, adapter replacement or settings cleanup; preserving NodeLaneQuickPaint calls does not require keeping a single-element vector or search. Delete caller-free wrappers rather than renaming or testing them. A caller outside an exact write set requires a bounded caller-migration update before API deletion, never an undefined-symbol interval or compatibility stub.

## Node-preservation matrix

| Required behavior | Existing machinery kept | Required proof |
| --- | --- | --- |
| Phantom source event/tick; no viewport-edge insertion | originPhantom, originPhantomAt, nodePointHit, NodeLaneQuickPaint .phantom | Task 9 extends scrolledOriginPhantomCommits for CC/Tempo with away/back switching and undo; 14–16 retain native hover/raster source checks |
| Explicit/implicit defaults and Tempo lead-in | Adapter points/leadIn and static composition | Existing emptyTempoStorageComposesNoLeadIn, firstNonzeroTempoPointComposesImplicitLeadInCurve, explicitTickZeroTempoPointSuppressesLeadInCurve and projectionCanvasOrigin |
| Drag/modifiers/stationary/delete/double-click | Existing node gesture state machine | Existing automationnodedrag cases; adapt activation/geometry, never musical expectations |
| Pencil/sweep/ramp/snapping/bend | Existing gestures and projection | Task 28 replaces artificial CC11 with empty supported CC1; retains transaction/tick/value/bend results; domain suite unchanged |
| Selected nodes in unpainted lanes | Complete logical table and collectSelectedNodeDrags | Task 10 preserves mixed Tempo/Pan/LFO same-tick order, untouched Volume, transaction/undo/redo after real tab switches |
| New band selection | Existing band gesture with active endpoints | Task 10 asserts separate Tempo/CC bands select only the active parameter |
| Value prompts/menus and stale handles | Revision/row/session guards and cancelInteraction | Task 11 switches during prompt/drag, attempts stale accept/release; foreign-session tests remain |
| Parameter commands/deletion | Existing clipboard/range and guarded confirmation | Tasks 7/12 preserve data effects/undo; labels remain after Clear/Delete; no Add/Hide/Show |
| Lifetime/input cancellation | Existing SongView/Quick ownership | Automation ownership, host lifecycle, selectionkey; tasks 22/23 retain relevant cancellation rows |
| Selection/tab identity | EditorSelectionModel and view-local active type | Tasks 8/10/22/27 prove unchanged bytes/undo/scope, label keys and SongTab/track transitions |
| Geometry/rendering | Canonical input-host bounds, same clip/paint paths | Tasks 13/16/19 prove minimum/enlarged-font labels, active-only nodes, borders, native phantom and playhead alignment |

Never repin point ticks, same-tick order, explicit/implicit storage, undo grouping or command targets merely because a fixture assumed stacked rows. Such a failure is a production regression until proven otherwise. Tests only about removed stack/header/scrollbar plumbing are deleted, not repinned.

## Controller proof gate

After all implementation/review gates settle:
The controller applies the production line accounting above and reports the final counts in the delivery report; no line-count condition applies to final verification or acceptance.


1. Refresh references across affected UI/check folders. Removed UI APIs have no remaining consumer; preserved EditorViewState/codec/remap references are explicitly not removal targets; unrelated piano-roll scrolling is not a false positive. Format edited supported files once with deno task format. No source-text tests or warning suppression.
   At the shared-seam repair boundary, run `deno task verify --filter automation-presentation --verbose` and `deno task verify --filter automation-editing --verbose --qt parameterTabsPreserveDocumentAndSelection`. The focused case must execute its behavioral body, not merely init/cleanup. Existing hover/native-raster cases also run when the renderer repair settles. Do not add a separate test suite for these helpers.
2. Compile and run focused coverage. Exact registered filters from src/checks/checkcatalog.cpp:

~~~sh
deno task verify --filter automation- --verbose
deno task verify --filter selectionkey --verbose
deno task verify --filter editor-drawer --verbose
deno task verify --filter scrollbar --verbose
deno task verify --filter host- --verbose
deno task verify --filter mainwindow-routing-state --verbose
deno task verify --filter selftest-workspace --verbose
deno task verify --filter projectworkspacecheck --verbose
deno task verify --filter sessioncheck --verbose
deno task verify --filter rollcheck --verbose
deno task verify --filter playhead-guides --verbose
deno task verify --filter rendering-playhead --verbose
~~~

These commands build first. The controller may avoid duplicate runs by running full verify once and recording every listed family; never silently omit a family. Read skill://verify and skill://porydaw-offscreen-window-checks before choosing backend/invocation settings. Avoid repeated desktop-input stress runs while the user uses the machine.

3. Exercise the real native Quick surface through the adapted WindowSystem fixtures, and launch the built app once through hub using the executable path reported by deno task build:app. Creation is not readiness: observe an exposed/rendered window without QML errors. Use skill://capture-macos-app-window for a bounded screenshot of the correct process window. No Instruments trace.

Native smoke matrix:
- At automation minimum/normal font: all nine full labels fit, every click changes the sole plot, no automation scroll strip, unchanged horizontal camera/grid alignment.
- At enlarged font/minimum supported host geometry: resize down to the derived minimum; all labels remain usable/unclipped. Larger height expands the plot, not a stack. Velocity/Voice Changes sizes/cap/handoff unchanged.
- With explicit multi-lane selection: cycle labels and verify unchanged bytes/revision/undo/selection and scope indicators on inactive included parameters. Group edit and undo through the existing command path.
- For CC and Tempo: scroll horizontally past a stored node, switch away/back, hover/drag the origin phantom. Observe paint/held-value readout; edit the original source tick, commit once, undo to exact prior bytes. No viewport-edge duplicate.
- Switch during provisional drag or pending prompt; attempt old release/accept: no wrong-parameter edit. Fresh edits recover; foreign popup ownership preserved.
- Choose different parameters in two SongTabs, switch tabs, change primary track and edit: the chosen type follows the intended tab/track; Tempo remains global. Exercise Enter/Space, Tab and a shared edit key from a label.

Native harnesses provide deterministic real pointer/keyboard input. Software/offscreen captures do not prove QSG pixels. If native capability is unavailable, finish reachable checks and report the exact missing proof; do not call it verified.

4. Final complete gate:

~~~sh
deno task verify --verbose
~~~

Expected: all harnesses pass, no assertion/QML/runtime failure. Resolve failures before handoff. Review the changed GUI against user expectations, not merely compilation.

5. After smoke proves behavior, perform required delivery cleanup. Only then append concrete documentation/cleanup work to the controller execution todo: update SPEC.md's addable-lane/pinned-Tempo prose and clarify that stored old row settings no longer drive this UI (the storage format remains unchanged); replace stale Add-lane material in docsrc/manual/automation.md with implemented selector/Tempo/selection/phantom behavior. Preserve unrelated manual stubs and do not invent supported parameters. Remove throwaway scripts. Add a changelog entry only if an established applicable changelog exists. Do not add tests merely to demonstrate work. Reverify if cleanup changes behavior.

## Execution and review contract

- Initialize each of the 35 active tasks in table order as its own todo. Do not initialize withdrawn tasks 24, 25 or 36, compress active tasks into phases, or track them from memory.
- Dispatch the exact brief to sdd-implementer. On NEEDS_CONTEXT, resolve source/tool facts first and revise a bounded brief; never ask the user for repository-provided information.
- Apply local task-scoped spec/quality review after each task. Fix/re-review up to the local five-round cap, then escalate the concrete unresolved issue. Never silently accept failed review findings.
- Review additions against their named runtime consumers and the user-visible invariants protected by existing coverage. Test-only helpers stay in test support; an unnecessary helper is deleted, not given new tests to justify retaining it. Check liveness before preserve/rename decisions and identify implicit behavioral consumers (default active parameter, geometry, focus), not just compiling references.
- Track the aggregate production-line count at every settled task and fix/review gate and report the final count. The count is informational bookkeeping: it never gates dispatch, review or acceptance, and no dispatch context mentions an allowance.
- Controller integrates and validates after writers settle. The final report distinguishes actual proof from unrun checks and names blockers. A phase boundary is not a handoff.
This corrected plan governs continuation and the authorized audit repairs; its text does not itself authorize further scope or a commit.

## Plan self-review

Review coverage: catalog, Tempo, node/phantom invariants, selection, sizing/font, keyboard/accessibility, menus/lifetime, persistence, exported and implicit behavioral consumers, and native/full verification. The `plan` agent verified the corrective approach before edits; its duplication finding changed the shared lookup from an additional implementation to a relocation. Exactly two production paths are new. The 35 task IDs remain; task 8/19's named cohesive exceptions and task 26-after-28 ordering are explicit. Corrected helper consumers depend on task 8; current code repairs integrate atomically without claiming the historical order or incomplete gates passed.

Method: original [writing-plans skill](https://github.com/obra/superpowers/blob/main/skills/writing-plans/SKILL.md), adapted to the mandatory local SDD brief/review loop. Accessibility API: [Qt Accessible documentation](https://doc.qt.io/qt-6/qml-qtquick-accessible.html).
