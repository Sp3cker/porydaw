## 1. Context

The user explicitly chose edit cursor over moving playhead. Task 28 establishes that cursor for outside/no-selection ruler menus.

## 2. Exact write set

- `src/ui/songview/rangeedit.cpp`
- `src/ui/songview.h`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`

## 3. Prerequisites

- [Task 28](task-28-brief.md).

## 4. Interface contract

Without active selection, insertTime opens the duration form at editCursorTick even while playing, capturing that cursor/meter at form open. Eligible active selection remains immediate and selection-first; unresolved active selection rejects without prompt fallback or state changes. Update the public comment that currently mentions live playhead.

## 5. Implementation steps

1. Replace only the no-selection playing/stopped anchor choice with edit cursor. Keep the form’s captured target, local-meter duration and transaction guards.
2. Update playing cases to give edit cursor and playhead different positions, advance playback while the form is open and verify insertion at the captured cursor. Preserve selected-playing, unresolved-scope, cancel and stale-form checks.
3. Exercise the outside-selection ruler flow through prompt acceptance, and verify a plain Insert Time activation with no ruler click uses the preexisting edit cursor.

## 6. Acceptance predicate

Insert Time always follows the selected valid span or captured stationary edit cursor, never the advancing playhead, and invalid selected scope cannot fall through to a prompt. Named checks: `deno task verify --filter mainwindow-routing-input --filter rollcheck --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not remove PendingInsertTimePrompt, use current cursor again at acceptance, or change selected interval insertion semantics.
