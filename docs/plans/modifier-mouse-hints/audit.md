# Modifier-mouse hints: first-revision audit

Historical record of the rejected first revision. Scores, counterexamples and the verdict below are preserved; they are not the current contract. See [spec.md](spec.md), [plan.md](plan.md) and the new [readiness gates](readiness.md) for revision 2.

## First-revision verdict

**Not ready for implementation dispatch.** The product behavior is mostly clear, but the proposed source identity and hover/lifecycle interface are not sufficient to guarantee it. This is a completed audit with concrete counterexamples, not an application implementation or a claim that the plan has been repaired.

## Scout comprehension test

Two independent scout agents answered the same [18-question quiz](quiz.md), using only the frozen plan/spec/inventory/briefs. Main wrote the expected answers before dispatch; the scouts could not inspect application code, one another's reports or the grading key. Questions include adversarial event sequences, not just recall of method names.

- **Alpha: 17 correct, 1 partial.** Its answer to Q7 first preserves live modifier semantics, then contradicts itself by saying a mid-drag modifier cannot change the action. The plan's “do not change semantics” wording should explicitly distinguish unchanged implementation from still-live modifier effects.
- **Beta: 18 correct conclusions.** Q4 has imprecise wording about retaining ownership, but its sequence results and Q3 demonstrate the intended source-checked clear behavior.
- Both independently identified the nested-target precedence gap, inspection/leave contradiction, shared-band source-identity failure and uncertain stationary restoration. Finding a genuine missing mechanism counts as correct, not as a scout misunderstanding.

### Grading key and results

| Question | Expected conclusion / accepted gap identification | Alpha | Beta |
| --- | --- | --- | --- |
| 1 | Show Control ghost-toggle immediately; distinguish real target/tool, not eligibility/held keys. | Correct | Correct |
| 2 | Permanent middle caption; normal reservation stretch1 retained hidden, hint stretch2, meter0; showMessage preserved. | Correct | Correct |
| 3 | Starting empty: A/same emits; B/same owner changes no emit; clearA and destroyA no effect; clearB clears and emits. Source observers must move even when text equal. | Correct | Correct |
| 4 | B publishes empty replacing owner/text; A clear is a no-op. Unhover must clear, not empty-publish. | Correct | Correct |
| 5 | Band this; each actual QML item; app-scoped QApplication child via instance/context property; no host interface or QML singleton changes. | Correct | Correct |
| 6 | First entry sends HoverEnter not HoverMove; only forward when !gestureActive(); preserve accepted/blocking/input behavior. | Correct | Correct |
| 7 | Keep originating description during actual grab; clear/refresh on release outside/inside. No held-modifier watcher; action semantics continue existing live/press/release rules. | Partial | Correct |
| 8 | Body velocity+selectionclick; edge resize/add selection no velocity; gutter wheel only; Ctrl pitchzoom then Shift horizontal; reuse local hit authority. | Correct | Correct |
| 9 | Node Alt time, phantom no time; sweep Alt fine/Shift ramp/Ctrlneutral; pencil Ctrl freehand Shift hold no Alt sampling; placement/rightband distinct; stationary tool refresh. | Correct | Correct |
| 10 | Roll rightmarquee Control release; velocity Control press. Plot permits registered detent chord plusShift; gutter exact chord. | Correct | Correct |
| 11 | Event CtrlShift additive range; header Ctrl wins toggle; inline text Shiftclick; mute/solo/add no scopehint. | Correct | Correct |
| 12 | Single Ctrl deselect no Shift ranges; NoSelection no selection; line Shift selection; DragSpin Shift fine drag no ordinaryShiftclick; inherited wheel preserved. | Correct | Correct |
| 13 | Background Shift OR Alt line; interior Alt finetime; endpoints not timemovable; margins nohint; not combined chord. | Correct | Correct |
| 14 | Open emptypublish session after cancel; child owns; close clears only matchingowner/children hide clear; normalhover recovery promised but concrete stationary re-entry mechanism requires code/Qt evidence. | Correct | Correct |
| 15 | Last publish wins so parent overwrites; plan requires avoiding overwrite but gives no executable depth/hover precedence mechanism. Flag gap rather than invent priority. | Correct | Correct |
| 16 | Ordinary sourceleave clears first; entering label retains only empty text. Stated retention is unimplemented/conflicting without an explicit inspection handoff/retention contract. | Correct | Correct |
| 17 | Same QObject identity makes stale plotclear erase gutter. Public source identity cannot distinguish them; protection only covers different source identities. | Correct | Correct |
| 18 | Task2 state and Task14 lifecycle see real label; Task14 automation-hover uses publiccurrentText with real unhostedEditorRig; native app scenarios/screenshots stillrequired, no extra harness. | Correct | Correct |

