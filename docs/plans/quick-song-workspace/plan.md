# Quick song workspace — SDD implementation plan

Status: planned, not implemented. Baseline: fork-main
`9f651a32406508f35c87df03902d956705df104c`. Authority: [spec.md](spec.md).
Evidence and audit dispositions: [review.md](review.md).

## Goal

Establish the permanent Quick song workspace as the first vertical slice toward
a fully Quick main window. Keep the existing QWidget outer shell this step. The
final production embedding glue is one WorkspaceQuickHost; no per-tab
QWidget/window or custom focus subsystem remains. This is a source-current
replacement for the previous composition plan, not a continuation of its
implementation branch.

## Execution setup

On implementation authorization, run
`deno task worktree:create -- quick-song-workspace --base fork-main` from the
main checkout. Work only in the printed path; read the worktree-file-tool-safety
skill. Do not create a worktree, commit, merge, delete a branch/worktree or push
merely to author/review this plan. Retain the old worktree read-only. If these
uncommitted plan artifacts are absent from the new checkout, copy this plan
directory only into it; do not copy production sources or the prototype. If
fork-main advanced, re-ground the written interfaces and closed write sets
against the new revision before implementation; do not silently treat old
evidence as current.

## Global constraints

- SDD-track tasks use `qt-cpp-reviewer` as the Qt-heavy implementation seat
  under sdd-execution-loop; task-scoped review is independent. Direct mechanical
  tasks use the stated inline contract. Before exported-symbol changes, run
  current LSP references/definition; use LSP rename when applicable. References
  outside a closed write set require the controller to amend the affected brief
  before writing, never an implicit scope expansion.
- Reuse Qt Quick Controls, native FocusScopes and existing domain/command
  owners. No per-song page registry, focus cache, queued focus repair, global
  keyboard forwarding, fake input fallback, new loading state machine or generic
  compatibility layer. Existing popup-local focus restoration is not tab focus
  history. Do not broaden to other QWidget surfaces, remove QtWidgets linkage,
  or rewrite EditActions' retained QWidget text handling.
- Preserve all existing session/audio/history/persistence/gesture semantics
  unless the spec explicitly changes presentation. Window-level Registry actions
  retain priority over persistent chrome; modal/text exceptions remain. Geometry
  and hit targets use existing layout/typography/font primitives and theme
  roles; no prototype pixel constants enter production.
- New production workspace files stay under src/ui/workspacequick. Existing
  scene modules remain cohesive. New check support stays under
  src/checks/support; extend existing harnesses, not a new standalone
  executable. Do not replace real behavior checks with field-copy, wiring or
  source-text assertions. Remove obsolete QWidget/per-song-window assertions
  rather than repinning them.
- Writers may do source/LSP/local read-only inspection. Only the controller runs
  shared builds, tests and formatters after the relevant writers settle. Do not
  issue a blanket ban on inspection. Native tests/desktop smoke run sequentially
  with other native checks; the Deno runner already serializes WindowSystem
  checks. Do not use raw CMake or mutate bundle compatibility links manually.
- The two mechanical batches are explicitly enumerated same-shape migrations,
  the allowed exception to small per-task write sets. They do not authorize
  behavioral rewrites or wildcard edits. All other writing tasks own at most
  three files. Registration files have one writer per milestone.

## Verification and checkpoint semantics

A task owns its exact source changes and one acceptance predicate. The
architecture cutovers require coordinated files: **A (1–12)** and **B (13–22)**
are atomic compile/behavior gates, not independently shippable partial
migrations. Their interface producers may finish writing before consumers, but
no task is marked accepted or committed until its gate's union builds and its
named predicate passes. Briefs explicitly defer controller verification to that
gate; an unbuildable intermediate tree is not accepted evidence. Within a gate
the write sets are disjoint; the controller integrates the already-frozen spec
contracts, not ad-hoc API negotiation.

A preserves the existing per-song SongTabQuickHost solely to keep the
application runnable while scene ownership changes. Task 9 retargets that
existing adapter; task 22 deletes it. No new transitional per-song module,
owned-window fallback, compatibility alias or parallel scene implementation is
allowed. B is the actual single-window application cutover. Neither gate is a
user handoff; execution continues through C and final native acceptance.

Sparse checkpoint milestones: accepted A before any B task reuses its files
(notably coordinator tasks 1→21 and CMake tasks 11→22); accepted B before C,
including nativegraphics files mechanically migrated by task 11 before task 23
adds scenarios; final accepted C. Group accepted disjoint work at these points
rather than committing every brief. Git persistence follows sdd-execution-loop
and explicit execution authorization; this planning request authorizes no
commits. Any authorized Porydaw commits must be pushed to their corresponding
remote branch. A failed/unreviewed change is never checkpointed as accepted.

