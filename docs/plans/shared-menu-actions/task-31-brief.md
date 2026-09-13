## 1. Context

Tasks 18, 20, 21 and 26–29 established owned-menu dismissal; Tasks 26–29 removed the old execution paths. This completes the clean cutover rather than keeping artificial stale activation as a supported feature.

## 2. Exact write set

- `src/ui/songview.h`
- `src/ui/songview.cpp`
- `src/ui/songview/rangeedit.cpp`
- `src/ui/songview/timeruler.h`
- `src/ui/songview/timeruler.cpp`
- `src/ui/songview/timeruler_interaction.cpp`
- `src/ui/songview/pianoroll.h`
- `src/ui/songview/pianoroll.cpp`
- `src/ui/songview/pianoroll_commands.cpp`
- `src/ui/songview/drawercoordination.cpp`
- `src/checks/host/tst_hostseams.cpp`

Mechanical exception: For each time/ruler/note menu owner, remove only its unused pending-menu structure/member, writes/resets, stale comparison and obsolete activated(int) execution sink/connection. Every action-row consumer and dismissal hook is already migrated. The two unused drawer history forwarding methods and their test-only calls are the same delete-only retirement; no production caller exists.

## 3. Prerequisites

- [Task 26](task-26-brief.md).
- [Task 27](task-27-brief.md).
- [Task 28](task-28-brief.md).
- [Task 29](task-29-brief.md).
- [Task 30](task-30-brief.md).

## 4. Interface contract

Remove PendingTimeSelectionMenu, PendingRulerMenu, PendingNoteMenu, menuSelectionStale and their now-unused handler declarations/definitions/assignments/connections. Preserve stable row enums used for lookup and every pending form/gesture transaction. Keep actionActivated focus-only completion. Also delete the unused duplicate requestDrawerPageUndo/requestDrawerPageRedo declarations/definitions and their plumbing-only host-seam invocations; their only caller is that check. MainWindow Undo/Redo retain WorkspaceUi::requestUndo/requestRedo.

## 5. Implementation steps

1. Delete the unreachable menu-only snapshot and legacy execution machinery in the exact listed owner files. Remove comments that promise stale menus remain usable or describe the old mutation sink.
2. Preserve PendingVelocityPrompt, PendingTimeSigPrompt, PendingInsertTimePrompt, automation draft guards and still-live local value-row handlers. No compatibility wrappers or empty no-op methods remain.

## 6. Acceptance predicate

All menus still execute through canonical actions with dismissal/focus behavior intact, and no obsolete time/ruler/note target snapshot path remains. Named checks: `deno task verify --filter rollcheck --filter automation --filter eventviews --filter selectionkey --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not delete real form/document validation or invent tests that manually execute a closed menu.