## Feasibility review

A separate Task agent audited the repository and primary Qt sources without seeing the quiz reports. Initial verdict: **READY WITH SPECIFIC CORRECTIONS**. It found three substantive gaps: nested Quick target precedence, uncovered/no-hint chrome ownership, and overly broad cancellation cleanup. It also confirmed real implementation seams, existing test fixtures/check filters, effective Quick visibility and the first-entry HoverEnter gap.

Main challenged two of the Task agent's positive conclusions with executed counterexamples: being a QObject is not enough when two physical surfaces share that identity, and Qt frame-synchronous hover does not imply hoveredChanged fires. After reading the evidence, the Task agent revised its verdict to **NOT READY as frozen** and accepted the physical-identity, nested precedence, inspection, stationary QML refresh and ongoing-popup-suppression defects.

The agent explicitly withdrew its claim that frame-sync hover alone guarantees restoration: C++ HoverMove publishers can refresh, but unchanged QML hover booleans do not trigger onHoveredChanged. Its chrome-ownership and focus/cancellation findings remain valid. A small method count is not evidence that the complete interface is sound.

## Load-bearing findings

### A. One band QObject is not one physical hover source

`TimelineInputItem::setInteraction` in `src/ui/songview/quick/timelineinputitem.cpp` attaches an interaction with a surface; `TimelinePointerInput` in `timelineinput.h` carries the emitting host. Plot and gutter may share the same band QObject. `pointerLeave()` does not carry the emitting host.

The written interface executes `publish(band, plot)`, `publish(band, gutter)`, old plot `clear(band)` as **empty text**. The stale-clear promise only holds across different QObject identities. More band-owned cleanup cannot fix the missing physical identity.

**Required design correction:** use the actual physical input item as source. The existing input-host presentation seam is a candidate: a host-owned hint setter would also keep lifecycle work out of each band. That changes the declared “TimelineInputHost/fakes unchanged” decision and must be reflected in the interface, complete caller migration and write sets before dispatch. Do not pretend adding another clear call solves it.

### B. Last publisher wins is not target precedence

`EventListPage.qml` has a nested editing target; `TrackHeaderBand.qml` overlays its rename TextInput above the band's input surface. `TrackHeaderModel::HitTarget` has no rename target, while pointerMove still resolves body/voice actions. Nonblocking Quick hover observations can coexist.

`publish(editor, text-help)` followed by `publish(parent, row-help)` displays row-help. The spec requires the editor to win without naming a mechanism. Publishing an empty parent description would also erase the child and is not suppression.

**Required design correction:** one logical publisher for each nested row/editor group, with the existing local hover state selecting its profile; explicitly suppress the underlying header publisher while the real rename target owns hover. Do not solve this with callback ordering, a global scene hit-test or a ranked hover stack. The isolated repair experiment below proves the local group pattern only.

### C. A one-time popup clear is not ongoing suppression or restoration

`QuickPopupLayer.qml::underlay` has no hoverEnabled setting; the form shield does. `QuickPopupSession::end` detaches content/layer and schedules deletion. Covered controls may remain hovered behind the underlay.

A covered editor can republish after the session's empty publication. Conversely, controls publishing only in onHoveredChanged can remain blank after popup close because their hover booleans never changed. Qt's frame-synchronous hover delivery does not remedy that callback mismatch.

**Required design correction:** use the existing QuickPopupSession as the input-scope authority, reject covered-background publication for the duration of that scope, and explicitly refresh actual still-hovered publishers when it changes. Name who connects those signals and where. This is pointer ownership, not action-availability filtering.

### D. Hint-label inspection conflicts with clearing on leave

The added tooltip-inspection behavior promises retained text when entering the hint label, but ordinary source leave first calls clear(source). The label then has no current text to retain. Traversing unrelated controls on the way makes that promise still less plausible.

**Required design correction:** remove this unrequested inspection handoff and retain accessible full text, or explicitly design a handoff/history policy. The simpler recommendation is to remove the extra feature; do not hide a delayed-clear timer or retained-source history inside install(). This product decision is not yet applied to the specification.

### E. No-hint chrome is not assigned complete ownership

`TimelineCanvas.qml` positions `TimelineScrollbar` above the scene bands and `DrawerChromeLayer` above them. These targets have no modifier alternatives, but passive hover does not inherently prevent a lower publisher from publishing. The original task write sets omit TimelineScrollbar.qml and DrawerChromeLayer.qml while the inventory promises coverage.

