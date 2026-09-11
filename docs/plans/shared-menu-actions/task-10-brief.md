## 1. Context

Task 9 owns real actions; this task makes a SongView their guarded active target without changing construction APIs. Tasks 11 and 13 provide composition roots; ruler/automation retirement consumers are Tasks 18, 20 and 21, and action-menu consumers are Tasks 26–29.

## 2. Exact write set

- `src/ui/songview.h`
- `src/ui/songview.cpp`
- `src/ui/songview/editactions.cpp`

## 3. Prerequisites

- [Task 9](task-9-brief.md).

## 4. Interface contract

Add read-only editActions() const and a private guarded borrow writable by friend songview::EditActions, plus selectionContextChanged(), contextMenusInvalidated(bool restoreFocus), and invalidateContextMenus(bool restoreFocus). EditActions::rebind is the sole binding mutation and owns the ordering in spec.md#single-binding-operation. Extend the existing application filter using spec.md#physical-activation-and-local-priority. The ruler/automation subscribers arrive in Tasks 18, 20 and 21; time/note subscribers in Tasks 26 and 27.

## 5. Implementation steps

1. Complete the single rebind operation with the private view borrow and early teardown call to rebind(nullptr), following the spec's pointer-clear/menu-retirement order. The destroyed-signal refresh is defensive, not the normal teardown path. No public view-side binding setter, default factory, constructor propagation or replacement ownership flag.
2. Emit menu invalidation before selection/context refresh at coordinateSelectionChange; notify action availability on primary/stored scope, note and time selection changes. Use document replacement and committed cursor seams without making setEditCursorTick drag updates seek. invalidateContextMenus emits contextMenusInvalidated; document changes and committed cursor changes publish the appropriate retirement without cancelling forms.
3. Implement the acceptance-only ShortcutOverride stage by calling the bound set's editorCommandForKey, then accepting and returning true on a match. No view-local binding/scope table or direct Registry match loop. Run regardless of menu-open state/platform/enablement; leave ordinary KeyPress, Window bindings and appearance handling unchanged.

## 6. Acceptance predicate

A bound view exposes the same guarded action set and selection/lifecycle observations without changing current local input behavior; no duplicate application filter is installed. Named checks: `deno task verify --filter selectionkey --filter host-seams --verbose`.

## 7. Task-specific constraints

[Global Constraints](plan.md#global-constraints) apply. The existing filter is installed at songview.cpp:325 and removed in the destructor. ShortcutOverride receivers are focus objects, not the application instance. Menu invalidation is separate from form cancellation.
