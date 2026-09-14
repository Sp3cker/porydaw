# Centralization architecture — open-book audit

## Result and limits

The supplemental architecture was revised twice in response to independent readers. Revision 3 is the current book: [plan](plan.md), [specification](spec.md), and six task briefs. It is a written implementation contract, **not an implemented or runtime-verified refactor**. The plan's entry conditions and integration/runtime evidence remain mandatory.

Seven independent scout readers supplied 102 scenario answers: three readers × 18 questions, two fresh readers × 18 questions, then two further fresh readers × six focused scenarios. This is not a claim of 102 correct answers. The first two rounds found substantive misunderstandings; the last round resolved the blocking admission, lifetime, identity, and gesture misunderstandings, with the limited answer-completeness/proof caveats below.

No production code was changed for this audit. Documentation validation checks task boundaries, source-path coverage, and internal consistency; it cannot establish the proposed C++/QML interface's runtime behavior.

## Method

- Freeze an author key before each dispatch. Readers receive the current book and questions, never that key, prior responses, or the audit.
- Each concurrent reader answers independently and states natural expectations, evidence, uncertainty, and suggested changes. No build/test/formatting work is assigned.
- Compare actual answers with the frozen key; preserve wrong answers and old specifications instead of retroactively making them correct.
- Reconsider the architecture when the intuitive answer conflicts with it. Prefer a simpler contract or more honest interface name over another warning paragraph. Retain a necessary constraint only with an explicit reason.
- Material revisions go to new readers. A later focused retest is not a fresh pass over every original question.

The [original quiz](quiz.md) has 18 questions. The [focused retest](retest.md) targets revised boundaries. Evidence archives are deliberately **nonnormative** and should not be read before taking either quiz:

| Round | Independent readers | Preserved evidence |
|---|---|---|
| 1 | HintQuizMaintainer, HintQuizIntegrator, HintQuizNewReader | [Complete reports, frozen key, original book](quiz-responses-round-1.md) |
| 2 | HintRetestInterfaces, HintRetestMaintenance | [Complete submitted payloads, frozen key, revision 2 book](quiz-responses-round-2.md) |
| 3 | HintFinalGateReader, HintFinalModelReader | [Complete reports and frozen revision 3 key](quiz-responses-round-3.md) |

Round 2's two tool jobs failed output-schema string-length limits, not the architecture questions. Their original complete submitted answer payloads were recovered and reviewed; they were not coached into replacement answers. Round 3 removed those artificial length limits and both output schemas validated. Tool transport success is not an architectural grade.

## Changes driven by the answers

| Evidence | Intuitive answer / problem | Revision adopted |
|---|---|---|
| Round 1, Q2; all three readers | Identical current horizontal-scroll behavior should not acquire two public identities merely because different widgets expose it. | Merge proposed `RulerHandle` and `VoicePlot` into `HorizontalScroll`. Share complete action/modifier sets; split only when actual behavior diverges. Keep genuinely different `TrackScope` and `EventRows` separate. |
| Round 1, Q3–Q5; Integrator Q5 explicitly exempted Empty from suppression | A publication-sounding API encourages treating blank output as harmless presentation rather than an ownership claim. | Replace proposed `publish(source, Id)` with `claim(source, Id)`. Empty is a blank admitted claim, not clear and not an admission exemption. Source identity transfers even when text does not change. No old overload remains. |
| Round 2, Maintenance Q5 | The reader identified the host gate but still expected the central `allowsSource` call to catch a bypassed Quick-popup gate. The name implied more authority than its body had. | Rename the unchanged native/application predicate to `allowsNativeInput`. Keep Quick session/mute admission in existing hosts. Explicitly withhold a rejection guarantee for unsupported direct calls that bypass those hosts. Do not invent another Quick ownership registry. |
| Round 1, Maintainer Q12 | The reader treated graph classification as something to recompute while the active drag crosses targets. | Rename retained graph/QML state to `m_gestureProfile` / `_gestureProfile`, and bind it to gesture origin through existing terminal settlement. Delete rendered-text caches; add no corresponding state to `TimelineInputItem`. |
| Round 2, Interfaces Q13 | The answer conflated application cache lifetime with the current source's lifetime. | Separate them explicitly: descriptions survive tab closure; claims do not. A new tab needs a new admitted claim, never a cache-driven caption restoration. |
| Round 1, Maintainer Q10 | The answer treated enum registration as per-instance. | Tie registration to the existing function-local static `once_flag`, once per process. Distinguish per-engine context-property installation, which borrows the same application-owned service. No singleton-instance registration. |
| Round 2, Maintenance task-boundary suggestion | The production virtual declaration should be owned with its production implementation, not mixed into a broad caller batch. | Move `timelineinput.h` into task 4 alongside `timelineinputitem.h/.cpp`; task 7 retains the two test recorders and other consumers. Task 6 owns the additional `timelinequickview_window.cpp` predicate-name migration only. |
| Rounds 1–2, Q14 precision | Some answers substituted an “either modifier” template for the real velocity equal-binding versus unequal-binding branch. | Name the existing authority and both rendering branches explicitly. Preserve behavior; do not create a new chord table or general modifier-template abstraction. |

