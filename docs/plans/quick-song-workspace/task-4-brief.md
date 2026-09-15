# T04 — Scope real popup lifetime and focus to its canvas

## Context

`QuickPopupSession` currently parents its layer to the window content item and
owns the swallowed-release button per session. Per [spec.md](spec.md) S5 the
real popup seam moves under each page's canvas FocusScope so popup lifetime,
geometry and focus are page-bounded. Produces the session/context API consumed
by task 1 (construction inside `attachScene`), task 6 (`qmlContext()` for panel
creation) and task 7 (popup state for playhead suppression); consumes task 5's
`QuickWindowInput` for release swallowing.

## Exact write set

- `src/ui/songview/quick/quickpopupsession.h`
- `src/ui/songview/quick/quickpopupsession.cpp`
- `src/ui/songview/quick/QuickPopupLayer.qml`

## Prerequisites

None — frozen spec only. Task 5's `QuickWindowInput::forWindow`/`swallowRelease`
is a frozen S5 contract this task consumes; both are written against the spec
within gate A.

## Interface contract

Per spec S5:

- Constructor becomes
  `QuickPopupSession(QQuickWindow &window, QQmlContext &context, QObject *parent = nullptr)`.
- Add `void setCanvasScope(QQuickItem &canvasScope)` — called exactly once per
  session after TimelineCanvas creation — and `QQmlContext *qmlContext() const`.
- Attachment order (driven by task 1, stated here as the contract this type must
  satisfy): context and popup session first, non-null `quickPopupSession`
  context property installed, then TimelineCanvas, then `setCanvasScope`, then
  interaction binding/publication. `ensureLayer()`/open entry points decline
  until `canvasScope` exists; no popup opens during canvas construction.
- The layer is visually parented to `canvasScope` — not `window.contentItem()`
  or a canvas sibling — fills/clips the page, and keeps QObject ownership in the
  session. All popup QML is constructed with the page context.
- `end(bool wasCancelled, bool restoreFocus)` clears live borrows and visually
  detaches retiring content/layer immediately but keeps their QObject parent as
  the session while `deleteLater` is pending; no retiring-object vector. Session
  destruction synchronously deletes remaining child QObjects before page-context
  teardown.
- Release swallowing delegates arm/clear to
  `QuickWindowInput::forWindow(window).swallowRelease(button)`; remove
  `m_swallowedReleaseButton` and the per-session ownership of that state.
- `QuickPopupLayer.qml` maps underlay press coordinates to scene before emitting
  `outsidePressed`; resize/form geometry and the underlay are page-bounded.

Preserved: cancellation signals, draft/revision validation, local Escape/dismiss
restoration, right-click retarget, note-off, and the existing local popup
focus-epoch checks — which must not restore focus on `cancel(false)` paths
(resize/readiness loss/switch/close cancel without forced focus).

## Implementation steps

1. Change the constructor signature and add `setCanvasScope`/`qmlContext`; store
   the page context and use it for all popup QML construction.
2. Reparent the layer under `canvasScope` with page fill/clip; gate
   `ensureLayer`/open on `canvasScope` presence.
3. Update `end()` and destruction to the S5 deferred-deletion ownership rule.
4. Replace `m_swallowedReleaseButton` handling with `QuickWindowInput`
   delegation and update `QuickPopupLayer.qml` underlay coordinate mapping.

## Acceptance predicate

A real form/page switch and owner destruction preserve survivor input and retire
QML before its context; named checks `host-integration` and `selectionkey` pass
under the gate-A run below. Local structural inspection is not a behavioral
pass.

## Task-specific constraints

- No new popup framework, scene-selection registry, or tab-focus cache.
- The tab bar stays outside the input shield: a pointer tab activation switches
  exactly once even with a form open.
- Remove this file's `quickengine.h` use; the header itself is deleted by
  task 6.

## Controller verification

[Gate A](plan.md#verification-and-checkpoint-semantics).
