# Centralize modifier-mouse hover descriptions

Status: **revision 3 implemented and source-reviewed; native acceptance paused**. The audit preserves the independent quizzes and author rulings; quiz results are not runtime verification.

## Authority and entry gate

- [spec.md](spec.md) owns the forward-facing typed catalogue contract and complete initial profile inventory.
- [The original specification](../spec.md) remains authoritative for behavior except the explicitly superseded presentation-payload contracts in the supplement.
- [The original plan](../plan.md) remains the history of the hover feature's implementation. Its original new-file limit is extended only for the two catalogue files named here.
- [quiz.md](quiz.md) is the original open-book architecture test; [retest.md](retest.md) targets revised boundaries. [audit.md](audit.md) records independent answers, author rulings, architecture revisions, and retest evidence.

Execute only after the original hover implementation and current fixes have settled and passed their own verification. The current implementation is in `.worktrees/modifier-mouse-hints`; documentation is in this main-checkout plan directory. Execution location must be explicitly established by the later implementation request. Do not write production code into the main checkout merely because these documents live here. Do not run two hint-interface migrations concurrently.

**Execution status — typed cutover implemented, native acceptance paused**

- Production work is confined to `.worktrees/modifier-mouse-hints`. Tasks 1–7 are implemented and each has **Spec PASS / Quality Approved**. No commits were made.
- The catalogue is the sole wording/cache authority. All native, C++, QML and concrete test-host producers use complete typed profiles. The old arbitrary-text API, fragment builder, producer caches and widget text/key properties are removed.
- Task 2 review caught a dropped null/native-input admission guard. Its original owner restored the guard before observation transfer and catalogue rendering; the same reviewer approved the repair. A throwaway boundary probe failed both hidden-source/Empty and null-source cases against the pre-fix library, then passed after rebuilding. This is mechanism evidence, not a fabricated permanent user-workflow test.
- Final restored-source proof: `deno task build:checks` **PASS**; `deno task verify --no-windowing-checks --verbose` **79/91 PASS, 12 excluded**; changed-file formatting **40 C/C++ files PASS**. The final run is archived as `artifact://343`.
- The throwaway smoke passes **19 assertions**: 17 cover style preconditions, QWidget/Quick composition, source transfer, metadata precedence and distinct engine identity; two directly probe rejected hidden/null `claim` calls. QWidget hover uses offscreen cursor observation. The Quick phase sends a synthetic mouse event through each real `QQuickWindow` to its actual `DragInput` in two separate `SongView` engines; it does not send directly to the item. This is not spontaneous native hover or a fresh native-app walkthrough.
- Additional desktop-safe evidence: all 12 selected track-header input/menu cases pass; five roll input cases pass before the raster-only failure. Prior software-wrapper selection-key core/window/local-input suites pass. Forced software rendering cannot satisfy the geometry-pixel assertions in selection-key gesture, pitch-bend raster, and roll band selection; each required clean baseline reproduces its failure, including the roll SIGBUS. Offscreen RHI also cannot render reliably. These unsupported-backend attempts are not native-suite passes; no production behavior or assertions were weakened.
- All temporary stashes were restored byte-for-byte and dropped. Seven throwaway build files were removed after the final smoke; their sources and baseline evidence are archived outside the checkout. Quick-start discovery text was updated, and obsolete comments were removed.
- Settled inherited repairs remain intact: neutral automation-tab hover ownership, scrollbar drag rebasing, creation-bound hover-service connections, and actual catalog/selector readiness in the affected fixtures. The entry gate used prior native passes plus the corrected offscreen run and source reviews; it was cumulative coverage, not a new full native run.
- The user explicitly waived the WAV-popup walkthrough and recovery diagnosis. They are out of scope and are not blockers for this cutover.
- The cumulative thermo gate is **Approved, no findings**. The configured specialist was dispatched but hard-stopped on its unavailable legacy skill name; the replacement read-only reviewer executed the full available `thermo-nuclear-code-quality-review` method over the complete refactor and final source, not a lighter generic audit. The independent evidence audit found no false-pass or isolation defect; its count/delivery wording clarifications are incorporated above.
- Final native composed coverage and the complete supported-backend suite remain unexecuted while desktop input is paused; do not label the cutover fully accepted on offscreen evidence alone.

## Goal

