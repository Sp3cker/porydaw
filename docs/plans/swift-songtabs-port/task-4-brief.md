# Task 4 — RewriteWindow wiring for tabs

## Context

The window shell adapts to the tabbed session: song opening no longer gates
on the current document's dirty state (tabs keep it alive), window close
iterates dirty tabs through the session, and the theme palette push targets
the session-owned palette once instead of the per-grid palette.

## Exact write set

- `src/app/RewriteWindow.cpp`
- `src/app/RewriteWindow.h`

## Prerequisites

- Task 2: `openSong(label:)` new-tab semantics, `requestCloseAll()` +
  `allTabsClosed`/`closeCancelled` signals, `ApplicationSession.palette`.

## Interface contract

- `chooseSong` → `invokeOpenSong(label)` — no `runAfterDirtyGate` on the
  outgoing document.
- `closeEvent`: if `session.tabCount == 0` → existing accept path. Otherwise
  call `requestCloseAll()` once, `event->ignore()`, and connect
  `allTabsClosed` → `close()` (reentrancy-guarded: a second closeEvent while
  close-all is in flight is ignored) and `closeCancelled` → nothing (window
  stays).
- `applyGridPalette` pushes to the session palette object
  (`m_session->property("palette")`), once at session creation and on theme
  change — not per-grid. Remove the `gridModel`→`palette` walk.
- `openStartup` unchanged in shape; `invokeOpenSong` signature drops the
  `discardChanges` argument to match Task 2.
- `songOpen`-gated actions (`m_saveAction`, undo/redo, transport) follow
  "any tab open" — the session's `songOpen` already means that.

## Implementation steps

1. Rewire `chooseSong`/`invokeOpenSong` to the new signature.
2. Replace `closeEvent`'s single-document dirty gate with the
   `requestCloseAll` handshake; keep `m_isClosing` semantics.
3. Move `applyGridPalette` to the session palette; call it after session
   creation and from the theme-change path.
4. `lsp references` on `runAfterDirtyGate`/`invokeOpenSong`/`documentDirty`
   before editing; remove `runAfterDirtyGate` if it becomes dead (check
   `chooseProject` — it may still gate project replace; keep it if so).

## Acceptance predicate

`deno task build:app` && `deno task verify --filter swiftrollgated --verbose`.
Covers: window mounts the overlay, session signals connect (the constructor's
`host-contract` warnings must not fire), open/save paths still invoke.

## Task-specific constraints

- Keep every `connectPropertyNotify`/`connectSessionSignal` contract line
  working; add `allTabsClosed`/`closeCancelled` connections the same way.
- No new C++ tab logic — the window stays a thin shell; all tab semantics
  live in the session.
