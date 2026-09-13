## 1. Context

Task 10 supplies context invalidation, Task 19 supplies action rows, and Tasks 20/21 retire automation fallback menus. This task lands time-menu dismissal and action projection together on their single verification surface.

## 2. Exact write set

- `src/ui/songview.cpp`
- `src/ui/songview/rangeedit.cpp`
- `src/checks/rollcheck/timemenu.cpp`

## 3. Prerequisites

- [Task 19](task-19-brief.md).
- [Task 25](task-25-brief.md).
- [Task 20](task-20-brief.md).
- [Task 21](task-21-brief.md).

## 4. Interface contract

buildTimeSelectionItems returns fromAction rows for existing TimeSelectionAction IDs. Their handlers are canonical actions, not the old local execution switch. Connect actionActivated only for terminal focus return when no new session opened. Task 31 removes now-unreachable menu target storage/sinks. Connect the SongView-owned time-menu host to contextMenusInvalidated with session ownership and restoreFocus checks; leave foreign forms alone.

## 5. Implementation steps

1. Subscribe once at the existing time-menu host lifecycle, using ownership checks and the supplied restoreFocus policy. Do not close foreign popup owners.
2. Map Copy/Cut/Delete/InsertBlank/Duplicate/RemoveContents/Paste/Clear IDs to the exact canonical actions, keeping Delete Selection distinct from Delete Time (Shift Left). Remove hand-authored shortcut text/enablement and live use of the pending snapshot route.
3. Preserve Paste’s real note-or-range clipboard eligibility and fresh payload read. In the poison-clipboard test, poison before opening the Copy phase because an eligibility flip now retires an open menu; retain the disabled-Paste no-activation case.
4. Observe focus-only actionActivated after the command; do not override focus of an Insert Time form opened by it. Keep lane/tempo targeting through the shared producer. Replace stale-activation scenarios with immediate dismissal and unchanged document/undo assertions, without clicking an old model.

## 6. Acceptance predicate

Rendered range menus and automation fallbacks activate the same actions as Edit/keys once, preserve clipboard contents/targeting and focus, and dismiss when eligibility/context changes. Named checks: `deno task verify --filter rollcheck --filter automation-editing --filter selectionkey --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Stable row IDs are lookup aids only. Do not emit or consume synthetic activated(int) to execute closed range menus.
