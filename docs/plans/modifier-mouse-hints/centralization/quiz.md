# Open-book architecture quiz

Book: [plan.md](plan.md), [spec.md](spec.md), and the six linked task briefs. Read the book before answering. The original behavior spec may be consulted where the supplement defers to it. Treat current production strings as the implementation being replaced, not as a competing design.

## Purpose and protocol

This is a test of the architecture's learnability, not the reader's memory. Readers work independently and cannot inspect the author's answer key, other readers' answers, or audit.md. They must not edit code/documents or run builds/tests/formatters/linters. Answer all questions without negotiating intended answers with the author.

For each question give:

1. **Book answer:** what you would implement, including the owning module or relevant call when useful.
2. **Evidence:** section/file in the book supporting that answer; say "not specified" if the decision is absent.
3. **Natural expectation:** what you would have expected from the names/interface before reading that rule. If it differs, describe the simpler or less surprising alternative. Do not suppress disagreement to match the book.
4. **Confidence:** high, medium, or low.

After the answers, identify at most three architecture changes that would make correct use more obvious. Prefer deleting a rule or moving ownership over adding documentation. Mark any contradiction or unimplementable requirement separately from personal preference.

The author fixes an answer key before dispatch. A book-answer mismatch is evidence against the architecture/contract, not an automatic reader failure. Correct answers with contrary natural expectations also receive a ruling. The author may retain a rule only with a concrete reason tied to existing behavior or a simpler overall design. Material revisions require fresh-reader retesting; coaching the same reader to repeat the desired answer is not evidence.

## Questions

### Q1 — Edit wording

A designer wants to improve the wording of the velocity note's detent explanation without changing the gesture. Which production module(s) should be edited? What should the velocity element continue to supply?

### Q2 — Same sentence, different meaning

A ruler handle and a voice-lane background both support exactly Shift-wheel horizontal scrolling. EventRows and TrackScope both include toggle/range descriptions. Which, if any, should share a public profile, and where may partial duplication be removed?

### Q3 — Blank target

The pointer moves from a described note to an ordinary no-hint control. What does the new target publish? Is that the same operation as the old target ending its hover? Explain what remains owned afterward.

### Q4 — Equal descriptions, new owner

Text field A and text field B use the same profile. The pointer moves A → B and then A's old leave is handled. Can publication skip work because the profile/text did not change? What should be visible after the leave?

### Q5 — Popup coverage

An underlying control still has a true hover flag while a popup covers it. Through its ordinary hover host it requests an Empty claim. Does blank text bypass suppression? Contrast a Quick popup's host/session gate with the native/application gate and the popup's own admitted Empty claim.

### Q6 — Stationary tool change

With a stationary pointer, automation switches from sweep to pencil. Who determines the new profile? Which existing host operation should update it? What if another source already owns the display?

### Q7 — Native fine editor

The native custom spin editor has fine drag and inherits accelerated wheel stepping. Its element calls setWidgetProfile. Is it assigning pointer-only metadata or a complete description? Where is the inherited wheel alternative supplied? What if metadata is absent versus explicitly Empty?

### Q8 — Style changes to no modifier

A native style reports Qt::NoModifier for accelerated spin stepping. Describe the expected hints over (a) the spin body, (b) its ordinary editor, and (c) its fine-drag editor. Does a QML numeric input necessarily change too?

### Q9 — Runtime parameter

Which current producer needs an extra publication parameter beyond source/profile? Where is that parameter obtained, and can ordinary elements or QML pass it through the public publisher?

### Q10 — Two tabs

The application opens a second song tab with another Quick engine. How do HintProfiles constants and the MouseHints object reach it? Should the existing context property be replaced with qmlRegisterSingletonInstance?

### Q11 — QML representation

A QML field binds its hover profile. What is stored in HoverHint: a sentence, string name, enum-valued integer, or object? What is the public C++ publication parameter type? What is the response if enum delivery fails at runtime?

### Q12 — Gesture retention

A graph drag starts over an interior vertex, then crosses blank plot space before release. What is retained, by whom, and when is the profile reclassified? Should this refactor add the same retained field to TimelineInputItem?

### Q13 — Cache ownership

The pointer moves across the same target repeatedly, then that tab closes and another is opened. Where are rendered strings cached? Does an empty rendered string mean cache miss? Which existing modules may still legitimately store a QString?

### Q14 — Keymap versus held modifiers

The velocity detent modifier is defined in the existing keymap. Should the catalogue hard-code the current Control value, accept it from each element, read the canonical binding, or watch held keys? What happens to the existing equal-chord/unequal-chord wording branch?

### Q15 — New target

A future interaction adds a genuinely distinct modifier action on a target that already has a hit resolver. What must be added, and what should not be added to the catalogue or source-lifetime machinery? Would a public fragment builder make this easier in the intended design?

### Q16 — No alternatives available now

A described action would have no useful effect on the current selection. Should the element switch to Empty, should the catalogue inspect the document, or should the existing target's profile remain? Explain the distinction between target classification and action eligibility.

### Q17 — Atomic migration

The publisher and production input host have switched to Id, but the QML producers and test hosts still pass strings. Can that subset be accepted or checkpointed? Is a temporary compatibility overload part of the plan? Which task owns the outstanding producer/recorder migration?

### Q18 — Proof and authority

The architecture quiz is answered correctly and build:app succeeds. What remains unproven? Which document controls old behavior versus the new payload/description architecture, and what additional evidence is required before implementation is called complete?
