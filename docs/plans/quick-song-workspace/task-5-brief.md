# T05 — Retain swallowed releases for the window lifetime

## Context

A popup dismissal press swallows its matching release; today that state dies
with the popup session, so closing a tab between press and release leaks a stray
release to the survivor page. Per [spec.md](spec.md) S5, a window-owned
`QuickWindowInput` holds outstanding swallowed buttons for the window's
lifetime. Produces the `forWindow`/`swallowRelease` contract consumed by task 4.

## Exact write set

- `src/ui/songview/quick/quickwindowinput.h` (new)
- `src/ui/songview/quick/quickwindowinput.cpp` (new)

## Prerequisites

None — frozen spec only. Task 4 consumes this interface within gate A.

## Interface contract

Per spec S5, `QuickWindowInput` is a window-owned QObject in `songview/quick`
with exactly:

- `static QuickWindowInput &forWindow(QQuickWindow &window)` — reuses one
  QObject child on the window; no external registry.
- `void swallowRelease(Qt::MouseButton button)` — records an outstanding
  swallowed button.

Store only a Qt::MouseButtons bitmask. The single window filter consumes a
matching release; a release or fresh matching press/double-click clears only
that bit, while window deactivation/hide/close clears all. It outlives
individual popup sessions, including a tab closing between dismissal press and
release.

## Implementation steps

1. Implement `forWindow` as a lazily created QObject child of the `QQuickWindow`
   and install the window event filter once.
2. Implement `swallowRelease` and the release-consumption filter with the
   fresh-press/double-click and deactivation/hide/close reset rules.
3. Keep the type free of every non-release concern listed below.

## Acceptance predicate

A dismissal press followed by owner close still swallows its release, and the
next whole click edits the survivor; named check `host-integration` passes under
the gate-A run below. Local structural inspection is not a behavioral pass.

## Task-specific constraints

- No KeyPress/KeyRelease forwarding, selected-scene pointer, editor pointers,
  focus state/history or activation policy.
- It must not consume a tab-strip click merely because another page has a popup.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
