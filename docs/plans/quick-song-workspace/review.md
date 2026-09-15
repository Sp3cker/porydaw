# Plan review evidence

This records plan-quality evidence, not production implementation acceptance.
Runtime commands in the briefs are obligations for the later implementation;
they were not run for this documentation-only task.

## Baseline and source grounding

Planning baseline: `fork-main` / HEAD
`9f651a32406508f35c87df03902d956705df104c`. Three independent scoped scouts
investigated session/model/MainWindow, scene/input/popups, and
geometry/resources/checks. Main checked load-bearing claims against current
source and LSP references rather than treating scout output as authority.

| Finding or proposed shortcut                                       | Adjudication in the written plan                                                                                                                                                                                                    |
| ------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Treat the old worktree as the implementation base                  | Rejected. New worktree from fork-main; old worktree stays read-only reference.                                                                                                                                                      |
| Replace an AutomationPage application-level pencil filter          | Obsolete baseline assumption. Current automationpage.cpp has no such filter; PencilToggle is already in editkeyrouting.cpp. Preserve it.                                                                                            |
| Rewrite EditActions QWidget shortcut/text handling                 | Rejected scope expansion. Other QWidget surfaces remain; this helper is still needed.                                                                                                                                               |
| Shared engine can keep page values in rootContext                  | Rejected. One child context per attachment; root context has no page-specific replacement values.                                                                                                                                   |
| Prototype Controls.Popup proves real popup focus/close behavior    | Rejected inference. Real QuickPopupLayer is currently window-root parented. New plan makes it a canvas FocusScope descendant and requires production popup checks.                                                                  |
| Popup constructor can take a canvas that has not yet been created  | Construction cycle resolved explicitly: context and popup first, canvas creation, setCanvasScope, then interaction binding.                                                                                                         |
| deleteLater alone is safe before context destruction               | Rejected. Retiring popup QObjects retain session ownership; menu panels belong to the layer. Session destruction retires them before context/provider teardown. No retirement registry.                                             |
| A destroyed popup session can retain a swallowed release           | Rejected. Only the outstanding button sequence moves to one window-owned release filter, without keyboard routing or selected-scene state.                                                                                          |
| Qt ungrab always means a physical release                          | Rejected by the prototype regression. Require EventPoint.Released, enabled strip and an actual in-viewport target, not just UngrabExclusive.                                                                                        |
| Plan could use src/CMakeLists.txt                                  | No such baseline file. Production source/QML registration is root CMakeLists.txt; checks registration is src/checks/CMakeLists.txt.                                                                                                 |
| Update only obvious SongTab fixtures                               | Insufficient. LSP and scoped allocation searches identified EditorRig/SongViewRig, raster, activity-meter, raw-view geometry/identity and mid-gesture resize consumers; closed mechanical batches enumerate them.                   |
| Task2 targets timelinequickview_layout.cpp                         | Closed-path validation failed: this source does not exist. Removed it from the write set. publishTimelineBandLayout lives in timelinequickview.cpp, already owned by task1; no new split is needed. The corrected inventory passes. |
| Native tab arrows automatically emit the desired selection request | Made explicit from PrototypeTabStrip.qml:86–96: arrow Keys handlers request the neighbouring delegate session; event.accepted stays false for native KeyNavigation. No currentIndexChanged feedback or model.get API.               |

The proof boundary is explicit: prior prototype results establish Qt-native
composition behavior on Qt 6.11, not the production popup, engine-resource,
CALayer, or session/audio migration.

## Architect blind-spot audit

The requested evidence-plan-architect reviewed the full draft, both SDD rules
and load-bearing current source. Initial verdict: NEEDS_REVISION, chiefly
because gate A would not compile on macOS with the original nativegraphics write
set. Findings were adjudicated rather than accepted mechanically:

