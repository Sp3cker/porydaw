# Task 6: Defend live and stale menu insertion

## Context

Task 5 changes two insertion callsites. This task retains proof for both and supplies menu evidence to Task 7; window deletion proof already belongs to Task 4.

## Exact write set

- `src/checks/rollcheck/timemenu.cpp`
- `src/checks/rollcheck/ruler_loop_menu.cpp`
- `src/checks/rollcheck/tst_pianoroll.h`

## Prerequisites

Task 5: guarded unified insertion in both existing context menus.

## Interface contract

Reuse PianoRollTest's existing fixtures, `openSharedTimeMenu()`, ruler pointer helpers and `quick_popup::clickMenuRow()` to open real menus and activate rendered rows by typed ID. Each changed insertion path receives live and stale-target coverage; no parallel menu-test abstraction is introduced.

## Implementation steps

1. Open the selection menu through `openSharedTimeMenu`, activate InsertBlank with `quick_popup::clickMenuRow`, and prove scoped insertion and one undo using a snapshot taken after fixture setup.
2. Exercise the ruler menu through its real pointer helpers with a click tick different from the selected start; prove insertion uses the selection and restores bytes with one undo.
3. For each menu, open with a selection, clear the selection, then attempt the original InsertBlank activation. Prove no mutation, undo entry, cursor move or duration prompt; retain existing document-revision stale cases.
4. Declare only necessary new slots in `tst_pianoroll.h`; preserve existing Copy/Paste/loop/signature coverage.

## Acceptance predicate

Both changed menu insertion paths perform one selected-scope transaction and reject expired selection targets without global-prompt fallback. Named checks: `deno task verify --filter rollcheck --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risk: a stale-row test can pass without exercising activation if its target vanished before the attempted click; use existing popup helpers to establish the real menu/row before invalidating the selection. Do not add a full insertion/deletion-by-menu matrix. The unchanged removal dispatches receive live smoke coverage under the shared verification policy.
