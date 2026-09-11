## 1. Context

Task 18 supplies retirement, Task 19 supplies QAction-backed row projection, and Task 24 supplies positional actions. This changes ruler right-click state establishment and removes its live dependence on clicked-target dispatch; Task 30 consumes the resulting cursor transition and Task 31 deletes leftover snapshot fields/sinks.

## 2. Exact write set

- `src/ui/songview/timeruler.h`
- `src/ui/songview/timeruler_interaction.cpp`
- `src/checks/rollcheck/ruler_loop_menu.cpp`

## 3. Prerequisites

- [Task 18](task-18-brief.md).
- [Task 19](task-19-brief.md).
- [Task 24](task-24-brief.md).

## 4. Interface contract

Replace the private showRulerMenu(uint64_t clickTick, const QPointF &scenePos) entry with showRulerMenu(const QPointF &scenePos). It consumes raw/exact right-press gesture state through the two terminal paths in spec.md#target-establishment, never a pre-snapped argument. The selection path finishes before cursor snapping/commit/seek is reachable. Both menu compositions use current canonical actions; clicked target state ends before the menu opens.

## 5. Implementation steps

1. Separate right-press raw/exact target state from the left-drag snapped m_selAnchor, and remove the clickTick argument from the release call. On completed release, the inside-selection path opens and finishes first; only the other path snaps a background coordinate and commits/seeks. Clear press state on release/cancel and preserve exact chip identity.
2. Compose the ruler's spec-defined inside/outside row sets directly from canonical actions, omitting positional/signature rows inside. Do not consume buildTimeSelectionItems or its TimeSelectionAction ID mapping: the ruler has its own menu composition. Remove live pending-target use and use actionActivated for post-command ruler focus only when no form opened.
3. Rewrite old outside-click selection tests to click inside. Cover a raw inside coordinate that would snap to the end remaining inside with unchanged cursor/seek, and an exact-end click taking the cursor path; also cover no selection, exact chip identity and cancellation. Move negative Remove Signature cases away from explicit events and preserve incremental loop undo.

## 6. Acceptance predicate

Ruler inside/outside/chip interactions establish the specified selection/cursor/seek state before opening, execute one canonical action, and preserve two-step loop undo and guarded forms. Named checks: `deno task verify --filter rollcheck --filter mainwindow-routing-input --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not add note-grid seek behavior, store clicked ticks after open, or restore an old cursor when the user dismisses the menu.
