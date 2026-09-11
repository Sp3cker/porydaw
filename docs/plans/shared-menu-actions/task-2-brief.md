## 1. Context

Settings currently snapshots the keymap and tests a third Keyboard tab. The retained Settings contract concerns Engine/Song editing, unavailable Song fallback, apply signaling, and engine persistence.

## 2. Exact write set

- `src/checks/keyboard/tst_settingsdialog.h`
- `src/checks/keyboard/tst_settingsdialog.cpp`

## 3. Prerequisites

None beyond the plan entry conditions.

## 4. Interface contract

Remove `keyboardApplySurvivesCancel` and keymap snapshot fields/setup/teardown. `configuredSettingsRoundTrip`, `unavailableSongTabFallsBackToEngine`, and `engineMixerPersistsAndRejectsInvalidValue` continue to exercise their named behavior. Do not turn tab-count or display-wording assertions into a new implementation pin.

## 5. Implementation steps

1. Delete the Keyboard-only case, declarations, keymap fixture dependencies, and the Keyboard portion of the mixed round-trip case.
2. Delete assertions of the incidental tab count and widget-class presence; retain actual Engine/Song round-trip and disabled/unavailable Song behavior. Retain isolated engine-setting restoration.
3. Keep Apply behavior only where it observes actual settings/application semantics; remove assertions about button gaps and text-based button discovery that existed solely for the deleted keyboard case.

## 6. Acceptance predicate

Settings behavioral checks run without referring to `Tab::Keyboard` or mutable keymaps while still rejecting invalid engine settings and exercising the retained Song/Engine round-trip. Verify with `deno task verify --filter settings-dialog --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not change production Settings in this task or delete unrelated engine validation.
