# Modifier-mouse hints: first-revision scout quiz

Historical record: this quiz was given independently to HintQuizAlpha and HintQuizBeta against the frozen first-revision plan. Results and limitations remain in [audit.md](audit.md); later changes do not retroactively alter scores. The current revision's fresh quiz is in [readiness.md](readiness.md).

Read only docs/plans/modifier-mouse-hints/plan.md, spec.md, inventory.md and relevant task briefs. Do not inspect application source, other agents, answer keys or reports. The test is whether the written plan communicates an executable design, not whether you can repair it from general Qt knowledge.

Answer each question with: conclusion, the plan path/section supporting it, and confidence (high/medium/low). Where the plan does not specify a necessary mechanism or contains conflicting requirements, say NOT SPECIFIED or CONTRADICTION and explain the missing decision. Do not invent a mechanism and present it as planned. Keep each answer under 100 words. Finish with up to three requirements you would need clarified before implementing.

1. A parameter tab cannot currently be ghosted, and no modifier key is held. What hint should hovering it show? Which kinds of target-specific distinctions may change a hint, and which predicates must not?
2. An operation message is currently visible. Where does a newly hovered target's hint go, how is space reserved, and what happens to the operation message and meter?
3. Execute this sequence: publish(A, "same"), publish(B, "same"), clear(A), destroy(A), clear(B). State current owner/text and whether hintChanged fires after every step. Explain the distinction between owner and text changes.
4. The pointer enters target B, which has no modifier alternatives, while A owns a nonempty hint. Then an old leave arrives from A. Which calls should the two targets make and what remains? Is publishing an empty string interchangeable with clearing on unhover?
5. A C++ timeline band and three QML controls need hints. What objects do they use as source, how do they reach the module, and who owns the module? Does the plan change TimelineInputHost or register a QML singleton?
6. Why does Task 4 add hover-enter forwarding? What exact condition prevents this new path from modifying a live gesture? What behavior must remain unchanged?
7. While hovering a note body, an actual drag starts, the pointer leaves its original bounds, and release occurs outside. Describe hint lifetime and whether holding another modifier during the drag updates, freezes or changes the actual action semantics.
8. Compare hints for a roll note body, a resize edge, and the piano-key gutter. Which wheel alternatives apply? Where may the target discrimination be computed?
9. Compare the automation node, origin phantom, sweep background and pencil background. Which gets Alt fine time, which does not? What happens when pencil mode changes under a stationary cursor?
10. Is additive selection decided at press or release for roll right-marquee and velocity right-marquee? Are the registered detent-unlock rules identical in the velocity plot and gutter?
11. Compare Control+Shift click in an event row with Control+Shift click in a track header. What happens to their hints over an active inline text editor or mute/solo/add control?
12. A standard single-selection list, a NoSelection table, an ordinary QLineEdit and DragSpinBox's overridden editor are hovered. Which selection/fine-drag hints apply? Does custom pointer metadata replace inherited wheel behavior too?
13. Which descriptions belong to pitch/modulation graph background, interior vertex, pinned endpoint and outside-canvas margins? Is Shift+Alt a required combined line-drawing chord?
14. A popup opens over the currently hinted editor, then its numeric child becomes hovered, then the popup closes beneath a stationary pointer. Describe the publication/clear sequence and the stated mechanism for restoring the underlying target. Distinguish guaranteed mechanics from requirements without a specified mechanism.
15. A parent QML row and nested text editor both have nonblocking hover observers. The editor publishes, then the parent's callback publishes. What chooses the winning target under the public contract? Does the plan specify how to prevent parent overwrite without changing event blocking?
16. The user moves from a hinted source to the hint label to inspect its elided tooltip. The source's leave happens first. What text is available when the label is entered? Identify the stated mechanism, or an unresolved conflict.
17. The same C++ band QObject owns both plot and gutter input items. Plot publishes, gutter publishes, then plot sends a late clear using that band QObject. What does the defined interface do? Does the promised stale-clear protection distinguish these two physical targets?
18. Which existing checks observe the real MainWindow status label, which use the public text accessor with an unhosted EditorRig, and what evidence is still required beyond green tests? Name the relevant task ownership without inventing a new harness.