Controller commands (all from the implementation worktree):

**Gate A:**
`deno task verify --filter host- --filter rollcheck --filter rollwindowingcheck --filter selectionkey --filter editor-drawer --filter eventviews --filter pitch-bend --filter rendering-playhead --filter playhead-guides --verbose`

**Gate B:**
`deno task verify --filter tabcheck --filter sessioncheck --filter selftest-workspace --filter mainwindow-routing --filter selectionkey --filter rollcheck --filter automation --filter velocity --filter scrollbar --filter trackheader --filter timelinepan --filter eventviews --filter pitch-bend --filter editor-drawer --verbose`

**Gate C/final:** `deno task verify --verbose` (cross-cutting hosting/caller
migration justifies the full normal registry) and targeted
`deno task verify --filter rendering-playhead --filter rollwindowingcheck --verbose`
for task23. Run `deno task format` with the explicit changed C/C++ files; QML is
validated through real component load and native checks, not sent to the C++
formatter. Re-run affected verification after any substantive correction.
Existing opt-in performance/corpus/ASAN jobs are not implied; do not invent a
local ASAN configure command.

Final real desktop acceptance: `deno task build:app`, launch the emitted app
through the supervised process tool, and use computer
accessibility/screenshots/input. Open two fixture songs; exercise tab
click/close/reorder/overflow, keyboard entry and real Space action, note and
automation editing, readiness/reload, real menu/form/pitchbend dismissal and
owner close, audition note-off, playback/native playhead, viewport resizing and
page switching. Observe survivors immediately without helper refocus. Capture
actual native playhead alignment and popup suppression. No native access means
acceptance is blocked, not replaced with offscreen evidence. Code fixes stay in
their owning tasks, with bounded fix/review loops; no final waiver of failed
checks.

Before native desktop acceptance, inspect computer.capabilities and the actual
backend's permission result. macOS Accessibility permission is needed for
AX/control operations; native desktop capture may also require Screen Recording.
Required grants need explicit interactive approval at that point. Do not
silently grant permissions, click OS permission dialogs, or substitute another
automation mechanism to bypass denial. Missing native access blocks acceptance;
it is not a reason to rebuild repeatedly or claim offscreen equivalence.

## Ordered tasks

The index contains route and dependency summary only; each SDD brief links to
shared contracts rather than repeating them. Tasks within one gate may write
concurrently where prerequisite interfaces are frozen; they do not independently
run gates. The `needs` column names interface dependencies, not acceptance or
commit order. Some APIs are mutually integrated within a gate: the spec is the
authority available to every writer before dispatch.

| Task | Work                                                                                  | Route / seat / reason                                                    | Needs                              | Gate |
| ---- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------- | ---- |
| 1    | [T01 — Extract the explicit borrowed scene lifecycle](task-1-brief.md)                | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | Frozen spec                        | A    |
| 2    | [T02 — Make SongView layout follow its item viewport](task-2-brief.md)                | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 1                                  | A    |
| 3    | [T03 — Make drawer image resources attachment scoped](task-3-brief.md)                | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | Frozen spec                        | A    |
| 4    | [T04 — Scope real popup lifetime and focus to its canvas](task-4-brief.md)            | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | Frozen spec                        | A    |
| 5    | [T05 — Retain swallowed releases for the window lifetime](task-5-brief.md)            | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | Frozen spec                        | A    |
| 6    | [T06 — Preserve scene anchors at page-local popup sinks](task-6-brief.md)             | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 4                                  | A    |
| 7    | [T07 — Map native playheads into the shared window](task-7-brief.md)                  | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 1, 4                               | A    |
| 8    | [T08 — Let native item scopes own editor keyboard routing](task-8-brief.md)           | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 1                                  | A    |
| 9    | [T09 — Retarget the existing host for the scene milestone](task-9-brief.md)           | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 1                                  | A    |
| 10   | [T10 — Give checks explicit native scene ownership](task-10-brief.md)                 | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 1, 8                               | A    |
| 11   | T11 — Migrate standalone fixtures and register scene sources (inline below)           | Direct / mechanical or documentation / fixed interface, no design choice | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10      | A    |
| 12   | [T12 — Prove shared-scene and popup lifetime behavior](task-12-brief.md)              | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11  | A    |
| 13   | [T13 — Project authoritative sessions through a Qt item model](task-13-brief.md)      | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | Frozen spec                        | B    |
| 14   | [T14 — Compose tabs and persistent song pages with Qt controls](task-14-brief.md)     | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 1, 8, 13                           | B    |
| 15   | [T15 — Embed one permanent Quick workspace in the retained shell](task-15-brief.md)   | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 13, 14                             | B    |
| 16   | [T16 — Cut workspace collection and selection over atomically](task-16-brief.md)      | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 13, 15                             | B    |
| 17   | [T17 — Make SongTab a window-free QObject session](task-17-brief.md)                  | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 1, 16                              | B    |
| 18   | [T18 — Preserve native window commands without queued focus repair](task-18-brief.md) | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 15, 16, 17                         | B    |
| 19   | [T19 — Prove real tab controls and model invariants](task-19-brief.md)                | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 13, 14, 15, 16, 17                 | B    |
| 20   | [T20 — Prove production cross-toolkit focus and popup transitions](task-20-brief.md)  | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 14, 15, 16, 17, 18                 | B    |
| 21   | [T21 — Remove the remaining per-song embedding focus signal](task-21-brief.md)        | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 15, 17, 18                         | B    |
| 22   | T22 — Migrate QObject session fixtures and delete old hosting (inline below)          | Direct / mechanical or documentation / fixed interface, no design choice | 13, 14, 15, 16, 17, 18, 19, 20, 21 | B    |
| 23   | [T23 — Verify native clipping and surface lifecycle on real pages](task-23-brief.md)  | SDD-track / qt-cpp-reviewer / ownership, model or native input contract  | 7, 16, 20, 22                      | C    |
| 24   | T24 — Document the shipped tab keyboard interactions (inline below)                   | Direct / mechanical or documentation / fixed interface, no design choice | 18, 19, 20, 22, 23                 | C    |