A maintainer changes a hover description in one catalogue, not in its QWidget/QML/interaction producer. Producers classify existing targets and send complete profile IDs; the existing hosts own lifetime; the existing caption receives the final text. Preserve all current wording and user-visible behavior.

## Global constraints

1. Read the supplement's spec and the original behavior spec. No action changes, availability filtering, new hit tests, new input handling, new lifetime/recovery state, or generic registry.
2. A clean cutover removes all arbitrary-text producer interfaces and caches. No QString compatibility overload, public fragment builder, string-key lookup, aliases, or parallel old path remains at the acceptance gate.
3. Existing action/hover target resolvers, Qt ownership, popup/native gating, shortcut priority, physical host identity, and status appearance remain unchanged. Do not reopen current fixes while extracting text.
4. Production writes are closed by the task table/briefs. Before dispatch, inspect current symbols and references with the available LSP; re-ground after active-worktree edits. A newly discovered consumer expands its owning task through a documented contract correction, not an ad hoc sibling edit.
5. Main is integration owner. Tasks 1–7 form **one atomic production cutover**: task-local read-only inspection and review are permitted, but no intermediate build, behavioral acceptance, or Git checkpoint of a half-migrated interface. Run shared validation only after every writer has settled.
6. Task 1 establishes the catalogue interface first. Tasks 2–7 have disjoint write sets and can then execute concurrently against this spec. No writer edits another task's files or asks it to invent the contract. Main resolves cross-task discrepancies.
7. Follow `sdd-execution-loop` for SDD tasks. The named Qt writer performs local structural inspection; the controller performs shared builds/tests/formatting at the gate below. Direct task 7 is a same-shape producer migration batch, not a reason to bypass review of changed semantics.
8. No new permanent test is required just to exercise a new enum. Existing concrete-host test adapters migrate honestly. Keep existing behavior assertions; do not re-pin wording tests, assert source text, or add catalogue-enumeration tests. A new permanent regression needs a plausible observable failure not already covered, a closed write-set amendment, and the original plan's realism rule.
9. This plan does not introduce runtime language switching. Cache lifetime is the application-owned catalogue lifetime; preserve existing startup/translation timing. Do not introduce local fallback formatting or regenerate profiles per pointer move.
10. Use only `deno task` for project build/checks/formatting and the applicable verify/offscreen/native-capture skills. One controller owns all validation. Do not mutate an active implementer's code or desktop as part of this document-only task.
11. The only new production files are `src/ui/mousehints/hintprofiles.h` and `.cpp`. Source/catalogue interfaces may use existing Qt/core keymap types; no new generic registration, event, translation, or cache module.
12. Git operations require separate authorization. The milestones below are acceptance boundaries, not permission to commit; any later authorized commit follows the repository push rule.

## Tasks

| Task | Change | Route / writer / reason | Prerequisites |
| --- | --- | --- | --- |
| 1 | [Central profile catalogue](task-1-brief.md) | SDD-track — qt-cpp-reviewer; enum metaobject, semantic extraction, cache contract | Entry gate |
| 2 | [Typed source claims](task-2-brief.md) | SDD-track — qt-cpp-reviewer; QObject source identity and final presentation state | 1 interface; atomic with 3–7 |
| 3 | [Native complete-profile adapter](task-3-brief.md) | SDD-track — qt-cpp-reviewer; widget family/style precedence | 1 interface; consumes 2, atomic with 2–7 |
| 4 | [Physical timeline host transport](task-4-brief.md) | SDD-track — qt-cpp-reviewer; owns host declaration and production adapter | 1 interface; consumes 2; recorder consumers in 7, atomic with 2–7 |
| 5 | [Graph profile retention](task-5-brief.md) | SDD-track — qt-cpp-reviewer; gesture source with retained profile | 1 interface; consumes 2, atomic with 2–7 |
| 6 | [QML profile transport and registration](task-6-brief.md) | SDD-track — qt-cpp-reviewer; QML/C++ enum transport and per-engine exposure | 1 interface; consumes 2/7, atomic with 2–7 |
| 7 | All producer and test-host callers | Direct — inline batch below; same-shape string-to-profile migration with fixed ID mapping | 1 interface; consumes 2/4/6, atomic with 2–6 |
| 8 | Composed verification and cumulative quality gate | Direct — controller; no production write set | All writers settled |

