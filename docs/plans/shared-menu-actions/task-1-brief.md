## 1. Context

The Keyboard UI and mutation APIs will be deleted in tasks 4–7. Remove tests for the rejected remapping product before removing their API. Keep fixed input behavior coverage, not tests of copied QAction fields or settings-widget geometry.

## 2. Exact write set

- `src/checks/keyboard/tst_keymapcheck.h`
- `src/checks/keyboard/keymapregistry.cpp`
- `src/checks/keyboard/keyboardshortcuts.cpp`

## 3. Prerequisites

None beyond the plan entry conditions.

## 4. Interface contract

Keep `runKeymapCheck(const QStringList &qtArguments)` and the `keymapcheck` registry entry unchanged. Move its existing body from `keyboardshortcuts.cpp` to `keymapregistry.cpp`. Retain `defaultMatching_data/defaultMatching`, fixed modifier matching and isolated QSettings setup; remove remapping-only fixture state and UI helpers. Task 6 deletes the emptied old translation unit and its build entry.

## 5. Implementation steps

1. Remove override persistence, unbind/reset/snapshot, conflict-assignment, attached-action mutation, and Keyboard widget cases plus their declarations/helpers. Remove the incidental Preferences-default echo and table/field-copy assertions rather than re-pinning them.
2. Reduce modifier cases to observable fixed exact-chord behavior, including ignored keypad modifiers and rejection of an extra real modifier; remove cases that assign a chord. Remove override snapshot/reset fixture calls while retaining isolated settings storage.
3. Relocate the runner into `keymapregistry.cpp`; leave the old compiled file empty until its source-list retirement in task 6. Preserve all surviving matching assertions and Qt argument forwarding.

## 6. Acceptance predicate

The surviving keyboard harness still exercises positive/negative fixed-key and fixed-modifier matching without any Registry mutation call or remapping UI, and remains discoverable/runnable through the unchanged runner. Verify with `deno task verify --filter keymapcheck --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not implement immutable production lookup yet or add replacement tests that merely inspect API wiring. The temporary empty translation unit is an existing source awaiting explicit deletion, not a new compatibility layer.
