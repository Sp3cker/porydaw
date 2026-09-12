# Task 3: Expose Delete Time in Edit

## Context

Task 2 supplies Insert command policy. Task 4 consumes the new window action; Task 5 consumes the deletion registry ID.

## Exact write set

- `src/mainwindow.cpp`
- `src/mainwindow.h`
- `src/ui/keymap.cpp`

## Prerequisites

Task 2: public selection-aware `void SongView::insertTime()`.

## Interface contract

Add private `QAction *m_deleteTimeAction`, initially null; object name `deleteTimeWindowAction`, `Qt::WindowShortcut`, registry ID `edit.delete_time`. Register Global/Edit display name `Delete Time`, `QKeySequence::UnknownKey` and empty default shortcut. Activation calls the selected ready tab's `removeTimeSelectionContents()` once.

Reuse the existing Insert QAction construction/ownership pattern and `updateChrome()` in MainWindow, plus `keymap::Registry` in `src/ui/keymap.cpp` for binding storage and attachment. SongView's `removeTimeSelectionContents()` and SongDocument's `removeTimeRange()` remain the scope and mutation owners; the new action adds discoverability, not a second deletion implementation.

## Implementation steps

1. Register the unbound deletion command beside `edit.insert_time` and add the QAction member beside the existing insertion member.
2. Create `Delete &Time (Shift Left)` immediately after Insert in the existing Edit menu, with MainWindow ownership and the existing registry attachment pattern.
3. Apply tab-readiness enablement alongside Insert in `updateChrome()` and retain command-time rejection for absent or unresolved selection.
4. Set the existing Insert action caption to fixed `Insert &Time`; preserve its object name, registry ID and configured binding.

## Acceptance predicate

The Edit menu exposes the specified actions and scoped deletion has one undoable effect, or none without a selection; native smoke meets the plan verification policy. Named checks: `deno task verify --filter mainwindow-routing-input --filter mainwindow-routing-native --verbose`.

## Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Residual risks: a default-unbound command is still rebindable and may compete with local text/popup input; the ready-tab action can remain enabled without a selection. Preserve native input checks and command-time rejection. No dynamic caption connection, one-off status tip or persistent selection-dependent enablement state; use existing QObject ownership without capturing a raw SongTab.