| ID  | Finding                                                         | Disposition                                                                                                                                                                                                                                       |
| --- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F1  | Nativegraphics still calls detachWindow after task 1 removes it | Fixed. Task 11 now owns the fixture and existing native scenarios' mechanical migration. Task 23 adds new scenarios only after those files pass gate A and the gate checkpoints.                                                                  |
| F2  | Remaining nativegraphics window-size assumptions lack an owner  | Fixed. All eight named fixture/scenario files are in task 11's closed batch; existing SongViewRig scenarios must pass at A, including playhead-guides. Window/surface lifecycle operations remain window-scoped.                                  |
| F3  | “Dirty/bank-aware” overstates the current title                 | Fixed from workspaceui_tabs.cpp:146–157. Preserve document label/name and document-dirty '*'; bank dirtiness does not change the title.                                                                                                           |
| F4  | Adjacent-command boundary behavior unspecified                  | Fixed, but rejected the suggested clamp for window commands. Preserve Qt's cyclic window navigation; local strip arrows remain inert at a missing neighbour. Source below.                                                                        |
| F5  | “registers5”, “until22” can read as counts                      | Fixed with explicit task references in the Direct contracts.                                                                                                                                                                                      |
| F6  | Repeated gate commands and concurrency paragraphs               | Fixed. Briefs link to canonical controller commands; repeated gate-B prerequisite prose removed.                                                                                                                                                  |
| F7  | Which delegate item is the viewport?                            | Fixed. The delegate root FocusScope is the viewport supplied to attachToPage.                                                                                                                                                                     |
| F8  | Scrollbar comment retains deleted InputGate terminology         | Fixed ownership: task 21 updates it with the final eligibility seam.                                                                                                                                                                              |
| F9  | New registerQuickTypes facade has no justified work             | Removed. Keep existing qt_add_qml_module-generated registration and qrc loading; do not add a no-op registration API.                                                                                                                             |
| F10 | Gate-wide deferral increases integration feedback distance      | Accepted process risk, not a rule violation. Keep settled union builds and bounded task fix/review loops; no speculative partial-build schedule or additional checkpoints.                                                                        |
| F11 | Host and QML invent different font/theme interfaces             | Fixed during audit. One required writable appearance value, exact key/source table, application-instance appearance-event filter and root setProperty updates. No new provider QObject. Architect confirmed the smaller value interface is sound. |
| F12 | Nonexistent task-2 layout file                                  | Fixed during audit; architect confirmed actual ownership in task 1.                                                                                                                                                                               |

