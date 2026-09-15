# T08 — Let native item scopes own editor keyboard routing

## Context

With several pages sharing one window, key dispatch and grab cancellation must
be scoped to the eligible page, per [spec.md](spec.md) S4. `TimelineCanvas`
becomes the FocusScope that owns focused descendants; dispatch is gated on task
1's `isInputEligible()`. Consumes task 1's eligibility contract; task 10's
`QuickSceneHost` relies on this gating for readiness-mirroring.

## Exact write set

- `src/ui/songview/quick/timelinequickview_keyrouting.cpp`
- `src/ui/songview/quick/TimelineCanvas.qml`

## Prerequisites

Task 1 — consumes `isInputEligible()` and the canvas-as-`rootObject` contract
only. Task 1 deletes the window-level KeyPress/KeyRelease no-activeFocus
fallback; this task must not reintroduce it or move it into a host dispatcher.

## Interface contract

Per spec S4:

- `TimelineCanvas.qml` root becomes a `FocusScope` with `focus: true`; the
  existing `Keys.onPressed`/`Keys.onReleased` fallback stays at that root. Popup
  visual descendants remain inside this canvas scope (task 4).
- Scene-root/item policy dispatch and QML scrollbar mutators are gated on
  `isInputEligible()`. On eligibility loss, cancel interactions and audition
  immediately without committing; ungrab a `mouseGrabberItem` only when it
  descends from this canvas/popup — never a sibling page or tab-strip grab.
- Retained unchanged: `TimelineInputItem` interaction-first delivery, the
  local-then-semantic Keys path,
  `SongView::handleEditKey`/`handleEditKeyRelease`, `EditActions` semantics, and
  no-key-recipient behavior (editor-only commands invent no recipient).
- `AutomationPage::setInputWindow` remains the pencil-binding seam
  (bound/unbound by task 2); do not add `readinessForInput`, a dispatcher, or
  change AutomationPage pencil routing.

## Implementation steps

1. Make the canvas root a `FocusScope` with `focus: true`, keeping the existing
   Keys handlers in place.
2. Gate `dispatchSongKey`/`dispatchSongKeyRelease` and the QML scrollbar mutator
   entry points on `isInputEligible()`.
3. Implement the eligibility-loss cancellation and descendant-scoped ungrab
   rule.

## Acceptance predicate

Text and editor commands stay local, no-focus does not dispatch, and page A
cannot cancel page B's or the strip's grab; named checks `selectionkey` and
`host-integration` pass under the gate-A run below. Local structural inspection
is not a behavioral pass.

## Task-specific constraints

- No `forceActiveFocus` on ordinary selection, ready notification, row movement,
  popup cancellation, window activation or timers (S4).
- No new key dispatcher, focus cache or queued focus repair.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
