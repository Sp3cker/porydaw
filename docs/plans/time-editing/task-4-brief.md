# Task 4: Prove window command routing

## Context

Tasks 2/3 produce the command policy and QAction surfaces. This task supplies window evidence consumed by Task 7.

## Exact write set

- `src/checks/mainwindowrouting/tst_mainwindowrouting_input.cpp`
- `src/checks/mainwindowrouting/tst_mainwindowrouting_native.cpp`

## Prerequisites

Task 2: selection-aware insertion. Task 3: registry-backed deletion QAction.

## Interface contract

Extend existing window QtTest classes through `MainWindowRoutingFixture` and their Quick popup/input helpers: input checks own selected-song routing and undo; a dedicated native time-editing slot owns real input dispatch and local-input protection. Reuse `keymap::Registry::snapshotOverrides()` / `restoreOverrides()` with Qt's `qScopeGuard` for temporary binding changes, not bespoke settings rollback.

## Implementation steps

1. Exercise the Insert QAction with a track selection during playback at a different playhead: prove selection anchoring, untouched track/inactive tab, no form, retained span, cursor at start and one byte-restoring undo. Reuse existing no-selection prompt acceptance/cancellation coverage.
2. Exercise the Delete QAction with a scoped range: prove removal and later-event shift, untouched track/inactive tab, cleared selection, seam cursor and one undo. Add a bounded whole-song routing case proving previously excluded content participates; do not reproduce global event-type or seam matrices.
3. Exercise Delete with no selection and with the public invalid-active fixture specified in Task 2: no popup or document/undo/cursor/selection change. Do not duplicate Task 2's invalid Insert case.
4. In a dedicated native slot, invoke configured Insert and prove exactly one transaction; invoke ordinary Delete and prove contents clearing without a shift. Exercise Delete through its real Edit menu row and a temporarily rebound registry shortcut. Restore the binding and prove text/popup-local input remains local rather than invoking a time edit.

## Acceptance predicate

Window surfaces target the selected song exactly once, retain scoped and whole-song routing, distinguish clearing from ripple removal and preserve input ownership and undo. Named checks: `deno task verify --filter mainwindow-routing-input --filter mainwindow-routing-native --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risks: QAction activation alone cannot prove native shortcut ownership, and leaked keymap overrides can contaminate later cases. Binding restoration must survive early assertion exits. Do not enlarge the copy/solo native scenario or substitute QAction::trigger() for native proof. A discovered production-routing defect requires a separately bounded repair write set.
