# Revision 3 — focused fresh-reader retest

Read the current [plan](plan.md), [specification](spec.md), and relevant task briefs. Do not read audit.md, earlier responses, archived books, author keys, or other readers' reports. This retest complements, rather than replaces, the original 18-question quiz.

For each R1–R6 provide the book answer, a section citation, your natural expectation before reading the contract, and confidence. Report contradictions without inventing missing rules. Work independently, read-only; skip builds/tests/formatters/linters. No contact with earlier readers.

## R1 — Can one gate replace the other?

A teammate proposes removing a QML host's Quick-popup ownership check because MouseHints::claim calls allowsNativeInput anyway. What would you implement? Is a direct claim from a covered Quick source guaranteed to be rejected? Explain the difference between that source requesting Empty and the popup itself requesting Empty.

## R2 — Cached description versus source lifetime

A hovered tab closes. The application catalogue still contains the description that tab used. What survives and what must end? Can the next tab restore the old caption from the cache without a new source claim? What differs if the pointer merely moves between two same-profile text fields?

## R3 — Which identities should be shared?

The ruler handle and voice plot each support only Shift-wheel horizontal scrolling. The event list and track header each support toggle/range selection, but only the event list supports additive Control+Shift range. Which public profiles do these four targets select? What is the rule for sharing a complete profile versus sharing a private fragment?

## R4 — Gesture state and native configuration

An interior graph-vertex drag crosses the plot background before release. Does it reclassify immediately, and where is its originating ID stored? Does TimelineInputItem gain the same field? Separately, a native fine spin editor's style step modifier becomes NoModifier: what hint remains, and does the Quick numeric DragScrub hint change with it?

## R5 — Registration and proof

A second tab creates a second Quick engine. Which registration runs again, and which object/context setup runs again? The application builds successfully with the new enum referenced by its registration code: what does that establish, and which runtime behavior still needs proof?

## R6 — Implementation ownership and adding behavior

Who owns TimelineInputHost's declaration and production overrides, and who migrates its two test adapters? May either half be accepted while the other still uses QString? Later, where would you change only wording, and what additional change is needed for a genuinely new complete action set? Do you add a public fragment builder or source-lifetime state?
