## 1. Context

The existing key switch mixes input-origin arbitration and domain execution. This task preserves behavior while producing the semantic interface consumed by Task 9 and the eventual key-only cutover in Task 15.

## 2. Exact write set

- `src/ui/songview.h`
- `src/ui/songview/editkeyrouting.cpp`
- `src/ui/songview/quick/eventlistcontroller.h`

## 3. Prerequisites

- [Task 7](task-7-brief.md).

## 4. Interface contract

Publish SongView::EditCommand for existing shared commands plus InsertTime, DeleteTime, ClearTimeSelection, PencilMode, MoveEventUp and MoveEventDown, with editCommandAvailable(EditCommand) const and executeEditCommand(EditCommand). Copy execution delegates to existing copySelection(), not another time/note precedence branch. Add the small inline EventListController::canMoveCurrentRow(int delta) const predicate next to its existing accessors; it owns visibility, non-editing and legal-current-row checks, including valid destination zero. handleEditKey retains recognition, origin eligibility, repeat, Escape and terminal consumption until Task 15; do not yet remove the physical-owner flag.

## 5. Implementation steps

1. Extract existing musical operations without changing their target authority: Copy uses copySelection()'s time-first branch; other note/time commands retain their existing resolver and local-origin restrictions. No focused-drawer targeting.
2. Centralize semantic gesture/readiness protection, including Window Solo. Add real entries for current Insert/Delete Time, Clear Time Selection, Pencil toggle and same-tick event moves. Event eligibility delegates to canMoveCurrentRow; its predicate never examines note/time selection and hides the raw destination sentinel from action code.
3. Derive action availability from those semantic operations. Preserve lane-transpose and unavailable-Duplicate terminal behavior, clipboard target assertions and key-release audition; no eligibility predicates are added to Registry.

## 6. Acceptance predicate

Shared keyboard edits retain their target, untouched neighbors and undo behavior after extraction; semantic Solo cannot mutate during a competing gesture. Named checks: `deno task verify --filter selectionkey --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not expose private roll/ruler objects or store invocation origin. Set Velocity and positional loop/signature enum entries arrive with Task 24.
