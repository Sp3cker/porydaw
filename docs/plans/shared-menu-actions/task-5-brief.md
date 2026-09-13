## 1. Context

The only production route requesting `Tab::Keyboard` has been removed. Settings can now own just Engine/Song values instead of keymap mutation/rollback.

## 2. Exact write set

- `src/ui/settingsdialog.h`
- `src/ui/settingsdialog.cpp`

## 3. Prerequisites

- [Task 2](task-2-brief.md).
- [Task 4](task-4-brief.md).

## 4. Interface contract

`SettingsDialog::Tab` has only Engine and Song. Delete the KeyboardShortcutsWidget member/construction and keymap dependency/snapshot. Preserve `applyRequested`, normal QDialog accept/reject, unavailable Song fallback and existing Engine/Song accessors. Remove the reject override if it no longer has behavior beyond QDialog.

## 5. Implementation steps

1. Remove the Keyboard enum value, widget include/member/tab and snapshot initialization.
2. Simplify currentTab/setCurrentTab to the two real tabs; preserve the fallback to Engine when Song is unavailable.
3. Remove keymap Apply/Cancel rollback code and redundant override; retain the existing settings apply signal and ordinary dialog behavior.

## 6. Acceptance predicate

The actual Settings dialog has only Engine/Song functionality, Apply/Cancel no longer reads or writes shortcut state, and unavailable Song selection still lands on Engine. Verify with `deno task verify --filter settings-dialog --verbose` and a visible Preferences/Apply/Cancel smoke after `deno task build:app`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not restyle the dialog, rewrite geometry, or alter Engine/Song transaction semantics.
