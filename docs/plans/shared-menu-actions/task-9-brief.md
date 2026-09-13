## 1. Context

Task 8 supplies the real semantic operations. This module supplies the actual QAction objects consumed by SongView binding in Task 10, MainWindow in Task 13, the automation fallback in Task 20 and Quick rows in Tasks 26–29.

## 2. Exact write set

- `src/ui/songview/editactions.h`
- `src/ui/songview/editactions.cpp`
- `CMakeLists.txt`

## 3. Prerequisites

- [Task 8](task-8-brief.md).

## 4. Interface contract

Implement the EditActions API and single-binding operation in spec.md with one enum-indexed action per currently implemented EditCommand. This set owns both Window- and Editor-scope song commands; scope is catalogue metadata, not a property of the owner. Initial/null target is disabled; destroyed-target refresh cannot be skipped when QPointer is already null. This task implements the forward guarded target and real callbacks; Task 10 adds the private SongView borrow inside that same rebind operation. Retain copyWindowAction, soloWindowAction, insertTimeWindowAction and deleteTimeWindowAction object names.

## 5. Implementation steps

1. Create real actions, installWindowShortcuts and editorCommandForKey from one enum-to-catalogue-ID association, including unbound commands. The installer registers only Window actions; the recognizer resolves only EditorRouted commands, independently of focus/enablement/target, and never activates. Connect semantics to triggered only and register the source in CMake. No second command map, function-valued dispatch table or placeholder cases.
2. Move Copy native QWidget text routing and Solo text protection into these canonical callbacks. Copy availability must preserve a supported live text-copy target even without musical selection; refresh that eligibility through existing focus-change notifications, without remembering a last-focused target. Keep gesture protection in semantic execution and restore check state from the model after a blocked toggle.
3. Observe current document/view/page and clipboard changes; disconnect old target observations on rebind. Cache clipboard eligibility, not payload, and read payload at execution. Follow the spec's two one-way signal flows: plain setChecked emits changed and toggled on a flip, never triggered; only triggered executes owned edits. No signal blocking or synchronization of borrowed View/transport toggles.

## 6. Acceptance predicate

The compiled action set executes existing semantic entries, retains guarded target lifetime and reports one coherent label/binding/availability source; existing command behavior remains intact. Named checks: `deno task verify --filter selectionkey --filter mainwindow-routing --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. Do not register Editor actions as WindowShortcut, create another Pencil action in AutomationPage, or poll playback frames. Task 10 completes the private reverse borrow without adding another public binding operation.