F4 primary source: Qt 6.11
[QTabWidget::keyPressEvent](https://raw.githubusercontent.com/qt/qtbase/v6.11.0/src/widgets/widgets/qtabwidget.cpp)
wraps below zero to count-1 and past the last row to zero. Keeping that behavior
avoids an unintended navigation change.

The architect confirmed that the gate graph is acyclic and the frozen-interface,
disjoint-write-set co-production conforms to the execution loop. It also
confirmed that the final scene, focus-entry and appearance contracts do not
retain the per-song window/focus hacks in the future Quick embedding boundary.

Closure review: the architect rechecked F1–F9 against the corrected files and
returned **READY**, with no remaining defects. It explicitly accepted cyclic
window navigation as the behavior-preserving correction to its initial clamp
suggestion.

## Independent implementer-comprehension quiz

Two fresh scouts read only the plan/spec/relevant briefs, not earlier review
reports. They answered 15 scenario questions: seven scene questions and eight
workspace questions. Their self-reported “determined” labels were not treated as
proof; Main checked exact APIs, ownership and ordering against the contract and
source. Several confidently incorrect transcriptions were rejected.

| Scenario                                                             | Result and clarification                                                                                                                                                                                     |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| S1: Attach/detach construction and ownership                         | Construction order understood; corrected the invented &engine.rootContext(), SongView cancellation argument and conflated menu-panel parent. Exact constructor and live-parent table now remove those traps. |
| S2: Close owner between dismissal press/release                      | Window lifetime and reset semantics understood. Follow-up question fixed storage to one Qt::MouseButtons bitmask with per-button clearing.                                                                   |
| S3: Nonzero page origin, menu coordinates and playhead overlap       | Coordinate spaces and full-popup suppression understood; corrected the placement sink to applyLevel, distinct from createPanel.                                                                              |
| S4: Background mode restoration/readiness/no focus recipient         | Eligibility and native scope behavior correctly recovered; no new focus repair or fallback.                                                                                                                  |
| S5: Shared-engine provider/context retirement                        | Isolation and unique provider names understood. Clarified that callers must not depend on synchronous provider deletion or add their own retirement tracker.                                                 |
| S6: Pencil, QWidget text and removed key fallback                    | Fallback and retained QWidget handling understood; corrected setInputWindow's purpose to prompt cancellation on deactivation, not pencil dispatch.                                                           |
| S7: Task ownership and real native proof                             | Task/file ownership, gates and rejection of prototype/direct-controller substitutes correctly recovered.                                                                                                     |
| W1: Model authority and forward move                                 | destinationChild=4 and mutation ordering correct; corrected invented NOTIFY name/payload. Exact zero-argument signals are explicit.                                                                          |
| W2: Selected/background close and teardown                           | Audio-before-lease and detach-before-row-removal correctly recovered. Clarified that Qt delegate retirement needs no manual destruction protocol.                                                            |
| W3: Pointer/user-open/window commands/arrows/ready                   | Focus entry and cyclic-window versus bounded-arrow navigation correctly recovered. Empty-workspace F6/focus entry now explicitly no-op.                                                                      |
| W4: Disabled drag, close buttons and overflow                        | Release-state guard understood. Rejected an invented destination-close-area exclusion; source close presses alone are excluded. Source-row resolution belongs to WorkspaceUi; no new QML lookup API.         |
| W5: Shared interfaces and persistent loading pages                   | Appearance exchange and retention understood; corrected session.quickView to the separate quickView model role.                                                                                              |
| W6: Fresh worktree, reference-only prototype, retained QWidget shell | Correctly recovered without broadening the slice.                                                                                                                                                            |
| W7: Frozen-interface writing, atomic gates and checkpoint reuse      | Correctly rejected waiting for task-1 acceptance inside gate A and reusing its files before gate A acceptance.                                                                                               |
| W8: Real controls/actions and native proof boundary                  | Harness/control paths understood; corrected guessed transport id and made permission approval/denial policy explicit.                                                                                        |

All eight additional implementer questions were closed in the documents:

- Zero-size initial viewport: attach now; normal width/height notifications
  republish the existing geometry (S3).
- Multi-button release tracking: Qt::MouseButtons bitmask, no allocation (S5).
- Popup visibility notification: existing isOpenChanged/isOpen, direct
  association and detach cleanup (S7).
- Provider deletion timing: Qt owns retirement; no synchronous-deletion
  dependency or caller-owned queue (S6).
- Delegate deletion timing: detach scene before row removal; let Repeater retire
  its delegate (S1/S2).
- Active drag visuals: target:null, native pressed/hover states only; no
  speculative re-layout or custom preview (S8).
- Empty-state focus: no-op, not focus on a decorative label (S4).
- Desktop permissions: inspect capabilities; explicit approval for required
  grants; denial blocks native acceptance (plan verification section).

The same scouts then answered bounded correction quizzes from the revised
documents: seven scene answers and six workspace answers. Main checked every
answer; all corrected APIs, ownership chains, edge behavior and approval rules
matched the written contracts. Both reported no remaining missing contract.
These are comprehension results, not a claim that production code already runs.

## Documentation acceptance

Controller validation passed:

- 24 ordered tasks: 21 SDD briefs and three inline Direct contracts.
- Every SDD brief has all seven required headings, at most three target files
  and at most five implementation steps.
- All closed write sets match the task inventory; existing targets resolve, with
  ten explicitly planned new source files.
- Gate A and gate B each have disjoint write sets; later file reuse is covered
  by the stated checkpoints.
- 56 local document links/anchors and the older plan's superseded notice
  resolve.
- No unresolved planning markers.

No production sources were changed, no implementation worktree was created, and
no app build/runtime check was claimed for this documentation-only deliverable.
