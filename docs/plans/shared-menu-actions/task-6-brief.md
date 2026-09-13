## 1. Context

The remapping widget has no production consumers and its UI cases are gone. The keymap runner already lives in keymapregistry.cpp.

## 2. Exact write set

- `src/ui/keyboardshortcutsdialog.h`
- `src/ui/keyboardshortcutsdialog.cpp`
- `src/checks/keyboard/keyboardshortcuts.cpp`
- `CMakeLists.txt`

Mechanical exception: Delete three obsolete translation/header files and their exact source-list entries; no surviving behavior or APIs are redesigned.

## 3. Prerequisites

- [Task 1](task-1-brief.md).
- [Task 5](task-5-brief.md).

## 4. Interface contract

Remove the two KeyboardShortcutsWidget files and the empty old keyboard test source. Keep the existing `keymapregistry.cpp`/`tst_keymapcheck.h` check source entries and runner registration. No compatibility header or empty source file remains.

## 5. Implementation steps

1. Confirm the widget and removed test file have no remaining includes/calls using LSP references and scoped source-list search.
2. Delete the three obsolete files and their exact application/check source entries in CMakeLists.txt.

## 6. Acceptance predicate

Application and checks link without the deleted widget or empty test translation unit, and the keyboard/settings harnesses remain runnable. Verify with `deno task verify --filter keymapcheck --filter settings-dialog --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. The four-file mechanical exception is only these deletions/build-entry removals. Do not modify the test catalogue or unrelated CMake sources.
