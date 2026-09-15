# T09 — Retarget the existing host for the scene milestone

## Context

`SongTabQuickHost` currently takes the coordinator's owned window via
`takeWindowForEmbedding()`. For gate A the application must stay runnable while
scene ownership changes, so this existing per-song adapter is retargeted — not
replaced — to own its engine/window/viewport and attach the coordinator
explicitly per [spec.md](spec.md) S3. It is deleted entirely by task 22; no new
transitional module is created. Consumes task 1's `attachScene`/`detachScene`
contract.

## Exact write set

- `src/ui/songtabquickhost.h`
- `src/ui/songtabquickhost.cpp`

## Prerequisites

Task 1 — consumes its explicit attach/detach interface only.

## Interface contract

- The host creates and owns its own `QQmlEngine`/`QQuickView` (or equivalent
  window+viewport), keeps the existing module-generated type registration and
  qrc loading, attaches the coordinator via `attachScene`/`attachToPage`, and
  calls `detachScene()` before destroying engine/window.
- `QWidget *container() const noexcept` retains its signature so the unchanged
  QWidget `SongTab` keeps embedding it.
- The existing `embeddingFocusRequested` connection is retained verbatim until
  task 21 removes the signal.
- No new compatibility host, window-transfer alias, or dual constructor path in
  the coordinator.

## Implementation steps

1. Replace the `takeWindowForEmbedding` transfer with owned
   engine/window/viewport construction plus explicit `attachScene`.
2. Reorder teardown: `detachScene()` while the window is live, then destroy the
   container/window/engine.
3. Keep the container widget contract and focus-bridge connection unchanged.

## Acceptance predicate

Existing `SongTab` still renders and edits through the explicit attach API while
the coordinator owns no window; named checks `host-adapter` and `rollcheck` pass
under the gate-A run below. Local structural inspection is not a behavioral
pass.

## Task-specific constraints

- This adapter is deliberately retained for milestone A only; do not generalize
  it, add fallback paths, or migrate other callers — task 22 deletes it.
- No per-song page registry or selection policy here.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