**Required design correction:** assign an explicit chrome-occlusion owner using existing control geometry/hover state and include the affected reusable QML files in a task. An empty publication that can immediately be overwritten by a covered band is insufficient. Do not broaden every band into a second geometry classifier.

### F. Cancellation does not necessarily end hover

`TimelineInputItem::focusOutEvent` routes FocusLost. `VoiceChangeArea::inputCancelled` explicitly distinguishes it because Quick focus transitions do not necessarily end pointer delivery. Normal release/ungrab also needs to distinguish a still-hovered target from an outside target.

**Required design correction:** derive clearing from actual source visibility/attachment, hover and grab state. Focus loss alone must not erase a valid hover hint; cancellation is not a synonym for leaving. Preserve existing domain cancellation behavior and define the presentation rule once rather than asking every band to invent it.

## Executed experiments

### Public-contract state model

A small executable model of the exact publish/clear rules produced:

| Sequence | Actual result |
| --- | --- |
| Shared band: plot publish, gutter publish, old plot clear | Empty — newer gutter lost |
| Child publish, parent publish | Parent text — child precedence lost |
| Source publish, source leave clear, hint-label entry retaining current | Empty — nothing to inspect |
| Editor publish, popup empty publish, covered editor republish | Editor text — popup leak |

This proves limitations of the stated interface, not the existence of implementation code.

### Real Qt Quick primitive probe

An isolated Qt6Quick/Qt6Qml/Qt6Test program used the offscreen platform and software scene graph. No Porydaw source was compiled/copied and no native window, application build or project test suite was run. Compile and both runs exited 0.

Original onHoveredChanged-only publisher, non-hovering popup underlay:

```
nested entry owner=child hint=text
popup open stationary owner=popup hint=
popup close stationary owner=popup hint=
move within child owner=popup hint=
move child to parent owner=popup hint=
```

Qt logged point updates at the stationary position, but no relevant hover-state transition. A revised probe with one group publisher, local child-hover profile selection, ongoing popup suppression and explicit popup-transition refresh produced:

```
nested entry owner=group hint=text
popup open stationary owner=popup hint=
popup close stationary owner=group hint=text
move within child owner=group hint=text
move child to parent owner=group hint=row
```

This is proof of that local repair pattern, not Porydaw integration, a complete popup-scope implementation or approval of a redesigned public interface.

## Still sound

- Immediate hints for existing mouse alternatives, including wheel, without action-availability logic.
- Qt native modifier labels and existing caption typography.
- A separate permanent QStatusBar region preserving showMessage and the meter; prior planning probes support layout feasibility.
- Source identity must change even when text does not; notifications can still deduplicate text changes.
- Real first-entry HoverEnter forwarding, guarded against mutating an active gesture.
- Existing MainWindow and automation fixtures rather than a new plumbing-only harness.

## API conclusion

The small method count hid too many ordering/lifetime obligations in callers. `publish(QObject*, text)` / `clear(QObject*)` are usable presentation primitives, but **not yet a sufficient caller contract** for the promised cross-toolkit behavior. Physical source identity, one publisher per nested target group, explicit input-scope suppression/refresh and centralized hover-versus-cancellation rules must be settled together. Adding more scattered clear calls or claiming Qt resolves all ordering would preserve the defects.

The next plan revision should settle those contracts, migrate the task write sets, then repeat the affected quiz scenarios and the Task-agent feasibility gate. No implementation should start from the pre-audit plan.

## Applied clarifications and handoff

The specification now explicitly distinguishes a retained description from live modifier effects, and distinguishes focus loss/cancellation from actual hover termination. The graph brief explicitly says pinned endpoints publish an empty description. These clarify intended behavior; they do not repair the structural interface defects above. Both plan.md and spec.md are marked not ready for dispatch rather than silently presenting the old contracts as approved.

## Verification

Validated 18 plan/audit documents, 38 local links and all 18 numbered quiz questions; no broken local links or anchors. Both isolated Qt experiment variants compiled/ran successfully, and the repair variant asserted the expected stationary restoration and child-to-parent transition. Temporary probe files were removed.

Qt source context: [hover delivery and frame-synchronous updates](https://raw.githubusercontent.com/qt/qtdeclarative/6.9/src/quick/util/qquickdeliveryagent.cpp) and [QWidget enter/leave dispatch](https://raw.githubusercontent.com/qt/qtbase/6.9/src/widgets/kernel/qapplication.cpp). The runtime counterexample limits what may be inferred from frame-synchronous delivery alone.
