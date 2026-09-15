# T10 — Give checks explicit native scene ownership

## Context

Checks currently rely on the coordinator's per-song window. Per
[spec.md](spec.md) S8, a test-only `checks::QuickSceneHost` owns the
engine/window/page scope and borrows the view, using the S3 interface verbatim.
Produces the host consumed by task 11 (standalone-view fixture migration), task
12 (host behavioral assertions) and task 22 (final QObject `SongTab` fixtures).

## Exact write set

- `src/checks/support/quickscenehost.h` (new)
- `src/checks/support/quickscenehost.cpp` (new)

## Prerequisites

Tasks 1 and 8 — consume the S3 attach/detach interface and the S4 eligibility
gating only.

## Interface contract

Per spec S8, `checks::QuickSceneHost` exposes exactly:

- `static std::unique_ptr<QuickSceneHost> create(SongView &, const QSize &, QString &error)`
- `static std::unique_ptr<QuickSceneHost> create(SongTab &, const QSize &, QString &error)`
- `QQuickWindow *window() const`
- `QQuickItem *viewport() const`
- `QQmlEngine &engine() const`
- `void resizeViewport(const QSize &)`
- `bool show(QString &error)`

It owns the engine, window and a simple native page scope; it borrows the
view/tab and detaches before destroying the host. `create` requires an
unattached view. The `SongTab` overload mirrors `isReady` through the page's
enabled/focus state; the `SongView` overload is ready by definition. Fixture
declaration order must destroy the host before borrowed view/tab/document. No
auto-host-on-query, synthetic forwarding or global map; use Qt native scopes,
not a dispatcher.

## Implementation steps

1. Implement construction: engine + window + page scope, existing module
   registration/qrc loading, and error-bearing `create`/`show` paths returning
   diagnostics through `QString &error`.
2. Implement `resizeViewport` to size the page viewport (not the whole shared
   window) and the `SongTab` readiness mirroring.
3. Implement destruction ordering: `detachScene()` while the window is live,
   then engine/window teardown.

## Acceptance predicate

The same production attach interface renders real fixtures and destroys the
scene before borrowed data; named check `host-seams` passes under the gate-A run
below. Local structural inspection is not a behavioral pass.

## Task-specific constraints

- Test-only support code under `src/checks/support`; no new standalone
  executable or check catalog.
- The `SongTab` overload is used only after task 17 removes its host; do not
  wire it to `SongTabQuickHost`.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
