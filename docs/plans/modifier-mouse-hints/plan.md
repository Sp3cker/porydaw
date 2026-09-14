# Modifier-mouse status hints

Status: **revision 3 — READY for implementation dispatch**. Realistic workflow acceptance and mandatory scope-bounded thermo gates are verified. The first [quiz](quiz.md) and [audit](audit.md) are historical, not approval of the rejected interface. [readiness.md](readiness.md) separates revision-2 technical evidence from this revision's policy/workflow audits. No application feature is implemented, and no implementation thermo gate has run.

## Goal and authority

Immediate smaller-font middle-status hints for **all existing modifier-dependent mouse alternatives**, including wheel. No availability checks, dimming or held-modifier listener. Preserve existing actions, selection/undo, operational messages and polyphony.

- [spec.md](spec.md): product behavior, exact shared interfaces, source/scope/hover lifetime and status layout.
- [inventory.md](inventory.md): complete audited coverage, handler/Qt authorities and executed planning probes.
- This file: dispatch order, closed ownership, shared validation, milestones and final acceptance. Briefs contain bounded deltas, not competing specifications.

### Supplemental description centralization

[centralization/plan.md](centralization/plan.md) defines the subsequent typed-profile refactor. It supersedes this plan's string-payload, element-local description/cache, pointer-text annotation, and four-new-production-files contracts only; the supplement explicitly authorizes two catalogue files. Existing hover/action/lifetime behavior remains authoritative. Execute the supplement only after the current hover implementation and fixes are settled and verified, never concurrently with a competing hint-interface migration. This link does not change the historical implementation-status statement above or authorize execution.

## Repair decisions

| First-audit defect | Settled correction |
| --- | --- |
| One band identity shared by plot/gutter | Physical TimelineInputItem is source; two explicit input-host presentation methods; all three concrete hosts migrate atomically |
| Band-specific cancellation/clear growth | Physical adapter owns leave/grab/hide/detach; FocusLost alone does not clear |
| One empty popup publication gets overwritten | Actual QuickPopupSession ownership gates QML; view mutes every borrowed C++ input host; native/application scope rejects in the service |
| Popup/native close lacks usable hover notification | Retained membership resyncs current state; one guarded queued idle move lets Qt restore lost membership to the actual leaf, without history or a second hit tester |
| Nested row/editor and rename competition | One logical publisher per group, child hover only selects profile; actual leaf membership excludes lower C++ sources |
| EventList QML hover is unreachable | Restack the already pointer-declining key-policy input below its page; prove original press/wheel/reorder/focus results |
| Scrollbar track/drawer card omissions | Named chrome owner covers all shared scrollbar instances, five drawer inputs and inline value-prompt group |
| Unrequested tooltip inspection/handoff | Removed; ordinary elision and full accessible description remain |
| Overloaded two-file common module | Core h/cpp plus one cohesive private native/status cpp; one reusable QML group policy, not fragments per control |
| Native implicit grabs and modal scope | Track actual pressed source; consume Qt WindowBlocked/Unblocked and native popup authority, rather than cloning modality rules |

Main reconciled the two scoped specialist designs against executed counterexamples. Their intermediate proposals are not alternate contracts: the spec deliberately rejects static popup-owned flags, cached unmute restoration, nonvisual popup/band sources, and using non-claiming refreshMouseHint for reacquisition.

## Global Constraints