### T11 — Migrate standalone fixtures and register scene sources

**Target (closed write set):**

- `CMakeLists.txt`
- `src/checks/CMakeLists.txt`
- `src/checks/support/editorrig.h`
- `src/checks/support/editorrig.cpp`
- `src/checks/support/songfixture.h`
- `src/checks/support/songfixture.cpp`
- `src/checks/support/quickframebuffer.h`
- `src/checks/support/quickframebuffer.cpp`
- `src/checks/automation/raster/rasterfixture.h`
- `src/checks/automation/raster/rasterfixture.cpp`
- `src/checks/drawerpresentation/velocity.cpp`
- `src/checks/rollcheck/identity.cpp`
- `src/checks/rollcheck/remap.cpp`
- `src/checks/rollcheck/static/geometry.cpp`
- `src/checks/trackheaders/trackheaderinput.cpp`
- `src/checks/trackheaders/tst_trackactivitymeter.h`
- `src/checks/trackheaders/tst_trackactivitymeter.cpp`
- `src/checks/trackheaders/tst_trackheadermodel.cpp`
- `src/checks/nativegraphics/nativegraphics_fixture.h`
- `src/checks/nativegraphics/nativegraphics_fixture.cpp`
- `src/checks/nativegraphics/tst_playhead_quick.cpp`
- `src/checks/nativegraphics/tst_playhead_plots.cpp`
- `src/checks/nativegraphics/tst_playhead_native_mac.mm`
- `src/checks/nativegraphics/tst_playhead_guides.cpp`
- `src/checks/nativegraphics/tst_playhead_autohover.cpp`
- `src/checks/nativegraphics/tst_nativewindowing.cpp`

**Change:** Closed mechanical batch: explicit QuickSceneHost ownership for each
standalone SongView allocation; host member after view/member before borrowed
data destruction, no auto-host-on-query. EditorRig/SongViewRig retain current
public assembly interface. quickframebuffer sizes/captures viewport with
scene/DPR mapping. Root CMake registers task 5's files; checks CMake registers
task 10's files. Remove quickengine header registration if present. Other
SongTab fixtures remain on task 9's host until task 22. Nativegraphics belongs
to this gate: migrate detachWindow to detachScene, viewport size/resize uses to
the hosted viewport, and fixture ownership without changing existing scenarios.
Keep actual window/surface lifecycle operations window-scoped. Task 23 adds new
native scenarios only after this existing harness is migrated and accepted. No
semantic test rewrite in this batch; task 12 owns new host assertions. Consume
spec S3, S8; prerequisites as indexed above.

**Acceptance:** Every existing caller compiles against the scene API and all
SongViewRig-based harnesses, including the enumerated nativegraphics family,
pass their existing scenarios at gate A. Controller runs Gate A after all its
writers settle.

### T22 — Migrate QObject session fixtures and delete old hosting

**Target (closed write set):**

