## 1. Context

The selection-key harness has one rebind-and-press case and shared RAII wrappers for restoring settings. Fixed shortcuts remove the mutation contract, not the automation selection regression.

## 2. Exact write set

- `src/checks/selectionkey/primitives.h`
- `src/checks/selectionkey/core.cpp`
- `src/checks/selectionkey/coreediting.cpp`
- `src/checks/selectionkey/tst_selectionkeycore.h`
- `src/checks/selectionkey/gesture.cpp`
- `src/checks/selectionkey/gesturecheck.h`

Mechanical exception: Six-file, same-shape removal of the KeymapRestore type, members and construction/reset/destruction calls; the one rebind-and-press scenario substitutes its shipped Delete key without altering its semantic target/assertions.

## 3. Prerequisites

None beyond the plan entry conditions.

## 4. Interface contract

Delete `selectionkey::KeymapRestore` and every `m_keymap`/`mKeymapRestore` use in this exact set. In `coreediting.cpp`, deliver shipped unmodified Delete to the same shown automation surface instead of rebinding to Alt+Backspace. Preserve the selected lane/time scope, untouched neighbors, undo and exactly-once assertions.

## 5. Implementation steps

1. Use LSP references to confirm the declared RAII/member closure; remove the wrapper and fixture-only members/lifetime calls from all six files.
2. Replace the one override assignment plus Alt+Backspace delivery with the shipped Delete delivery, retaining the meaningful selection and document assertions and updating the diagnostic to describe that behavior.
3. Remove only now-unused includes/comments from these touched fixtures.

## 6. Acceptance predicate

All four selection-key suites retain their input/selection/gesture assertions and run without a mutable Registry fixture or test-only binding. Verify with `deno task verify --filter selectionkey --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. This is not permission to weaken the genuine automation Delete scenario or redesign its fixture/input delivery.