1. Implement the complete spec/inventory, including no-hint targets and inherited native wheel/text behavior. Target/tool/configured-family identity is allowed; action eligibility is not.
2. Keep existing input/action owners, Qt ownership, shortcut/popup arbitration, global Space priority and press-time versus live modifiers. No new input grabs, key dispatcher, click/key replay or active-pointer-move refresh. The only synthetic-input exception is the spec's coalesced, queued-and-revalidated **idle MouseMove** through the existing Quick window on scope recovery. Physical hosts may recompute existing idle hover only under their membership guards.
3. Use native modifier formatting, translations, typography/theme/layout primitives and cached profiles. Do not re-run note/point searches, format per pointer pixel or create document-driven hint state.
4. Source identity differs from text: same text still transfers ownership; unhover source-check clears; a no-hint entry claims empty; a suppressed source cannot claim even empty. Never recreate application services during teardown.
5. Write sets are closed. Changes to public or private cross-file contracts return to Main before dependent dispatch. Only four new production files are authorized: mousehints.h, mousehints.cpp, widgethints.cpp and HoverHint.qml. Existing checks retain ownership under src/checks.
6. Follow sdd-execution-loop for SDD tasks. In shared-tree waves, writers perform their required read-only local inspection; the controller runs shared builds/tests and formatter/linter commands after writers settle. Tasks 4+15 and 5+17 are explicit atomic integration waves: do not validate or accept a half-cutover. Source-only producer compilation is not visible-feature acceptance.
7. Use deno task and the verify/offscreen/native-capture skills. No competing validation processes or repeated desktop stress tests. Apply the repository's single-baseline rule to failures; resolve them before handoff.
8. Apply [Realistic scope and checks](#realistic-scope-and-checks) to production code, permanent tests and review findings. Complete feature coverage is not a Cartesian test matrix. Actual native application exercise and screenshots remain mandatory.
9. Planning authorizes no worktree/branch/commit/merge/push. Execution location and any Git-checkpoint permission belong to the later implementation request. Authorized commits must be pushed. Checkpoint boundaries below are not implied permission.
10. The controller MUST dispatch `thermo-nuclear-reviewer` at every [Mandatory thermo review gate](#mandatory-thermo-review-gates), without waiting for the user to ask. Per-task review and passing checks do not replace these cross-task gates. Reviewers receive the plan's goals, non-goals, realism rule and prior rulings; findings are adjudicated within that scope.

## Realistic scope and checks

The feature is discoverability for existing mouse actions, not a new input framework. Production code must support ordinary use and the actual ownership/lifetime obligations it introduces. Keep inexpensive source/lifetime/idle guards; do not add states, generalized recovery, fallback modes or wider types merely to accommodate contrived tests.

A new permanent behavioral check must identify **the existing user workflow or supported fixture, the observable failure, and a plausible implementation mistake**. Drive normal application controls and Qt input; let Qt deliver its real enter/leave/destruction ordering. Do not manufacture late callbacks, mutate hidden state behind a popup, or invent unrelated windows to make a case reachable. A rare case can qualify if the workflow is credible and its consequence matters; “technically possible” alone does not qualify. Structural review can also flag demonstrable duplication, coupling or needless state without inventing a behavioral failure.

Reuse existing input/edit/undo checks. Add a focused regression only where an uncertain behavior lacks coverage; the inventory/native table is a coverage checklist, not a demand for a new test per control, modifier, toolkit or lifetime permutation. Isolated Qt primitive probes remain throwaway evidence, not automatic permanent-test requirements. If a supposed requirement has no realistic route, the controller removes it from the brief or keeps it as a one-off probe; do not invent product behavior to justify it.

| Questionable draft requirement | Required realistic replacement |
| --- | --- |
| Manually delayed plot clear or staged old-owner destruction | Move through actual plot/gutter and same-profile controls; switch/close real tabs and popups. Assert the visible hint, not a hand-arranged callback schedule. |
| Force a gesture between queued recovery and dispatch | Preserve the simple dispatch-time guards and ordinary drag/release checks. No mandatory permanent race test without an evidenced real-input sequence; the isolated guard probe already supplies mechanism evidence. |
| Mutate the background tool while a popup owns input | Use the existing PencilToggle command with no popup. Separately move the pointer between real underlying targets while a popup is open, then dismiss it without further motion. |
| Create an unrelated second window to test modality | Exercise Porydaw's existing owned/floating surfaces and actual WAV-export progress dialog; do not create unsupported window arrangements. |

These replacements narrow test machinery, not the requested hint coverage or existing action semantics.

## Mandatory thermo review gates

These are controller-owned execution gates, not optional suggestions or additional implementation tasks. Track them in the execution todo/results from the start. Dispatch the **`thermo-nuclear-reviewer`** agent in read-only mode; explicitly authorize **`skill://thermo-nuclear-code-quality-review` as the intended thermo method for this dispatch**. The agent may still reference the unavailable legacy name `thermo-nuclear-code-review`; resolve that lookup by naming/authorizing the available method, not by silently substituting a generic review. The reviewer must not edit, commit, run builds/tests/formatters/linters, or start a broader audit.

| Gate | Settled work to review | Must pass before |
| --- | --- | --- |
| T1 — common ownership | Tasks 1, 2 and atomic 4+15 at Milestone A: common module, native adapter/status and physical host policy | Task 16 and the popup/view integration wave |
| T2 — integrated input scope | Tasks 16 and atomic 5+17, against the accepted common contracts: QML group policy, popup authority and window recovery | Domain/chrome fan-out: Tasks 6–13, 18 and 20 |
| T3 — surface implementation | Completed Tasks 3, 6–13, 18 and 20 at Milestone B, including the large automation and nested-QML tasks | Regression Tasks 14 and 19 |
| T4 — final cumulative review | All plan changes, regression checks and final cleanup at Milestone C, including accepted work not yet committed | Final handoff or any completion claim |

Task 3 may overlap T1 because its writes are independent. Otherwise do not cross a listed hold point on the assumption that review will pass. Each gate follows the covering controller checks and per-task review; it does not cause a redundant build solely to prepare a review.

An aborted/missing-skill/tool-failed/incomplete reviewer result is **not a passed gate**. The controller resolves the prerequisite and resumes the same reviewer with its existing packet, or records why a replacement thermo reviewer is necessary. Keep the hold point closed; neither a failed invocation nor an implementer's self-review supplies the verdict.

If a task changes an agreed shared interface/ownership rule, introduces an unplanned shared mechanism, or returns a concrete structural concern, require a thermo gate after that task's settled atomic unit and before dependent dispatch. A scheduled gate covering the same work can satisfy this trigger. Raw line counts, timers and arbitrary task counts do not create extra gates.

### Review scope and adjudication

- **Dispatch packet:** the goal/non-goals and Global Constraints; this section and the realism rule; spec and affected briefs; immutable task-scoped diffs/evidence plus accepted interface context and prior rulings. Include untracked/new files and accepted uncommitted work, exclude unrelated user work. T4 uses the execution loop's cumulative review package from the agreed implementation base. Adjacent source may be read to understand a dependency; it is not permission for a repository-wide refactor.
- **Review question:** does this implement the agreed discoverability feature with less duplication, state, coupling and indirection, while preserving real input behavior? Challenge unjustified complexity even if the plan prescribed it. Do not reinterpret completeness as support for hypothetical workflows, tooltip/history features, a new input dispatcher or a generalized hint framework.
- **Finding evidence:** cite affected code/contract and either a credible user workflow with observable harm, or concrete in-scope structural cost with a smaller behavior-preserving remedy. Label each finding **in-scope blocking**, **in-scope minor**, or **out-of-scope proposal**. File size alone, theoretical reachability and unrelated pre-existing debt are not blockers.
- **Controller ruling:** decide each finding as fix, no change with evidence, or out of scope; record the reason in existing task/review results and carry it into later dispatches. Do not ask the user to arbitrate routine comments. Out-of-scope proposals do not become implementation tasks or hold the gate open. Reviewers may expose a genuine flaw in the plan; the controller must resolve it, not dismiss it merely because the implementation followed the brief.
- **Fix discipline:** accepted blockers go to the owning implementer within a reconciled write set, with covering verification and a scoped re-review by the same reviewer under sdd-execution-loop. If a necessary fix changes a shared contract, update the spec/brief and revalidate affected consumers before resuming. Actual product-scope changes require user approval. Do not accumulate speculative fixes, silently discard findings, or spawn fresh broad audits until one approves.
- **Exit:** no unresolved confirmed in-scope blocker; all findings have a disposition and the fixed package has covering evidence. Record the verdict before releasing the hold point. These thermo gates supplement per-task spec review; T4 supplies the loop's final cumulative quality review, rather than adding a duplicate final audit.

## Tasks

Task numbers remain stable from the first draft; execute by dependencies, not numeric order. Main is integration owner. Every SDD brief has at most three files, five steps and one acceptance predicate. Direct items are mechanical annotations/interface migration with complete inline contracts.

| Task | Change | Route / agent / reason | Prerequisites |
| --- | --- | --- | --- |
| 1 | [Application source/scope primitives](task-1-brief.md) | SDD — qt-cpp-reviewer; QObject lifetime and shared contract | — |
| 2 | [Native families and status presentation](task-2-brief.md) | SDD — qt-cpp-reviewer; native routing/layout | 1 |
| 3 | Custom native control annotations | Direct — inline; two fixed reversible call sites | 2 |
| 4 | [Physical host policy](task-4-brief.md) | SDD — qt-cpp-reviewer; hover/grab/lifetime | 1; atomic with 15 |
| 5 | [Authoritative popup scope](task-5-brief.md) | SDD — qt-cpp-reviewer; popup ownership | 4+15, 16; atomic with 17 |
| 6 | [Roll targets and gutter](task-6-brief.md) | SDD — qt-cpp-reviewer; existing hit/gesture precedence | 4+15, 17 |
| 7 | [Ruler background/handles](task-7-brief.md) | SDD — qt-cpp-reviewer; sweep precedence | 4+15, 17 |
| 8 | [Header scope and rename](task-8-brief.md) | SDD — qt-cpp-reviewer; model/Quick leaf ownership | 4+15, 16, 17 |
| 9 | [Automation tools and nodes](task-9-brief.md) | SDD — qt-cpp-reviewer; target/tool refresh | 4+15, 17 |
| 10 | [Velocity plot/gutter](task-10-brief.md) | SDD — qt-cpp-reviewer; press-time distinctions | 4+15, 17 |
| 11 | [Voice markers](task-11-brief.md) | SDD — qt-cpp-reviewer; hover/gesture lifetime | 4+15, 17 |
| 12 | [Quick numeric/tabs/event groups](task-12-brief.md) | SDD — sdd-implementer; nested target policy | 5+17, 16, 18 |
| 13 | [Pitch/modulation graph targets](task-13-brief.md) | SDD — qt-cpp-reviewer; passive graph input | 5+17 |
| 14 | [Composed source/scope/layout regressions](task-14-brief.md) | SDD — qt-cpp-reviewer; uncertain integration transitions | all production tasks |
| 15 | Input-host interface and recorder migration | Direct — inline; mechanical pure-virtual cutover | 1; atomic with 4 |
| 16 | [Reusable QML group policy](task-16-brief.md) | SDD — sdd-implementer; common scope/grab protocol | 2 |
| 17 | [Existing view/context integration](task-17-brief.md) | SDD — qt-cpp-reviewer; construction, borrowed items and idle recovery | 4+15, 16; atomic with 5 |
| 18 | [Reachable chrome/event hover](task-18-brief.md) | SDD — sdd-implementer; actual leaf delivery | 5+17, 16 |
| 19 | [Automation target/tool regression](task-19-brief.md) | SDD — qt-cpp-reviewer; stationary recovery | 9, 5+17; after production wave |
| 20 | Voice-picker search annotation | Direct — inline; reuse one existing hover handler | 5+17, 16 |

### Task 3 — Direct contract

**Write:** `src/ui/dragspinbox.cpp`, `src/ui/transportbar.cpp`.

**Change:** Annotate DragSpinBox's actual overridden editor and OutputVolumeDial using setPointerDescription for their Shift fine drag. Format from the service; preserve inherited wheel/arrow behavior. Do not advertise ordinary Shift-click selection on DragSpinBox's click-select-all editor or add a subclass deny-list.

**Acceptance:** Existing fine drag and inherited wheel produce their original results while the middle bar shows the profile. Controller: `deno task verify --filter transportcheck --verbose`, plus native custom-controls row. No headers/gesture algorithms.

### Task 15 — Direct atomic migration contract

**Write:** `src/ui/songview/quick/timelineinput.h`, `src/checks/automation/raster/rasterfixture.cpp`, `src/checks/automation/presentation/tst_automationpresentation.cpp`.

**Change:** Add the two exact pure virtuals setMouseHint/refreshMouseHint from the spec. Implement them in RasterAutomationInputHost and CursorDprHost as honest single-source recorders (text plus owned state; refresh changes only an owned record), not empty methods. Do not alter action interfaces/input structs or add a fake production implementation.

**Acceptance:** All three concrete hosts compile under the new contract after **Task 4 and 15 both settle**. Controller runs Task 4's named suites once. The two tasks have disjoint files and one atomic verification boundary; neither may be validated/accepted in isolation.

### Task 20 — Direct annotation contract

**Write:** `src/ui/songview/quick/VoicePickerPrompt.qml`.

**Change:** Reuse the search TextInput's existing I-beam HoverHandler as one HoverHint source, with native Shift-click text-selection description and actual session scope. Preserve cursor shape, filter/accept binding, navigation and prompt keys. Modern TextInput already supports this action; add no input behavior or availability check.

**Acceptance:** Hovering voice search immediately shows text-selection help, Shift-click still extends selection, and popup close/scope recovery works. Controller: `deno task verify --filter host-integration --filter selectionkey --verbose`, plus native Quick-controls row. No separate brief or new control type.

## Dependency waves and checkpoints

1. Accept Task 1's core producer gate. Before CMake reuse by 2, retain its accepted/reviewed change at the execution loop's authorized checkpoint boundary.
2. Tasks **2**, **4+15** are disjoint and can execute concurrently. After 2, Task 3 can overlap host work. **Milestone A:** native status/families work in the actual MainWindow; all concrete hosts compile and retain original input behavior. Run **T1** before Task 16; do not stop at a compiled unconnected service.
3. Before Task 16's CMake reuse, checkpoint the accepted Task 2 change under the same permission rule. Task 16 produces the group policy. Tasks **5+17** execute together against the fixed isOpen/owns/context contract; all popup/context changes settle before shared tests and **T2**.
4. After **T2**, Tasks **6–11, 13, 18, 20** have disjoint writes and may run concurrently. Task 12 starts after 18 makes the event page hover-reachable and may overlap remaining domain tasks. **Milestone B:** every inventory category and native coverage row works. Run **T3** after these writers settle.
5. After **T3**, Tasks **14 and 19** are disjoint regression slices. **Milestone C:** controller runs the complete final verification/native walkthrough, performs final documentation/temporary-artifact cleanup, and runs cumulative **T4** before handoff.

Only CMakeLists.txt is deliberately re-edited: 1 → 2 → 16. All other implementation paths have one task owner. No per-task commits are implied. Additional discovered reuse requires controller reconciliation, not simultaneous edits.

## Coverage ownership

| Inventory category | Task | Existing checks / native evidence |
| --- | --- | --- |
| Roll body/edge/right-button/plot/gutter wheel | 6 | rollcheck, timelinepancheck, selectionkey-gesture; roll row |
| Ruler background/consumed handles/wheel | 7 | rollcheck, timelinepancheck; ruler row |
| Header body/voice/mute/solo/add/rename | 8 | trackheader, selectionkey; header row |
| Automation node/phantom/sweep/pencil/insertion/wheel | 9, 19 | automation, editor-drawer; automation row |
| Velocity note/background/right-button/gutter/wheel | 10 | velocity, editor-drawer; velocity row |
| Voice marker/background/gutter | 11 | editor-drawer; voice-marker row |
| Numeric DragInput / parameter ghost tabs | 12 | host-seams, automation, selectionkey; Quick-controls row |
| Event row/cell/header/inline editor / reachable hover | 12, 18 | eventviews, selectionkey; Quick-controls row |
| Voice-picker search / drawer inline value text | 20, 18 | host-integration, editor-drawer; Quick-controls row |
| Pitch/modulation background/interior/pinned/margins | 13 | rollcheck, host-integration; graph row |
| QWidget text/spin/selection/slider/scroll-area families | 1–2 | mainwindow-routing; native-families row |
| DragSpinBox / OutputVolumeDial | 3 | transportcheck; custom-controls row |
| Popup shields/cards/menu ownership | 5, 16–17 | host-integration, selectionkey, 14; popup row |
| All five scrollbars / five drawer inputs / value card | 4, 18 | scrollbar, editor-drawer, 14; chrome row |
| Physical source/grab/tab/app/native modal lifetime | 1, 2, 4, 5, 17, 14 | mainwindow-routing, host suites; lifecycle row |
| Caption/elision/accessibility/messages/meter layout | 2, 14 | mainwindow-routing-state; layout row |

## Native acceptance

Controller builds with `deno task build:app`, launches the actual app with existing project/check fixtures, and reads the native capture skill before screenshots. Capture each target **with no modifier held**, then exercise representative alternatives and confirm original results. Do not drop operations to make long profiles fit. Offscreen planning probes are not native Porydaw screenshot proof.

| Scenario | Required observation |
| --- | --- |
| Roll | First entry suffices; body/edge/blank/gutter differ; velocity, resize, right-drag time/marquee and wheel results unchanged |
| Ruler | Background offers multi-track sweep; consumed handles do not; Shift wheel remains horizontal |
| Header | Body/voice show scope; mute/solo/add clear; rename replaces body help, including stationary show/hide |
| Automation | Node/phantom/sweep/pencil and insertion/wheel differ; stationary tool change and popup recovery use current state; live Alt/Control and captured Shift remain functional |
| Velocity | Note/background/gutter reflect actual selection/detent/press-time rules; ramp/right marquee unchanged |
| Voice marker | Marker adds fine-time drag; background has plot wheel; gutter clears |
| Quick controls | Numeric fine drag/wheel, ghost toggle without eligibility, event Control+Shift range, text editors/search/value field; EventList restack preserves click/wheel/reorder/focus and restores real hover |
| Graph | Both graph modes distinguish background/interior/empty pinned endpoints/margins; Shift or Alt is not a combined chord |
| Native families | Real text, spin, SingleSelection, NoSelection, scrollbar and forwarding viewports in owned dialogs; no invented Shift multi-selection |
| Custom controls | No generic Shift-click selection on custom click-select-all editors; fine drag and inherited wheel remain correct |
| Chrome | Full scrollbar tracks/thumbs, drawer bar/detent/handles and value card suppress covered bands; field versus card differs without parent overwrite |
| Popup | Open clears before movement; all later background publications rejected; real owned children can publish; stationary close restores the current target with retained or lost membership, without a lower source stealing a higher leaf |
| Lifecycle | Move between actual same-profile controls; switch/close tabs and popups; keyboard focus changes without pointer motion; drag/release inside and outside; switch applications and use existing owned/floating windows. Exercise native modal suppression/recovery through WAV export's window-modal progress dialog, without fabricated windows or callback races. |
| Layout | Ordinary/minimum usable width, longest profiles, meter on/off, operational timeout/message, font/enlarged-font: no hint-driven height/min-width/meter shift; smaller caption, clean elision, full accessible text |

## Final acceptance

Controller runs once after settled edits:

```sh
deno task format --check
deno task verify --verbose
deno task build:app
```

Complete the native table and inspect actual-window screenshots. Every inventory category is required, but use the realism rule rather than adding exhaustive permanent cases. Resolve failures/uncovered paths before handoff. T1–T3 must already have passed; after the cleanup below, T4 must have a recorded accepted verdict with every finding dispositioned. Passing tests alone is not completion.

Only after native smoke proves behavior, update the existing `docsrc/getting-started/quick-start.md` Look around section with a short discovery note and remove execution-only scratch artifacts. No new runtime hint catalog, help system or unnecessary screenshot churn. This cleanup is not a preallocated implementation task.

## Planning verification

The inventory records source evidence and executed isolated Qt probes for native modifiers/families, stable status layout, popup/nested hover, implicit native routing, embedded-window modality, the existing const-QObject ownership signature through QML, and the stationary native-reentry failure plus guarded recovery. The first audit remains preserved because passing document checks did not prove its interface correct. Revision 2 gates and their limits are recorded separately in [readiness.md](readiness.md).
