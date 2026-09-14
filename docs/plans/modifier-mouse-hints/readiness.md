# Plan readiness and historical evidence

Status: **revision 3 READY for implementation dispatch; feature not implemented.** The [plan](plan.md) and [spec](spec.md) distinguish realistic acceptance from framework-only probes and require bounded thermo reviews during execution. The [first audit](audit.md) and [first quiz](quiz.md) remain historical evidence; their rejected design is not silently reclassified as passing.

## Revision 3 scope and review gates

The user's correction is binding: code and checks must serve realistic use, and thermo reviews must run automatically without turning speculative findings into new scope.

- **Realism:** permanent checks need an existing workflow/supported fixture, observable failure and plausible mistake. Ordinary Qt delivery replaces staged callbacks/destruction; real tab/popup lifecycle replaces unsupported window arrangements. Production ownership/lifetime/idle guards remain.
- **Concrete workflows:** stationary PencilToggle with no popup; separately move between real targets while a popup owns input, then dismiss without further motion. Native modal coverage uses WAV export's existing progress dialog. No direct background tool mutation or mandatory synthetic callback race.
- **Automatic review cadence:** T1 common ownership, T2 integrated popup/view scope, T3 surface implementation, T4 cumulative final review. Hold points, read-only `thermo-nuclear-reviewer` dispatch, an additional shared-contract/structural-concern trigger and explicit completion requirements live in plan.md.
- **Scope control:** reviewers can challenge genuine bugs and needless complexity, including a flawed plan decision. They must substantiate findings, distinguish blocking/minor/out-of-scope, and cannot add product requirements. The controller records dispositions, owns bounded fixes and re-review, and carries rulings forward.

Revision-3 validation passed:

| Review / check | Result |
| --- | --- |
| HintWorkflowAudit — gui-behavior-auditor | READY; realistic tool/popup/native workflows preserve required hover, lifecycle, layout and original action coverage. No required correction. |
| HintThermoGateAudit — thermo-nuclear-reviewer | READY; mandatory hold points, complete diff coverage, scope adjudication and bounded fix discipline have no blocking policy findings. |
| Document integrity | All links/anchors, bounded briefs, named filters and write ownership remain valid. |
| Gate-aware schedule model | Four gate rows present; dependency graph remains acyclic; every named hold point rejects dispatch without its accepted gate. T4 additionally requires the specified final proof/cleanup evidence. |

The thermo dry run initially stopped because the agent referenced the unavailable `thermo-nuclear-code-review` skill. Explicit controller authorization of `thermo-nuclear-code-quality-review` resolved it; the same reviewer resumed and completed the audit. Future dispatches now name that authorization, and aborted/missing-skill/incomplete results explicitly keep the gate closed. No agent configuration was edited.

The policy audit classified duplicated common hint policy and an ordinary stale popup hint as in-scope blockers; a generic priority registry for hypothetical overlaps and splitting a cohesive file solely for a line target were not accepted as required work. These were supplied policy examples, not discovered production defects.

Neither planning audit counts as an implementation T1–T4 pass. The revision-2 verdict below established technical feasibility, not that every former adversarial test requirement earned a permanent test. Its raw probes/quiz remain mechanism evidence.

## Revision 2 closed-contract quiz

The initial answer key was fixed before dispatch and withheld from scouts. After the native-reentry probe falsified an assumption, the recovery answers were revised and frozen before a focused retest. Answers are judged for mechanism and preserved behavior, not copied wording. This was not a clean first-pass 20/20 result.

1. What appears on hover, when, and may selection/value/command eligibility suppress it?

2. Plot and gutter share a band. Gutter publishes after plot; a late plot leave arrives. Which source survives and why?

3. A and B publish identical text, then A dies. What changes on B publication and what may A destruction clear?

4. Distinguish setMouseHint, refreshMouseHint and resyncMouseHint. After popup close the old owner no longer owns: which path can reacquire?

5. A non-hovering popup overlay leaves underlying hovered true. A later frame/tool update tries both nonempty and empty publication. How are both rejected?

6. Popup closes with no hoveredChanged; cursor/tool changed underneath. How does each toolkit recover? Distinguish retained membership from native Leave with no stationary reentry; what must not be restored?

7. Compare FocusLost, release/ungrab inside, release outside and source hide during a grab.

8. An event cell is editing. Parent and text child could both publish. What is the one-publisher rule, including editor margins?

9. Rename owns a higher hover leaf. Can a lower C++ header resync use geometry alone to take ownership after another scope closes?

10. Why does EventList need a stacking correction even though its input interaction ignores pointer events? What remains unchanged?

11. A window-modal dialog blocks embedded Quick but not an unrelated window. Which authority is consumed and how does Quick recover?

12. QWidget::mouseGrabber is null after a press and move outside. May native hint retention assume no grab?

13. How does native observation avoid global mouse tracking and propagated-parent overwrite?

14. May live Alt snapping stop changing during a drag because its hint profile was retained? Is the hint label an inspection/tooltip target?

