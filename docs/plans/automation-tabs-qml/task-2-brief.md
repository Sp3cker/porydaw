# Task 2 — Gutter-internal scrolling, remove the height Binding

Runs after Task 1 (same file — Task 1 is reviewed and approved; its hunks
are the base). With the floor gone (Task 3 landed), the grid's cumulative
height no longer constrains the drawer — but the grid would overflow a
shorter gutter, so it must scroll internally.

## Target

- `src/ui/songview/quick/AutomationTabs.qml` — the only file. Nothing else.

## Change

1. Wrap the `grid` GridLayout in a `Flickable` that `anchors.fill: parent`
   with `clip: true`, `contentWidth: width`,
   `contentHeight: grid.implicitHeight`, `flickableDirection` vertical.
   The grid keeps its columns, rows, TabButtons, objectNames
   (`automationParameterTab<N>` — checks resolve tabs through them), and all
   Task 1 styling/behavior; only its anchors change to live inside the
   Flickable content (width bound to the Flickable width).
2. Delete the `minimumContentHeight` Binding block. The C++ property still
   exists (Task 4 removes it) — a written-but-unread value is harmless for
   one step; do NOT touch C++ here.
3. No scrollbar chrome (gutter too narrow); Flickable default wheel/drag
   scrolling applies. Note the wheel-behavior change (wheel over the gutter
   now scrolls tabs) in the result for the reviewer.

## Acceptance

`grep pattern="minimumContentHeight" path="src/ui/songview/quick"` finds
nothing. `deno task format` does NOT accept QML (clang-format errors on
`.qml`) — skip the format step for this file. `deno task build:app` (which
compiles the QML via qmlcachegen) passes. Verification is non-waivable:
report command plus output, pasted raw not prose. Harness runs stay
controller-side.