- `CMakeLists.txt`
- `src/ui/songtabquickhost.h`
- `src/ui/songtabquickhost.cpp`
- `src/checks/automation/tst_automationediting.h`
- `src/checks/automation/automationfixture.cpp`
- `src/checks/automation/automationnodedrag.cpp`
- `src/checks/clipboard/clipcheck_test.h`
- `src/checks/clipboard/clipcheck_fixture.cpp`
- `src/checks/drawerpresentation/fixtures.h`
- `src/checks/drawerpresentation/fixtures.cpp`
- `src/checks/eventviews/eventview_fixture.h`
- `src/checks/eventviews/eventview_fixture.cpp`
- `src/checks/pitchbend/tst_pitchbendediting.h`
- `src/checks/pitchbend/fixture.cpp`
- `src/checks/rollcheck/rollcheck.h`
- `src/checks/rollcheck/harness.cpp`
- `src/checks/rollcheck/tst_pianoroll.h`
- `src/checks/rollcheck/velocity_prompt.cpp`
- `src/checks/rollcheck/static/fixtures.h`
- `src/checks/rollcheck/static/fixtures.cpp`
- `src/checks/scrollbar/tst_scrollbar.h`
- `src/checks/scrollbar/tst_scrollbar.cpp`
- `src/checks/timelinepan/timelinepanfixture.h`
- `src/checks/timelinepan/timelinepanfixture.cpp`
- `src/checks/trackheaders/tst_trackheaders.h`
- `src/checks/trackheaders/trackheaderfixture.cpp`
- `src/checks/velocity/tst_velocityediting.h`
- `src/checks/velocity/tst_velocityediting.cpp`

**Change:** Closed mechanical batch: register task 13 and task 15's files and
WorkspaceSongs/SongTabStrip in root CMake QML alias loop+QML_FILES; remove
SongTabQuickHost source entries and delete its h/cpp. Replace standalone SongTab
resize/show/ensurePolished with explicit QuickSceneHost ownership and viewport
sizing, including mid-gesture/mid-prompt resizes. Host member after tab means
host destroys first. Preserve domain assertions and scenario timings; task 20
owns MainWindow fixture. No new test catalog/standalone executable. Consume spec
S1, S8; prerequisites as indexed above.

**Acceptance:** All affected fixtures compile and preserve behavior on
window-free sessions; gate B commands. Controller runs Gate B after all its
writers settle.

### T24 — Document the shipped tab keyboard interactions

**Target (closed write set):**

- `docsrc/manual/shortcuts.md`
- `docsrc/manual/main-window.md`

**Change:** After real smoke establishes behavior, document next/previous, F6
strip entry, arrows/Enter and retained Space transport behavior in existing
manual sources. Explain no new user-visible loading or layout redesign. Do not
claim entire main window converted; no generated docs or speculative future
shortcut changes. Consume spec S4; prerequisites as indexed above.

**Acceptance:** Documented gestures match actual shown-window behavior and
internal links resolve; final documentation validation. Controller runs the
final desktop smoke above and validates the changed Markdown/link targets; no
additional app build solely for documentation.

## Evidence sources and deliberate non-changes

Baseline source anchors: songtab.h class/constructor;
workspaceui.cpp::buildUi/destructor;
workspaceui_tabs.cpp::createTab/removeTab/destroyAllTabs/selectTab/persistTabs;
mainwindow.cpp::onSelectedTabChanged; timelinequickview.cpp constructor and
timelinequickview_window.cpp::detachWindow/eventFilter;
songview.cpp::resolveViewportGeometry/cancelTransientInput;
quickpopupsession.cpp::ensureLayer/end;
quickmenuhost.cpp::createPanel/applyLevel; pitchbendeditor.cpp::placeContent;
drawerchrome.cpp::releaseIconProvider; playheadoverlay.cpp::synchronizeGeometry;
src/checks/checkcatalog.cpp and both root/checks CMake files. Source claims in
old-worktree reports are not authoritative where these differ.

Existing MainWindow widget text controls, transport actions, QWidget
dialogs/docks and EditActions::installWindowShortcuts are intentionally
unchanged. AutomationPage already delegates pencil policy to SongView; retain
that rather than inventing an obsolete-filter migration. QGuiApplication utility
cleanup is not separately scheduled: it does not determine per-song window
ownership and may be changed only within an already-owned file where its old use
depended on the removed host. No claim of a QWidget-free application or
completed fully Quick MainWindow at the end of this slice.

Qt primary sources supporting the selected mechanisms:
[StackLayout](https://doc.qt.io/qt-6/qml-qtquick-layouts-stacklayout.html),
[FocusScope](https://doc.qt.io/qt-6/qml-qtquick-focusscope.html),
[TabBar](https://doc.qt.io/qt-6/qml-qtquick-controls-tabbar.html),
[PointerHandler grab transitions](https://doc.qt.io/qt-6/qml-qtquick-pointerhandler.html),
[eventPoint release state](https://doc.qt.io/qt-6/qml-qtquick-eventpoint.html),
[container window ownership](https://doc.qt.io/qt-6/qwidget.html#createWindowContainer),
[model row moves](https://doc.qt.io/qt-6/qabstractitemmodel.html#beginMoveRows).
Real production checks, not documentation alone, establish behavior.