15. What differs between roll note body/edge and plot/gutter modifier-wheel descriptions?

16. Compare Control+Shift on track headers versus event rows, and Shift+Alt on graph background versus pinned endpoints.

17. What does shared DragInput advertise and what tempting generic text/wheel claims are excluded?

18. Who covers scrollbar tracks, drawer card versus field, and voice-picker search? Is a popupOwned flag enough?

19. Name the atomic host cutover files, the deliberate reused file/order, and whether the plan authorizes Git checkpoints.

20. What do planning probes/readiness prove, and what remains mandatory before claiming the feature implemented?

### Reader results

Two usable independent scout responses covered the 20-question contract. A third output was unusable and rejected, not counted as a pass.

| Reader | Initial defects / omissions | Disposition |
| --- | --- | --- |
| HintQuizV2Beta | Invented ownership machinery; mixed host update methods; conflated Quick/native scope; incomplete final verification obligations | Corrected by targeted questions and the explicit three-gate matrix. Final recovery retest correctly explained leaf restoration, dispatch-time guards and surviving-popup scope. Its final native widget-at API answer was still wrong and rejected; the authoritative contract explicitly says QApplication::widgetAt. |
| HintQuizV2Gamma | Quick/native scope conflation; wrong widget-at API owner; omitted voice search and exact atomic write files | Scope trace and coverage/write-set answers corrected. Final focused retest correctly answered recovery, all dispatch-time guards, surviving-popup scope and QApplication::widgetAt. |
| HintQuizV2Alpha | Placeholder/corrupted output | Excluded entirely; no evidence or score attributed to it. |

The scope question exposed a genuine documentation ambiguity: a custom Quick popup is not QApplication's activePopupWidget. The spec now assigns Quick rejection to HoverHint/host mute, native rejection to allowsSource, and inactive rejection to the service. A direct background publication that bypasses the Quick gate can overwrite the overlay claim; there is no hidden priority rule.

The final focused retest asked: how lost membership recovers without lower-source theft; why to queue/revalidate a callback rather than post a prevalidated event; whether native recovery may run while a Quick popup survives; and the fully qualified native widget-at API. Both scouts recovered the three behavioral mechanisms. The API-name error above was not accepted or used to change the correct contract.

## Revision 2 independent feasibility gate

**HintFeasibilityV2, qt-cpp-reviewer: READY for implementation dispatch.** This followed an initial NOT READY verdict and a bounded re-review of the corrections, not an unconditional endorsement of the first revision.

| Finding | Closed correction |
| --- | --- |
| B1 — still-hovered-only recovery cannot restore native-modal Leave | Executed failure and corrected primitive; [Task 17](task-17-brief.md) owns the private coalesced recovery helper and its three existing view files. Queue a lifetime-bound callback, re-read guards/current cursor, then send one idle NoButton move through Qt's actual leaf delivery. No history, custom scene hit tester, active-gesture replay or prevalidated event. |
| C1 — notification declarations could be mistaken for ordinary methods | hintChanged and scopeRefresh are explicitly Qt signals in the spec and producer brief. |
| C2 — isolated component acceptance lacked an execution location | Task 16 names a controller-owned throwaway QML consumer outside the repository, removed after proof. |

The reviewer accepted the dispatch-time guard refinement, existing m_view/m_detachStarted borrows, native-ancestor hit check excluding transients, and recovery of owned children while a Quick popup survives. The revised Task 17 remains within three files/five steps; its added files do not overlap another writer.

Remaining implementation proof is explicitly **not waived**: composed source/gesture/scope regressions, stationary rename show/hide delivery, effective-visibility handling, status layout/elision/accessibility, all named suites and the complete native walkthrough with actual-window screenshots. Planning approval is not application acceptance.

## Integrity and evidence

Structural validation passed: 23 documents, 20 implementation tasks (17 bounded SDD briefs plus Direct 3/15/20) and four mandatory thermo gates; exact brief headings, at most three files/five steps per SDD brief, all local links/anchors valid, and 49 distinct planned write paths. Four new production files are authorized. The only deliberate reused path is CMakeLists.txt, ordered 1 → 2 → 16. The gate-aware dependency graph is acyclic; concurrent implementation waves and both atomic cutovers have disjoint writes. All 19 named filter strings match the current 91-entry check catalog.

[inventory.md](inventory.md) records primary Qt/source evidence and executed planning probes. The final reentry experiment observed:

```text
before hovered=1 enters=1
blocked hovered=0 enters=1
closed hovered=0 enters=1
recovered hovered=1 enters=2 deliveries=1
upperLeaf lowerHovered=0 upperHovered=1 deliveries=2
queuedGuard deliveries=2 domainActive=1
```

The corrected probe compiled and exited 0 without warnings. It proves the isolated Qt mechanism, not the composed Porydaw implementation. Earlier failure and probe-setup correction are recorded, not hidden. Controller-only document validation and standalone Qt experiments ran; no production source was changed, no project build/test suite ran, and no branch/worktree/commit was created. Execution-only probe artifacts are removed before handoff.
