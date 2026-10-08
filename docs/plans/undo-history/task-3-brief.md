# Context
App presenter and command for the Undo History dock. Read plan.md (Contract, Rulings R3,
R6, R8, R9, Global Constraints) and spec.md §5 first. Tasks 1 and 2 add the Core and
`DocumentSession.jump` APIs concurrently; code against the Contract.

# Exact write set
- src/swift/app/history/UndoHistoryPanel.swift (new: `UndoHistoryRow` + `UndoHistoryPanel`)
- src/swift/app/CMakeLists.txt (source list)
- src/swift/app/ApplicationSession.swift
- src/swift/app/ApplicationSession+Commands.swift
- src/swift/app/ApplicationSession+Tabs.swift
- src/swift/app/commands/KeybindingRegistry.swift
- src/swift/app/shell/ShellActionCatalog.swift
- src/swift/app/shell/ShellPresenter.swift
- src/swift/app/shell/ShellPresenter+ActionPolicy.swift
- any existing check that enumerates registry ids or View-menu actions and fails on a new
  id (update only that enumeration)

# Implementation steps
1. Rows and panel per Contract, modeled on `SongListPresenter`'s `QListModel` usage.
   Rows: newest step first, then the base row (`isBase`, label per R3, `isSaved` =
   `baseIsSaved`, `applied` true, `isCurrent` when `undoIndex == 0`). Row → target: step at
   offset `o` → `o + 1`; base → `0`.
2. `sync(history:visible:)`-style update (R9): no-op when hidden or when the history
   instance and `revision` are unchanged; otherwise diff the projection: mutate existing
   row objects for flag/label changes, `replaceSubrange` for inserted/removed rows. Empty
   when no song is open. Updates `currentRow`.
3. Wiring: `ApplicationSession` owns `public let undoHistory`. Call its sync from the
   selected tab's state-change path (`tabStateChanged(for:)` when the tab is selected; the
   workspace already forwards `.history`/`.dirty` domains), `tabsDidChange`, and when
   `ShellPresenter.undoHistoryVisible` turns on. Verify `markSaved` reaches it via
   `.dirty`; report if any revision-bumping mutation does not publish.
4. Jump request (R8): `ApplicationSession+Commands.swift` gains
   `requestHistoryJumpImpl(toIndex:)` mirroring `requestUndoImpl` (clear gates,
   `publishLastSaveError("")`, `onDocumentStateChanged?(false)`, Task awaiting
   `session.jump(toIndex:)` on the captured `DocumentSession`, errors via the same failure
   publication, then `refreshDocumentState()`), plus a private in-flight flag that makes
   `refreshDocumentState` publish `canUndo`/`canRedo` false and drives `canJump`.
   `canJump` is also false when any tab has a bank transition in flight (same rule as
   `refreshDocumentState`). `activate(row:)` maps row → target and calls it.
5. Command (R6): `view.undo_history` "Undo History", window scope, no default keys, in the
   View section after the Polyphony Debugger; `ShellPresenter` toggles
   `undoHistoryVisible` (then syncs the panel when shown); ActionPolicy: enabled when
   `session.songOpen` and under the same wav-export rule as `view.polyphony_debugger`;
   checkable, checked from `undoHistoryVisible`. No persisted visibility.
6. Inspect final declarations locally; no build/test/lint/formatter mid-flight.

# Acceptance predicate
The bridged names in plan.md exist exactly; menu undo/redo behavior is unchanged except
R8. Controller runs `deno task build:checks`, `deno task bridge:baseline` +
`deno task checks:bridge`, `deno task checks:shell`.

# Task-specific constraints
SHARED_TREE. Do not edit src/swift/core, src/swift/document, src/ui or src/checks/editorqml.