These are interface, identity, ownership, and dispatch changes—not merely added prose asking readers to memorize the original answers.

## Alternatives reconsidered but not adopted

### One central gate for all Quick and native sources

A final reader still described this as their initial intuition, but correctly read the revised split. Centralizing wording does not make `MouseHints` authoritative for Quick popup-session membership. Moving that authority would couple the presentation service to existing Quick session state or duplicate it. Keep the current host boundary; use the narrow predicate name and ordered admission contract to expose the limitation. There is no claim that misuse becomes impossible.

### Treat same-profile movement as a no-op

A final reader initially expected this. Text equality is not source identity: a late leave/clear from the old field must not clear the new field. Transfer ownership first and suppress only the unchanged-text notification. Additional current-profile state would not solve that source-lifetime requirement.

### Extra native inheritance sentinel or boolean

Missing widget metadata already means infer the family; a valid stored `Id::Empty` means an explicit blank override. Adding another flag or public pseudo-profile creates two representations of the same distinction. Keep property validity as the distinction, and remove pointer-only annotation composition.

### Public native-style plumbing or a typed QObject wrapper for QML

Only the existing native observer needs the style modifier; retain its private overload/friend access. QML enum values are integer-valued and the C++ argument is typed. Another public overload, gadget wrapper, or string-name fallback increases surface area without proving runtime delivery. The composed two-engine smoke is still required.

### No local classifiers at all

The catalogue must not acquire hit testing, tools, selection modes, popup sessions, or document state. Cohesive local classification in the existing automation and graph owners remains correct. Delete local sentence construction and rendered caches, not legitimate behavioral classification.

### Accept speculative scaffolding described by a reader

Some long answers invented unsupported builder names, fallback APIs, or helpers. These are not evidence of an existing contract and are not implementation requirements. Only claims grounded in the book/current source and an observable scenario were considered.

## Final focused retest adjudication

Both fresh readers independently answered the revised high-risk contracts correctly. Neither proposed a further grounded architectural change.

| Scenario | Adjudication |
|---|---|
| R1 — Quick gate versus native predicate | Both correct: retain the host gate; direct bypass is not guaranteed rejected; Empty does not alter admission. This resolves the recurring round-2 error. |
| R2 — Cache versus source lifetime | Both correct: application cache survives, old claim ends, new tab must claim, same-profile live movement still transfers ownership. |
| R3 — Profile identity | Both correct: `HorizontalScroll` shared; `TrackScope` / `EventRows` separate; partial fragments private. |
| R4 — Gesture and native configuration | Both correct: retain the graph gesture ID, add no TimelineInputItem field, zero native style removes only accelerated stepping, Quick DragScrub remains independent. |
| R5 — Process registration and proof | Both correctly distinguish process registration from per-engine borrowing and require runtime enum/two-engine proof. GateReader additionally says the build proves “QML constants compile”; that extra claim is not established by the premise. Credit C++/moc/link viability only, not QML load/evaluation. This is a verification overstatement, not a competing architecture to adopt. |
| R6 — Ownership and extension | Both correctly identify tasks 4/7, atomic acceptance, central wording, and no new fragment/source framework. Their new-action extension answers are under-specific: GateReader omits the producer selecting the new ID; ModelReader conditions its answer on the producer already selecting it. The frozen key requires that selection change as well as the new ID/catalogue entry. Do not report either as a complete extension recipe. |

The R6 omission was reconsidered: nothing in either natural-expectation answer proposes automatic target discovery, and adding such machinery would contradict the requested classification/presentation split. Keep the existing explicit target-selection contract rather than creating a registry to compensate for abbreviated answers. **Adding an enum or catalogue entry alone never wires a new target.** The implementation owner must update the existing classifier/producer when a genuinely new complete set is introduced. This is already required by the normative catalogue/producer contracts.

Consequently, this audit does **not** award a perfect final-round score. It records resolved architecture misunderstandings, two kinds of bounded response imprecision, and the reason no additional architectural mechanism is justified by them.

## Documentation verification and execution boundary

The author checked the revised dispatch contracts against the implementation worktree:

- Six SDD briefs have the required seven headings, sequential steps, at most three files and at most five steps each.
- Tasks 1–7 name 40 unique production/check/build paths with no write overlap. Thirty-eight exist in the implementation worktree; the two catalogue files are intentional additions. The mechanical consumer batch has 26 files.
- The current inventory has 30 distinct profile IDs; both scrolling targets map to `HorizontalScroll`.
- The original plan and specification link to the supplement and explicitly identify superseded contracts; historical behavior remains authoritative.
- Passed documentation validation across 16 documents: 81 local links/anchors, balanced fenced blocks, 18 original questions plus six focused scenarios, and the task/ID counts above. An initial validator assertion expected second-level rather than the quiz's actual third-level question headings; correcting that matcher completed validation without changing the quiz.

No app build, UI smoke, check suite, format run, or implementation review was performed as part of writing this plan. Those are named execution gates, not implied by scout comprehension or documentation checks.
