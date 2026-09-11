## 1. Context

Task 10 supplies invalidation, Task 22 exposes the guarded velocity form, Task 24 owns its QAction and Task 19 supplies action rows. This task lands note-menu dismissal and projection together; Task 31 retires leftover storage.

## 2. Exact write set

- `src/ui/songview/pianoroll.cpp`
- `src/ui/songview/pianoroll_commands.cpp`
- `src/checks/rollcheck/pencil_velocity.cpp`

## 3. Prerequisites

- [Task 19](task-19-brief.md).
- [Task 24](task-24-brief.md).

## 4. Interface contract

NoteMenuAction Copy/Cut/Delete/Velocity rows are fromAction projections of the bound canonical actions. Set Velocity uses the static action label. No note-menu-local command switch executes these rows; focus-only completion must not steal a newly opened form. Connect contextMenusInvalidated once and cancel only an owned note-menu session, preserving independent velocity forms and normal/teardown focus policy.

## 5. Implementation steps

1. Add the owned-menu invalidation hook at the existing PianoRoll menu lifecycle without broad transient cancellation.
2. Replace note row metadata and ID execution with action projections, retaining ordinary right-click selection/retarget behavior.
3. Preserve no-cursor/no-seek note-grid behavior and modal velocity lifetime. If terminal focus restoration is needed, use actionActivated solely for that purpose after checking the session.
4. Exercise Copy/Cut/Delete and velocity opening after retarget; retain selection dismissal and one-edit/undo observations rather than snapshot internals. Replace old stale-menu-click assertions with synchronous dismissal and unchanged document/undo state.

## 6. Acceptance predicate

The rendered note menu activates canonical commands once on current selected notes, opens the existing velocity form safely, and never gains ruler-style cursor/seek behavior. Named checks: `deno task verify --filter rollcheck --filter selectionkey-local-input --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Remove the per-row velocity suffix rather than adding a label override API or second Velocity action.
