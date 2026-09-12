# Task 1: Rename the insertion command

## Context

Rename Function refactoring: the current public name describes only the prompt anchor. Task 2 consumes the neutral command name; Task 3 retains the existing window action caller.

## Exact write set

- `src/ui/songview.h`
- `src/ui/songview/rangeedit.cpp`
- `src/mainwindow.cpp`
- `src/checks/rollcheck/velocity_prompt.cpp`

## Prerequisites

None.

## Interface contract

Public `void SongView::insertTime()` replaces `void SongView::insertTimeAtPlaybackCursor()` without changing behavior. SongView's existing `openInsertTimePrompt()` in `rangeedit.cpp` remains the prompt owner; this task adds no wrapper or new command owner.

## Implementation steps

1. Use LSP references and rename for the declaration, definition, MainWindow caller and velocity-prompt check caller in the closed write set.
2. Preserve control flow, prompt behavior, action IDs and test expectations; remove the old symbol without an alias.

## Acceptance predicate

All callers resolve to the new command with unchanged prompt cancellation and undo behavior. Named checks: LSP rename/reference result; `deno task verify --filter rollcheck --filter mainwindow-routing-input --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: a missed semantic caller breaks the clean rename; LSP must cover the complete reference set. Pure same-shape rename only; semantic changes belong to Task 2.
