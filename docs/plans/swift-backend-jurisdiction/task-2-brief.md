# Task 2: Four-way cancel-reason parity

## Context

Production cancels live interactions through a four-value reason enum
(`songview::TimelineInputCancelReason`: FocusLost, PointerUngrabbed,
Hidden, WindowDeactivated) with per-reason teardown semantics that differ
per surface (`timelineinputitem.cpp` entries, `pianoroll_interaction.cpp`,
`timeruler_interaction.cpp`, `voicechangearea.cpp`, `drawerchrome.cpp`).
The prototype has one undifferentiated `cancelPointer()` /
`cancelRightPointer()` and no focus-loss or window-deactivate path at all.
This task ports the reason enum and the grid-surface semantics matrix
([spec](spec.md) §3.2, §5.2) and wires the three QML entries plus the
native window eventFilter. Consumes Task 1's
`revision` surface (cancel rows assert revision invariance); producer for
Task 5 (Escape routes through the reason-taking cancels).

## Exact write set

Edited:
- `src/ui/songview/quick/swift-grid-prototype/PianoGrid.swift`
- `src/ui/songview/quick/swift-grid-prototype/Main.qml`
- `src/ui/songview/quick/swift-grid-prototype/App.swift` — install the
  native window eventFilter (or a small native helper this file owns)
- `src/ui/songview/quick/swift-grid-prototype/CMakeLists.txt` — only if a
  new native TU is required for the filter
- `src/checks/swiftgridprototype/jurisdiction_smoke.cpp` — append `verifyGridCancel`
- `src/checks/swiftgridprototype/grid_smoke.h` — declare `verifyGridCancel(QQuickWindow *, QObject *)`
- `src/checks/swiftgridprototype/grid_smoke.cpp` — call it after `verifyGridUndo`

Created (only if App.swift cannot attach the filter alone):
- one small native helper under `src/ui/songview/quick/swift-grid-prototype/native/`

## Prerequisites

Task 1 (`revision`, `canUndo` surface used by the cancel rows).

## Interface contract

- `GridCancelReason` with raw values 0–3 in production declaration order
  (spec §3.2), declared in `PianoGrid.swift` (it is the grid's input
  vocabulary; no new file).
- `cancelPointer(reason: Int)` / `cancelRightPointer(reason: Int)` replace
  the no-arg versions — clean cutover: both `Main.qml` call sites and the
  existing interaction-smoke `onCanceled` path update in this task; no
  deprecated shims.
- Behavior exactly per the spec §3.2 matrix: `focusLost` keeps both
  gesture families alive with zero state change (subsequent
  `updatePointer`/`endPointer` still work and commit);
  `pointerUngrabbed` is today's teardown plus right-gesture
  `selectionAtRightPress` restore; `hidden` and `windowDeactivated` add
  hover teardown (`hoverKey`, `cursorKind`) and pitch-preview discard
  (`cancelPitchCurves()` path) when an editor is open; unknown codes are
  no-ops.
- Entries per spec §3.2: MouseArea `onCanceled` → reason 1; grid input
  surface `onActiveFocusChanged` (lost while visible) → reason 0;
  `onVisibleChanged` false → reason 2 on the grid surface **and** the
  window (window `hide()` is Hidden, not WindowDeactivated); native
  window `eventFilter` Hide + WindowDeactivate → reason 3 once. Do not
  wire reason 3 through QML `onActiveChanged`. Popup surfaces are not
  torn down by the grid's window-deactivate path (host arbitration).
- Smoke: `verifyGridCancel` implements the five spec §6.2 rows, driving
  real Qt events — `ungrabMouse()` on the grabber, `forceActiveFocus`
  steal, hide (`visible = false` and/or window `hide()`), and a
  `QEvent::WindowDeactivate` sent to the window (production
  `sendWindowDeactivate`). Hidden ends `!isVisible` on the hidden
  object; WindowDeactivate ends with the window still `isVisible`. Do
  not assert `!isActive()`.

## Implementation steps

1. Add `GridCancelReason` and the reason-taking cancels; split today's
   teardown into the matrix's per-reason behaviors. Preserve the existing
   `guard let g = gesture` no-op for every reason.
2. Wire the three QML entries and the native window eventFilter. The
   focus entry must not fire on the grid's own menu-open focus handoff
   (that popup keeps its own input — production menu-session rule); the
   visible guard in the QML handler is the arbiter of that. Window
   `onVisibleChanged` is Hidden (reason 2). Reason 3 is the eventFilter
   only.
3. Append `verifyGridCancel` with the §6.2 rows; the focus-loss row must
   prove survival behaviorally (a later move + release commits, Task 1's
   `undo` restores), not just status text. Hidden and WindowDeactivate
   rows assert the visibility predicate that separates them.
4. Run the acceptance check.

## Acceptance predicate

All five §6.2 rows pass: ungrab discards previews without mutation,
focus loss keeps a live gesture committable, hidden and
window-deactivated tear down with hover/preview cleanup, right-ungrab
restores the captured selection; `revision` never advances through a
cancel; Wave-1 groups, existing smokes, Task-1 undo rows, and the final
`SWIFT_GRID_SMOKE PASS` unchanged. Named checks (implementer runs):

- `deno task prototype:swift-grid --smoke`

Covers: four entry paths through real event delivery, per-reason teardown
differences (survival vs teardown vs teardown+hover/preview), right-family
selection restore, window-level once-only delivery with popup
protection. Coverage gap, named: the production entry paths themselves
are exercised by the automation/selectionkey suites against C++ surfaces
this task does not touch — they are normative sources here, not gates;
Swift-side parity is claimed only through the smoke rows. The parity
oracle is not a gate for this task (spec §1 D6).

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk:
`hidden` and `windowDeactivated` have identical grid-surface teardown by
design (production PianoRoll treats them identically); do not invent a
difference — the rows prove the entry difference (and the visibility
predicate), not a teardown difference. Synthesized WindowDeactivate does
not flip `isActive`; do not restore-or-assert it. Do not wire popup
teardown on window deactivation (spec §8 defers popup-session parity).