The "consumes" edges describe agreed interfaces, not a need to wait for the sibling's edited file. Only the catalogue contract must be settled before fan-out. If its implementation reveals that the spec is insufficient, amend it before dispatch rather than sending incomplete briefs.

## Task 7 — Direct migration contract

### Target

The following is the exact write set, grouped only for discoverability. Paths are relative to the implementation checkout; no directory wildcard grants write authority.

| Group | Files |
| --- | --- |
| Real test-host adapters | `src/checks/automation/presentation/tst_automationpresentation.cpp`; `src/checks/automation/raster/rasterfixture.cpp` |
| Native annotations | `src/ui/dragspinbox.cpp`; `src/ui/transportbar.cpp` |
| Roll | `src/ui/songview/pianoroll_geometry.cpp`; `src/ui/songview/pianoroll_interaction.cpp` |
| Ruler | `src/ui/songview/timeruler.h`; `src/ui/songview/timeruler_interaction.cpp` |
| Header | `src/ui/songview/trackheadermodel.h`; `src/ui/songview/trackheadermodel.cpp` |
| Automation | `src/ui/editordrawer/automationcanvas.h`; `src/ui/editordrawer/automationcanvas.cpp`; `src/ui/editordrawer/automationcanvas_input.cpp` |
| Velocity | `src/ui/editordrawer/velocityarea/velocityarea.h`; `src/ui/editordrawer/velocityarea/velocityarea_interaction.cpp` |
| Voice lane | `src/ui/editordrawer/voicechangearea/voicechangearea.h`; `src/ui/editordrawer/voicechangearea/voicechangearea.cpp` |
| QML producers | `src/ui/songview/quick/AutomationTabs.qml`; `src/ui/songview/quick/DragInput.qml`; `src/ui/songview/quick/DrawerChromeLayer.qml`; `src/ui/songview/quick/EventListPage.qml`; `src/ui/songview/quick/QuickPopupLayer.qml`; `src/ui/songview/quick/TimelineScrollbar.qml`; `src/ui/songview/quick/TrackHeaderBand.qml`; `src/ui/songview/quick/VoicePickerPrompt.qml` |
| Popup's direct empty claim | `src/ui/songview/quick/quickpopupsession.cpp` |

### Change

1. Migrate both concrete test recorders to task 4's typed TimelineInputHost interface. The recorders keep their owned-state semantics and typed record; do not add rendering or no-op implementations. Task 4 owns the virtual-interface declaration and production override together; this batch owns its recorder consumers. No input event/type changes.
2. Migrate both native annotations to `setWidgetProfile`: the overridden spin editor selects NativeFineSpinEditor and OutputVolumeDial selects NativeFinePageStep. The complete profiles include inherited wheel alternatives; preserve the annotated physical widget.
3. Replace producer text selection with the IDs in the spec's inventory. Remove RollMouseHints/rollMouseHints/rollGutterMouseHint and its forward declaration; TimeRuler's formatting-only mouseHints/mouseHintProfile and members; TrackHeaderModel::scopeHint/m_scopeHint; AutomationCanvas::ensureMouseHintProfiles and cache members; VelocityArea::ensureMouseHintProfiles and its three cached strings; VoiceChangeArea::mouseHintText and cached strings. AutomationCanvas keeps a local `ui::hint_profiles::Id mouseHintProfile() const` classifier and uses it for existing idle publication and stationary refresh. Simple two-way selectors become direct ID selection at their existing call sites, not new forwarding methods. Preserve the ruler's pressTargetAt, the roll's existing note/edge result, and all edit functions. Do not delete unrelated text or remove input guards.
4. Replace every QML HoverHint `text` binding with `profile`, preserving group nesting and conditional target choices. Replace EventListPage::rowHintText with EventRows constants at its actual callers. The inline editor/value prompt chooses TextSelection only for its current text-input hover and Empty for its inert remainder; unedited rows choose EventRows. Empty shields/scrollbars may rely on the explicit Empty default. Remove only hint-construction calls/guards, not HoverHint's service/scope guards, tooltips, or input handlers.
5. Replace the popup's direct call with `claim(source, Id::Empty)` and all remaining producer empty payloads with Id::Empty. No old MouseHints::publish caller remains. Ruler handles and voice plot background both select HorizontalScroll. Remove obsolete includes/comments only where made obsolete by extraction. Use LSP rename/references for cross-file symbol changes where available; do not use text replacement as a substitute for symbol references.

