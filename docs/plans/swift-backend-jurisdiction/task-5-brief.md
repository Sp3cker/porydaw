# Task 5: Single Escape arbiter

## Context

Production routes Escape once, at the top of
`SongView::handleEditKey`: a live pointer gesture cancels (preserving its
captured selection), an idle Escape clears the selection — one decision
point taking full surface state. The prototype instead has three
independent QML deciders: `NoteMenu.qml` (Keys Escape → `close()`),
`PitchBendPopup.qml` (Escape → `bridge.cancelAndClose()`), and
`PitchBendGraph.qml` (`Keys.onShortcutOverride` claims Escape, popup
decides) — plus no window-tier fallback for an idle grid. This task moves
the decision into one Swift entry point ([spec](spec.md) §3.5) and turns every QML
surface into a forwarder, per the host-arbitration rule (spec §1 D1):
QML delivers the already-arbitrated observation (`noteMenuOpen`), Swift
decides, QML executes the returned action. Consumes Task 2's
reason-taking cancels (Escape routes through the pointer-ungrab
teardown, matching production's `cancelInteraction()` default).

## Exact write set

Edited:
- `src/ui/songview/quick/swift-grid-prototype/PianoGrid.swift` — `GridEscapeAction`, `escapePressed(noteMenuOpen:)`
- `src/ui/songview/quick/swift-grid-prototype/Main.qml` — window-tier Escape forward on the grid input surface; popup/menu hosts execute returned actions
- `src/ui/songview/quick/swift-grid-prototype/NoteMenu.qml` — Escape branch forwards instead of closing
- `src/ui/songview/quick/swift-grid-prototype/PitchBendPopup.qml` — Escape branch forwards instead of calling `cancelAndClose()` directly
- `src/ui/songview/quick/swift-grid-prototype/PitchBendGraph.qml` — keep the ShortcutOverride claim; forward the pressed Escape
- `src/checks/swiftgridprototype/jurisdiction_smoke.cpp` — append `verifyGridEscape`
- `src/checks/swiftgridprototype/grid_smoke.h` — declare `verifyGridEscape(QQuickWindow *, QObject *)`
- `src/checks/swiftgridprototype/grid_smoke.cpp` — call it after `verifyGridCancel`

## Prerequisites

Task 2 (`cancelPointer(reason:)` teardown that Escape reuses).

## Interface contract

- `PianoGrid` gains exactly spec §3.5: `GridEscapeAction`
  (`none`/`cancelGesture`/`closePitchEditor`/`closeNoteMenu`/
  `clearSelection`) and
  `@discardableResult public func escapePressed(noteMenuOpen: Bool) -> GridEscapeAction`.
- Precedence frozen: live gesture (either family) → teardown identical to
  `cancelPointer(reason: 1)` including the right-family
  `selectionAtRightPress` restore → `.cancelGesture`; else open pitch
  editor → cancel graph gestures + `cancelPitchCurves()` + close →
  `.closePitchEditor`; else `noteMenuOpen` → `.closeNoteMenu` (no model
  menu state); else clear the note selection → `.clearSelection`.
  Escape is always consumed (model side effects happen inside; the return
  value only tells QML what visual to tear down).
- QML forwarding shape everywhere (spec §3.5):
  `gridModel.escapePressed(noteMenu.opened)` then a switch on the action
  — `closePitchEditor` → close the pitch popup host (its existing
  `onClosed` nulls `pitchBridge` and calls `closePitchEditor()`);
  `closeNoteMenu` → `noteMenu.close()`; other actions need no QML work.
  The graph's ShortcutOverride keeps claiming Escape so the focused
  canvas still receives it; its pressed handler forwards.
- Smoke: `verifyGridEscape` implements the five spec §6.4 rows,
  delivering Escape as real key events against each focus surface
  (graph focus, popup focus, grid surface focus) and asserting the
  arbiter's action through observable state (gesture gone, popup closed,
  menu closed, selection empty, preview discarded, `revision`
  unchanged).

## Implementation steps

1. Add `GridEscapeAction` and `escapePressed` per the frozen precedence;
   the gesture branch must reuse the Task-2 teardown, not duplicate it.
2. Convert the three QML deciders to forwarders and add the window-tier
   fallback on the grid input surface (the surface that already receives
   `forceActiveFocus` after popup closes). No surface may close itself
   on Escape except by executing the returned action.
3. Append `verifyGridEscape` with the §6.4 rows, including the
   preview-discard assertion through the interaction smoke's existing
   popup-reopen raster pattern.
4. Run the acceptance check.

## Acceptance predicate

All five §6.4 rows pass: Escape mid-gesture cancels without mutation and
preserves the captured selection; Escape from any popup/graph focus
closes the pitch editor discarding only the live preview; the note menu
closes with selection preserved; idle Escape clears the selection; every
focus path reaches the same arbiter decision. `revision` never advances.
Wave-1 groups, existing smokes, Tasks 1–4 groups, and the final
`SWIFT_GRID_SMOKE PASS` unchanged — including the existing
`pitch-abort-and-escape-discard-live-preview` interaction rows, which now
run through the arbiter. Named checks (implementer runs):

- `deno task prototype:swift-grid --smoke`

Covers: arbiter precedence across all four surface states, QML
forwarding from every previous independent handler, preview/commit
split, selection preservation, single-path ownership. Coverage gap,
named: production's Escape also drives the shared popup session's
ShortcutOverride swallowing (spec §8) — only the pitch popup's claim is
in scope here; menu-popup session parity stays deferred. The parity
oracle is not a gate for this task (spec §1 D6).

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk:
double delivery — a surface that both forwards and handles, or a
ShortcutOverride claim without a matching forward, silently eats Escape;
the `escape-single-arbiter-paths` row exists to catch exactly that. Do
not add focus memory or a key queue (AGENTS.md); the arbiter is stateless
over the observed `noteMenuOpen` and model state. Runs after Task 3
settles to keep `jurisdiction_smoke.cpp` single-writer, though its only
interface need is Task 2.