### Acceptance

After the entire atomic cutover, every current producer selects one inventoried ID without assembling hint text, all three hosts satisfy the typed interface, and real composed behavior remains unchanged. **Named checks, controller:** `deno task verify --filter automation --verbose`, `deno task verify --filter mainwindow-routing --verbose`, and the task-8 gate below.

## Verification

Task 8 owns this single shared verification policy. Checks run in the selected implementation checkout, not automatically where this document lives. Load `skill://verify`; load the offscreen/window-capture skills for the corresponding scenario. Do not equate a filter matching zero harnesses with a pass.

1. **Build/registration:** `deno task build:app`. Confirm the new header is processed by AUTOMOC, and the current QML module accepts the profile constants and enum-typed invokable. A successful build is not evidence of runtime enum delivery.
2. **Focused existing behavior:** `deno task verify --filter automation --verbose`; `deno task verify --filter mainwindow-routing --verbose`; `deno task verify --filter pitch-bend --verbose`; `deno task verify --filter rollcheck --verbose`; `deno task verify --filter trackheader --verbose`; `deno task verify --filter selectionkey --verbose`. Confirm actual harness names against `src/checks/checkcatalog.cpp` at execution. These cover the payload consumers and preserve action/key routing; do not invent a `mainwindowrouting` filter without hyphens.
3. **Actual composed smoke:** launch the built native application through the repository's supported launcher and capture its actual window. Hover a C++ roll target, a QML numeric target, an event row and its inline editor, and native fine/ordinary numeric controls. Observe the displayed wording, inherited wheel descriptions and unchanged input results. Move through a no-hint target and two same-profile text fields; verify blank claims and source transfer. Change automation pencil mode with a stationary pointer, drag/release outside, and dismiss a real popup without extra pointer motion. Open a second song tab to prove the same enum registration works in its separate engine. No direct-to-item press/move/release substitution for composed delivery.
4. **Uncertain native edge:** exercise the native spin style-modifier path including Qt::NoModifier with an isolated throwaway Qt smoke in the existing check/application build context if the shipped style cannot provide it. Verify body becomes blank, ordinary editor retains selection, fine editor retains fine drag. No scratch CMake project or permanent catalogue-enumeration test. If a runtime capability is unavailable, record the exact limitation; do not claim it was exercised.
5. **Structural cutover audit:** inspect the complete diff and scoped references. No old MouseHints::publish declaration/caller, public QString claim/setter, fragment invokable, local hint sentences/joins, per-element rendered-text caches, per-widget text/key cache properties, or stale helper declarations remain. The final status text/cache in MouseHints/catalogue/caption is allowed. Verify no new hit tests, ownership state machine, input events, or action eligibility were introduced. This is an inspection, not a source-text unit test.
6. **Finish:** run `deno task format --check` on the changed production/check files; resolve failures under repository policy. Remove throwaway smoke artifacts, update the supplemental execution status/evidence, then obtain one cumulative read-only thermo-nuclear quality review scoped to this refactor and its preserved behavior. An unresolved in-scope blocker prevents handoff. Use the original plan's realism/adjudication rules without reopening unrelated feature design.

The commands above are planned verification, not checks already run during authoring. Passing an architecture quiz also does not establish runtime correctness.

## Milestones and checkpoint discipline

- **Contract milestone:** catalogue spec/brief and comprehension audit accepted; current feature/fixes verified; choose execution checkout.
- **Atomic integration milestone:** tasks 1–7 complete, task-local reviews accepted, full source graph migrated with no shims. No intermediate acceptance of either half of a changed virtual/QML interface.
- **Delivery milestone:** task 8's runtime/structural evidence and cumulative quality verdict accepted. Documentation records limitations honestly.

No production file has multiple planned writers. CMake belongs only to task 1; MouseHints h/cpp only to task 2; widgethints only to task 3; TimelineInputHost declaration and input item h/cpp only to task 4; graph pair only to task 5; HoverHint, registration cpp, and the recovery cpp's native-predicate rename only to task 6; remaining callers only to task 7. If repair requires reusing an already accepted write set, follow the execution loop's reviewed checkpoint rules and existing Git authorization; do not checkpoint an unbuildable partial cutover.
